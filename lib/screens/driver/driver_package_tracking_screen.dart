import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/tourist/tourist_messages_screen.dart';
import 'package:url_launcher/url_launcher.dart';

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
  // Driver must be within 150m to mark arrival/pickup
  static const double _proximityMeters = 150.0;

  // TODO: REMOVE TEST MODE BEFORE PRODUCTION
  static const bool kDriverActionTestMode = true;

  final _repo = TourisTrikeRepository();
  final _supabase = Supabase.instance.client;

  String _bookingId = '';
  PackageActivity? _activity;
  PackageBooking? _booking;
  List<BookingItineraryItem> _spots = [];

  bool _loading = true;
  String? _error;
  bool _actionBusy = false;
  String? _eta;

  // Current driver GPS position
  Position? _currentPosition;

  RealtimeChannel? _activityChannel;
  RealtimeChannel? _bookingChannel;
  RealtimeChannel? _itineraryChannel;
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
    _activityChannel?.unsubscribe();
    _bookingChannel?.unsubscribe();
    _itineraryChannel?.unsubscribe();
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
      final initialActivity = await _repo.fetchPackageActivityById(
        widget.activityId,
      );
      final bookingId = initialActivity?.bookingId ?? _bookingId;
      if (bookingId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'Booking not found for this activity.';
          _loading = false;
        });
        return;
      }
      final results = await Future.wait([
        _repo.fetchPackageBookingDetails(bookingId),
        _repo.fetchBookingItinerary(bookingId),
      ]);
      final booking = results[0] as PackageBooking?;
      var spots = results[1] as List<BookingItineraryItem>;

      if (spots.isEmpty) {
        await _repo.ensureBookingItinerary(bookingId);
        spots = await _repo.fetchBookingItinerary(bookingId);
      }

      if (!mounted) return;
      setState(() {
        _bookingId = bookingId;
        _activity = initialActivity;
        _booking = booking;
        _spots = spots;
        _loading = false;
      });

      _debugTourState('load');
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
    final bookingId = _bookingId;
    if (bookingId.isEmpty) return;

    _activityChannel?.unsubscribe();
    _activityChannel = _supabase
        .channel('driver-activity:$bookingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'package_activities',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: bookingId,
          ),
          callback: (_) => _refreshTrackingState(logTag: 'activity-update'),
        )
        .subscribe();

    _bookingChannel?.unsubscribe();
    _bookingChannel = _supabase
        .channel('driver-booking:$bookingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'package_bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: bookingId,
          ),
          callback: (_) => _refreshTrackingState(logTag: 'booking-update'),
        )
        .subscribe();

    _itineraryChannel?.unsubscribe();
    _itineraryChannel = _supabase
        .channel('driver-itinerary:$bookingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'booking_itinerary_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: bookingId,
          ),
          callback: (_) => _refreshTrackingState(logTag: 'itinerary-update'),
        )
        .subscribe();
  }

  Future<void> _startGpsStreaming() async {
    final ok = await _checkLocationPermission();
    if (!ok) return;
    await _gpsSub?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 8,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen((
      pos,
    ) async {
      if (_activity == null) return;
      _currentPosition = pos;

      try {
        // Update activity + booking rows
        await _repo.updateDriverLocation(
          activityId: widget.activityId,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
        // Also upsert live location table for tourists' real-time channel
        await _repo.upsertDriverLiveLocation(
          activityId: widget.activityId,
          latitude: pos.latitude,
          longitude: pos.longitude,
          heading: pos.heading,
          speed: pos.speed,
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
    });
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

  // ── Proximity check ───────────────────────────────────────────

  /// Returns true if the driver is within [_proximityMeters] of [target].
  bool _isNearTarget(LatLng target) {
    final pos = _currentPosition;
    if (pos == null) return true; // allow if GPS not yet available
    final distMeters = _haversineMeters(
      pos.latitude,
      pos.longitude,
      target.latitude,
      target.longitude,
    );
    return distMeters <= _proximityMeters;
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _deg2rad(double deg) => deg * (math.pi / 180);

  bool get _allItineraryItemsCompleted =>
      _spots.isNotEmpty &&
      _spots.every((spot) => spot.spotStatus == 'completed');

  int get _incompleteItineraryItemsCount =>
      _spots.where((spot) => spot.spotStatus != 'completed').length;

  bool get _hasPickedUp =>
      _activity?.pickedUpAt != null || _booking?.pickedUpAt != null;

  BookingItineraryItem? get _currentItineraryItem =>
      _spots.where((s) => s.spotStatus != 'completed').firstOrNull;

  String get _currentSpotName =>
      _currentItineraryItem?.destinationName ?? 'Spot';

  String get _selectedCurrentActionLabel {
    final status = _activity?.tourStatus ?? '';
    final currentItem = _currentItineraryItem;
    if (status == 'completed') return 'none';
    if (status == 'driver_accepted') return 'En Route to Pickup';
    if (status == 'driver_en_route') return 'Arrived at Pickup';
    if (!_hasPickedUp) return 'Mark Tourist Picked Up';
    if (_allItineraryItemsCompleted) {
      if (status == 'ready_to_complete') return 'Complete Trip';
      return 'Arrived at Drop-off';
    }
    if (currentItem == null) return 'reload itinerary';
    if (currentItem.spotStatus == 'at_spot') {
      return 'Complete ${currentItem.destinationName}';
    }
    return 'Arrived at ${currentItem.destinationName}';
  }

  Future<void> _refreshTrackingState({String logTag = 'refresh'}) async {
    final bookingId = _bookingId.isNotEmpty
        ? _bookingId
        : (_activity?.bookingId.isNotEmpty == true ? _activity!.bookingId : '');
    if (bookingId.isEmpty) return;
    final results = await Future.wait([
      _repo.fetchPackageActivityById(widget.activityId),
      _repo.fetchPackageBookingDetails(bookingId),
      _repo.fetchBookingItinerary(bookingId),
    ]);
    var refreshedSpots = results[2] as List<BookingItineraryItem>;
    if (refreshedSpots.isEmpty) {
      await _repo.ensureBookingItinerary(bookingId);
      refreshedSpots = await _repo.fetchBookingItinerary(bookingId);
    }
    if (!mounted) return;
    setState(() {
      _activity = results[0] as PackageActivity?;
      _booking = results[1] as PackageBooking?;
      _spots = refreshedSpots;
    });
    _debugTourState(logTag);
    _buildMarkers();
    _fetchCurrentRoute();
  }

  void _debugTourState(String tag, {Map<String, dynamic>? rpcResult}) {
    final activity = _activity;
    final booking = _booking;
    final currentItem = _currentItineraryItem;
    final completedCount = _spots
        .where((spot) => spot.spotStatus == 'completed')
        .length;
    final spotStatusList = _spots
        .map((spot) => '${spot.id}:${spot.spotStatus}')
        .join(', ');
    debugPrint(
      '[DriverTracking:$tag] '
      'booking_id=${_bookingId.isNotEmpty ? _bookingId : activity?.bookingId} '
      'loaded travel_date=${booking?.travelDate} '
      'loaded pickup_address=${booking?.pickupAddress} '
      'loaded dropoff_address=${booking?.dropoffAddress} '
      'total itinerary items=${_spots.length} '
      'incomplete itinerary items=$_incompleteItineraryItemsCount '
      'completed itinerary items=$completedCount '
      'current itinerary item id=${currentItem?.id} '
      'current itinerary item status=${currentItem?.spotStatus} '
      'selected current action=$_selectedCurrentActionLabel '
      'spot_status list=[$spotStatusList] '
      'package_activities.status=${activity?.status} '
      'package_activities.tour_status=${activity?.tourStatus} '
      'package_bookings.status=${booking?.status} '
      'package_bookings.booking_status=${booking?.bookingStatus} '
      '${rpcResult == null ? '' : 'rpc=$rpcResult'}',
    );
  }

  // ── Map ───────────────────────────────────────────────────────

  void _buildMarkers() {
    if (_activity == null) return;

    final markers = <Marker>{};
    final pickup = _pickupLatLng();
    final dropoff = _dropoffLatLng();
    final driverPos = _driverLatLng();

    if (pickup != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: 'Pickup',
            snippet: _booking?.pickupAddress ?? '',
          ),
        ),
      );
    }
    if (dropoff != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: dropoff,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'Drop-off',
            snippet: _booking?.dropoffAddress ?? '',
          ),
        ),
      );
    }

    for (var i = 0; i < _spots.length; i++) {
      final lat = _spots[i].latitude;
      final lng = _spots[i].longitude;
      if (lat == 0 && lng == 0) continue;
      final isDone = _spots[i].spotStatus == 'completed';
      final isCurrent = !isDone && _spots[i].id == _currentItineraryItem?.id;
      markers.add(
        Marker(
          markerId: MarkerId('spot_$i'),
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isDone
                ? BitmapDescriptor.hueGreen
                : isCurrent
                ? BitmapDescriptor.hueOrange
                : BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: 'Stop ${i + 1}: ${_spots[i].destinationName}',
          ),
        ),
      );
    }

    if (driverPos != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: driverPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: const InfoWindow(title: 'You (Driver)'),
        ),
      );
    }

    if (mounted) setState(() => _markers = markers);
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
    } else if (status == 'driver_arrived') {
      origin = pickupPos;
      destination = _spots.isNotEmpty ? _currentSpotLatLng() : dropoffPos;
    } else if (status == 'picked_up' ||
        status == 'on_tour' ||
        status == 'en_route_to_spot' ||
        status == 'at_spot') {
      if (_allItineraryItemsCompleted) {
        origin = driverPos;
        destination = dropoffPos;
      } else {
        origin = driverPos ?? pickupPos;
        destination = _currentSpotLatLng();
      }
    } else if (status == 'en_route_to_dropoff' ||
        status == 'ready_to_complete') {
      origin = driverPos;
      destination = dropoffPos;
    } else {
      if (mounted) setState(() => _polylines = {});
      return;
    }

    if (origin == null || destination == null) {
      if (mounted) setState(() => _polylines = {});
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
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return;
      final route = routes.first as Map;
      final legs = (route['legs'] as List?) ?? const [];
      String? durationText;
      if (legs.isNotEmpty) {
        final leg = legs.first as Map;
        durationText = leg['duration']?['text'] as String?;
        final steps = (leg['steps'] as List?) ?? const [];
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
          _eta = durationText;
        });
      }
    } catch (_) {}
  }

  List<LatLng> _decodePolyline(String encoded) {
    final result = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, r = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        r |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (r & 1) != 0 ? ~(r >> 1) : (r >> 1);
      shift = 0;
      r = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        r |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (r & 1) != 0 ? ~(r >> 1) : (r >> 1);
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
    final item = _currentItineraryItem;
    if (item == null) return null;
    if (item.latitude == 0 && item.longitude == 0) return null;
    return LatLng(item.latitude, item.longitude);
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
    _logStatus('driver_en_route');
    await _refreshTrackingState(logTag: 'driver-en-route');
    _showSnack('Status: En route to pickup.');
  });

  Future<void> _markArrived() => _doAction(() async {
    final pickupPos = _pickupLatLng();
    // TODO: REMOVE TEST MODE BEFORE PRODUCTION
    if (!kDriverActionTestMode &&
        pickupPos != null &&
        !_isNearTarget(pickupPos)) {
      _showSnack(
        'You must be within 150 m of the pickup point to mark arrival.',
      );
      return;
    }
    await _repo.updateActivityTourStatus(
      activityId: widget.activityId,
      tourStatus: 'driver_arrived',
      extra: {'arrived_at': DateTime.now().toIso8601String()},
    );
    _logStatus('driver_arrived');
    await _refreshTrackingState(logTag: 'driver-arrived');
    _showSnack('Status: Arrived at pickup.');
  });

  Future<void> _markPickedUp() => _doAction(() async {
    final pickupPos = _pickupLatLng();
    // TODO: REMOVE TEST MODE BEFORE PRODUCTION
    if (!kDriverActionTestMode &&
        pickupPos != null &&
        !_isNearTarget(pickupPos)) {
      _showSnack(
        'You must be at the pickup location to mark tourist as picked up.',
      );
      return;
    }
    await _repo.updateActivityTourStatus(
      activityId: widget.activityId,
      tourStatus: 'on_tour',
      activityStatus: 'ongoing',
      bookingStatus: 'on_tour',
      extra: {'picked_up_at': DateTime.now().toIso8601String()},
    );
    final currentItem = _currentItineraryItem;
    if (_bookingId.isNotEmpty && currentItem != null) {
      await _repo.markSpotTravelling(
        bookingId: _bookingId,
        itineraryItemId: currentItem.id.toString(),
      );
    }
    _logStatus('picked_up');
    await _refreshTrackingState(logTag: 'picked-up');
    _showSnack('Status: Tourist picked up.');
  });

  Future<void> _markEnRouteToSpot() => _doAction(() async {
    final bookingId = _bookingId;
    final currentItem = _currentItineraryItem;
    await _repo.updateActivityTourStatus(
      activityId: widget.activityId,
      tourStatus: 'on_tour',
      activityStatus: 'ongoing',
      bookingStatus: 'on_tour',
    );
    if (bookingId.isNotEmpty && currentItem != null) {
      await _repo.markSpotTravelling(
        bookingId: bookingId,
        itineraryItemId: currentItem.id.toString(),
      );
    }
    _logStatus('en_route_to_spot');
    await _refreshTrackingState(logTag: 'en-route-to-spot');
    _showSnack('Status: En route to next spot.');
  });

  Future<void> _markAtSpot() => _doAction(() async {
    final spotPos = _currentSpotLatLng();
    // TODO: REMOVE TEST MODE BEFORE PRODUCTION
    if (!kDriverActionTestMode && spotPos != null && !_isNearTarget(spotPos)) {
      _showSnack('You must be within 150 m of the spot to mark arrival.');
      return;
    }
    final currentItem = _currentItineraryItem;
    final bookingId = _bookingId;

    // Optimistic update so the button changes immediately
    if (currentItem != null && mounted) {
      setState(() {
        _spots = _spots.map((s) {
          if (s.id == currentItem.id) {
            return BookingItineraryItem({
              ...s.row,
              'spot_status': 'at_spot',
              'actual_arrival_time': DateTime.now().toIso8601String(),
            });
          }
          return s;
        }).toList();
      });
    }

    await _repo.updateActivityTourStatus(
      activityId: widget.activityId,
      tourStatus: 'on_tour',
      activityStatus: 'ongoing',
      bookingStatus: 'on_tour',
    );
    if (bookingId.isNotEmpty && currentItem != null) {
      await _repo.markSpotActualArrival(
        bookingId: bookingId,
        itineraryItemId: currentItem.id.toString(),
      );
    }
    _logStatus('at_spot');
    await _refreshTrackingState(logTag: 'at-spot');
    _showSnack('Arrived at ${currentItem?.destinationName ?? 'spot'}.');
  });

  Future<void> _markSpotComplete() => _doAction(() async {
    // TODO: REMOVE TEST MODE BEFORE PRODUCTION
    BookingItineraryItem? currentItem = _currentItineraryItem;
    if (currentItem == null) {
      if (kDriverActionTestMode && _spots.isNotEmpty) {
        final atSpot = _spots.where((s) => s.spotStatus.trim().toLowerCase() == 'at_spot').firstOrNull;
        currentItem = atSpot ?? _spots.where((s) => s.spotStatus.trim().toLowerCase() != 'completed').firstOrNull;
      }
      if (currentItem == null) {
        await _refreshTrackingState(logTag: 'spot-complete-null');
        _showSnack('Refreshed. Please try again.');
        return;
      }
    }

    final spotName = currentItem.destinationName;
    final totalItems = _spots.length;
    final completedBefore = _spots.where((s) => s.spotStatus.trim().toLowerCase() == 'completed').length;
    final itemId = currentItem.id?.toString() ?? '';

    debugPrint(
      '[SpotComplete] BEFORE: id=$itemId name=$spotName '
      'status=${currentItem.spotStatus} total=$totalItems '
      'completedBefore=$completedBefore bookingId=$_bookingId',
    );

    if (itemId.isEmpty || itemId == 'null') {
      _showSnack('Cannot complete spot: item ID is missing. Try refreshing.');
      await _refreshTrackingState(logTag: 'spot-complete-no-id');
      return;
    }

    // Optimistic update so UI responds immediately.
    if (mounted) {
      setState(() {
        _spots = _spots.map((s) {
          if (s.id?.toString() == itemId) {
            return BookingItineraryItem({
              ...s.row,
              'spot_status': 'completed',
              'actual_departure_time': DateTime.now().toIso8601String(),
            });
          }
          return s;
        }).toList();
      });
    }

    // Use the SECURITY DEFINER RPC — bypasses RLS entirely, atomic, and
    // handles marking the next item as 'travelling' in one transaction.
    // This is the reliable path: direct table updates are silently blocked
    // by the booking_itinerary_items UPDATE policy for drivers.
    Map<String, dynamic> rpcResult;
    try {
      rpcResult = await _repo.completeCurrentItineraryItem(
        widget.activityId,
        itineraryItemId: itemId,
      );
    } catch (e) {
      // RPC failed — revert optimistic update and surface the error.
      await _refreshTrackingState(logTag: 'spot-complete-error');
      _showSnack('Error completing spot: $e');
      return;
    }

    _debugTourState('spot-complete-rpc', rpcResult: rpcResult);

    final completedNow =
        (rpcResult['completed_items'] as num?)?.toInt() ?? (completedBefore + 1);
    final rpcTotal =
        (rpcResult['total_items'] as num?)?.toInt() ?? totalItems;
    final allSpotsCompletedNow = completedNow >= rpcTotal && rpcTotal > 0;

    // Sync local _spots state from the authoritative server list returned by
    // the RPC so our UI exactly matches the DB without a full re-fetch.
    final rawList = rpcResult['spot_status_list'];
    if (rawList is List && rawList.isNotEmpty) {
      final statusMap = <String, String>{};
      for (final item in rawList) {
        if (item is Map) {
          final id = item['id']?.toString();
          final status = item['spot_status']?.toString();
          if (id != null && id.isNotEmpty && status != null) {
            statusMap[id] = status;
          }
        }
      }
      if (mounted && statusMap.isNotEmpty) {
        setState(() {
          _spots = _spots.map((s) {
            final newStatus = statusMap[s.id?.toString()];
            if (newStatus != null) {
              return BookingItineraryItem({...s.row, 'spot_status': newStatus});
            }
            return s;
          }).toList();
        });
      }
    }

    if (allSpotsCompletedNow) {
      // All spots done — transition to en_route_to_dropoff.
      // The RPC leaves tour_status as 'on_tour'; we promote it here.
      await _repo.updateActivityTourStatus(
        activityId: widget.activityId,
        tourStatus: 'en_route_to_dropoff',
        bookingStatus: 'on_tour',
      );
      await _refreshTrackingState(logTag: 'all-spots-done');
      _logStatus('en_route_to_dropoff');
      _showSnack('All $rpcTotal spots done! Head to the drop-off point.');
    } else {
      await _refreshTrackingState(logTag: 'spot-complete');
      _logStatus('on_tour');
      final nextItem = _spots.where((s) => s.spotStatus.trim().toLowerCase() != 'completed').firstOrNull;
      _showSnack(
        '$spotName completed. $completedNow of $rpcTotal spots done.'
        '${nextItem != null ? ' Next: ${nextItem.destinationName}' : ''}',
      );
    }
  });

  Future<void> _markArrivedAtDropoff() => _doAction(() async {
    final dropoffPos = _dropoffLatLng();
    // TODO: REMOVE TEST MODE BEFORE PRODUCTION
    if (!kDriverActionTestMode &&
        dropoffPos != null &&
        !_isNearTarget(dropoffPos)) {
      _showSnack('You must be within 150 m of the drop-off point.');
      return;
    }
    await _repo.updateActivityTourStatus(
      activityId: widget.activityId,
      tourStatus: 'ready_to_complete',
      bookingStatus: 'on_tour',
    );
    _logStatus('ready_to_complete');
    await _refreshTrackingState(logTag: 'arrived-dropoff');
    _showSnack('Arrived at drop-off. Tap "Complete Trip" when ready.');
  });

  Future<void> _markCompleteTour() => _doAction(() async {
    if (!_allItineraryItemsCompleted) {
      _showSnack('Complete all itinerary spots before finishing the tour.');
      return;
    }

    final booking = _booking;
    final isAdvanced = (booking?.bookingType ?? 'same_day') == 'advanced';
    final remainingBalance = booking?.remainingBalance ?? 0.0;

    if (isAdvanced && remainingBalance > 0) {
      final confirmed = await _showCashConfirmDialog(remainingBalance);
      if (confirmed != true) return;
    }

    await _repo.completePackageActivity(
      widget.activityId,
      remainingPaymentMethod: isAdvanced && remainingBalance > 0 ? 'cash' : '',
    );
    await _refreshTrackingState(logTag: 'complete-tour');
    _logStatus('completed');
    _showSnack('Tour completed successfully.');
  });

  void _logStatus(String status, {int? spotIndex}) {
    final activity = _activity;
    if (activity == null) return;
    final pos = _currentPosition;
    _repo
        .logTripStatus(
          activityId: widget.activityId,
          bookingId: activity.bookingId,
          status: status,
          spotIndex: spotIndex,
          latitude: pos?.latitude,
          longitude: pos?.longitude,
        )
        .catchError((_) {});
  }

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
                fontSize: 26,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ── Tourist contact ───────────────────────────────────────────

  Future<void> _openTouristChat() async {
    final activity = _activity;
    if (activity == null) {
      _showSnack('Activity not loaded yet.');
      return;
    }
    final touristId = activity.touristId;
    if (touristId.isEmpty) {
      _showSnack('Tourist info not available.');
      return;
    }
    final driverId = _repo.requireUserId();
    try {
      final conversation = await _repo.getOrCreateConversation(
        touristId: touristId,
        driverId: driverId,
        bookingId: _bookingId.isNotEmpty ? _bookingId : null,
      );
      if (!mounted) return;
      final tourist = activity.touristRow;
      final rawName = (tourist?['full_name'] as String? ?? '').trim();
      final touristName = rawName.isNotEmpty
          ? rawName
          : [tourist?['first_name'], tourist?['last_name']]
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .join(' ');
      final touristPhone = (tourist?['mobile'] as String? ?? '').trim();
      final touristAvatar = (tourist?['profile_image_url'] as String? ?? '').trim();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TouristChatScreen(
            conversationId: conversation['id'].toString(),
            driverId: touristId,
            driverName: touristName.isNotEmpty ? touristName : 'Tourist',
            driverPhone: touristPhone,
            driverAvatar: touristAvatar,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showSnack('Unable to open chat: $e');
    }
  }

  Future<void> _callTourist() async {
    final tourist = _activity?.touristRow;
    final phone = (tourist?['mobile'] as String? ?? '').trim();
    if (phone.isEmpty) {
      _showSnack('Tourist phone number not available.');
      return;
    }
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnack('Unable to launch phone dialer.');
    }
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mapHeight = (size.height * 0.32).clamp(200.0, 320.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : _buildContent(mapHeight),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Color(0xFFEF4444),
            ),
            const SizedBox(height: 12),
            const Text(
              'Failed to load activity',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
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

  Widget _buildContent(double mapHeight) {
    final activity = _activity!;
    final status = activity.tourStatus;
    final isCompleted = status == 'completed';
    final bottom = MediaQuery.of(context).padding.bottom;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: mapHeight,
          pinned: true,
          backgroundColor: const Color(0xFF2F6FFF),
          foregroundColor: Colors.white,
          title: Row(
            children: [
              const Expanded(
                child: Text(
                  'Tour Navigation',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (_eta != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    _eta!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
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
          padding: EdgeInsets.fromLTRB(16, 14, 16, 24 + bottom),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _StatusCard(status: status),
              const SizedBox(height: 12),
              if (!isCompleted) ...[
                _ActionButtons(
                  status: status,
                  hasPickedUp: _hasPickedUp,
                  hasCurrentItem: _currentItineraryItem != null,
                  currentSpotName: _currentSpotName,
                  currentItemStatus: _currentItineraryItem?.spotStatus ?? '',
                  allSpotsCompleted: _allItineraryItemsCompleted,
                  actionBusy: _actionBusy,
                  // TODO: REMOVE TEST MODE BEFORE PRODUCTION
                  testMode: kDriverActionTestMode,
                  onMarkEnRoute: _markEnRoute,
                  onMarkArrived: _markArrived,
                  onMarkPickedUp: _markPickedUp,
                  onMarkEnRouteToSpot: _markEnRouteToSpot,
                  onMarkAtSpot: _markAtSpot,
                  onMarkSpotComplete: _markSpotComplete,
                  onMarkArrivedAtDropoff: _markArrivedAtDropoff,
                  onMarkCompleteTour: _markCompleteTour,
                ),
                const SizedBox(height: 12),
              ],
              _TouristCard(
                activity: activity,
                onMessage: _openTouristChat,
                onCall: _callTourist,
              ),
              const SizedBox(height: 12),
              _BookingCard(booking: _booking, activity: activity),
              const SizedBox(height: 12),
              _LocationsCard(booking: _booking),
              const SizedBox(height: 12),
              _SpotProgressCard(
                spots: _spots,
                currentItemId: _currentItineraryItem?.id.toString(),
                status: status,
              ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: info.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: info.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: info.iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(info.icon, color: info.color, size: 22),
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
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  info.description,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
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
      case 'on_tour':
        return _StatusInfo(
          icon: Icons.route_rounded,
          label: 'On Tour',
          description:
              'Follow the tourist itinerary and complete each selected spot one by one.',
          color: const Color(0xFF0EA5E9),
          bg: const Color(0xFFF0F9FF),
          border: const Color(0xFFBAE6FD),
          iconBg: const Color(0xFFE0F2FE),
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
      case 'ready_to_complete':
        return _StatusInfo(
          icon: Icons.task_alt_rounded,
          label: 'All Spots Completed',
          description:
              'All itinerary spots are done. Finish the tour when ready.',
          color: const Color(0xFF0F766E),
          bg: const Color(0xFFECFDF5),
          border: const Color(0xFFA7F3D0),
          iconBg: const Color(0xFFD1FAE5),
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
    required this.hasPickedUp,
    required this.hasCurrentItem,
    required this.currentSpotName,
    required this.currentItemStatus,
    required this.allSpotsCompleted,
    required this.actionBusy,
    // TODO: REMOVE TEST MODE BEFORE PRODUCTION
    this.testMode = false,
    required this.onMarkEnRoute,
    required this.onMarkArrived,
    required this.onMarkPickedUp,
    required this.onMarkEnRouteToSpot,
    required this.onMarkAtSpot,
    required this.onMarkSpotComplete,
    required this.onMarkArrivedAtDropoff,
    required this.onMarkCompleteTour,
  });

  final String status;
  final bool hasPickedUp;
  final bool hasCurrentItem;
  final String currentSpotName;
  final String currentItemStatus;
  final bool allSpotsCompleted;
  final bool actionBusy;
  // TODO: REMOVE TEST MODE BEFORE PRODUCTION
  final bool testMode;
  final VoidCallback onMarkEnRoute;
  final VoidCallback onMarkArrived;
  final VoidCallback onMarkPickedUp;
  final VoidCallback onMarkEnRouteToSpot;
  final VoidCallback onMarkAtSpot;
  final VoidCallback onMarkSpotComplete;
  final VoidCallback onMarkArrivedAtDropoff;
  final VoidCallback onMarkCompleteTour;

  @override
  Widget build(BuildContext context) {
    final buttons = _buildButtons();
    if (buttons.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
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
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: buttons),
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
            label: 'Mark Tourist Picked Up',
            icon: Icons.groups_rounded,
            primary: true,
            busy: actionBusy,
            onTap: onMarkPickedUp,
          ),
        ];
      case 'picked_up':
      case 'on_tour':
      case 'en_route_to_spot':
      case 'at_spot':
      case 'en_route_to_dropoff':
      case 'ready_to_complete':
        // TODO: REMOVE TEST MODE BEFORE PRODUCTION
        if (!testMode && !hasPickedUp) {
          return [
            _ActionBtn(
              label: 'Mark Tourist Picked Up',
              icon: Icons.groups_rounded,
              primary: true,
              busy: actionBusy,
              onTap: onMarkPickedUp,
            ),
          ];
        }

        // ── Drop-off flow (all itinerary spots are completed) ──
        if (allSpotsCompleted) {
          if (status == 'ready_to_complete') {
            return [
              _ActionBtn(
                label: 'Complete Trip',
                icon: Icons.task_alt_rounded,
                primary: true,
                busy: actionBusy,
                onTap: onMarkCompleteTour,
              ),
            ];
          }
          return [
            _ActionBtn(
              label: 'Arrived at Drop-off',
              icon: Icons.flag_rounded,
              primary: true,
              busy: actionBusy,
              onTap: onMarkArrivedAtDropoff,
            ),
          ];
        }

        // ── Itinerary spot progression ─────────────────────────
        // TODO: REMOVE TEST MODE BEFORE PRODUCTION
        if (!testMode && !hasCurrentItem) return [];

        if (currentItemStatus == 'at_spot') {
          return [
            _ActionBtn(
              label: 'Complete $currentSpotName',
              icon: Icons.check_circle_rounded,
              primary: true,
              busy: actionBusy,
              onTap: onMarkSpotComplete,
            ),
          ];
        }
        return [
          _ActionBtn(
            label: 'Arrived at $currentSpotName',
            icon: Icons.place_rounded,
            primary: true,
            busy: actionBusy,
            onTap: onMarkAtSpot,
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
        backgroundColor: primary
            ? const Color(0xFF2F6FFF)
            : const Color(0xFFEAF2FF),
        foregroundColor: primary ? Colors.white : const Color(0xFF2F6FFF),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: busy
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 17),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

// ── Tourist Info Card ─────────────────────────────────────────

class _TouristCard extends StatelessWidget {
  const _TouristCard({
    required this.activity,
    this.onMessage,
    this.onCall,
  });
  final PackageActivity activity;
  final VoidCallback? onMessage;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final tourist = activity.touristRow;
    final name = _name(tourist);
    final img = (tourist?['profile_image_url'] as String? ?? '').trim();
    final phone = (tourist?['mobile'] as String? ?? '').trim();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFEAF2FF),
                backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
                child: img.isEmpty
                    ? const Icon(Icons.person_rounded, color: Color(0xFF2F6FFF))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOURIST',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    if (phone.isNotEmpty)
                      Text(
                        phone,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (onCall != null)
                _ContactIconBtn(
                  icon: Icons.phone_rounded,
                  color: const Color(0xFF16A34A),
                  tooltip: 'Call tourist',
                  onTap: onCall!,
                ),
              if (onMessage != null)
                _ContactIconBtn(
                  icon: Icons.chat_bubble_outline_rounded,
                  color: const Color(0xFF2F6FFF),
                  tooltip: 'Message tourist',
                  onTap: onMessage!,
                ),
            ],
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
    final combo = '$first $last'.trim();
    return combo.isNotEmpty ? combo : 'Tourist';
  }
}

class _ContactIconBtn extends StatelessWidget {
  const _ContactIconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
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
    final rawTravelDate = dbString(b?.row['travel_date']);
    final type = b?.bookingType ?? 'same_day';
    final total = b?.totalAmount ?? activity.price;
    final dp = b?.downpaymentAmount ?? 0.0;
    final remaining = b?.remainingBalance ?? 0.0;
    final requiredDrivers = b?.requiredDrivers ?? 1;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Booking Details'),
          const SizedBox(height: 10),
          _row(
            Icons.calendar_today_rounded,
            'Date',
            travelDate != null
                ? DateFormat('MMMM d, yyyy').format(travelDate)
                : rawTravelDate.isNotEmpty
                ? rawTravelDate
                : '—',
          ),
          const SizedBox(height: 8),
          _row(
            Icons.groups_rounded,
            'Passengers',
            '$adults adult${adults == 1 ? '' : 's'}${children > 0 ? ' · $children child${children == 1 ? '' : 'ren'}' : ''}',
          ),
          if (requiredDrivers > 1) ...[
            const SizedBox(height: 8),
            _row(
              Icons.electric_rickshaw_rounded,
              'Tricycles',
              '$requiredDrivers required for this group',
            ),
          ],
          const SizedBox(height: 8),
          _row(
            Icons.event_rounded,
            'Type',
            type == 'advanced' ? 'Advanced Booking' : 'Same-Day Booking',
          ),
          const SizedBox(height: 8),
          _row(
            Icons.payments_rounded,
            'Total',
            'PHP ${total.toStringAsFixed(2)}',
          ),
          if (type == 'advanced') ...[
            const SizedBox(height: 8),
            _row(
              Icons.price_check_rounded,
              'Down payment',
              'PHP ${dp.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 8),
            _row(
              Icons.account_balance_wallet_rounded,
              'Remaining balance',
              remaining > 0 ? 'PHP ${remaining.toStringAsFixed(2)}' : 'Settled',
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
      fontSize: 14.5,
    ),
  );

  Widget _row(IconData icon, String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 15, color: const Color(0xFF2F6FFF)),
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
                  fontSize: 9.5,
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
                  fontSize: 13.5,
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
    final b = booking;
    final pickup = (b?.pickupAddress ?? '').trim();
    final dropoff = (b?.dropoffAddress ?? '').trim();
    if (pickup.isEmpty && dropoff.isEmpty) return const SizedBox.shrink();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pickup & Drop-off',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 10),
          if (pickup.isNotEmpty) ...[
            _LocationRow(
              icon: Icons.trip_origin_rounded,
              color: const Color(0xFF16A34A),
              label: 'PICKUP',
              address: pickup,
            ),
          ],
          if (pickup.isNotEmpty && dropoff.isNotEmpty)
            const SizedBox(height: 8),
          if (dropoff.isNotEmpty) ...[
            _LocationRow(
              icon: Icons.location_on_rounded,
              color: const Color(0xFFEF4444),
              label: 'DROP-OFF',
              address: dropoff,
            ),
          ],
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.address,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
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
                  fontSize: 9.5,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
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
    required this.currentItemId,
    required this.status,
  });

  final List<BookingItineraryItem> spots;
  final String? currentItemId;
  final String status;

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox.shrink();
    final completedCount = spots
        .where((spot) => spot.spotStatus == 'completed')
        .length;

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
                    fontSize: 14.5,
                  ),
                ),
              ),
              Text(
                '$completedCount / ${spots.length} done',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...List.generate(spots.length, (i) {
            final isDone = spots[i].spotStatus == 'completed';
            final isCurrent =
                !isDone &&
                spots[i].id.toString() == currentItemId &&
                (status == 'picked_up' ||
                    status == 'on_tour' ||
                    status == 'en_route_to_spot' ||
                    status == 'at_spot');
            return _SpotRow(
              number: i + 1,
              title: spots[i].destinationName,
              address: spots[i].destinationAddress,
              scheduledArrival: spots[i].arrivalTime,
              scheduledDeparture: spots[i].departureTime,
              actualArrival: spots[i].actualArrivalTime,
              actualDeparture: spots[i].actualDepartureTime,
              spotStatus: spots[i].spotStatus,
              stayMinutes: spots[i].estimatedStayDurationMinutes,
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
    required this.address,
    required this.scheduledArrival,
    required this.scheduledDeparture,
    required this.actualArrival,
    required this.actualDeparture,
    required this.spotStatus,
    required this.stayMinutes,
    required this.isDone,
    required this.isCurrent,
    required this.isLast,
  });

  final int number;
  final String title;
  final String address;
  final String scheduledArrival;
  final String scheduledDeparture;
  final DateTime? actualArrival;
  final DateTime? actualDeparture;
  final String spotStatus;
  final int stayMinutes;
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
    final timeFmt = DateFormat('h:mm a');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isDone
                    ? const Color(0xFFECFDF5)
                    : isCurrent
                    ? const Color(0xFFEAF2FF)
                    : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.8),
              ),
              child: isDone
                  ? const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Color(0xFF16A34A),
                    )
                  : Center(
                      child: Text(
                        '$number',
                        style: TextStyle(
                          color: isCurrent
                              ? const Color(0xFF2F6FFF)
                              : const Color(0xFF94A3B8),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 32,
                color: color.withValues(alpha: 0.3),
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 3, bottom: isLast ? 0 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDone
                              ? const Color(0xFF64748B)
                              : isCurrent
                              ? const Color(0xFF0F172A)
                              : const Color(0xFF94A3B8),
                          fontWeight: isCurrent
                              ? FontWeight.w900
                              : FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'Current',
                          style: TextStyle(
                            color: Color(0xFF2F6FFF),
                            fontWeight: FontWeight.w900,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                  ],
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
                if (scheduledArrival.isNotEmpty ||
                    scheduledDeparture.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 10,
                        color: Color(0xFFCBD5E1),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _buildScheduleLabel(
                          scheduledArrival,
                          scheduledDeparture,
                        ),
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
                if (actualArrival != null || actualDeparture != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 10,
                        color: Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _buildActualLabel(
                          actualArrival,
                          actualDeparture,
                          timeFmt,
                        ),
                        style: const TextStyle(
                          color: Color(0xFF16A34A),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _buildScheduleLabel(String arr, String dep) {
    final a = formatScheduleTimeLabel(arr);
    final d = formatScheduleTimeLabel(dep);
    if (a.isNotEmpty && d.isNotEmpty) return '$a – $d';
    if (a.isNotEmpty) return 'Arr. $a';
    if (d.isNotEmpty) return 'Dep. $d';
    return '';
  }

  String _buildActualLabel(DateTime? arr, DateTime? dep, DateFormat fmt) {
    if (arr != null && dep != null) {
      return '${fmt.format(arr)} – ${fmt.format(dep)}';
    }
    if (arr != null) return 'Arrived ${fmt.format(arr)}';
    if (dep != null) return 'Left ${fmt.format(dep)}';
    return '';
  }
}

// ── Shared Card Container ─────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
