import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/itinerary_ai_suggestion.dart';

void main() {
  const selected = ['a', 'b', 'c'];
  test('accepts an exact permutation and optional controlled stay', () {
    final result = ItineraryAiSuggestion.parse({
      'ordered_destination_ids': ['b', 'a', 'c'],
      'explanation': 'The route has less backtracking.',
      'stay_recommendations': [
        {'destination_id': 'a', 'minutes': 45},
        {'destination_id': 'b', 'minutes': 999},
        {'destination_id': 'unknown', 'minutes': 30},
      ],
      'travel_time_minutes': 1,
    }, selected);
    expect(result.orderedDestinationIds, ['b', 'a', 'c']);
    expect(result.stayRecommendations, {'a': 45});
  });

  test('rejects unknown, missing, and duplicate destination IDs', () {
    for (final ids in [
      ['a', 'b', 'x'],
      ['a', 'b'],
      ['a', 'a', 'b'],
    ]) {
      expect(
        () => ItineraryAiSuggestion.parse({
          'ordered_destination_ids': ids,
          'explanation': 'A route suggestion.',
        }, selected),
        throwsFormatException,
      );
    }
  });
}
