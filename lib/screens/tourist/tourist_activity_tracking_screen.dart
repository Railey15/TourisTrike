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
import 'package:touristrike/components/tourist/driver_review_modal.dart';
import 'package:touristrike/screens/tourist/tourist_messages_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class ActivityTrackingScreen extends StatefulWidget {
  const ActivityTrackingScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<ActivityTrackingScreen> createState() => _ActivityTrackingScreenState();
}

class _ActivityTrackingScreenState extends State<ActivityTrackingScreen> {
  static const _apiKey = CitySpotSuggestionService.defaultGoogleMapsApiKey;

  final _repo = TourisTrikeRepository();
  final _supabase = Supabase.instance.client;

  PackageActivity? _activity;
  PackageBooking? _booking;
  DriverInfo? _driverInfo;
  List<BookingItineraryItem> _spots = [];
  List<EmergencyContactRecord> _emergencyContacts = [];

  bool _loading = true;
  String? _error;
  String? _eta;
  bool _reviewShown = false;

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _activityChannel?.unsubscribe();
    _locationChannel?.unsubscribe();
    _bookingChannel?.unsubscribe();
    _itineraryChannel?.unsubscribe();
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
      final booking = await _repo.fetchPackageBookingDetails(widget.bookingId);
      final spots = await _repo.fetchBookingItinerary(widget.bookingId);
      final emergencyContacts = await _repo.fetchEmergencyContacts();

      DriverInfo? driverInfo;
      final driverId = booking?.assignedDriverId ?? activity?.driverId ?? '';
      if (driverId.isNotEmpty) {
        driverInfo = await _repo.fetchDriverInfo(driverId);
      }

      if (!mounted) return;
      setState(() {
        _activity = activity;
        _booking = booking;
        _driverInfo = driverInfo;
        _spots = spots;
        _emergencyContacts = emergencyContacts;
        _loading = false;
      });

      _debugTourState('load');
      _buildMarkers();
      _fetchCurrentRoute();

      _subscribeToActivity(driverId);
      _subscribeToBooking(widget.bookingId);
      _checkAndShowReviewModal();
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
              if (lat == null || lng == null) return;
              // Update driver position in the activity row locally
              if (_activity != null) {
                setState(() {
                  _activity = PackageActivity({
                    ..._activity!.row,
                    'driver_latitude': lat.toDouble(),
                    'driver_longitude': lng.toDouble(),
                    'driver_last_seen': newRow['updated_at'],
                  });
                });
                _buildMarkers();
                _animateCameraToDriver();
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
          callback: (_) => _refreshSpots(logTag: 'itinerary-update'),
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

    final alreadyReviewed = await _repo.hasReviewedBooking(bookingId);
    if (alreadyReviewed) {
      _reviewShown = true;
      return;
    }

    if (!mounted) return;
    setState(() => _reviewShown = true);

    await DriverReviewModal.show(
      context,
      bookingId: bookingId,
      driverId: driverId,
      driverName: _driverInfo?.name ?? '',
      driverAvatarUrl: _driverInfo?.profile?.avatarUrl.isNotEmpty == true
          ? _driverInfo!.profile!.avatarUrl
          : _driverInfo?.profile?.profileImageUrl ?? '',
    );
  }

  // ── Booking status (driver acceptance counter) ───────────────
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

    final currentItem = _currentItineraryItem;
    for (var i = 0; i < _spots.length; i++) {
      final spot = _spots[i];
      if (spot.latitude == 0 && spot.longitude == 0) continue;
      final isCompleted = spot.spotStatus == 'completed';
      final isCurrent = !isCompleted && spot.id == currentItem?.id;
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
            title: 'Stop ${i + 1}: ${spot.destinationName}',
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
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: const InfoWindow(title: 'Your Driver'),
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

    final result = await _fetchRoute(origin, destination);
    if (!mounted) return;
    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: result.points,
          color: const Color(0xFF2A86FF),
          width: 5,
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

  Future<_RouteResult> _fetchRoute(LatLng origin, LatLng dest) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${dest.latitude},${dest.longitude}'
        '&mode=driving'
        '&key=$_apiKey',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = (body['routes'] as List?) ?? const [];
        if (routes.isNotEmpty) {
          final route = routes.first as Map;
          final encoded = route['overview_polyline']?['points'] as String?;
          final legs = (route['legs'] as List?) ?? const [];
          String? durationText;
          if (legs.isNotEmpty) {
            final leg = legs.first as Map;
            durationText = leg['duration']?['text'] as String?;
          }
          if (encoded != null) {
            return _RouteResult(
              points: _decodePolyline(encoded),
              durationText: durationText,
            );
          }
        }
      }
    } catch (_) {}
    return _RouteResult(points: [origin, dest]);
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
      lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  void _animateCameraToDriver() {
    final activity = _activity;
    if (_mapCtrl == null || activity?.driverLatitude == null) return;
    _mapCtrl!.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(activity!.driverLatitude!, activity.driverLongitude!),
      ),
    );
  }

  void _animateCameraToRelevant() {
    if (_mapCtrl == null) return;
    final activity = _activity;
    final booking = _booking;
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

  // ── Emergency helpers ────────────────────────────────────────
  EmergencyContactRecord? get _primaryEmergencyContact =>
      _emergencyContacts.isEmpty ? null : _emergencyContacts.first;

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

  Future<void> _launchSms(String phone, {String body = ''}) async {
    final normalized = phone.trim();
    if (normalized.isEmpty) return;
    final uri = Uri.parse(
      body.isEmpty
          ? 'sms:$normalized'
          : 'sms:$normalized?body=${Uri.encodeComponent(body)}',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _shareLiveLocation() async {
    final contact = _primaryEmergencyContact;
    if (contact == null) {
      _showSnack('Add an emergency contact first.');
      return;
    }
    try {
      final position = await Geolocator.getCurrentPosition();
      final mapsLink =
          'https://maps.google.com/?q=${position.latitude},${position.longitude}';
      await _launchSms(
        contact.phoneNumber,
        body:
            'TourisTrike emergency location: '
            '${position.latitude.toStringAsFixed(6)}, '
            '${position.longitude.toStringAsFixed(6)}\n$mapsLink',
      );
    } catch (_) {
      _showSnack('Unable to get your current location right now.');
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
    final mapHeight = (size.height * 0.32).clamp(200.0, 320.0);

    // Show "Finding Drivers" overlay until all drivers accept
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
        Column(
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
                  _CircleBtn(icon: Icons.refresh_rounded, onTap: _load),
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
                      eta: _eta,
                    ),
                    const SizedBox(height: 12),

                    // ── Group Booking Counter ─────────────────────
                    if (requiredDrivers > 1) ...[
                      _GroupBookingCard(
                        requiredDrivers: requiredDrivers,
                        acceptedDrivers: acceptedDrivers,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Emergency shortcuts ───────────────────────
                    _EmergencyShortcutCard(
                      contact: _primaryEmergencyContact,
                      onCall: _primaryEmergencyContact == null
                          ? null
                          : () => _launchPhone(
                              _primaryEmergencyContact!.phoneNumber,
                            ),
                      onText: _primaryEmergencyContact == null
                          ? null
                          : () => _launchSms(
                              _primaryEmergencyContact!.phoneNumber,
                            ),
                      onShareLocation: _primaryEmergencyContact == null
                          ? null
                          : _shareLiveLocation,
                    ),
                    const SizedBox(height: 12),

                    // ── Map ───────────────────────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        height: mapHeight,
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
                                        const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF59E0B)),
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
                              child: Divider(
                                height: 1,
                                color: Color(0xFFE7EEF7),
                              ),
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

                    // ── Tour Spots ────────────────────────────────
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
                  ],
                ),
              ),
            ),
          ],
        ), // end Column
        // ── Finding Drivers overlay ───────────────────────────────
        if (isWaitingForDrivers)
          _FindingDriversOverlay(
            accepted: acceptedDrivers,
            required: requiredDrivers,
          ),
      ], // end Stack.children
    ); // end Stack
  }
}

// ── Route result ──────────────────────────────────────────────
class _RouteResult {
  const _RouteResult({required this.points, this.durationText});
  final List<LatLng> points;
  final String? durationText;
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

class _GroupBookingCard extends StatelessWidget {
  const _GroupBookingCard({
    required this.requiredDrivers,
    required this.acceptedDrivers,
  });

  final int requiredDrivers;
  final int acceptedDrivers;

  @override
  Widget build(BuildContext context) {
    final allAccepted = acceptedDrivers >= requiredDrivers;
    final color = allAccepted
        ? const Color(0xFF16A34A)
        : const Color(0xFFF59E0B);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              allAccepted ? Icons.groups_rounded : Icons.hourglass_top_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allAccepted
                      ? 'All Drivers Confirmed'
                      : 'Waiting for Drivers ($acceptedDrivers / $requiredDrivers)',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'This tour requires $requiredDrivers tricycle${requiredDrivers > 1 ? 's' : ''} for your group.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
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
}

class _EmergencyShortcutCard extends StatelessWidget {
  const _EmergencyShortcutCard({
    required this.contact,
    required this.onCall,
    required this.onText,
    required this.onShareLocation,
  });

  final EmergencyContactRecord? contact;
  final VoidCallback? onCall;
  final VoidCallback? onText;
  final VoidCallback? onShareLocation;

  @override
  Widget build(BuildContext context) {
    final hasContact = contact != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF7ED), Color(0xFFFFFBEB)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFED7AA)),
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
                  color: const Color(0xFFFFEDD5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.emergency_share_rounded,
                  color: Color(0xFFEA580C),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Emergency Shortcuts',
                      style: TextStyle(
                        color: Color(0xFF9A3412),
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      hasContact
                          ? 'Quick access for ${contact!.name}'
                          : 'Add an emergency contact in your profile.',
                      style: const TextStyle(
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _EmergencyActionButton(
                  icon: Icons.call_rounded,
                  label: 'Call',
                  onTap: onCall,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _EmergencyActionButton(
                  icon: Icons.sms_rounded,
                  label: 'Text',
                  onTap: onText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _EmergencyActionButton(
                  icon: Icons.my_location_rounded,
                  label: 'Share',
                  onTap: onShareLocation,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmergencyActionButton extends StatelessWidget {
  const _EmergencyActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: onTap == null ? const Color(0xFFFDE7D8) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: onTap == null
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFEA580C),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: onTap == null
                    ? const Color(0xFFC2410C)
                    : const Color(0xFF9A3412),
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
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
                  // Scheduled times
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
                  // Actual times (shown when available)
                  if (actualArrival != null || actualDeparture != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 11,
                            color: Color(0xFF16A34A),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _buildActualTimeLabel(
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
                    ),
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

  String _buildActualTimeLabel(
    DateTime? arrival,
    DateTime? departure,
    DateFormat fmt,
  ) {
    if (arrival != null && departure != null) {
      return 'Actual: ${fmt.format(arrival)} – ${fmt.format(departure)}';
    }
    if (arrival != null) return 'Arrived: ${fmt.format(arrival)}';
    if (departure != null) return 'Departed: ${fmt.format(departure)}';
    return '';
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
        width: 42,
        height: 42,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: const Color(0xFF0F172A), size: 20),
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

// ── Finding Drivers overlay ───────────────────────────────────
// Shown on top of the tracking screen until all required drivers accept.
class _FindingDriversOverlay extends StatefulWidget {
  const _FindingDriversOverlay({
    required this.accepted,
    required this.required,
  });

  final int accepted;
  final int required;

  @override
  State<_FindingDriversOverlay> createState() => _FindingDriversOverlayState();
}

class _FindingDriversOverlayState extends State<_FindingDriversOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.required - widget.accepted;
    return Positioned.fill(
      child: Container(
        color: const Color(0xCC0F172A),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing icon
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) => Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        const Color(0xFF2A86FF).withValues(alpha: 0.2),
                        const Color(0xFF2A86FF).withValues(alpha: 0.5),
                        _pulse.value,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child:
                        child ??
                        const Icon(
                          Icons.electric_rickshaw_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Finding Drivers...',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Waiting for Drivers  ${widget.accepted} / ${widget.required}',
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 20),

                // Progress bar
                SizedBox(
                  width: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: widget.required > 0
                          ? widget.accepted / widget.required
                          : 0,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF2A86FF),
                      ),
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Per-slot indicator
                if (widget.required > 1)
                  Wrap(
                    spacing: 8,
                    children: List.generate(widget.required, (i) {
                      final filled = i < widget.accepted;
                      return Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: filled
                              ? const Color(0xFF2A86FF)
                              : Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: filled
                                ? const Color(0xFF2A86FF)
                                : Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(
                          filled
                              ? Icons.person_rounded
                              : Icons.person_outline_rounded,
                          color: filled
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.4),
                          size: 20,
                        ),
                      );
                    }),
                  ),
                const SizedBox(height: 20),

                Text(
                  remaining > 0
                      ? 'Waiting for $remaining more driver${remaining == 1 ? '' : 's'} to accept.'
                      : 'All drivers confirmed!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
