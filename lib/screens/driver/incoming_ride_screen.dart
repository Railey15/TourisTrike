import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/supabase/touristrike_repository.dart';
import '../driver/driver_location_service.dart';

// ============================================================================
// SHARED UI CONSTANTS
// ============================================================================

const Color _primary = Color(0xFF2563EB);
const Color _primaryLight = Color(0xFF3BA9F5);

const Color _background = Color(0xFFF4F7FB);
const Color _surface = Colors.white;

const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);
const Color _subtle = Color(0xFF94A3B8);

const Color _border = Color(0xFFE5EBF3);
const Color _softBlue = Color(0xFFEFF6FF);

const Color _success = Color(0xFF16A34A);
const Color _successSoft = Color(0xFFECFDF5);

const Color _danger = Color(0xFFDC2626);
const Color _dangerSoft = Color(0xFFFEF2F2);

// ============================================================================
// SCREEN
// ============================================================================

class IncomingRideScreen extends StatefulWidget {
  const IncomingRideScreen({
    super.key,
    required this.rideId,
  });

  final String rideId;

  @override
  State<IncomingRideScreen> createState() => _IncomingRideScreenState();
}

class _IncomingRideScreenState extends State<IncomingRideScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TourisTrikeRepository _repo = TourisTrikeRepository();

  Map<String, dynamic>? _ride;
  Map<String, dynamic>? _touristProfile;

  RealtimeChannel? _rideChannel;

  bool _loading = true;
  bool _updatingStatus = false;

  GoogleMapController? _mapController;

  final DriverLocationService _loc = DriverLocationService();

  StreamSubscription<Position>? _posSub;

  LatLng? _driverLatLng;

  static final LatLngBounds _phBulacanBounds = LatLngBounds(
    southwest: const LatLng(
      14.35,
      120.35,
    ),
    northeast: const LatLng(
      15.55,
      121.55,
    ),
  );

  static const LatLng _fallbackCenter = LatLng(
    14.8448,
    120.8104,
  );

  // =========================================================================
  // LIFECYCLE
  // =========================================================================

  @override
  void initState() {
    super.initState();

    _loadRideAndTourist();
    _subscribeRideRealtime();
    _startDriverLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();

    _loc.stop();

    final channel = _rideChannel;
    _rideChannel = null;

    if (channel != null) {
      supabase.removeChannel(channel);
    }

    _mapController?.dispose();

    super.dispose();
  }

  User get _user {
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged-in user.');
    }

    return user;
  }

  // =========================================================================
  // FEEDBACK
  // =========================================================================

  void _snack(
    String message, {
    bool error = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: error
              ? _danger
              : const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  // =========================================================================
  // LOAD
  // =========================================================================

  Future<void> _loadRideAndTourist() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final ride = await supabase
          .from('rides')
          .select('*')
          .eq('id', widget.rideId)
          .maybeSingle();

      if (ride == null) {
        if (!mounted) {
          return;
        }

        setState(() {
          _ride = null;
          _touristProfile = null;
          _loading = false;
        });

        return;
      }

      Map<String, dynamic>? tourist;

      final touristId = ride['tourist_id'];

      if (touristId != null) {
        tourist = await supabase
            .from('profiles')
            .select(
              'id, full_name, first_name, last_name, profile_image_url, mobile',
            )
            .eq('id', touristId)
            .maybeSingle();
      }

      final driverLat = ride['driver_lat'];
      final driverLng = ride['driver_lng'];

      if (driverLat is num &&
          driverLng is num &&
          _isValidLatLng(
            driverLat.toDouble(),
            driverLng.toDouble(),
          )) {
        _driverLatLng = LatLng(
          driverLat.toDouble(),
          driverLng.toDouble(),
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _ride = Map<String, dynamic>.from(ride);

        _touristProfile = tourist == null
            ? null
            : Map<String, dynamic>.from(tourist);

        _loading = false;
      });

      _scheduleFit();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });

      _snack(
        'Failed to load tour assignment.',
        error: true,
      );
    }
  }

  // =========================================================================
  // REALTIME
  // =========================================================================

  void _subscribeRideRealtime() {
    _rideChannel = supabase.channel(
      'ride-${widget.rideId}',
    );

    _rideChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.rideId,
          ),
          callback: (payload) {
            final newRow = payload.newRecord;

            if (!mounted) {
              return;
            }

            final driverLat = newRow['driver_lat'];
            final driverLng = newRow['driver_lng'];

            if (driverLat is num &&
                driverLng is num &&
                _isValidLatLng(
                  driverLat.toDouble(),
                  driverLng.toDouble(),
                )) {
              _driverLatLng = LatLng(
                driverLat.toDouble(),
                driverLng.toDouble(),
              );
            }

            setState(() {
              _ride = Map<String, dynamic>.from(
                newRow,
              );
            });

            final status = (newRow['status'] ?? '')
                .toString();

            if (status == 'completed') {
              _stopDriverLocation();
            }

            _scheduleFit();
          },
        )
        .subscribe();
  }

  // =========================================================================
  // DRIVER LOCATION
  // =========================================================================

  Future<void> _startDriverLocation() async {
    await _posSub?.cancel();

    _posSub = _loc.start().listen(
      (position) async {
        if (!_isValidLatLng(
          position.latitude,
          position.longitude,
        )) {
          return;
        }

        final rideStatus =
            (_ride?['status'] ?? '').toString();

        if (rideStatus == 'completed') {
          return;
        }

        _driverLatLng = LatLng(
          position.latitude,
          position.longitude,
        );

        if (_ride != null) {
          try {
            await supabase
                .from('rides')
                .update({
                  'driver_lat': position.latitude,
                  'driver_lng': position.longitude,
                  'driver_last_seen':
                      DateTime.now().toIso8601String(),
                })
                .eq(
                  'id',
                  widget.rideId,
                );
          } catch (_) {
            // Keep location UI responsive even if RLS blocks an update.
          }
        }

        _maybeFollowDriver();

        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  Future<void> _stopDriverLocation() async {
    await _posSub?.cancel();

    _posSub = null;

    _loc.stop();
  }

  void _maybeFollowDriver() {
    final ride = _ride;

    if (ride == null) {
      return;
    }

    final status = (ride['status'] ?? '').toString();

    if (status != 'enroute_pickup' &&
        status != 'ongoing') {
      return;
    }

    final driver = _driverLatLng;
    final target = _currentTarget();

    if (driver == null || target == null) {
      return;
    }

    _fitBounds(
      driver,
      target,
    );
  }

  // =========================================================================
  // LOCATION HELPERS
  // =========================================================================

  bool _isValidLatLng(
    double lat,
    double lng,
  ) {
    if (lat == 0 && lng == 0) {
      return false;
    }

    if (lat.isNaN || lng.isNaN) {
      return false;
    }

    if (lat.abs() > 90 || lng.abs() > 180) {
      return false;
    }

    return true;
  }

  LatLng? _pickupLatLng() {
    final ride = _ride;

    if (ride == null) {
      return null;
    }

    final lat = ride['pickup_lat'];
    final lng = ride['pickup_lng'];

    if (lat is num &&
        lng is num &&
        _isValidLatLng(
          lat.toDouble(),
          lng.toDouble(),
        )) {
      return LatLng(
        lat.toDouble(),
        lng.toDouble(),
      );
    }

    return null;
  }

  LatLng? _dropoffLatLng() {
    final ride = _ride;

    if (ride == null) {
      return null;
    }

    final lat = ride['dropoff_lat'];
    final lng = ride['dropoff_lng'];

    if (lat is num &&
        lng is num &&
        _isValidLatLng(
          lat.toDouble(),
          lng.toDouble(),
        )) {
      return LatLng(
        lat.toDouble(),
        lng.toDouble(),
      );
    }

    return null;
  }

  LatLng? _currentTarget() {
    final ride = _ride;

    if (ride == null) {
      return null;
    }

    final status = (ride['status'] ?? '').toString();

    if (status == 'ongoing') {
      return _dropoffLatLng();
    }

    return _pickupLatLng();
  }

  void _scheduleFit() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (!mounted) {
          return;
        }

        _fitToTarget();
      },
    );
  }

  void _fitToTarget() {
    if (_mapController == null) {
      return;
    }

    final pickup = _pickupLatLng();
    final driver = _driverLatLng;
    final target = _currentTarget();

    if (driver != null && target != null) {
      _fitBounds(
        driver,
        target,
      );

      return;
    }

    if (pickup != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: pickup,
            zoom: 16,
          ),
        ),
      );

      return;
    }

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(
          target: _fallbackCenter,
          zoom: 13.5,
        ),
      ),
    );
  }

  void _fitBounds(
    LatLng a,
    LatLng b,
  ) {
    if (_mapController == null) {
      return;
    }

    final distance =
        Geolocator.distanceBetween(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        ) /
        1000;

    if (distance > 120) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          _phBulacanBounds,
          40,
        ),
      );

      return;
    }

    final samePosition =
        (a.latitude - b.latitude).abs() < 0.00001 &&
        (a.longitude - b.longitude).abs() < 0.00001;

    if (samePosition) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: a,
            zoom: 17,
          ),
        ),
      );

      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(
        math.min(
          a.latitude,
          b.latitude,
        ),
        math.min(
          a.longitude,
          b.longitude,
        ),
      ),
      northeast: LatLng(
        math.max(
          a.latitude,
          b.latitude,
        ),
        math.max(
          a.longitude,
          b.longitude,
        ),
      ),
    );

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds,
        62,
      ),
    );
  }

  // =========================================================================
  // STATUS
  // =========================================================================

  Future<void> _setStatus(
    String status,
  ) async {
    if (_ride == null || _updatingStatus) {
      return;
    }

    setState(() {
      _updatingStatus = true;
    });

    try {
      final payload = <String, dynamic>{
        'status': status,
      };

      if (status == 'completed') {
        payload['completed_at'] =
            DateTime.now().toIso8601String();

        if (_driverLatLng != null) {
          payload['driver_lat'] =
              _driverLatLng!.latitude;

          payload['driver_lng'] =
              _driverLatLng!.longitude;

          payload['driver_last_seen'] =
              DateTime.now().toIso8601String();
        }
      }

      final updated = await supabase
          .from('rides')
          .update(payload)
          .eq(
            'id',
            widget.rideId,
          )
          .eq(
            'driver_id',
            _user.id,
          )
          .select()
          .maybeSingle();

      if (updated == null) {
        _snack(
          'Status update failed.',
          error: true,
        );

        return;
      }

      if (status == 'completed') {
        await _stopDriverLocation();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _ride = Map<String, dynamic>.from(
          updated,
        );
      });

      _scheduleFit();

      if (status == 'completed') {
        _snack(
          'Tour completed successfully.',
        );
      }
    } catch (e) {
      _snack(
        'Status update blocked. Check RLS.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingStatus = false;
        });
      }
    }
  }

  // =========================================================================
  // PAYMENT
  // =========================================================================

  Future<bool> _recordRidePaymentBeforeCompleting() async {
    final ride = _ride;

    if (ride == null) {
      return true;
    }

    final rawFare = ride['fare_amount'];

    final amount = rawFare is num
        ? rawFare.toDouble()
        : 0.0;

    if (amount <= 0) {
      return true;
    }

    final rawMethod =
        (ride['payment_method'] ?? 'cash')
            .toString()
            .trim()
            .toLowerCase();

    final method =
        rawMethod == 'gcash' || rawMethod == 'maya'
            ? rawMethod
            : 'cash';

    final refController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _PaymentConfirmationSheet(
          amount: amount,
          method: method,
          referenceController: refController,
          onCancel: () {
            Navigator.pop(
              sheetContext,
              false,
            );
          },
          onConfirm: () {
            Navigator.pop(
              sheetContext,
              true,
            );
          },
        );
      },
    );

    if (confirmed != true) {
      refController.dispose();
      return false;
    }

    try {
      await _repo.recordRidePayment(
        rideId: widget.rideId,
        paymentMethod: method,
        amount: amount,
        externalReferenceNo:
            refController.text.trim().isEmpty
                ? null
                : refController.text.trim(),
      );

      refController.dispose();

      return true;
    } catch (e) {
      refController.dispose();

      _snack(
        'Unable to record payment: $e',
        error: true,
      );

      return false;
    }
  }

  // =========================================================================
  // PRIMARY ACTION
  // =========================================================================

  _Action? _primaryAction(
    String status,
  ) {
    switch (status) {
      case 'accepted':
        return const _Action(
          label: 'Navigate to Pickup',
          nextStatus: 'enroute_pickup',
          toast: 'En route to pickup.',
          icon: Icons.navigation_rounded,
        );

      case 'enroute_pickup':
        return const _Action(
          label: 'Arrived at Pickup',
          nextStatus: 'arrived',
          toast: 'Arrived at pickup.',
          icon: Icons.location_on_rounded,
        );

      case 'arrived':
        return const _Action(
          label: 'Start Tour',
          nextStatus: 'ongoing',
          toast: 'Tour started.',
          icon: Icons.play_arrow_rounded,
        );

      case 'ongoing':
        return const _Action(
          label: 'Complete Tour',
          nextStatus: 'completed',
          toast: 'Tour completed.',
          icon: Icons.flag_rounded,
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
    final ride = _ride;

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const _LoadingView()
            : ride == null
                ? _emptyState()
                : _content(ride),
      ),
    );
  }

  Widget _emptyState() {
    return Column(
      children: [
        _AssignmentTopBar(
          title: 'Tour Assignment',
          onBack: () => Navigator.of(context).pop(),
        ),

        const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: _EmptyAssignmentCard(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(
    Map<String, dynamic> ride,
  ) {
    final pickupName = (ride['pickup_name'] ?? '')
        .toString()
        .trim();

    final dropoffName = (ride['dropoff_name'] ?? '')
        .toString()
        .trim();

    final status = (ride['status'] ?? '')
        .toString()
        .trim();

    final pickup = _pickupLatLng();
    final dropoff = _dropoffLatLng();
    final driver = _driverLatLng;

    final touristName = _touristName();

    final touristMobile =
        (_touristProfile?['mobile'] ?? '')
            .toString()
            .trim();

    final touristImage =
        (_touristProfile?['profile_image_url'] ?? '')
            .toString()
            .trim();

    final fare = ride['fare_amount'];

    final fareText = fare is num
        ? '₱${fare.toStringAsFixed(2)}'
        : '₱0.00';

    final distance = ride['distance_km'];

    final distanceText = distance is num
        ? '${distance.toStringAsFixed(1)} km'
        : '—';

    final action = _primaryAction(status);

    final routePoints = <LatLng>[];

    final target = _currentTarget();

    if (driver != null &&
        target != null &&
        status != 'completed') {
      routePoints.addAll([
        driver,
        target,
      ]);
    }

    final initialCenter =
        pickup ?? _fallbackCenter;

    final nextStep = _nextStepInformation(
      status,
    );

    final completed = status == 'completed';

    return Column(
      children: [
        _AssignmentTopBar(
          title: 'Tour Assignment',
          onBack: () => Navigator.of(context).pop(),
        ),

        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              16,
              8,
              16,
              24,
            ),
            children: [
              // ==============================================================
              // STATUS
              // ==============================================================

              _RideStatusOverview(
                status: status,
                title: _statusTitle(status),
                subtitle: _statusSubtitle(status),
              ),

              const SizedBox(height: 14),

              // ==============================================================
              // MAP
              // ==============================================================

              _MapCard(
                status: status,
                initialCenter: initialCenter,
                pickup: pickup,
                dropoff: dropoff,
                driver: driver,
                pickupName: pickupName,
                dropoffName: dropoffName,
                routePoints: routePoints,
                onMapCreated: (controller) {
                  _mapController = controller;
                  _scheduleFit();
                },
                onDriverLocation: () {
                  if (_driverLatLng == null) {
                    _snack(
                      'Driver location not available yet.',
                    );

                    return;
                  }

                  _mapController?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: _driverLatLng!,
                        zoom: 16.5,
                      ),
                    ),
                  );
                },
                onTargetLocation: () {
                  final currentTarget = _currentTarget();

                  if (currentTarget == null) {
                    _snack(
                      'Target location is not available.',
                    );

                    return;
                  }

                  _mapController?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: currentTarget,
                        zoom: 16.2,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 14),

              // ==============================================================
              // TOURIST
              // ==============================================================

              _TouristCard(
                name: touristName,
                mobile: touristMobile,
                imageUrl: touristImage,
                onCall: () {
                  _snack('Call feature is not connected yet.');
                },
                onMessage: () {
                  _snack('Chat feature is not connected yet.');
                },
              ),

              const SizedBox(height: 14),

              // ==============================================================
              // ROUTE
              // ==============================================================

              _SectionTitle(
                icon: Icons.route_rounded,
                title: 'Tour Route',
                subtitle:
                    'Pickup and destination for this assignment',
              ),

              const SizedBox(height: 10),

              _RouteTimelineCard(
                pickup: pickupName.isEmpty
                    ? 'Pickup location unavailable'
                    : pickupName,
                dropoff: dropoffName.isEmpty
                    ? 'Destination unavailable'
                    : dropoffName,
                status: status,
              ),

              const SizedBox(height: 14),

              // ==============================================================
              // STATS
              // ==============================================================

              Row(
                children: [
                  Expanded(
                    child: _SummaryStatCard(
                      icon: Icons.payments_outlined,
                      label: 'EST. EARNINGS',
                      value: fareText,
                      accent: _success,
                      accentBackground:
                          _successSoft,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: _SummaryStatCard(
                      icon: Icons.route_outlined,
                      label: 'DISTANCE',
                      value: distanceText,
                      accent: _primary,
                      accentBackground:
                          _softBlue,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ==============================================================
              // NEXT STEP
              // ==============================================================

              if (!completed)
                _NextStepCard(
                  icon: nextStep.icon,
                  title: nextStep.title,
                  subtitle: nextStep.subtitle,
                )
              else
                const _CompletedCard(),

              // Bottom padding because action area is outside scroll.
              const SizedBox(height: 10),
            ],
          ),
        ),

        // ====================================================================
        // PERSISTENT PRIMARY ACTION
        // ====================================================================

        _BottomRideAction(
          status: status,
          action: action,
          updating: _updatingStatus,
          onPressed: action == null
              ? null
              : () async {
                  if (action.nextStatus == 'completed') {
                    final paid =
                        await _recordRidePaymentBeforeCompleting();

                    if (!paid) {
                      return;
                    }
                  }

                  await _setStatus(
                    action.nextStatus,
                  );

                  if (action.nextStatus != 'completed') {
                    _snack(action.toast);
                  }
                },
        ),
      ],
    );
  }

  // =========================================================================
  // DISPLAY HELPERS
  // =========================================================================

  String _statusTitle(
    String status,
  ) {
    switch (status) {
      case 'accepted':
        return 'Tour accepted';

      case 'enroute_pickup':
        return 'Heading to tourist';

      case 'arrived':
        return 'You have arrived';

      case 'ongoing':
        return 'Tour in progress';

      case 'completed':
        return 'Tour completed';

      case 'searching':
        return 'Waiting for assignment';

      default:
        return 'Tour assignment';
    }
  }

  String _statusSubtitle(
    String status,
  ) {
    switch (status) {
      case 'accepted':
        return 'Review the pickup location and start heading to the tourist.';

      case 'enroute_pickup':
        return 'Drive safely to the tourist pickup point.';

      case 'arrived':
        return 'Meet the tourist and start the tour when everyone is ready.';

      case 'ongoing':
        return 'Proceed to the destination and complete the assigned tour.';

      case 'completed':
        return 'This assignment has been successfully completed.';

      case 'searching':
        return 'The system is still looking for an available assignment.';

      default:
        return 'Follow the assignment details below.';
    }
  }

  _NextStepInfo _nextStepInformation(
    String status,
  ) {
    switch (status) {
      case 'accepted':
        return const _NextStepInfo(
          icon: Icons.navigation_rounded,
          title: 'Head to the pickup point',
          subtitle:
              'Check the map, confirm the tourist location, then tap Navigate to Pickup.',
        );

      case 'enroute_pickup':
        return const _NextStepInfo(
          icon: Icons.location_on_outlined,
          title: 'Meet the tourist',
          subtitle:
              'Once you reach the pickup point, tap Arrived at Pickup.',
        );

      case 'arrived':
        return const _NextStepInfo(
          icon: Icons.people_outline_rounded,
          title: 'Confirm everyone is ready',
          subtitle:
              'Make sure the tourist is onboard before starting the tour.',
        );

      case 'ongoing':
        return const _NextStepInfo(
          icon: Icons.flag_outlined,
          title: 'Proceed to the destination',
          subtitle:
              'Finish the tour safely, confirm payment, then complete the assignment.',
        );

      default:
        return const _NextStepInfo(
          icon: Icons.info_outline_rounded,
          title: 'Follow your assignment',
          subtitle:
              'Use the action below when you are ready for the next stage.',
        );
    }
  }

  String _touristName() {
    if (_touristProfile == null) {
      return 'Tourist';
    }

    final fullName =
        (_touristProfile?['full_name'] ?? '')
            .toString()
            .trim();

    if (fullName.isNotEmpty) {
      return fullName;
    }

    final firstName =
        (_touristProfile?['first_name'] ?? '')
            .toString()
            .trim();

    final lastName =
        (_touristProfile?['last_name'] ?? '')
            .toString()
            .trim();

    final joined = '$firstName $lastName'.trim();

    return joined.isNotEmpty
        ? joined
        : 'Tourist';
  }
}

// ============================================================================
// TOP BAR
// ============================================================================

class _AssignmentTopBar extends StatelessWidget {
  const _AssignmentTopBar({
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
      ),
      decoration: const BoxDecoration(
        color: _background,
      ),
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
                  border: Border.all(
                    color: _border,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: _ink,
                ),
              ),
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: -0.25,
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: _softBlue,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'DRIVER',
              style: TextStyle(
                color: _primary,
                fontWeight: FontWeight.w900,
                fontSize: 9,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// STATUS OVERVIEW
// ============================================================================

class _RideStatusOverview extends StatelessWidget {
  const _RideStatusOverview({
    required this.status,
    required this.title,
    required this.subtitle,
  });

  final String status;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final statusStyle = _rideStatusStyle(status);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _primary,
            _primaryLight,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.20),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.local_taxi_outlined,
              color: Colors.white,
              size: 21,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusChip(
                  label: statusStyle.label,
                  foreground: statusStyle.foreground,
                  background: statusStyle.background,
                ),

                const SizedBox(height: 9),

                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 10.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
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

// ============================================================================
// MAP
// ============================================================================

class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.status,
    required this.initialCenter,
    required this.pickup,
    required this.dropoff,
    required this.driver,
    required this.pickupName,
    required this.dropoffName,
    required this.routePoints,
    required this.onMapCreated,
    required this.onDriverLocation,
    required this.onTargetLocation,
  });

  final String status;

  final LatLng initialCenter;

  final LatLng? pickup;
  final LatLng? dropoff;
  final LatLng? driver;

  final String pickupName;
  final String dropoffName;

  final List<LatLng> routePoints;

  final ValueChanged<GoogleMapController> onMapCreated;

  final VoidCallback onDriverLocation;
  final VoidCallback onTargetLocation;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 288,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _border,
        ),
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
                  target: initialCenter,
                  zoom: 15,
                ),
                cameraTargetBounds: CameraTargetBounds(
                  _IncomingRideMapLimits.bounds,
                ),
                minMaxZoomPreference:
                    const MinMaxZoomPreference(
                  11,
                  19,
                ),
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: false,
                mapToolbarEnabled: false,
                buildingsEnabled: true,
                onMapCreated: onMapCreated,
                markers: {
                  if (pickup != null)
                    Marker(
                      markerId: const MarkerId('pickup'),
                      position: pickup!,
                      icon:
                          BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueGreen,
                      ),
                      infoWindow: InfoWindow(
                        title: pickupName.isEmpty
                            ? 'Pickup'
                            : pickupName,
                      ),
                    ),

                  if (dropoff != null)
                    Marker(
                      markerId: const MarkerId('dropoff'),
                      position: dropoff!,
                      icon:
                          BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueRed,
                      ),
                      infoWindow: InfoWindow(
                        title: dropoffName.isEmpty
                            ? 'Destination'
                            : dropoffName,
                      ),
                    ),

                  if (driver != null)
                    Marker(
                      markerId: const MarkerId('driver'),
                      position: driver!,
                      icon:
                          BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueAzure,
                      ),
                      infoWindow: const InfoWindow(
                        title: 'Your Location',
                      ),
                    ),
                },
                polylines: {
                  if (routePoints.length == 2)
                    Polyline(
                      polylineId:
                          const PolylineId('incoming-route'),
                      points: routePoints,
                      width: 6,
                      color: _primary.withValues(alpha: 0.82),
                    ),
                },
              ),
            ),

            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      color: _primary,
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'BULACAN',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              bottom: 12,
              right: 12,
              child: Column(
                children: [
                  _MapControlButton(
                    icon: Icons.my_location_rounded,
                    tooltip: 'My location',
                    onTap: onDriverLocation,
                  ),

                  const SizedBox(height: 8),

                  _MapControlButton(
                    icon: status == 'ongoing'
                        ? Icons.flag_outlined
                        : Icons.person_pin_circle_outlined,
                    tooltip: 'Current target',
                    onTap: onTargetLocation,
                  ),
                ],
              ),
            ),

            Positioned(
              left: 12,
              right: 76,
              bottom: 12,
              child: _MapLegend(
                status: status,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingRideMapLimits {
  static final LatLngBounds bounds = LatLngBounds(
    southwest: const LatLng(
      14.35,
      120.35,
    ),
    northeast: const LatLng(
      15.55,
      121.55,
    ),
  );
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(13),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              color: _ink,
              size: 19,
            ),
          ),
        ),
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _LegendDot(
            color: _primary,
          ),

          const SizedBox(width: 4),

          const Flexible(
            child: Text(
              'You',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _muted,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(width: 10),

          _LegendDot(
            color: status == 'ongoing'
                ? _danger
                : _success,
          ),

          const SizedBox(width: 4),

          Flexible(
            child: Text(
              status == 'ongoing'
                  ? 'Destination'
                  : 'Pickup',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _muted,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ============================================================================
// TOURIST CARD
// ============================================================================

class _TouristCard extends StatelessWidget {
  const _TouristCard({
    required this.name,
    required this.mobile,
    required this.imageUrl,
    required this.onCall,
    required this.onMessage,
  });

  final String name;
  final String mobile;
  final String imageUrl;

  final VoidCallback onCall;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: _softBlue,
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFD5E6FF),
              ),
            ),
            child: ClipOval(
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const _TouristAvatarFallback(),
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
                  'TOURIST',
                  style: TextStyle(
                    color: _subtle,
                    fontWeight: FontWeight.w900,
                    fontSize: 8.5,
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
                  mobile.isEmpty
                      ? 'No phone number available'
                      : mobile,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          _ContactActionButton(
            icon: Icons.call_outlined,
            tooltip: 'Call tourist',
            onTap: onCall,
          ),

          const SizedBox(width: 7),

          _ContactActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            tooltip: 'Message tourist',
            onTap: onMessage,
          ),
        ],
      ),
    );
  }
}

class _TouristAvatarFallback extends StatelessWidget {
  const _TouristAvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _softBlue,
      alignment: Alignment.center,
      child: const Icon(
        Icons.person_rounded,
        color: _primary,
        size: 25,
      ),
    );
  }
}

class _ContactActionButton extends StatelessWidget {
  const _ContactActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _softBlue,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              color: _primary,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SECTION TITLE
// ============================================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
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
          child: Icon(
            icon,
            color: _primary,
            size: 17,
          ),
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
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                subtitle,
                style: const TextStyle(
                  color: _subtle,
                  fontWeight: FontWeight.w600,
                  fontSize: 9.8,
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
// ROUTE TIMELINE
// ============================================================================

class _RouteTimelineCard extends StatelessWidget {
  const _RouteTimelineCard({
    required this.pickup,
    required this.dropoff,
    required this.status,
  });

  final String pickup;
  final String dropoff;
  final String status;

  @override
  Widget build(BuildContext context) {
    final pickupReached =
        status == 'arrived' ||
        status == 'ongoing' ||
        status == 'completed';

    final destinationReached =
        status == 'completed';

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _border,
        ),
      ),
      child: Column(
        children: [
          _RoutePoint(
            color: _success,
            title: 'PICKUP',
            value: pickup,
            subtitle: pickupReached
                ? 'Pickup reached'
                : 'Tourist pickup point',
            completed: pickupReached,
          ),

          Padding(
            padding: const EdgeInsets.only(
              left: 15,
            ),
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 30,
                  color: const Color(0xFFDCE5F0),
                ),
              ],
            ),
          ),

          _RoutePoint(
            color: _danger,
            title: 'DESTINATION',
            value: dropoff,
            subtitle: destinationReached
                ? 'Destination reached'
                : 'Tour destination',
            completed: destinationReached,
          ),
        ],
      ),
    );
  }
}

class _RoutePoint extends StatelessWidget {
  const _RoutePoint({
    required this.color,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.completed,
  });

  final Color color;
  final String title;
  final String value;
  final String subtitle;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.11),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            completed
                ? Icons.check_rounded
                : Icons.location_on_rounded,
            color: color,
            size: 17,
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
                  color: _subtle,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.55,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                value,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 12.2,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                subtitle,
                style: TextStyle(
                  color: completed
                      ? _success
                      : _muted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
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
// STAT CARDS
// ============================================================================

class _SummaryStatCard extends StatelessWidget {
  const _SummaryStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.accentBackground,
  });

  final IconData icon;
  final String label;
  final String value;

  final Color accent;
  final Color accentBackground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accentBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: accent,
              size: 18,
            ),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _subtle,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
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

// ============================================================================
// NEXT STEP
// ============================================================================

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _softBlue,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFCFE2FF),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: _primary,
              size: 18,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NEXT STEP',
                  style: TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                    letterSpacing: 0.5,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF58708E),
                    fontWeight: FontWeight.w600,
                    fontSize: 9.8,
                    height: 1.4,
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

class _CompletedCard extends StatelessWidget {
  const _CompletedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _successSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFBBF7D0),
        ),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Color(0xFFDCFCE7),
            child: Icon(
              Icons.check_rounded,
              color: _success,
            ),
          ),

          SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tour completed',
                  style: TextStyle(
                    color: Color(0xFF166534),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),

                SizedBox(height: 3),

                Text(
                  'This assignment has been successfully completed and recorded.',
                  style: TextStyle(
                    color: Color(0xFF3F7650),
                    fontWeight: FontWeight.w600,
                    fontSize: 9.8,
                    height: 1.35,
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

// ============================================================================
// BOTTOM ACTION
// ============================================================================

class _BottomRideAction extends StatelessWidget {
  const _BottomRideAction({
    required this.status,
    required this.action,
    required this.updating,
    required this.onPressed,
  });

  final String status;
  final _Action? action;
  final bool updating;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final completed = status == 'completed';

    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        11,
        16,
        11 + bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(
            color: _border,
          ),
        ),
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
              height: 50,
              decoration: BoxDecoration(
                color: _successSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFBBF7D0),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: _success,
                    size: 19,
                  ),

                  SizedBox(width: 7),

                  Text(
                    'TOUR COMPLETED',
                    style: TextStyle(
                      color: Color(0xFF166534),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.25,
                    ),
                  ),
                ],
              ),
            )
          : SizedBox(
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      _primary,
                      _primaryLight,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _primary.withValues(alpha: 0.20),
                      blurRadius: 16,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: updating ? null : onPressed,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: updating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(
                              action?.icon ??
                                  Icons.check_rounded,
                              size: 19,
                            ),

                            const SizedBox(width: 8),

                            Text(
                              action?.label ?? 'Continue',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                              ),
                            ),

                            const SizedBox(width: 6),

                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 17,
                            ),
                          ],
                        ),
                ),
              ),
            ),
    );
  }
}

// ============================================================================
// PAYMENT SHEET
// ============================================================================

class _PaymentConfirmationSheet extends StatelessWidget {
  const _PaymentConfirmationSheet({
    required this.amount,
    required this.method,
    required this.referenceController,
    required this.onCancel,
    required this.onConfirm,
  });

  final double amount;
  final String method;

  final TextEditingController referenceController;

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final isCash = method == 'cash';

    final keyboardInset =
        MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          18 + keyboardInset,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(28),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCE4EE),
                    borderRadius:
                        BorderRadius.circular(999),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _successSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      color: _success,
                      size: 21,
                    ),
                  ),

                  const SizedBox(width: 11),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm Payment',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),

                        SizedBox(height: 2),

                        Text(
                          'Record the payment received from the tourist',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF15803D),
                      Color(0xFF22C55E),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PAYMENT RECEIVED',
                      style: TextStyle(
                        color: Colors.white.withValues(
                          alpha: 0.72,
                        ),
                        fontWeight: FontWeight.w900,
                        fontSize: 8.5,
                        letterSpacing: 0.55,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      '₱${amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 27,
                        letterSpacing: -0.5,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: 0.14,
                        ),
                        borderRadius:
                            BorderRadius.circular(999),
                      ),
                      child: Text(
                        method.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              if (!isCash)
                TextField(
                  controller: referenceController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        '${method.toUpperCase()} Reference Number',
                    hintText:
                        'Enter reference number if available',
                    prefixIcon: const Icon(
                      Icons.receipt_long_outlined,
                      color: _primary,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: _border,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: _border,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: _primary,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius:
                        BorderRadius.circular(15),
                    border: Border.all(
                      color: const Color(0xFFFDE68A),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFD97706),
                        size: 18,
                      ),

                      SizedBox(width: 8),

                      Expanded(
                        child: Text(
                          'Confirm only after you have actually received the cash payment from the tourist.',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.w600,
                            fontSize: 10.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _success,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(15),
                    ),
                  ),
                  icon: const Icon(
                    Icons.check_rounded,
                    size: 19,
                  ),
                  label: const Text(
                    'Confirm & Complete Tour',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: _muted,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
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
// STATUS CHIP
// ============================================================================

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;

  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w900,
          fontSize: 8.5,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

_RideStatusStyle _rideStatusStyle(
  String status,
) {
  final normalized = status.trim().isEmpty
      ? 'accepted'
      : status.trim();

  switch (normalized) {
    case 'searching':
      return const _RideStatusStyle(
        label: 'SEARCHING',
        foreground: Color(0xFF475569),
        background: Color(0xFFF1F5F9),
      );

    case 'accepted':
      return const _RideStatusStyle(
        label: 'ACCEPTED',
        foreground: Color(0xFF166534),
        background: Color(0xFFDCFCE7),
      );

    case 'enroute_pickup':
      return const _RideStatusStyle(
        label: 'EN ROUTE',
        foreground: Color(0xFF1D4ED8),
        background: Color(0xFFDBEAFE),
      );

    case 'arrived':
      return const _RideStatusStyle(
        label: 'ARRIVED',
        foreground: Color(0xFF92400E),
        background: Color(0xFFFEF3C7),
      );

    case 'ongoing':
      return const _RideStatusStyle(
        label: 'TOUR IN PROGRESS',
        foreground: Color(0xFF5B21B6),
        background: Color(0xFFEDE9FE),
      );

    case 'completed':
      return const _RideStatusStyle(
        label: 'COMPLETED',
        foreground: Color(0xFF166534),
        background: Color(0xFFDCFCE7),
      );

    default:
      return _RideStatusStyle(
        label: normalized
            .replaceAll('_', ' ')
            .toUpperCase(),
        foreground: const Color(0xFF1D4ED8),
        background: const Color(0xFFDBEAFE),
      );
  }
}

class _RideStatusStyle {
  const _RideStatusStyle({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;
}

// ============================================================================
// EMPTY / LOADING
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
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: _primary,
              strokeWidth: 3,
            ),
          ),

          SizedBox(height: 14),

          Text(
            'Loading tour assignment...',
            style: TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAssignmentCard extends StatelessWidget {
  const _EmptyAssignmentCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _border,
        ),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: _softBlue,
            child: Icon(
              Icons.route_outlined,
              color: _primary,
              size: 27,
            ),
          ),

          SizedBox(height: 14),

          Text(
            'Assignment unavailable',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),

          SizedBox(height: 6),

          Text(
            'This tour assignment could not be found or may have already ended.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _muted,
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DATA CLASSES
// ============================================================================

class _Action {
  const _Action({
    required this.label,
    required this.nextStatus,
    required this.toast,
    required this.icon,
  });

  final String label;
  final String nextStatus;
  final String toast;

  final IconData icon;
}

class _NextStepInfo {
  const _NextStepInfo({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}