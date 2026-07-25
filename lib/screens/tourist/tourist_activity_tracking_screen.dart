import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/components/tourist/driver_review_modal.dart';
import 'package:touristrike/components/tourist/share_trip_bottom_sheet.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/services/emergency_service.dart';
import 'package:touristrike/core/services/route_polyline_service.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/shared/acknowledgement_receipt_screen.dart';
import 'package:touristrike/screens/tourist/tourist_messages_screen.dart';
import 'package:touristrike/widgets/gcash_payment_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

class ActivityTrackingScreen extends StatefulWidget {
  const ActivityTrackingScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<ActivityTrackingScreen> createState() => _ActivityTrackingScreenState();
}

class _ActivityTrackingScreenState extends State<ActivityTrackingScreen> {
  static final _apiKey = CitySpotSuggestionService.resolveApiKey();
  final _routeService = RoutePolylineService(apiKey: _apiKey);

  final _repo = TourisTrikeRepository();
  final _supabase = Supabase.instance.client;

  PackageActivity? _activity;
  PackageBooking? _booking;
  DriverInfo? _driverInfo;
  List<BookingItineraryItem> _spots = [];
  List<EmergencyContactRecord> _emergencyContacts = [];
  List<PaymentRecord> _paymentRecords = [];

  bool _loading = true;
  String? _error;
  String? _eta;
  bool _reviewShown = false;

  // Navigation state
  bool _isFollowingDriver = false;
  bool _isProgrammaticMove = false;
  double _driverSpeed = 0.0; // m/s from live location
  double _driverHeading = 0.0; // degrees clockwise from North

  // Custom bitmap markers (loaded from assets once on init)
  BitmapDescriptor? _tricycleMarker;
  BitmapDescriptor? _passengerMarker;

  // Tourist's own live GPS position (for passenger marker on map)
  Position? _touristPosition;
  StreamSubscription<Position>? _touristGpsSub;

  RealtimeChannel? _activityChannel;
  RealtimeChannel? _locationChannel;
  RealtimeChannel? _bookingChannel;
  RealtimeChannel? _itineraryChannel;
  GoogleMapController? _mapCtrl;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  static const _defaultCenter = LatLng(14.9597, 120.9206);

  BookingItineraryItem? get _currentItineraryItem =>
      _spots.where((s) => s.spotStatus != 'completed').firstOrNull;

  // package_bookings.id is uuid in this project (not bigint), so the raw
  // string id is passed through as-is.
  dynamic get _bookingIdForQueries => widget.bookingId;

  PaymentRecord? _paymentRecordForStage(String stage) {
    final matches =
        _paymentRecords.where((p) => p.paymentStage == stage && p.status != 'cancelled').toList()
          ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return matches.isEmpty ? null : matches.first;
  }

  // TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
  Future<void> _openPaymentSheet({
    required String stage,
    required double amount,
    required String description,
  }) async {
    final driverInfo = _driverInfo;
    if (driverInfo == null || driverInfo.id.isEmpty) return;
    final details = driverInfo.details;

    final record = await showGcashPaymentSheet(
      context,
      payeeId: driverInfo.id,
      payeeName: driverInfo.name,
      gcashQrUrl: details?.gcashQrUrl ?? '',
      gcashNumber: details?.gcashNumber ?? '',
      gcashName: details?.gcashName ?? '',
      amount: amount,
      serviceDescription: description,
      bookingId: _bookingIdForQueries,
      paymentStage: stage,
    );
    if (record != null && mounted) {
      _load();
    }
  }

  void _openReceipt(PaymentRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AcknowledgementReceiptScreen(
          record: record,
          payeeName: _driverInfo?.name,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initCustomMarkers();
    _load();
  }

  @override
  void dispose() {
    _activityChannel?.unsubscribe();
    _locationChannel?.unsubscribe();
    _bookingChannel?.unsubscribe();
    _itineraryChannel?.unsubscribe();
    _touristGpsSub?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ── Custom marker loading ─────────────────────────────────────
  Future<void> _initCustomMarkers() async {
    try {
      final results = await Future.wait([
        BitmapDescriptor.asset(
          const ImageConfiguration(size: Size(35, 35)),
          'assets/icons/tricycle_marker.png',
        ),
        BitmapDescriptor.asset(
          const ImageConfiguration(size: Size(30, 30)),
          'assets/icons/passenger_marker.png',
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _tricycleMarker = results[0];
        _passengerMarker = results[1];
      });
      _buildMarkers();
    } catch (e) {
      debugPrint('[Markers] Failed to load custom markers: $e');
    }
  }

  // ── Data loading ─────────────────────────────────────────────
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final activity = await _repo.fetchActivityForBooking(widget.bookingId);
      final booking = await _repo.fetchPackageBookingDetails(widget.bookingId);
      final spots = await _repo.fetchBookingItinerary(widget.bookingId);
      final emergencyContacts = await _repo.fetchEmergencyContacts();

      DriverInfo? driverInfo;
      final driverId = booking?.assignedDriverId ?? activity?.driverId ?? '';
      if (driverId.isNotEmpty) {
        driverInfo = await _repo.fetchDriverInfo(driverId);
      }

      var paymentRecords = <PaymentRecord>[];
      try {
        paymentRecords = await _repo.fetchPaymentRecordsFor(
          bookingId: _bookingIdForQueries,
        );
      } catch (_) {
        // Non-fatal — payment status cards just won't show yet.
      }

      if (!mounted) return;
      setState(() {
        _activity = activity;
        _booking = booking;
        _driverInfo = driverInfo;
        _spots = spots;
        _emergencyContacts = emergencyContacts;
        _paymentRecords = paymentRecords;
        _loading = false;
      });

      _debugTourState('load');
      _buildMarkers();
      _fetchCurrentRoute();

      _subscribeToActivity(driverId);
      _subscribeToBooking(widget.bookingId);
      _checkAndShowReviewModal();
      _startTouristGpsStreaming();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Realtime subscriptions ────────────────────────────────────
  void _subscribeToActivity(String driverId) {
    _activityChannel?.unsubscribe();
    _activityChannel = _supabase
        .channel('tracking:${widget.bookingId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'package_activities',
          filter: PostgresChangeFilter(
            column: 'booking_id',
            type: PostgresChangeFilterType.eq,
            value: widget.bookingId,
          ),
          callback: (payload) {
            final newRow = payload.newRecord;
            if (!mounted || newRow.isEmpty) return;
            final updated = PackageActivity(Map<String, dynamic>.from(newRow));
            final prevStatus = _activity?.tourStatus;
            setState(() => _activity = updated);

            _buildMarkers();
            if (updated.tourStatus != prevStatus) {
              _fetchCurrentRoute();
              _refreshSpots(logTag: 'activity-status-update');
            } else if (updated.driverLatitude != null) {
              _updateRouteForDriverPosition();
            } else {
              _debugTourState('activity-update');
            }
          },
        )
        .subscribe();

    // Subscribe to live location table for smoother driver position updates
    if (driverId.isNotEmpty) {
      _locationChannel?.unsubscribe();
      _locationChannel = _supabase
          .channel('live-loc:$driverId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'driver_live_locations',
            filter: PostgresChangeFilter(
              column: 'driver_id',
              type: PostgresChangeFilterType.eq,
              value: driverId,
            ),
            callback: (payload) {
              final newRow = payload.newRecord;
              if (!mounted || newRow.isEmpty) return;
              final lat = newRow['latitude'] as num?;
              final lng = newRow['longitude'] as num?;
              final speed = (newRow['speed'] as num?)?.toDouble() ?? 0.0;
              final heading =
                  (newRow['heading'] as num?)?.toDouble() ?? _driverHeading;
              if (lat == null || lng == null) return;
              if (_activity != null) {
                setState(() {
                  _driverSpeed = speed;
                  _driverHeading = heading;
                  _activity = PackageActivity({
                    ..._activity!.row,
                    'driver_latitude': lat.toDouble(),
                    'driver_longitude': lng.toDouble(),
                    'driver_last_seen': newRow['updated_at'],
                  });
                });
                _buildMarkers();
                // Only follow camera when user has tapped Recenter
                if (_isFollowingDriver) _animateCameraToDriver();
              }
            },
          )
          .subscribe();
    }

    _itineraryChannel?.unsubscribe();
    _itineraryChannel = _supabase
        .channel('itinerary:${widget.bookingId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'booking_itinerary_items',
          filter: PostgresChangeFilter(
            column: 'booking_id',
            type: PostgresChangeFilterType.eq,
            value: widget.bookingId,
          ),
          callback: (payload) {
            final newRow = payload.newRecord;
            if (!mounted) return;
            // Optimistic local update so tourist sees timestamps immediately
            // without waiting for the full _refreshSpots round-trip.
            if (newRow.isNotEmpty) {
              final itemId = newRow['id']?.toString();
              if (itemId != null && itemId.isNotEmpty) {
                setState(() {
                  _spots = _spots.map((s) {
                    if (s.id?.toString() == itemId) {
                      return BookingItineraryItem(
                        Map<String, dynamic>.from({...s.row, ...newRow}),
                      );
                    }
                    return s;
                  }).toList();
                });
              }
            }
            _refreshSpots(logTag: 'itinerary-update');
          },
        )
        .subscribe();
  }

  // ── Review modal ─────────────────────────────────────────────
  bool _isTourCompleted() {
    final bookingStatus = _booking?.bookingStatus ?? '';
    final tourStatus = _activity?.tourStatus ?? '';
    final activityStatus = _activity?.status ?? '';
    return bookingStatus == 'completed' ||
        tourStatus == 'completed' ||
        tourStatus == 'dropped_off' ||
        activityStatus == 'completed';
  }

  Future<void> _checkAndShowReviewModal() async {
    if (_reviewShown) return;
    if (!_isTourCompleted()) return;

    final bookingId = _booking?.id?.toString() ?? widget.bookingId;
    final driverId = _booking?.assignedDriverId ?? _activity?.driverId ?? '';

    if (bookingId.isEmpty || driverId.isEmpty) return;

    final packageId = _booking?.packageId ?? _activity?.packageId;
    final packageName = dbString(
      _activity?.packageRow?['title'],
      fallback: dbString(_booking?.packageRow?['title']),
    );

    final hasDriver = await _repo.hasReviewedDriver(bookingId);
    final hasPackage =
        packageId == null || await _repo.hasReviewedPackage(bookingId);

    if (hasDriver && hasPackage) {
      _reviewShown = true;
      return;
    }

    if (!mounted) return;
    setState(() => _reviewShown = true);

    final submitted = await DriverReviewModal.show(
      context,
      bookingId: bookingId,
      driverId: driverId,
      driverName: _driverInfo?.name ?? '',
      driverAvatarUrl: _driverInfo?.profile?.avatarUrl.isNotEmpty == true
          ? _driverInfo!.profile!.avatarUrl
          : _driverInfo?.profile?.profileImageUrl ?? '',
      packageId: packageId,
      packageName: packageName.isNotEmpty ? packageName : null,
      includeDriverReview: !hasDriver,
      includePackageReview: !hasPackage,
    );
    if (!mounted || !submitted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Thank you for your feedback!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    await _refreshSpots(logTag: 'review-submitted');
  }

  // ── Refresh ───────────────────────────────────────────────────
  Future<void> _refreshSpots({String logTag = 'refresh-spots'}) async {
    final activity = await _repo.fetchActivityForBooking(widget.bookingId);
    final booking = await _repo.fetchPackageBookingDetails(widget.bookingId);
    final spots = await _repo.fetchBookingItinerary(widget.bookingId);
    final driverId = booking?.assignedDriverId ?? activity?.driverId ?? '';
    final driverInfo = driverId.isEmpty
        ? null
        : await _repo.fetchDriverInfo(driverId);
    if (!mounted) return;
    setState(() {
      _activity = activity;
      _booking = booking;
      _driverInfo = driverInfo;
      _spots = spots;
    });
    _debugTourState(logTag);
    _buildMarkers();
    _fetchCurrentRoute();
    _checkAndShowReviewModal();
  }

  void _debugTourState(String tag) {
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
      '[TouristTracking:$tag] '
      'booking_id=${activity?.bookingId ?? widget.bookingId} '
      'loaded travel_date=${booking?.travelDate} '
      'loaded pickup_address=${booking?.pickupAddress} '
      'loaded dropoff_address=${booking?.dropoffAddress} '
      'total itinerary items=${_spots.length} '
      'completed itinerary items=$completedCount '
      'current itinerary item id=${currentItem?.id} '
      'current itinerary item status=${currentItem?.spotStatus} '
      'spot_status list=[$spotStatusList] '
      'package_activities.status=${activity?.status} '
      'package_activities.tour_status=${activity?.tourStatus} '
      'package_bookings.status=${booking?.status} '
      'package_bookings.booking_status=${booking?.bookingStatus}',
    );
  }

  Future<void> _startTouristGpsStreaming() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      await _touristGpsSub?.cancel();
      _touristGpsSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen((pos) {
            if (!mounted) return;
            setState(() => _touristPosition = pos);
            _buildMarkers();
          });
    } catch (_) {}
  }

  void _subscribeToBooking(String bookingId) {
    _bookingChannel?.unsubscribe();
    _bookingChannel = _supabase
        .channel('booking-progress:$bookingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'package_bookings',
          filter: PostgresChangeFilter(
            column: 'id',
            type: PostgresChangeFilterType.eq,
            value: bookingId,
          ),
          callback: (_) => _refreshSpots(logTag: 'booking-update'),
        )
        .subscribe();
  }

  // ── Markers ──────────────────────────────────────────────────
  void _buildMarkers() {
    final markers = <Marker>{};
    final booking = _booking;

    // Tourist's live location — passenger icon
    if (_touristPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('tourist_live'),
          position: LatLng(
            _touristPosition!.latitude,
            _touristPosition!.longitude,
          ),
          icon:
              _passengerMarker ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'You'),
          zIndexInt: 2,
        ),
      );
    }

    // Pickup point — green circular pin
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

    // Drop-off point — red/orange destination pin
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

    // Itinerary spots — completed=green, active=orange, upcoming=azure
    for (var i = 0; i < _spots.length; i++) {
      final spot = _spots[i];
      if (spot.latitude == 0 && spot.longitude == 0) continue;
      final isDone = spot.spotStatus == 'completed';
      final isCurrent = !isDone && spot.id == _currentItineraryItem?.id;
      markers.add(
        Marker(
          markerId: MarkerId('spot_$i'),
          position: LatLng(spot.latitude, spot.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isDone
                ? BitmapDescriptor.hueGreen
                : isCurrent
                ? BitmapDescriptor.hueOrange
                : BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: 'Stop ${i + 1}: ${spot.destinationName}',
            snippet: spot.destinationAddress,
          ),
        ),
      );
    }

    // Driver position — tricycle icon, rotates with heading
    final activity = _activity;
    if (activity != null &&
        activity.driverLatitude != null &&
        activity.driverLongitude != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(activity.driverLatitude!, activity.driverLongitude!),
          icon:
              _tricycleMarker ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          rotation: _driverHeading,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          infoWindow: const InfoWindow(title: 'Your Driver'),
          zIndexInt: 1,
        ),
      );
    }

    if (mounted) setState(() => _markers = markers);
  }

  // ── Route / polyline ─────────────────────────────────────────
  Future<void> _fetchCurrentRoute() async {
    final activity = _activity;
    final booking = _booking;
    if (activity == null || booking == null) return;

    LatLng? origin;
    LatLng? destination;
    final ts = activity.tourStatus;

    if (ts == 'driver_accepted' ||
        ts == 'driver_en_route' ||
        ts == 'driver_arrived') {
      if (activity.driverLatitude != null && booking.pickupLatitude != null) {
        origin = LatLng(activity.driverLatitude!, activity.driverLongitude!);
        destination = LatLng(booking.pickupLatitude!, booking.pickupLongitude!);
      }
    } else if (ts == 'picked_up' ||
        ts == 'on_tour' ||
        ts == 'en_route_to_spot') {
      final currentItem = _currentItineraryItem;
      if (currentItem != null) {
        origin = activity.driverLatitude != null
            ? LatLng(activity.driverLatitude!, activity.driverLongitude!)
            : booking.pickupLatitude != null
            ? LatLng(booking.pickupLatitude!, booking.pickupLongitude!)
            : null;
        destination = LatLng(currentItem.latitude, currentItem.longitude);
      }
    } else if (ts == 'at_spot') {
      final currentItem = _currentItineraryItem;
      if (currentItem != null && activity.driverLatitude != null) {
        origin = LatLng(activity.driverLatitude!, activity.driverLongitude!);
        destination = LatLng(currentItem.latitude, currentItem.longitude);
      }
    } else if (ts == 'en_route_to_dropoff' || ts == 'ready_to_complete') {
      if (booking.dropoffLatitude != null) {
        origin = activity.driverLatitude != null
            ? LatLng(activity.driverLatitude!, activity.driverLongitude!)
            : _spots.isNotEmpty
            ? LatLng(_spots.last.latitude, _spots.last.longitude)
            : null;
        destination = LatLng(
          booking.dropoffLatitude!,
          booking.dropoffLongitude!,
        );
      }
    }

    if (origin == null || destination == null) {
      if (mounted) setState(() => _polylines = {});
      return;
    }

    final result = await _routeService.fetchRoute(origin, destination);
    if (!mounted) return;
    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: result.points,
          color: const Color(0xFF2A86FF),
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

  Future<void> _updateRouteForDriverPosition() async {
    final activity = _activity;
    if (activity?.driverLatitude == null) return;
    final ts = activity!.tourStatus;
    if (ts == 'at_spot' ||
        ts == 'dropped_off' ||
        ts == 'completed' ||
        ts == 'waiting_driver') {
      return;
    }
    await _fetchCurrentRoute();
  }

  // ── Camera helpers ────────────────────────────────────────────

  /// Dynamic zoom: slow speed → zoom in, fast speed → zoom out (like Google Maps).
  double _speedToZoom(double speedMs) {
    final kmh = speedMs * 3.6;
    if (kmh < 10) return 17.0;
    if (kmh < 30) return 15.5;
    if (kmh < 60) return 13.5;
    return 12.0;
  }

  void _animateCameraToDriver() {
    final activity = _activity;
    if (_mapCtrl == null || activity?.driverLatitude == null) return;
    _isProgrammaticMove = true;
    _mapCtrl!.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(activity!.driverLatitude!, activity.driverLongitude!),
        _speedToZoom(_driverSpeed),
      ),
    );
  }

  void _animateCameraToRelevant() {
    if (_mapCtrl == null) return;
    final activity = _activity;
    final booking = _booking;
    if (activity?.driverLatitude != null) {
      _isProgrammaticMove = true;
      _mapCtrl!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(activity!.driverLatitude!, activity.driverLongitude!),
          15,
        ),
      );
    } else if (booking?.pickupLatitude != null) {
      _isProgrammaticMove = true;
      _mapCtrl!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(booking!.pickupLatitude!, booking.pickupLongitude!),
          15,
        ),
      );
    }
  }

  void _animateCameraToPickup() {
    final booking = _booking;
    if (_mapCtrl == null || booking?.pickupLatitude == null) return;
    _isProgrammaticMove = true;
    _mapCtrl!.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(booking!.pickupLatitude!, booking.pickupLongitude!),
        17,
      ),
    );
  }

  LatLng get _initialCenter {
    if (_booking?.pickupLatitude != null) {
      return LatLng(_booking!.pickupLatitude!, _booking!.pickupLongitude!);
    }
    return _defaultCenter;
  }

  // ── Status helpers ───────────────────────────────────────────
  static const _statusInfo = {
    'waiting_for_drivers': (
      'Finding Drivers',
      'We are finding available drivers for your group tour.',
      Color(0xFFF59E0B),
      Icons.search_rounded,
    ),
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
    'on_tour': (
      'On Tour',
      'Your selected itinerary is active and updates as each spot is completed.',
      Color(0xFF0EA5E9),
      Icons.route_rounded,
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
    'ready_to_complete': (
      'All Spots Completed',
      'Every booked spot is completed. Your tour stays active until the driver finishes the trip.',
      Color(0xFF16A34A),
      Icons.task_alt_rounded,
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _launchPhone(String phone) async {
    final normalized = phone.trim();
    if (normalized.isEmpty) return;
    final uri = Uri.parse('tel:$normalized');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openDriverChat() async {
    final booking = _booking;
    final driverId = booking?.assignedDriverId ?? _activity?.driverId ?? '';
    if (driverId.isEmpty) {
      _showSnack('Driver has not accepted the tour yet.');
      return;
    }
    try {
      final conversation = await _repo.getOrCreateConversation(
        touristId: booking?.touristId.isNotEmpty == true
            ? booking!.touristId
            : _repo.requireUserId(),
        driverId: driverId,
        bookingId: booking?.id,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TouristChatScreen(
            conversationId: conversation['id'].toString(),
            driverId: driverId,
            driverName: _driverInfo?.name ?? 'Driver',
            driverPhone: _driverInfo?.phoneNumber ?? '',
            driverAvatar: _driverInfo?.profile?.avatarUrl.isNotEmpty == true
                ? _driverInfo!.profile!.avatarUrl
                : _driverInfo?.profile?.profileImageUrl ?? '',
          ),
        ),
      );
    } catch (error) {
      final message = error is StateError
          ? error.toString().replaceFirst('Bad state: ', '')
          : 'Unable to chat right now.';
      _showSnack(message);
    }
  }

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
            ? _ErrorView(message: _error!, onRetry: _load)
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final activity = _activity;
    final booking = _booking;
    final size = MediaQuery.sizeOf(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);
    final mapHeight = (size.height * 0.40).clamp(240.0, 380.0);

    final requiredDrivers = booking?.requiredDrivers ?? 1;
    final acceptedDrivers = booking?.acceptedDriversCount ?? 0;
    final bookingStatus = booking?.bookingStatus ?? '';
    final isWaitingForDrivers =
        bookingStatus == 'waiting_for_drivers' ||
        (acceptedDrivers < requiredDrivers &&
            (activity?.status == 'pending' || activity == null));

    final tourStatus = isWaitingForDrivers
        ? 'waiting_for_drivers'
        : (activity?.tourStatus ?? 'waiting_driver');
    final statusData =
        _statusInfo[tourStatus] ??
        (
          tourStatus.replaceAll('_', ' ').toUpperCase(),
          '',
          const Color(0xFF64748B),
          Icons.info_rounded,
        );
    final (statusLabel, statusDesc, statusColor, statusIcon) = statusData;

    final bookingType = dbString(
      booking?.row['booking_type'],
      fallback: 'advanced',
    );
    final travelDate = booking?.travelDate;
    final adults = booking?.adults ?? 0;
    final children = booking?.children ?? 0;
    final totalAmount = booking?.totalAmount ?? 0.0;
    final driverName = _driverInfo?.name ?? '';
    final driverPhone = _driverInfo?.phoneNumber ?? '';
    final vehicleDetails = _driverInfo?.vehicleDetails ?? '';
    final driverRating = _driverInfo?.profile?.averageRating ?? 0.0;
    final driverReviewCount = _driverInfo?.profile?.totalReviews ?? 0;

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            // ── Map as hero SliverAppBar ─────────────────────────
            SliverAppBar(
              expandedHeight: mapHeight,
              pinned: true,
              backgroundColor: const Color(0xFF2A86FF),
              foregroundColor: Colors.white,
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Tour Tracking',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  if (_eta != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _eta!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () {
                      ShareTripBottomSheet.show(
                        context,
                        bookingId: widget.bookingId,
                        travelDate: _booking?.travelDate,
                      );
                    },
                    icon: const Icon(Icons.share_location_rounded, size: 20),
                    color: Colors.white,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    tooltip: 'Share Trip',
                  ),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    color: Colors.white,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  children: [
                    ClipRect(
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _initialCenter,
                          zoom: 14,
                        ),
                        markers: _markers,
                        polylines: _polylines,
                        onMapCreated: (ctrl) {
                          _mapCtrl = ctrl;
                          _animateCameraToRelevant();
                        },
                        onCameraMoveStarted: () {
                          if (!_isProgrammaticMove && _isFollowingDriver) {
                            setState(() => _isFollowingDriver = false);
                          }
                        },
                        onCameraIdle: () => _isProgrammaticMove = false,
                        gestureRecognizers: {
                          Factory<OneSequenceGestureRecognizer>(
                            () => EagerGestureRecognizer(),
                          ),
                        },
                        zoomControlsEnabled: false,
                        myLocationButtonEnabled: false,
                        compassEnabled: true,
                        mapToolbarEnabled: false,
                        rotateGesturesEnabled: true,
                        scrollGesturesEnabled: true,
                        zoomGesturesEnabled: true,
                        tiltGesturesEnabled: true,
                      ),
                    ),
                    // Recenter FABs
                    Positioned(
                      right: 12,
                      bottom: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_booking?.pickupLatitude != null) ...[
                            FloatingActionButton.small(
                              heroTag: 'tourist_recenter_pickup',
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF16A34A),
                              elevation: 4,
                              tooltip: 'Recenter on Pickup',
                              onPressed: () {
                                setState(() => _isFollowingDriver = false);
                                _animateCameraToPickup();
                              },
                              child: const Icon(Icons.hail_rounded, size: 20),
                            ),
                            const SizedBox(height: 8),
                          ],
                          FloatingActionButton.small(
                            heroTag: 'tourist_recenter',
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF2A86FF),
                            elevation: 4,
                            tooltip: 'Recenter on Driver',
                            onPressed: () {
                              setState(() => _isFollowingDriver = true);
                              _animateCameraToRelevant();
                            },
                            child: const Icon(
                              Icons.my_location_rounded,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Content cards ────────────────────────────────────
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 24 + bottom),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Live Status Card ──────────────────────────
                  _StatusCard(
                    icon: statusIcon,
                    label: statusLabel,
                    description: statusDesc,
                    color: statusColor,
                    eta: _eta,
                  ),
                  const SizedBox(height: 12),

                  // ── Finding Drivers Card ──────────────────────
                  if (isWaitingForDrivers) ...[
                    _FindingDriversCard(
                      acceptedDrivers: acceptedDrivers,
                      requiredDrivers: requiredDrivers,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Emergency ─────────────────────────────────
                  _EmergencyPanel(
                    bookingId: widget.bookingId,
                    activityId: _activity?.row['id']?.toString(),
                    driverId: _booking?.assignedDriverId ?? _activity?.driverId,
                    tripStatus: activity?.tourStatus ?? '',
                    currentSpotName: _currentItineraryItem?.destinationName,
                    driverName: driverName.isNotEmpty ? driverName : null,
                    contacts: _emergencyContacts,
                  ),
                  const SizedBox(height: 12),

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
                                if (driverPhone.isNotEmpty)
                                  InkWell(
                                    onTap: () => _launchPhone(driverPhone),
                                    child: Text(
                                      driverPhone,
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                if (vehicleDetails.isNotEmpty)
                                  Text(
                                    vehicleDetails,
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                if (driverReviewCount > 0)
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        size: 13,
                                        color: Color(0xFFF59E0B),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${driverRating.toStringAsFixed(1)} ($driverReviewCount)',
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              IconButton(
                                onPressed: driverPhone.isEmpty
                                    ? null
                                    : () => _launchPhone(driverPhone),
                                tooltip: 'Call driver',
                                icon: const Icon(
                                  Icons.phone_rounded,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                              IconButton(
                                onPressed: _openDriverChat,
                                tooltip: 'Message driver',
                                icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: Color(0xFF2A86FF),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── GCash-to-GCash payment (down payment + remaining) ──
                  // TourisTrike does NOT custody funds. Money moves directly
                  // from the tourist's GCash to the driver's GCash.
                  if (driverName.isNotEmpty &&
                      bookingType == 'advanced' &&
                      (booking?.downpaymentAmount ?? 0) > 0) ...[
                    _PaymentStageCard(
                      title: 'Down Payment',
                      amount: booking!.downpaymentAmount,
                      record: _paymentRecordForStage('down_payment'),
                      onPay: () => _openPaymentSheet(
                        stage: 'down_payment',
                        amount: booking.downpaymentAmount,
                        description:
                            'Down payment for package booking #${widget.bookingId}',
                      ),
                      onViewReceipt: _openReceipt,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (driverName.isNotEmpty &&
                      (booking?.remainingBalance ?? 0) > 0) ...[
                    _PaymentStageCard(
                      title: 'Remaining Balance',
                      amount: booking!.remainingBalance,
                      record: _paymentRecordForStage('remaining_balance'),
                      onPay: () => _openPaymentSheet(
                        stage: 'remaining_balance',
                        amount: booking.remainingBalance,
                        description:
                            'Remaining balance for package booking #${widget.bookingId}',
                      ),
                      onViewReceipt: _openReceipt,
                    ),
                    const SizedBox(height: 12),
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
                              ? DateFormat(
                                  'EEE, MMM d, yyyy',
                                ).format(travelDate)
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
                          value:
                              '$adults adult${adults != 1 ? 's' : ''}'
                              '${children > 0 ? ', $children child${children != 1 ? 'ren' : ''}' : ''}',
                        ),
                        if (requiredDrivers > 1) ...[
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Tricycles',
                            value: '$requiredDrivers required',
                          ),
                        ],
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: 'Total Amount',
                          value: money.format(totalAmount),
                          bold: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

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
                    const SizedBox(height: 12),
                  ],

                  // ── Tour Itinerary ────────────────────────────
                  if (_spots.isNotEmpty) ...[
                    _SectionLabel('Tour Itinerary (${_spots.length} stops)'),
                    const SizedBox(height: 8),
                    _InfoCard(
                      child: Column(
                        children: _spots.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final spot = entry.value;
                          final isCurrent =
                              activity != null &&
                              spot.id == _currentItineraryItem?.id &&
                              spot.spotStatus != 'completed' &&
                              (activity.tourStatus == 'on_tour' ||
                                  activity.tourStatus == 'en_route_to_spot' ||
                                  activity.tourStatus == 'at_spot' ||
                                  activity.tourStatus == 'picked_up');
                          final isDone = spot.spotStatus == 'completed';
                          return _SpotRow(
                            index: idx + 1,
                            title: spot.destinationName,
                            scheduledArrival: spot.arrivalTime,
                            scheduledDeparture: spot.departureTime,
                            actualArrival: spot.actualArrivalTime,
                            actualDeparture: spot.actualDepartureTime,
                            spotStatus: spot.spotStatus,
                            stayMinutes: spot.estimatedStayDurationMinutes,
                            isCurrent: isCurrent,
                            isDone: isDone,
                            isLast: idx == _spots.length - 1,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ],
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
    this.eta,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final String? eta;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
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
          if (eta != null) ...[
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  eta!,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const Text(
                  'ETA',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FindingDriversCard extends StatelessWidget {
  const _FindingDriversCard({
    required this.acceptedDrivers,
    required this.requiredDrivers,
  });

  final int acceptedDrivers;
  final int requiredDrivers;

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFF59E0B);
    final progress = requiredDrivers > 0
        ? acceptedDrivers / requiredDrivers
        : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.electric_rickshaw_rounded,
                  color: amber,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Finding Drivers',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Waiting for driver/s to accept.',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Waiting for Drivers',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              Text(
                '$acceptedDrivers / $requiredDrivers',
                style: const TextStyle(
                  color: amber,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: amber.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(amber),
              minHeight: 7,
            ),
          ),
          if (requiredDrivers > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: List.generate(requiredDrivers, (i) {
                final filled = i < acceptedDrivers;
                return Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: filled
                        ? amber.withValues(alpha: 0.18)
                        : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: filled ? amber : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Icon(
                    Icons.electric_rickshaw_rounded,
                    color: filled ? amber : const Color(0xFFCBD5E1),
                    size: 18,
                  ),
                );
              }),
            ),
          ],
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

// TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
class _PaymentStageCard extends StatelessWidget {
  const _PaymentStageCard({
    required this.title,
    required this.amount,
    required this.record,
    required this.onPay,
    required this.onViewReceipt,
  });

  final String title;
  final double amount;
  final PaymentRecord? record;
  final VoidCallback onPay;
  final ValueChanged<PaymentRecord> onViewReceipt;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);
    final r = record;
    final status = r?.status;

    Color chipColor = const Color(0xFF64748B);
    Color chipBg = const Color(0xFFF1F5F9);
    String chipLabel = 'Not yet paid';
    if (status == 'confirmed') {
      chipColor = const Color(0xFF16A34A);
      chipBg = const Color(0xFFDCFCE7);
      chipLabel = 'Confirmed';
    } else if (status == 'pending_confirmation') {
      chipColor = const Color(0xFFB45309);
      chipBg = const Color(0xFFFFF3CD);
      chipLabel = 'Waiting for driver confirmation';
    } else if (status == 'disputed') {
      chipColor = const Color(0xFFDC2626);
      chipBg = const Color(0xFFFFF1F2);
      chipLabel = 'Disputed';
    }

    return _InfoCard(
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
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      money.format(amount),
                      style: const TextStyle(
                        color: Color(0xFF2A86FF),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  chipLabel,
                  style: TextStyle(color: chipColor, fontWeight: FontWeight.w800, fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: status == 'confirmed'
                ? OutlinedButton.icon(
                    onPressed: () => onViewReceipt(r!),
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('View Receipt'),
                  )
                : status == 'pending_confirmation'
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Submitted. Waiting for the driver to confirm receipt.',
                      style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: onPay,
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('Pay Now'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2A86FF)),
                  ),
          ),
        ],
      ),
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
        fontSize: 17,
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
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: const Color(0xFF0F172A),
              fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
              fontSize: bold ? 14.5 : 13,
            ),
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
        Icon(icon, color: iconColor, size: 18),
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
                  fontSize: 10.5,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
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

class _SpotRow extends StatelessWidget {
  const _SpotRow({
    required this.index,
    required this.title,
    required this.scheduledArrival,
    required this.scheduledDeparture,
    required this.actualArrival,
    required this.actualDeparture,
    required this.spotStatus,
    required this.stayMinutes,
    required this.isCurrent,
    required this.isDone,
    required this.isLast,
  });

  final int index;
  final String title;
  final String scheduledArrival;
  final String scheduledDeparture;
  final DateTime? actualArrival;
  final DateTime? actualDeparture;
  final String spotStatus;
  final int stayMinutes;
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

    final timeFmt = DateFormat('h:mm a');

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step indicator
            Column(
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
                              fontSize: 11,
                            ),
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: isDone
                                ? const Color(0xFF94A3B8)
                                : isCurrent
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF64748B),
                            fontWeight: isCurrent
                                ? FontWeight.w900
                                : FontWeight.w700,
                            fontSize: 13.5,
                            decoration: isDone
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      _SpotStatusChip(status: spotStatus, isDone: isDone),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (scheduledArrival.isNotEmpty ||
                      scheduledDeparture.isNotEmpty)
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 11,
                          color: Color(0xFFCBD5E1),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _buildTimeLabel(scheduledArrival, scheduledDeparture),
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  if (actualArrival != null) ...[
                    const SizedBox(height: 4),
                    _TimestampBadge(
                      icon: Icons.location_on_rounded,
                      label: 'Arrived',
                      time: timeFmt.format(actualArrival!.toLocal()),
                      color: const Color(0xFF2A86FF),
                    ),
                  ],
                  if (actualDeparture != null) ...[
                    const SizedBox(height: 3),
                    _TimestampBadge(
                      icon: Icons.check_circle_rounded,
                      label: 'Completed',
                      time: timeFmt.format(actualDeparture!.toLocal()),
                      color: const Color(0xFF16A34A),
                    ),
                  ],
                  if (stayMinutes > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Stay: ${stayMinutes}m',
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 13, top: 2, bottom: 2),
            child: Container(
              width: 2,
              height: 14,
              color: color.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }

  String _buildTimeLabel(String arrival, String departure) {
    final a = formatScheduleTimeLabel(arrival);
    final d = formatScheduleTimeLabel(departure);
    if (a.isNotEmpty && d.isNotEmpty) return '$a – $d';
    if (a.isNotEmpty) return 'Arr. $a';
    if (d.isNotEmpty) return 'Dep. $d';
    return '';
  }
}

class _TimestampBadge extends StatelessWidget {
  const _TimestampBadge({
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(
                '$label at $time',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpotStatusChip extends StatelessWidget {
  const _SpotStatusChip({required this.status, required this.isDone});

  final String status;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    if (isDone || status == 'completed') {
      return const SizedBox.shrink();
    }
    final (label, color) = switch (status) {
      'travelling' => ('EN ROUTE', const Color(0xFF0EA5E9)),
      'at_spot' => ('HERE', const Color(0xFF16A34A)),
      _ => ('', const Color(0xFF94A3B8)),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 9.5,
        ),
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
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ── Emergency Panel ───────────────────────────────────────────

class _EmergencyPanel extends StatefulWidget {
  const _EmergencyPanel({
    required this.bookingId,
    this.activityId,
    this.driverId,
    required this.tripStatus,
    this.currentSpotName,
    this.driverName,
    required this.contacts,
  });

  final String bookingId;
  final String? activityId;
  final String? driverId;
  final String tripStatus;
  final String? currentSpotName;
  final String? driverName;
  final List<EmergencyContactRecord> contacts;

  @override
  State<_EmergencyPanel> createState() => _EmergencyPanelState();
}

class _EmergencyPanelState extends State<_EmergencyPanel>
    with SingleTickerProviderStateMixin {
  static const _cooldownDuration = Duration(minutes: 5);

  late final AnimationController _pulse;
  late final Animation<double> _scale;

  bool _sending = false;
  DateTime? _cooldownUntil;
  int _cooldownSecondsLeft = 0;
  Timer? _cooldownTimer;

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.04,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  bool get _inCooldown =>
      _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);

  void _startCooldown() {
    _cooldownUntil = DateTime.now().add(_cooldownDuration);
    _updateCooldownSeconds();
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateCooldownSeconds();
      if (!_inCooldown) {
        _cooldownTimer?.cancel();
        setState(() {});
      }
    });
  }

  void _updateCooldownSeconds() {
    if (_cooldownUntil == null) return;
    final remaining = _cooldownUntil!.difference(DateTime.now());
    setState(() {
      _cooldownSecondsLeft = remaining.isNegative ? 0 : remaining.inSeconds;
    });
  }

  Future<void> _onEmergencyPressed() async {
    if (_sending || _inCooldown) return;

    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EmergencyConfirmDialog(noteController: noteController),
    );
    if (confirmed != true || !mounted) {
      noteController.dispose();
      return;
    }

    setState(() => _sending = true);

    try {
      final touristId = _supabase.auth.currentUser?.id ?? '';
      String? touristName;
      try {
        final profile = await _supabase
            .from('profiles')
            .select('full_name, first_name, last_name')
            .eq('id', touristId)
            .maybeSingle();
        if (profile != null) {
          touristName = (profile['full_name'] as String?)?.trim();
          if (touristName == null || touristName.isEmpty) {
            final fn = (profile['first_name'] as String?) ?? '';
            final ln = (profile['last_name'] as String?) ?? '';
            touristName = '$fn $ln'.trim();
          }
        }
      } catch (_) {}

      final note = noteController.text.trim();
      await EmergencyService(_supabase).triggerAlert(
        touristId: touristId,
        bookingId: widget.bookingId,
        activityId: widget.activityId,
        driverId: widget.driverId?.isEmpty == true ? null : widget.driverId,
        tripStatus: widget.tripStatus,
        currentSpotName: widget.currentSpotName,
        touristName: touristName,
        driverName: widget.driverName,
        note: note.isEmpty ? null : note,
      );

      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency alert sent. Help is on the way.'),
          backgroundColor: Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send alert: $e'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      noteController.dispose();
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryContact = widget.contacts.firstOrNull;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF1F2), Color(0xFFFFF5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE4E6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.emergency_rounded,
                  color: Color(0xFFDC2626),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Alert',
                      style: TextStyle(
                        color: Color(0xFF7F1D1D),
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      'Instantly notifies your contacts and the tourism office.',
                      style: TextStyle(
                        color: Color(0xFF9A3412),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_inCooldown)
            _CooldownButton(secondsLeft: _cooldownSecondsLeft)
          else
            ScaleTransition(
              scale: _scale,
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : _onEmergencyPressed,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.emergency_rounded, size: 22),
                  label: Text(
                    _sending ? 'Sending Alert...' : 'EMERGENCY',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          if (primaryContact != null) ...[
            const SizedBox(height: 12),
            _ContactShortcut(contact: primaryContact),
          ],
        ],
      ),
    );
  }
}

class _CooldownButton extends StatelessWidget {
  const _CooldownButton({required this.secondsLeft});
  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    final mins = secondsLeft ~/ 60;
    final secs = secondsLeft % 60;
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF16A34A).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF16A34A).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF16A34A),
            size: 20,
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Alert Sent',
                style: TextStyle(
                  color: Color(0xFF16A34A),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              Text(
                'Next alert in ${mins}m ${secs.toString().padLeft(2, '0')}s',
                style: const TextStyle(
                  color: Color(0xFF16A34A),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmergencyConfirmDialog extends StatelessWidget {
  const _EmergencyConfirmDialog({required this.noteController});
  final TextEditingController noteController;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFFFE4E6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emergency_rounded,
                color: Color(0xFFDC2626),
                size: 30,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Send Emergency Alert?',
              style: TextStyle(
                color: Color(0xFF7F1D1D),
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'This will immediately notify:',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            _NotifyItem(Icons.person_rounded, 'Your emergency contacts'),
            _NotifyItem(
              Icons.electric_rickshaw_rounded,
              'Your assigned driver',
            ),
            _NotifyItem(Icons.business_rounded, 'TourisTrike tourism office'),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLength: 200,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Add a note (optional)...',
                hintStyle: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                contentPadding: const EdgeInsets.all(12),
                counterStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'SEND ALERT',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NotifyItem extends StatelessWidget {
  const _NotifyItem(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: const Color(0xFFDC2626)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactShortcut extends StatelessWidget {
  const _ContactShortcut({required this.contact});
  final EmergencyContactRecord contact;

  @override
  Widget build(BuildContext context) {
    final phone = contact.phoneNumber.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.person_outline_rounded,
            size: 16,
            color: Color(0xFF9A3412),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              contact.name,
              style: const TextStyle(
                color: Color(0xFF7F1D1D),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (phone.isNotEmpty)
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse('tel:$phone');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.call_rounded, size: 13, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Call',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
