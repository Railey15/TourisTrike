import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/convoy_state.dart';
import 'package:touristrike/core/policies/live_tour_visibility.dart';

ConvoyDriverSnapshot assignment(
  ConvoyJourneyState state, {
  String status = 'accepted',
}) => ConvoyDriverSnapshot(
  driverId: 'driver-1',
  driverName: 'Driver',
  plateNumber: 'TEST',
  journeyState: state,
  currentStopIndex: 0,
  stateUpdatedAt: DateTime.utc(2026),
  assignmentStatus: status,
);

void main() {
  final scheduled = DateTime.utc(2026, 10, 10, 8);

  test('accepted roster controls tourist map and Share Trip together', () {
    expect(
      LiveTourVisibility.tourist(
        roster: [],
        statuses: ['confirmed'],
        scheduledStartAt: scheduled,
        now: scheduled,
        serverAuthorized: true,
      ),
      false,
    );
    expect(
      LiveTourVisibility.tourist(
        roster: [assignment(ConvoyJourneyState.assigned, status: 'pending')],
        statuses: ['confirmed'],
        scheduledStartAt: scheduled,
        now: scheduled,
        serverAuthorized: true,
      ),
      false,
    );
    expect(
      LiveTourVisibility.driver(
        assignment: assignment(ConvoyJourneyState.assigned, status: 'rejected'),
        statuses: ['confirmed'],
        scheduledStartAt: scheduled,
        now: scheduled,
        serverAuthorized: true,
      ),
      false,
    );
    for (final state in ConvoyJourneyState.values.where(
      (state) => state != ConvoyJourneyState.completed,
    )) {
      final accepted = assignment(state);
      expect(
        LiveTourVisibility.tourist(
          roster: [accepted],
          statuses: ['confirmed'],
          scheduledStartAt: scheduled,
          now: scheduled,
          serverAuthorized: true,
        ),
        true,
        reason: state.name,
      );
      expect(
        LiveTourVisibility.driver(
          assignment: accepted,
          statuses: ['confirmed'],
          scheduledStartAt: scheduled,
          now: scheduled,
          serverAuthorized: true,
        ),
        true,
        reason: state.name,
      );
    }
  });

  test('completed assignments and terminal tours hide live tracking', () {
    final accepted = assignment(ConvoyJourneyState.enRouteStop);
    expect(
      LiveTourVisibility.tourist(
        roster: [assignment(ConvoyJourneyState.completed, status: 'completed')],
        statuses: ['confirmed'],
        scheduledStartAt: scheduled,
        now: scheduled,
        serverAuthorized: true,
      ),
      false,
    );
    expect(
      LiveTourVisibility.driver(
        assignment: assignment(
          ConvoyJourneyState.completed,
          status: 'completed',
        ),
        statuses: ['confirmed'],
        scheduledStartAt: scheduled,
        now: scheduled,
        serverAuthorized: true,
      ),
      false,
    );
    for (final terminal in [
      'completed',
      'done',
      'cancelled',
      'rejected',
      'expired',
      'failed',
      'closed',
    ]) {
      expect(
        LiveTourVisibility.tourist(
          roster: [accepted],
          statuses: [terminal],
          scheduledStartAt: scheduled,
          now: scheduled,
          serverAuthorized: true,
        ),
        false,
        reason: terminal,
      );
      expect(
        LiveTourVisibility.driver(
          assignment: accepted,
          statuses: [terminal],
          scheduledStartAt: scheduled,
          now: scheduled,
          serverAuthorized: true,
        ),
        false,
        reason: terminal,
      );
    }
  });

  test('scheduled start is an inclusive live tracking boundary', () {
    final accepted = assignment(ConvoyJourneyState.assigned);
    final oneMinuteEarly = scheduled.subtract(const Duration(minutes: 1));
    for (final visible in [
      LiveTourVisibility.tourist(
        roster: [accepted],
        statuses: ['confirmed'],
        scheduledStartAt: scheduled,
        now: oneMinuteEarly,
        serverAuthorized: true,
      ),
      LiveTourVisibility.driver(
        assignment: accepted,
        statuses: ['confirmed'],
        scheduledStartAt: scheduled,
        now: oneMinuteEarly,
        serverAuthorized: true,
      ),
    ]) {
      expect(visible, isFalse);
    }
    expect(
      LiveTourVisibility.tourist(
        roster: [accepted],
        statuses: ['confirmed'],
        scheduledStartAt: scheduled,
        now: scheduled,
        serverAuthorized: true,
      ),
      isTrue,
    );
  });

  test('server denial fails closed even after scheduled start', () {
    expect(
      LiveTourVisibility.driver(
        assignment: assignment(ConvoyJourneyState.assigned),
        statuses: ['confirmed'],
        scheduledStartAt: scheduled,
        now: scheduled.add(const Duration(minutes: 1)),
        serverAuthorized: false,
      ),
      isFalse,
    );
  });

  test('authorized TEST MODE bypasses only the future schedule boundary', () {
    final accepted = assignment(ConvoyJourneyState.assigned);
    final early = scheduled.subtract(const Duration(days: 1));

    expect(
      LiveTourVisibility.driver(
        assignment: accepted,
        statuses: ['confirmed'],
        scheduledStartAt: scheduled,
        now: early,
        serverAuthorized: true,
        scheduleBypassAuthorized: true,
      ),
      isTrue,
    );
    expect(
      LiveTourVisibility.tourist(
        roster: [accepted],
        statuses: ['cancelled'],
        scheduledStartAt: scheduled,
        now: early,
        serverAuthorized: true,
        scheduleBypassAuthorized: true,
      ),
      isFalse,
    );
    expect(
      LiveTourVisibility.driver(
        assignment: assignment(ConvoyJourneyState.assigned, status: 'rejected'),
        statuses: ['confirmed'],
        scheduledStartAt: scheduled,
        now: early,
        serverAuthorized: true,
        scheduleBypassAuthorized: true,
      ),
      isFalse,
    );
  });
}
