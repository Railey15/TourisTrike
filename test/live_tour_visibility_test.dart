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
  test('accepted roster controls tourist map and Share Trip together', () {
    expect(
      LiveTourVisibility.tourist(roster: [], statuses: ['confirmed']),
      false,
    );
    expect(
      LiveTourVisibility.tourist(
        roster: [assignment(ConvoyJourneyState.assigned, status: 'pending')],
        statuses: ['confirmed'],
      ),
      false,
    );
    expect(
      LiveTourVisibility.driver(
        assignment: assignment(ConvoyJourneyState.assigned, status: 'rejected'),
        statuses: ['confirmed'],
      ),
      false,
    );
    for (final state in ConvoyJourneyState.values.where(
      (state) => state != ConvoyJourneyState.completed,
    )) {
      final accepted = assignment(state);
      expect(
        LiveTourVisibility.tourist(roster: [accepted], statuses: ['confirmed']),
        true,
        reason: state.name,
      );
      expect(
        LiveTourVisibility.driver(
          assignment: accepted,
          statuses: ['confirmed'],
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
        LiveTourVisibility.tourist(roster: [accepted], statuses: [terminal]),
        false,
        reason: terminal,
      );
      expect(
        LiveTourVisibility.driver(assignment: accepted, statuses: [terminal]),
        false,
        reason: terminal,
      );
    }
  });
}
