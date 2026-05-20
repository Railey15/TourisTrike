import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/places/city_spot_suggestions.dart';

class TouristAiRecommendationSpot {
  const TouristAiRecommendationSpot({
    required this.id,
    required this.title,
    required this.address,
    required this.distanceText,
    required this.distanceKm,
    required this.category,
    required this.rating,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.municipality,
    required this.googlePlaceId,
    required this.description,
    this.openNow,
    this.userRatingsTotal = 0,
    this.types = const [],
  });

  final String id;
  final String title;
  final String address;
  final String distanceText;
  final double distanceKm;
  final String category;
  final double rating;
  final int userRatingsTotal;
  final String imageUrl;
  final double latitude;
  final double longitude;
  final bool? openNow;
  final List<String> types;
  final String municipality;
  final String googlePlaceId;
  final String description;
}

class TouristAiRecommendationService {
  const TouristAiRecommendationService({
    SupabaseClient? supabase,
    CitySpotSuggestionService? spotSuggestionService,
  }) : _supabase = supabase,
       _spotSuggestionService = spotSuggestionService;

  final SupabaseClient? _supabase;
  final CitySpotSuggestionService? _spotSuggestionService;

  SupabaseClient get supabase => _supabase ?? Supabase.instance.client;

  CitySpotSuggestionService get spotSuggestionService =>
      _spotSuggestionService ?? const CitySpotSuggestionService();

  Future<List<TouristAiRecommendationSpot>> loadMunicipalitySpots({
    required String municipality,
    required LatLng center,
    int googleLimit = 20,
  }) async {
    final results = await Future.wait([
      loadSavedTouristSpots(municipality: municipality, center: center),
      loadGoogleFamousSpots(
        municipality: municipality,
        center: center,
        limit: googleLimit,
      ),
    ]);

    final merged = mergeAndDeduplicateSpots([...results[0], ...results[1]]);
    merged.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return merged;
  }

  Future<List<TouristAiRecommendationSpot>> loadGoogleFamousSpots({
    required String municipality,
    required LatLng center,
    int limit = 20,
  }) async {
    final suggestions = await spotSuggestionService.fetchSuggestions(
      city: municipality,
      province: 'Bulacan',
      center: center,
      limit: limit,
    );

    return suggestions
        .map((suggestion) {
          final category = normalizeSpotCategory(
            suggestion.category,
            placeTypes: suggestion.placeTypes,
          );
          return TouristAiRecommendationSpot(
            id: suggestion.id,
            title: suggestion.title,
            address: suggestion.address,
            distanceText: distanceText(suggestion.distanceKm),
            distanceKm: suggestion.distanceKm,
            category: category,
            rating: suggestion.rating,
            imageUrl: suggestion.imageForCard,
            latitude: suggestion.latitude,
            longitude: suggestion.longitude,
            openNow: null,
            types: suggestion.placeTypes,
            municipality: municipality,
            googlePlaceId: suggestion.id,
            description: suggestion.description,
          );
        })
        .toList(growable: false);
  }

  Future<List<TouristAiRecommendationSpot>> loadSavedTouristSpots({
    required String municipality,
    required LatLng center,
  }) async {
    try {
      final responses = await Future.wait([
        supabase
            .from('tourist_spots')
            .select(
              'id, title, city, municipality, latitude, longitude, rating, image_url, description, address, barangay, source_type, google_place_id, category_id, tourist_spot_images(image_url, sort_order, is_cover)',
            )
            .neq('status', 'archived')
            .order('title', ascending: true)
            .limit(200)
            .timeout(const Duration(seconds: 15)),
        supabase
            .from('tourism_categories')
            .select('id, name')
            .limit(200)
            .timeout(const Duration(seconds: 15)),
      ]);

      final spotRows = (responses[0] as List).whereType<Map>().toList();
      final categoryRows = (responses[1] as List).whereType<Map>().toList();
      final categoryNames = <String, String>{
        for (final row in categoryRows)
          '${row['id']}': ((row['name'] as String?) ?? '').trim(),
      };
      final selectedCity = normalizeText(municipality);

      return spotRows
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) {
            final city = normalizeText(
              ((row['municipality'] as String?) ??
                      (row['city'] as String?) ??
                      '')
                  .trim(),
            );
            final fallbackCity = normalizeText(
              ((row['city'] as String?) ?? '').trim(),
            );
            return city == selectedCity ||
                fallbackCity == selectedCity ||
                fallbackCity == normalizeText('$municipality Bulacan') ||
                fallbackCity.contains(selectedCity);
          })
          .map((row) {
            final lat = (row['latitude'] as num?)?.toDouble() ?? 0;
            final lng = (row['longitude'] as num?)?.toDouble() ?? 0;
            final distanceKm = haversineKm(
              center.latitude,
              center.longitude,
              lat,
              lng,
            );
            final categoryName =
                categoryNames['${row['category_id']}'] ??
                ((row['category'] as String?) ?? '');
            final resolvedMunicipality =
                ((row['municipality'] as String?)?.trim().isNotEmpty ?? false)
                ? (row['municipality'] as String).trim()
                : ((row['city'] as String?) ?? municipality).trim();
            final category = normalizeSpotCategory(
              categoryName,
              title: (row['title'] as String?) ?? '',
              description: (row['description'] as String?) ?? '',
            );

            return TouristAiRecommendationSpot(
              id: '${row['id']}',
              title: ((row['title'] as String?) ?? 'Untitled Spot').trim(),
              address: ((row['address'] as String?) ?? '').trim(),
              distanceText: distanceText(distanceKm),
              distanceKm: distanceKm,
              category: category,
              rating: (row['rating'] as num?)?.toDouble() ?? 4.5,
              imageUrl: resolveSpotImageUrl(
                primaryImage: (row['image_url'] as String?) ?? '',
                imageRows: row['tourist_spot_images'] as List?,
              ),
              latitude: lat,
              longitude: lng,
              openNow: null,
              municipality: resolvedMunicipality,
              googlePlaceId: ((row['google_place_id'] as String?) ?? '').trim(),
              description: ((row['description'] as String?) ?? '').trim(),
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<TouristAiRecommendationSpot> mergeAndDeduplicateSpots(
    List<TouristAiRecommendationSpot> spots,
  ) {
    final merged = <TouristAiRecommendationSpot>[];
    final seen = <String>{};

    for (final spot in spots) {
      final googleKey = spot.googlePlaceId.trim().toLowerCase();
      final fallbackKey =
          '${normalizeText(spot.title)}|${normalizeText(spot.municipality)}';
      final key = googleKey.isNotEmpty ? 'g:$googleKey' : 't:$fallbackKey';
      if (seen.add(key)) {
        merged.add(spot);
      }
    }

    return merged;
  }

  String normalizeSpotCategory(
    String rawCategory, {
    List<String> placeTypes = const [],
    String title = '',
    String description = '',
  }) {
    final source = [
      rawCategory,
      title,
      description,
      placeTypes.join(' '),
    ].join(' ').toLowerCase();

    if (source.contains('museum')) return 'Museum';
    if (source.contains('park') ||
        source.contains('garden') ||
        source.contains('playground')) {
      return 'Park';
    }
    if (source.contains('resort') ||
        source.contains('pool') ||
        source.contains('beach')) {
      return 'Resort';
    }
    if (source.contains('food') ||
        source.contains('restaurant') ||
        source.contains('cafe') ||
        source.contains('eat')) {
      return 'Food';
    }
    if (source.contains('religious') ||
        source.contains('church') ||
        source.contains('cathedral') ||
        source.contains('worship') ||
        source.contains('temple')) {
      return 'Religious';
    }
    if (source.contains('historic') ||
        source.contains('historical') ||
        source.contains('heritage') ||
        source.contains('monument')) {
      return 'Historical';
    }
    if (source.contains('nature') ||
        source.contains('mountain') ||
        source.contains('river') ||
        source.contains('falls') ||
        source.contains('lake') ||
        source.contains('forest')) {
      return 'Nature';
    }
    return 'Nature';
  }

  bool matchesPreferredCategory(
    TouristAiRecommendationSpot spot,
    Iterable<String> preferredCategories,
  ) {
    final categories = preferredCategories
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (categories.isEmpty) return false;

    final source = [
      spot.category,
      spot.title,
      spot.description,
      spot.address,
      spot.municipality,
      spot.types.join(' '),
    ].join(' ').toLowerCase();

    for (final preferred in categories) {
      final normalizedPreferred = preferred.toLowerCase();
      if (spot.category.toLowerCase() == normalizedPreferred) {
        return true;
      }

      switch (normalizedPreferred) {
        case 'food':
          if (source.contains('food') ||
              source.contains('restaurant') ||
              source.contains('cafe') ||
              source.contains('eat')) {
            return true;
          }
          break;
        case 'nature':
          if (source.contains('nature') ||
              source.contains('park') ||
              source.contains('garden') ||
              source.contains('mountain') ||
              source.contains('river') ||
              source.contains('falls') ||
              source.contains('lake') ||
              source.contains('forest')) {
            return true;
          }
          break;
        case 'historical':
          if (source.contains('historical') ||
              source.contains('historic') ||
              source.contains('heritage') ||
              source.contains('monument') ||
              source.contains('museum')) {
            return true;
          }
          break;
        case 'religious':
          if (source.contains('religious') ||
              source.contains('church') ||
              source.contains('cathedral') ||
              source.contains('worship') ||
              source.contains('temple')) {
            return true;
          }
          break;
        case 'resort':
          if (source.contains('resort') ||
              source.contains('pool') ||
              source.contains('beach')) {
            return true;
          }
          break;
        case 'museum':
          if (source.contains('museum')) {
            return true;
          }
          break;
        case 'park':
          if (source.contains('park') ||
              source.contains('garden') ||
              source.contains('playground')) {
            return true;
          }
          break;
      }
    }

    return false;
  }

  String distanceText(double km) {
    if (km < 1) return '${(km * 1000).round()} m away';
    return '${km.toStringAsFixed(1)} km away';
  }

  String resolveSpotImageUrl({
    required String primaryImage,
    required List? imageRows,
  }) {
    if (primaryImage.trim().isNotEmpty) return primaryImage.trim();
    if (imageRows == null) return '';

    final images = imageRows.whereType<Map>().map(Map<String, dynamic>.from);
    Map<String, dynamic>? preferred;

    for (final image in images) {
      if (image['is_cover'] == true) {
        preferred = image;
        break;
      }
      preferred ??= image;
    }

    return ((preferred?['image_url'] as String?) ?? '').trim();
  }

  String normalizeText(String value) {
    return value
        .toLowerCase()
        .replaceAll('Ã±', 'n')
        .replaceAll('ÃƒÂ±', 'n')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .replaceAll(',', '')
        .replaceAll('.', '');
  }

  double haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180);
}
