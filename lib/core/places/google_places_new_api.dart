import 'dart:convert';

const googlePlacesNewHost = 'places.googleapis.com';

const googlePlacesSearchFieldMask =
    'places.id,'
    'places.displayName,'
    'places.formattedAddress,'
    'places.location,'
    'places.rating,'
    'places.userRatingCount,'
    'places.photos,'
    'places.types,'
    'places.businessStatus';

const googlePlaceDetailsFieldMask =
    'id,'
    'displayName,'
    'formattedAddress,'
    'location,'
    'rating,'
    'userRatingCount,'
    'websiteUri,'
    'nationalPhoneNumber,'
    'editorialSummary,'
    'regularOpeningHours.weekdayDescriptions,'
    'addressComponents,'
    'photos,'
    'types,'
    'businessStatus';

Uri googlePlacesNewUri(String operation, Map<String, String> parameters) {
  return switch (operation) {
    'textSearch' => Uri.https(googlePlacesNewHost, '/v1/places:searchText'),
    'nearbySearch' => Uri.https(googlePlacesNewHost, '/v1/places:searchNearby'),
    'autocomplete' => Uri.https(googlePlacesNewHost, '/v1/places:autocomplete'),
    'details' => Uri.https(
      googlePlacesNewHost,
      '/v1/places/${Uri.encodeComponent(parameters['place_id'] ?? '')}',
      {
        'languageCode': parameters['language'] ?? 'en',
        if ((parameters['region'] ?? '').trim().isNotEmpty)
          'regionCode': parameters['region']!.toUpperCase(),
      },
    ),
    _ => throw ArgumentError.value(operation, 'operation'),
  };
}

Map<String, String> googlePlacesNewHeaders({
  required String apiKey,
  required String operation,
}) {
  return {
    'Content-Type': 'application/json',
    'X-Goog-Api-Key': apiKey,
    if (operation == 'textSearch' || operation == 'nearbySearch')
      'X-Goog-FieldMask': googlePlacesSearchFieldMask,
    if (operation == 'details') 'X-Goog-FieldMask': googlePlaceDetailsFieldMask,
  };
}

String googlePlacesNewRequestBody(
  String operation,
  Map<String, String> parameters,
) {
  final language = parameters['language'] ?? 'en';
  final region = (parameters['region'] ?? 'ph').toUpperCase();
  final location = _parseLocation(parameters['location']);
  final radius = _parseRadius(parameters['radius']);

  final body = switch (operation) {
    'textSearch' => <String, dynamic>{
      'textQuery': parameters['query']?.trim() ?? '',
      'languageCode': language,
      'regionCode': region,
      'pageSize': 20,
      if (location != null)
        'locationBias': {
          'circle': {'center': location, 'radius': radius},
        },
    },
    'nearbySearch' => <String, dynamic>{
      'languageCode': language,
      'regionCode': region,
      'maxResultCount': 20,
      'rankPreference': 'POPULARITY',
      'includedTypes': [_nearbyType(parameters)],
      if (location != null)
        'locationRestriction': {
          'circle': {'center': location, 'radius': radius},
        },
    },
    'autocomplete' => <String, dynamic>{
      'input': parameters['input']?.trim() ?? '',
      'languageCode': language,
      'regionCode': region,
      'includedRegionCodes': ['ph'],
      if (location != null)
        parameters['strictbounds'] == 'true'
            ? 'locationRestriction'
            : 'locationBias': {
          'circle': {'center': location, 'radius': radius},
        },
    },
    _ => <String, dynamic>{},
  };
  return jsonEncode(body);
}

Map<String, dynamic> normalizeGooglePlacesNewResponse(
  String operation,
  Map<String, dynamic> body,
) {
  if (operation == 'textSearch' || operation == 'nearbySearch') {
    final places = (body['places'] as List?) ?? const [];
    return {
      'status': places.isEmpty ? 'ZERO_RESULTS' : 'OK',
      'results': places.whereType<Map>().map(_legacyPlace).toList(),
      if (body['nextPageToken'] != null)
        'next_page_token': body['nextPageToken'],
    };
  }
  if (operation == 'details') {
    return {'status': 'OK', 'result': _legacyPlace(body)};
  }
  if (operation == 'autocomplete') {
    final suggestions = (body['suggestions'] as List?) ?? const [];
    final predictions = <Map<String, dynamic>>[];
    for (final raw in suggestions.whereType<Map>()) {
      final prediction = raw['placePrediction'];
      if (prediction is! Map) continue;
      final placeId = prediction['placeId']?.toString().trim() ?? '';
      final text =
          ((prediction['text'] as Map?)?['text'])?.toString().trim() ?? '';
      if (placeId.isEmpty || text.isEmpty) continue;
      predictions.add({'place_id': placeId, 'description': text});
    }
    return {
      'status': predictions.isEmpty ? 'ZERO_RESULTS' : 'OK',
      'predictions': predictions,
    };
  }
  return body;
}

Map<String, dynamic> _legacyPlace(Map raw) {
  final place = Map<String, dynamic>.from(raw);
  final displayName = place['displayName'];
  final location = place['location'];
  final editorial = place['editorialSummary'];
  final openingHours = place['regularOpeningHours'];
  return {
    'place_id': place['id'],
    'name': displayName is Map ? displayName['text'] : null,
    'formatted_address': place['formattedAddress'],
    if (location is Map)
      'geometry': {
        'location': {'lat': location['latitude'], 'lng': location['longitude']},
      },
    'rating': place['rating'],
    'user_ratings_total': place['userRatingCount'],
    'website': place['websiteUri'],
    'formatted_phone_number': place['nationalPhoneNumber'],
    if (editorial is Map) 'editorial_summary': {'overview': editorial['text']},
    if (openingHours is Map)
      'opening_hours': {'weekday_text': openingHours['weekdayDescriptions']},
    'address_components': ((place['addressComponents'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (component) => {
            'long_name': component['longText'],
            'short_name': component['shortText'],
            'types': component['types'],
          },
        )
        .toList(),
    'photos': ((place['photos'] as List?) ?? const [])
        .whereType<Map>()
        .map((photo) => {'photo_reference': photo['name']})
        .toList(),
    'types': place['types'],
    'business_status': place['businessStatus'],
  }..removeWhere((_, value) => value == null);
}

Map<String, double>? _parseLocation(String? raw) {
  final parts = raw?.split(',') ?? const [];
  if (parts.length != 2) return null;
  final latitude = double.tryParse(parts[0]);
  final longitude = double.tryParse(parts[1]);
  if (latitude == null || longitude == null) return null;
  return {'latitude': latitude, 'longitude': longitude};
}

double _parseRadius(String? raw) {
  final radius = double.tryParse(raw ?? '') ?? 25000;
  return radius.clamp(1, 50000).toDouble();
}

String _nearbyType(Map<String, String> parameters) {
  final value = (parameters['type'] ?? parameters['keyword'] ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(' ', '_');
  return switch (value) {
    'museum' ||
    'park' ||
    'church' ||
    'restaurant' ||
    'cafe' ||
    'tourist_attraction' => value,
    _ => 'tourist_attraction',
  };
}
