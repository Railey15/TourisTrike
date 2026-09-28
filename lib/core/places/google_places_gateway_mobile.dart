import 'dart:convert';

import 'package:http/http.dart' as http;

import 'google_maps_api_key_resolver.dart';
import 'google_places_errors.dart';
import 'google_places_diagnostics.dart';

class GooglePlacesGateway {
  GooglePlacesGateway({required this.apiKey, http.Client? client})
    : _resolvedApiKey = apiKey,
      _client = client;

  final String apiKey;
  String _resolvedApiKey;
  final http.Client? _client;

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
    final endpoint = 'https://maps.googleapis.com$path';
    final effectiveApiKey = await _loadApiKey();
    if (effectiveApiKey.isEmpty) {
      await GooglePlacesDiagnostics.record(
        operation: operation,
        endpoint: endpoint,
        key: '',
        googleStatus: 'NOT_CONFIGURED',
      );
      throw const GooglePlacesException(
        kind: GooglePlacesFailureKind.notConfigured,
        message: 'Google Places is not configured on this device.',
      );
    }
    final uri = Uri.https('maps.googleapis.com', path, {
      ...parameters,
      'key': effectiveApiKey,
    });

    http.Response response;
    try {
      response = await (_client?.get(uri) ?? http.get(uri)).timeout(
        const Duration(seconds: 12),
      );
    } catch (_) {
      await GooglePlacesDiagnostics.record(
        operation: operation,
        endpoint: endpoint,
        key: effectiveApiKey,
        googleStatus: 'NETWORK_FAILURE',
      );
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
      await GooglePlacesDiagnostics.record(
        operation: operation,
        endpoint: endpoint,
        key: effectiveApiKey,
        httpStatus: response.statusCode,
        googleStatus: 'UNREADABLE_RESPONSE',
      );
      throw GooglePlacesException(
        kind: GooglePlacesFailureKind.upstream,
        message: 'Google Places returned an unreadable response.',
        statusCode: response.statusCode,
      );
    }

    if (body['status'] != 'OK' && body['status'] != 'ZERO_RESULTS' ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      final error = body['error'];
      await GooglePlacesDiagnostics.record(
        operation: operation,
        endpoint: endpoint,
        key: effectiveApiKey,
        httpStatus: response.statusCode,
        googleStatus:
            body['status']?.toString() ??
            (error is Map ? error['status']?.toString() : null) ??
            'UNKNOWN',
        googleMessage:
            body['error_message']?.toString() ??
            (error is Map ? error['message']?.toString() : null) ??
            '',
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

  Future<String> photoProxyUrl(String photoReference) async {
    final effectiveApiKey = await _loadApiKey();
    if (photoReference.trim().isEmpty || effectiveApiKey.isEmpty) return '';
    return photoUrl(photoReference);
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

  Future<String> staticMapProxyUrl({
    required double latitude,
    required double longitude,
  }) async {
    final effectiveApiKey = await _loadApiKey();
    if (effectiveApiKey.isEmpty) return '';
    return staticMapUrl(latitude: latitude, longitude: longitude);
  }

  Future<String> routeStaticMapUrl({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
    String encodedPolyline = '',
  }) async {
    final effectiveApiKey = await _loadApiKey();
    if (effectiveApiKey.isEmpty) return '';
    return Uri.https('maps.googleapis.com', '/maps/api/staticmap', {
      'size': '800x360',
      'scale': '2',
      'maptype': 'roadmap',
      'markers': [
        'color:green|label:P|$pickupLatitude,$pickupLongitude',
        'color:red|label:D|$dropoffLatitude,$dropoffLongitude',
      ],
      if (encodedPolyline.isNotEmpty)
        'path': 'color:0x2A86FF|weight:4|enc:$encodedPolyline',
      'key': effectiveApiKey,
    }).toString();
  }
}

String resolveGoogleMapsApiKey() => GoogleMapsApiKeyResolver.cachedKey;
