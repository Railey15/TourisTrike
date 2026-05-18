import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

class ActivityTrackingScreen extends StatefulWidget {
  const ActivityTrackingScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<ActivityTrackingScreen> createState() =>
      _ActivityTrackingScreenState();
}

class _ActivityTrackingScreenState extends State<ActivityTrackingScreen> {
  static const _apiKey = CitySpotSuggestionService.defaultGoogleMapsApiKey;

  final _repo = TourisTrikeRepository();
  final _supabase = Supabase.instance.client;

  PackageActivity? _activity;
  PackageBooking? _booking;
  DriverInfo? _driverInfo;
  List<CustomizedPackageSpot> _spots = [];

  bool _loading = true;
  String? _error;

  RealtimeChannel? _channel;
  GoogleMapController? _mapCtrl;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  static const _defaultCenter = LatLng(14.9597, 120.9206);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final activity = await _repo.fetchActivityForBooking(widget.bookingId);
      final spots = await _repo.fetchBookingSpots(widget.bookingId);

      PackageBooking? booking;
      DriverInfo? driverInfo;
      if (activity?.bookingRow != null) {
        booking = PackageBooking(activity!.bookingRow!);
      }
      final driverId = booking?.assignedDriverId ?? activity?.driverId ?? '';
      if (driverId.isNotEmpty) {
        driverInfo = await _repo.fetchDriverInfo(driverId);
      }

      setState(() {
        _activity = activity;
        _booking = booking;
        _driverInfo = driverInfo;
        _spots = spots;
        _loading = false;
      });

      _buildMarkers();
      _fetchCurrentRoute();

      if (activity != null) {
        _subscribeToActivity(activity.id);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Realtime subscription ────────────────────────────────────
  void _subscribeToActivity(String activityId) {
    _channel?.unsubscribe();
    _channel = _supabase
        .channel('tracking:$activityId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'package_activities',
          filter: PostgresChangeFilter(
            column: 'id',
            type: PostgresChangeFilterType.eq,
            value: activityId,
          ),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  // ── Markers ──────────────────────────────────────────────────
  void _buildMarkers() {
    final markers = <Marker>{};
    final booking = _booking;

    // Pickup marker
    if (booking != null &&
        booking.pickupLatitude != null &&
        booking.pickupLongitude != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(booking.pickupLatitude!, booking.pickupLongitude!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: 'Pickup Point',
            snippet: booking.pickupAddress,
          ),
        ),
      );
    }

    // Drop-off marker
    if (booking != null &&
        booking.dropoffLatitude != null &&
        booking.dropoffLongitude != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(booking.dropoffLatitude!, booking.dropoffLongitude!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'Drop-off Point',
            snippet: booking.dropoffAddress,
          ),
        ),
      );
    }

    final currentSpotIndex = _activity?.currentSpotIndex ?? 0;

    // Spot markers
    for (var i = 0; i < _spots.length; i++) {
      final spot = _spots[i];
      if (spot.latitude == 0 && spot.longitude == 0) continue;
      final isCompleted = i < currentSpotIndex;
      final isCurrent = i == currentSpotIndex;
      markers.add(
        Marker(
          markerId: MarkerId('spot_$i'),
          position: LatLng(spot.latitude, spot.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isCompleted
                ? BitmapDescriptor.hueGreen
                : isCurrent
                ? BitmapDescriptor.hueOrange
                : BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: 'Stop ${i + 1}: ${spot.spotTitle}',
            snippet: spot.spotAddress,
          ),
        ),
      );
    }

    // Driver marker (live)
    final activity = _activity;
    if (activity != null &&
        activity.driverLatitude != null &&
        activity.driverLongitude != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(activity.driverLatitude!, activity.driverLongitude!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: const InfoWindow(title: 'Your Driver'),
        ),
      );
    }

    setState(() => _markers = markers);
  }

  // ── Route / polyline ─────────────────────────────────────────
  Future<void> _fetchCurrentRoute() async {
    final activity = _activity;
    final booking = _booking;
    if (activity == null || booking == null) return;

    LatLng? origin;
    LatLng? destination;
    final ts = activity.tourStatus;

    if (ts == 'driver_accepted' || ts == 'driver_en_route') {
      // Driver going to pickup
      if (activity.driverLatitude != null && booking.pickupLatitude != null) {
        origin = LatLng(activity.driverLatitude!, activity.driverLongitude!);
        destination =
            LatLng(booking.pickupLatitude!, booking.pickupLongitude!);
      }
    } else if (ts == 'driver_arrived') {
      if (activity.driverLatitude != null && booking.pickupLatitude != null) {
        origin = LatLng(activity.driverLatitude!, activity.driverLongitude!);
        destination =
            LatLng(booking.pickupLatitude!, booking.pickupLongitude!);
      }
    } else if (ts == 'picked_up' || ts == 'en_route_to_spot') {
      // Going to the current spot
      final idx = activity.currentSpotIndex;
      if (idx < _spots.length) {
        if (activity.driverLatitude != null) {
          origin =
              LatLng(activity.driverLatitude!, activity.driverLongitude!);
        } else if (booking.pickupLatitude != null) {
          origin =
              LatLng(booking.pickupLatitude!, booking.pickupLongitude!);
        }
        destination = LatLng(_spots[idx].latitude, _spots[idx].longitude);
      }
    } else if (ts == 'at_spot') {
      final idx = activity.currentSpotIndex;
      if (idx < _spots.length && activity.driverLatitude != null) {
        origin = LatLng(activity.driverLatitude!, activity.driverLongitude!);
        destination = LatLng(_spots[idx].latitude, _spots[idx].longitude);
      }
    } else if (ts == 'en_route_to_dropoff') {
      // Going to drop-off
      if (booking.dropoffLatitude != null) {
        if (activity.driverLatitude != null) {
          origin =
              LatLng(activity.driverLatitude!, activity.driverLongitude!);
        } else if (_spots.isNotEmpty) {
          final last = _spots.last;
          origin = LatLng(last.latitude, last.longitude);
        }
        destination =
            LatLng(booking.dropoffLatitude!, booking.dropoffLongitude!);
      }
    }

    if (origin == null || destination == null) {
      setState(() => _polylines = {});
      return;
    }

    final points = await _fetchRoute(origin, destination);
    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: const Color(0xFF2A86FF),
          width: 5,
        ),
      };
    });
  }

  Future<List<LatLng>> _fetchRoute(LatLng origin, LatLng dest) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${dest.latitude},${dest.longitude}'
        '&key=$_apiKey',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = (body['routes'] as List?) ?? const [];
        if (routes.isNotEmpty) {
          final encoded =
              routes.first['overview_polyline']?['points'] as String?;
          if (encoded != null) return _decodePolyline(encoded);
        }
      }
    } catch (_) {}
    return [origin, dest];
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    final len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dLat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dLng;
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  void _animateCameraToRelevant() {
    final activity = _activity;
    final booking = _booking;
    if (_mapCtrl == null) return;
    if (activity?.driverLatitude != null) {
      _mapCtrl!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(activity!.driverLatitude!, activity.driverLongitude!),
          14,
        ),
      );
    } else if (booking?.pickupLatitude != null) {
      _mapCtrl!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(booking!.pickupLatitude!, booking.pickupLongitude!),
          14,
        ),
      );
    }
  }

  LatLng get _initialCenter {
    if (_booking?.pickupLatitude != null) {
      return LatLng(_booking!.pickupLatitude!, _booking!.pickupLongitude!);
    }
    return _defaultCenter;
  }

  // ── Status helpers ───────────────────────────────────────────
  static const _statusInfo = {
    'waiting_driver': (
      'Waiting for Driver',
      'Your booking is waiting for a driver to accept.',
      Color(0xFFF59E0B),
      Icons.hourglass_empty_rounded,
    ),
    'driver_accepted': (
      'Driver Accepted',
      'A driver has accepted your booking and will be on the way soon.',
      Color(0xFF2A86FF),
      Icons.check_circle_rounded,
    ),
    'driver_en_route': (
      'Driver On the Way',
      'Your driver is heading to your pickup point.',
      Color(0xFF2A86FF),
      Icons.directions_car_rounded,
    ),
    'driver_arrived': (
      'Driver Arrived',
      'Your driver has arrived at the pickup point.',
      Color(0xFF7C3AED),
      Icons.location_on_rounded,
    ),
    'picked_up': (
      'Tour Started!',
      'You have been picked up. Enjoy your tour!',
      Color(0xFF16A34A),
      Icons.tour_rounded,
    ),
    'en_route_to_spot': (
      'Heading to Next Stop',
      'Your driver is heading to the next spot on your tour.',
      Color(0xFF0EA5E9),
      Icons.navigation_rounded,
    ),
    'at_spot': (
      'At Tour Spot',
      'You have arrived at a tour destination. Enjoy!',
      Color(0xFF16A34A),
      Icons.place_rounded,
    ),
    'en_route_to_dropoff': (
      'Heading to Drop-off',
      'All spots completed! Your driver is taking you to your drop-off point.',
      Color(0xFF2A86FF),
      Icons.home_rounded,
    ),
    'dropped_off': (
      'Dropped Off',
      'You have been dropped off. Thank you for touring with TourisTrike!',
      Color(0xFF16A34A),
      Icons.check_circle_outline_rounded,
    ),
    'completed': (
      'Tour Completed',
      'Your tour has been completed. We hope you had a great time!',
      Color(0xFF16A34A),
      Icons.star_rounded,
    ),
  };

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF2A86FF)),
              )
            : _error != null
                ? _ErrorView(
                    message: _error!,
                    onRetry: _load,
                  )
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final activity = _activity;
    final booking = _booking;
    final bottom = MediaQuery.of(context).padding.bottom;
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);

    final tourStatus = activity?.tourStatus ?? 'waiting_driver';
    final statusData = _statusInfo[tourStatus] ??
        (
          tourStatus.replaceAll('_', ' ').toUpperCase(),
          '',
          const Color(0xFF64748B),
          Icons.info_rounded,
        );
    final (statusLabel, statusDesc, statusColor, statusIcon) = statusData;

    // Booking details from bookingRow
    final bookingType =
        dbString(booking?.row['booking_type'], fallback: 'advanced');
    final travelDate = booking?.travelDate;
    final adults = booking?.row['adults'] is int
        ? booking!.row['adults'] as int
        : 0;
    final children = booking?.row['children'] is int
        ? booking!.row['children'] as int
        : 0;
    final totalAmount = booking?.totalAmount ?? 0.0;
    final driverName = _driverInfo?.name ?? '';
    final driverPhone = _driverInfo?.phoneNumber ?? '';
    final vehicleDetails = _driverInfo?.vehicleDetails ?? '';

    return Column(
      children: [
        // ── Header ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _CircleBtn(
                icon: Icons.arrow_back_rounded,
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Tour Tracking',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _CircleBtn(
                icon: Icons.refresh_rounded,
                onTap: _load,
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 24 + bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Live Status Card ──────────────────────────
                _StatusCard(
                  icon: statusIcon,
                  label: statusLabel,
                  description: statusDesc,
                  color: statusColor,
                ),
                const SizedBox(height: 16),

                // ── Map ───────────────────────────────────────
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 280,
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _initialCenter,
                        zoom: 13,
                      ),
                      markers: _markers,
                      polylines: _polylines,
                      onMapCreated: (ctrl) {
                        _mapCtrl = ctrl;
                        _animateCameraToRelevant();
                      },
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Driver Info ───────────────────────────────
                if (driverName.isNotEmpty) ...[
                  _SectionLabel('Your Driver'),
                  const SizedBox(height: 8),
                  _InfoCard(
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF2FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF2A86FF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                driverName,
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              if (driverPhone.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  driverPhone,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              if (vehicleDetails.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  vehicleDetails,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.electric_rickshaw_rounded,
                          color: Color(0xFF2A86FF),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Booking Details ───────────────────────────
                _SectionLabel('Booking Details'),
                const SizedBox(height: 8),
                _InfoCard(
                  child: Column(
                    children: [
                      _DetailRow(
                        label: 'Date',
                        value: travelDate != null
                            ? DateFormat('EEE, MMM d, yyyy').format(travelDate)
                            : '—',
                      ),
                      const SizedBox(height: 8),
                      _DetailRow(
                        label: 'Booking Type',
                        value: bookingType == 'same_day'
                            ? 'Same-day'
                            : 'Advanced',
                      ),
                      const SizedBox(height: 8),
                      _DetailRow(
                        label: 'Participants',
                        value: '$adults adult${adults != 1 ? 's' : ''}'
                            '${children > 0 ? ', $children child${children != 1 ? 'ren' : ''}' : ''}',
                      ),
                      const SizedBox(height: 8),
                      _DetailRow(
                        label: 'Total Amount',
                        value: money.format(totalAmount),
                        bold: true,
                      ),
                      if (driverName.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _DetailRow(label: 'Driver Name', value: driverName),
                      ],
                      if (driverPhone.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _DetailRow(label: 'Driver Phone', value: driverPhone),
                      ],
                      if (vehicleDetails.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: 'Vehicle',
                          value: vehicleDetails,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Pickup & Drop-off ─────────────────────────
                if (booking != null) ...[
                  _SectionLabel('Locations'),
                  const SizedBox(height: 8),
                  _InfoCard(
                    child: Column(
                      children: [
                        _LocationRow(
                          icon: Icons.trip_origin_rounded,
                          iconColor: const Color(0xFF16A34A),
                          label: 'Pickup',
                          address: booking.pickupAddress.isNotEmpty
                              ? booking.pickupAddress
                              : '—',
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1, color: Color(0xFFE7EEF7)),
                        ),
                        _LocationRow(
                          icon: Icons.location_on_rounded,
                          iconColor: const Color(0xFFDC2626),
                          label: 'Drop-off',
                          address: booking.dropoffAddress.isNotEmpty
                              ? booking.dropoffAddress
                              : '—',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Tour Spots ────────────────────────────────
                if (_spots.isNotEmpty) ...[
                  _SectionLabel('Tour Stops (${_spots.length})'),
                  const SizedBox(height: 8),
                  _InfoCard(
                    child: Column(
                      children: _spots.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final spot = entry.value;
                        final isCurrent = activity != null &&
                            activity.currentSpotIndex == idx &&
                            (activity.tourStatus == 'picked_up' ||
                                activity.tourStatus == 'en_route_to_spot' ||
                                activity.tourStatus == 'at_spot');
                        final isDone = activity != null &&
                            idx < activity.currentSpotIndex;
                        return _SpotRow(
                          index: idx + 1,
                          title: spot.spotTitle,
                          isCurrent: isCurrent,
                          isDone: isDone,
                          isLast: idx == _spots.length - 1,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: const Color(0xFF0F172A),
            fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
            fontSize: bold ? 15 : 13.5,
          ),
        ),
      ],
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.address,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpotRow extends StatelessWidget {
  const _SpotRow({
    required this.index,
    required this.title,
    required this.isCurrent,
    required this.isDone,
    required this.isLast,
  });

  final int index;
  final String title;
  final bool isCurrent;
  final bool isDone;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = isDone
        ? const Color(0xFF16A34A)
        : isCurrent
            ? const Color(0xFF2A86FF)
            : const Color(0xFFCBD5E1);

    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.5),
              ),
              child: Center(
                child: isDone
                    ? Icon(Icons.check_rounded, size: 14, color: color)
                    : Text(
                        '$index',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isDone
                      ? const Color(0xFF94A3B8)
                      : isCurrent
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF64748B),
                  fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 13.5,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (isCurrent)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'CURRENT',
                  style: TextStyle(
                    color: Color(0xFF2A86FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
        if (!isLast) ...[
          Padding(
            padding: const EdgeInsets.only(left: 13),
            child: Container(
              width: 2,
              height: 18,
              color: const Color(0xFFE7EEF7),
            ),
          ),
        ],
      ],
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: const Color(0xFF0F172A), size: 22),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFDC2626),
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
