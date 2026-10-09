import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../places/google_maps_api_key_resolver.dart';
import 'google_routes_api.dart';
import 'itinerary_route_exception.dart';

Future<Map<String, dynamic>> fetchItineraryDirections(
  String apiKey,
  List<LatLng> points, {
  bool requestTraffic = false,
}) async {
  if (points.length < 2 || points.any((point) => !_validPoint(point))) {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.invalidCoordinates,
      pointCount: points.length,
    );
  }

  final effectiveApiKey = await GoogleMapsApiKeyResolver.resolve(
    explicitKey: apiKey,
  );
  if (effectiveApiKey.isEmpty) {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.notConfigured,
      pointCount: points.length,
    );
  }

  final uri = Uri.parse(googleRoutesEndpoint);

  if (kDebugMode) {
    debugPrint(
      '[ItineraryDirections] operation=computeRoutes points=${points.length} '
      'traffic=$requestTraffic',
    );
  }

  late http.Response response;
  try {
    response = await http
        .post(
          uri,
          headers: googleRoutesHeaders(effectiveApiKey),
          body: googleRoutesRequestBody(points, trafficAware: requestTraffic),
        )
        .timeout(const Duration(seconds: 12));
  } on TimeoutException {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.network,
      pointCount: points.length,
    );
  } on http.ClientException {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.network,
      pointCount: points.length,
    );
  } catch (_) {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.network,
      pointCount: points.length,
    );
  }

  if (kDebugMode) {
    debugPrint(
      '[ItineraryDirections] operation=computeRoutes '
      'httpStatus=${response.statusCode} points=${points.length}',
    );
  }

  if (response.statusCode == 429) {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.rateLimited,
      httpStatus: response.statusCode,
      pointCount: points.length,
    );
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    var kind = response.statusCode >= 500
        ? ItineraryRouteFailure.upstream
        : ItineraryRouteFailure.invalidRequest;
    try {
      final decoded = jsonDecode(response.body);
      final error = decoded is Map ? decoded['error'] : null;
      final status = error is Map ? error['status']?.toString() ?? '' : '';
      final message = error is Map ? error['message']?.toString() ?? '' : '';
      kind = routesFailureForError(
        httpStatus: response.statusCode,
        status: status,
        message: message,
      );
    } catch (_) {
      // The HTTP status still provides a safe fallback classification.
    }
    throw ItineraryRouteException(
      kind: kind,
      httpStatus: response.statusCode,
      pointCount: points.length,
    );
  }

  try {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException();
    }
    return normalizeRoutesForItinerary(decoded);
  } on FormatException {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.malformedResponse,
      httpStatus: response.statusCode,
      pointCount: points.length,
    );
  }
}

ItineraryRouteFailure routesFailureForError({
  required int httpStatus,
  required String status,
  required String message,
}) {
  final normalized = '$status $message'.toLowerCase();
  if (httpStatus == 429 || normalized.contains('quota')) {
    return ItineraryRouteFailure.rateLimited;
  }
  if (normalized.contains('billing')) return ItineraryRouteFailure.billing;
  if (normalized.contains('legacy api') ||
      normalized.contains('legacy endpoint')) {
    return ItineraryRouteFailure.legacyEndpoint;
  }
  if (normalized.contains('not enabled') ||
      normalized.contains('has not been used') ||
      normalized.contains('disabled')) {
    return ItineraryRouteFailure.apiNotEnabled;
  }
  if (normalized.contains('api key not valid') ||
      normalized.contains('invalid api key')) {
    return ItineraryRouteFailure.invalidApiKey;
  }
  if (normalized.contains('referer') ||
      normalized.contains('restriction') ||
      normalized.contains('not authorized')) {
    return ItineraryRouteFailure.restrictionMismatch;
  }
  if (httpStatus == 401 || httpStatus == 403) {
    return ItineraryRouteFailure.unauthorized;
  }
  return httpStatus >= 500
      ? ItineraryRouteFailure.upstream
      : ItineraryRouteFailure.invalidRequest;
}

bool _validPoint(LatLng point) =>
    point.latitude.isFinite &&
    point.longitude.isFinite &&
    point.latitude.abs() <= 90 &&
    point.longitude.abs() <= 180 &&
    !(point.latitude == 0 && point.longitude == 0);
