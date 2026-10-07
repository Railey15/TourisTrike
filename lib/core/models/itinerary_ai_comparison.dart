import '../services/itinerary_schedule_service.dart';

/// Compares only routes calculated by the existing Google Maps service.
class ItineraryAiComparison {
  const ItineraryAiComparison._(this.originalMinutes, this.suggestedMinutes);

  final int originalMinutes;
  final int suggestedMinutes;
  int get minutesSaved => originalMinutes - suggestedMinutes;
  bool get isImprovement => minutesSaved > 0;

  static ItineraryAiComparison? fromRoutedLegs({
    required List<ItineraryTravelLeg> original,
    required List<ItineraryTravelLeg> suggested,
    required List<int> stays,
  }) {
    if (original.isEmpty ||
        original.length != suggested.length ||
        original.length != stays.length + 1 ||
        original.any((leg) => !leg.usedGoogleMaps) ||
        suggested.any((leg) => !leg.usedGoogleMaps)) {
      return null;
    }
    final stayMinutes = stays.fold<int>(0, (sum, value) => sum + value);
    return ItineraryAiComparison._(
      stayMinutes +
          original.fold<int>(0, (sum, leg) => sum + leg.durationMinutes),
      stayMinutes +
          suggested.fold<int>(0, (sum, leg) => sum + leg.durationMinutes),
    );
  }
}
