import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/policies/driver_withdrawal_policy.dart';

void main() {
  bool allowed({
    String booking = 'accepted',
    String tour = 'driver_accepted',
    String assignment = 'accepted',
    bool arrived = false,
    bool pickedUp = false,
    String journey = 'assigned',
  }) => canRequestDriverWithdrawal(
    bookingStatus: booking,
    tourStatus: tour,
    assignmentStatus: assignment,
    hasArrived: arrived,
    hasPickedUp: pickedUp,
    assignmentJourneyState: journey,
  );

  test('only accepted pre-start assignments may withdraw', () {
    expect(allowed(), isTrue);
    expect(allowed(booking: 'waiting_for_drivers'), isTrue);
    expect(allowed(booking: 'confirmed'), isTrue);
    expect(allowed(tour: 'driver_arrived', arrived: true), isTrue);
    expect(allowed(booking: 'on_tour'), isFalse);
    expect(allowed(tour: 'on_tour'), isFalse);
    expect(allowed(pickedUp: true), isFalse);
    expect(allowed(journey: 'boarded'), isFalse);
    expect(allowed(journey: 'en_route_stop'), isFalse);
    expect(allowed(assignment: 'rejected'), isFalse);
  });

  test('server race errors never appear raw', () {
    for (final code in [
      'CANNOT_CANCEL_AFTER_TOUR_STARTED',
      'TOUR_ALREADY_STARTED',
    ]) {
      final message = withdrawalErrorMessage(
        Exception('PostgrestException(message: $code, code: P0001)'),
      );
      expect(message, withdrawalAfterStartMessage);
      expect(message, isNot(contains('PostgrestException')));
      expect(message, isNot(contains('P0001')));
    }
  });
}
