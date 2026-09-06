import 'dart:convert';

import 'package:http/http.dart' as http;

import 'google_maps_api_key_resolver.dart';
import 'google_places_errors.dart';

class GooglePlacesGateway {
  GooglePlacesGateway({required this.apiKey}) : _resolvedApiKey = apiKey;

  final String apiKey;
  String _resolvedApiKey;

  Future<String> _loadApiKey() async {
    _resolvedApiKey = await GoogleMapsApiKeyResolver.resolve(
      explicitKey: _resolvedApiKey,
    );
    return _resolvedApiKey;
  }

  Future<Map<String, dynamic>> request(
    String operation,
    Map<String, String> parameters,
  ) async {
    final effectiveApiKey = await _loadApiKey();
    if (effectiveApiKey.isEmpty) {
      throw const GooglePlacesException(
        kind: GooglePlacesFailureKind.notConfigured,
        message: 'Google Places is not configured on this device.',
      );
    }

    final path = switch (operation) {
      'textSearch' => '/maps/api/place/textsearch/json',
      'nearbySearch' => '/maps/api/place/nearbysearch/json',
      'details' => '/maps/api/place/details/json',
      'autocomplete' => '/maps/api/place/autocomplete/json',
      'geocode' => '/maps/api/geocode/json',
      _ => throw const GooglePlacesException(
        kind: GooglePlacesFailureKind.invalidRequest,
        message: 'Unsupported Google Places request.',
      ),
    };
    final uri = Uri.https('maps.googleapis.com', path, {
      ...parameters,
      'key': effectiveApiKey,
    });

    http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 12));
    } catch (_) {
      throw const GooglePlacesException(
        kind: GooglePlacesFailureKind.network,
        message:
            'Could not reach Google Places. Check your connection and retry.',
      );
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw GooglePlacesException(
        kind: GooglePlacesFailureKind.upstream,
        message: 'Google Places returned an unreadable response.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode == 429) {
      throw const GooglePlacesException(
        kind: GooglePlacesFailureKind.rateLimited,
        message:
            'Google Places request limit was reached. Please retry shortly.',
        statusCode: 429,
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw GooglePlacesException(
        kind: GooglePlacesFailureKind.unauthorized,
        message: 'Google Places rejected the configured API key.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GooglePlacesException(
        kind: GooglePlacesFailureKind.upstream,
        message: 'Google Places is unavailable right now.',
        statusCode: response.statusCode,
      );
    }

    final status = body['status']?.toString() ?? '';
    if (status == 'OK' || status == 'ZERO_RESULTS') return body;
    if (status == 'OVER_QUERY_LIMIT') {
      throw const GooglePlacesException(
        kind: GooglePlacesFailureKind.rateLimited,
        message:
            'Google Places request limit was reached. Please retry shortly.',
        statusCode: 429,
      );
    }
    if (status == 'REQUEST_DENIED') {
      throw const GooglePlacesException(
        kind: GooglePlacesFailureKind.unauthorized,
        message:
            'Google Places rejected the configured API key or API restrictions.',
        statusCode: 403,
      );
    }
    if (status == 'INVALID_REQUEST') {
      throw const GooglePlacesException(
        kind: GooglePlacesFailureKind.invalidRequest,
        message: 'Google Places rejected this search request.',
        statusCode: 400,
      );
    }
    throw const GooglePlacesException(
      kind: GooglePlacesFailureKind.upstream,
      message: 'Google Places is unavailable right now.',
      statusCode: 502,
    );
  }

  String photoUrl(String photoReference, {int maxWidth = 900}) {
    if (photoReference.trim().isEmpty || _resolvedApiKey.trim().isEmpty) {
      return '';
    }
    return Uri.https('maps.googleapis.com', '/maps/api/place/photo', {
      'maxwidth': '$maxWidth',
      'photo_reference': photoReference,
      'key': _resolvedApiKey,
    }).toString();
  }

  String staticMapUrl({required double latitude, required double longitude}) {
    if (_resolvedApiKey.trim().isEmpty) return '';
    final marker = '$latitude,$longitude';
    return Uri.https('maps.googleapis.com', '/maps/api/staticmap', {
      'center': marker,
      'zoom': '15',
      'size': '640x420',
      'scale': '2',
      'maptype': 'roadmap',
      'markers': 'color:red|$marker',
      'key': _resolvedApiKey,
    }).toString();
  }

  String routeStaticMapUrl({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
  }) {
    if (_resolvedApiKey.trim().isEmpty) return '';
    return Uri.https('maps.googleapis.com', '/maps/api/staticmap', {
      'size': '800x360',
      'scale': '2',
      'maptype': 'roadmap',
      'markers': [
        'color:green|label:P|$pickupLatitude,$pickupLongitude',
        'color:red|label:D|$dropoffLatitude,$dropoffLongitude',
      ],
      'key': _resolvedApiKey,
    }).toString();
  }
}

String resolveGoogleMapsApiKey() => GoogleMapsApiKeyResolver.cachedKey;
