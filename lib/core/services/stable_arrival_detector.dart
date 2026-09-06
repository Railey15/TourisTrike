/// Uses distinct, recent fixes for the current persisted driver stage. A failed
/// network attempt may be retried; the persisted arrival transition is final.
class StableArrivalDetector {
  StableArrivalDetector({required this.radiusMeters});
  static const maxAccuracyMeters = 50.0;
  static const maxFixAge = Duration(seconds: 20);

  static bool isUsableFix({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime sampledAt,
    required DateTime now,
  }) =>
      latitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.isFinite &&
      longitude.abs() <= 180 &&
      accuracyMeters.isFinite &&
      accuracyMeters >= 0 &&
      accuracyMeters <= maxAccuracyMeters &&
      now.difference(sampledAt) <= maxFixAge &&
      !sampledAt.isAfter(now.add(const Duration(seconds: 2)));
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
    if (!distanceMeters.isFinite ||
        !accuracyMeters.isFinite ||
        accuracyMeters < 0 ||
        accuracyMeters > maxAccuracyMeters ||
        distanceMeters > radiusMeters ||
        distanceMeters < 0 ||
        now.difference(sampledAt) > maxFixAge ||
        sampledAt.isAfter(now.add(const Duration(seconds: 2)))) {
      _insideCount = 0;
      _firstInside = null;
      return false;
    }
    // A bad future timestamp must not prevent subsequent real fixes.
    if (_lastSample != null && !sampledAt.isAfter(_lastSample!)) return false;
    final gap = _lastSample == null
        ? Duration.zero
        : sampledAt.difference(_lastSample!);
    _lastSample = sampledAt;
    if (gap > maxFixAge) {
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
