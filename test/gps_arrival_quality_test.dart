import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/services/stable_arrival_detector.dart';

void main() {
  final now = DateTime.utc(2026, 9, 6, 8);
  bool usable({
    double lat = 15,
    double lng = 121,
    double accuracy = 10,
    Duration age = Duration.zero,
  }) => StableArrivalDetector.isUsableFix(
    latitude: lat,
    longitude: lng,
    accuracyMeters: accuracy,
    sampledAt: now.subtract(age),
    now: now,
  );

  test('only valid fresh accurate coordinates may be uploaded for arrival', () {
    expect(usable(), isTrue);
    expect(usable(lat: 91), isFalse);
    expect(usable(lng: -181), isFalse);
    expect(usable(lat: double.nan), isFalse);
    expect(usable(lng: double.infinity), isFalse);
    expect(usable(accuracy: -1), isFalse);
    expect(usable(accuracy: double.nan), isFalse);
    expect(usable(accuracy: 51), isFalse);
    expect(usable(age: const Duration(seconds: 21)), isFalse);
    expect(usable(age: const Duration(seconds: -3)), isFalse);
    expect(usable(accuracy: 50, age: const Duration(seconds: 20)), isTrue);
  });

  test('a future-dated fix does not poison later valid arrival samples', () {
    final detector = StableArrivalDetector(radiusMeters: 150);
    bool sample(int seconds, {int futureOffset = 0}) => detector.observe(
      target: 'pickup',
      distanceMeters: 20,
      accuracyMeters: 10,
      sampledAt: now.add(Duration(seconds: seconds + futureOffset)),
      now: now.add(Duration(seconds: seconds)),
    );
    expect(sample(0), isFalse);
    expect(sample(3, futureOffset: 3600), isFalse);
    expect(sample(6), isFalse);
    expect(sample(9), isFalse);
    expect(sample(12), isTrue);
  });

  test(
    'each driver and repeated stop uses its own stable arrival sequence',
    () {
      final a = StableArrivalDetector(radiusMeters: 150);
      final b = StableArrivalDetector(radiusMeters: 150);
      bool sample(
        StableArrivalDetector detector,
        int seconds, {
        String target = 'stop:0',
        double distance = 20,
      }) => detector.observe(
        target: target,
        distanceMeters: distance,
        accuracyMeters: 10,
        sampledAt: now.add(Duration(seconds: seconds)),
        now: now.add(Duration(seconds: seconds)),
      );
      for (final seconds in [0, 3]) {
        expect(sample(a, seconds), isFalse);
        expect(sample(b, seconds, distance: 500), isFalse);
      }
      expect(sample(a, 6), isTrue);
      expect(sample(b, 6), isFalse);
      expect(sample(a, 9, target: 'stop:1'), isFalse);
      expect(sample(b, 9), isFalse);
      expect(sample(b, 12), isTrue);
      expect(sample(a, 12, target: 'stop:1', distance: 151), isFalse);
      expect(sample(a, 15, target: 'stop:1'), isFalse);
      expect(sample(a, 18, target: 'stop:1'), isFalse);
      expect(sample(a, 21, target: 'stop:1'), isTrue);
    },
  );
}
