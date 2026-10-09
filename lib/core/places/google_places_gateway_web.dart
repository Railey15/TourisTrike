import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_places_errors.dart';

class GooglePlacesGateway {
  const GooglePlacesGateway({required this.apiKey, Object? client});

  // Kept for a matching cross-platform constructor. It is never sent on web.
  final String apiKey;

  Future<Map<String, dynamic>> request(
    String operation,
    Map<String, String> parameters,
  ) async {
    try {
      final response = await Supabase.instance.client.functions
          .invoke(
            'google-places',
            body: {'operation': operation, 'parameters': parameters},
          )
          .timeout(const Duration(seconds: 15));
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw const GooglePlacesException(
        kind: GooglePlacesFailureKind.upstream,
        message: 'The Places service returned an unreadable response.',
      );
    } on GooglePlacesException {
      rethrow;
    } on FunctionException catch (error) {
      throw _fromFunctionError(error);
    } catch (_) {
      throw const GooglePlacesException(
        kind: GooglePlacesFailureKind.network,
        message:
            'Could not reach the Places service. Check your connection and retry.',
      );
    }
  }

  GooglePlacesException _fromFunctionError(FunctionException error) {
    final details = error.details;
    final map = details is Map ? Map<String, dynamic>.from(details) : null;
    final code = map?['error']?.toString() ?? '';
    final message = map?['message']?.toString();
    if (error.status == 429 || code == 'RATE_LIMITED') {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.rateLimited,
        message:
            message ??
            'Google Places request limit was reached. Please retry shortly.',
        statusCode: 429,
      );
    }
    if (code == 'API_NOT_ENABLED') {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.apiNotEnabled,
        message: message ?? 'Places API (New) is not enabled on the server.',
        statusCode: error.status,
      );
    }
    if (code == 'LEGACY_ENDPOINT') {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.legacyEndpoint,
        message:
            message ??
            'The deployed Places service attempted to use a legacy endpoint.',
        statusCode: error.status,
      );
    }
    if (code == 'INVALID_API_KEY') {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.invalidApiKey,
        message: message ?? 'Google Places rejected the server API key.',
        statusCode: error.status,
      );
    }
    if (code == 'API_RESTRICTION_MISMATCH') {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.restrictionMismatch,
        message:
            message ?? 'The server API key restrictions rejected this request.',
        statusCode: error.status,
      );
    }
    if (code == 'BILLING_REQUIRED') {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.billing,
        message: message ?? 'Google Maps Platform billing is unavailable.',
        statusCode: error.status,
      );
    }
    if (code == 'MISSING_FIELD_MASK') {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.missingFieldMask,
        message: message ?? 'Google Places rejected the field mask.',
        statusCode: error.status,
      );
    }
    if (error.status == 401 ||
        error.status == 403 ||
        code == 'GOOGLE_UNAUTHORIZED') {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.unauthorized,
        message:
            message ??
            'Google Places rejected the server API key or its restrictions.',
        statusCode: error.status,
      );
    }
    if (error.status == 503 || code == 'NOT_CONFIGURED') {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.notConfigured,
        message: message ?? 'Google Places is not configured on the server.',
        statusCode: error.status,
      );
    }
    if (error.status == 400) {
      return GooglePlacesException(
        kind: GooglePlacesFailureKind.invalidRequest,
        message: message ?? 'Google Places rejected this search request.',
        statusCode: error.status,
      );
    }
    return GooglePlacesException(
      kind: error.status == 0
          ? GooglePlacesFailureKind.network
          : GooglePlacesFailureKind.upstream,
      message: message ?? 'The Places service is unavailable right now.',
      statusCode: error.status,
    );
  }

  String photoUrl(String photoReference, {int maxWidth = 900}) => '';

  String staticMapUrl({required double latitude, required double longitude}) =>
      '';

  Future<String> photoProxyUrl(String photoReference) async {
    final data = await request('photoProxyUrl', {
      'photo_reference': photoReference,
    });
    return data['url']?.toString().trim() ?? '';
  }

  Future<String> staticMapProxyUrl({
    required double latitude,
    required double longitude,
  }) async => '';

  Future<String> routeStaticMapUrl({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
    String encodedPolyline = '',
  }) async => '';
}

String resolveGoogleMapsApiKey() => '';
