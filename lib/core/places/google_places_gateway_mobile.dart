import 'dart:convert';

import 'package:http/http.dart' as http;

import 'google_maps_api_key_resolver.dart';
import 'google_places_errors.dart';
import 'google_places_diagnostics.dart';
import 'google_places_new_api.dart';

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
    final isGeocode = operation == 'geocode';
    if (!isGeocode &&
        !const {
          'textSearch',
          'nearbySearch',
          'details',
          'autocomplete',
        }.contains(operation)) {
      throw const GooglePlacesException(
        kind: GooglePlacesFailureKind.invalidRequest,
        message: 'Unsupported Google Places request.',
      );
    }
    final uri = isGeocode
        ? Uri.https('maps.googleapis.com', '/maps/api/geocode/json', parameters)
        : googlePlacesNewUri(operation, parameters);
    final endpoint = Uri(
      scheme: uri.scheme,
      host: uri.host,
      path: uri.path,
    ).toString();
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
    http.Response response;
    try {
      if (isGeocode) {
        final keyedUri = uri.replace(
          queryParameters: {...uri.queryParameters, 'key': effectiveApiKey},
        );
        response = await (_client?.get(keyedUri) ?? http.get(keyedUri)).timeout(
          const Duration(seconds: 12),
        );
      } else {
        final headers = googlePlacesNewHeaders(
          apiKey: effectiveApiKey,
          operation: operation,
        );
        if (operation == 'details') {
          response =
              await (_client?.get(uri, headers: headers) ??
                      http.get(uri, headers: headers))
                  .timeout(const Duration(seconds: 12));
        } else {
          final requestBody = googlePlacesNewRequestBody(operation, parameters);
          response =
              await (_client?.post(uri, headers: headers, body: requestBody) ??
                      http.post(uri, headers: headers, body: requestBody))
                  .timeout(const Duration(seconds: 12));
        }
      }
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

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body['error'];
      await GooglePlacesDiagnostics.record(
        operation: operation,
        endpoint: endpoint,
        key: effectiveApiKey,
        httpStatus: response.statusCode,
        googleStatus:
            (error is Map ? error['status']?.toString() : null) ??
            body['status']?.toString() ??
            'UNKNOWN',
        googleMessage:
            body['error_message']?.toString() ??
            (error is Map ? error['message']?.toString() : null) ??
            '',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _newApiException(body, response.statusCode);
    }

    if (!isGeocode) {
      return normalizeGooglePlacesNewResponse(operation, body);
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

  GooglePlacesException _newApiException(
    Map<String, dynamic> body,
    int statusCode,
  ) {
    final error = body['error'];
    final status = error is Map ? error['status']?.toString() ?? '' : '';
    final message = error is Map ? error['message']?.toString() ?? '' : '';
    final normalized = '$status $message'.toLowerCase();
    if (statusCode == 429 || normalized.contains('quota')) {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.rateLimited,
        message:
            'Google Places request limit was reached. Please retry shortly.',
        statusCode: statusCode,
      );
    }
    if (normalized.contains('field mask')) {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.missingFieldMask,
        message: 'Google Places rejected a missing or invalid field mask.',
        statusCode: statusCode,
      );
    }
    if (normalized.contains('billing')) {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.billing,
        message:
            'Google Maps Platform billing is not available for this project.',
        statusCode: statusCode,
      );
    }
    if (normalized.contains('legacy api') ||
        normalized.contains('legacy endpoint')) {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.legacyEndpoint,
        message:
            'Google Places rejected a legacy endpoint. Update the deployed client or server.',
        statusCode: statusCode,
      );
    }
    if (normalized.contains('not enabled') ||
        normalized.contains('has not been used') ||
        normalized.contains('disabled')) {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.apiNotEnabled,
        message: 'Places API (New) is not enabled for this project.',
        statusCode: statusCode,
      );
    }
    if (normalized.contains('api key not valid') ||
        normalized.contains('invalid api key')) {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.invalidApiKey,
        message: 'Google Places rejected the configured API key.',
        statusCode: statusCode,
      );
    }
    if (normalized.contains('referer') ||
        normalized.contains('restriction') ||
        normalized.contains('not authorized')) {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.restrictionMismatch,
        message: 'The API key restrictions do not allow this Places request.',
        statusCode: statusCode,
      );
    }
    if (statusCode == 401 || statusCode == 403) {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.unauthorized,
        message: 'Google Places rejected the configured API key.',
        statusCode: statusCode,
      );
    }
    if (statusCode == 400) {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.invalidRequest,
        message: 'Google Places rejected this search request.',
        statusCode: statusCode,
      );
    }
    return GooglePlacesException(
      kind: GooglePlacesFailureKind.upstream,
      message: 'Google Places is unavailable right now.',
      statusCode: statusCode,
    );
  }

  String photoUrl(String photoReference, {int maxWidth = 900}) {
    if (photoReference.trim().isEmpty || _resolvedApiKey.trim().isEmpty) {
      return '';
    }
    final resource = photoReference.trim().replaceFirst(RegExp(r'^/+'), '');
    if (!resource.startsWith('places/') || !resource.contains('/photos/')) {
      return '';
    }
    return Uri.https(googlePlacesNewHost, '/v1/$resource/media', {
      'maxWidthPx': '$maxWidth',
      'key': _resolvedApiKey,
    }).toString();
  }

  Future<String> photoProxyUrl(String photoReference) async {
    final effectiveApiKey = await _loadApiKey();
    if (photoReference.trim().isEmpty || effectiveApiKey.isEmpty) return '';
    return photoUrl(photoReference);
  }

  String staticMapUrl({required double latitude, required double longitude}) {
    return '';
  }

  Future<String> staticMapProxyUrl({
    required double latitude,
    required double longitude,
  }) async {
    return '';
  }

  Future<String> routeStaticMapUrl({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
    String encodedPolyline = '',
  }) async {
    return '';
  }
}

String resolveGoogleMapsApiKey() => GoogleMapsApiKeyResolver.cachedKey;
