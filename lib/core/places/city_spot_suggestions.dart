import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class CitySpotSuggestion {
  const CitySpotSuggestion({
    required this.id,
    required this.title,
    required this.city,
    required this.province,
    String barangayHint = '',
    required this.address,
    required this.description,
    required this.reason,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.imageUrl,
    this.photoReference = '',
    this.contactNumber = '',
    this.websiteUrl = '',
    this.openingHoursText = '',
    this.userRatingsTotal = 0,
    required this.category,
    this.placeTypes = const [],
    required this.distanceKm,
  }) : _barangayHint = barangayHint;

  final String id;
  final String title;
  final String city;
  final String province;
  final String _barangayHint;
  final String address;
  final String description;
  final String reason;
  final double latitude;
  final double longitude;
  final double rating;
  final String imageUrl;
  final String photoReference;
  final String contactNumber;
  final String websiteUrl;
  final String openingHoursText;
  final int userRatingsTotal;
  final String category;
  final List<String> placeTypes;
  final double distanceKm;

  String get distanceText {
    if (distanceKm < 1) return '${(distanceKm * 1000).round()}m away';
    return '${distanceKm.toStringAsFixed(1)}km away';
  }

  String get imageForCard {
    if (imageUrl.isNotEmpty) return imageUrl;
    return CitySpotSuggestionService.buildStaticMapUrl(
      latitude: latitude,
      longitude: longitude,
    );
  }

  String get barangayHint {
    if (_barangayHint.trim().isNotEmpty) return _barangayHint.trim();
    if (address.trim().isEmpty) return '';
    final parts = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '';
    return parts.first;
  }
}

class CityMunicipalityArea {
  const CityMunicipalityArea({required this.name, required this.center});

  final String name;
  final LatLng center;
}

class CitySpotSuggestionService {
  CitySpotSuggestionService({String? apiKey})
    : apiKey = apiKey ?? resolveApiKey();

  static const LatLng defaultBulacanCenter = LatLng(14.9597, 120.9206);

  final String apiKey;

  /// Reads `GOOGLE_MAPS_API_KEY` or `GOOGLE_PLACES_API_KEY` from `.env`.
  /// Callers receive an empty key when configuration is unavailable.
  static String resolveApiKey() {
    try {
      final fromEnv =
          (dotenv.env['GOOGLE_MAPS_API_KEY'] ??
                  dotenv.env['GOOGLE_PLACES_API_KEY'] ??
                  '')
              .trim();
      if (fromEnv.isNotEmpty) return fromEnv;
    } catch (_) {
      // dotenv may not be loaded in tests.
    }
    return '';
  }

  Future<List<CitySpotSuggestion>> fetchSuggestions({
    required String city,
    String province = 'Bulacan',
    LatLng? center,
    int limit = 8,
    Set<String> excludeTitles = const {},
  }) async {
    final trimmedCity = city.trim();
    if (trimmedCity.isEmpty || apiKey.trim().isEmpty) return const [];

    final effectiveProvince = province.trim().isEmpty
        ? 'Bulacan'
        : province.trim();
    final effectiveCenter =
        center ?? centerForCity(trimmedCity) ?? defaultBulacanCenter;
    final textSpecs = _spotSearchSpecs(trimmedCity, effectiveProvince);
    final fallbackSpecs = _fallbackTextSearchSpecs(
      trimmedCity,
      effectiveProvince,
    );
    final nearbySpecs = _nearbySearchSpecs();

    final futures = <Future<List<CitySpotSuggestion>>>[
      for (final spec in textSpecs)
        _fetchGoogleTextSearch(
          spec: spec,
          city: trimmedCity,
          province: effectiveProvince,
          center: effectiveCenter,
        ),
      for (final spec in fallbackSpecs)
        _fetchGoogleTextSearch(
          spec: spec,
          city: trimmedCity,
          province: effectiveProvince,
          center: effectiveCenter,
        ),
      for (final spec in nearbySpecs)
        _fetchGoogleNearbySearch(
          spec: spec,
          city: trimmedCity,
          province: effectiveProvince,
          center: effectiveCenter,
        ),
    ];

    final batches = await Future.wait(futures);

    final excluded = excludeTitles
        .map(normalizeText)
        .where((value) => value.isNotEmpty)
        .toSet();
    final suggestionsById = <String, CitySpotSuggestion>{};
    final seenTitles = <String>{...excluded};

    for (final batch in batches) {
      for (final suggestion in batch) {
        final normalizedTitle = normalizeText(suggestion.title);
        if (normalizedTitle.isEmpty || seenTitles.contains(normalizedTitle)) {
          continue;
        }
        seenTitles.add(normalizedTitle);
        suggestionsById.putIfAbsent(suggestion.id, () => suggestion);
      }
    }

    final balanced = _balancedSpots(suggestionsById.values.toList(), limit);
    return _enrichSuggestionsWithPlaceDetails(
      balanced,
      city: trimmedCity,
      province: effectiveProvince,
      center: effectiveCenter,
    );
  }

  Future<List<CitySpotSuggestion>> searchPlaces({
    required String query,
    required String city,
    String province = 'Bulacan',
    LatLng? center,
    int limit = 5,
  }) async {
    final trimmedQuery = query.trim();
    final trimmedCity = city.trim();
    if (trimmedQuery.length < 3 ||
        trimmedCity.isEmpty ||
        apiKey.trim().isEmpty) {
      return const [];
    }

    final effectiveProvince = province.trim().isEmpty
        ? 'Bulacan'
        : province.trim();
    final effectiveCenter =
        center ?? centerForCity(trimmedCity) ?? defaultBulacanCenter;
    final results = await _fetchGoogleTextSearch(
      spec: _SpotSearchSpec(
        tag: 'Address',
        query: '$trimmedQuery, $trimmedCity, $effectiveProvince, Philippines',
      ),
      city: trimmedCity,
      province: effectiveProvince,
      center: effectiveCenter,
    );
    return _enrichSuggestionsWithPlaceDetails(
      results.take(limit).toList(growable: false),
      city: trimmedCity,
      province: effectiveProvince,
      center: effectiveCenter,
    );
  }

  LatLng? centerForCity(String city) {
    final normalizedCity = normalizeText(city);
    for (final area in bulacanMunicipalities) {
      if (cityAliases(area.name).contains(normalizedCity)) {
        return area.center;
      }
    }
    return null;
  }

  List<String> citySearchNames(String city) {
    final names = cityAliases(city).toList(growable: false);
    return names
        .map((alias) => denormalizeCityAlias(alias, fallback: city))
        .toSet()
        .toList(growable: false);
  }

  static String buildStaticMapUrl({
    required double latitude,
    required double longitude,
    String? apiKey,
  }) {
    final key = apiKey ?? resolveApiKey();
    if (key.trim().isEmpty) return '';
    final marker = Uri.encodeComponent('$latitude,$longitude');
    return 'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$marker'
        '&zoom=15'
        '&size=640x420'
        '&scale=2'
        '&maptype=roadmap'
        '&markers=color:red%7C$marker'
        '&key=$key';
  }

  Future<List<CitySpotSuggestion>> _fetchGoogleTextSearch({
    required _SpotSearchSpec spec,
    required String city,
    required String province,
    required LatLng center,
  }) async {
    try {
      final query = Uri.encodeQueryComponent(spec.query);
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json'
        '?query=$query'
        '&location=${center.latitude},${center.longitude}'
        '&radius=25000'
        '&region=ph'
        '&key=$apiKey',
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final status = body['status']?.toString() ?? '';

      if (status != 'OK' && status != 'ZERO_RESULTS') {
        _logPlacesApiIssue('textsearch', spec.tag, status, body);
        return const [];
      }

      final results = (body['results'] as List?) ?? const [];
      final suggestions = _parsePlacesResults(
        results: results,
        city: city,
        province: province,
        center: center,
        fallbackTag: spec.tag,
      );

      suggestions.sort(_compareSpotQuality);
      return suggestions.take(6).toList(growable: false);
    } catch (error, stack) {
      developer.log(
        'Google Places text search failed (${spec.tag}): $error',
        name: 'CitySpotSuggestionService',
        stackTrace: stack,
      );
      return const [];
    }
  }

  Future<List<CitySpotSuggestion>> _fetchGoogleNearbySearch({
    required _NearbySearchSpec spec,
    required String city,
    required String province,
    required LatLng center,
  }) async {
    try {
      final keyword = Uri.encodeQueryComponent(spec.keyword);
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=${center.latitude},${center.longitude}'
        '&radius=25000'
        '&keyword=$keyword'
        '&region=ph'
        '&key=$apiKey',
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final status = body['status']?.toString() ?? '';
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        _logPlacesApiIssue('nearbysearch', spec.tag, status, body);
        return const [];
      }

      final results = (body['results'] as List?) ?? const [];
      final suggestions = _parsePlacesResults(
        results: results,
        city: city,
        province: province,
        center: center,
        fallbackTag: spec.tag,
      );

      suggestions.sort(_compareSpotQuality);
      return suggestions.take(6).toList(growable: false);
    } catch (error, stack) {
      developer.log(
        'Google Places nearby search failed (${spec.tag}): $error',
        name: 'CitySpotSuggestionService',
        stackTrace: stack,
      );
      return const [];
    }
  }

  Future<List<CitySpotSuggestion>> _enrichSuggestionsWithPlaceDetails(
    List<CitySpotSuggestion> suggestions, {
    required String city,
    required String province,
    required LatLng center,
  }) async {
    if (suggestions.isEmpty) return const [];

    final futures = suggestions.map(
      (suggestion) => _fetchPlaceDetailsSuggestion(
        suggestion: suggestion,
        city: city,
        province: province,
        center: center,
      ),
    );

    return Future.wait(futures);
  }

  Future<CitySpotSuggestion> _fetchPlaceDetailsSuggestion({
    required CitySpotSuggestion suggestion,
    required String city,
    required String province,
    required LatLng center,
  }) async {
    if (suggestion.id.trim().isEmpty || suggestion.id.startsWith('ai-')) {
      return suggestion;
    }

    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${Uri.encodeQueryComponent(suggestion.id)}'
        '&fields='
        'place_id,'
        'name,'
        'formatted_address,'
        'geometry/location,'
        'rating,'
        'user_ratings_total,'
        'website,'
        'formatted_phone_number,'
        'editorial_summary,'
        'opening_hours/weekday_text,'
        'address_components,'
        'photos/photo_reference,'
        'types,'
        'business_status'
        '&region=ph'
        '&key=$apiKey',
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return suggestion;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final status = body['status']?.toString() ?? '';
      if (status != 'OK') {
        _logPlacesApiIssue('details', suggestion.category, status, body);
        return suggestion;
      }

      final result = body['result'];
      if (result is! Map<String, dynamic>) return suggestion;

      return _buildSuggestionFromDetails(
        suggestion: suggestion,
        details: result,
        city: city,
        province: province,
        center: center,
      );
    } catch (error, stack) {
      developer.log(
        'Google Places details failed (${suggestion.title}): $error',
        name: 'CitySpotSuggestionService',
        stackTrace: stack,
      );
      return suggestion;
    }
  }

  void _logPlacesApiIssue(
    String endpoint,
    String tag,
    String status,
    Map<String, dynamic> body,
  ) {
    final message = body['error_message']?.toString() ?? '';
    developer.log(
      'Google Places $endpoint [$tag] returned $status'
      '${message.isEmpty ? '' : ': $message'}',
      name: 'CitySpotSuggestionService',
    );
  }

  List<CitySpotSuggestion> _parsePlacesResults({
    required List results,
    required String city,
    required String province,
    required LatLng center,
    required String fallbackTag,
  }) {
    final suggestions = <CitySpotSuggestion>[];

    for (final raw in results) {
      final item = raw as Map<String, dynamic>;
      final geometry = item['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      if (location == null) continue;

      final name = (item['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;

      final address =
          (item['formatted_address'] as String?)?.trim() ??
          (item['vicinity'] as String?)?.trim() ??
          '';
      final lat = ((location['lat'] as num?) ?? center.latitude).toDouble();
      final lng = ((location['lng'] as num?) ?? center.longitude).toDouble();
      if (!_isPlaceInSelectedCity(
        address: address,
        city: city,
        province: province,
        latitude: lat,
        longitude: lng,
        center: center,
      )) {
        continue;
      }
      final rating = ((item['rating'] as num?) ?? 4.5).toDouble();
      final placeId = (item['place_id'] as String?) ?? name;
      final types = ((item['types'] as List?) ?? const [])
          .map((entry) => entry.toString())
          .toList(growable: false);
      if (!_isAcceptedPlace(types, name)) continue;

      final category = _tagFromGoogleTypes(types, name, fallbackTag);
      final photos = (item['photos'] as List?) ?? const [];
      final photoRef = photos.isEmpty
          ? ''
          : ((photos.first as Map)['photo_reference'] as String?) ?? '';
      final imageUrl = photoRef.isEmpty
          ? ''
          : 'https://maps.googleapis.com/maps/api/place/photo'
                '?maxwidth=900'
                '&photo_reference=${Uri.encodeComponent(photoRef)}'
                '&key=$apiKey';

      suggestions.add(
        CitySpotSuggestion(
          id: placeId,
          title: name,
          city: city,
          province: province,
          address: address,
          description: _buildDescription(
            city: city,
            province: province,
            category: category,
          ),
          reason: _buildReason(city: city, category: category, rating: rating),
          latitude: lat,
          longitude: lng,
          rating: rating,
          imageUrl: imageUrl,
          photoReference: photoRef,
          category: category,
          placeTypes: types,
          distanceKm: _haversineKm(center.latitude, center.longitude, lat, lng),
        ),
      );
    }

    return suggestions;
  }

  CitySpotSuggestion _buildSuggestionFromDetails({
    required CitySpotSuggestion suggestion,
    required Map<String, dynamic> details,
    required String city,
    required String province,
    required LatLng center,
  }) {
    final geometry = details['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;
    final lat = ((location?['lat'] as num?) ?? suggestion.latitude).toDouble();
    final lng = ((location?['lng'] as num?) ?? suggestion.longitude).toDouble();
    final address =
        (details['formatted_address'] as String?)?.trim() ?? suggestion.address;
    final components =
        (details['address_components'] as List?)
            ?.whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    final placeTypes = ((details['types'] as List?) ?? suggestion.placeTypes)
        .map((entry) => entry.toString())
        .toList(growable: false);

    if (!_isPlaceInSelectedCity(
      address: address,
      city: city,
      province: province,
      latitude: lat,
      longitude: lng,
      center: center,
    )) {
      return suggestion;
    }

    final rating = ((details['rating'] as num?) ?? suggestion.rating)
        .toDouble();
    final photoRows = (details['photos'] as List?) ?? const [];
    final photoRef = photoRows.isEmpty
        ? suggestion.photoReference
        : ((photoRows.first as Map)['photo_reference'] as String?) ??
              suggestion.photoReference;
    final imageUrl = photoRef.isEmpty
        ? suggestion.imageUrl
        : 'https://maps.googleapis.com/maps/api/place/photo'
              '?maxwidth=900'
              '&photo_reference=${Uri.encodeComponent(photoRef)}'
              '&key=$apiKey';
    final category = _tagFromGoogleTypes(
      placeTypes,
      (details['name'] as String?)?.trim() ?? suggestion.title,
      suggestion.category,
    );
    final editorial =
        ((details['editorial_summary'] as Map?)?['overview'] as String?)
            ?.trim();

    return CitySpotSuggestion(
      id: (details['place_id'] as String?) ?? suggestion.id,
      title: (details['name'] as String?)?.trim() ?? suggestion.title,
      city: city,
      province: province,
      barangayHint:
          _addressComponent(components, const [
            'sublocality_level_1',
            'sublocality',
            'neighborhood',
          ]) ??
          suggestion.barangayHint,
      address: address,
      description: editorial?.isNotEmpty == true
          ? editorial!
          : suggestion.description,
      reason: _buildReason(city: city, category: category, rating: rating),
      latitude: lat,
      longitude: lng,
      rating: rating,
      imageUrl: imageUrl,
      photoReference: photoRef,
      contactNumber:
          (details['formatted_phone_number'] as String?)?.trim() ??
          suggestion.contactNumber,
      websiteUrl:
          (details['website'] as String?)?.trim() ?? suggestion.websiteUrl,
      openingHoursText:
          _openingHoursSummary(details) ?? suggestion.openingHoursText,
      userRatingsTotal:
          ((details['user_ratings_total'] as num?)?.toInt()) ??
          suggestion.userRatingsTotal,
      category: category,
      placeTypes: placeTypes,
      distanceKm: _haversineKm(center.latitude, center.longitude, lat, lng),
    );
  }

  List<_SpotSearchSpec> _spotSearchSpecs(String city, String province) {
    final where = '$city $province Philippines';
    return [
      _SpotSearchSpec(
        tag: 'Historical',
        query: 'famous historical landmarks heritage sites monuments in $where',
      ),
      _SpotSearchSpec(
        tag: 'Nature',
        query: 'nature parks gardens scenic tourist attractions in $where',
      ),
      _SpotSearchSpec(
        tag: 'Religious',
        query: 'famous churches cathedrals pilgrimage sites in $where',
      ),
      _SpotSearchSpec(
        tag: 'Cultural',
        query: 'museums cultural centers galleries in $where',
      ),
      _SpotSearchSpec(
        tag: 'Adventure',
        query:
            'adventure parks outdoor activities hiking zipline resorts in $where',
      ),
      _SpotSearchSpec(
        tag: 'Food',
        query: 'popular local restaurants cafes delicacies in $where',
      ),
    ];
  }

  List<_SpotSearchSpec> _fallbackTextSearchSpecs(String city, String province) {
    return [
      _SpotSearchSpec(
        tag: 'Historical',
        query: '$city $province tourist attractions',
      ),
      _SpotSearchSpec(tag: 'Cultural', query: '$city $province famous spots'),
      _SpotSearchSpec(tag: 'Historical', query: '$city historical places'),
      _SpotSearchSpec(tag: 'Nature', query: '$city nature spots'),
    ];
  }

  List<_NearbySearchSpec> _nearbySearchSpecs() {
    return const [
      _NearbySearchSpec(tag: 'Historical', keyword: 'tourist attraction'),
      _NearbySearchSpec(tag: 'Cultural', keyword: 'point of interest'),
    ];
  }

  List<CitySpotSuggestion> _balancedSpots(
    List<CitySpotSuggestion> spots,
    int limit,
  ) {
    final buckets = <String, List<CitySpotSuggestion>>{
      for (final tag in _spotTagOrder) tag: <CitySpotSuggestion>[],
    };

    for (final spot in spots) {
      (buckets[spot.category] ??= <CitySpotSuggestion>[]).add(spot);
    }

    for (final bucket in buckets.values) {
      bucket.sort(_compareSpotQuality);
    }

    final result = <CitySpotSuggestion>[];
    final counts = <String, int>{};
    while (result.length < limit) {
      var added = false;

      for (final tag in _spotTagOrder) {
        final bucket = buckets[tag];
        if (bucket == null || bucket.isEmpty) continue;

        result.add(bucket.removeAt(0));
        counts[tag] = (counts[tag] ?? 0) + 1;
        added = true;

        if (result.length == limit) break;
      }

      if (!added) break;
    }

    return result;
  }

  int _compareSpotQuality(CitySpotSuggestion a, CitySpotSuggestion b) {
    final aScore = a.rating - a.distanceKm / 80;
    final bScore = b.rating - b.distanceKm / 80;
    return bScore.compareTo(aScore);
  }

  String _tagFromGoogleTypes(
    List<String> types,
    String title, [
    String fallbackTag = 'Historical',
  ]) {
    final text = '${types.join(' ')} $title'.toLowerCase();

    if (text.contains('church') || text.contains('place_of_worship')) {
      return 'Religious';
    }
    if (text.contains('museum') ||
        text.contains('gallery') ||
        text.contains('cultural')) {
      return 'Cultural';
    }
    if (text.contains('heritage') ||
        text.contains('historical') ||
        text.contains('monument') ||
        text.contains('landmark')) {
      return 'Historical';
    }
    if (text.contains('park') ||
        text.contains('garden') ||
        text.contains('natural') ||
        text.contains('waterfall') ||
        text.contains('mountain') ||
        text.contains('scenic')) {
      return 'Nature';
    }
    if (text.contains('sports') ||
        text.contains('stadium') ||
        text.contains('arena') ||
        text.contains('court') ||
        text.contains('gym') ||
        text.contains('swimming_pool') ||
        text.contains('recreation') ||
        text.contains('adventure') ||
        text.contains('campground') ||
        text.contains('rv_park') ||
        text.contains('hiking') ||
        text.contains('resort')) {
      return 'Adventure';
    }
    if (text.contains('cafe') ||
        text.contains('coffee') ||
        text.contains('bakery') ||
        text.contains('pastry')) {
      return 'Cafe';
    }
    if (text.contains('restaurant') || text.contains('food')) {
      return 'Food';
    }

    return fallbackTag;
  }

  bool _isAcceptedPlace(List<String> types, String title) {
    final typeSet = types.map((type) => type.toLowerCase()).toSet();
    if (typeSet.any(_acceptedGooglePlaceTypes.contains)) {
      return true;
    }

    final text = '${types.join(' ')} $title'.toLowerCase();
    return text.contains('tourist') ||
        text.contains('heritage') ||
        text.contains('church') ||
        text.contains('museum') ||
        text.contains('park') ||
        text.contains('nature') ||
        text.contains('adventure') ||
        text.contains('cafe') ||
        text.contains('restaurant') ||
        text.contains('food');
  }

  bool _isPlaceInSelectedCity({
    required String address,
    required String city,
    required String province,
    required double latitude,
    required double longitude,
    required LatLng center,
  }) {
    final normalizedAddress = normalizeText(address);
    final selectedProvince = normalizeText(province);
    final aliases = cityAliases(city);

    if (aliases.isEmpty) return false;

    final distanceKm = _haversineKm(
      center.latitude,
      center.longitude,
      latitude,
      longitude,
    );

    // Prefer geographic proximity to the selected municipality center.
    // Google addresses often omit "Bulacan", so do not require it in text.
    if (distanceKm <= 25) return true;

    if (normalizedAddress.isNotEmpty &&
        aliases.any(normalizedAddress.contains)) {
      return true;
    }

    if (selectedProvince.isNotEmpty &&
        normalizedAddress.contains(selectedProvince) &&
        distanceKm <= 40) {
      return true;
    }

    return false;
  }

  String _buildDescription({
    required String city,
    required String province,
    required String category,
  }) {
    return '$category destination suggestion for visitors exploring $city, $province.';
  }

  String _buildReason({
    required String city,
    required String category,
    required double rating,
  }) {
    if (rating > 0) {
      return 'Suggested because it matches the $category category in $city and currently shows strong public interest on Google Places.';
    }
    return 'Suggested because it matches the $category category and appears relevant for visitors in $city.';
  }

  static String normalizeText(String value) {
    return value
        .toLowerCase()
        .replaceAll('Ã±', 'n')
        .replaceAll('ñ', 'n')
        .replaceAll('ñ', 'n')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .replaceAll(',', '')
        .replaceAll('.', '');
  }

  static Set<String> cityAliases(String city) {
    final normalized = normalizeText(city);
    if (normalized.isEmpty) return const {};

    final aliases = <String>{normalized};
    const aliasMap = {
      'baliwag': {'baliuag'},
      'baliuag': {'baliwag'},
      'santamaria': {'stamaria'},
      'stamaria': {'santamaria'},
      'sanjosedelmonte': {'sjdm'},
      'sjdm': {'sanjosedelmonte'},
      'donaremediostrinidad': {'drt'},
      'drt': {'donaremediostrinidad'},
      'bulakan': {'bulacan'},
      'bulacan': {'bulakan'},
    };
    aliases.addAll(aliasMap[normalized] ?? const {});
    return aliases;
  }

  static String denormalizeCityAlias(String alias, {required String fallback}) {
    switch (alias) {
      case 'baliuag':
        return 'Baliuag';
      case 'baliwag':
        return 'Baliwag';
      case 'santamaria':
        return 'Santa Maria';
      case 'stamaria':
        return 'Sta Maria';
      case 'sanjosedelmonte':
        return 'San Jose del Monte';
      case 'sjdm':
        return 'SJDM';
      case 'donaremediostrinidad':
        return 'Dona Remedios Trinidad';
      case 'drt':
        return 'DRT';
      case 'bulakan':
        return 'Bulakan';
      case 'bulacan':
        return 'Bulacan';
      default:
        return fallback;
    }
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
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

  String? _addressComponent(
    List<Map<String, dynamic>> components,
    List<String> acceptedTypes,
  ) {
    for (final component in components) {
      final types = ((component['types'] as List?) ?? const [])
          .map((entry) => entry.toString())
          .toSet();
      if (types.any(acceptedTypes.contains)) {
        final longName = component['long_name']?.toString().trim() ?? '';
        if (longName.isNotEmpty) return longName;
      }
    }
    return null;
  }

  String? _openingHoursSummary(Map<String, dynamic> details) {
    final openingHours = details['opening_hours'];
    if (openingHours is! Map) return null;
    final weekdayText = (openingHours['weekday_text'] as List?)
        ?.map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (weekdayText == null || weekdayText.isEmpty) return null;
    return weekdayText.first;
  }

  static List<String> barangaysForCity(String city) {
    final normalized = normalizeText(city);
    for (final entry in _barangaysByCity.entries) {
      if (cityAliases(entry.key).contains(normalized)) {
        return entry.value;
      }
    }
    return [];
  }
}

class _SpotSearchSpec {
  const _SpotSearchSpec({required this.tag, required this.query});

  final String tag;
  final String query;
}

const List<String> _spotTagOrder = [
  'Historical',
  'Nature',
  'Religious',
  'Food',
  'Cafe',
  'Adventure',
  'Cultural',
];

const Set<String> _acceptedGooglePlaceTypes = {
  'tourist_attraction',
  'point_of_interest',
  'establishment',
  'park',
  'church',
  'museum',
  'place_of_worship',
  'restaurant',
  'cafe',
  'bakery',
  'natural_feature',
  'art_gallery',
  'amusement_park',
  'aquarium',
  'zoo',
  'shopping_mall',
  'lodging',
  'spa',
  'bar',
  'night_club',
};

class _NearbySearchSpec {
  const _NearbySearchSpec({required this.tag, required this.keyword});

  final String tag;
  final String keyword;
}

const Map<String, List<String>> _barangaysByCity = {
  'Malolos': [
    'Atlag',
    'Bagna',
    'Bagong Bayan',
    'Balayong',
    'Balite',
    'Bangkal',
    'Barihan',
    'Bulihan',
    'Bungahan',
    'Caingin',
    'Calero',
    'Caliligawan',
    'Canalate',
    'Caniogan',
    'Catmon',
    'Gen. Tinio',
    'Lambakin',
    'Longos',
    'Look 1st',
    'Look 2nd',
    'Lugam',
    'Mabolo',
    'Matimbo',
    'Mojon',
    'Namayan',
    'Niugan',
    'Pamarawan',
    'Panasahan',
    'Pinagbakahan',
    'San Agustin',
    'San Gabriel',
    'San Juan',
    'San Pablo',
    'San Vicente',
    'Santiago',
    'Santo Cristo',
    'Santo Niño',
    'Santo Rosario',
    'Santol',
    'Sumapang Bata',
    'Sumapang Matanda',
    'Taal',
    'Taytay',
    'Tikay',
  ],
  'Baliwag': [
    'Bagong Nayon',
    'Barangca',
    'Calantipay',
    'Catulinan',
    'Concepcion',
    'Hinukay',
    'Makinabang',
    'Matangtubig',
    'Pagala',
    'Paitan',
    'Piel',
    'Pinagbarilan',
    'Poblacion',
    'Sabang',
    'San Jose',
    'San Roque',
    'Santa Barbara',
    'Santo Cristo',
    'Santo Niño',
    'Subic',
    'Sulivan',
    'Tangos',
    'Tarcan',
    'Tiaong',
    'Tibagan',
    'Tilapayong',
    'Virgen delas Flores',
  ],
  // Add more cities as needed
};

const List<CityMunicipalityArea> bulacanMunicipalities = [
  CityMunicipalityArea(name: 'Bustos', center: LatLng(14.9597, 120.9206)),
  CityMunicipalityArea(name: 'Baliwag', center: LatLng(14.9547, 120.8969)),
  CityMunicipalityArea(name: 'Malolos', center: LatLng(14.8434, 120.8114)),
  CityMunicipalityArea(name: 'Pulilan', center: LatLng(14.9017, 120.8492)),
  CityMunicipalityArea(name: 'Plaridel', center: LatLng(14.8873, 120.8572)),
  CityMunicipalityArea(name: 'San Rafael', center: LatLng(15.0265, 120.9283)),
  CityMunicipalityArea(
    name: 'San Ildefonso',
    center: LatLng(15.0809, 120.9410),
  ),
  CityMunicipalityArea(name: 'San Miguel', center: LatLng(15.1458, 120.9783)),
  CityMunicipalityArea(name: 'Calumpit', center: LatLng(14.9164, 120.7658)),
  CityMunicipalityArea(name: 'Hagonoy', center: LatLng(14.8340, 120.7328)),
  CityMunicipalityArea(name: 'Paombong', center: LatLng(14.8319, 120.7897)),
  CityMunicipalityArea(name: 'Guiguinto', center: LatLng(14.8333, 120.8833)),
  CityMunicipalityArea(name: 'Balagtas', center: LatLng(14.8167, 120.8667)),
  CityMunicipalityArea(name: 'Bocaue', center: LatLng(14.7983, 120.9261)),
  CityMunicipalityArea(name: 'Marilao', center: LatLng(14.7581, 120.9481)),
  CityMunicipalityArea(name: 'Meycauayan', center: LatLng(14.7369, 120.9608)),
  CityMunicipalityArea(name: 'Norzagaray', center: LatLng(14.9109, 121.0493)),
  CityMunicipalityArea(name: 'Santa Maria', center: LatLng(14.8208, 120.9636)),
  CityMunicipalityArea(name: 'Angat', center: LatLng(14.9285, 121.0292)),
  CityMunicipalityArea(name: 'Pandi', center: LatLng(14.8650, 120.9572)),
  CityMunicipalityArea(name: 'Obando', center: LatLng(14.7098, 120.9362)),
  CityMunicipalityArea(name: 'Bulakan', center: LatLng(14.7928, 120.8789)),
  CityMunicipalityArea(
    name: 'Dona Remedios Trinidad',
    center: LatLng(15.0005, 121.0838),
  ),
  CityMunicipalityArea(
    name: 'San Jose del Monte',
    center: LatLng(14.8139, 121.0453),
  ),
];
