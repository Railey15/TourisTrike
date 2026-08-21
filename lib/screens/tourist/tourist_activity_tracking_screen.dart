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
import 'package:touristrike/screens/tourist/booking_cancellation_result_screen.dart';
import 'package:touristrike/screens/tourist/tourist_messages_screen.dart';
import 'package:touristrike/widgets/gcash_payment_sheet.dart';
import 'package:touristrike/widgets/package_booking_cancellation_flow.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================================
// TOURIST TRACKING UI COLORS
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

class ActivityTrackingScreen extends StatefulWidget {
  const ActivityTrackingScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<ActivityTrackingScreen> createState() => _ActivityTrackingScreenState();
}

class _ActivityTrackingScreenState extends State<ActivityTrackingScreen> {
  static final _apiKey = CitySpotSuggestionService.resolveApiKey();

  final RoutePolylineService _routeService = RoutePolylineService(
    apiKey: _apiKey,
  );

  final TourisTrikeRepository _repo = TourisTrikeRepository();
  final SupabaseClient _supabase = Supabase.instance.client;

  PackageActivity? _activity;
  PackageBooking? _booking;
  DriverInfo? _driverInfo;

  List<BookingItineraryItem> _spots = [];
  List<EmergencyContactRecord> _emergencyContacts = [];
  List<PaymentRecord> _paymentRecords = [];

  bool _loading = true;
  bool _reviewShown = false;

  String? _error;
  String? _eta;

  bool _isFollowingDriver = false;
  bool _isProgrammaticMove = false;

  double _driverSpeed = 0.0;
  double _driverHeading = 0.0;

  BitmapDescriptor? _tricycleMarker;
  BitmapDescriptor? _passengerMarker;

  Position? _touristPosition;

  StreamSubscription<Position>? _touristGpsSub;

  RealtimeChannel? _activityChannel;
  RealtimeChannel? _locationChannel;
  RealtimeChannel? _bookingChannel;
  RealtimeChannel? _itineraryChannel;

  GoogleMapController? _mapCtrl;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  static const LatLng _defaultCenter = LatLng(14.9597, 120.9206);

  BookingItineraryItem? get _currentItineraryItem =>
      _spots.where((spot) => spot.spotStatus != 'completed').firstOrNull;

  dynamic get _bookingIdForQueries => widget.bookingId;

  int get _completedSpotCount =>
      _spots.where((spot) => spot.spotStatus == 'completed').length;

  double get _itineraryProgress {
    if (_spots.isEmpty) return 0;

    return _completedSpotCount / _spots.length;
  }

  // =========================================================================
  // PAYMENT HELPERS
  // =========================================================================

  PaymentRecord? _paymentRecordForStage(String stage) {
    final matches =
        _paymentRecords
            .where(
              (payment) =>
                  payment.paymentStage == stage &&
                  payment.status != 'cancelled',
            )
            .toList()
          ..sort(
            (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
              a.createdAt ?? DateTime(0),
            ),
          );

    return matches.isEmpty ? null : matches.first;
  }

  Future<void> _openPaymentSheet({
    required String stage,
    required double amount,
    required String description,
  }) async {
    final driverInfo = _driverInfo;

    if (driverInfo == null || driverInfo.id.isEmpty) {
      return;
    }

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
    _locationChannel?.unsubscribe();
    _bookingChannel?.unsubscribe();
    _itineraryChannel?.unsubscribe();

    _touristGpsSub?.cancel();

    _mapCtrl?.dispose();

    super.dispose();
  }

  // =========================================================================
  // CUSTOM MAP MARKERS
  // =========================================================================

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

  // =========================================================================
  // LOAD
  // =========================================================================

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

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
        // Payment status is non-critical to screen loading.
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

  // =========================================================================
  // REALTIME
  // =========================================================================

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

            if (!mounted || newRow.isEmpty) {
              return;
            }

            final updated = PackageActivity(Map<String, dynamic>.from(newRow));

            final previousStatus = _activity?.tourStatus;

            setState(() {
              _activity = updated;
            });

            _buildMarkers();

            if (updated.tourStatus != previousStatus) {
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

              if (!mounted || newRow.isEmpty) {
                return;
              }

              final lat = newRow['latitude'] as num?;
              final lng = newRow['longitude'] as num?;

              final speed = (newRow['speed'] as num?)?.toDouble() ?? 0;

              final heading =
                  (newRow['heading'] as num?)?.toDouble() ?? _driverHeading;

              if (lat == null || lng == null) {
                return;
              }

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

                if (_isFollowingDriver) {
                  _animateCameraToDriver();
                }
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

            if (newRow.isNotEmpty) {
              final itemId = newRow['id']?.toString();

              if (itemId != null && itemId.isNotEmpty) {
                setState(() {
                  _spots = _spots.map((spot) {
                    if (spot.id?.toString() == itemId) {
                      return BookingItineraryItem(
                        Map<String, dynamic>.from({...spot.row, ...newRow}),
                      );
                    }

                    return spot;
                  }).toList();
                });
              }
            }

            _refreshSpots(logTag: 'itinerary-update');
          },
        )
        .subscribe();
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

  // =========================================================================
  // REVIEW
  // =========================================================================

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
    if (_reviewShown || !_isTourCompleted()) {
      return;
    }

    final bookingId = _booking?.id?.toString() ?? widget.bookingId;

    final driverId = _booking?.assignedDriverId ?? _activity?.driverId ?? '';

    if (bookingId.isEmpty || driverId.isEmpty) {
      return;
    }

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

    setState(() {
      _reviewShown = true;
    });

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

    if (!mounted || !submitted) {
      return;
    }

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

  // =========================================================================
  // REFRESH
  // =========================================================================

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

  // =========================================================================
  // TOURIST GPS
  // =========================================================================

  Future<void> _startTouristGpsStreaming() async {
    try {
      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      await _touristGpsSub?.cancel();

      _touristGpsSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen((position) {
            if (!mounted) return;

            setState(() {
              _touristPosition = position;
            });

            _buildMarkers();
          });
    } catch (_) {}
  }

  // =========================================================================
  // MAP MARKERS
  // =========================================================================

  void _buildMarkers() {
    final markers = <Marker>{};

    final booking = _booking;

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

    for (var index = 0; index < _spots.length; index++) {
      final spot = _spots[index];

      if (spot.latitude == 0 && spot.longitude == 0) {
        continue;
      }

      final done = spot.spotStatus == 'completed';

      final current = !done && spot.id == _currentItineraryItem?.id;

      markers.add(
        Marker(
          markerId: MarkerId('spot_$index'),
          position: LatLng(spot.latitude, spot.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            done
                ? BitmapDescriptor.hueGreen
                : current
                ? BitmapDescriptor.hueOrange
                : BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: 'Stop ${index + 1}: ${spot.destinationName}',
            snippet: spot.destinationAddress,
          ),
        ),
      );
    }

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

    if (mounted) {
      setState(() {
        _markers = markers;
      });
    }
  }

  // =========================================================================
  // ROUTE
  // =========================================================================

  Future<void> _fetchCurrentRoute() async {
    final activity = _activity;
    final booking = _booking;

    if (activity == null || booking == null) {
      return;
    }

    LatLng? origin;
    LatLng? destination;

    final status = activity.tourStatus;

    if (status == 'driver_accepted' ||
        status == 'driver_en_route' ||
        status == 'driver_arrived') {
      if (activity.driverLatitude != null &&
          activity.driverLongitude != null &&
          booking.pickupLatitude != null &&
          booking.pickupLongitude != null) {
        origin = LatLng(activity.driverLatitude!, activity.driverLongitude!);

        destination = LatLng(booking.pickupLatitude!, booking.pickupLongitude!);
      }
    } else if (status == 'picked_up' ||
        status == 'on_tour' ||
        status == 'en_route_to_spot') {
      final currentItem = _currentItineraryItem;

      if (currentItem != null) {
        origin =
            activity.driverLatitude != null && activity.driverLongitude != null
            ? LatLng(activity.driverLatitude!, activity.driverLongitude!)
            : booking.pickupLatitude != null && booking.pickupLongitude != null
            ? LatLng(booking.pickupLatitude!, booking.pickupLongitude!)
            : null;

        destination = LatLng(currentItem.latitude, currentItem.longitude);
      }
    } else if (status == 'at_spot') {
      final currentItem = _currentItineraryItem;

      if (currentItem != null &&
          activity.driverLatitude != null &&
          activity.driverLongitude != null) {
        origin = LatLng(activity.driverLatitude!, activity.driverLongitude!);

        destination = LatLng(currentItem.latitude, currentItem.longitude);
      }
    } else if (status == 'en_route_to_dropoff' ||
        status == 'ready_to_complete') {
      if (booking.dropoffLatitude != null && booking.dropoffLongitude != null) {
        origin =
            activity.driverLatitude != null && activity.driverLongitude != null
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
      if (mounted) {
        setState(() {
          _polylines = {};
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

  Future<void> _updateRouteForDriverPosition() async {
    final activity = _activity;

    if (activity?.driverLatitude == null) {
      return;
    }

    final status = activity!.tourStatus;

    if (status == 'at_spot' ||
        status == 'dropped_off' ||
        status == 'completed' ||
        status == 'waiting_driver') {
      return;
    }

    await _fetchCurrentRoute();
  }

  // =========================================================================
  // CAMERA
  // =========================================================================

  double _speedToZoom(double speedMs) {
    final kmh = speedMs * 3.6;

    if (kmh < 10) return 17;
    if (kmh < 30) return 15.5;
    if (kmh < 60) return 13.5;

    return 12;
  }

  void _animateCameraToDriver() {
    final activity = _activity;

    if (_mapCtrl == null ||
        activity?.driverLatitude == null ||
        activity?.driverLongitude == null) {
      return;
    }

    _isProgrammaticMove = true;

    _mapCtrl!.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(activity!.driverLatitude!, activity.driverLongitude!),
        _speedToZoom(_driverSpeed),
      ),
    );
  }

  void _animateCameraToRelevant() {
    if (_mapCtrl == null) {
      return;
    }

    final activity = _activity;
    final booking = _booking;

    if (activity?.driverLatitude != null && activity?.driverLongitude != null) {
      _isProgrammaticMove = true;

      _mapCtrl!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(activity!.driverLatitude!, activity.driverLongitude!),
          15,
        ),
      );
    } else if (booking?.pickupLatitude != null &&
        booking?.pickupLongitude != null) {
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

    if (_mapCtrl == null ||
        booking?.pickupLatitude == null ||
        booking?.pickupLongitude == null) {
      return;
    }

    _isProgrammaticMove = true;

    _mapCtrl!.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(booking!.pickupLatitude!, booking.pickupLongitude!),
        17,
      ),
    );
  }

  LatLng get _initialCenter {
    if (_booking?.pickupLatitude != null && _booking?.pickupLongitude != null) {
      return LatLng(_booking!.pickupLatitude!, _booking!.pickupLongitude!);
    }

    return _defaultCenter;
  }

  // =========================================================================
  // STATUS INFO
  // =========================================================================

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
      Color(0xFF2563EB),
      Icons.check_circle_rounded,
    ),
    'driver_en_route': (
      'Driver On the Way',
      'Your driver is heading to your pickup point.',
      Color(0xFF2563EB),
      Icons.navigation_rounded,
    ),
    'driver_arrived': (
      'Driver Arrived',
      'Your driver has arrived at the pickup point.',
      Color(0xFF7C3AED),
      Icons.location_on_rounded,
    ),
    'picked_up': (
      'Tour Started',
      'You have been picked up. Enjoy your tour!',
      Color(0xFF16A34A),
      Icons.tour_rounded,
    ),
    'on_tour': (
      'Tour in Progress',
      'Your selected itinerary updates as each destination is completed.',
      Color(0xFF0EA5E9),
      Icons.route_rounded,
    ),
    'en_route_to_spot': (
      'Heading to Next Stop',
      'Your driver is heading to the next destination.',
      Color(0xFF0EA5E9),
      Icons.navigation_rounded,
    ),
    'at_spot': (
      'At Tour Destination',
      'You have arrived. Enjoy exploring!',
      Color(0xFF16A34A),
      Icons.place_rounded,
    ),
    'en_route_to_dropoff': (
      'Heading to Drop-off',
      'All stops are complete. Your driver is taking you to the final drop-off.',
      Color(0xFF2563EB),
      Icons.flag_rounded,
    ),
    'ready_to_complete': (
      'Tour Almost Complete',
      'All booked destinations are complete.',
      Color(0xFF16A34A),
      Icons.task_alt_rounded,
    ),
    'dropped_off': (
      'Dropped Off',
      'You have reached your final destination.',
      Color(0xFF16A34A),
      Icons.check_circle_outline_rounded,
    ),
    'completed': (
      'Tour Completed',
      'Thank you for touring with TourisTrike!',
      Color(0xFF16A34A),
      Icons.star_rounded,
    ),
  };

  // =========================================================================
  // MISC
  // =========================================================================

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  Future<void> _launchPhone(String phone) async {
    final normalized = phone.trim();

    if (normalized.isEmpty) return;

    final uri = Uri.parse('tel:$normalized');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
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

  // =========================================================================
  // BUILD
  // =========================================================================

  bool get _isCancelled {
    final values = [
      _booking?.status,
      _booking?.bookingStatus,
      _activity?.status,
      _activity?.tourStatus,
    ];
    return values.any((value) => value?.toLowerCase() == 'cancelled');
  }

  bool get _canOfferCancellation {
    final tourStatus = _activity?.tourStatus.toLowerCase() ?? 'waiting_driver';
    return !_isCancelled &&
        !{
          'driver_arrived',
          'picked_up',
          'on_tour',
          'en_route_to_spot',
          'at_spot',
          'en_route_to_dropoff',
          'ready_to_complete',
          'dropped_off',
          'completed',
        }.contains(tourStatus);
  }

  Future<void> _manageCancellation() async {
    final booking = _booking;
    if (booking == null) return;
    final packageTitle = dbString(
      booking.packageRow?['title'],
      fallback: 'Tour package',
    );
    final result = await showPackageBookingCancellationFlow(
      context,
      bookingId: widget.bookingId,
      packageTitle: packageTitle,
      travelDate: booking.travelDate,
      repository: _repo,
    );
    if (result == null || !mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => BookingCancellationResultScreen(
          result: result,
          packageTitle: packageTitle,
          travelDate: booking.travelDate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const _LoadingView()
            : _error != null
            ? Column(
                children: [
                  _TrackingTopBar(
                    eta: null,
                    onBack: () => Navigator.pop(context),
                    onShare: () {},
                    onRefresh: _load,
                    onManage: null,
                  ),
                  Expanded(
                    child: _ErrorView(message: _error!, onRetry: _load),
                  ),
                ],
              )
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final activity = _activity;
    final booking = _booking;

    if (_isCancelled) return _buildCancelledContent();

    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    final requiredDrivers = booking?.requiredDrivers ?? 1;

    final acceptedDrivers = booking?.acceptedDriversCount ?? 0;

    final bookingStatus = booking?.bookingStatus ?? '';

    final waitingDrivers =
        bookingStatus == 'waiting_for_drivers' ||
        (acceptedDrivers < requiredDrivers &&
            (activity?.status == 'pending' || activity == null));

    final tourStatus = waitingDrivers
        ? 'waiting_for_drivers'
        : activity?.tourStatus ?? 'waiting_driver';

    final statusData =
        _statusInfo[tourStatus] ??
        (
          tourStatus.replaceAll('_', ' ').toUpperCase(),
          '',
          _muted,
          Icons.info_rounded,
        );

    final (statusLabel, statusDescription, statusColor, statusIcon) =
        statusData;

    final bookingType = dbString(
      booking?.row['booking_type'],
      fallback: 'advanced',
    );

    final travelDate = booking?.travelDate;

    final adults = booking?.adults ?? 0;

    final children = booking?.children ?? 0;

    final totalAmount = booking?.totalAmount ?? 0;

    final driverName = _driverInfo?.name ?? '';

    final driverPhone = _driverInfo?.phoneNumber ?? '';

    final vehicleDetails = _driverInfo?.vehicleDetails ?? '';

    final driverRating = _driverInfo?.profile?.averageRating ?? 0;

    final driverReviewCount = _driverInfo?.profile?.totalReviews ?? 0;

    final completed = tourStatus == 'completed' || tourStatus == 'dropped_off';

    return Column(
      children: [
        // ===================================================================
        // CONSISTENT COMPACT TOP BAR
        // ===================================================================
        _TrackingTopBar(
          eta: _eta,
          onBack: () => Navigator.pop(context),
          onShare: () {
            ShareTripBottomSheet.show(
              context,
              bookingId: widget.bookingId,
              travelDate: _booking?.travelDate,
            );
          },
          onRefresh: _load,
          onManage: _canOfferCancellation ? _manageCancellation : null,
        ),

        Expanded(
          child: RefreshIndicator(
            color: _primary,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // ===========================================================
                // LIVE TOUR STATUS
                // ===========================================================
                _TourStatusHero(
                  icon: statusIcon,
                  title: statusLabel,
                  subtitle: statusDescription,
                  color: statusColor,
                  eta: _eta,
                  completed: _completedSpotCount,
                  total: _spots.length,
                ),

                const SizedBox(height: 14),

                // ===========================================================
                // MAP
                // ===========================================================
                _TourMapCard(
                  initialCenter: _initialCenter,
                  markers: _markers,
                  polylines: _polylines,
                  isFollowing: _isFollowingDriver,
                  onMapCreated: (controller) {
                    _mapCtrl = controller;
                    _animateCameraToRelevant();
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

                    _animateCameraToPickup();
                  },
                  onDriverTap: () {
                    setState(() {
                      _isFollowingDriver = true;
                    });

                    _animateCameraToRelevant();
                  },
                ),

                const SizedBox(height: 14),

                // ===========================================================
                // WAITING FOR MULTIPLE DRIVERS
                // ===========================================================
                if (waitingDrivers) ...[
                  _FindingDriversCard(
                    acceptedDrivers: acceptedDrivers,
                    requiredDrivers: requiredDrivers,
                  ),
                  const SizedBox(height: 14),
                ],

                // ===========================================================
                // CURRENT DESTINATION
                // ===========================================================
                if (!completed && _currentItineraryItem != null) ...[
                  _CurrentTourStopCard(
                    spot: _currentItineraryItem!,
                    completedCount: _completedSpotCount,
                    totalCount: _spots.length,
                    eta: _eta,
                  ),
                  const SizedBox(height: 14),
                ],

                // ===========================================================
                // DRIVER
                // ===========================================================
                if (driverName.isNotEmpty) ...[
                  _DriverCard(
                    name: driverName,
                    phone: driverPhone,
                    vehicle: vehicleDetails,
                    avatarUrl:
                        _driverInfo?.profile?.avatarUrl.isNotEmpty == true
                        ? _driverInfo!.profile!.avatarUrl
                        : _driverInfo?.profile?.profileImageUrl ?? '',
                    rating: driverRating,
                    reviewCount: driverReviewCount,
                    onCall: driverPhone.isEmpty
                        ? null
                        : () => _launchPhone(driverPhone),
                    onMessage: _openDriverChat,
                  ),
                  const SizedBox(height: 14),
                ],

                // ===========================================================
                // EMERGENCY
                // ===========================================================
                _EmergencyPanel(
                  bookingId: widget.bookingId,
                  activityId: _activity?.row['id']?.toString(),
                  driverId: _booking?.assignedDriverId ?? _activity?.driverId,
                  tripStatus: activity?.tourStatus ?? '',
                  currentSpotName: _currentItineraryItem?.destinationName,
                  driverName: driverName.isNotEmpty ? driverName : null,
                  contacts: _emergencyContacts,
                ),

                const SizedBox(height: 14),

                // ===========================================================
                // ITINERARY
                // ===========================================================
                if (_spots.isNotEmpty) ...[
                  _ItineraryProgressCard(
                    spots: _spots,
                    currentItemId: _currentItineraryItem?.id?.toString(),
                    tourStatus: tourStatus,
                  ),
                  const SizedBox(height: 14),
                ],

                // ===========================================================
                // PICKUP / DROP-OFF
                // ===========================================================
                if (booking != null) ...[
                  _LocationsCard(
                    pickup: booking.pickupAddress,
                    dropoff: booking.dropoffAddress,
                    tourStatus: tourStatus,
                  ),
                  const SizedBox(height: 14),
                ],

                // ===========================================================
                // PAYMENTS
                // ===========================================================
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
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 14),
                ],

                // ===========================================================
                // BOOKING SUMMARY
                // ===========================================================
                _BookingSummaryCard(
                  date: travelDate,
                  bookingType: bookingType,
                  adults: adults,
                  children: children,
                  tricycles: requiredDrivers,
                  totalAmount: money.format(totalAmount),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCancelledContent() {
    final booking = _booking;
    final reason = booking?.cancelledReason.trim();
    final refund = booking?.refundableAmount ?? 0;
    final paid = _paymentRecords
        .where((record) => record.isConfirmed)
        .fold<double>(0, (total, record) => total + record.amount);
    final refundText = paid <= 0
        ? 'No payment was made'
        : refund > 0
        ? '${NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(refund)} refund pending'
        : 'Non-refundable';

    return Column(
      children: [
        _TrackingTopBar(
          eta: null,
          onBack: () => Navigator.pop(context),
          onShare: () {},
          onRefresh: _load,
          onManage: null,
        ),
        Expanded(
          child: RefreshIndicator(
            color: _primary,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: _dangerSoft,
                        child: Icon(
                          Icons.event_busy_rounded,
                          color: _danger,
                          size: 29,
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
                      const SizedBox(height: 6),
                      const Text(
                        'This booking remains in your history for reference.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted),
                      ),
                      const SizedBox(height: 18),
                      _CancelledDetail(
                        label: 'Tour date',
                        value: booking?.travelDate == null
                            ? 'Schedule unavailable'
                            : DateFormat(
                                'MMM d, yyyy',
                              ).format(booking!.travelDate!),
                      ),
                      _CancelledDetail(
                        label: 'Cancelled',
                        value: booking?.cancelledAt == null
                            ? 'Recently'
                            : DateFormat(
                                'MMM d, yyyy • h:mm a',
                              ).format(booking!.cancelledAt!),
                      ),
                      _CancelledDetail(
                        label: 'Reason',
                        value: reason == null || reason.isEmpty
                            ? 'Not specified'
                            : reason,
                      ),
                      _CancelledDetail(label: 'Refund', value: refundText),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: _primary,
                  ),
                  child: const Text('Back to Bookings'),
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

class _TrackingTopBar extends StatelessWidget {
  const _TrackingTopBar({
    required this.eta,
    required this.onBack,
    required this.onShare,
    required this.onRefresh,
    this.onManage,
  });

  final String? eta;

  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback onRefresh;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: _background,
      child: Row(
        children: [
          _TopIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),

          const SizedBox(width: 11),

          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tour Tracking',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 17.5,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Live trip progress',
                  style: TextStyle(
                    color: _subtle,
                    fontWeight: FontWeight.w600,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),

          if (eta != null && eta!.trim().isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _softBlue,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_rounded, size: 12, color: _primary),
                  const SizedBox(width: 4),
                  Text(
                    eta!,
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 6),
          ],

          _TopIconButton(icon: Icons.share_location_outlined, onTap: onShare),

          const SizedBox(width: 6),

          _TopIconButton(icon: Icons.refresh_rounded, onTap: onRefresh),

          if (onManage != null) ...[
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: 'Manage booking',
              onSelected: (_) => onManage!(),
              itemBuilder: (_) => const [
                PopupMenuItem<String>(
                  value: 'cancel',
                  child: Row(
                    children: [
                      Icon(Icons.event_busy_outlined, color: _danger, size: 20),
                      SizedBox(width: 9),
                      Text('Cancel Booking'),
                    ],
                  ),
                ),
              ],
              child: const SizedBox(
                width: 38,
                height: 38,
                child: Icon(Icons.more_vert_rounded, color: _ink),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CancelledDetail extends StatelessWidget {
  const _CancelledDetail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _border)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(label, style: const TextStyle(color: _muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 17, color: _ink),
        ),
      ),
    );
  }
}

// ============================================================================
// STATUS HERO
// ============================================================================

class _TourStatusHero extends StatelessWidget {
  const _TourStatusHero({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.eta,
    required this.completed,
    required this.total,
  });

  final IconData icon;

  final String title;
  final String subtitle;

  final Color color;

  final String? eta;

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, _primaryLight, 0.42) ?? color],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
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
                child: Icon(icon, color: Colors.white, size: 21),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: -0.2,
                      ),
                    ),

                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (eta != null && eta!.trim().isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    eta!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 9,
                    ),
                  ),
                ),
            ],
          ),

          if (total > 0) ...[
            const SizedBox(height: 14),

            Row(
              children: [
                Text(
                  '$completed of $total destinations completed',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                    fontSize: 9.2,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
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
// MAP CARD
// ============================================================================

class _TourMapCard extends StatelessWidget {
  const _TourMapCard({
    required this.initialCenter,
    required this.markers,
    required this.polylines,
    required this.isFollowing,
    required this.onMapCreated,
    required this.onCameraMoveStarted,
    required this.onCameraIdle,
    required this.onPickupTap,
    required this.onDriverTap,
  });

  final LatLng initialCenter;

  final Set<Marker> markers;
  final Set<Polyline> polylines;

  final bool isFollowing;

  final ValueChanged<GoogleMapController> onMapCreated;

  final VoidCallback onCameraMoveStarted;
  final VoidCallback onCameraIdle;

  final VoidCallback onPickupTap;
  final VoidCallback onDriverTap;

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.31).clamp(
      240.0,
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
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
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
                  target: initialCenter,
                  zoom: 14,
                ),
                markers: markers,
                polylines: polylines,
                onMapCreated: onMapCreated,
                onCameraMoveStarted: onCameraMoveStarted,
                onCameraIdle: onCameraIdle,
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
                      isFollowing ? 'FOLLOWING DRIVER' : 'LIVE TOUR MAP',
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
                  _MapActionButton(
                    icon: Icons.hail_rounded,
                    color: _success,
                    onTap: onPickupTap,
                  ),
                  const SizedBox(height: 8),
                  _MapActionButton(
                    icon: Icons.my_location_rounded,
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
              right: 72,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MapLegendItem(color: _primary, text: 'Driver'),
                    SizedBox(width: 10),
                    _MapLegendItem(color: Color(0xFFF59E0B), text: 'Current'),
                    SizedBox(width: 10),
                    _MapLegendItem(color: _success, text: 'Done'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final Color color;

  final VoidCallback onTap;

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      color: active ? color : Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 19, color: active ? Colors.white : color),
        ),
      ),
    );
  }
}

class _MapLegendItem extends StatelessWidget {
  const _MapLegendItem({required this.color, required this.text});

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
            fontSize: 8,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// FINDING DRIVERS
// ============================================================================

class _FindingDriversCard extends StatelessWidget {
  const _FindingDriversCard({
    required this.acceptedDrivers,
    required this.requiredDrivers,
  });

  final int acceptedDrivers;
  final int requiredDrivers;

  @override
  Widget build(BuildContext context) {
    final progress = requiredDrivers > 0
        ? acceptedDrivers / requiredDrivers
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _warningSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE3A7)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 41,
                height: 41,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.electric_rickshaw_rounded,
                  color: _warning,
                  size: 20,
                ),
              ),

              const SizedBox(width: 10),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Finding Your Drivers',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Waiting for all required drivers to accept.',
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),

              Text(
                '$acceptedDrivers/$requiredDrivers',
                style: const TextStyle(
                  color: _warning,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: _warning.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(_warning),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CURRENT STOP
// ============================================================================

class _CurrentTourStopCard extends StatelessWidget {
  const _CurrentTourStopCard({
    required this.spot,
    required this.completedCount,
    required this.totalCount,
    required this.eta,
  });

  final BookingItineraryItem spot;

  final int completedCount;
  final int totalCount;

  final String? eta;

  @override
  Widget build(BuildContext context) {
    final atSpot = spot.spotStatus == 'at_spot';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFCFE2FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: atSpot ? _successSoft : _softBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              atSpot ? Icons.place_rounded : Icons.navigation_rounded,
              color: atSpot ? _success : _primary,
              size: 20,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  atSpot ? 'CURRENT DESTINATION' : 'NEXT DESTINATION',
                  style: TextStyle(
                    color: atSpot ? _success : _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 8.2,
                    letterSpacing: 0.5,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  spot.destinationName,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),

                if (spot.destinationAddress.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),

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
                    _InfoChip(
                      icon: Icons.flag_outlined,
                      text: 'Stop ${completedCount + 1} of $totalCount',
                    ),
                    if (eta != null && eta!.trim().isNotEmpty)
                      _InfoChip(icon: Icons.schedule_rounded, text: eta!),
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

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
          Icon(icon, size: 10, color: _muted),
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
      ),
    );
  }
}

// ============================================================================
// DRIVER CARD
// ============================================================================

class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.name,
    required this.phone,
    required this.vehicle,
    required this.avatarUrl,
    required this.rating,
    required this.reviewCount,
    required this.onCall,
    required this.onMessage,
  });

  final String name;
  final String phone;
  final String vehicle;
  final String avatarUrl;

  final double rating;
  final int reviewCount;

  final VoidCallback? onCall;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return _ModernCard(
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _softBlue,
              border: Border.all(color: const Color(0xFFD4E5FF)),
            ),
            child: ClipOval(
              child: avatarUrl.isNotEmpty
                  ? Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _DriverAvatarFallback(),
                    )
                  : const _DriverAvatarFallback(),
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOUR DRIVER',
                  style: TextStyle(
                    color: _subtle,
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                    letterSpacing: 0.5,
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

                if (vehicle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    vehicle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 9.5,
                    ),
                  ),
                ],

                if (reviewCount > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 13,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${rating.toStringAsFixed(1)} ($reviewCount)',
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          _DriverContactButton(
            icon: Icons.call_outlined,
            color: _success,
            enabled: onCall != null,
            onTap: onCall,
          ),

          const SizedBox(width: 7),

          _DriverContactButton(
            icon: Icons.chat_bubble_outline_rounded,
            color: _primary,
            enabled: true,
            onTap: onMessage,
          ),
        ],
      ),
    );
  }
}

class _DriverAvatarFallback extends StatelessWidget {
  const _DriverAvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _softBlue,
      child: const Icon(Icons.person_rounded, color: _primary, size: 26),
    );
  }
}

class _DriverContactButton extends StatelessWidget {
  const _DriverContactButton({
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color color;

  final bool enabled;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? color.withValues(alpha: 0.09) : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 18, color: enabled ? color : _subtle),
        ),
      ),
    );
  }
}

// ============================================================================
// ITINERARY
// ============================================================================

class _ItineraryProgressCard extends StatelessWidget {
  const _ItineraryProgressCard({
    required this.spots,
    required this.currentItemId,
    required this.tourStatus,
  });

  final List<BookingItineraryItem> spots;

  final String? currentItemId;

  final String tourStatus;

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
                width: 37,
                height: 37,
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
                        fontSize: 13.5,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Track your progress through every destination',
                      style: TextStyle(
                        color: _subtle,
                        fontWeight: FontWeight.w600,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$completed/${spots.length}',
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
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

          ...spots.asMap().entries.map((entry) {
            final index = entry.key;
            final spot = entry.value;

            final done = spot.spotStatus == 'completed';

            final current =
                !done &&
                spot.id?.toString() == currentItemId &&
                _tourIsActive(tourStatus);

            return _TourSpotTimelineRow(
              index: index + 1,
              spot: spot,
              done: done,
              current: current,
              last: index == spots.length - 1,
            );
          }),
        ],
      ),
    );
  }

  bool _tourIsActive(String status) {
    return status == 'picked_up' ||
        status == 'on_tour' ||
        status == 'en_route_to_spot' ||
        status == 'at_spot';
  }
}

class _TourSpotTimelineRow extends StatelessWidget {
  const _TourSpotTimelineRow({
    required this.index,
    required this.spot,
    required this.done,
    required this.current,
    required this.last,
  });

  final int index;

  final BookingItineraryItem spot;

  final bool done;
  final bool current;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? _success
        : current
        ? _primary
        : const Color(0xFFCBD5E1);

    final timeFormat = DateFormat('h:mm a');

    final schedule = _buildTimeLabel(spot.arrivalTime, spot.departureTime);

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
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done
                      ? _successSoft
                      : current
                      ? _softBlue
                      : const Color(0xFFF4F6F9),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: current ? 2 : 1.5),
                ),
                child: done
                    ? const Icon(Icons.check_rounded, color: _success, size: 15)
                    : Text(
                        '$index',
                        style: TextStyle(
                          color: current ? _primary : _subtle,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
              ),

              if (!last)
                Container(
                  width: 2,
                  height: 52,
                  color: color.withValues(alpha: 0.22),
                ),
            ],
          ),
        ),

        const SizedBox(width: 9),

        Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: last ? 0 : 9),
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: BoxDecoration(
              color: current ? const Color(0xFFF7FAFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              border: current
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
                          color: done ? _muted : _ink,
                          fontWeight: current
                              ? FontWeight.w900
                              : FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),

                    if (current)
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
                            fontSize: 7,
                          ),
                        ),
                      ),
                  ],
                ),

                if (schedule.isNotEmpty) ...[
                  const SizedBox(height: 5),

                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        color: _subtle,
                        size: 11,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        schedule,
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 8.8,
                        ),
                      ),
                    ],
                  ),
                ],

                if (spot.actualArrivalTime != null) ...[
                  const SizedBox(height: 5),

                  _ActualStatusBadge(
                    icon: Icons.location_on_rounded,
                    text:
                        'Arrived ${timeFormat.format(spot.actualArrivalTime!.toLocal())}',
                    color: _primary,
                  ),
                ],

                if (spot.actualDepartureTime != null) ...[
                  const SizedBox(height: 4),

                  _ActualStatusBadge(
                    icon: Icons.check_circle_rounded,
                    text:
                        'Completed ${timeFormat.format(spot.actualDepartureTime!.toLocal())}',
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

  String _buildTimeLabel(String arrival, String departure) {
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

class _ActualStatusBadge extends StatelessWidget {
  const _ActualStatusBadge({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
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
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 8.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// LOCATIONS
// ============================================================================

class _LocationsCard extends StatelessWidget {
  const _LocationsCard({
    required this.pickup,
    required this.dropoff,
    required this.tourStatus,
  });

  final String pickup;
  final String dropoff;
  final String tourStatus;

  @override
  Widget build(BuildContext context) {
    final pickupDone =
        tourStatus == 'driver_arrived' ||
        tourStatus == 'picked_up' ||
        tourStatus == 'on_tour' ||
        tourStatus == 'en_route_to_spot' ||
        tourStatus == 'at_spot' ||
        tourStatus == 'en_route_to_dropoff' ||
        tourStatus == 'ready_to_complete' ||
        tourStatus == 'completed';

    final dropoffDone =
        tourStatus == 'ready_to_complete' ||
        tourStatus == 'dropped_off' ||
        tourStatus == 'completed';

    return _ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            icon: Icons.route_outlined,
            title: 'Pickup & Drop-off',
            subtitle: 'Your main trip route',
          ),

          const SizedBox(height: 14),

          _LocationTimelineRow(
            color: _success,
            icon: pickupDone ? Icons.check_rounded : Icons.trip_origin_rounded,
            label: 'PICKUP',
            address: pickup.isEmpty ? 'Pickup location unavailable' : pickup,
            complete: pickupDone,
            line: true,
          ),

          _LocationTimelineRow(
            color: _danger,
            icon: dropoffDone ? Icons.check_rounded : Icons.location_on_rounded,
            label: 'DROP-OFF',
            address: dropoff.isEmpty
                ? 'Drop-off location unavailable'
                : dropoff,
            complete: dropoffDone,
            line: false,
          ),
        ],
      ),
    );
  }
}

class _LocationTimelineRow extends StatelessWidget {
  const _LocationTimelineRow({
    required this.color,
    required this.icon,
    required this.label,
    required this.address,
    required this.complete,
    required this.line,
  });

  final Color color;

  final IconData icon;

  final String label;
  final String address;

  final bool complete;
  final bool line;

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
                child: Icon(icon, size: 15, color: color),
              ),

              if (line)
                Container(width: 2, height: 37, color: const Color(0xFFDCE5F0)),
            ],
          ),
        ),

        const SizedBox(width: 9),

        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: line ? 12 : 0),
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
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  complete
                      ? 'Completed'
                      : label == 'PICKUP'
                      ? 'Tour starting point'
                      : 'Final destination',
                  style: TextStyle(
                    color: complete ? _success : _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 8.5,
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
// PAYMENT CARD
// ============================================================================

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
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    final payment = record;
    final status = payment?.status;

    Color statusColor = _muted;
    Color statusBackground = const Color(0xFFF1F5F9);

    String statusText = 'Not yet paid';

    if (status == 'confirmed') {
      statusColor = _success;
      statusBackground = _successSoft;
      statusText = 'Confirmed';
    } else if (status == 'pending_confirmation') {
      statusColor = _warning;
      statusBackground = _warningSoft;
      statusText = 'Awaiting confirmation';
    } else if (status == 'disputed') {
      statusColor = _danger;
      statusBackground = _dangerSoft;
      statusText = 'Disputed';
    }

    return _ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.payments_outlined,
                  color: _primary,
                  size: 19,
                ),
              ),

              const SizedBox(width: 10),

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
                      money.format(amount),
                      style: const TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 45,
            child: status == 'confirmed'
                ? OutlinedButton.icon(
                    onPressed: () => onViewReceipt(payment!),
                    icon: const Icon(Icons.receipt_long_rounded, size: 17),
                    label: const Text('View Receipt'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: const BorderSide(color: Color(0xFFD5E5FF)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  )
                : status == 'pending_confirmation'
                ? Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _warningSoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Text(
                      'Waiting for driver confirmation',
                      style: TextStyle(
                        color: _warning,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: onPay,
                    icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                    label: const Text('Pay with GCash'),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// BOOKING SUMMARY
// ============================================================================

class _BookingSummaryCard extends StatelessWidget {
  const _BookingSummaryCard({
    required this.date,
    required this.bookingType,
    required this.adults,
    required this.children,
    required this.tricycles,
    required this.totalAmount,
  });

  final DateTime? date;

  final String bookingType;

  final int adults;
  final int children;
  final int tricycles;

  final String totalAmount;

  @override
  Widget build(BuildContext context) {
    return _ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            icon: Icons.receipt_long_outlined,
            title: 'Booking Summary',
            subtitle: 'Your tour booking information',
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _BookingMetric(
                  icon: Icons.groups_outlined,
                  label: 'PASSENGERS',
                  value: '${adults + children}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BookingMetric(
                  icon: Icons.electric_rickshaw_outlined,
                  label: 'TRICYCLES',
                  value: '$tricycles',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BookingMetric(
                  icon: Icons.payments_outlined,
                  label: 'TOTAL',
                  value: totalAmount,
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          const Divider(height: 1, color: Color(0xFFEDF1F6)),

          const SizedBox(height: 12),

          _BookingDetailRow(
            icon: Icons.calendar_today_outlined,
            label: 'Travel Date',
            value: date == null
                ? '—'
                : DateFormat('MMMM d, yyyy').format(date!),
          ),

          const SizedBox(height: 9),

          _BookingDetailRow(
            icon: Icons.event_outlined,
            label: 'Booking Type',
            value: bookingType == 'same_day'
                ? 'Same-Day Booking'
                : 'Advanced Booking',
          ),

          const SizedBox(height: 9),

          _BookingDetailRow(
            icon: Icons.groups_2_outlined,
            label: 'Participants',
            value:
                '$adults adult${adults == 1 ? '' : 's'}'
                '${children > 0 ? ' • $children child${children == 1 ? '' : 'ren'}' : ''}',
          ),
        ],
      ),
    );
  }
}

class _BookingMetric extends StatelessWidget {
  const _BookingMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: _primary, size: 16),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _subtle,
              fontWeight: FontWeight.w800,
              fontSize: 7,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingDetailRow extends StatelessWidget {
  const _BookingDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;

  final String label;
  final String value;

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
                  fontSize: 8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
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
// SHARED CARD
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
                  fontSize: 9,
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
// LOADING / ERROR
// ============================================================================

class _LoadingView extends StatelessWidget {
  const _LoadingView();

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
            'Preparing live tour tracking...',
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
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
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// EMERGENCY PANEL
// ============================================================================

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

  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _scale = Tween<double>(
      begin: 1,
      end: 1.025,
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
    if (_cooldownUntil == null) {
      return;
    }

    final remaining = _cooldownUntil!.difference(DateTime.now());

    setState(() {
      _cooldownSecondsLeft = remaining.isNegative ? 0 : remaining.inSeconds;
    });
  }

  Future<void> _onEmergencyPressed() async {
    if (_sending || _inCooldown) {
      return;
    }

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

    setState(() {
      _sending = true;
    });

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
            final firstName = (profile['first_name'] as String?) ?? '';

            final lastName = (profile['last_name'] as String?) ?? '';

            touristName = '$firstName $lastName'.trim();
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

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text(
              'Emergency alert sent. Help is on the way.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            backgroundColor: _success,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Failed to send alert: $e'),
            backgroundColor: _danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      noteController.dispose();

      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryContact = widget.contacts.firstOrNull;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _dangerSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.emergency_outlined,
                  color: _danger,
                  size: 20,
                ),
              ),

              const SizedBox(width: 10),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Assistance',
                      style: TextStyle(
                        color: Color(0xFF7F1D1D),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Use only when immediate assistance is needed.',
                      style: TextStyle(
                        color: Color(0xFF9A5050),
                        fontWeight: FontWeight.w600,
                        fontSize: 9.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (_inCooldown)
            _CooldownButton(secondsLeft: _cooldownSecondsLeft)
          else
            ScaleTransition(
              scale: _scale,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : _onEmergencyPressed,
                  icon: _sending
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.emergency_rounded, size: 18),
                  label: Text(
                    _sending ? 'Sending Alert...' : 'Emergency Alert',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: _danger,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),

          if (primaryContact != null) ...[
            const SizedBox(height: 9),

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
    final minutes = secondsLeft ~/ 60;

    final seconds = secondsLeft % 60;

    return Container(
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        color: _successSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded, color: _success, size: 18),

          const SizedBox(width: 7),

          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Alert Sent',
                style: TextStyle(
                  color: _success,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
              Text(
                'Available again in ${minutes}m ${seconds.toString().padLeft(2, '0')}s',
                style: const TextStyle(
                  color: _success,
                  fontWeight: FontWeight.w600,
                  fontSize: 8,
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
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 55,
              height: 55,
              decoration: const BoxDecoration(
                color: _dangerSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emergency_rounded,
                color: _danger,
                size: 28,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Send Emergency Alert?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Your location and current tour information will be sent immediately.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _muted,
                fontWeight: FontWeight.w600,
                fontSize: 10,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 14),

            const _NotifyItem(
              Icons.person_outline_rounded,
              'Your emergency contacts',
            ),

            const _NotifyItem(
              Icons.electric_rickshaw_outlined,
              'Your assigned driver',
            ),

            const _NotifyItem(
              Icons.business_outlined,
              'TourisTrike tourism office',
            ),

            const SizedBox(height: 13),

            TextField(
              controller: noteController,
              maxLength: 200,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add a note (optional)',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.all(12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: _danger),
                ),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _muted,
                  side: const BorderSide(color: _border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),

            const SizedBox(width: 9),

            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: _danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Text(
                  'Send Alert',
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: _danger),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 10,
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline_rounded, color: _danger, size: 15),

          const SizedBox(width: 7),

          Expanded(
            child: Text(
              contact.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),

          if (phone.isNotEmpty)
            Material(
              color: _danger,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () async {
                  final uri = Uri.parse('tel:$phone');

                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.call_rounded, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Call',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 9,
                        ),
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
