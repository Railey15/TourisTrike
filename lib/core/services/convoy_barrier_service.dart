import '../models/convoy_state.dart';

/// Single source of truth for convoy barrier gating and deadlock/offline
/// detection. Every "can this driver depart / complete the tour" decision,
/// and every stuck/offline check, MUST go through this class — do not
/// re-implement a threshold comparison or a state ordering check in a
/// widget or screen.
///
/// Callers are expected to pass only currently-accepted drivers (i.e.
/// `booking_drivers` rows already filtered to `status = 'accepted'`) —
/// this service has no notion of acceptance/cancellation, only journey
/// progress. Slot cancellation/release is a Phase 5 concern.
///
/// Pure and Supabase-agnostic on purpose — unit-testable without a
/// database or a widget tree.
class ConvoyBarrierService {
  const ConvoyBarrierService._();

  /// A driver stuck at the same journey_state longer than this shows the
  /// amber "Waiting for [Name] - N mins" warning to the rest of the convoy.
  static const stuckWarningThreshold = Duration(minutes: 10);

  /// Past this, the app should surface "Report Issue" (notifies the
  /// tourism office admin) and expose an admin-side force-release/remove
  /// option. Threshold only — the report/override flow itself is Phase 5.
  static const stuckCriticalThreshold = Duration(minutes: 20);

  /// No location ping for this long marks a driver 'offline' in the UI.
  static const offlineThreshold = Duration(minutes: 5);

  // ── Barrier gates ────────────────────────────────────────────

  /// "Depart from Pickup" — every driver must have at least boarded.
  static bool canDepartFromPickup(List<ConvoyDriverSnapshot> convoy) =>
      convoy.every(
        (d) => d.journeyState.isAtLeast(ConvoyJourneyState.boarded),
      );

  static List<ConvoyDriverSnapshot> blockingDepartFromPickup(
    List<ConvoyDriverSnapshot> convoy,
  ) => convoy
      .where((d) => !d.journeyState.isAtLeast(ConvoyJourneyState.boarded))
      .toList(growable: false);

  /// "Depart from Stop N" — every driver must be past stop N already, or
  /// at stop N with stopDone reached. Stop-index-aware because
  /// enRouteStop/atStop/stopDone recur per stop — comparing raw
  /// [ConvoyJourneyState.order] alone would be wrong across two drivers
  /// sitting on different stops.
  static bool canDepartFromStop(
    List<ConvoyDriverSnapshot> convoy,
    int stopIndex,
  ) => convoy.every((d) => _hasClearedStop(d, stopIndex));

  static List<ConvoyDriverSnapshot> blockingDepartFromStop(
    List<ConvoyDriverSnapshot> convoy,
    int stopIndex,
  ) => convoy
      .where((d) => !_hasClearedStop(d, stopIndex))
      .toList(growable: false);

  static bool _hasClearedStop(ConvoyDriverSnapshot d, int stopIndex) =>
      d.currentStopIndex > stopIndex ||
      (d.currentStopIndex == stopIndex &&
          d.journeyState.isAtLeast(ConvoyJourneyState.stopDone));

  /// "Complete Tour" — every driver must have at least reached drop-off.
  static bool canCompleteTour(List<ConvoyDriverSnapshot> convoy) => convoy
      .every((d) => d.journeyState.isAtLeast(ConvoyJourneyState.atDropoff));

  static List<ConvoyDriverSnapshot> blockingCompleteTour(
    List<ConvoyDriverSnapshot> convoy,
  ) => convoy
      .where((d) => !d.journeyState.isAtLeast(ConvoyJourneyState.atDropoff))
      .toList(growable: false);

  /// True once a driver has reached whichever gate state they're
  /// currently sitting at (boarded/stopDone/atDropoff/completed) — i.e.
  /// they're independently "arrived and waiting," not still en route.
  /// Single source for the "N of M arrived/ready" aggregates shown in
  /// ConvoyRosterStrip and ConvoyOverallStatusBanner.
  static bool isAtGate(ConvoyDriverSnapshot d) => switch (d.journeyState) {
    ConvoyJourneyState.boarded ||
    ConvoyJourneyState.stopDone ||
    ConvoyJourneyState.atDropoff ||
    ConvoyJourneyState.completed => true,
    _ => false,
  };

  // ── Overall status (Open Question 4: slowest driver wins) ──────

  /// The convoy's overall status is the SLOWEST driver's state — used for
  /// the tourist-facing aggregate banner (Phase 3) and the legacy
  /// `package_activities.tour_status` mirror write. Returns null for an
  /// empty convoy (caller decides how to display that — should not
  /// happen for a booking whose tracking screen is even showing).
  ///
  /// Must mirror the slowest-state SQL in `advance_driver_journey_state`
  /// (supabase/migrations/20260805020000_convoy_phase2b_advance_state_rpc.sql)
  /// — keep both in sync. This Dart copy is for CLIENT-SIDE DISPLAY only;
  /// the SQL copy is the authoritative one that actually gets written.
  static ConvoyJourneyState? deriveOverallState(
    List<ConvoyDriverSnapshot> convoy,
  ) {
    if (convoy.isEmpty) return null;
    return convoy
        .map((d) => d.journeyState)
        .reduce((a, b) => a.order <= b.order ? a : b);
  }

  // ── Deadlock / offline detection ────────────────────────────

  static Duration elapsedAtCurrentState(
    ConvoyDriverSnapshot driver, {
    DateTime? now,
  }) => (now ?? DateTime.now()).difference(driver.stateUpdatedAt);

  static bool isStuck(ConvoyDriverSnapshot driver, {DateTime? now}) =>
      elapsedAtCurrentState(driver, now: now) >= stuckWarningThreshold;

  static bool isCriticallyStuck(
    ConvoyDriverSnapshot driver, {
    DateTime? now,
  }) => elapsedAtCurrentState(driver, now: now) >= stuckCriticalThreshold;

  static bool isOffline(ConvoyDriverSnapshot driver, {DateTime? now}) {
    final lastSeen = driver.lastLocationAt;
    if (lastSeen == null) return true;
    return (now ?? DateTime.now()).difference(lastSeen) >= offlineThreshold;
  }
}
