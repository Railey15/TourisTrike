import 'itinerary_stay_options.dart';

class ItineraryAiSuggestion {
  const ItineraryAiSuggestion({
    required this.orderedDestinationIds,
    required this.explanation,
    required this.stayRecommendations,
  });

  final List<String> orderedDestinationIds;
  final String explanation;
  final Map<String, int> stayRecommendations;

  static ItineraryAiSuggestion parse(Object? raw, List<String> selectedIds) {
    if (raw is! Map || selectedIds.toSet().length != selectedIds.length) {
      throw const FormatException('Invalid itinerary suggestion');
    }
    final ids = raw['ordered_destination_ids'];
    final explanation = raw['explanation'];
    if (ids is! List ||
        ids.length != selectedIds.length ||
        ids.any((id) => id is! String) ||
        ids.toSet().length != ids.length ||
        ids.toSet().difference(selectedIds.toSet()).isNotEmpty ||
        explanation is! String ||
        explanation.trim().isEmpty ||
        explanation.length > 500) {
      throw const FormatException('Invalid itinerary suggestion');
    }
    final stays = <String, int>{};
    final recommendations = raw['stay_recommendations'];
    if (recommendations is List) {
      for (final row in recommendations) {
        if (row is! Map) continue;
        final id = row['destination_id'];
        final minutes = row['minutes'];
        if (id is String &&
            selectedIds.contains(id) &&
            minutes is int &&
            ItineraryStayOptions.minutes.contains(minutes)) {
          stays[id] = minutes;
        }
      }
    }
    return ItineraryAiSuggestion(
      orderedDestinationIds: List<String>.unmodifiable(ids.cast<String>()),
      explanation: explanation.trim(),
      stayRecommendations: Map<String, int>.unmodifiable(stays),
    );
  }
}
