import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

class DriverPackageTrackingScreen extends StatefulWidget {
  const DriverPackageTrackingScreen({super.key, required this.activityId});

  final String activityId;

  @override
  State<DriverPackageTrackingScreen> createState() =>
      _DriverPackageTrackingScreenState();
}

class _DriverPackageTrackingScreenState
    extends State<DriverPackageTrackingScreen> {
  static const _apiKey = CitySpotSuggestionService.defaultGoogleMapsApiKey;
  static const _defaultCenter = LatLng(14.9597, 120.9206);

  final _repo = TourisTrikeRepository();
  final _supabase = Supabase.instance.client;

  PackageActivity? _activity;
  PackageBooking? _booking;
  List<BookingItineraryItem> _spots = [];

  bool _loading = true;
  String? _error;
  bool _actionBusy = false;

  RealtimeChannel? _channel;
  StreamSubscription<Position>? _gpsSub;
  GoogleMapController? _mapCtrl;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _gpsSub?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final act = await _repo.fetchPackageActivityById(widget.activityId);
      if (act == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Activity not found.';
          _loading = false;
        });
        return;
      }
      final spots = await _repo.fetchBookingItinerary(act.bookingId);
      PackageBooking? booking;
      if (act.bookingRow != null) booking = PackageBooking(act.bookingRow!);

      if (!mounted) return;
      setState(() {
        _activity = act;
        _booking = booking;
        _spots = spots;
        _loading = false;
      });

      _buildMarkers();
      _fetchCurrentRoute();
      _subscribeRealtime();
      _startGpsStreaming();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('driver-tracking:${widget.activityId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'package_activities',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.activityId,
          ),
          callback: (payload) {
            final newRow = payload.newRecord;
            if (!mounted || newRow.isEmpty) return;
            final updated = PackageActivity(Map<String, dynamic>.from(newRow));
            setState(() => _activity = updated);
            _buildMarkers();
            _fetchCurrentRoute();
          },
        );
    _channel!.subscribe();
  }

  Future<void> _startGpsStreaming() async {
    final ok = await _checkLocationPermission();
    if (!ok) return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) async {
        if (_activity == null) return;
        try {
          await _repo.updateDriverLocation(
            activityId: widget.activityId,
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
          if (mounted) {
            setState(() {
              _activity = PackageActivity({
                ..._activity!.row,
                'driver_latitude': pos.latitude,
                'driver_longitude': pos.longitude,
                'driver_last_seen': DateTime.now().toIso8601String(),
              });
            });
            _buildMarkers();
            _animateToDriver(LatLng(pos.latitude, pos.longitude));
          }
        } catch (_) {}
      },
    );
  }

  Future<bool> _checkLocationPermission() async {
    final svc = await Geolocator.isLocationServiceEnabled();
    if (!svc) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm != LocationPermission.denied &&
        perm != LocationPermission.deniedForever;
  }

  // ── Map ───────────────────────────────────────────────────────

  void _buildMarkers() {
    if (_activity == null) return;

    final markers = <Marker>{};

    final pickup = _pickupLatLng();
    final dropoff = _dropoffLatLng();
    final driverPos = _driverLatLng();

    if (pickup != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: pickup,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Pickup',
          snippet: _booking?.pickupAddress ?? '',
        ),
      ));
    }
    if (dropoff != null) {
      markers.add(Marker(
        markerId: const MarkerId('dropoff'),
        position: dropoff,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Drop-off',
          snippet: _booking?.dropoffAddress ?? '',
        ),
      ));
    }

    for (var i = 0; i < _spots.length; i++) {
      final lat = _spots[i].latitude;
      final lng = _spots[i].longitude;
      if (lat == 0 && lng == 0) continue;
      final isDone = i < (_activity?.currentSpotIndex ?? 0);
      markers.add(Marker(
        markerId: MarkerId('spot_$i'),
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isDone ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueAzure,
        ),
        infoWindow: InfoWindow(
          title: 'Stop ${i + 1}: ${_spots[i].destinationName}',
        ),
      ));
    }

    if (driverPos != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: driverPos,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueOrange,
        ),
        infoWindow: const InfoWindow(title: 'You (Driver)'),
      ));
    }

    setState(() => _markers = markers);
  }

  Future<void> _fetchCurrentRoute() async {
    if (_activity == null) return;

    final status = _activity!.tourStatus;
    final driverPos = _driverLatLng();
    final pickupPos = _pickupLatLng();
    final dropoffPos = _dropoffLatLng();

    LatLng? origin;
    LatLng? destination;

    if (status == 'driver_accepted' || status == 'driver_en_route') {
      origin = driverPos;
      destination = pickupPos;
    } else if (status == 'driver_arrived' || status == 'picked_up') {
      origin = pickupPos;
      destination = _spots.isNotEmpty ? _currentSpotLatLng() : dropoffPos;
    } else if (status == 'en_route_to_spot' || status == 'at_spot') {
      origin = driverPos;
      destination = _currentSpotLatLng();
    } else if (status == 'en_route_to_dropoff') {
      origin = driverPos;
      destination = dropoffPos;
    } else {
      setState(() => _polylines = {});
      return;
    }

    if (origin == null || destination == null) {
      setState(() => _polylines = {});
      return;
    }

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&mode=driving'
        '&key=$_apiKey',
      );
      final res = await http.get(url);
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return;
      final legs = (routes.first as Map)['legs'] as List?;
      if (legs == null || legs.isEmpty) return;
      final steps = (legs.first as Map)['steps'] as List?;
      if (steps == null) return;

      final points = <LatLng>[];
      for (final step in steps) {
        final encoded = (step as Map)['polyline']?['points'] as String?;
        if (encoded != null) points.addAll(_decodePolyline(encoded));
      }

      if (!mounted) return;
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: points,
            color: const Color(0xFF2F6FFF),
            width: 5,
          ),
        };
      });
    } catch (_) {}
  }

  List<LatLng> _decodePolyline(String encoded) {
    final result = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int b;
      int shift = 0;
      int result0 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result0 |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result0 & 1) != 0 ? ~(result0 >> 1) : (result0 >> 1);

      shift = 0;
      result0 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result0 |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result0 & 1) != 0 ? ~(result0 >> 1) : (result0 >> 1);

      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }

  LatLng? _driverLatLng() {
    final lat = _activity?.driverLatitude;
    final lng = _activity?.driverLongitude;
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  LatLng? _pickupLatLng() {
    final lat = _booking?.pickupLatitude;
    final lng = _booking?.pickupLongitude;
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  LatLng? _dropoffLatLng() {
    final lat = _booking?.dropoffLatitude;
    final lng = _booking?.dropoffLongitude;
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  LatLng? _currentSpotLatLng() {
    final idx = _activity?.currentSpotIndex ?? 0;
    if (_spots.isEmpty || idx >= _spots.length) return null;
    final s = _spots[idx];
    if (s.latitude == 0 && s.longitude == 0) return null;
    return LatLng(s.latitude, s.longitude);
  }

  void _animateToDriver(LatLng pos) {
    _mapCtrl?.animateCamera(CameraUpdate.newLatLng(pos));
  }

  // ── Actions ───────────────────────────────────────────────────

  Future<void> _doAction(Future<void> Function() action) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _markEnRoute() => _doAction(() async {
        await _repo.updateActivityTourStatus(
          activityId: widget.activityId,
          tourStatus: 'driver_en_route',
        );
        _showSnack('Status: En route to pickup.');
      });

  Future<void> _markArrived() => _doAction(() async {
        await _repo.updateActivityTourStatus(
          activityId: widget.activityId,
          tourStatus: 'driver_arrived',
          extra: {'arrived_at': DateTime.now().toIso8601String()},
        );
        _showSnack('Status: Arrived at pickup.');
      });

  Future<void> _markPickedUp() => _doAction(() async {
        await _repo.updateActivityTourStatus(
          activityId: widget.activityId,
          tourStatus: 'picked_up',
          extra: {'picked_up_at': DateTime.now().toIso8601String()},
        );
        _showSnack('Status: Tourist picked up.');
      });

  Future<void> _markEnRouteToSpot() => _doAction(() async {
        await _repo.updateActivityTourStatus(
          activityId: widget.activityId,
          tourStatus: 'en_route_to_spot',
        );
        _showSnack('Status: En route to next spot.');
      });

  Future<void> _markAtSpot() => _doAction(() async {
        await _repo.updateActivityTourStatus(
          activityId: widget.activityId,
          tourStatus: 'at_spot',
        );
        _showSnack('Status: Arrived at spot.');
      });

  Future<void> _markSpotComplete() => _doAction(() async {
        final current = _activity?.currentSpotIndex ?? 0;
        final next = current + 1;
        final allDone = next >= _spots.length;

        if (allDone) {
          await _repo.updateActivityTourStatus(
            activityId: widget.activityId,
            tourStatus: 'en_route_to_dropoff',
            currentSpotIndex: next,
          );
          _showSnack('All spots done. Heading to drop-off.');
        } else {
          await _repo.updateActivityTourStatus(
            activityId: widget.activityId,
            tourStatus: 'en_route_to_spot',
            currentSpotIndex: next,
          );
          _showSnack('Spot complete. Moving to next spot.');
        }
      });

  Future<void> _markDroppedOff() => _doAction(() async {
        final booking = _booking;
        final isAdvanced = (booking?.bookingType ?? 'same_day') == 'advanced';
        final remainingBalance = booking?.remainingBalance ?? 0.0;

        if (isAdvanced && remainingBalance > 0) {
          final confirmed = await _showCashConfirmDialog(remainingBalance);
          if (confirmed != true) return;
        }

        await _repo.completePackageActivity(
          widget.activityId,
          remainingPaymentMethod:
              isAdvanced && remainingBalance > 0 ? 'cash' : '',
        );
        _showSnack('Tour completed! Great job.');
      });

  Future<bool?> _showCashConfirmDialog(double amount) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Confirm Remaining Balance',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This is an advanced booking with a remaining balance due:',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            Text(
              'PHP ${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Confirm that the tourist has paid the remaining balance before completing the tour.',
              style: TextStyle(color: Color(0xFF64748B), height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Payment Confirmed'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            const Text(
              'Failed to load activity',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final activity = _activity!;
    final status = activity.tourStatus;
    final isCompleted = status == 'completed' || status == 'dropped_off';

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          backgroundColor: const Color(0xFF2F6FFF),
          foregroundColor: Colors.white,
          title: const Text(
            'Tour Navigation',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: ClipRect(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _driverLatLng() ?? _pickupLatLng() ?? _defaultCenter,
                  zoom: 14.5,
                ),
                markers: _markers,
                polylines: _polylines,
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: false,
                mapToolbarEnabled: false,
                onMapCreated: (ctrl) => _mapCtrl = ctrl,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _StatusCard(status: status),
              const SizedBox(height: 14),
              if (!isCompleted) ...[
                _ActionButtons(
                  status: status,
                  spots: _spots,
                  currentSpotIndex: activity.currentSpotIndex,
                  actionBusy: _actionBusy,
                  onMarkEnRoute: _markEnRoute,
                  onMarkArrived: _markArrived,
                  onMarkPickedUp: _markPickedUp,
                  onMarkEnRouteToSpot: _markEnRouteToSpot,
                  onMarkAtSpot: _markAtSpot,
                  onMarkSpotComplete: _markSpotComplete,
                  onMarkDroppedOff: _markDroppedOff,
                ),
                const SizedBox(height: 14),
              ],
              _TouristCard(activity: activity),
              const SizedBox(height: 14),
              _BookingCard(booking: _booking, activity: activity),
              const SizedBox(height: 14),
              _LocationsCard(booking: _booking),
              const SizedBox(height: 14),
              _SpotProgressCard(
                spots: _spots,
                currentIndex: activity.currentSpotIndex,
                status: status,
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ],
    );
  }
}

// ── Status Card ───────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final info = _statusInfo(status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: info.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: info.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: info.iconBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(info.icon, color: info.color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.label,
                  style: TextStyle(
                    color: info.color,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  info.description,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _StatusInfo _statusInfo(String s) {
    switch (s) {
      case 'driver_accepted':
        return _StatusInfo(
          icon: Icons.check_circle_rounded,
          label: 'Booking Accepted',
          description: 'Tap "En Route" when you start heading to pickup.',
          color: const Color(0xFF2F6FFF),
          bg: const Color(0xFFEAF2FF),
          border: const Color(0xFFBFD7FF),
          iconBg: const Color(0xFFD6E8FF),
        );
      case 'driver_en_route':
        return _StatusInfo(
          icon: Icons.navigation_rounded,
          label: 'En Route to Pickup',
          description: 'Heading to the tourist pickup location.',
          color: const Color(0xFF7C3AED),
          bg: const Color(0xFFF5F3FF),
          border: const Color(0xFFDDD6FE),
          iconBg: const Color(0xFFEDE9FE),
        );
      case 'driver_arrived':
        return _StatusInfo(
          icon: Icons.location_on_rounded,
          label: 'Arrived at Pickup',
          description: "You've arrived. Waiting for the tourist.",
          color: const Color(0xFF0891B2),
          bg: const Color(0xFFECFEFF),
          border: const Color(0xFFA5F3FC),
          iconBg: const Color(0xFFCFFAFE),
        );
      case 'picked_up':
        return _StatusInfo(
          icon: Icons.groups_rounded,
          label: 'Tourist Picked Up',
          description: 'Head to the first tour spot when ready.',
          color: const Color(0xFF059669),
          bg: const Color(0xFFECFDF5),
          border: const Color(0xFFA7F3D0),
          iconBg: const Color(0xFFD1FAE5),
        );
      case 'en_route_to_spot':
        return _StatusInfo(
          icon: Icons.directions_car_rounded,
          label: 'En Route to Spot',
          description: 'Heading to the next tour stop.',
          color: const Color(0xFFD97706),
          bg: const Color(0xFFFFFBEB),
          border: const Color(0xFFFDE68A),
          iconBg: const Color(0xFFFEF3C7),
        );
      case 'at_spot':
        return _StatusInfo(
          icon: Icons.place_rounded,
          label: 'At Tour Spot',
          description: 'Tourist is exploring. Mark complete when done.',
          color: const Color(0xFFEA580C),
          bg: const Color(0xFFFFF7ED),
          border: const Color(0xFFFED7AA),
          iconBg: const Color(0xFFFFEDD5),
        );
      case 'en_route_to_dropoff':
        return _StatusInfo(
          icon: Icons.flag_rounded,
          label: 'En Route to Drop-off',
          description: 'All spots complete. Heading to drop-off.',
          color: const Color(0xFF7C3AED),
          bg: const Color(0xFFF5F3FF),
          border: const Color(0xFFDDD6FE),
          iconBg: const Color(0xFFEDE9FE),
        );
      case 'dropped_off':
      case 'completed':
        return _StatusInfo(
          icon: Icons.task_alt_rounded,
          label: 'Tour Completed',
          description: 'The tour package has been completed successfully.',
          color: const Color(0xFF16A34A),
          bg: const Color(0xFFECFDF5),
          border: const Color(0xFFA7F3D0),
          iconBg: const Color(0xFFD1FAE5),
        );
      default:
        return _StatusInfo(
          icon: Icons.hourglass_empty_rounded,
          label: 'Waiting to Start',
          description: 'Review booking details and tap Accept.',
          color: const Color(0xFF64748B),
          bg: const Color(0xFFF1F5F9),
          border: const Color(0xFFE2E8F0),
          iconBg: const Color(0xFFE2E8F0),
        );
    }
  }
}

class _StatusInfo {
  const _StatusInfo({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.bg,
    required this.border,
    required this.iconBg,
  });
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final Color bg;
  final Color border;
  final Color iconBg;
}

// ── Action Buttons ────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.status,
    required this.spots,
    required this.currentSpotIndex,
    required this.actionBusy,
    required this.onMarkEnRoute,
    required this.onMarkArrived,
    required this.onMarkPickedUp,
    required this.onMarkEnRouteToSpot,
    required this.onMarkAtSpot,
    required this.onMarkSpotComplete,
    required this.onMarkDroppedOff,
  });

  final String status;
  final List<BookingItineraryItem> spots;
  final int currentSpotIndex;
  final bool actionBusy;
  final VoidCallback onMarkEnRoute;
  final VoidCallback onMarkArrived;
  final VoidCallback onMarkPickedUp;
  final VoidCallback onMarkEnRouteToSpot;
  final VoidCallback onMarkAtSpot;
  final VoidCallback onMarkSpotComplete;
  final VoidCallback onMarkDroppedOff;

  @override
  Widget build(BuildContext context) {
    final buttons = _buildButtons();
    if (buttons.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Driver Actions',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: buttons,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildButtons() {
    switch (status) {
      case 'driver_accepted':
        return [
          _ActionBtn(
            label: 'En Route to Pickup',
            icon: Icons.navigation_rounded,
            primary: true,
            busy: actionBusy,
            onTap: onMarkEnRoute,
          ),
        ];
      case 'driver_en_route':
        return [
          _ActionBtn(
            label: 'Arrived at Pickup',
            icon: Icons.location_on_rounded,
            primary: true,
            busy: actionBusy,
            onTap: onMarkArrived,
          ),
        ];
      case 'driver_arrived':
        return [
          _ActionBtn(
            label: 'Tourist Picked Up',
            icon: Icons.groups_rounded,
            primary: true,
            busy: actionBusy,
            onTap: onMarkPickedUp,
          ),
        ];
      case 'picked_up':
        return [
          _ActionBtn(
            label: 'Head to First Spot',
            icon: Icons.directions_car_rounded,
            primary: true,
            busy: actionBusy,
            onTap: onMarkEnRouteToSpot,
          ),
        ];
      case 'en_route_to_spot':
        return [
          _ActionBtn(
            label: 'Arrived at Spot',
            icon: Icons.place_rounded,
            primary: true,
            busy: actionBusy,
            onTap: onMarkAtSpot,
          ),
        ];
      case 'at_spot':
        final nextIndex = currentSpotIndex + 1;
        final isLast = nextIndex >= spots.length;
        return [
          _ActionBtn(
            label: isLast ? 'Head to Drop-off' : 'Next Spot',
            icon: isLast
                ? Icons.flag_rounded
                : Icons.skip_next_rounded,
            primary: true,
            busy: actionBusy,
            onTap: onMarkSpotComplete,
          ),
        ];
      case 'en_route_to_dropoff':
        return [
          _ActionBtn(
            label: 'Tourist Dropped Off',
            icon: Icons.task_alt_rounded,
            primary: true,
            busy: actionBusy,
            onTap: onMarkDroppedOff,
          ),
        ];
      default:
        return [];
    }
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.busy,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor:
            primary ? const Color(0xFF2F6FFF) : const Color(0xFFEAF2FF),
        foregroundColor: primary ? Colors.white : const Color(0xFF2F6FFF),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

// ── Tourist Info Card ─────────────────────────────────────────

class _TouristCard extends StatelessWidget {
  const _TouristCard({required this.activity});
  final PackageActivity activity;

  @override
  Widget build(BuildContext context) {
    final tourist = activity.touristRow;
    final name = _name(tourist);
    final img = tourist?['profile_image_url']?.toString() ?? '';

    return _Card(
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFFEAF2FF),
            backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
            child: img.isEmpty
                ? const Icon(Icons.person_rounded, color: Color(0xFF2F6FFF))
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tourist',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _name(Json? r) {
    if (r == null) return 'Tourist';
    final full = (r['full_name'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    final first = (r['first_name'] ?? '').toString().trim();
    final last = (r['last_name'] ?? '').toString().trim();
    return ('$first $last').trim().isNotEmpty ? '$first $last' : 'Tourist';
  }
}

// ── Booking Details Card ──────────────────────────────────────

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.activity});

  final PackageBooking? booking;
  final PackageActivity activity;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final adults = b?.adults ?? 1;
    final children = b?.children ?? 0;
    final travelDate = b?.travelDate;
    final type = b?.bookingType ?? 'same_day';
    final total = b?.totalAmount ?? activity.price;
    final dp = b?.downpaymentAmount ?? 0.0;
    final remaining = b?.remainingBalance ?? 0.0;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Booking Details'),
          const SizedBox(height: 12),
          _row(
            Icons.calendar_today_rounded,
            'Date',
            travelDate != null
                ? DateFormat('MMMM d, yyyy').format(travelDate)
                : '—',
          ),
          const SizedBox(height: 10),
          _row(
            Icons.groups_rounded,
            'Passengers',
            '$adults adult${adults == 1 ? '' : 's'}${children > 0 ? ' · $children child${children == 1 ? '' : 'ren'}' : ''}',
          ),
          const SizedBox(height: 10),
          _row(
            Icons.event_rounded,
            'Type',
            type == 'advanced' ? 'Advanced Booking' : 'Same-Day Booking',
          ),
          const SizedBox(height: 10),
          _row(
            Icons.payments_rounded,
            'Total',
            'PHP ${total.toStringAsFixed(2)}',
          ),
          if (type == 'advanced') ...[
            const SizedBox(height: 10),
            _row(
              Icons.price_check_rounded,
              'Down payment',
              'PHP ${dp.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 10),
            _row(
              Icons.account_balance_wallet_rounded,
              'Remaining balance',
              remaining > 0
                  ? 'PHP ${remaining.toStringAsFixed(2)}'
                  : 'Settled',
              valueColor: remaining > 0
                  ? const Color(0xFFEA580C)
                  : const Color(0xFF16A34A),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
      );

  Widget _row(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 17, color: const Color(0xFF2F6FFF)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
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

// ── Locations Card ────────────────────────────────────────────

class _LocationsCard extends StatelessWidget {
  const _LocationsCard({required this.booking});
  final PackageBooking? booking;

  @override
  Widget build(BuildContext context) {
    final pickup = booking?.pickupAddress ?? 'Not specified';
    final dropoff = booking?.dropoffAddress ?? 'Not specified';

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Locations',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          _LocationRow(
            icon: Icons.trip_origin_rounded,
            label: 'Pickup',
            address: pickup,
            color: const Color(0xFF16A34A),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 17),
            child: SizedBox(
              height: 20,
              child: VerticalDivider(
                width: 1,
                thickness: 2,
                color: Color(0xFFCBD5E1),
              ),
            ),
          ),
          _LocationRow(
            icon: Icons.flag_rounded,
            label: 'Drop-off',
            address: dropoff,
            color: const Color(0xFFEF4444),
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.icon,
    required this.label,
    required this.address,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String address;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
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

// ── Spot Progress Card ────────────────────────────────────────

class _SpotProgressCard extends StatelessWidget {
  const _SpotProgressCard({
    required this.spots,
    required this.currentIndex,
    required this.status,
  });

  final List<BookingItineraryItem> spots;
  final int currentIndex;
  final String status;

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox.shrink();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tour Itinerary',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '$currentIndex / ${spots.length} done',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(spots.length, (i) {
            final isDone = i < currentIndex;
            final isCurrent = i == currentIndex &&
                (status == 'en_route_to_spot' || status == 'at_spot');
            return _SpotRow(
              number: i + 1,
              title: spots[i].destinationName,
              subtitle: _driverItinerarySummary(spots[i]),
              isDone: isDone,
              isCurrent: isCurrent,
              isLast: i == spots.length - 1,
            );
          }),
        ],
      ),
    );
  }
}

class _SpotRow extends StatelessWidget {
  const _SpotRow({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.isDone,
    required this.isCurrent,
    required this.isLast,
  });

  final int number;
  final String title;
  final String subtitle;
  final bool isDone;
  final bool isCurrent;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = isDone
        ? const Color(0xFF16A34A)
        : isCurrent
        ? const Color(0xFF2F6FFF)
        : const Color(0xFFCBD5E1);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDone
                    ? const Color(0xFFECFDF5)
                    : isCurrent
                    ? const Color(0xFFEAF2FF)
                    : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: isDone
                  ? const Icon(Icons.check_rounded,
                      size: 16, color: Color(0xFF16A34A))
                  : Center(
                      child: Text(
                        '$number',
                        style: TextStyle(
                          color: isCurrent
                              ? const Color(0xFF2F6FFF)
                              : const Color(0xFF94A3B8),
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: color.withValues(alpha: 0.35),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 4, bottom: isLast ? 0 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDone
                        ? const Color(0xFF64748B)
                        : isCurrent
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF94A3B8),
                    fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (isCurrent)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Current',
                style: TextStyle(
                  color: Color(0xFF2F6FFF),
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _driverItinerarySummary(BookingItineraryItem item) {
  final parts = <String>[];
  if (item.arrivalTime.isNotEmpty) {
    parts.add('Arrival ${formatScheduleTimeLabel(item.arrivalTime)}');
  }
  if (item.estimatedStayDurationMinutes > 0) {
    parts.add('Stay ${item.estimatedStayDurationMinutes}m');
  }
  if (item.departureTime.isNotEmpty) {
    parts.add('Departure ${formatScheduleTimeLabel(item.departureTime)}');
  }
  return parts.join(' • ');
}

// ── Shared Card Container ─────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
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
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
