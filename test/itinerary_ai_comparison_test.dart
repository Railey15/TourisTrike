import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/itinerary_ai_comparison.dart';
import 'package:touristrike/core/services/itinerary_schedule_service.dart';

void main() {
  ItineraryTravelLeg leg(int minutes, {bool maps = true}) => ItineraryTravelLeg(
    durationMinutes: minutes,
    distanceMeters: 1000,
    usedGoogleMaps: maps,
  );

  test('savings use only routed legs and unchanged stays', () {
    final comparison = ItineraryAiComparison.fromRoutedLegs(
      original: [leg(20), leg(15), leg(10), leg(5)],
      suggested: [leg(10), leg(10), leg(10), leg(5)],
      stays: [30, 45, 60],
    )!;
    expect(comparison.originalMinutes, 185);
    expect(comparison.suggestedMinutes, 170);
    expect(comparison.minutesSaved, 15);
  });

  test('does not claim savings without two verified complete routes', () {
    expect(
      ItineraryAiComparison.fromRoutedLegs(
        original: [leg(20), leg(10, maps: false)],
        suggested: [leg(1), leg(1)],
        stays: [30],
      ),
      isNull,
    );
    expect(
      ItineraryAiComparison.fromRoutedLegs(
        original: [leg(20), leg(10)],
        suggested: [leg(1)],
        stays: [30],
      ),
      isNull,
    );
  });
}
