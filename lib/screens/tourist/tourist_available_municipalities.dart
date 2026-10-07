import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';

import 'tourist_location_state.dart';

/// Uses the same active, Bulacan spot visibility scope as discovery cards.
Future<Set<String>> loadTouristAvailableMunicipalities(
  SupabaseClient supabase,
) async {
  final available = <String>{};
  const pageSize = 1000;
  for (var offset = 0; ; offset += pageSize) {
    final rows = await supabase
        .from('tourist_spots')
        .select('municipality, city')
        .eq('status', 'active')
        .inFilter('verification_status', ['approved', 'verified'])
        .eq('province', 'Bulacan')
        .order('id')
        .range(offset, offset + pageSize - 1);
    available.addAll(availableMunicipalitiesFromActiveSpotRows(rows));
    if (rows.length < pageSize) return available;
  }
}

Set<String> availableMunicipalitiesFromActiveSpotRows(
  Iterable<Map<String, dynamic>> rows,
) {
  return {
    for (final row in rows)
      for (final area in touristBulacanMunicipalities)
        if (CitySpotSuggestionService.matchesMunicipalityName(
          ((row['municipality'] as String?)?.trim().isNotEmpty == true
                      ? row['municipality']
                      : row['city'])
                  ?.toString() ??
              '',
          area.name,
        ))
          area.name,
  };
}
