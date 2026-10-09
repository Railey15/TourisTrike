class TouristTrackingVisibility {
  const TouristTrackingVisibility._({
    required this.isCompleted,
    required this.isCancelled,
    required this.isTerminal,
    required this.showEmergency,
  });

  static const _completedStatuses = {'completed', 'done'};
  static const _terminalStatuses = {
    ..._completedStatuses,
    'cancelled',
    'refunded',
    'rejected',
    'failed',
    'expired',
  };
  static const _emergencyTourStatuses = {
    'picked_up',
    'on_tour',
    'en_route_to_spot',
    'at_spot',
    'en_route_to_dropoff',
    'ready_to_complete',
  };

  factory TouristTrackingVisibility.fromStatuses({
    String? bookingStatus,
    String? bookingLifecycleStatus,
    String? activityStatus,
    String? tourStatus,
    String? refundStatus,
    bool hasPickedUpAt = false,
  }) {
    final normalized = <String?>{
      bookingStatus,
      bookingLifecycleStatus,
      activityStatus,
      tourStatus,
    }.whereType<String>().map((value) => value.trim().toLowerCase()).toSet();
    final completed = normalized.any(_completedStatuses.contains);
    final cancelled = normalized.contains('cancelled');
    final terminal = normalized.any(_terminalStatuses.contains);
    final refunded = refundStatus?.trim().toLowerCase() == 'refunded';
    final activeEmergencyState = normalized.any(
      _emergencyTourStatuses.contains,
    );

    return TouristTrackingVisibility._(
      isCompleted: completed,
      isCancelled: cancelled,
      isTerminal: terminal || refunded,
      showEmergency:
          !(terminal || refunded) && (activeEmergencyState || hasPickedUpAt),
    );
  }

  final bool isCompleted;
  final bool isCancelled;
  final bool isTerminal;
  final bool showEmergency;

  bool get showLivePaymentProgress => !isTerminal;
  bool get showLiveDriverControls => !isTerminal;
  bool get showRealtimeTourProgress => !isTerminal;
}
