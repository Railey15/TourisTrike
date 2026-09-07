import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/emergency_photo.dart';

class EmergencyAlertResult {
  const EmergencyAlertResult({
    required this.alertId,
    this.mapsLink,
    required this.triggeredAt,
    this.emailSent = false,
  });

  final String alertId;
  final String? mapsLink;
  final DateTime triggeredAt;
  final bool emailSent;
}

class EmergencyService {
  const EmergencyService(this._supabase);

  final SupabaseClient _supabase;

  // Reused for retries of one form submission, using the existing UUID PK.
  static String newAlertId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<EmergencyAlertResult> triggerAlert({
    required String touristId,
    required String bookingId,
    String? activityId,
    String? driverId,
    required String tripStatus,
    String? currentSpotName,
    String? touristName,
    String? driverName,
    String? note,
    String? alertId,
    EmergencyPhoto? photo,
    Position? knownPosition,
  }) async {
    // 1. Get GPS — best-effort with 8s timeout
    double? lat, lng;
    if (knownPosition != null &&
        knownPosition.latitude.isFinite &&
        knownPosition.longitude.isFinite) {
      lat = knownPosition.latitude;
      lng = knownPosition.longitude;
    }
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {}

    final mapsLink = (lat != null && lng != null)
        ? 'https://maps.google.com/?q=$lat,$lng'
        : null;

    final trimmedNote = note?.trim().isEmpty == true ? null : note?.trim();

    // 2. Save alert to Supabase
    final requestedId = alertId ?? newAlertId();
    Map<String, dynamic> alertRow;
    var newlyCreated = true;
    try {
      alertRow = await _supabase
          .from('emergency_alerts')
          .insert({
            'id': requestedId,
            'tourist_id': touristId,
            'booking_id': bookingId.isEmpty ? null : bookingId,
            'activity_id': activityId,
            'driver_id': driverId?.isEmpty == true ? null : driverId,
            'trip_status': tripStatus,
            'current_spot_name': currentSpotName,
            'latitude': lat,
            'longitude': lng,
            'maps_link': mapsLink,
            'tourist_note': trimmedNote,
            'alert_status': 'active',
          })
          .select()
          .single();
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
      // A double request or an insert whose response was lost uses the same row.
      alertRow = await _supabase
          .from('emergency_alerts')
          .select()
          .eq('id', requestedId)
          .eq('tourist_id', touristId)
          .single();
      newlyCreated = false;
    }

    final savedAlertId = alertRow['id'] as String;

    // 3. In-app notification for every accepted driver in the convoy.
    // Falls back to the single legacy driverId for non-package / solo rides.
    if (newlyCreated) {
      try {
        final driverIds = <String>{};

        if (bookingId.isNotEmpty) {
          final convoyRows = await _supabase
              .from('booking_drivers')
              .select('driver_id')
              .eq('booking_id', bookingId)
              .eq('status', 'accepted');

          for (final row in convoyRows as List) {
            final id = (row as Map)['driver_id']?.toString();

            if (id != null && id.isNotEmpty) {
              driverIds.add(id);
            }
          }
        }

        if (driverId != null && driverId.isNotEmpty) {
          driverIds.add(driverId);
        }

        if (driverIds.isNotEmpty) {
          await _supabase.from('notifications').insert([
            for (final id in driverIds)
              {
                'user_id': id,
                'title': '🚨 Emergency Alert',
                'body':
                    '${touristName?.isNotEmpty == true ? touristName : 'Your tourist'} '
                    'has triggered an emergency alert during the tour!'
                    '${mapsLink != null ? '\n📍 Location: $mapsLink' : ''}',
                'type': 'emergency',
              },
          ]);
        }
      } catch (_) {}
    }

    // 4. In-app notifications for subtenant admins
    if (newlyCreated) {
      try {
        final subtenants = await _supabase
            .from('profiles')
            .select('id')
            .inFilter('role', ['admin', 'subtenant']);

        final notifRows = <Map<String, dynamic>>[];
        for (final s in subtenants as List) {
          final uid = s['id'] as String?;
          if (uid == null || uid == touristId) continue;
          notifRows.add({
            'user_id': uid,
            'title': '🚨 Emergency Alert',
            'body':
                '${touristName?.isNotEmpty == true ? touristName : 'A tourist'} '
                'triggered an emergency during a tour.'
                '${bookingId.isNotEmpty ? '\nBooking: $bookingId' : ''}'
                '${mapsLink != null ? '\n📍 $mapsLink' : ''}',
            'type': 'emergency',
          });
        }
        if (notifRows.isNotEmpty) {
          await _supabase.from('notifications').insert(notifRows);
        }
      } catch (_) {}
    }

    // 5. Email/attachment failure must not undo the saved database alert.
    bool emailSent = false;
    try {
      final resp = await _supabase.functions.invoke(
        'send-emergency-email',
        body: {
          'alert_id': savedAlertId,
          if (photo != null) 'photo': photo.toJson(),
        },
      );
      final data = resp.data;
      emailSent =
          resp.status >= 200 &&
          resp.status < 300 &&
          data is Map &&
          data['email_sent'] == true;
    } catch (_) {
      debugPrint('[Emergency] Email request failed; database alert retained.');
    }

    return EmergencyAlertResult(
      alertId: savedAlertId,
      mapsLink: alertRow['maps_link'] as String?,
      triggeredAt:
          DateTime.tryParse(alertRow['created_at']?.toString() ?? '') ??
          DateTime.now(),
      emailSent: emailSent,
    );
  }
}
