import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/services/booking_driver_markers.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/services/route_polyline_service.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:touristrike/widgets/convoy/convoy_tourist_driver_list.dart';
import 'package:touristrike/widgets/live_itinerary_estimates.dart';
import 'package:touristrike/core/services/itinerary_schedule_service.dart';

class GuestTripTrackingScreen extends StatefulWidget {
  const GuestTripTrackingScreen({
    super.key,
    required this.publicToken,
    required this.accessCode,
    required this.initialDetails,
    this.repository,
    this.routeService,
    this.etaService,
  });

  final String publicToken;
  final String accessCode;
  final GuestTripDetails initialDetails;
  final TourisTrikeRepository? repository;
  final RoutePolylineService? routeService;
  final ItineraryScheduleService? etaService;

  @override
  State<GuestTripTrackingScreen> createState() =>
      _GuestTripTrackingScreenState();
}

class _GuestTripTrackingScreenState extends State<GuestTripTrackingScreen> {
  static final _apiKey = CitySpotSuggestionService.resolveApiKey();
  late final _routeService =
      widget.routeService ?? RoutePolylineService(apiKey: _apiKey);

  late final _repo = widget.repository ?? TourisTrikeRepository();

  late GuestTripDetails _details;
  GoogleMapController? _mapCtrl;

  BitmapDescriptor? _tricycleMarker;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  String? _eta;
  String? _selectedDriverId;
  bool _isFollowingDriver = false;
  bool _isProgrammaticMove = false;

  Timer? _refreshTimer;
  bool _refreshing = false;
  bool _accessUnavailable = false;
  int _routeGeneration = 0;
  DateTime? _lastRouteAt;
  String? _lastRouteTarget;

  @override
  void initState() {
    super.initState();
    _details = widget.initialDetails;
    _initCustomMarkers();
    _buildMarkers();
    _fetchCurrentRoute();
    _startPeriodicRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ── Custom markers ────────────────────────────────────────────────────────

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
      debugPrint('[GuestMarkers] Failed to load custom markers: $e');
    }
  }

  // ── Itinerary helpers ─────────────────────────────────────────────────────

  Map<String, dynamic>? get _currentSpotItem {
    for (final item in _details.itineraryItems) {
      final status = item['status']?.toString() ?? '';
      if (status != 'completed') return item;
    }
    return null;
  }

  LatLng? get _currentSpotLatLng {
    final item = _currentSpotItem;
    if (item == null) return null;
    final lat = (item['latitude'] as num?)?.toDouble();
    final lng = (item['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) return null;
    return LatLng(lat, lng);
  }

  // ── Realtime subscriptions ────────────────────────────────────────────────

  void _startPeriodicRefresh() {
    if (_details.isTripEnded) return;
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshDetails();
    });
  }

  Future<void> _refreshDetails() async {
    if (_refreshing || _details.isTripEnded) return;
    _refreshing = true;
    try {
      final updated = await _repo
          .validateGuestTripLink(
            publicToken: widget.publicToken,
            accessCode: widget.accessCode,
            silent: true,
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (updated == null) throw StateError('Shared trip unavailable');
      setState(() {
        _details = updated;
        _accessUnavailable = false;
        if (!updated.drivers.any((d) => d.driverId == _selectedDriverId)) {
          _selectedDriverId = null;
        }
      });
      if (updated.isTripEnded) {
        _refreshTimer?.cancel();
        _routeGeneration++;
        setState(() {
          _polylines = {};
          _eta = null;
        });
      }
      _buildMarkers();
      if (_isFollowingDriver) _animateCameraToRelevant();
      _fetchCurrentRoute();
    } catch (_) {
      debugPrint(
        '[SharedTrip] Token-scoped refresh failed; hiding stale tracking.',
      );
      if (mounted) {
        setState(() {
          _accessUnavailable = true;
          _markers = {};
          _polylines = {};
          _eta = null;
        });
      }
      _routeGeneration++;
    } finally {
      _refreshing = false;
    }
  }

  // ── Markers ───────────────────────────────────────────────────────────────

  void _buildMarkers() {
    final markers = <Marker>{};

    // Pickup — green pin (always shown)
    final pLat = _details.pickupLatitude;
    final pLng = _details.pickupLongitude;
    if (pLat != null && pLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(pLat, pLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: _details.pickupLandmark.isNotEmpty
                ? _details.pickupLandmark
                : 'Pickup Point',
          ),
        ),
      );
    }

    // Drop-off — red pin (always shown)
    final dLat = _details.dropoffLatitude;
    final dLng = _details.dropoffLongitude;
    if (dLat != null && dLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(dLat, dLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: _details.dropoffLandmark.isNotEmpty
                ? _details.dropoffLandmark
                : 'Drop-off Point',
          ),
        ),
      );
    }

    // All itinerary spots: done=green, current=orange, upcoming=azure
    final currentSpot = _currentSpotItem;
    final items = _details.itineraryItems;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final lat = (item['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (item['longitude'] as num?)?.toDouble() ?? 0.0;
      if (lat == 0.0 && lng == 0.0) continue;
      final status = item['status']?.toString() ?? '';
      final isDone = status == 'completed';
      final isCurrent = !isDone && identical(item, currentSpot);
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
            title: 'Stop ${i + 1}: ${item['name']?.toString() ?? ''}',
          ),
        ),
      );
    }

    if (!_details.isTripEnded && !_accessUnavailable) {
      markers.addAll(
        buildBookingDriverMarkers(
          drivers: _details.drivers,
          selectedDriverId: _selectedDriverId,
          onSelect: _selectDriver,
          icon:
              _tricycleMarker ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    if (mounted) setState(() => _markers = markers);
  }

  // ── Route / polyline ──────────────────────────────────────────────────────

  Future<void> _fetchCurrentRoute() async {
    if (_details.isTripEnded || _accessUnavailable) return;
    final origins = <String, LatLng>{
      for (final driver in _details.drivers)
        if (driver.latitude != null &&
            driver.longitude != null &&
            validDriverCoordinates(driver.latitude!, driver.longitude!))
          driver.driverId: LatLng(driver.latitude!, driver.longitude!),
    };
    if (origins.isEmpty) {
      _routeGeneration++;
      if (mounted) {
        setState(() {
          _polylines = {};
          _eta = null;
        });
      }
      return;
    }

    LatLng? destination;
    final ts = _details.tourStatus;

    if (ts == 'driver_accepted' ||
        ts == 'driver_en_route' ||
        ts == 'driver_arrived') {
      final lat = _details.pickupLatitude;
      final lng = _details.pickupLongitude;
      if (lat != null && lng != null) destination = LatLng(lat, lng);
    } else if (ts == 'picked_up' ||
        ts == 'on_tour' ||
        ts == 'en_route_to_spot' ||
        ts == 'at_spot') {
      destination = _currentSpotLatLng;
      if (destination == null &&
          _details.dropoffLatitude != null &&
          _details.dropoffLongitude != null) {
        destination = LatLng(
          _details.dropoffLatitude!,
          _details.dropoffLongitude!,
        );
      }
    } else if (ts == 'en_route_to_dropoff' || ts == 'ready_to_complete') {
      final lat = _details.dropoffLatitude;
      final lng = _details.dropoffLongitude;
      if (lat != null && lng != null) destination = LatLng(lat, lng);
    }

    if (destination == null) {
      _routeGeneration++;
      if (mounted) {
        setState(() {
          _polylines = {};
          _eta = null;
        });
      }
      return;
    }

    final target =
        '${destination.latitude},${destination.longitude}:${_details.tourStatus}:'
        '${origins.keys.join(',')}:$_selectedDriverId';
    if (_lastRouteTarget == target &&
        _lastRouteAt != null &&
        DateTime.now().difference(_lastRouteAt!) <
            const Duration(seconds: 30)) {
      return;
    }
    final generation = ++_routeGeneration;
    _lastRouteTarget = target;
    _lastRouteAt = DateTime.now();
    final targetPoint = destination;
    final results = await Future.wait(
      origins.entries.map((entry) async {
        try {
          final route = await _routeService
              .fetchRoute(entry.value, targetPoint)
              .timeout(const Duration(seconds: 20));
          return (driverId: entry.key, route: route);
        } catch (_) {
          debugPrint(
            '[SharedTrip] Driver route unavailable; map markers retained.',
          );
          return null;
        }
      }),
    );
    if (!mounted ||
        generation != _routeGeneration ||
        _details.isTripEnded ||
        _accessUnavailable) {
      return;
    }
    setState(() {
      _polylines = {
        for (final result in results)
          if (result != null)
            Polyline(
              polylineId: PolylineId('driver_route_${result.driverId}'),
              points: result.route.points,
              color:
                  result.driverId == _selectedDriverId ||
                      _selectedDriverId == null
                  ? const Color(0xFF2A86FF)
                  : const Color(0xFF7C3AED),
              width: 5,
              geodesic: true,
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
      };
      _eta = null;
      for (final result in results) {
        if (result != null &&
            (result.driverId == _selectedDriverId || origins.length == 1)) {
          _eta = result.route.durationText;
        }
      }
    });
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  void _animateCameraToRelevant() {
    if (_mapCtrl == null) return;
    final driverMarkers = _markers.where(
      (m) => m.markerId.value.startsWith('driver_'),
    );
    final focused = _selectedDriverId == null
        ? null
        : driverMarkers
              .where((m) => m.markerId.value == 'driver_$_selectedDriverId')
              .firstOrNull;
    if (_isFollowingDriver && focused != null) {
      _isProgrammaticMove = true;
      _mapCtrl!.animateCamera(CameraUpdate.newLatLngZoom(focused.position, 15));
      return;
    }
    if (_markers.isNotEmpty) {
      final points =
          (_isFollowingDriver && driverMarkers.isNotEmpty
                  ? driverMarkers
                  : _markers)
              .map((marker) => marker.position);
      var south = points.first.latitude;
      var north = south;
      var west = points.first.longitude;
      var east = west;
      for (final point in points) {
        if (point.latitude < south) south = point.latitude;
        if (point.latitude > north) north = point.latitude;
        if (point.longitude < west) west = point.longitude;
        if (point.longitude > east) east = point.longitude;
      }
      _isProgrammaticMove = true;
      _mapCtrl!.animateCamera(
        north - south < .0005 && east - west < .0005
            ? CameraUpdate.newLatLngZoom(points.first, 16)
            : CameraUpdate.newLatLngBounds(
                LatLngBounds(
                  southwest: LatLng(south, west),
                  northeast: LatLng(north, east),
                ),
                48,
              ),
      );
      return;
    }
    final dLat = _details.driverLatitude;
    final dLng = _details.driverLongitude;
    if (dLat != null && dLng != null) {
      _isProgrammaticMove = true;
      _mapCtrl!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(dLat, dLng), 15),
      );
      return;
    }
    final pLat = _details.pickupLatitude;
    final pLng = _details.pickupLongitude;
    if (pLat != null && pLng != null) {
      _isProgrammaticMove = true;
      _mapCtrl!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pLat, pLng), 15),
      );
    }
  }

  void _selectDriver(String id) {
    setState(() {
      _selectedDriverId = id;
      _isFollowingDriver = true;
    });
    _buildMarkers();
    _animateCameraToRelevant();
    _fetchCurrentRoute();
  }

  void _animateCameraToCurrentSpot() {
    final spot = _currentSpotLatLng;
    if (_mapCtrl == null || spot == null) return;
    _isProgrammaticMove = true;
    _mapCtrl!.animateCamera(CameraUpdate.newLatLngZoom(spot, 17));
  }

  // ── Emergency ─────────────────────────────────────────────────────────────

  Future<void> _callEmergency() async {
    final uri = Uri.parse('tel:911');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _showEmergencySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmergencySheet(onCall: _callEmergency),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  static const _defaultCenter = LatLng(14.9597, 120.9206);

  LatLng get _initialCenter {
    final dLat = _details.driverLatitude;
    final dLng = _details.driverLongitude;
    if (dLat != null && dLng != null) return LatLng(dLat, dLng);
    final pLat = _details.pickupLatitude;
    final pLng = _details.pickupLongitude;
    if (pLat != null && pLng != null) return LatLng(pLat, pLng);
    return _defaultCenter;
  }

  @override
  Widget build(BuildContext context) {
    if (_accessUnavailable) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shared Trip')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Trip access or connection unavailable.'),
              TextButton(
                onPressed: _refreshDetails,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final bottom = MediaQuery.of(context).padding.bottom;
    final size = MediaQuery.sizeOf(context);
    final mapHeight = (size.height * 0.40).clamp(240.0, 380.0);

    if (_details.isTripEnded) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),
              const Expanded(
                child: _FullScreenMessage(
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: Color(0xFF16A34A),
                  title: 'This trip has ended.',
                  subtitle: 'Live location sharing has ended.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            // ── Map as pinned SliverAppBar (always visible) ───────
            SliverAppBar(
              expandedHeight: mapHeight,
              pinned: true,
              backgroundColor: const Color(0xFF2A86FF),
              foregroundColor: Colors.white,
              automaticallyImplyLeading: false,
              title: _buildHeaderRow(),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
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
                          debugPrint('[SharedTrip] Google Map created.');
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
                          if (_currentSpotLatLng != null) ...[
                            FloatingActionButton.small(
                              heroTag: 'guest_recenter_spot',
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFFF59E0B),
                              elevation: 4,
                              tooltip: 'Recenter on Destination',
                              onPressed: () {
                                setState(() => _isFollowingDriver = false);
                                _animateCameraToCurrentSpot();
                              },
                              child: const Icon(Icons.place_rounded, size: 20),
                            ),
                            const SizedBox(height: 8),
                          ],
                          FloatingActionButton.small(
                            heroTag: 'guest_recenter',
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF2A86FF),
                            elevation: 4,
                            tooltip: 'Recenter on Driver',
                            onPressed: () {
                              setState(() {
                                _isFollowingDriver = true;
                                _selectedDriverId = null;
                              });
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

            // ── Content cards ─────────────────────────────────────
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottom),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _GuestStatusCard(
                    tourStatus:
                        const {
                          'awaiting_remaining_payment',
                          'awaiting_final_payment',
                        }.contains(_details.bookingStatusDetail)
                        ? _details.bookingStatusDetail
                        : _details.tourStatus,
                    eta: _eta,
                    driverCount: _details.drivers.length,
                  ),
                  const SizedBox(height: 12),
                  ConvoyTouristDriverList(
                    convoy: _details.drivers,
                    guestView: true,
                    selectedDriverId: _selectedDriverId,
                    onSelect: _selectDriver,
                  ),
                  if (_details.drivers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    LiveItineraryEstimates(
                      booking: _details.trackingBooking,
                      drivers: _details.drivers,
                      stops: _details.trackingStops,
                      service: widget.etaService,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_details.itineraryItems.isNotEmpty) ...[
                    _SectionLabel(
                      'Tour Itinerary (${_details.itineraryItems.length} stops)',
                    ),
                    const SizedBox(height: 8),
                    _GuestItineraryCard(items: _details.itineraryItems),
                    const SizedBox(height: 12),
                  ],
                  if (_details.pickupLandmark.isNotEmpty) ...[
                    const _SectionLabel('Pickup Area'),
                    const SizedBox(height: 8),
                    _SimpleInfoCard(
                      icon: Icons.hail_rounded,
                      value: _details.pickupLandmark,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_details.dropoffLandmark.isNotEmpty) ...[
                    const _SectionLabel('Drop-off Area'),
                    const SizedBox(height: 8),
                    _SimpleInfoCard(
                      icon: Icons.flag_rounded,
                      value: _details.dropoffLandmark,
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: _showEmergencySheet,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.emergency_rounded, size: 18),
                    label: const Text(
                      'Emergency Assistance',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Contact details, full addresses, and payment information are not shown in guest view.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                      height: 1.5,
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        const Icon(Icons.share_location_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'TourisTrike — Trip Tracking',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              Text(
                'Guest View',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ),
        if (_eta != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
        ],
        IconButton(
          onPressed: _refreshDetails,
          icon: const Icon(
            Icons.refresh_rounded,
            color: Colors.white,
            size: 20,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  // Used only for the trip-ended state (no map needed).
  Widget _buildHeader() {
    return Container(
      color: const Color(0xFF2A86FF),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: _buildHeaderRow(),
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

class _GuestStatusCard extends StatelessWidget {
  const _GuestStatusCard({
    required this.tourStatus,
    this.eta,
    this.driverCount = 0,
  });

  final String tourStatus;
  final int driverCount;
  final String? eta;

  static const _statusInfo = <String, (String, String, Color, IconData)>{
    'awaiting_remaining_payment': (
      'Preparing for Drop-off',
      'Tour itinerary completed — preparing for drop-off.',
      Color(0xFF2A86FF),
      Icons.route_rounded,
    ),
    'awaiting_final_payment': (
      'Finishing Trip',
      'The tour is being finalized.',
      Color(0xFF2A86FF),
      Icons.task_alt_rounded,
    ),
    'not_started': (
      'Not Started',
      'The tour has not started yet.',
      Color(0xFF64748B),
      Icons.hourglass_empty_rounded,
    ),
    'waiting_driver': (
      'Finding Driver',
      'Looking for an available driver.',
      Color(0xFFF59E0B),
      Icons.search_rounded,
    ),
    'driver_accepted': (
      'Driver Found',
      'A driver has accepted and will be on the way.',
      Color(0xFF2A86FF),
      Icons.check_circle_rounded,
    ),
    'driver_en_route': (
      'Driver On the Way',
      'Your driver is heading to the pickup point.',
      Color(0xFF2A86FF),
      Icons.directions_car_rounded,
    ),
    'driver_arrived': (
      'Driver Arrived',
      'Driver is at the pickup point.',
      Color(0xFF7C3AED),
      Icons.location_on_rounded,
    ),
    'picked_up': (
      'Tour Started!',
      'The group has been picked up. Tour is in progress.',
      Color(0xFF16A34A),
      Icons.tour_rounded,
    ),
    'on_tour': (
      'On Tour',
      'The tour is active and itinerary is being completed.',
      Color(0xFF0EA5E9),
      Icons.route_rounded,
    ),
    'en_route_to_spot': (
      'Heading to Next Stop',
      'Driving to the next itinerary stop.',
      Color(0xFF0EA5E9),
      Icons.navigation_rounded,
    ),
    'at_spot': (
      'At Tour Spot',
      'Currently at a tour destination.',
      Color(0xFF16A34A),
      Icons.place_rounded,
    ),
    'en_route_to_dropoff': (
      'Heading to Drop-off',
      'All spots done! Heading to drop-off point.',
      Color(0xFF2A86FF),
      Icons.home_rounded,
    ),
    'ready_to_complete': (
      'All Spots Done',
      'Every booked spot is completed.',
      Color(0xFF16A34A),
      Icons.task_alt_rounded,
    ),
    'dropped_off': (
      'Dropped Off',
      'The tour group has been dropped off.',
      Color(0xFF16A34A),
      Icons.check_circle_outline_rounded,
    ),
    'completed': (
      'Tour Completed',
      'The tour has been completed.',
      Color(0xFF16A34A),
      Icons.star_rounded,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final data =
        _statusInfo[tourStatus] ??
        (
          tourStatus.replaceAll('_', ' ').toUpperCase(),
          '',
          const Color(0xFF64748B),
          Icons.info_rounded,
        );
    final (singleLabel, singleDesc, color, icon) = data;
    final (label, desc) = driverCount > 1
        ? switch (tourStatus) {
            'driver_accepted' => (
              'Drivers Found',
              'Drivers have accepted and will be on the way.',
            ),
            'driver_en_route' => (
              'Drivers On the Way',
              'Your drivers are heading to the pickup point.',
            ),
            'driver_arrived' => (
              'Driver Arrived',
              'A driver has reached pickup. Check each driver’s status below.',
            ),
            _ => (singleLabel, singleDesc),
          }
        : (singleLabel, singleDesc);

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
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    desc,
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

// ── Itinerary card ────────────────────────────────────────────────────────────

class _GuestItineraryCard extends StatelessWidget {
  const _GuestItineraryCard({required this.items});

  final List<Map<String, dynamic>> items;

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
      child: Column(
        children: items.asMap().entries.map((entry) {
          final idx = entry.key;
          return _GuestItineraryRow(
            index: idx + 1,
            item: entry.value,
            isLast: idx == items.length - 1,
          );
        }).toList(),
      ),
    );
  }
}

class _GuestItineraryRow extends StatelessWidget {
  const _GuestItineraryRow({
    required this.index,
    required this.item,
    required this.isLast,
  });

  final int index;
  final Map<String, dynamic> item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? 'Stop $index';
    final status = item['status']?.toString() ?? '';
    final arrivedAt = item['arrived_at'] != null
        ? DateTime.tryParse(item['arrived_at'].toString())?.toLocal()
        : null;
    final departedAt = item['departed_at'] != null
        ? DateTime.tryParse(item['departed_at'].toString())?.toLocal()
        : null;
    final scheduledArrival = item['arrival_time']?.toString() ?? '';
    final scheduledDeparture = item['departure_time']?.toString() ?? '';
    final stayMinutes =
        (item['estimated_stay_duration_minutes'] as num?)?.toInt() ?? 0;

    final isDone = status == 'completed';
    final isCurrent =
        status == 'travelling' || status == 'visiting' || status == 'at_spot';

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
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
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
                      _GuestSpotChip(status: status, isDone: isDone),
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
                  if (arrivedAt != null) ...[
                    const SizedBox(height: 4),
                    _TimestampBadge(
                      icon: Icons.location_on_rounded,
                      label: 'Arrived',
                      time: timeFmt.format(arrivedAt),
                      color: const Color(0xFF2A86FF),
                    ),
                  ],
                  if (departedAt != null) ...[
                    const SizedBox(height: 3),
                    _TimestampBadge(
                      icon: Icons.check_circle_rounded,
                      label: 'Completed',
                      time: timeFmt.format(departedAt),
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

class _GuestSpotChip extends StatelessWidget {
  const _GuestSpotChip({required this.status, required this.isDone});

  final String status;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    if (isDone) return const SizedBox.shrink();
    final (label, color) = switch (status) {
      'travelling' => ('EN ROUTE', const Color(0xFF0EA5E9)),
      'visiting' || 'at_spot' => ('HERE', const Color(0xFF16A34A)),
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

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SimpleInfoCard extends StatelessWidget {
  const _SimpleInfoCard({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2A86FF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
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

class _FullScreenMessage extends StatelessWidget {
  const _FullScreenMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: iconColor),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencySheet extends StatelessWidget {
  const _EmergencySheet({required this.onCall});

  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Emergency',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'If you or someone is in danger, call emergency services immediately.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onCall();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.call_rounded, size: 20),
            label: const Text(
              'Call 911 — Emergency',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
