import '../../core/services/booking_driver_markers.dart';
import 'dart:async';
import 'package:touristrike/widgets/live_itinerary_estimates.dart';
import 'package:touristrike/core/services/stable_arrival_detector.dart';
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
import 'package:touristrike/core/services/developer_settings.dart';
import 'package:touristrike/core/services/route_polyline_service.dart';
import 'package:touristrike/core/services/live_marker_motion.dart';
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
  ConvoyStageProgress? _convoyProgress;

  bool _convoyLoading = true;
  String? _convoyError;

  RealtimeChannel? _bookingDriversChannel;
  RealtimeChannel? _participantLocationChannel;
  LatLng? _touristLivePosition;

  Timer? _convoyPollTimer;
  Timer? _convoyTicker;
  late StableArrivalDetector _arrivalDetector;
  Timer? _journeyTicker;
  Timer? _gpsRecoveryTimer;
  bool _gpsRecoveryBusy = false;
  bool _automaticTransitionBusy = false;
  String? _gpsIssue;
  DateTime? _gpsMonitoringStartedAt;
  DateTime? _lastUsableGpsAt;
  final Set<String> _confirmedArrivalKeys = {};
  DateTime? _lastAutomaticAttempt;
  String? _lastAutomaticKey;

  int _convoyConsecutiveFailures = 0;
  int _convoyLoadGeneration = 0;

  bool get _appearsOffline => _convoyConsecutiveFailures >= 2;

  Widget _buildConvoyOverview() {
    // -------------------------------------------------------------------------
    // LOADING
    // -------------------------------------------------------------------------

    if (_convoyLoading && _convoy.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: _primary,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Loading convoy',
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Checking the other drivers assigned to this tour.',
                    style: TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
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

    // -------------------------------------------------------------------------
    // ERROR
    // -------------------------------------------------------------------------

    if (_convoyError != null && _convoy.isEmpty) {
      return ConvoyRosterErrorCard(
        message: _convoyError!,
        onRetry: _loadConvoy,
      );
    }

    final me = _myConvoyStatus;

    if (me == null) {
      return ConvoyRosterErrorCard(
        message: 'You are not recorded as an accepted driver for this booking.',
        onRetry: _loadConvoy,
      );
    }

    final progress = _convoyProgress;
    final progressRequest = _stageProgressRequestFor(me);
    if (progress == null ||
        !progress.matches(progressRequest.stage, progressRequest.stopIndex)) {
      return ConvoyRosterErrorCard(
        message: 'Checking the authoritative convoy progress.',
        onRetry: _loadConvoy,
      );
    }

    final blockingDrivers = _blockingDriversFor(me);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Only display the roster for actual group/convoy bookings.
        if (_convoy.length > 1) ...[
          ConvoyRosterStrip(
            convoy: _convoy,
            selfDriverId: _repo.currentUserId ?? '',
            progress: progress,
            onCall: _callConvoyDriver,
          ),
          const SizedBox(height: 12),
        ],

        // Show barrier waiting information only when this driver
        // is currently waiting on other convoy members.
        if (blockingDrivers.isNotEmpty)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: ConvoyWaitingCard(
              key: ValueKey(
                'convoy-wait-${me.journeyState.name}-${me.currentStopIndex}',
              ),
              blockingDrivers: blockingDrivers,
            ),
          ),
      ],
    );
  }

  // =========================================================================
  // CORE SERVICES / STATE
  // =========================================================================

  static final _apiKey = CitySpotSuggestionService.resolveApiKey();

  static const LatLng _defaultCenter = LatLng(14.9597, 120.9206);

  final RoutePolylineService _routeService = RoutePolylineService(
    apiKey: _apiKey,
  );

  late double _proximityMeters;

  final TourisTrikeRepository _repo = TourisTrikeRepository();
  final SupabaseClient _supabase = Supabase.instance.client;

  String _bookingId = '';

  PackageActivity? _activity;
  PackageBooking? _booking;

  List<BookingItineraryItem> _spots = [];
  List<PaymentRecord> _paymentRecords = [];
  List<PaymentAllocation> _paymentAllocations = [];

  bool _loading = true;
  bool _actionBusy = false;
  bool _serverTestModeEnabled = false;

  String? _error;
  String? _eta;

  bool _isFollowingDriver = false;
  bool _isProgrammaticMove = false;

  BitmapDescriptor? _tricycleMarker;

  Position? _currentPosition;
  DateTime? _lastDriverLocationUploadAt;
  bool _driverLocationUploadInFlight = false;

  RealtimeChannel? _activityChannel;
  RealtimeChannel? _bookingChannel;
  RealtimeChannel? _itineraryChannel;
  RealtimeChannel? _paymentChannel;

  StreamSubscription<Position>? _gpsSub;
  Timer? _scheduleGateTimer;
  Timer? _routeRefreshTimer;
  int _routeLoadGeneration = 0;

  GoogleMapController? _mapCtrl;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  final LiveMarkerMotion _markerMotion = LiveMarkerMotion();
  final Map<String, LatLng> _liveMarkerPositions = <String, LatLng>{};
  final Map<String, double> _liveMarkerHeadings = <String, double>{};

  bool get _configuredTestMode => kDebugMode && _serverTestModeEnabled;

  bool get _bypassTransactionValidation => _configuredTestMode;

  String _testActionLabel(String productionLabel) =>
      kDebugMode && _bypassTransactionValidation
      ? '$productionLabel — TEST'
      : productionLabel;

  LatLng? get _simulatedDriverLocation {
    final settings = DeveloperSettings.instance;
    final driverId = _repo.currentUserId ?? '';
    if (!settings.canSimulateLocationFor(
      bookingId: _bookingId,
      driverId: driverId,
    )) {
      return null;
    }
    return LatLng(settings.simulatedLatitude!, settings.simulatedLongitude!);
  }

  bool get _isBookingCancelled {
    final values = [
      _booking?.status,
      _booking?.bookingStatus,
      _activity?.status,
      _activity?.tourStatus,
    ];

    return values.any((value) => value?.toLowerCase() == 'cancelled');
  }

  bool get _isBookingClosed {
    const terminal = {'cancelled', 'completed', 'done', 'rejected', 'closed'};
    final values = [
      _booking?.status,
      _booking?.bookingStatus,
      _activity?.status,
      _activity?.tourStatus,
    ];
    return values.any((value) => terminal.contains(value?.toLowerCase()));
  }

  bool get _shouldShareDriverLocation =>
      !_isBookingClosed &&
      _myConvoyStatus?.journeyState != ConvoyJourneyState.completed;

  bool _hasConfirmedPayment(String stage, double requiredAmount) {
    if (requiredAmount <= 0) return true;
    return _paymentRecords.any(
      (record) =>
          record.paymentStage == stage &&
          record.status == 'confirmed' &&
          record.amount >= requiredAmount,
    );
  }

  String? get _serverGateNotice {
    final me = _myConvoyStatus;
    final booking = _booking;
    if (me == null || booking == null) return null;

    if (me.journeyState == ConvoyJourneyState.assigned) {
      final scheduled = booking.scheduledStartAt;
      if (!_bypassTransactionValidation &&
          scheduled != null &&
          DateTime.now().isBefore(scheduled)) {
        return 'Upcoming booking • Navigation unlocks ${DateFormat('MMM d, yyyy • h:mm a').format(scheduled.toLocal())}.';
      }
      if (!_bypassTransactionValidation &&
          !_hasConfirmedPayment('down_payment', booking.downpaymentAmount)) {
        return 'Down payment has not been confirmed yet. Required: ₱${booking.downpaymentAmount.toStringAsFixed(2)}.';
      }
    }

    if (!_bypassTransactionValidation &&
        const {
          ConvoyJourneyState.stopDone,
          ConvoyJourneyState.atDropoff,
        }.contains(me.journeyState) &&
        _allItineraryItemsCompleted &&
        !_hasConfirmedPayment('remaining_balance', booking.remainingBalance)) {
      return 'Waiting for remaining payment. Drop-off unlocks after secure GCash confirmation or every convoy driver confirms cash.';
    }

    return null;
  }

  void _syncScheduleGateTimer() {
    _scheduleGateTimer?.cancel();
    final scheduled = _booking?.scheduledStartAt;
    if (scheduled == null) return;
    final delay = scheduled.difference(DateTime.now());
    if (delay.isNegative) return;
    _scheduleGateTimer = Timer(delay + const Duration(seconds: 1), () {
      if (mounted) setState(() {});
    });
  }

  // =========================================================================
  // LIFECYCLE
  // =========================================================================

  @override
  void initState() {
    super.initState();

    DeveloperSettings.instance.addListener(_onDeveloperSettingsChanged);
    _initCustomMarkers();
    _load();
    _journeyTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _isBookingClosed) return;
      setState(() {});
      unawaited(_progressReadyJourney());
    });
    _gpsRecoveryTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _recoverGpsFix(),
    );
  }

  void _onDeveloperSettingsChanged() {
    if (mounted) setState(() {});
    if (mounted && !_loading) unawaited(_startGpsStreaming());
  }

  @override
  void dispose() {
    DeveloperSettings.instance.removeListener(_onDeveloperSettingsChanged);
    _journeyTicker?.cancel();
    _gpsRecoveryTimer?.cancel();
    _activityChannel?.unsubscribe();
    _bookingChannel?.unsubscribe();
    _itineraryChannel?.unsubscribe();
    _paymentChannel?.unsubscribe();

    _bookingDriversChannel?.unsubscribe();
    _participantLocationChannel?.unsubscribe();

    _convoyPollTimer?.cancel();
    _convoyTicker?.cancel();

    _gpsSub?.cancel();
    _scheduleGateTimer?.cancel();
    _routeRefreshTimer?.cancel();
    _markerMotion.dispose();
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
        _repo.fetchDriverArrivalRadiusMeters(),
      ]);
      _proximityMeters = results[2] as double;
      _arrivalDetector = StableArrivalDetector(radiusMeters: _proximityMeters);

      var serverTestModeEnabled = false;
      if (kDebugMode) {
        try {
          serverTestModeEnabled = await _repo.fetchDeveloperTestBookingMode(
            bookingId,
          );
        } catch (error) {
          debugPrint(
            '[TEST MODE] booking_id=$bookingId action=read '
            'server_state_error=$error',
          );
        }
      }

      final booking = results[0] as PackageBooking?;

      var spots = results[1] as List<BookingItineraryItem>;

      if (spots.isEmpty) {
        await _repo.ensureBookingItinerary(bookingId);

        spots = await _repo.fetchBookingItinerary(bookingId);
      }

      var paymentRecords = <PaymentRecord>[];
      var paymentAllocations = <PaymentAllocation>[];

      try {
        paymentRecords = await _repo.fetchPaymentRecordsFor(
          bookingId: bookingId,
        );
        paymentAllocations = await _repo.fetchPaymentAllocationsForBooking(
          bookingId,
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
        _paymentAllocations = paymentAllocations;
        _serverTestModeEnabled = serverTestModeEnabled;
        _loading = false;
      });

      _debugTourState('load');

      _syncScheduleGateTimer();

      _buildMarkers();
      _subscribeRealtime();

      if (_isBookingClosed) {
        await _gpsSub?.cancel();
        _gpsSub = null;

        _bookingDriversChannel?.unsubscribe();
        _bookingDriversChannel = null;

        _convoyPollTimer?.cancel();
        _convoyPollTimer = null;

        _convoyTicker?.cancel();
        _convoyTicker = null;

        if (mounted) {
          setState(() {
            _convoyLoading = false;
            _convoyError = null;
            _convoyConsecutiveFailures = 0;
          });
        }

        await _loadConvoy();
        _buildMarkers();
      } else {
        _fetchCurrentRoute();
        _startGpsStreaming();

        await _loadConvoy();
        _subscribeConvoyRealtime();
      }
    } catch (e, stackTrace) {
      debugPrint('[DriverTracking:load] Error: $e');

      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _error = 'Unable to load tour information. Please try again.';
        _loading = false;
      });
    }
  }

  // =========================================================================
  // CONVOY SYNC
  // =========================================================================

  Future<void> _loadConvoy() async {
    if (_bookingId.isEmpty) return;
    final loadGeneration = ++_convoyLoadGeneration;

    if (_convoy.isEmpty && mounted) {
      setState(() {
        _convoyLoading = true;
        _convoyError = null;
      });
    }

    final before = _myConvoyStatus;

    final wasBlocked = before != null && _blockingDriversFor(before).isNotEmpty;

    try {
      final roster = await _repo.fetchConvoyRoster(_bookingId);
      ConvoyDriverSnapshot? rosterMe;
      final currentUserId = _repo.currentUserId;
      if (currentUserId != null) {
        for (final driver in roster) {
          if (driver.driverId == currentUserId) {
            rosterMe = driver;
            break;
          }
        }
      }
      ConvoyStageProgress? progress;
      if (rosterMe != null) {
        final request = _stageProgressRequestFor(rosterMe);
        progress = await _repo.fetchConvoyStageProgress(
          bookingId: _bookingId,
          stage: request.stage,
          stopIndex: request.stopIndex,
        );
      }

      if (!mounted || loadGeneration != _convoyLoadGeneration) return;

      for (final driver in roster) {
        if (driver.latitude == null || driver.longitude == null) continue;
        final point = LatLng(driver.latitude!, driver.longitude!);
        _markerMotion.seedIfAbsent(driver.driverId, point, driver.heading);
        _liveMarkerPositions[driver.driverId] = point;
        _liveMarkerHeadings[driver.driverId] = driver.heading;
      }

      setState(() {
        _convoy = roster;
        _convoyProgress = progress;
        _convoyLoading = false;
        _convoyConsecutiveFailures = 0;

        _convoyError = roster.isEmpty
            ? 'Could not load the driver roster for this booking.'
            : null;
      });

      _syncConvoyTicker();

      if (!_shouldShareDriverLocation) {
        await _gpsSub?.cancel();
        _gpsSub = null;
      }

      _buildMarkers();
      _scheduleRouteRefresh();

      _maybeAnnounceBarrierReleased(before: before, wasBlocked: wasBlocked);
    } catch (e) {
      if (!mounted || loadGeneration != _convoyLoadGeneration) return;

      setState(() {
        _convoyLoading = false;
        _convoyProgress = null;
        _convoyConsecutiveFailures++;

        if (!_appearsOffline) {
          _convoyError = 'Could not load the driver roster: $e';
        }
      });
    }
  }

  void _subscribeConvoyRealtime() {
    final bookingId = _bookingId;

    if (bookingId.isEmpty) return;

    _bookingDriversChannel?.unsubscribe();

    _bookingDriversChannel = _supabase
        .channel('convoy-roster:$bookingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'booking_drivers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: bookingId,
          ),
          callback: (_) {
            _refreshLifecycleAndConvoy('convoy-insert');
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'booking_drivers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: bookingId,
          ),
          callback: (_) {
            _refreshLifecycleAndConvoy('convoy-update');
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_live_locations',
          callback: (payload) {
            final row = payload.newRecord;
            final driverId = row['driver_id']?.toString() ?? '';
            if (driverId.isEmpty ||
                !_convoy.any((driver) => driver.driverId == driverId)) {
              return;
            }
            final lat = (row['latitude'] as num?)?.toDouble();
            final lng = (row['longitude'] as num?)?.toDouble();
            if (lat == null ||
                lng == null ||
                !lat.isFinite ||
                !lng.isFinite ||
                lat < -90 ||
                lat > 90 ||
                lng < -180 ||
                lng > 180) {
              return;
            }
            final merged = mergeBookingDriverLocation(_convoy, row);
            final before = _convoy
                .where((d) => d.driverId == driverId)
                .firstOrNull;
            final after = merged
                .where((d) => d.driverId == driverId)
                .firstOrNull;
            if (identical(before, after)) return;
            setState(() => _convoy = merged);
            _markerMotion.animateTo(
              driverId,
              LatLng(lat, lng),
              (row['heading'] as num?)?.toDouble() ?? 0,
              (position, heading) {
                if (!mounted) return;
                setState(() {
                  _liveMarkerPositions[driverId] = position;
                  _liveMarkerHeadings[driverId] = heading;
                });
                _buildMarkers();
              },
            );
            _scheduleRouteRefresh();
          },
        )
        .subscribe();

    _participantLocationChannel?.unsubscribe();
    _participantLocationChannel = _supabase
        .channel('booking-participant-location:$bookingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'booking_participant_live_locations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: bookingId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row['participant_role'] != 'tourist') return;
            final lat = (row['latitude'] as num?)?.toDouble();
            final lng = (row['longitude'] as num?)?.toDouble();
            if (!mounted || lat == null || lng == null) return;
            setState(() => _touristLivePosition = LatLng(lat, lng));
            _buildMarkers();
          },
        )
        .subscribe();
    unawaited(_loadTouristLiveLocation());

    _convoyPollTimer?.cancel();

    _convoyPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_isBookingClosed) {
        _loadConvoy();
      }
    });
  }

  Future<void> _loadTouristLiveLocation() async {
    final row = await _repo.fetchTouristLiveLocation(_bookingId);
    final lat = (row?['latitude'] as num?)?.toDouble();
    final lng = (row?['longitude'] as num?)?.toDouble();
    if (!mounted || lat == null || lng == null) return;
    setState(() => _touristLivePosition = LatLng(lat, lng));
    _buildMarkers();
  }

  ConvoyDriverSnapshot? get _myConvoyStatus {
    final myId = _repo.currentUserId;

    if (myId == null) return null;

    for (final driver in _convoy) {
      if (driver.driverId == myId) {
        return driver;
      }
    }

    return null;
  }

  ({String stage, int? stopIndex}) _stageProgressRequestFor(
    ConvoyDriverSnapshot driver,
  ) {
    return switch (driver.journeyState) {
      ConvoyJourneyState.assigned => (stage: 'assigned', stopIndex: null),
      ConvoyJourneyState.enRoutePickup ||
      ConvoyJourneyState.atPickup => (stage: 'at_pickup', stopIndex: null),
      ConvoyJourneyState.boarded => (stage: 'boarded', stopIndex: null),
      ConvoyJourneyState.enRouteStop || ConvoyJourneyState.atStop => (
        stage: 'at_stop',
        stopIndex: driver.currentStopIndex,
      ),
      ConvoyJourneyState.stopDone => (
        stage: 'stop_done',
        stopIndex: driver.currentStopIndex,
      ),
      ConvoyJourneyState.enRouteDropoff ||
      ConvoyJourneyState.atDropoff => (stage: 'at_dropoff', stopIndex: null),
      ConvoyJourneyState.completed => (stage: 'completed', stopIndex: null),
    };
  }

  void _refreshLifecycleAndConvoy(String logTag) {
    unawaited(
      Future.wait([_refreshTrackingState(logTag: logTag), _loadConvoy()]),
    );
  }

  void _syncConvoyTicker() {
    final me = _myConvoyStatus;

    final blocked = me != null && _blockingDriversFor(me).isNotEmpty;

    if (blocked && _convoyTicker == null) {
      _convoyTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (!blocked && _convoyTicker != null) {
      _convoyTicker?.cancel();
      _convoyTicker = null;
    }
  }

  void _maybeAnnounceBarrierReleased({
    required ConvoyDriverSnapshot? before,
    required bool wasBlocked,
  }) {
    if (!wasBlocked || before == null) {
      return;
    }

    final after = _myConvoyStatus;

    if (after == null) return;

    if (after.journeyState != before.journeyState) {
      return;
    }

    if (_blockingDriversFor(after).isNotEmpty) {
      return;
    }

    HapticFeedback.mediumImpact();

    _showSnack('All drivers are ready. You may continue.');
  }

  List<ConvoyDriverSnapshot> _blockingDriversFor(ConvoyDriverSnapshot me) {
    if (me.journeyState != ConvoyJourneyState.boarded &&
        me.journeyState != ConvoyJourneyState.stopDone) {
      return const [];
    }
    final request = _stageProgressRequestFor(me);
    final progress = _convoyProgress;
    if (progress == null ||
        !progress.matches(request.stage, request.stopIndex)) {
      return const [];
    }
    final waitingIds = progress.waitingDriverIds.toSet();
    return _convoy
        .where((driver) => waitingIds.contains(driver.driverId))
        .toList(growable: false);
  }

  Future<bool> _advanceConvoyStateCore(ConvoyJourneyState target) async {
    try {
      await _repo.advanceDriverJourneyState(
        bookingId: _bookingId,
        targetState: target,
      );

      await Future.wait([
        _loadConvoy(),
        _refreshTrackingState(logTag: 'convoy-advance'),
      ]);

      return true;
    } on ConvoyBarrierNotMetException {
      await _loadConvoy();

      _showSnack(
        'Not everyone is ready yet. Waiting for the rest of the convoy.',
      );

      return false;
    } on PostgrestException catch (error) {
      final message = error.message;
      if (message.contains('DOWNPAYMENT_NOT_CONFIRMED')) {
        _showSnack('Waiting for tourist down payment.', error: true);
        return false;
      }
      if (message.contains('BOOKING_START_TOO_EARLY')) {
        _showSnack(
          'This tour cannot start before its scheduled date and time.',
          error: true,
        );
        return false;
      }
      if (message.contains('DRIVER_SLOTS_NOT_FILLED')) {
        _showSnack('Waiting for all required drivers to accept.', error: true);
        return false;
      }
      if (message.contains('REMAINING_BALANCE_NOT_CONFIRMED')) {
        _showSnack(
          'Confirm the remaining balance payment before completing the tour.',
          error: true,
        );
        return false;
      }
      rethrow;
    }
  }

  // =========================================================================
  // REALTIME
  // =========================================================================

  void _subscribeRealtime() {
    final bookingId = _bookingId;

    if (bookingId.isEmpty) {
      return;
    }

    _activityChannel?.unsubscribe();

    _activityChannel = _supabase
        .channel('driver-activity:$bookingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'package_activities',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: bookingId,
          ),
          callback: (_) {
            _refreshLifecycleAndConvoy('activity-update');
          },
        )
        .subscribe();

    _bookingChannel?.unsubscribe();

    _bookingChannel = _supabase
        .channel('driver-booking:$bookingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'package_bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: bookingId,
          ),
          callback: (_) {
            _refreshLifecycleAndConvoy('booking-update');
          },
        )
        .subscribe();

    _itineraryChannel?.unsubscribe();

    _itineraryChannel = _supabase
        .channel('driver-itinerary:$bookingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'booking_itinerary_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: bookingId,
          ),
          callback: (_) {
            _refreshLifecycleAndConvoy('itinerary-update');
          },
        )
        .subscribe();

    _paymentChannel?.unsubscribe();
    _paymentChannel = _supabase
        .channel('driver-payments:$bookingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payment_records',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: bookingId,
          ),
          callback: (_) {
            _refreshTrackingState(logTag: 'payment-update');
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payment_allocations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: bookingId,
          ),
          callback: (_) {
            _refreshTrackingState(logTag: 'payment-allocation-update');
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'booking_payment_requirements',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: bookingId,
          ),
          callback: (_) {
            _refreshTrackingState(logTag: 'payment-requirement-update');
          },
        )
        .subscribe();
  }

  // =========================================================================
  // GPS
  // =========================================================================

  Future<void> _startGpsStreaming() async {
    if (!_shouldShareDriverLocation) return;
    _gpsMonitoringStartedAt ??= DateTime.now();

    final simulated = _simulatedDriverLocation;
    if (simulated != null) {
      await _gpsSub?.cancel();
      _gpsSub = null;
      await _recoverGpsFix();
      _buildMarkers();
      _fetchCurrentRoute();
      return;
    }

    final ok = await _checkLocationPermission();

    if (!ok) {
      if (mounted) {
        setState(
          () => _gpsIssue =
              'Location is unavailable. Enable GPS and location permission.',
        );
      }
      return;
    }

    await _gpsSub?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) async {
        final activity = _activity;

        if (activity == null || !_shouldShareDriverLocation) {
          return;
        }

        if (!_acceptGpsFix(position)) return;

        final now = DateTime.now();
        final mayUpload =
            !_driverLocationUploadInFlight &&
            (_lastDriverLocationUploadAt == null ||
                now.difference(_lastDriverLocationUploadAt!) >=
                    const Duration(seconds: 3));
        if (!mayUpload) {
          _buildMarkers();
          if (_isFollowingDriver) {
            _animateCameraFollowing(
              LatLng(position.latitude, position.longitude),
              position.speed,
            );
          }
          return;
        }
        _driverLocationUploadInFlight = true;
        _lastDriverLocationUploadAt = now;

        try {
          // Each driver always writes to their own live-location row.
          await _repo.upsertDriverLiveLocation(
            activityId: widget.activityId,
            latitude: position.latitude,
            longitude: position.longitude,
            heading: position.heading,
            speed: position.speed,
          );

          await _detectAutomaticArrival(position);

          if (!mounted || !_shouldShareDriverLocation) return;

          // package_activities has only one legacy driver_latitude/longitude
          // pair. On a convoy booking, only the legacy assigned driver writes
          // those columns so convoy drivers do not overwrite one another.
          final isLegacyWriter =
              _convoy.length <= 1 ||
              _booking?.assignedDriverId == _repo.currentUserId;

          if (isLegacyWriter) {
            await _repo.updateDriverLocation(
              activityId: widget.activityId,
              latitude: position.latitude,
              longitude: position.longitude,
            );
          }

          if (!mounted) return;

          final myId = _repo.currentUserId;
          if (myId != null) {
            _markerMotion.animateTo(
              myId,
              LatLng(position.latitude, position.longitude),
              position.heading,
              (displayed, heading) {
                if (!mounted) return;
                setState(() {
                  _liveMarkerPositions[myId] = displayed;
                  _liveMarkerHeadings[myId] = heading;
                });
                _buildMarkers();
              },
            );
          }

          if (isLegacyWriter) {
            setState(() {
              _activity = PackageActivity({
                ...?_activity?.row,
                'driver_latitude': position.latitude,
                'driver_longitude': position.longitude,
                'driver_last_seen': DateTime.now().toIso8601String(),
              });
            });
          }

          _buildMarkers();
          _scheduleRouteRefresh();

          if (_isFollowingDriver) {
            _animateCameraFollowing(
              LatLng(position.latitude, position.longitude),
              position.speed,
            );
          }
        } catch (e) {
          _gpsIssue = 'Unable to sync your location. Check your connection.';
          debugPrint('[DriverTracking:gps] Location sync failed: $e');

          // Keep the local driver marker responsive even if the backend write
          // temporarily fails.
          if (mounted) {
            _buildMarkers();
          }
        } finally {
          _driverLocationUploadInFlight = false;
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(
            () => _gpsIssue =
                'GPS updates stopped. Retry location or use arrival fallback.',
          );
        }
      },
    );
  }

  ({ConvoyJourneyState state, LatLng point})? get _arrivalTarget {
    final me = _myConvoyStatus;
    if (me == null) return null;
    final point = switch (me.journeyState) {
      ConvoyJourneyState.enRoutePickup => _pickupLatLng(),
      ConvoyJourneyState.enRouteStop => _currentSpotLatLng(),
      ConvoyJourneyState.enRouteDropoff => _dropoffLatLng(),
      _ => null,
    };
    if (point == null) return null;
    return (
      state: switch (me.journeyState) {
        ConvoyJourneyState.enRoutePickup => ConvoyJourneyState.atPickup,
        ConvoyJourneyState.enRouteStop => ConvoyJourneyState.atStop,
        _ => ConvoyJourneyState.atDropoff,
      },
      point: point,
    );
  }

  Future<void> _detectAutomaticArrival(Position position) async {
    final target = _arrivalTarget;
    if (!_shouldShareDriverLocation ||
        target == null ||
        _automaticTransitionBusy ||
        _actionBusy) {
      return;
    }
    final key =
        '$_bookingId:${target.state.dbValue}:${_myConvoyStatus?.currentStopIndex}';
    if (_confirmedArrivalKeys.contains(key)) return;
    final stable = _arrivalDetector.observe(
      target: key,
      distanceMeters: _haversineMeters(
        position.latitude,
        position.longitude,
        target.point.latitude,
        target.point.longitude,
      ),
      accuracyMeters: position.accuracy,
      sampledAt: position.timestamp,
      now: DateTime.now(),
    );
    if (!stable || !_canAttemptAutomatic(key)) return;
    _automaticTransitionBusy = true;
    try {
      final result = await _repo.advanceDriverJourneyState(
        bookingId: _bookingId,
        targetState: target.state,
        automaticArrival: true,
      );
      _confirmedArrivalKeys.add(key);
      _arrivalDetector.reset();
      if (mounted) {
        if (result['no_op'] != true) {
          _showSnack(switch (target.state) {
            ConvoyJourneyState.atPickup =>
              "You've arrived at the tourist pickup point.",
            ConvoyJourneyState.atStop =>
              'Arrived at ${_currentItineraryItem?.destinationName ?? 'tour stop'}. Stay timer started.',
            _ => 'Arrived at drop-off location.',
          });
        }
        await Future.wait([
          _loadConvoy(),
          _refreshTrackingState(logTag: 'gps-arrival'),
        ]);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _gpsIssue =
              'Unable to verify arrival automatically. Retry or use the arrival fallback.',
        );
      }
    } finally {
      _automaticTransitionBusy = false;
    }
  }

  bool _canAttemptAutomatic(String key) {
    final now = DateTime.now();
    if (_lastAutomaticKey == key &&
        _lastAutomaticAttempt != null &&
        now.difference(_lastAutomaticAttempt!) < const Duration(seconds: 10)) {
      return false;
    }
    _lastAutomaticKey = key;
    _lastAutomaticAttempt = now;
    return true;
  }

  Future<void> _recoverGpsFix() async {
    if (!mounted ||
        _gpsRecoveryBusy ||
        !_shouldShareDriverLocation ||
        _activity == null) {
      return;
    }
    _gpsRecoveryBusy = true;
    try {
      final simulated = _simulatedDriverLocation;
      if (simulated == null &&
          (!await Geolocator.isLocationServiceEnabled() ||
              !const {
                LocationPermission.always,
                LocationPermission.whileInUse,
              }.contains(await Geolocator.checkPermission()))) {
        if (mounted) {
          setState(
            () => _gpsIssue =
                'Enable GPS and location permission to verify arrival.',
          );
        }
        return;
      }
      final position = simulated == null
          ? await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 7),
            )
          : Position(
              latitude: simulated.latitude,
              longitude: simulated.longitude,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            );
      if (!mounted || !_shouldShareDriverLocation || !_acceptGpsFix(position)) {
        return;
      }
      await _repo.upsertDriverLiveLocation(
        activityId: widget.activityId,
        latitude: position.latitude,
        longitude: position.longitude,
        heading: position.heading,
        speed: position.speed,
      );
      if (!mounted) return;
      _convoy = mergeBookingDriverLocation(_convoy, {
        'driver_id': _repo.currentUserId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'heading': position.heading,
        'updated_at': position.timestamp.toIso8601String(),
      });
      final myId = _repo.currentUserId;
      if (myId != null) {
        _liveMarkerPositions[myId] = LatLng(
          position.latitude,
          position.longitude,
        );
        _liveMarkerHeadings[myId] = position.heading;
      }
      _buildMarkers();
      await _detectAutomaticArrival(position);
    } catch (_) {
      if (mounted) {
        setState(
          () => _gpsIssue =
              'Unable to verify arrival automatically. Check GPS and connection.',
        );
      }
    } finally {
      _gpsRecoveryBusy = false;
    }
  }

  bool _acceptGpsFix(Position position) {
    final now = DateTime.now();
    if (_lastUsableGpsAt != null &&
        position.timestamp.isBefore(_lastUsableGpsAt!)) {
      return false;
    }
    if (!StableArrivalDetector.isUsableFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      sampledAt: position.timestamp,
      now: now,
    )) {
      _arrivalDetector.reset();
      return false;
    }
    _currentPosition = position;
    _lastUsableGpsAt = position.timestamp;
    _gpsIssue = null;
    // Even an update skipped by upload throttling must break a noisy streak.
    final target = _arrivalTarget;
    if (target != null &&
        _haversineMeters(
              position.latitude,
              position.longitude,
              target.point.latitude,
              target.point.longitude,
            ) >
            _proximityMeters) {
      _arrivalDetector.reset();
    }
    return true;
  }

  String? get _arrivalGpsFailure {
    if (_gpsIssue != null) return _gpsIssue;
    final since = _lastUsableGpsAt ?? _gpsMonitoringStartedAt;
    if (since != null &&
        DateTime.now().difference(since) >= const Duration(seconds: 30)) {
      return 'No recent accurate GPS fix. Move to an open area or retry GPS.';
    }
    return null;
  }

  Duration get _stayRemaining {
    final me = _myConvoyStatus;
    if (me == null ||
        me.journeyState != ConvoyJourneyState.atStop ||
        (me.currentStopIndex < 0 || me.currentStopIndex >= _spots.length)) {
      return Duration.zero;
    }
    return remainingStopStay(
      arrivedAt: me.stateUpdatedAt,
      stayMinutes: _spots[me.currentStopIndex].estimatedStayDurationMinutes,
      now: DateTime.now(),
    );
  }

  Future<void> _progressReadyJourney() async {
    final me = _myConvoyStatus;
    if (me == null ||
        _actionBusy ||
        _automaticTransitionBusy ||
        _loading ||
        !const {
          ConvoyJourneyState.boarded,
          ConvoyJourneyState.stopDone,
        }.contains(me.journeyState)) {
      return;
    }
    final request = _stageProgressRequestFor(me);
    if (_convoyProgress?.matches(request.stage, request.stopIndex) != true ||
        _convoyProgress?.allSatisfied != true ||
        _serverGateNotice != null) {
      return;
    }
    if (me.journeyState == ConvoyJourneyState.stopDone &&
        !_allItineraryItemsCompleted &&
        me.currentStopIndex >= _spots.length - 1) {
      return;
    }
    final key = 'depart:${me.journeyState.dbValue}:${me.currentStopIndex}';
    if (!_canAttemptAutomatic(key)) return;
    _automaticTransitionBusy = true;
    try {
      if (me.journeyState == ConvoyJourneyState.boarded) {
        await _departPickup();
      } else {
        await _departStop();
      }
    } finally {
      _automaticTransitionBusy = false;
    }
  }

  Future<void> _manualArrivalFallback() async {
    if (_actionBusy ||
        _automaticTransitionBusy ||
        _arrivalTarget == null ||
        _arrivalGpsFailure == null) {
      return;
    }
    final requestedTarget = _arrivalTarget;
    final requestedStopIndex = _myConvoyStatus?.currentStopIndex;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm arrival fallback'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Use this only when you are at the destination and automatic GPS detection failed. The server checks a recent driver or tourist location. An internet connection is required.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason (at least 10 characters)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().length >= 10) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Confirm arrival'),
          ),
        ],
      ),
    );
    // The dialog's text field is disposed after its closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (!mounted ||
        reason == null ||
        _arrivalGpsFailure == null ||
        _arrivalTarget != requestedTarget ||
        _myConvoyStatus?.currentStopIndex != requestedStopIndex) {
      return;
    }
    await _doAction(() async {
      await _repo.confirmDriverArrivalFallback(_bookingId, reason);
      await Future.wait([
        _loadConvoy(),
        _refreshTrackingState(logTag: 'manual-arrival-fallback'),
      ]);
      _showSnack('Arrival confirmed.');
    });
  }

  Widget _buildJourneyAutomationNotice() {
    final me = _myConvoyStatus;
    if (me == null) return const SizedBox.shrink();
    final target = _arrivalTarget;
    final stay = _stayRemaining;
    final gpsFailure = _arrivalGpsFailure;
    final message = target != null
        ? gpsFailure != null
              ? 'Unable to verify arrival automatically.\n$gpsFailure'
              : '${switch (me.journeyState) {
                  ConvoyJourneyState.enRoutePickup => 'Heading to pickup',
                  ConvoyJourneyState.enRouteStop => 'Heading to ${_currentItineraryItem?.destinationName ?? 'tour stop'}',
                  _ => 'Heading to drop-off',
                }}\nArrival will be detected automatically by GPS within ${_proximityMeters.toInt()} m.'
        : me.journeyState == ConvoyJourneyState.atStop &&
              me.currentStopIndex >= 0 &&
              me.currentStopIndex < _spots.length
        ? 'Arrived ${DateFormat('h:mm a').format(me.stateUpdatedAt.toLocal())} · Time of Stay: ${_spots[me.currentStopIndex].estimatedStayDurationMinutes} min\n'
              'Expected departure: ${DateFormat('h:mm a').format(me.stateUpdatedAt.toLocal().add(Duration(minutes: _spots[me.currentStopIndex].estimatedStayDurationMinutes)))}\n'
              '${stay > Duration.zero ? '${stay.inMinutes}:${(stay.inSeconds % 60).toString().padLeft(2, '0')} remaining' : 'Stay complete. Confirm when your passengers are ready.'}'
        : me.journeyState == ConvoyJourneyState.boarded
        ? 'Tourist picked up. Navigation starts when the convoy is ready.'
        : me.journeyState == ConvoyJourneyState.stopDone
        ? 'You are ready. Waiting for convoy readiness and any required payment.'
        : me.journeyState.label;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            if (target != null && gpsFailure != null)
              Wrap(
                children: [
                  TextButton(
                    onPressed: () async {
                      await _startGpsStreaming();
                      await _recoverGpsFix();
                    },
                    child: const Text('Retry GPS'),
                  ),
                  TextButton(
                    onPressed: _actionBusy || _automaticTransitionBusy
                        ? null
                        : _manualArrivalFallback,
                    child: const Text('Verify Arrival Manually'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
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

  BookingItineraryItem? get _currentItineraryItem {
    final me = _myConvoyStatus;
    if (me != null &&
        const {
          ConvoyJourneyState.enRouteStop,
          ConvoyJourneyState.atStop,
          ConvoyJourneyState.stopDone,
        }.contains(me.journeyState)) {
      final index = me.journeyState == ConvoyJourneyState.stopDone
          ? me.currentStopIndex + 1
          : me.currentStopIndex;
      return index >= 0 && index < _spots.length ? _spots[index] : null;
    }
    return _spots.where((spot) => spot.spotStatus != 'completed').firstOrNull;
  }

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
    var paymentAllocations = _paymentAllocations;

    try {
      paymentRecords = await _repo.fetchPaymentRecordsFor(bookingId: bookingId);
      paymentAllocations = await _repo.fetchPaymentAllocationsForBooking(
        bookingId,
      );
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _activity = results[0] as PackageActivity?;

      _booking = results[1] as PackageBooking?;

      _spots = refreshedSpots;

      _paymentRecords = paymentRecords;
      _paymentAllocations = paymentAllocations;
    });

    _debugTourState(logTag);

    if (_isBookingClosed) {
      await _gpsSub?.cancel();
      _gpsSub = null;

      _bookingDriversChannel?.unsubscribe();
      _bookingDriversChannel = null;

      _convoyPollTimer?.cancel();
      _convoyPollTimer = null;

      _convoyTicker?.cancel();
      _convoyTicker = null;

      if (mounted) {
        setState(() {
          _polylines = {};
          _convoyLoading = false;
          _convoyError = null;
          _convoyConsecutiveFailures = 0;
        });
      }
      await _loadConvoy();
      _buildMarkers();
    } else {
      _buildMarkers();
      _fetchCurrentRoute();

      // Refresh convoy state as part of a tracking refresh.
      if (_bookingId.isNotEmpty) {
        await _loadConvoy();
      }
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

    if (_touristLivePosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('tourist_live'),
          position: _touristLivePosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Tourist'),
          zIndexInt: 2,
        ),
      );
    }

    final pickup = _pickupLatLng();
    final dropoff = _dropoffLatLng();

    // -------------------------------------------------------------------------
    // PICKUP
    // -------------------------------------------------------------------------

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

    // -------------------------------------------------------------------------
    // DROP-OFF
    // -------------------------------------------------------------------------

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

    // -------------------------------------------------------------------------
    // ITINERARY SPOTS
    // -------------------------------------------------------------------------

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

    markers.addAll(
      buildBookingDriverMarkers(
        drivers: _convoy,
        icon:
            _tricycleMarker ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        positions: _liveMarkerPositions,
        headings: _liveMarkerHeadings,
        viewerId: _repo.currentUserId,
      ),
    );

    if (!mounted) return;

    setState(() {
      _markers = markers;
    });
  }

  void _scheduleRouteRefresh() {
    _routeRefreshTimer?.cancel();
    _routeRefreshTimer = Timer(const Duration(seconds: 2), _fetchCurrentRoute);
  }

  LatLng? _currentRouteDestination() {
    final me = _myConvoyStatus;
    if (me == null) return null;
    return switch (me.journeyState) {
      ConvoyJourneyState.assigned ||
      ConvoyJourneyState.enRoutePickup ||
      ConvoyJourneyState.atPickup => _pickupLatLng(),
      ConvoyJourneyState.boarded ||
      ConvoyJourneyState.enRouteStop ||
      ConvoyJourneyState.atStop => _currentSpotLatLng(),
      ConvoyJourneyState.stopDone =>
        _allItineraryItemsCompleted ? null : _currentSpotLatLng(),
      ConvoyJourneyState.enRouteDropoff ||
      ConvoyJourneyState.atDropoff => _dropoffLatLng(),
      ConvoyJourneyState.completed => null,
    };
  }

  Future<void> _fetchCurrentRoute() async {
    if (_activity == null) return;
    final destination = _currentRouteDestination();
    if (destination == null) {
      if (mounted) {
        setState(() {
          _polylines = {};
          _eta = null;
        });
      }
      return;
    }

    final origins = <String, LatLng>{
      for (final driver in _convoy)
        if (_liveMarkerPositions[driver.driverId] != null ||
            (driver.latitude != null && driver.longitude != null))
          driver.driverId:
              _liveMarkerPositions[driver.driverId] ??
              LatLng(driver.latitude!, driver.longitude!),
    };
    final myId = _repo.currentUserId ?? 'self';
    final myPosition = _liveMarkerPositions[myId] ?? _driverLatLng();
    if (myPosition != null) origins[myId] = myPosition;
    if (origins.isEmpty) return;

    final generation = ++_routeLoadGeneration;
    final results = await Future.wait(
      origins.entries.map((entry) async {
        try {
          final route = await _routeService.fetchRoute(
            entry.value,
            destination,
          );
          return (driverId: entry.key, route: route);
        } catch (error) {
          debugPrint('[Routes] driver=${entry.key} route failed: $error');
          return null;
        }
      }),
    );
    if (!mounted || generation != _routeLoadGeneration) return;

    final lines = <Polyline>{};
    String? myEta;
    for (final result in results) {
      if (result == null) continue;
      final isMe = result.driverId == myId;
      lines.add(
        Polyline(
          polylineId: PolylineId('driver_route_${result.driverId}'),
          points: result.route.points,
          color: isMe ? _primary : const Color(0xFF7C3AED),
          width: isMe ? 6 : 4,
          geodesic: true,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: isMe ? 2 : 1,
        ),
      );
      if (isMe || myEta == null) myEta = result.route.durationText;
    }

    setState(() {
      _polylines = lines;
      _eta = myEta;
    });
  }

  LatLng? _driverLatLng() {
    final simulated = _simulatedDriverLocation;
    if (simulated != null) return simulated;

    final position = _currentPosition;

    if (position != null) {
      return LatLng(position.latitude, position.longitude);
    }

    final me = _myConvoyStatus;
    if (me?.latitude == null || me?.longitude == null) return null;
    return LatLng(me!.latitude!, me.longitude!);
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

  void _fitConvoyBounds() {
    final points = <LatLng>[];

    // Add every convoy driver's latest position.
    for (final driver in _convoy) {
      if (driver.latitude != null && driver.longitude != null) {
        points.add(LatLng(driver.latitude!, driver.longitude!));
      }
    }

    // Ensure our own freshest position is included.
    final ownPosition = _driverLatLng();

    if (ownPosition != null &&
        !points.any(
          (point) =>
              point.latitude == ownPosition.latitude &&
              point.longitude == ownPosition.longitude,
        )) {
      points.add(ownPosition);
    }

    if (points.isEmpty) {
      _showSnack('Convoy locations are not available yet.');
      return;
    }

    if (points.length == 1) {
      setState(() {
        _isFollowingDriver = false;
      });

      _isProgrammaticMove = true;

      _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(points.first, 16));

      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;

    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);

      maxLat = math.max(maxLat, point.latitude);

      minLng = math.min(minLng, point.longitude);

      maxLng = math.max(maxLng, point.longitude);
    }

    setState(() {
      _isFollowingDriver = false;
    });

    _isProgrammaticMove = true;

    _mapCtrl?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        70,
      ),
    );
  }
  // =========================================================================
  // ACTION WRAPPER
  // =========================================================================

  Future<void> _syncServerTestModeState() async {
    if (!kDebugMode || _bookingId.isEmpty) return;

    var enabled = false;
    try {
      enabled = await _repo.fetchDeveloperTestBookingMode(_bookingId);
    } catch (error) {
      debugPrint(
        '[TEST MODE] booking_id=$_bookingId action=refresh '
        'server_state_error=$error',
      );
    }

    if (mounted && enabled != _serverTestModeEnabled) {
      setState(() => _serverTestModeEnabled = enabled);
    }
  }

  Future<void> _doAction(Future<void> Function() action) async {
    if (_actionBusy) {
      return;
    }

    setState(() {
      _actionBusy = true;
    });

    try {
      await _syncServerTestModeState();
      await action();
    } catch (e) {
      if (mounted) {
        _showSnack(_actionErrorMessage(e), error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  String _actionErrorMessage(Object error) {
    final raw = error.toString();
    if (kDebugMode && _bypassTransactionValidation) {
      if (raw.contains('TEST_BOOKING_NOT_REGISTERED')) {
        return 'Server-side Testing Mode is not active for this booking. Re-enable Testing Mode in Developer Tools, then retry.';
      }
      if (raw.contains('NOT_TEST_BOOKING_DRIVER') ||
          raw.contains('NOT_ASSIGNED_DRIVER') ||
          raw.contains('NOT_IN_CONVOY')) {
        return 'Testing Mode can only advance the real driver assignment signed in on this device.';
      }
      if (raw.contains('CANCELLED_BOOKING_CANNOT_ADVANCE')) {
        return 'A cancelled test booking cannot be advanced. Use another disposable booking.';
      }
      if (raw.contains('debug_') &&
          (raw.contains('PGRST202') || raw.contains('not found'))) {
        return 'The server-side Testing Mode migration is missing. Apply the pending Supabase migrations and retry.';
      }
    }
    return 'Unable to update the trip. Please retry. ($error)';
  }

  // =========================================================================
  // TOUR ACTIONS — CONVOY JOURNEY STATE
  // =========================================================================

  Future<void> _markEnRoutePickup() => _doAction(() async {
    final advanced = await _advanceConvoyStateCore(
      ConvoyJourneyState.enRoutePickup,
    );
    if (!advanced) return;

    _logStatus('driver_en_route');
    _showSnack('Status: En route to pickup.');
  });

  Future<void> _markBoarded() => _doAction(() async {
    // Arrival was already verified by the server. Boarding is a human
    // confirmation and must also work after an approved GPS fallback.
    final advanced = await _advanceConvoyStateCore(ConvoyJourneyState.boarded);

    if (!advanced) return;

    _logStatus('boarded');

    final blockers = _myConvoyStatus == null
        ? const <ConvoyDriverSnapshot>[]
        : _blockingDriversFor(_myConvoyStatus!);

    _showSnack(
      blockers.isEmpty
          ? 'Passengers boarded. The convoy is ready to depart.'
          : 'Passengers boarded. Waiting for the rest of the convoy.',
    );
  });

  Future<void> _departPickup() => _doAction(() async {
    final target = _spots.isEmpty
        ? ConvoyJourneyState.enRouteDropoff
        : ConvoyJourneyState.enRouteStop;

    final advanced = await _advanceConvoyStateCore(target);
    if (!advanced) return;

    final firstItem = _spots.isEmpty ? null : _spots.first;

    if (_bookingId.isNotEmpty && firstItem != null) {
      await _repo.markSpotTravelling(
        bookingId: _bookingId,
        itineraryItemId: firstItem.id.toString(),
      );
    }

    _logStatus(_spots.isEmpty ? 'en_route_to_dropoff' : 'picked_up');

    _showSnack(
      _spots.isEmpty
          ? 'Convoy departing pickup for drop-off.'
          : 'Convoy departing pickup for the first tour stop.',
    );
  });

  Future<void> _markStopDone() => _doAction(() async {
    final currentItem = _currentItineraryItem;
    if (currentItem == null) {
      await Future.wait([
        _loadConvoy(),
        _refreshTrackingState(logTag: 'spot-already-completed'),
      ]);
      _showSnack(
        'This shared stop was already completed. Convoy progress is now synchronized.',
      );
      return;
    }

    final spotName = currentItem.destinationName;
    final itemId = currentItem.id?.toString() ?? '';

    if (itemId.isEmpty || itemId == 'null') {
      _showSnack(
        'Cannot complete spot: item ID is missing. Try refreshing.',
        error: true,
      );
      await _refreshTrackingState(logTag: 'spot-complete-no-id');
      return;
    }

    late final Map<String, dynamic> rpcResult;
    try {
      rpcResult = await _repo.completeCurrentItineraryItem(
        widget.activityId,
        bookingId: _bookingId,
        itineraryItemId: itemId,
      );
    } on PostgrestException catch (error) {
      await _refreshTrackingState(logTag: 'spot-complete-error');
      if (error.message.contains('BARRIER_NOT_MET')) {
        _showSnack('Waiting for every convoy driver to arrive at this stop.');
      } else if (error.message.contains('STALE_ITINERARY_STOP')) {
        _showSnack('The shared stop already advanced. Progress synchronized.');
      } else {
        _showSnack(
          'Unable to complete this stop: ${error.message}',
          error: true,
        );
      }
      return;
    }

    _debugTourState('spot-complete-rpc', rpcResult: rpcResult);

    await Future.wait([
      _loadConvoy(),
      _refreshTrackingState(logTag: 'shared-stop-completed'),
    ]);

    if (rpcResult['driver_ready'] == true) {
      _showSnack(
        'Your passengers are ready. Waiting for the rest of the convoy.',
      );
      return;
    }
    final completedNow = (rpcResult['completed_items'] as num?)?.toInt() ?? 0;
    final rpcTotal =
        (rpcResult['total_items'] as num?)?.toInt() ?? _spots.length;
    final allCompletedNow = completedNow >= rpcTotal && rpcTotal > 0;
    final alreadyCompleted = rpcResult['already_completed'] == true;

    if (allCompletedNow) {
      _showSnack(
        alreadyCompleted
            ? 'The final shared stop was already complete. Convoy progress synchronized.'
            : rpcResult['awaiting_remaining_payment'] == true
            ? 'All $rpcTotal spots are complete. Waiting for remaining payment before drop-off.'
            : 'All $rpcTotal spots are complete. The convoy may continue to drop-off.',
      );
    } else {
      final nextItem = _spots
          .where((spot) => spot.spotStatus.trim().toLowerCase() != 'completed')
          .firstOrNull;

      _showSnack(
        '${alreadyCompleted ? '$spotName was already completed.' : '$spotName completed.'} '
        '$completedNow of $rpcTotal spots done.'
        '${nextItem != null ? ' Next: ${nextItem.destinationName}' : ''} '
        'Convoy progress synchronized.',
      );
    }
  });

  Future<void> _departStop() => _doAction(() async {
    final hasMoreStops = !_allItineraryItemsCompleted;

    final target = hasMoreStops
        ? ConvoyJourneyState.enRouteStop
        : ConvoyJourneyState.enRouteDropoff;

    final advanced = await _advanceConvoyStateCore(target);
    if (!advanced) return;

    final nextItem = _currentItineraryItem;

    if (_bookingId.isNotEmpty && hasMoreStops && nextItem != null) {
      await _repo.markSpotTravelling(
        bookingId: _bookingId,
        itineraryItemId: nextItem.id.toString(),
      );
    }

    _logStatus(hasMoreStops ? 'en_route_to_spot' : 'en_route_to_dropoff');

    _showSnack(
      hasMoreStops
          ? 'Convoy departing to the next stop.'
          : 'Convoy departing to drop-off.',
    );
  });

  Future<void> _completeTour() => _doAction(() async {
    if (!_bypassTransactionValidation && !_hasConfirmedRemainingBalance) {
      _showSnack(
        'Confirm the remaining balance before completing the tour.',
        error: true,
      );
      return;
    }
    if (!_allItineraryItemsCompleted) {
      _showSnack(
        'Complete all itinerary spots before finishing the tour.',
        error: true,
      );
      return;
    }

    final advanced = await _advanceConvoyStateCore(
      ConvoyJourneyState.completed,
    );
    if (!advanced) return;

    try {
      final completion = await _repo.completePackageActivity(
        widget.activityId,
        bookingId: _bookingId,
      );
      if (completion['overall_completed'] != true) {
        await _refreshTrackingState(logTag: 'convoy-completion-pending');
        _showSnack(
          completion['awaiting_final_payment'] == true
              ? 'Assignment completed. The tour is finished and awaiting final payment.'
              : 'Assignment completed. Waiting for the rest of the convoy.',
        );
        return;
      }
    } on PostgrestException catch (e) {
      if (e.message.contains('REMAINING_BALANCE_UNPAID') ||
          e.message.contains('REMAINING_BALANCE_NOT_CONFIRMED')) {
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

  bool get _hasConfirmedRemainingBalance =>
      (_booking?.remainingBalance ?? 0) <= 0 ||
      _paymentRecords.any(
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

  Future<void> _confirmCashShare(_PendingCashShare item) async {
    try {
      await _repo.confirmGroupCashShare(item.record.id as String);
      await _repo.notifyUser(
        userId: item.record.payerId,
        title: 'Cash received',
        body:
            'A driver confirmed receiving ₱${item.allocation.driverAmount.toStringAsFixed(2)} of the remaining balance.',
        type: 'cash_payment_confirmed',
      );
      _showSnack('Cash receipt confirmed.');
      await _refreshTrackingState(logTag: 'cash-share-confirmed');
    } catch (e) {
      _showSnack('Unable to confirm cash receipt: $e', error: true);
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
    final simulated = _simulatedDriverLocation;

    _repo
        .logTripStatus(
          activityId: widget.activityId,
          bookingId: activity.bookingId,
          status: status,
          spotIndex: spotIndex,
          latitude: simulated?.latitude ?? position?.latitude,
          longitude: simulated?.longitude ?? position?.longitude,
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

    try {
      final conversation = _bookingId.isNotEmpty
          ? await _repo.ensureBookingGroupConversation(_bookingId)
          : await _repo.getOrCreateConversation(
              touristId: touristId,
              driverId: _repo.requireUserId(),
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
            driverName: _bookingId.isNotEmpty && _convoy.length > 1
                ? 'Booking Group (${_convoy.length + 1})'
                : touristName.isNotEmpty
                ? touristName
                : 'Tourist',
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

  Future<void> _callConvoyDriver(ConvoyDriverSnapshot driver) async {
    final phone = driver.phoneNumber.trim();

    if (phone.isEmpty) {
      _showSnack(
        '${driver.driverName}\'s phone number is not available.',
        error: true,
      );

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
    final me = _myConvoyStatus;

    if (me == null) {
      return null;
    }

    final progressRequest = _stageProgressRequestFor(me);
    final progress = _convoyProgress;
    if (progress == null ||
        !progress.matches(progressRequest.stage, progressRequest.stopIndex)) {
      return null;
    }

    final blockingDrivers = _blockingDriversFor(me);

    // At synchronized barrier states, the waiting card is the action UI until
    // every required convoy driver is ready. The server still re-validates the
    // barrier when the action is eventually pressed.
    if (blockingDrivers.isNotEmpty) {
      return null;
    }

    if (_serverGateNotice != null) {
      return null;
    }

    switch (me.journeyState) {
      case ConvoyJourneyState.assigned:
        return _PrimaryTourAction(
          label: _testActionLabel('Start Navigation to Pickup'),
          description: 'Begin heading to the tourist pickup location.',
          icon: Icons.navigation_rounded,
          onTap: _markEnRoutePickup,
        );

      case ConvoyJourneyState.enRoutePickup:
        return null;

      case ConvoyJourneyState.atPickup:
        return _PrimaryTourAction(
          label: _testActionLabel('Tourist Picked Up'),
          description: 'Confirm that your assigned passengers are onboard.',
          icon: Icons.groups_rounded,
          onTap: _markBoarded,
        );

      case ConvoyJourneyState.boarded:
        return null;

      case ConvoyJourneyState.enRouteStop:
        return null;

      case ConvoyJourneyState.atStop:
        if (!_bypassTransactionValidation && _stayRemaining > Duration.zero) {
          return null;
        }
        return _PrimaryTourAction(
          label: _testActionLabel(
            me.currentStopIndex >= _spots.length - 1
                ? 'Finish Tour Stops'
                : 'Proceed to Next Stop',
          ),
          description:
              'Confirm your passengers are ready. Departure waits for the convoy.',
          icon: Icons.route_rounded,
          onTap: _markStopDone,
        );

      case ConvoyJourneyState.stopDone:
        return null;

      case ConvoyJourneyState.enRouteDropoff:
        return null;

      case ConvoyJourneyState.atDropoff:
        return _PrimaryTourAction(
          label: _testActionLabel('Tourist Dropped Off'),
          description: 'Confirm your assigned passengers have safely alighted.',
          icon: Icons.task_alt_rounded,
          onTap: _completeTour,
        );

      case ConvoyJourneyState.completed:
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
        child: Column(
          children: [
            if (kDebugMode)
              AnimatedBuilder(
                animation: DeveloperSettings.instance,
                builder: (context, _) => _configuredTestMode
                    ? const _DriverTestModeActiveBanner()
                    : const SizedBox.shrink(),
              ),
            Expanded(
              child: _loading
                  ? const _TrackingLoadingView()
                  : _error != null
                  ? _buildError()
                  : _buildContent(),
            ),
          ],
        ),
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

    final assignmentCompleted =
        _myConvoyStatus?.journeyState == ConvoyJourneyState.completed;
    final bookingCompleted =
        (_booking?.bookingStatus ?? '').toLowerCase() == 'completed' &&
        status == 'completed';
    final awaitingFinalPayment =
        (_booking?.bookingStatus ?? '').toLowerCase() ==
        'awaiting_final_payment';
    final awaitingRemainingPayment =
        (_booking?.bookingStatus ?? '').toLowerCase() ==
            'awaiting_remaining_payment' ||
        status == 'awaiting_remaining_payment';
    final completedDriverCount = _convoy
        .where((driver) => driver.journeyState == ConvoyJourneyState.completed)
        .length;

    final currentDriverId = _repo.currentUserId ?? '';
    final pendingPayments = _paymentRecords
        .where(
          (record) =>
              record.status == 'pending_confirmation' &&
              record.provider == 'manual' &&
              record.payeeId == currentDriverId,
        )
        .toList();
    final pendingCashShares = <_PendingCashShare>[];
    for (final allocation in _paymentAllocations.where(
      (item) => item.driverId == currentDriverId && item.isAwaitingCash,
    )) {
      final record = _paymentRecords
          .where((item) => item.id?.toString() == allocation.paymentRecordId)
          .firstOrNull;
      if (record != null && record.isGroupCash && record.isPending) {
        pendingCashShares.add(
          _PendingCashShare(record: record, allocation: allocation),
        );
      }
    }
    final remainingPayment = _paymentRecords
        .where(
          (record) =>
              record.paymentStage == 'remaining_balance' &&
              record.status != 'cancelled',
        )
        .firstOrNull;
    final remainingAllocations = remainingPayment == null
        ? const <PaymentAllocation>[]
        : _paymentAllocations
              .where(
                (allocation) =>
                    allocation.paymentRecordId ==
                    remainingPayment.id?.toString(),
              )
              .toList(growable: false);
    final confirmedCashCount = remainingAllocations
        .where((allocation) => allocation.isCashConfirmed)
        .length;
    final paymentGateMessage =
        remainingPayment?.isGroupCash == true && remainingAllocations.isNotEmpty
        ? 'Cash confirmation: $confirmedCashCount of ${remainingAllocations.length} drivers confirmed. Drop-off stays locked until everyone confirms.'
        : remainingPayment?.isPayMongo == true
        ? 'Waiting for secure GCash payment confirmation. Drop-off unlocks automatically after the webhook confirms payment.'
        : 'Itinerary completed. Waiting for remaining payment; drop-off unlocks after payment confirmation.';

    final primaryAction = _currentPrimaryAction();
    final serverGateNotice = _serverGateNotice;

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
                if (_booking != null && !_isBookingClosed)
                  LiveItineraryEstimates(
                    booking: _booking!,
                    drivers: _convoy,
                    stops: _spots,
                    onlyDriverId: _repo.currentUserId,
                  ),
                _buildJourneyAutomationNotice(),
                const SizedBox(height: 10),
                _ModernStatusCard(
                  status: status,
                  completedCount: _completedItineraryItemsCount,
                  totalCount: _spots.length,
                ),

                const SizedBox(height: 12),

                if (awaitingRemainingPayment) ...[
                  _ServerGateNotice(message: paymentGateMessage),
                  const SizedBox(height: 12),
                ] else if (awaitingFinalPayment) ...[
                  _ServerGateNotice(
                    message:
                        'Tour finished. Your assignment is complete; the booking is awaiting confirmed final payment.',
                  ),
                  const SizedBox(height: 12),
                ] else if (assignmentCompleted && !bookingCompleted) ...[
                  _ServerGateNotice(
                    message:
                        'Assignment completed. $completedDriverCount of ${_convoy.length} convoy drivers are finished.',
                  ),
                  const SizedBox(height: 12),
                ],

                if (serverGateNotice != null) ...[
                  _ServerGateNotice(message: serverGateNotice),
                  const SizedBox(height: 12),
                ],

                // Convoy information only becomes visually substantial
                // for multi-driver bookings.
                if (_convoy.length > 1 ||
                    _convoyLoading ||
                    _convoyError != null) ...[
                  _buildConvoyOverview(),
                  const SizedBox(height: 12),
                ],

                _NavigationMapCard(
                  markers: _markers,
                  polylines: _polylines,
                  initialTarget:
                      _driverLatLng() ?? _pickupLatLng() ?? _defaultCenter,
                  isFollowing: _isFollowingDriver,
                  showConvoyControl: _convoy.length > 1,
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
                  onConvoyTap: _fitConvoyBounds,
                ),
                const SizedBox(height: 14),
                if (!assignmentCompleted && _spots.isNotEmpty)
                  _CurrentDestinationCard(
                    currentItem: _currentItineraryItem,
                    completedCount: _completedItineraryItemsCount,
                    totalCount: _spots.length,
                    eta: _eta,
                    status: status,
                  ),
                if (!assignmentCompleted && _spots.isNotEmpty)
                  const SizedBox(height: 14),
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
                _ModernLocationsCard(
                  booking: _booking,
                  activity: _activity,
                  status: status,
                ),
                const SizedBox(height: 14),
                _ModernBookingCard(
                  booking: _booking,
                  activity: activity,
                  remainingBalanceSettled: _hasConfirmedRemainingBalance,
                ),
                if (pendingPayments.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ModernPaymentsCard(
                    records: pendingPayments,
                    onConfirm: _confirmPayment,
                    onDispute: _disputePayment,
                  ),
                ],
                if (pendingCashShares.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _CashReceiptConfirmationCard(
                    shares: pendingCashShares,
                    onConfirm: _confirmCashShare,
                  ),
                ],
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
        _PersistentDriverActionBar(
          completed: assignmentCompleted,
          bookingCompleted: bookingCompleted,
          awaitingFinalPayment: awaitingFinalPayment,
          completedDriverCount: completedDriverCount,
          totalDriverCount: _convoy.length,
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
    required this.showConvoyControl,
    required this.status,
    required this.onMapCreated,
    required this.onCameraMoveStarted,
    required this.onCameraIdle,
    required this.onPickupTap,
    required this.onDriverTap,
    required this.onConvoyTap,
  });

  final Set<Marker> markers;
  final Set<Polyline> polylines;

  final LatLng initialTarget;

  final bool isFollowing;
  final bool showConvoyControl;
  final String status;

  final ValueChanged<GoogleMapController> onMapCreated;

  final VoidCallback onCameraMoveStarted;

  final VoidCallback onCameraIdle;
  final VoidCallback onPickupTap;
  final VoidCallback onDriverTap;
  final VoidCallback onConvoyTap;

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
                  if (showConvoyControl) ...[
                    _MapRoundButton(
                      icon: Icons.groups_2_outlined,
                      tooltip: 'Show entire convoy',
                      color: const Color(0xFF7C3AED),
                      onTap: onConvoyTap,
                    ),
                    const SizedBox(height: 8),
                  ],
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
              child: _MapLegendBar(
                status: status,
                showConvoy: showConvoyControl,
              ),
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
  const _MapLegendBar({required this.status, required this.showConvoy});

  final String status;
  final bool showConvoy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _LegendItem(color: _primary, text: 'You'),
          if (showConvoy) ...[
            const SizedBox(width: 10),
            const _LegendItem(color: Color(0xFF7C3AED), text: 'Convoy'),
          ],
          const SizedBox(width: 10),
          const _LegendItem(color: Color(0xFFF59E0B), text: 'Current'),
          const SizedBox(width: 10),
          const Flexible(
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
                        text:
                            'Planned: ${_buildScheduleLabel(spot.arrivalTime, spot.departureTime)}',
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
                    label: 'First convoy arrival',
                    time: timeFormat.format(spot.actualArrivalTime!.toLocal()),
                    color: _primary,
                  ),
                ],
                if (spot.actualDepartureTime != null) ...[
                  const SizedBox(height: 4),
                  _ActualTimeBadge(
                    icon: Icons.check_circle_rounded,
                    label: 'Actual departure',
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
  const _ModernLocationsCard({
    required this.booking,
    required this.activity,
    required this.status,
  });

  final PackageBooking? booking;
  final PackageActivity? activity;
  final String status;

  String _time(DateTime value) =>
      DateFormat('MMM d, h:mm a').format(value.toLocal());

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
              status: [
                if (booking?.scheduledStartAt != null)
                  'Scheduled ${_time(booking!.scheduledStartAt!)}',
                if (booking?.arrivedAt != null || activity?.arrivedAt != null)
                  'Arrived ${_time((booking?.arrivedAt ?? activity!.arrivedAt)!)}',
                if (booking?.pickedUpAt != null || activity?.pickedUpAt != null)
                  'Picked up ${_time((booking?.pickedUpAt ?? activity!.pickedUpAt)!)}',
              ].join(' • '),
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
              status: activity?.droppedOffAt != null
                  ? 'Dropped off ${_time(activity!.droppedOffAt!)}'
                  : booking?.estimatedEndAt != null
                  ? 'Estimated ${_time(booking!.estimatedEndAt!)}'
                  : 'Final destination',
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
  const _ModernBookingCard({
    required this.booking,
    required this.activity,
    required this.remainingBalanceSettled,
  });

  final PackageBooking? booking;
  final PackageActivity activity;
  final bool remainingBalanceSettled;

  @override
  Widget build(BuildContext context) {
    final b = booking;

    final adults = b?.adults ?? 1;

    final children = b?.children ?? 0;

    final travelDate = b?.travelDate;

    final scheduledStart = b?.scheduledStartAt?.toLocal();

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
            label: 'Pickup Schedule',
            value: scheduledStart != null
                ? DateFormat('MMMM d, yyyy • h:mm a').format(scheduledStart)
                : travelDate != null
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
              value: remaining > 0 && !remainingBalanceSettled
                  ? '₱${remaining.toStringAsFixed(2)}'
                  : 'Settled',
              valueColor: remaining > 0 && !remainingBalanceSettled
                  ? _warning
                  : _success,
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

class _PendingCashShare {
  const _PendingCashShare({required this.record, required this.allocation});

  final PaymentRecord record;
  final PaymentAllocation allocation;
}

class _CashReceiptConfirmationCard extends StatelessWidget {
  const _CashReceiptConfirmationCard({
    required this.shares,
    required this.onConfirm,
  });

  final List<_PendingCashShare> shares;
  final ValueChanged<_PendingCashShare> onConfirm;

  @override
  Widget build(BuildContext context) {
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
          const Text(
            'Cash Receipt Confirmation',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Confirm only after you physically receive your allocated share.',
            style: TextStyle(
              color: _subtle,
              fontWeight: FontWeight.w600,
              fontSize: 9.5,
            ),
          ),
          const SizedBox(height: 12),
          ...shares.map(
            (item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _warningSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '₱${item.allocation.driverAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        const Text(
                          'Your remaining-balance cash share',
                          style: TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => onConfirm(item),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: _success,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Confirm Cash Received',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
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

class _DriverTestModeActiveBanner extends StatelessWidget {
  const _DriverTestModeActiveBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFB91C1C),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Text(
        'TEST MODE ACTIVE • OPERATIONAL CONSTRAINTS BYPASSED',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ============================================================================
// PERSISTENT ACTION BAR
// ============================================================================

class _ServerGateNotice extends StatelessWidget {
  const _ServerGateNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _warningSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: _warning, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w800,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersistentDriverActionBar extends StatelessWidget {
  const _PersistentDriverActionBar({
    required this.completed,
    required this.bookingCompleted,
    required this.awaitingFinalPayment,
    required this.completedDriverCount,
    required this.totalDriverCount,
    required this.busy,
    required this.action,
  });

  final bool completed;
  final bool bookingCompleted;
  final bool awaitingFinalPayment;
  final int completedDriverCount;
  final int totalDriverCount;
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: _success,
                    size: 19,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    bookingCompleted
                        ? 'TOUR COMPLETED'
                        : awaitingFinalPayment
                        ? 'ASSIGNMENT COMPLETED • AWAITING FINAL PAYMENT'
                        : 'ASSIGNMENT COMPLETED • $completedDriverCount OF $totalDriverCount DRIVERS',
                    style: const TextStyle(
                      color: Color(0xFF166534),
                      fontWeight: FontWeight.w900,
                      fontSize: 10.5,
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

    case 'awaiting_remaining_payment':
      return const _StatusVisual(
        badge: 'PAYMENT REQUIRED',
        title: 'Waiting for remaining payment',
        description:
            'The itinerary is complete. Drop-off unlocks after payment confirmation.',
        icon: Icons.payments_outlined,
        gradientStart: Color(0xFFD97706),
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
