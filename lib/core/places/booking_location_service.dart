import 'dart:convert';

import 'package:flutter/services.dart';
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

  /// Explicit country information takes priority over formatted-address text.
  bool get isPhilippines {
    if (countryCode.isNotEmpty) {
      return countryCode.toUpperCase() == 'PH';
    }

    if (country.isNotEmpty) {
      return country.toLowerCase() == 'philippines';
    }

    return RegExp(
      r'(^|,)\s*Philippines\s*$',
      caseSensitive: false,
    ).hasMatch(address);
  }
}

class BookingLocationException implements Exception {
  const BookingLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Google Places Autocomplete / Place Details / Geocoding integration used
/// specifically by the tour-package pickup and drop-off location picker.
///
/// API-key resolution order:
///
/// 1. Explicit [apiKey] passed to this service.
/// 2. GOOGLE_MAPS_API_KEY supplied using --dart-define.
/// 3. Android/iOS native configuration via MethodChannel.
///
/// On Android the native configuration is populated by Gradle from .env,
/// allowing normal `flutter run` to use the configured Maps/Places key.
class BookingLocationService {
  BookingLocationService({String? apiKey, http.Client? client})
    : _resolvedApiKey = (apiKey ?? CitySpotSuggestionService.resolveApiKey())
          .trim(),
      _client = client ?? http.Client(),
      _ownsClient = client == null;

  static const MethodChannel _configChannel = MethodChannel(
    'touristrike/config',
  );

  String _resolvedApiKey;

  final http.Client _client;
  final bool _ownsClient;

  /// Exposed mainly for diagnostics/tests.
  String get apiKey => _resolvedApiKey;

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  // ===========================================================================
  // API KEY
  // ===========================================================================

  Future<String> _loadApiKey() async {
    if (_resolvedApiKey.trim().isNotEmpty) {
      return _resolvedApiKey.trim();
    }

    try {
      final nativeKey = await _configChannel.invokeMethod<String>(
        'getGoogleMapsApiKey',
      );

      if (nativeKey != null && nativeKey.trim().isNotEmpty) {
        _resolvedApiKey = nativeKey.trim();
      }
    } catch (_) {
      // Web/desktop targets may not install the native configuration channel.
      // In those environments, use --dart-define or inject apiKey explicitly.
    }

    return _resolvedApiKey.trim();
  }

  // ===========================================================================
  // HTTP
  // ===========================================================================

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, String> params,
  ) async {
    final effectiveApiKey = await _loadApiKey();

    if (effectiveApiKey.isEmpty) {
      throw const BookingLocationException(
        'Location search is not configured. Please contact support.',
      );
    }

    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/$path/json', {
        ...params,
        'key': effectiveApiKey,
        'language': 'en',
      });

      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 429) {
        throw const BookingLocationException(
          'Location search is temporarily busy. Please retry shortly.',
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const BookingLocationException(
          'Google location service rejected the configured API key.',
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const BookingLocationException(
          'Location service is unavailable. Please retry.',
        );
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw const BookingLocationException(
          'Location service returned an invalid response. Please retry.',
        );
      }

      final body = decoded;

      final status = body['status']?.toString() ?? '';

      if (status == 'OK' || status == 'ZERO_RESULTS') {
        return body;
      }

      if (status == 'REQUEST_DENIED') {
        throw const BookingLocationException(
          'Google location service rejected the configured API key or API restrictions.',
        );
      }

      if (status == 'OVER_QUERY_LIMIT') {
        throw const BookingLocationException(
          'Location search request limit was reached. Please retry shortly.',
        );
      }

      if (status == 'INVALID_REQUEST') {
        throw const BookingLocationException(
          'Google could not process this location request. Please try again.',
        );
      }

      throw const BookingLocationException(
        'Location service could not complete the request. Please retry.',
      );
    } on BookingLocationException {
      rethrow;
    } catch (_) {
      // Never expose URLs or API keys through exception text.
      throw const BookingLocationException(
        'Could not reach the location service. Check your connection and retry.',
      );
    }
  }

  // ===========================================================================
  // AUTOCOMPLETE
  // ===========================================================================

  Future<List<BookingPlaceSuggestion>> search(String query) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return const [];
    }

    final body = await _request('place/autocomplete', {
      'input': trimmedQuery,
      'components': 'country:ph',
    });

    final predictions = (body['predictions'] as List?) ?? const [];

    return predictions
        .whereType<Map>()
        .where(
          (prediction) =>
              (prediction['place_id'] as String? ?? '').trim().isNotEmpty,
        )
        .take(5)
        .map(
          (prediction) => BookingPlaceSuggestion(
            placeId: prediction['place_id'] as String,
            description: prediction['description'] as String? ?? '',
          ),
        )
        .toList(growable: false);
  }

  // ===========================================================================
  // PARSING
  // ===========================================================================

  BookingLocation _parse(
    Map result, {
    String? placeId,
    double? lat,
    double? lng,
    String fallbackAddress = '',
  }) {
    final geometry = result['geometry'] as Map?;
    final location = geometry?['location'] as Map?;

    final latitude = lat ?? (location?['lat'] as num?)?.toDouble();

    final longitude = lng ?? (location?['lng'] as num?)?.toDouble();

    if (latitude == null || longitude == null) {
      throw const BookingLocationException(
        'This location has no coordinates. Please select another result.',
      );
    }

    final components = <String, Map>{};

    final addressComponents =
        (result['address_components'] as List?) ?? const [];

    for (final component in addressComponents.whereType<Map>()) {
      final types = (component['types'] as List?) ?? const [];

      for (final type in types) {
        components[type.toString()] = component;
      }
    }

    String name(String type) {
      return (components[type]?['long_name'] as String? ?? '').trim();
    }

    final provinceLevel2 = name('administrative_area_level_2');
    final provinceLevel1 = name('administrative_area_level_1');

    final locality = name('locality');
    final administrativeLevel3 = name('administrative_area_level_3');

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
      province: provinceLevel2.isNotEmpty ? provinceLevel2 : provinceLevel1,
      locality: locality.isNotEmpty ? locality : administrativeLevel3,
    );

    if (!parsed.hasValidCoordinates) {
      throw const BookingLocationException(
        'This location has invalid coordinates. Please select another result.',
      );
    }

    return parsed;
  }

  // ===========================================================================
  // VALIDATION
  // ===========================================================================

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

  // ===========================================================================
  // PLACE DETAILS
  // ===========================================================================

  Future<BookingLocation> select(BookingPlaceSuggestion suggestion) async {
    final body = await _request('place/details', {
      'place_id': suggestion.placeId,
      'fields': 'geometry,formatted_address,address_components,name,place_id',
    });

    final result = body['result'];

    if (result is! Map) {
      throw const BookingLocationException(
        'Unable to resolve this place. Please select another result.',
      );
    }

    final place = _parse(
      result,
      placeId: suggestion.placeId,
      fallbackAddress: suggestion.description,
    );

    if (place.countryCode.isNotEmpty) {
      return _validate(place);
    }

    // If Google Place Details did not provide explicit country metadata,
    // resolve the coordinates through reverse geocoding rather than trusting
    // typed/display text.
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

  // ===========================================================================
  // CURRENT LOCATION / REVERSE GEOCODING
  // ===========================================================================

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

    final first = results.first;

    if (first is! Map) {
      throw const BookingLocationException(
        'Could not verify this location. Please retry.',
      );
    }

    // Preserve the actual GPS coordinates rather than replacing them with
    // Google's geocoder centroid.
    return _validate(_parse(first, lat: latitude, lng: longitude));
  }
}
