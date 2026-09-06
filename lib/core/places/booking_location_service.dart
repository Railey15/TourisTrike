import 'dart:convert';

import 'package:http/http.dart' as http;

import 'city_spot_suggestions.dart';

class BookingPlaceSuggestion {
  const BookingPlaceSuggestion({
    required this.placeId,
    required this.description,
  });
  final String placeId;
  final String description;
}

class BookingLocation {
  const BookingLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
    this.placeId,
    this.country = '',
    this.countryCode = '',
    this.province = '',
    this.locality = '',
  });
  final String address;
  final double latitude;
  final double longitude;
  final String? placeId;
  final String country;
  final String countryCode;
  final String province;
  final String locality;

  bool get hasValidCoordinates =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;

  // Explicit country evidence always overrides display text.
  bool get isPhilippines => countryCode.isNotEmpty
      ? countryCode.toUpperCase() == 'PH'
      : country.isNotEmpty
      ? country.toLowerCase() == 'philippines'
      : RegExp(
          r'(^|,)\s*Philippines\s*$',
          caseSensitive: false,
        ).hasMatch(address);
}

class BookingLocationException implements Exception {
  const BookingLocationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Existing Google Places Autocomplete/Details and Geocoding REST integration.
/// Kept separate from the field so responses and country validation are testable.
class BookingLocationService {
  BookingLocationService({String? apiKey, http.Client? client})
    : apiKey = apiKey ?? CitySpotSuggestionService.resolveApiKey(),
      _client = client ?? http.Client(),
      _ownsClient = client == null;
  final String apiKey;
  final http.Client _client;
  final bool _ownsClient;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, String> params,
  ) async {
    if (apiKey.trim().isEmpty) {
      throw const BookingLocationException(
        'Location search is not configured. Please contact support.',
      );
    }
    try {
      final response = await _client
          .get(
            Uri.https('maps.googleapis.com', '/maps/api/$path/json', {
              ...params,
              'key': apiKey,
              'language': 'en',
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw const BookingLocationException(
          'Location service is unavailable. Please retry.',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final status = body['status'];
      if (status == 'OK' || status == 'ZERO_RESULTS') return body;
      if (status == 'REQUEST_DENIED') {
        throw const BookingLocationException(
          'Google location service is unavailable. Please contact support or retry later.',
        );
      }
      throw const BookingLocationException(
        'Location service could not complete the request. Please retry.',
      );
    } on BookingLocationException {
      rethrow;
    } catch (_) {
      // Never expose request URLs/API keys through exception text.
      throw const BookingLocationException(
        'Could not reach the location service. Check your connection and retry.',
      );
    }
  }

  Future<List<BookingPlaceSuggestion>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final body = await _request('place/autocomplete', {
      'input': query.trim(),
      'components': 'country:ph',
    });
    return ((body['predictions'] as List?) ?? const [])
        .whereType<Map>()
        .where((p) => (p['place_id'] as String? ?? '').isNotEmpty)
        .take(5)
        .map(
          (p) => BookingPlaceSuggestion(
            placeId: p['place_id'] as String,
            description: p['description'] as String? ?? '',
          ),
        )
        .toList();
  }

  BookingLocation _parse(
    Map result, {
    String? placeId,
    double? lat,
    double? lng,
    String fallbackAddress = '',
  }) {
    final location = (result['geometry'] as Map?)?['location'] as Map?;
    final latitude = lat ?? (location?['lat'] as num?)?.toDouble();
    final longitude = lng ?? (location?['lng'] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      throw const BookingLocationException(
        'This location has no coordinates. Please select another result.',
      );
    }
    final components = <String, Map>{};
    for (final c
        in ((result['address_components'] as List?) ?? const [])
            .whereType<Map>()) {
      for (final type in (c['types'] as List? ?? const [])) {
        components[type.toString()] = c;
      }
    }
    String name(String type) =>
        (components[type]?['long_name'] as String? ?? '').trim();
    final parsed = BookingLocation(
      address: (result['formatted_address'] as String? ?? fallbackAddress)
          .trim(),
      latitude: latitude,
      longitude: longitude,
      placeId: placeId ?? result['place_id'] as String?,
      country: name('country'),
      countryCode: (components['country']?['short_name'] as String? ?? '')
          .trim()
          .toUpperCase(),
      province: name('administrative_area_level_2').isNotEmpty
          ? name('administrative_area_level_2')
          : name('administrative_area_level_1'),
      locality: name('locality').isNotEmpty
          ? name('locality')
          : name('administrative_area_level_3'),
    );
    if (!parsed.hasValidCoordinates) {
      throw const BookingLocationException(
        'This location has invalid coordinates. Please select another result.',
      );
    }
    return parsed;
  }

  BookingLocation _validate(BookingLocation location) {
    if (!location.isPhilippines) {
      throw const BookingLocationException(
        'Please select a valid location within the Philippines.',
      );
    }
    return BookingLocation(
      address: location.address,
      latitude: location.latitude,
      longitude: location.longitude,
      placeId: location.placeId,
      country: location.country.isEmpty ? 'Philippines' : location.country,
      countryCode: 'PH',
      province: location.province,
      locality: location.locality,
    );
  }

  Future<BookingLocation> select(BookingPlaceSuggestion suggestion) async {
    final body = await _request('place/details', {
      'place_id': suggestion.placeId,
      'fields': 'geometry,formatted_address,address_components,name,place_id',
    });
    if (body['result'] is! Map) {
      throw const BookingLocationException(
        'Unable to resolve this place. Please select another result.',
      );
    }
    final place = _parse(
      body['result'] as Map,
      placeId: suggestion.placeId,
      fallbackAddress: suggestion.description,
    );
    if (place.countryCode.isNotEmpty) return _validate(place);
    // Coordinates must be resolved before country fallback; never use typed text.
    final reverse = await currentLocation(place.latitude, place.longitude);
    return _validate(
      BookingLocation(
        address: place.address,
        latitude: place.latitude,
        longitude: place.longitude,
        placeId: place.placeId,
        country: reverse.country,
        countryCode: reverse.countryCode,
        province: reverse.province,
        locality: reverse.locality,
      ),
    );
  }

  Future<BookingLocation> currentLocation(
    double latitude,
    double longitude,
  ) async {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw const BookingLocationException(
        'Invalid GPS coordinates. Please retry.',
      );
    }
    final body = await _request('geocode', {'latlng': '$latitude,$longitude'});
    final results = (body['results'] as List?) ?? const [];
    if (results.isEmpty) {
      throw const BookingLocationException(
        'Could not verify the country at this location. Please retry.',
      );
    }
    // Preserve the GPS fix rather than replacing it with a geocoder centroid.
    return _validate(
      _parse(results.first as Map, lat: latitude, lng: longitude),
    );
  }
}
