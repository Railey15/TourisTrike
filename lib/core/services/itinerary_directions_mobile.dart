import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../places/google_maps_api_key_resolver.dart';
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

  String coordinate(LatLng point) => '${point.latitude},${point.longitude}';
  final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
    'origin': coordinate(points.first),
    'destination': coordinate(points.last),
    if (points.length > 2)
      'waypoints': points
          .skip(1)
          .take(points.length - 2)
          .map(coordinate)
          .join('|'),
    'mode': 'driving',
    if (requestTraffic) 'departure_time': 'now',
    'region': 'ph',
    'key': effectiveApiKey,
  });

  if (kDebugMode) {
    debugPrint(
      '[ItineraryDirections] operation=directions points=${points.length} '
      'traffic=$requestTraffic',
    );
  }

  late http.Response response;
  try {
    response = await http.get(uri).timeout(const Duration(seconds: 12));
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
      '[ItineraryDirections] operation=directions '
      'httpStatus=${response.statusCode} points=${points.length}',
    );
  }

  if (response.statusCode == 401 || response.statusCode == 403) {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.unauthorized,
      httpStatus: response.statusCode,
      pointCount: points.length,
    );
  }
  if (response.statusCode == 429) {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.rateLimited,
      httpStatus: response.statusCode,
      pointCount: points.length,
    );
  }
  if (response.statusCode != 200) {
    throw ItineraryRouteException(
      kind: response.statusCode >= 500
          ? ItineraryRouteFailure.upstream
          : ItineraryRouteFailure.invalidRequest,
      httpStatus: response.statusCode,
      pointCount: points.length,
    );
  }

  try {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException();
    }
    return decoded;
  } on FormatException {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.malformedResponse,
      httpStatus: response.statusCode,
      pointCount: points.length,
    );
  }
}

bool _validPoint(LatLng point) =>
    point.latitude.isFinite &&
    point.longitude.isFinite &&
    point.latitude.abs() <= 90 &&
    point.longitude.abs() <= 180 &&
    !(point.latitude == 0 && point.longitude == 0);
