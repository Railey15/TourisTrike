import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/models/convoy_state.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/services/convoy_barrier_service.dart';
import 'package:touristrike/core/services/route_polyline_service.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/shared/payment_dispute_screen.dart'
    show paymentDisputeReasons;
import 'package:touristrike/screens/tourist/tourist_messages_screen.dart';
import 'package:touristrike/widgets/convoy/convoy_roster_error_card.dart';
import 'package:touristrike/widgets/convoy/convoy_roster_strip.dart';
import 'package:touristrike/widgets/convoy/convoy_waiting_card.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================================
// UI CONSTANTS
// ============================================================================

const Color _primary = Color(0xFF2563EB);
const Color _primaryLight = Color(0xFF3BA9F5);

const Color _background = Color(0xFFF5F7FB);
const Color _surface = Colors.white;

const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);
const Color _subtle = Color(0xFF94A3B8);

const Color _border = Color(0xFFE5EBF3);
const Color _softBlue = Color(0xFFEAF3FF);

const Color _success = Color(0xFF16A34A);
const Color _successSoft = Color(0xFFECFDF5);

const Color _warning = Color(0xFFD97706);
const Color _warningSoft = Color(0xFFFFFBEB);

const Color _danger = Color(0xFFDC2626);
const Color _dangerSoft = Color(0xFFFEF2F2);

// ============================================================================
// SCREEN
// ============================================================================

class DriverPackageTrackingScreen extends StatefulWidget {
  const DriverPackageTrackingScreen({super.key, required this.activityId});

  final String activityId;

  @override
  State<DriverPackageTrackingScreen> createState() =>
      _DriverPackageTrackingScreenState();
}

class _DriverPackageTrackingScreenState
    extends State<DriverPackageTrackingScreen> {
  // =========================================================================
  // CONVOY STATE
  // =========================================================================

  List<ConvoyDriverSnapshot> _convoy = [];

  bool _convoyLoading = true;
  String? _convoyError;

  RealtimeChannel? _bookingDriversChannel;

  Timer? _convoyPollTimer;
  Timer? _convoyTicker;

  int _convoyConsecutiveFailures = 0;

  bool get _appearsOffline => _convoyConsecutiveFailures >= 2;

  // =========================================================================
  // CORE SERVICES / STATE
  // =========================================================================

  static final _apiKey = CitySpotSuggestionService.resolveApiKey();

  static const LatLng _defaultCenter = LatLng(14.9597, 120.9206);

  final RoutePolylineService _routeService = RoutePolylineService(
    apiKey: _apiKey,
  );

  static const double _proximityMeters = 150.0;

  // TODO: REMOVE TEST MODE BEFORE PRODUCTION
  static const bool kDriverActionTestMode = true;

  final TourisTrikeRepository _repo = TourisTrikeRepository();
  final SupabaseClient _supabase = Supabase.instance.client;

  String _bookingId = '';

  PackageActivity? _activity;
  PackageBooking? _booking;

  List<BookingItineraryItem> _spots = [];
  List<PaymentRecord> _paymentRecords = [];

  bool _loading = true;
  bool _actionBusy = false;

  String? _error;
  String? _eta;

  bool _isFollowingDriver = false;
  bool _isProgrammaticMove = false;

  BitmapDescriptor? _tricycleMarker;

  Position? _currentPosition;

  RealtimeChannel? _activityChannel;
  RealtimeChannel? _bookingChannel;
  RealtimeChannel? _itineraryChannel;

  StreamSubscription<Position>? _gpsSub;

  GoogleMapController? _mapCtrl;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  bool get _isBookingCancelled {
    final values = [
      _booking?.status,
      _booking?.bookingStatus,
      _activity?.status,
      _activity?.tourStatus,
    ];

    return values.any((value) => value?.toLowerCase() == 'cancelled');
  }

  // =========================================================================
  // LIFECYCLE
  // =========================================================================

  @override
  void initState() {
    super.initState();

    _initCustomMarkers();
    _load();
  }

  @override
  void dispose() {
    _activityChannel?.unsubscribe();
    _bookingChannel?.unsubscribe();
    _itineraryChannel?.unsubscribe();

    _bookingDriversChannel?.unsubscribe();
    _convoyPollTimer?.cancel();
    _convoyTicker?.cancel();

    _gpsSub?.cancel();
    _mapCtrl?.dispose();

    super.dispose();
  }

  // =========================================================================
  // MARKERS
  // =========================================================================

  Future<void> _initCustomMarkers() async {
    try {
      _tricycleMarker = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(35, 35)),
        'assets/icons/tricycle_marker.png',
      );

      if (!mounted) return;

      setState(() {});

      _buildMarkers();
    } catch (e) {
      debugPrint('[Markers] Failed to load custom markers: $e');
    }
  }

  // =========================================================================
  // DATA
  // =========================================================================

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

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

      var paymentRecords = <PaymentRecord>[];

      try {
        paymentRecords = await _repo.fetchPaymentRecordsFor(
          bookingId: bookingId,
        );
      } catch (_) {
        // Payment card is non-critical for initial loading.
      }

      if (!mounted) return;

      setState(() {
        _bookingId = bookingId;
        _activity = initialActivity;
        _booking = booking;
        _spots = spots;
        _paymentRecords = paymentRecords;
        _loading = false;
      });

      _debugTourState('load');

      _buildMarkers();
      _subscribeRealtime();

      if (_isBookingCancelled) {
        await _gpsSub?.cancel();
        _gpsSub = null;
      } else {
        _fetchCurrentRoute();
        _startGpsStreaming();
      }
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

    if (bookingId.isEmpty) {
      return;
    }

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

  // =========================================================================
  // GPS
  // =========================================================================

  Future<void> _startGpsStreaming() async {
    if (_isBookingCancelled) return;

    final ok = await _checkLocationPermission();

    if (!ok) {
      return;
    }

    await _gpsSub?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 8,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen((
      position,
    ) async {
      if (_activity == null) {
        return;
      }

      _currentPosition = position;

      try {
        await _repo.updateDriverLocation(
          activityId: widget.activityId,
          latitude: position.latitude,
          longitude: position.longitude,
        );

        await _repo.upsertDriverLiveLocation(
          activityId: widget.activityId,
          latitude: position.latitude,
          longitude: position.longitude,
          heading: position.heading,
          speed: position.speed,
        );

        if (!mounted) return;

        setState(() {
          _activity = PackageActivity({
            ..._activity!.row,
            'driver_latitude': position.latitude,
            'driver_longitude': position.longitude,
            'driver_last_seen': DateTime.now().toIso8601String(),
          });
        });

        _buildMarkers();

        if (_isFollowingDriver) {
          _animateCameraFollowing(
            LatLng(position.latitude, position.longitude),
            position.speed,
          );
        }
      } catch (_) {
        // Continue showing GPS even if backend update fails.
      }
    });
  }

  Future<bool> _checkLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return false;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  // =========================================================================
  // PROXIMITY
  // =========================================================================

  bool _isNearTarget(LatLng target) {
    final position = _currentPosition;

    if (position == null) {
      return true;
    }

    final distanceMeters = _haversineMeters(
      position.latitude,
      position.longitude,
      target.latitude,
      target.longitude,
    );

    return distanceMeters <= _proximityMeters;
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

  double _deg2rad(double degrees) {
    return degrees * (math.pi / 180);
  }

  // =========================================================================
  // ITINERARY GETTERS
  // =========================================================================

  bool get _allItineraryItemsCompleted =>
      _spots.isNotEmpty &&
      _spots.every((spot) => spot.spotStatus == 'completed');

  int get _incompleteItineraryItemsCount =>
      _spots.where((spot) => spot.spotStatus != 'completed').length;

  int get _completedItineraryItemsCount =>
      _spots.where((spot) => spot.spotStatus == 'completed').length;

  bool get _hasPickedUp =>
      _activity?.pickedUpAt != null || _booking?.pickedUpAt != null;

  BookingItineraryItem? get _currentItineraryItem =>
      _spots.where((spot) => spot.spotStatus != 'completed').firstOrNull;

  String get _currentSpotName =>
      _currentItineraryItem?.destinationName ?? 'Spot';

  String get _selectedCurrentActionLabel {
    final status = _activity?.tourStatus ?? '';

    final currentItem = _currentItineraryItem;

    if (status == 'completed') {
      return 'none';
    }

    if (status == 'driver_accepted') {
      return 'En Route to Pickup';
    }

    if (status == 'driver_en_route') {
      return 'Arrived at Pickup';
    }

    if (!_hasPickedUp) {
      return 'Mark Tourist Picked Up';
    }

    if (_allItineraryItemsCompleted) {
      if (status == 'ready_to_complete') {
        return 'Complete Trip';
      }

      return 'Arrived at Drop-off';
    }

    if (currentItem == null) {
      return 'reload itinerary';
    }

    if (currentItem.spotStatus == 'at_spot') {
      return 'Complete ${currentItem.destinationName}';
    }

    return 'Arrived at ${currentItem.destinationName}';
  }

  // =========================================================================
  // REFRESH
  // =========================================================================

  Future<void> _refreshTrackingState({String logTag = 'refresh'}) async {
    final bookingId = _bookingId.isNotEmpty
        ? _bookingId
        : (_activity?.bookingId.isNotEmpty == true ? _activity!.bookingId : '');

    if (bookingId.isEmpty) {
      return;
    }

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

    var paymentRecords = _paymentRecords;

    try {
      paymentRecords = await _repo.fetchPaymentRecordsFor(bookingId: bookingId);
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _activity = results[0] as PackageActivity?;

      _booking = results[1] as PackageBooking?;

      _spots = refreshedSpots;

      _paymentRecords = paymentRecords;
    });

    _debugTourState(logTag);

    if (_isBookingCancelled) {
      await _gpsSub?.cancel();
      _gpsSub = null;

      if (mounted) {
        setState(() {
          _markers = {};
          _polylines = {};
        });
      }
    } else {
      _buildMarkers();
      _fetchCurrentRoute();
    }
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

  // =========================================================================
  // MAP
  // =========================================================================

  void _buildMarkers() {
    if (_activity == null) {
      return;
    }

    final markers = <Marker>{};

    final pickup = _pickupLatLng();

    final dropoff = _dropoffLatLng();

    final driverPosition = _driverLatLng();

    if (pickup != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: 'Pickup Point',
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

    for (var index = 0; index < _spots.length; index++) {
      final spot = _spots[index];

      final lat = spot.latitude;
      final lng = spot.longitude;

      if (lat == 0 && lng == 0) {
        continue;
      }

      final isDone = spot.spotStatus == 'completed';

      final isCurrent = !isDone && spot.id == _currentItineraryItem?.id;

      markers.add(
        Marker(
          markerId: MarkerId('spot_$index'),
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isDone
                ? BitmapDescriptor.hueGreen
                : isCurrent
                ? BitmapDescriptor.hueOrange
                : BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: 'Stop ${index + 1}: ${spot.destinationName}',
          ),
        ),
      );
    }

    if (driverPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: driverPosition,
          icon:
              _tricycleMarker ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          rotation: _currentPosition?.heading ?? 0,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          infoWindow: const InfoWindow(title: 'You (Driver)'),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers = markers;
      });
    }
  }

  Future<void> _fetchCurrentRoute() async {
    if (_activity == null) {
      return;
    }

    final status = _activity!.tourStatus;

    final driverPosition = _driverLatLng();

    final pickupPosition = _pickupLatLng();

    final dropoffPosition = _dropoffLatLng();

    LatLng? origin;
    LatLng? destination;

    if (status == 'driver_accepted' || status == 'driver_en_route') {
      origin = driverPosition;
      destination = pickupPosition;
    } else if (status == 'driver_arrived') {
      origin = pickupPosition;

      destination = _spots.isNotEmpty ? _currentSpotLatLng() : dropoffPosition;
    } else if (status == 'picked_up' ||
        status == 'on_tour' ||
        status == 'en_route_to_spot' ||
        status == 'at_spot') {
      if (_allItineraryItemsCompleted) {
        origin = driverPosition;
        destination = dropoffPosition;
      } else {
        origin = driverPosition ?? pickupPosition;

        destination = _currentSpotLatLng();
      }
    } else if (status == 'en_route_to_dropoff' ||
        status == 'ready_to_complete') {
      origin = driverPosition;
      destination = dropoffPosition;
    } else {
      if (mounted) {
        setState(() {
          _polylines = {};
          _eta = null;
        });
      }

      return;
    }

    if (origin == null || destination == null) {
      if (mounted) {
        setState(() {
          _polylines = {};
          _eta = null;
        });
      }

      return;
    }

    final result = await _routeService.fetchRoute(origin, destination);

    if (!mounted) return;

    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: result.points,
          color: _primary,
          width: 5,
          geodesic: true,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      };

      _eta = result.durationText;
    });
  }

  LatLng? _driverLatLng() {
    final lat = _activity?.driverLatitude;

    final lng = _activity?.driverLongitude;

    if (lat == null || lng == null) {
      return null;
    }

    return LatLng(lat, lng);
  }

  LatLng? _pickupLatLng() {
    final lat = _booking?.pickupLatitude;

    final lng = _booking?.pickupLongitude;

    if (lat == null || lng == null) {
      return null;
    }

    return LatLng(lat, lng);
  }

  LatLng? _dropoffLatLng() {
    final lat = _booking?.dropoffLatitude;

    final lng = _booking?.dropoffLongitude;

    if (lat == null || lng == null) {
      return null;
    }

    return LatLng(lat, lng);
  }

  LatLng? _currentSpotLatLng() {
    final item = _currentItineraryItem;

    if (item == null) {
      return null;
    }

    if (item.latitude == 0 && item.longitude == 0) {
      return null;
    }

    return LatLng(item.latitude, item.longitude);
  }

  void _animateCameraFollowing(LatLng position, double speedMs) {
    if (!_isFollowingDriver) {
      return;
    }

    _isProgrammaticMove = true;

    _mapCtrl?.animateCamera(
      CameraUpdate.newLatLngZoom(position, _speedToZoom(speedMs)),
    );
  }

  double _speedToZoom(double speedMs) {
    final kmh = speedMs * 3.6;

    if (kmh < 10) {
      return 17;
    }

    if (kmh < 30) {
      return 15.5;
    }

    if (kmh < 60) {
      return 13.5;
    }

    return 12;
  }

  // =========================================================================
  // ACTION WRAPPER
  // =========================================================================

  Future<void> _doAction(Future<void> Function() action) async {
    if (_actionBusy) {
      return;
    }

    setState(() {
      _actionBusy = true;
    });

    try {
      await action();
    } catch (e) {
      if (mounted) {
        _showSnack('Error: $e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  // =========================================================================
  // TOUR ACTIONS
  // =========================================================================

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
    final pickup = _pickupLatLng();

    if (!kDriverActionTestMode && pickup != null && !_isNearTarget(pickup)) {
      _showSnack(
        'You must be within 150 m of the pickup point to mark arrival.',
        error: true,
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
    final pickup = _pickupLatLng();

    if (!kDriverActionTestMode && pickup != null && !_isNearTarget(pickup)) {
      _showSnack(
        'You must be at the pickup location to mark tourist as picked up.',
        error: true,
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
    final spotPosition = _currentSpotLatLng();

    if (!kDriverActionTestMode &&
        spotPosition != null &&
        !_isNearTarget(spotPosition)) {
      _showSnack(
        'You must be within 150 m of the spot to mark arrival.',
        error: true,
      );

      return;
    }

    final currentItem = _currentItineraryItem;

    final bookingId = _bookingId;

    if (currentItem != null && mounted) {
      setState(() {
        _spots = _spots.map((spot) {
          if (spot.id == currentItem.id) {
            return BookingItineraryItem({
              ...spot.row,
              'spot_status': 'at_spot',
              'actual_arrival_time': DateTime.now().toIso8601String(),
            });
          }

          return spot;
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
    BookingItineraryItem? currentItem = _currentItineraryItem;

    if (currentItem == null) {
      if (kDriverActionTestMode && _spots.isNotEmpty) {
        final atSpot = _spots
            .where((spot) => spot.spotStatus.trim().toLowerCase() == 'at_spot')
            .firstOrNull;

        currentItem =
            atSpot ??
            _spots
                .where(
                  (spot) => spot.spotStatus.trim().toLowerCase() != 'completed',
                )
                .firstOrNull;
      }

      if (currentItem == null) {
        await _refreshTrackingState(logTag: 'spot-complete-null');

        _showSnack('Refreshed. Please try again.');

        return;
      }
    }

    final spotName = currentItem.destinationName;

    final totalItems = _spots.length;

    final completedBefore = _spots
        .where((spot) => spot.spotStatus.trim().toLowerCase() == 'completed')
        .length;

    final itemId = currentItem.id?.toString() ?? '';

    debugPrint(
      '[SpotComplete] BEFORE: '
      'id=$itemId '
      'name=$spotName '
      'status=${currentItem.spotStatus} '
      'total=$totalItems '
      'completedBefore=$completedBefore '
      'bookingId=$_bookingId',
    );

    if (itemId.isEmpty || itemId == 'null') {
      _showSnack(
        'Cannot complete spot: item ID is missing. Try refreshing.',
        error: true,
      );

      await _refreshTrackingState(logTag: 'spot-complete-no-id');

      return;
    }

    if (mounted) {
      setState(() {
        _spots = _spots.map((spot) {
          if (spot.id?.toString() == itemId) {
            return BookingItineraryItem({
              ...spot.row,
              'spot_status': 'completed',
              'actual_departure_time': DateTime.now().toIso8601String(),
            });
          }

          return spot;
        }).toList();
      });
    }

    Map<String, dynamic> rpcResult;

    try {
      rpcResult = await _repo.completeCurrentItineraryItem(
        widget.activityId,
        itineraryItemId: itemId,
      );
    } catch (e) {
      await _refreshTrackingState(logTag: 'spot-complete-error');

      _showSnack('Error completing spot: $e', error: true);

      return;
    }

    _debugTourState('spot-complete-rpc', rpcResult: rpcResult);

    final completedNow =
        (rpcResult['completed_items'] as num?)?.toInt() ?? completedBefore + 1;

    final rpcTotal = (rpcResult['total_items'] as num?)?.toInt() ?? totalItems;

    final allCompleted = completedNow >= rpcTotal && rpcTotal > 0;

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
          _spots = _spots.map((spot) {
            final newStatus = statusMap[spot.id?.toString()];

            if (newStatus != null) {
              return BookingItineraryItem({
                ...spot.row,
                'spot_status': newStatus,
              });
            }

            return spot;
          }).toList();
        });
      }
    }

    if (allCompleted) {
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

      final nextItem = _spots
          .where((spot) => spot.spotStatus.trim().toLowerCase() != 'completed')
          .firstOrNull;

      _showSnack(
        '$spotName completed. '
        '$completedNow of $rpcTotal spots done.'
        '${nextItem != null ? ' Next: ${nextItem.destinationName}' : ''}',
      );
    }
  });

  Future<void> _markArrivedAtDropoff() => _doAction(() async {
    final dropoff = _dropoffLatLng();

    if (!kDriverActionTestMode && dropoff != null && !_isNearTarget(dropoff)) {
      _showSnack(
        'You must be within 150 m of the drop-off point.',
        error: true,
      );

      return;
    }

    await _repo.updateActivityTourStatus(
      activityId: widget.activityId,
      tourStatus: 'ready_to_complete',
      bookingStatus: 'on_tour',
      extra: {'dropped_off_at': DateTime.now().toIso8601String()},
    );

    _logStatus('dropped_off');

    await _refreshTrackingState(logTag: 'arrived-dropoff');

    _showSnack('Arrived at drop-off. Tap Complete Trip when ready.');
  });

  Future<void> _markCompleteTour() => _doAction(() async {
    if (!_allItineraryItemsCompleted) {
      _showSnack(
        'Complete all itinerary spots before finishing the tour.',
        error: true,
      );

      return;
    }

    final booking = _booking;

    final isAdvanced = (booking?.bookingType ?? 'same_day') == 'advanced';

    final remainingBalance = booking?.remainingBalance ?? 0;

    if (isAdvanced && remainingBalance > 0 && !_hasConfirmedRemainingBalance) {
      _showSnack(
        'Confirm the remaining balance payment before completing the tour.',
        error: true,
      );

      return;
    }

    try {
      await _repo.completePackageActivity(widget.activityId);
    } on PostgrestException catch (e) {
      if (e.message.contains('REMAINING_BALANCE_UNPAID')) {
        _showSnack(
          'Confirm the remaining balance payment before completing the tour.',
          error: true,
        );

        return;
      }

      rethrow;
    }

    await _refreshTrackingState(logTag: 'complete-tour');

    _logStatus('completed');

    _showSnack('Tour completed successfully.');
  });

  // =========================================================================
  // PAYMENTS
  // =========================================================================

  bool get _hasConfirmedRemainingBalance => _paymentRecords.any(
    (record) =>
        record.paymentStage == 'remaining_balance' &&
        record.status == 'confirmed',
  );

  Future<void> _confirmPayment(PaymentRecord record) async {
    try {
      await _repo.confirmPaymentRecord(record.id as String);

      await _repo.notifyUser(
        userId: record.payerId,
        title: 'Payment confirmed',
        body:
            'Your payment of ₱${record.amount.toStringAsFixed(2)} was confirmed.',
        type: 'payment_confirmed',
      );

      _showSnack('Payment confirmed.');

      await _refreshTrackingState(logTag: 'payment-confirmed');
    } catch (e) {
      _showSnack('Unable to confirm payment: $e', error: true);
    }
  }

  Future<void> _disputePayment(PaymentRecord record) async {
    final reason = await _pickDisputeReason();

    if (reason == null) {
      return;
    }

    try {
      await _repo.raisePaymentDispute(
        paymentRecordId: record.id as String,
        reason: reason,
      );

      _showSnack('Dispute filed. An admin will review it.');

      await _refreshTrackingState(logTag: 'payment-disputed');
    } catch (e) {
      _showSnack('Unable to file dispute: $e', error: true);
    }
  }

  Future<String?> _pickDisputeReason() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCE4EE),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    CircleAvatar(
                      radius: 21,
                      backgroundColor: _dangerSoft,
                      child: Icon(
                        Icons.report_problem_outlined,
                        color: _danger,
                        size: 20,
                      ),
                    ),
                    SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Report Payment Problem',
                            style: TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Select the issue you encountered.',
                            style: TextStyle(
                              color: _muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...paymentDisputeReasons.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Material(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => Navigator.pop(context, entry.key),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(13),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: const TextStyle(
                                    color: _ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: _subtle,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================================================================
  // LOGGING
  // =========================================================================

  void _logStatus(String status, {int? spotIndex}) {
    final activity = _activity;

    if (activity == null) {
      return;
    }

    final position = _currentPosition;

    _repo
        .logTripStatus(
          activityId: widget.activityId,
          bookingId: activity.bookingId,
          status: status,
          spotIndex: spotIndex,
          latitude: position?.latitude,
          longitude: position?.longitude,
        )
        .catchError((_) {});
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? _danger : const Color(0xFF1E293B),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  // =========================================================================
  // TOURIST CONTACT
  // =========================================================================

  Future<void> _openTouristChat() async {
    final activity = _activity;

    if (activity == null) {
      _showSnack('Activity not loaded yet.', error: true);

      return;
    }

    final touristId = activity.touristId;

    if (touristId.isEmpty) {
      _showSnack('Tourist info not available.', error: true);

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
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .join(' ');

      final touristPhone = (tourist?['mobile'] as String? ?? '').trim();

      final touristAvatar = (tourist?['profile_image_url'] as String? ?? '')
          .trim();

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
      if (mounted) {
        _showSnack('Unable to open chat: $e', error: true);
      }
    }
  }

  Future<void> _callTourist() async {
    final tourist = _activity?.touristRow;

    final phone = (tourist?['mobile'] as String? ?? '').trim();

    if (phone.isEmpty) {
      _showSnack('Tourist phone number not available.', error: true);

      return;
    }

    final uri = Uri.parse('tel:$phone');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnack('Unable to launch phone dialer.', error: true);
    }
  }

  // =========================================================================
  // BOTTOM PRIMARY ACTION
  // =========================================================================

  _PrimaryTourAction? _currentPrimaryAction() {
    final status = _activity?.tourStatus ?? '';

    switch (status) {
      case 'driver_accepted':
        return _PrimaryTourAction(
          label: 'Start Navigation to Pickup',
          description: 'Begin heading to the tourist pickup location.',
          icon: Icons.navigation_rounded,
          onTap: _markEnRoute,
        );

      case 'driver_en_route':
        return _PrimaryTourAction(
          label: 'Arrived at Pickup',
          description: 'Confirm once you reach the tourist.',
          icon: Icons.location_on_rounded,
          onTap: _markArrived,
        );

      case 'driver_arrived':
        return _PrimaryTourAction(
          label: 'Mark Tourist Picked Up',
          description: 'Confirm the tourist is onboard.',
          icon: Icons.groups_rounded,
          onTap: _markPickedUp,
        );

      case 'picked_up':
      case 'on_tour':
      case 'en_route_to_spot':
      case 'at_spot':
      case 'en_route_to_dropoff':
      case 'ready_to_complete':
        if (!kDriverActionTestMode && !_hasPickedUp) {
          return _PrimaryTourAction(
            label: 'Mark Tourist Picked Up',
            description: 'Confirm the tourist is onboard first.',
            icon: Icons.groups_rounded,
            onTap: _markPickedUp,
          );
        }

        if (_allItineraryItemsCompleted) {
          if (status == 'ready_to_complete') {
            return _PrimaryTourAction(
              label: 'Complete Trip',
              description: 'Finish this tour assignment.',
              icon: Icons.task_alt_rounded,
              onTap: _markCompleteTour,
            );
          }

          return _PrimaryTourAction(
            label: 'Arrived at Drop-off',
            description: 'Confirm once the tourist reaches the final drop-off.',
            icon: Icons.flag_rounded,
            onTap: _markArrivedAtDropoff,
          );
        }

        final currentItem = _currentItineraryItem;

        if (!kDriverActionTestMode && currentItem == null) {
          return null;
        }

        if (currentItem?.spotStatus == 'at_spot') {
          return _PrimaryTourAction(
            label: 'Complete ${currentItem?.destinationName ?? 'Current Spot'}',
            description:
                'Mark this destination complete when the tourist is ready to leave.',
            icon: Icons.check_circle_rounded,
            onTap: _markSpotComplete,
          );
        }

        return _PrimaryTourAction(
          label: 'Arrived at ${currentItem?.destinationName ?? 'Current Spot'}',
          description:
              'Confirm once you are at the next itinerary destination.',
          icon: Icons.place_rounded,
          onTap: _markAtSpot,
        );

      default:
        return null;
    }
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const _TrackingLoadingView()
            : _error != null
            ? _buildError()
            : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    return Column(
      children: [
        _DriverTrackingTopBar(
          title: 'Tour Navigation',
          onBack: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _TrackingErrorCard(message: _error!, onRetry: _load),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isBookingCancelled) {
      return _buildCancelledContent();
    }

    final activity = _activity!;

    final status = activity.tourStatus;

    final completed = status == 'completed';

    final pendingPayments = _paymentRecords
        .where((record) => record.status == 'pending_confirmation')
        .toList();

    final primaryAction = _currentPrimaryAction();

    return Column(
      children: [
        _DriverTrackingTopBar(
          title: 'Tour Navigation',
          eta: _eta,
          onBack: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _refreshTrackingState(logTag: 'manual-refresh'),
            color: _primary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
              children: [
                _ModernStatusCard(
                  status: status,
                  completedCount: _completedItineraryItemsCount,
                  totalCount: _spots.length,
                ),
                const SizedBox(height: 12),
                _NavigationMapCard(
                  markers: _markers,
                  polylines: _polylines,
                  initialTarget:
                      _driverLatLng() ?? _pickupLatLng() ?? _defaultCenter,
                  isFollowing: _isFollowingDriver,
                  status: status,
                  onMapCreated: (controller) {
                    _mapCtrl = controller;
                  },
                  onCameraMoveStarted: () {
                    if (!_isProgrammaticMove && _isFollowingDriver) {
                      setState(() {
                        _isFollowingDriver = false;
                      });
                    }
                  },
                  onCameraIdle: () {
                    _isProgrammaticMove = false;
                  },
                  onPickupTap: () {
                    setState(() {
                      _isFollowingDriver = false;
                    });

                    final pickup = _pickupLatLng();

                    if (pickup == null) {
                      _showSnack('Pickup location unavailable.', error: true);

                      return;
                    }

                    _isProgrammaticMove = true;

                    _mapCtrl?.animateCamera(
                      CameraUpdate.newLatLngZoom(pickup, 17),
                    );
                  },
                  onDriverTap: () {
                    setState(() {
                      _isFollowingDriver = true;
                    });

                    final position = _currentPosition;

                    if (position != null) {
                      _animateCameraFollowing(
                        LatLng(position.latitude, position.longitude),
                        position.speed,
                      );

                      return;
                    }

                    final driver = _driverLatLng();

                    if (driver != null) {
                      _isProgrammaticMove = true;

                      _mapCtrl?.animateCamera(
                        CameraUpdate.newLatLngZoom(driver, 15),
                      );
                    }
                  },
                ),
                const SizedBox(height: 14),
                if (!completed && _spots.isNotEmpty)
                  _CurrentDestinationCard(
                    currentItem: _currentItineraryItem,
                    completedCount: _completedItineraryItemsCount,
                    totalCount: _spots.length,
                    eta: _eta,
                    status: status,
                  ),
                if (!completed && _spots.isNotEmpty) const SizedBox(height: 14),
                if (_spots.isNotEmpty)
                  _ModernSpotProgressCard(
                    spots: _spots,
                    currentItemId: _currentItineraryItem?.id.toString(),
                    status: status,
                  ),
                if (_spots.isNotEmpty) const SizedBox(height: 14),
                _ModernTouristCard(
                  activity: activity,
                  onMessage: _openTouristChat,
                  onCall: _callTourist,
                ),
                const SizedBox(height: 14),
                _ModernLocationsCard(booking: _booking, status: status),
                const SizedBox(height: 14),
                _ModernBookingCard(booking: _booking, activity: activity),
                if (pendingPayments.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ModernPaymentsCard(
                    records: pendingPayments,
                    onConfirm: _confirmPayment,
                    onDispute: _disputePayment,
                  ),
                ],
                if (kDriverActionTestMode && !completed) ...[
                  const SizedBox(height: 14),
                  const _TestModeNotice(),
                ],
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
        _PersistentDriverActionBar(
          completed: completed,
          busy: _actionBusy,
          action: primaryAction,
        ),
      ],
    );
  }

  Widget _buildCancelledContent() {
    final booking = _booking;

    final reason = booking?.cancelledReason.trim();

    return Column(
      children: [
        _DriverTrackingTopBar(
          title: 'Tour Navigation',
          onBack: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: RefreshIndicator(
            color: _primary,
            onRefresh: () => _refreshTrackingState(logTag: 'cancelled-refresh'),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 29,
                        backgroundColor: _dangerSoft,
                        child: Icon(
                          Icons.event_busy_rounded,
                          color: _danger,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Booking Cancelled',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'The tourist cancelled this booking.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted),
                      ),
                      if (reason != null && reason.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Cancellation reason',
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                reason,
                                style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Return to Available Bookings'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: _primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// TOP BAR
// ============================================================================

class _DriverTrackingTopBar extends StatelessWidget {
  const _DriverTrackingTopBar({
    required this.title,
    required this.onBack,
    this.eta,
  });

  final String title;
  final String? eta;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(color: _background),
      child: Row(
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(13),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _ink,
                  size: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          const ContainerTitle(),
          if (eta != null && eta!.trim().isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _softBlue,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_rounded, color: _primary, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    eta!,
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ContainerTitle extends StatelessWidget {
  const ContainerTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return const Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tour Navigation',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 17.5,
              letterSpacing: -0.2,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Live driver tracking',
            style: TextStyle(
              color: _subtle,
              fontWeight: FontWeight.w600,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// STATUS CARD
// ============================================================================

class _ModernStatusCard extends StatelessWidget {
  const _ModernStatusCard({
    required this.status,
    required this.completedCount,
    required this.totalCount,
  });

  final String status;
  final int completedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final info = _statusVisual(status);

    final progress = totalCount <= 0 ? 0.0 : completedCount / totalCount;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [info.gradientStart, info.gradientEnd],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: info.gradientStart.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(info.icon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        info.badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 8.5,
                          letterSpacing: 0.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      info.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16.5,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      info.description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w600,
                        fontSize: 10.2,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (totalCount > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  '$completedCount of $totalCount destinations completed',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                    fontSize: 9.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// NAVIGATION MAP
// ============================================================================

class _NavigationMapCard extends StatelessWidget {
  const _NavigationMapCard({
    required this.markers,
    required this.polylines,
    required this.initialTarget,
    required this.isFollowing,
    required this.status,
    required this.onMapCreated,
    required this.onCameraMoveStarted,
    required this.onCameraIdle,
    required this.onPickupTap,
    required this.onDriverTap,
  });

  final Set<Marker> markers;
  final Set<Polyline> polylines;

  final LatLng initialTarget;

  final bool isFollowing;
  final String status;

  final ValueChanged<GoogleMapController> onMapCreated;

  final VoidCallback onCameraMoveStarted;

  final VoidCallback onCameraIdle;
  final VoidCallback onPickupTap;
  final VoidCallback onDriverTap;

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.30).clamp(
      235.0,
      300.0,
    );

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned.fill(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: initialTarget,
                  zoom: 14.5,
                ),
                markers: markers,
                polylines: polylines,
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: true,
                mapToolbarEnabled: false,
                rotateGesturesEnabled: true,
                scrollGesturesEnabled: true,
                zoomGesturesEnabled: true,
                tiltGesturesEnabled: true,
                onMapCreated: onMapCreated,
                onCameraMoveStarted: onCameraMoveStarted,
                onCameraIdle: onCameraIdle,
                gestureRecognizers: {
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFollowing
                          ? Icons.navigation_rounded
                          : Icons.map_outlined,
                      color: _primary,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isFollowing ? 'FOLLOWING DRIVER' : 'TOUR ROUTE',
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 8.5,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Column(
                children: [
                  _MapRoundButton(
                    icon: Icons.hail_rounded,
                    tooltip: 'Pickup point',
                    color: _success,
                    onTap: onPickupTap,
                  ),
                  const SizedBox(height: 8),
                  _MapRoundButton(
                    icon: Icons.my_location_rounded,
                    tooltip: 'Follow driver',
                    color: _primary,
                    active: isFollowing,
                    onTap: onDriverTap,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              right: 70,
              child: _MapLegendBar(status: status),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapRoundButton extends StatelessWidget {
  const _MapRoundButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? color : Colors.white.withValues(alpha: 0.96),
        elevation: 3,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: active ? Colors.white : color, size: 19),
          ),
        ),
      ),
    );
  }
}

class _MapLegendBar extends StatelessWidget {
  const _MapLegendBar({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(color: _primary, text: 'You'),
          SizedBox(width: 10),
          _LegendItem(color: Color(0xFFF59E0B), text: 'Current'),
          SizedBox(width: 10),
          Flexible(
            child: _LegendItem(color: _success, text: 'Done'),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: _muted,
            fontWeight: FontWeight.w700,
            fontSize: 8.5,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// CURRENT DESTINATION CARD
// ============================================================================

class _CurrentDestinationCard extends StatelessWidget {
  const _CurrentDestinationCard({
    required this.currentItem,
    required this.completedCount,
    required this.totalCount,
    required this.eta,
    required this.status,
  });

  final BookingItineraryItem? currentItem;

  final int completedCount;
  final int totalCount;

  final String? eta;
  final String status;

  @override
  Widget build(BuildContext context) {
    if (currentItem == null) {
      return const SizedBox.shrink();
    }

    final atSpot = currentItem!.spotStatus == 'at_spot';

    final index = completedCount + 1;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFCFE2FF), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: atSpot ? _warningSoft : _softBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              atSpot ? Icons.place_rounded : Icons.navigation_rounded,
              color: atSpot ? _warning : _primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  atSpot ? 'CURRENT DESTINATION' : 'NEXT DESTINATION',
                  style: TextStyle(
                    color: atSpot ? _warning : _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 8.5,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  currentItem!.destinationName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
                if (currentItem!.destinationAddress.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    currentItem!.destinationAddress,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 9.8,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MiniMetadataChip(
                      icon: Icons.flag_outlined,
                      text: 'Stop $index of $totalCount',
                    ),
                    if (eta != null && eta!.trim().isNotEmpty)
                      _MiniMetadataChip(
                        icon: Icons.schedule_rounded,
                        text: eta!,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetadataChip extends StatelessWidget {
  const _MiniMetadataChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _muted, size: 11),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
              fontSize: 8.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MODERN ITINERARY CARD
// ============================================================================

class _ModernSpotProgressCard extends StatelessWidget {
  const _ModernSpotProgressCard({
    required this.spots,
    required this.currentItemId,
    required this.status,
  });

  final List<BookingItineraryItem> spots;

  final String? currentItemId;
  final String status;

  @override
  Widget build(BuildContext context) {
    final completed = spots
        .where((spot) => spot.spotStatus == 'completed')
        .length;

    final progress = spots.isEmpty ? 0.0 : completed / spots.length;

    return _ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.route_outlined,
                  color: _primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tour Itinerary',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Follow each destination in order',
                      style: TextStyle(
                        color: _subtle,
                        fontWeight: FontWeight.w600,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$completed/${spots.length}',
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: const Color(0xFFE8EDF4),
              color: _primary,
            ),
          ),
          const SizedBox(height: 15),
          ...List.generate(spots.length, (index) {
            final spot = spots[index];

            final done = spot.spotStatus == 'completed';

            final current =
                !done &&
                spot.id.toString() == currentItemId &&
                _isTourActiveStatus(status);

            return _ModernSpotRow(
              number: index + 1,
              spot: spot,
              isDone: done,
              isCurrent: current,
              isLast: index == spots.length - 1,
            );
          }),
        ],
      ),
    );
  }

  bool _isTourActiveStatus(String status) {
    return status == 'picked_up' ||
        status == 'on_tour' ||
        status == 'en_route_to_spot' ||
        status == 'at_spot';
  }
}

class _ModernSpotRow extends StatelessWidget {
  const _ModernSpotRow({
    required this.number,
    required this.spot,
    required this.isDone,
    required this.isCurrent,
    required this.isLast,
  });

  final int number;
  final BookingItineraryItem spot;
  final bool isDone;
  final bool isCurrent;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final markerColor = isDone
        ? _success
        : isCurrent
        ? _primary
        : const Color(0xFFCBD5E1);

    final timeFormat = DateFormat('h:mm a');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDone
                      ? _successSoft
                      : isCurrent
                      ? _softBlue
                      : const Color(0xFFF4F6F9),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: markerColor,
                    width: isCurrent ? 2 : 1.5,
                  ),
                ),
                child: isDone
                    ? const Icon(Icons.check_rounded, color: _success, size: 15)
                    : Text(
                        '$number',
                        style: TextStyle(
                          color: isCurrent ? _primary : _subtle,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 47,
                  color: markerColor.withValues(alpha: 0.22),
                ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: isLast ? 0 : 9),
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
            decoration: BoxDecoration(
              color: isCurrent ? const Color(0xFFF7FAFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: isCurrent
                  ? Border.all(color: const Color(0xFFD5E5FF))
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        spot.destinationName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDone ? _muted : _ink,
                          fontWeight: isCurrent
                              ? FontWeight.w900
                              : FontWeight.w800,
                          fontSize: 12.5,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _softBlue,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'CURRENT',
                          style: TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 7.5,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                  ],
                ),
                if (spot.destinationAddress.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    spot.destinationAddress,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 9.5,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    if (spot.arrivalTime.isNotEmpty ||
                        spot.departureTime.isNotEmpty)
                      _SmallTimingChip(
                        icon: Icons.schedule_rounded,
                        text: _buildScheduleLabel(
                          spot.arrivalTime,
                          spot.departureTime,
                        ),
                      ),
                    if (spot.estimatedStayDurationMinutes > 0)
                      _SmallTimingChip(
                        icon: Icons.hourglass_bottom_rounded,
                        text: '${spot.estimatedStayDurationMinutes} min',
                      ),
                  ],
                ),
                if (spot.actualArrivalTime != null) ...[
                  const SizedBox(height: 6),
                  _ActualTimeBadge(
                    icon: Icons.location_on_rounded,
                    label: 'Arrived',
                    time: timeFormat.format(spot.actualArrivalTime!.toLocal()),
                    color: _primary,
                  ),
                ],
                if (spot.actualDepartureTime != null) ...[
                  const SizedBox(height: 4),
                  _ActualTimeBadge(
                    icon: Icons.check_circle_rounded,
                    label: 'Completed',
                    time: timeFormat.format(
                      spot.actualDepartureTime!.toLocal(),
                    ),
                    color: _success,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _buildScheduleLabel(String arrival, String departure) {
    final a = formatScheduleTimeLabel(arrival);

    final d = formatScheduleTimeLabel(departure);

    if (a.isNotEmpty && d.isNotEmpty) {
      return '$a – $d';
    }

    if (a.isNotEmpty) {
      return 'Arr. $a';
    }

    if (d.isNotEmpty) {
      return 'Dep. $d';
    }

    return '';
  }
}

class _SmallTimingChip extends StatelessWidget {
  const _SmallTimingChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _subtle, size: 10),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
              fontSize: 8.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActualTimeBadge extends StatelessWidget {
  const _ActualTimeBadge({
    required this.icon,
    required this.label,
    required this.time,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String time;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            '$label at $time',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 8.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TOURIST CARD
// ============================================================================

class _ModernTouristCard extends StatelessWidget {
  const _ModernTouristCard({
    required this.activity,
    required this.onMessage,
    required this.onCall,
  });

  final PackageActivity activity;

  final VoidCallback onMessage;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final tourist = activity.touristRow;

    final name = _name(tourist);

    final image = (tourist?['profile_image_url'] as String? ?? '').trim();

    final phone = (tourist?['mobile'] as String? ?? '').trim();

    return _ModernCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: _softBlue,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD4E5FF)),
            ),
            child: ClipOval(
              child: image.isNotEmpty
                  ? Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _TouristAvatarFallback(),
                    )
                  : const _TouristAvatarFallback(),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOUR TOURIST',
                  style: TextStyle(
                    color: _subtle,
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                    letterSpacing: 0.55,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  phone.isEmpty ? 'Phone number unavailable' : phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _ContactButton(
            icon: Icons.call_outlined,
            tooltip: 'Call tourist',
            color: _success,
            onTap: onCall,
          ),
          const SizedBox(width: 7),
          _ContactButton(
            icon: Icons.chat_bubble_outline_rounded,
            tooltip: 'Message tourist',
            color: _primary,
            onTap: onMessage,
          ),
        ],
      ),
    );
  }

  String _name(Json? row) {
    if (row == null) {
      return 'Tourist';
    }

    final full = (row['full_name'] ?? '').toString().trim();

    if (full.isNotEmpty) {
      return full;
    }

    final first = (row['first_name'] ?? '').toString().trim();

    final last = (row['last_name'] ?? '').toString().trim();

    final name = '$first $last'.trim();

    return name.isNotEmpty ? name : 'Tourist';
  }
}

class _TouristAvatarFallback extends StatelessWidget {
  const _TouristAvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _softBlue,
      alignment: Alignment.center,
      child: const Icon(Icons.person_rounded, color: _primary, size: 25),
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: color, size: 18),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// LOCATION CARD
// ============================================================================

class _ModernLocationsCard extends StatelessWidget {
  const _ModernLocationsCard({required this.booking, required this.status});

  final PackageBooking? booking;
  final String status;

  @override
  Widget build(BuildContext context) {
    final pickup = (booking?.pickupAddress ?? '').trim();

    final dropoff = (booking?.dropoffAddress ?? '').trim();

    if (pickup.isEmpty && dropoff.isEmpty) {
      return const SizedBox.shrink();
    }

    final pickupComplete =
        status == 'driver_arrived' ||
        status == 'picked_up' ||
        status == 'on_tour' ||
        status == 'en_route_to_spot' ||
        status == 'at_spot' ||
        status == 'en_route_to_dropoff' ||
        status == 'ready_to_complete' ||
        status == 'completed';

    final dropoffComplete =
        status == 'ready_to_complete' || status == 'completed';

    return _ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            icon: Icons.route_outlined,
            title: 'Pickup & Drop-off',
            subtitle: 'Main route for this tour',
          ),
          const SizedBox(height: 14),
          if (pickup.isNotEmpty)
            _LocationTimelineItem(
              color: _success,
              icon: pickupComplete
                  ? Icons.check_rounded
                  : Icons.trip_origin_rounded,
              label: 'PICKUP',
              address: pickup,
              status: pickupComplete ? 'Completed' : 'Tourist pickup',
              complete: pickupComplete,
              hasLine: dropoff.isNotEmpty,
            ),
          if (dropoff.isNotEmpty)
            _LocationTimelineItem(
              color: _danger,
              icon: dropoffComplete
                  ? Icons.check_rounded
                  : Icons.location_on_rounded,
              label: 'DROP-OFF',
              address: dropoff,
              status: dropoffComplete ? 'Completed' : 'Final destination',
              complete: dropoffComplete,
              hasLine: false,
            ),
        ],
      ),
    );
  }
}

class _LocationTimelineItem extends StatelessWidget {
  const _LocationTimelineItem({
    required this.color,
    required this.icon,
    required this.label,
    required this.address,
    required this.status,
    required this.complete,
    required this.hasLine,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String address;
  final String status;
  final bool complete;
  final bool hasLine;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 15),
              ),
              if (hasLine)
                Container(width: 2, height: 34, color: const Color(0xFFDCE5F0)),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: hasLine ? 11 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _subtle,
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  address,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status,
                  style: TextStyle(
                    color: complete ? _success : _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// BOOKING CARD
// ============================================================================

class _ModernBookingCard extends StatelessWidget {
  const _ModernBookingCard({required this.booking, required this.activity});

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

    final downpayment = b?.downpaymentAmount ?? 0;

    final remaining = b?.remainingBalance ?? 0;

    final requiredDrivers = b?.requiredDrivers ?? 1;

    final passengerCount = adults + children;

    return _ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            icon: Icons.receipt_long_outlined,
            title: 'Booking Summary',
            subtitle: 'Important trip and payment information',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _BookingMetric(
                  label: 'PASSENGERS',
                  value: '$passengerCount',
                  icon: Icons.groups_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BookingMetric(
                  label: 'TRICYCLES',
                  value: '$requiredDrivers',
                  icon: Icons.electric_rickshaw_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BookingMetric(
                  label: 'TOTAL',
                  value: '₱${total.toStringAsFixed(0)}',
                  icon: Icons.payments_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Divider(color: Color(0xFFEDF1F6), height: 1),
          const SizedBox(height: 12),
          _BookingInfoLine(
            icon: Icons.calendar_today_outlined,
            label: 'Travel Date',
            value: travelDate != null
                ? DateFormat('MMMM d, yyyy').format(travelDate)
                : rawTravelDate.isNotEmpty
                ? rawTravelDate
                : '—',
          ),
          const SizedBox(height: 9),
          _BookingInfoLine(
            icon: Icons.event_outlined,
            label: 'Booking Type',
            value: type == 'advanced' ? 'Advanced Booking' : 'Same-Day Booking',
          ),
          if (type == 'advanced') ...[
            const SizedBox(height: 9),
            _BookingInfoLine(
              icon: Icons.price_check_outlined,
              label: 'Down Payment',
              value: '₱${downpayment.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 9),
            _BookingInfoLine(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Remaining Balance',
              value: remaining > 0
                  ? '₱${remaining.toStringAsFixed(2)}'
                  : 'Settled',
              valueColor: remaining > 0 ? _warning : _success,
            ),
          ],
        ],
      ),
    );
  }
}

class _BookingMetric extends StatelessWidget {
  const _BookingMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: _primary, size: 16),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _subtle,
              fontWeight: FontWeight.w800,
              fontSize: 7.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingInfoLine extends StatelessWidget {
  const _BookingInfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            color: _softBlue,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _primary, size: 14),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _subtle,
                  fontWeight: FontWeight.w700,
                  fontSize: 8.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// PAYMENTS
// ============================================================================

class _ModernPaymentsCard extends StatelessWidget {
  const _ModernPaymentsCard({
    required this.records,
    required this.onConfirm,
    required this.onDispute,
  });

  final List<PaymentRecord> records;

  final ValueChanged<PaymentRecord> onConfirm;

  final ValueChanged<PaymentRecord> onDispute;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE3A7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _warningSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.payments_outlined,
                  color: _warning,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment Confirmation',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Review payments sent directly by the tourist',
                      style: TextStyle(
                        color: _subtle,
                        fontWeight: FontWeight.w600,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ...records.map(
            (record) => _PendingPaymentItem(
              record: record,
              onConfirm: () => onConfirm(record),
              onDispute: () => onDispute(record),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingPaymentItem extends StatelessWidget {
  const _PendingPaymentItem({
    required this.record,
    required this.onConfirm,
    required this.onDispute,
  });

  final PaymentRecord record;

  final VoidCallback onConfirm;
  final VoidCallback onDispute;

  @override
  Widget build(BuildContext context) {
    final stage = record.paymentStage == 'down_payment'
        ? 'Down payment'
        : record.paymentStage == 'remaining_balance'
        ? 'Remaining balance'
        : 'Payment';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _warningSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '₱${record.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$stage • ${record.paymentMethod.toUpperCase()}',
                      style: const TextStyle(
                        color: Color(0xFF8A5A16),
                        fontWeight: FontWeight.w700,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'VERIFY',
                  style: TextStyle(
                    color: _warning,
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          if (record.externalReferenceNo.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  color: _muted,
                  size: 13,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Ref: ${record.externalReferenceNo}',
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDispute,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _danger,
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Report',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: _success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TEST MODE
// ============================================================================

class _TestModeNotice extends StatelessWidget {
  const _TestModeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: Color(0xFFEA580C), size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Driver action test mode is enabled. Proximity restrictions are temporarily bypassed.',
              style: TextStyle(
                color: Color(0xFF9A4D12),
                fontWeight: FontWeight.w600,
                fontSize: 9.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PERSISTENT ACTION BAR
// ============================================================================

class _PersistentDriverActionBar extends StatelessWidget {
  const _PersistentDriverActionBar({
    required this.completed,
    required this.busy,
    required this.action,
  });

  final bool completed;
  final bool busy;

  final _PrimaryTourAction? action;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: completed
          ? Container(
              height: 52,
              decoration: BoxDecoration(
                color: _successSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, color: _success, size: 19),
                  SizedBox(width: 7),
                  Text(
                    'TOUR COMPLETED',
                    style: TextStyle(
                      color: Color(0xFF166534),
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            )
          : action == null
          ? const SizedBox.shrink()
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        action!.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _subtle,
                          fontWeight: FontWeight.w600,
                          fontSize: 8.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_primary, _primaryLight],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: _primary.withValues(alpha: 0.19),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: busy ? null : action!.onTap,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(action!.icon, size: 18),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    action!.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PrimaryTourAction {
  const _PrimaryTourAction({
    required this.label,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String description;

  final IconData icon;

  final VoidCallback onTap;
}

// ============================================================================
// SHARED CARD HEADER
// ============================================================================

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 37,
          height: 37,
          decoration: BoxDecoration(
            color: _softBlue,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _primary, size: 17),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _subtle,
                  fontWeight: FontWeight.w600,
                  fontSize: 9.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// CARD
// ============================================================================

class _ModernCard extends StatelessWidget {
  const _ModernCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ============================================================================
// STATUS VISUAL
// ============================================================================

class _StatusVisual {
  const _StatusVisual({
    required this.badge,
    required this.title,
    required this.description,
    required this.icon,
    required this.gradientStart,
    required this.gradientEnd,
  });

  final String badge;
  final String title;
  final String description;

  final IconData icon;

  final Color gradientStart;
  final Color gradientEnd;
}

_StatusVisual _statusVisual(String status) {
  switch (status) {
    case 'driver_accepted':
      return const _StatusVisual(
        badge: 'BOOKING ACCEPTED',
        title: 'Ready to start',
        description:
            'Review the pickup point and begin heading to the tourist when ready.',
        icon: Icons.check_circle_outline_rounded,
        gradientStart: Color(0xFF2563EB),
        gradientEnd: Color(0xFF3B82F6),
      );

    case 'driver_en_route':
      return const _StatusVisual(
        badge: 'EN ROUTE',
        title: 'Heading to pickup',
        description: 'Navigate safely to the tourist pickup location.',
        icon: Icons.navigation_rounded,
        gradientStart: Color(0xFF5B21B6),
        gradientEnd: Color(0xFF8B5CF6),
      );

    case 'driver_arrived':
      return const _StatusVisual(
        badge: 'AT PICKUP',
        title: 'You have arrived',
        description:
            'Meet the tourist and confirm pickup when everyone is ready.',
        icon: Icons.location_on_outlined,
        gradientStart: Color(0xFF0891B2),
        gradientEnd: Color(0xFF22D3EE),
      );

    case 'picked_up':
      return const _StatusVisual(
        badge: 'TOURIST PICKED UP',
        title: 'Tour starting',
        description:
            'Follow the itinerary and proceed to the first destination.',
        icon: Icons.groups_outlined,
        gradientStart: Color(0xFF059669),
        gradientEnd: Color(0xFF10B981),
      );

    case 'on_tour':
    case 'en_route_to_spot':
      return const _StatusVisual(
        badge: 'TOUR IN PROGRESS',
        title: 'Follow the itinerary',
        description:
            'Proceed through each selected destination in the planned order.',
        icon: Icons.route_rounded,
        gradientStart: Color(0xFF2563EB),
        gradientEnd: Color(0xFF38BDF8),
      );

    case 'at_spot':
      return const _StatusVisual(
        badge: 'AT DESTINATION',
        title: 'Tourist is exploring',
        description:
            'Mark this destination complete once the tourist is ready to continue.',
        icon: Icons.place_outlined,
        gradientStart: Color(0xFFEA580C),
        gradientEnd: Color(0xFFF59E0B),
      );

    case 'en_route_to_dropoff':
      return const _StatusVisual(
        badge: 'FINAL LEG',
        title: 'Heading to drop-off',
        description:
            'All tour spots are completed. Proceed to the final drop-off point.',
        icon: Icons.flag_outlined,
        gradientStart: Color(0xFF6D28D9),
        gradientEnd: Color(0xFF8B5CF6),
      );

    case 'ready_to_complete':
      return const _StatusVisual(
        badge: 'READY TO FINISH',
        title: 'Tour finished',
        description: 'Review any remaining payment and complete the trip.',
        icon: Icons.task_alt_rounded,
        gradientStart: Color(0xFF0F766E),
        gradientEnd: Color(0xFF14B8A6),
      );

    case 'completed':
      return const _StatusVisual(
        badge: 'COMPLETED',
        title: 'Tour completed',
        description: 'This package tour has been completed successfully.',
        icon: Icons.check_circle_rounded,
        gradientStart: Color(0xFF15803D),
        gradientEnd: Color(0xFF22C55E),
      );

    default:
      return const _StatusVisual(
        badge: 'TOUR STATUS',
        title: 'Waiting to begin',
        description: 'Review the assignment information below.',
        icon: Icons.hourglass_empty_rounded,
        gradientStart: Color(0xFF475569),
        gradientEnd: Color(0xFF64748B),
      );
  }
}

// ============================================================================
// LOADING
// ============================================================================

class _TrackingLoadingView extends StatelessWidget {
  const _TrackingLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 31,
            height: 31,
            child: CircularProgressIndicator(color: _primary, strokeWidth: 3),
          ),
          SizedBox(height: 13),
          Text(
            'Preparing live tour navigation...',
            style: TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ERROR
// ============================================================================

class _TrackingErrorCard extends StatelessWidget {
  const _TrackingErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: _dangerSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: _danger,
              size: 27,
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'Unable to load tour',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w600,
              fontSize: 10,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text(
                'Try Again',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
