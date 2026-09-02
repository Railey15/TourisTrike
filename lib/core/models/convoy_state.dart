/// Single source of truth for per-driver convoy journey state.
///
/// Mirrors `booking_drivers.journey_state` exactly — see the CHECK
/// constraint in
/// supabase/migrations/20260805000000_convoy_phase0_data_model.sql.
/// If you add/rename a state, update BOTH places.
///
/// Pipeline: assigned -> enRoutePickup -> atPickup -> boarded
///   -> [per itinerary stop: enRouteStop -> atStop -> stopDone]
///   -> enRouteDropoff -> atDropoff -> completed
///
/// `boarded` and `stopDone` are reached by independent, per-driver
/// actions (each driver marks their own passengers ready). Leaving
/// `boarded`/`stopDone` for the NEXT `enRoute*` state is the barrier —
/// gated on every driver in the convoy reaching that point first. See
/// ConvoyBarrierService for the gating logic itself; this file only
/// defines the state values and their linear order.
enum ConvoyJourneyState {
  assigned,
  enRoutePickup,
  atPickup,
  boarded,
  enRouteStop,
  atStop,
  stopDone,
  enRouteDropoff,
  atDropoff,
  completed;

  String get dbValue => switch (this) {
    ConvoyJourneyState.assigned => 'assigned',
    ConvoyJourneyState.enRoutePickup => 'en_route_pickup',
    ConvoyJourneyState.atPickup => 'at_pickup',
    ConvoyJourneyState.boarded => 'boarded',
    ConvoyJourneyState.enRouteStop => 'en_route_stop',
    ConvoyJourneyState.atStop => 'at_stop',
    ConvoyJourneyState.stopDone => 'stop_done',
    ConvoyJourneyState.enRouteDropoff => 'en_route_dropoff',
    ConvoyJourneyState.atDropoff => 'at_dropoff',
    ConvoyJourneyState.completed => 'completed',
  };

  /// Rider-facing label. Centralized here so no UI file hardcodes these
  /// strings — see CODE HYGIENE rule 1 in the convoy refactor brief.
  String get label => switch (this) {
    ConvoyJourneyState.assigned => 'Assigned',
    ConvoyJourneyState.enRoutePickup => 'En Route to Pickup',
    ConvoyJourneyState.atPickup => 'At Pickup',
    ConvoyJourneyState.boarded => 'Passengers Boarded',
    ConvoyJourneyState.enRouteStop => 'En Route to Stop',
    ConvoyJourneyState.atStop => 'At Stop',
    ConvoyJourneyState.stopDone => 'Stop Complete',
    ConvoyJourneyState.enRouteDropoff => 'En Route to Drop-off',
    ConvoyJourneyState.atDropoff => 'At Drop-off',
    ConvoyJourneyState.completed => 'Completed',
  };

  /// Legacy `package_activities.tour_status` / `driver_package_tracking_
  /// screen.dart` vocabulary equivalent — used ONLY for the backward-
  /// compatible mirror write so pre-convoy readers (tourist screen,
  /// subtenant dashboard, driver home earnings, guest trip link — see
  /// the Phase 2b chat report for the full reader list) keep working
  /// until they're migrated in Phase 3/4. Must mirror the `case` in the
  /// `advance_driver_journey_state` SQL RPC
  /// (supabase/migrations/20260805020000_convoy_phase2b_advance_state_rpc.sql)
  /// — keep both in sync.
  String get legacyTourStatus => switch (this) {
    ConvoyJourneyState.assigned => 'driver_accepted',
    ConvoyJourneyState.enRoutePickup => 'driver_en_route',
    ConvoyJourneyState.atPickup => 'driver_arrived',
    ConvoyJourneyState.boarded => 'picked_up',
    ConvoyJourneyState.enRouteStop => 'en_route_to_spot',
    ConvoyJourneyState.atStop => 'at_spot',
    ConvoyJourneyState.stopDone => 'on_tour',
    ConvoyJourneyState.enRouteDropoff => 'en_route_to_dropoff',
    ConvoyJourneyState.atDropoff => 'ready_to_complete',
    ConvoyJourneyState.completed => 'completed',
  };

  /// Parses a `booking_drivers.journey_state` value. Falls back to
  /// [assigned] for null/unrecognized input instead of throwing — this
  /// is a display-layer parse, never a source of a null-check crash.
  static ConvoyJourneyState fromDb(String? value) => switch (value) {
    'assigned' => ConvoyJourneyState.assigned,
    'en_route_pickup' => ConvoyJourneyState.enRoutePickup,
    'at_pickup' => ConvoyJourneyState.atPickup,
    'boarded' => ConvoyJourneyState.boarded,
    'en_route_stop' => ConvoyJourneyState.enRouteStop,
    'at_stop' => ConvoyJourneyState.atStop,
    'stop_done' => ConvoyJourneyState.stopDone,
    'en_route_dropoff' => ConvoyJourneyState.enRouteDropoff,
    'at_dropoff' => ConvoyJourneyState.atDropoff,
    'completed' => ConvoyJourneyState.completed,
    _ => ConvoyJourneyState.assigned,
  };

  /// Linear pipeline order (enum declaration order). Safe for
  /// [isAtLeast] comparisons anywhere in the pipeline EXCEPT within the
  /// repeating stop loop (enRouteStop/atStop/stopDone recur per stop) —
  /// there, ConvoyBarrierService also checks `currentStopIndex` before
  /// trusting this ordering.
  int get order => index;

  bool isAtLeast(ConvoyJourneyState other) => order >= other.order;
}

/// Minimal, Supabase-agnostic snapshot of one driver's convoy position —
/// the input shape ConvoyBarrierService operates on. Deliberately not a
/// `TourisTrikeRow` wrapper (unlike PackageActivity/BookingItineraryItem)
/// so the barrier logic stays pure and unit-testable without constructing
/// fake Supabase rows. The repository layer maps real rows into this.
class ConvoyDriverSnapshot {
  const ConvoyDriverSnapshot({
    required this.driverId,
    required this.driverName,
    required this.plateNumber,
    required this.journeyState,
    required this.currentStopIndex,
    required this.stateUpdatedAt,
    this.assignmentStatus = 'accepted',
    this.lastLocationAt,
    this.phoneNumber = '',
    this.avatarUrl = '',
    this.latitude,
    this.longitude,
    this.heading = 0,
    this.todaName = '',
    this.rating = 0,
    this.assignedPassengers = 0,
  });

  final String driverId;
  final String driverName;
  final String plateNumber;
  final ConvoyJourneyState journeyState;
  final int currentStopIndex;

  /// When [journeyState] last changed — drives the deadlock timers.
  final DateTime stateUpdatedAt;

  /// Roster membership state from `booking_drivers.status`. Completed
  /// assignments remain convoy members and satisfy every earlier gate.
  final String assignmentStatus;

  bool get isAssignmentCompleted =>
      assignmentStatus == 'completed' ||
      journeyState == ConvoyJourneyState.completed;

  /// Latest `driver_live_locations.updated_at` for this driver, if any —
  /// drives offline detection. Null means no location ping has ever been
  /// recorded for this driver on this booking.
  final DateTime? lastLocationAt;

  final String phoneNumber;
  final String avatarUrl;

  /// Last known position (from driver_live_locations) — null until that
  /// driver's GPS stream has posted at least once. Used for the "show
  /// every tricycle in the convoy" map requirement (Phase 2c).
  final double? latitude;
  final double? longitude;
  final double heading;

  final String todaName;
  final double rating;

  /// This driver's share of the booking's total passengers — auto-split
  /// floor-division-plus-remainder-to-the-first-accepted-driver, computed
  /// server-side once the group is fully accepted (see
  /// compute_passenger_split in the Phase 0 migration, wired into
  /// accept_package_booking in the Phase 3 migration).
  final int assignedPassengers;
}

/// Authoritative aggregate returned by `get_convoy_stage_progress`.
class ConvoyStageProgress {
  const ConvoyStageProgress({
    required this.stage,
    required this.stopIndex,
    required this.requiredDriverCount,
    required this.satisfiedDriverCount,
    required this.allSatisfied,
    required this.waitingDriverIds,
    required this.driverStates,
  });

  factory ConvoyStageProgress.fromJson(Map<String, dynamic> json) {
    final waiting = json['waiting_driver_ids'];
    final states = json['driver_states'];
    return ConvoyStageProgress(
      stage: json['stage']?.toString() ?? '',
      stopIndex: (json['stop_index'] as num?)?.toInt(),
      requiredDriverCount:
          (json['required_driver_count'] as num?)?.toInt() ?? 0,
      satisfiedDriverCount:
          (json['satisfied_driver_count'] as num?)?.toInt() ?? 0,
      allSatisfied: json['all_satisfied'] == true,
      waitingDriverIds: waiting is List
          ? waiting.map((id) => id.toString()).toList(growable: false)
          : const [],
      driverStates: states is List
          ? states
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList(growable: false)
          : const [],
    );
  }

  final String stage;
  final int? stopIndex;
  final int requiredDriverCount;
  final int satisfiedDriverCount;
  final bool allSatisfied;
  final List<String> waitingDriverIds;
  final List<Map<String, dynamic>> driverStates;

  bool matches(String expectedStage, int? expectedStopIndex) =>
      stage == expectedStage &&
      (stage != 'at_stop' && stage != 'stop_done' ||
          stopIndex == expectedStopIndex);
}

/// Shared callback shape for the convoy widgets' contact buttons
/// (ConvoyRosterStrip, ConvoyTouristDriverList) — defined once here so
/// both widget files agree on it without importing each other.
typedef ConvoyContactCallback = void Function(ConvoyDriverSnapshot driver);

/// Thrown by `TourisTrikeRepository.advanceDriverJourneyState` when the
/// server rejects a transition because the barrier isn't satisfied yet.
/// Kept distinct from other errors so the UI can show the waiting card
/// instead of a generic error snackbar — see driver_package_tracking_
/// screen.dart's handling of this type.
class ConvoyBarrierNotMetException implements Exception {
  const ConvoyBarrierNotMetException();

  @override
  String toString() =>
      'ConvoyBarrierNotMetException: other drivers are not ready yet.';
}
