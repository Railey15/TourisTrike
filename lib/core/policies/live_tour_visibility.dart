import 'package:touristrike/core/models/convoy_state.dart';

/// Presentation and subscription gate derived from the accepted booking roster.
/// The roster is loaded from booking_drivers, not from assigned_driver_id.
class LiveTourVisibility {
  const LiveTourVisibility._();

  static const _terminal = {
    'completed',
    'done',
    'cancelled',
    'rejected',
    'expired',
    'failed',
    'closed',
  };

  static bool _isTerminal(Iterable<String?> statuses) => statuses.any(
    (status) => _terminal.contains(status?.trim().toLowerCase()),
  );

  static bool tourist({
    required List<ConvoyDriverSnapshot> roster,
    required Iterable<String?> statuses,
    required DateTime? scheduledStartAt,
    required DateTime now,
    required bool serverAuthorized,
    bool scheduleBypassAuthorized = false,
  }) {
    if (!serverAuthorized ||
        scheduledStartAt == null ||
        (now.isBefore(scheduledStartAt) && !scheduleBypassAuthorized) ||
        _isTerminal(statuses)) {
      return false;
    }
    return roster.any(
      (driver) =>
          driver.assignmentStatus == 'accepted' &&
          driver.journeyState != ConvoyJourneyState.completed,
    );
  }

  static bool driver({
    required ConvoyDriverSnapshot? assignment,
    required Iterable<String?> statuses,
    required DateTime? scheduledStartAt,
    required DateTime now,
    required bool serverAuthorized,
    bool scheduleBypassAuthorized = false,
  }) {
    return serverAuthorized &&
        scheduledStartAt != null &&
        (!now.isBefore(scheduledStartAt) || scheduleBypassAuthorized) &&
        !_isTerminal(statuses) &&
        assignment?.assignmentStatus == 'accepted' &&
        assignment?.journeyState != ConvoyJourneyState.completed;
  }
}
