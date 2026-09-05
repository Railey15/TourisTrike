/// Uses distinct, recent fixes for the current persisted driver stage. A failed
/// network attempt may be retried; the persisted arrival transition is final.
class StableArrivalDetector {
  StableArrivalDetector({required this.radiusMeters});
  final double radiusMeters;
  String? _target;
  DateTime? _lastSample;
  DateTime? _firstInside;
  int _insideCount = 0;
  void reset() {
    _target = null;
    _lastSample = null;
    _firstInside = null;
    _insideCount = 0;
  }

  bool observe({
    required String target,
    required double distanceMeters,
    required double accuracyMeters,
    required DateTime sampledAt,
    required DateTime now,
  }) {
    if (_target != target) {
      reset();
      _target = target;
    }
    if (_lastSample != null && !sampledAt.isAfter(_lastSample!)) return false;
    final gap = _lastSample == null
        ? Duration.zero
        : sampledAt.difference(_lastSample!);
    _lastSample = sampledAt;
    if (!distanceMeters.isFinite ||
        !accuracyMeters.isFinite ||
        accuracyMeters < 0 ||
        accuracyMeters > 50 ||
        distanceMeters > radiusMeters ||
        distanceMeters < 0 ||
        now.difference(sampledAt).inSeconds > 20 ||
        sampledAt.isAfter(now.add(const Duration(seconds: 2)))) {
      _insideCount = 0;
      _firstInside = null;
      return false;
    }
    if (gap > const Duration(seconds: 20)) {
      _insideCount = 0;
      _firstInside = null;
    }
    _firstInside ??= sampledAt;
    _insideCount++;
    return _insideCount >= 3 &&
        sampledAt.difference(_firstInside!) >= const Duration(seconds: 6);
  }
}

Duration remainingStopStay({
  required DateTime arrivedAt,
  required int stayMinutes,
  required DateTime now,
}) {
  final remaining = arrivedAt
      .add(Duration(minutes: stayMinutes))
      .difference(now);
  return remaining.isNegative ? Duration.zero : remaining;
}
