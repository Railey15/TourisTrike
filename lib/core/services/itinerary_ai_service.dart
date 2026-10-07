import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/itinerary_ai_suggestion.dart';

class ItineraryAiService {
  const ItineraryAiService();

  Future<ItineraryAiSuggestion> suggest({
    required Object packageId,
    required List<Map<String, Object?>> destinations,
    required List<double> pickup,
    required List<double> dropoff,
    required int pickupMinutes,
    required List<Map<String, Object?>> currentRouteLegs,
  }) async {
    final response = await Supabase.instance.client.functions
        .invoke(
          'itinerary-ai-suggest',
          body: {
            'package_id': packageId,
            'destinations': destinations,
            'pickup': pickup,
            'dropoff': dropoff,
            'pickup_minutes': pickupMinutes,
            'current_route_legs': currentRouteLegs,
          },
        )
        .timeout(const Duration(seconds: 25));
    return ItineraryAiSuggestion.parse(
      response.data,
      destinations.map((row) => row['id']! as String).toList(),
    );
  }
}
