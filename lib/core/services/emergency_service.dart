import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  }) async {
    // 1. Get GPS — best-effort with 8s timeout
    double? lat, lng;
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
    final alertRow = await _supabase
        .from('emergency_alerts')
        .insert({
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

    final alertId = alertRow['id'] as String;

    // 3. In-app notification for every accepted driver in the convoy.
    // Falls back to the single legacy driverId for non-package / solo rides.
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

    // 4. In-app notifications for subtenant admins
    try {
      final subtenants = await _supabase.from('profiles').select('id').inFilter(
        'role',
        ['admin', 'subtenant'],
      );

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

    // 5. Call edge function for email — best-effort, does not block
    bool emailSent = false;
    try {
      final resp = await _supabase.functions.invoke(
        'send-emergency-email',
        body: {'alert_id': alertId},
      );
      emailSent = resp.status >= 200 && resp.status < 300;
    } catch (_) {}

    return EmergencyAlertResult(
      alertId: alertId,
      mapsLink: mapsLink,
      triggeredAt: DateTime.now(),
      emailSent: emailSent,
    );
  }
}
