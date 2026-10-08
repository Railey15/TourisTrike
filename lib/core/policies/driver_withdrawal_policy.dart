/// Mirrors the guards in request_driver_withdrawal and withdraw_driver_slot_impl.
bool canRequestDriverWithdrawal({
  required String bookingStatus,
  required String tourStatus,
  required String assignmentStatus,
  required bool hasArrived,
  required bool hasPickedUp,
  String assignmentJourneyState = 'assigned',
}) {
  const startedTourStates = {
    'picked_up',
    'on_tour',
    'en_route_to_spot',
    'at_spot',
    'en_route_to_dropoff',
    'ready_to_complete',
    'dropped_off',
    'completed',
  };
  const startedJourneyStates = {
    'boarded',
    'en_route_stop',
    'at_stop',
    'stop_done',
    'en_route_dropoff',
    'at_dropoff',
    'completed',
  };
  return assignmentStatus == 'accepted' &&
      {
        'pending',
        'confirmed',
        'accepted',
        'waiting_for_drivers',
        'driver_accepted',
        'driver_en_route',
        'driver_on_the_way',
      }.contains(bookingStatus.toLowerCase()) &&
      !hasPickedUp &&
      !startedTourStates.contains(tourStatus.toLowerCase()) &&
      !startedJourneyStates.contains(assignmentJourneyState.toLowerCase());
}

const withdrawalAfterStartMessage =
    'You can no longer withdraw from this tour because the trip has already started. '
    'Please contact the Tourism Office if assistance is needed.';

String withdrawalErrorMessage(Object error) {
  final raw = error.toString();
  if (raw.contains('CANNOT_CANCEL_AFTER_TOUR_STARTED') ||
      raw.contains('TOUR_ALREADY_STARTED')) {
    return withdrawalAfterStartMessage;
  }
  if (raw.contains('NOT_IN_CONVOY')) {
    return 'Your Driver assignment is no longer active. Please refresh the tour.';
  }
  return 'Unable to withdraw right now. Please try again or contact the Tourism Office.';
}
