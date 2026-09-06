import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'itinerary_directions_mobile.dart'
    if (dart.library.js_interop) 'itinerary_directions_web.dart';
import 'itinerary_route_exception.dart';

export 'itinerary_route_exception.dart';

class ItineraryTravelLeg {
  const ItineraryTravelLeg({
    required this.durationMinutes,
    required this.distanceMeters,
    required this.usedGoogleMaps,
  });

  final int durationMinutes;
  final int distanceMeters;
  final bool usedGoogleMaps;
}

class ItineraryStopTiming {
  const ItineraryStopTiming({
    required this.arrivalMinutes,
    required this.departureMinutes,
    required this.travelDurationMinutes,
  });

  final int arrivalMinutes;
  final int departureMinutes;
  final int travelDurationMinutes;
}

List<ItineraryStopTiming> calculateItineraryTimings({
  required int pickupMinutes,
  required List<int> stayDurationMinutes,
  required List<int> travelDurationMinutes,
}) {
  if (stayDurationMinutes.length != travelDurationMinutes.length) {
    throw ArgumentError('Each stop must have one inbound travel duration.');
  }

  var cursor = pickupMinutes;
  return List<ItineraryStopTiming>.generate(stayDurationMinutes.length, (i) {
    final travel = math.max(0, travelDurationMinutes[i]);
    final stay = math.max(1, stayDurationMinutes[i]);
    final arrival = cursor + travel;
    final departure = arrival + stay;
    cursor = departure;
    return ItineraryStopTiming(
      arrivalMinutes: arrival,
      departureMinutes: departure,
      travelDurationMinutes: travel,
    );
  });
}

int calculateEstimatedDropoffMinutes({
  required List<ItineraryStopTiming> stopTimings,
  required int finalTravelDurationMinutes,
}) {
  if (stopTimings.isEmpty) {
    throw ArgumentError('At least one itinerary stop is required.');
  }
  return stopTimings.last.departureMinutes +
      math.max(0, finalTravelDurationMinutes);
}

String buildItineraryRouteKey(List<LatLng> orderedPoints) => orderedPoints
    .map((point) => '${point.latitude},${point.longitude}')
    .join('|');

typedef ItineraryDirectionsLoader =
    Future<Map<String, dynamic>> Function(String apiKey, List<LatLng> points);

// Google returns traffic duration only without intermediate stopovers. Live
// forecasts request individual legs, then keep the configured destination order.
Future<Map<String, dynamic>> _fetchLiveDirections(
  String apiKey,
  List<LatLng> points,
) async {
  final responses = await Future.wait([
    for (var i = 0; i < points.length - 1; i++)
      fetchItineraryDirections(apiKey, [
        points[i],
        points[i + 1],
      ], requestTraffic: true),
  ]);
  final legs = <Map<String, dynamic>>[];
  for (final body in responses) {
    if (body['status'] != 'OK') throw const ItineraryRouteException();
    final route = (body['routes'] as List).first as Map;
    final leg = Map<String, dynamic>.from(
      (route['legs'] as List).single as Map,
    );
    // Google standard duration remains usable when traffic data is unavailable.
    leg['duration'] = leg['duration_in_traffic'] ?? leg['duration'];
    legs.add(leg);
  }
  return {
    'status': 'OK',
    'routes': [
      {'legs': legs},
    ],
  };
}

class ItineraryScheduleService {
  const ItineraryScheduleService({
    required this.apiKey,
    this.directionsLoader = fetchItineraryDirections,
  });
  const ItineraryScheduleService.live({
    required this.apiKey,
    this.directionsLoader = _fetchLiveDirections,
  });
  final String apiKey;
  final ItineraryDirectionsLoader directionsLoader;

  Future<List<ItineraryTravelLeg>> fetchTravelLegs(
    List<LatLng> orderedPoints,
  ) async {
    if (orderedPoints.length < 2 || orderedPoints.any((p) => !_validPoint(p))) {
      throw ItineraryRouteException(
        kind: ItineraryRouteFailure.invalidCoordinates,
        pointCount: orderedPoints.length,
      );
    }

    try {
      final body = await directionsLoader(apiKey, orderedPoints);
      final status = body['status']?.toString() ?? '';
      if (status != 'OK') {
        throw ItineraryRouteException(
          kind: _failureForGoogleResponse(body, status),
          googleStatus: status,
          pointCount: orderedPoints.length,
        );
      }

      final routes = body['routes'];
      if (routes is! List || routes.isEmpty || routes.first is! Map) {
        throw ItineraryRouteException(
          kind: ItineraryRouteFailure.malformedResponse,
          googleStatus: status,
          pointCount: orderedPoints.length,
        );
      }
      final legs = (routes.first as Map)['legs'];
      if (legs is! List) {
        throw ItineraryRouteException(
          kind: ItineraryRouteFailure.malformedResponse,
          googleStatus: status,
          pointCount: orderedPoints.length,
        );
      }
      if (legs.length != orderedPoints.length - 1) {
        throw ItineraryRouteException(
          kind: ItineraryRouteFailure.incompleteLegs,
          googleStatus: status,
          pointCount: orderedPoints.length,
          legCount: legs.length,
        );
      }
      final parsed = legs
          .map((raw) {
            if (raw is! Map) {
              throw ItineraryRouteException(
                kind: ItineraryRouteFailure.malformedResponse,
                googleStatus: status,
                pointCount: orderedPoints.length,
                legCount: legs.length,
              );
            }
            final leg = raw;
            final seconds = ((leg['duration'] as Map?)?['value'] as num?);
            final meters = ((leg['distance'] as Map?)?['value'] as num?);
            if (seconds == null ||
                meters == null ||
                !seconds.isFinite ||
                !meters.isFinite ||
                seconds < 0 ||
                meters < 0) {
              throw ItineraryRouteException(
                kind: ItineraryRouteFailure.malformedResponse,
                googleStatus: status,
                pointCount: orderedPoints.length,
                legCount: legs.length,
              );
            }
            return ItineraryTravelLeg(
              durationMinutes: (seconds / 60).ceil(),
              distanceMeters: meters.round(),
              usedGoogleMaps: true,
            );
          })
          .toList(growable: false);
      _debugRoute(
        status: status,
        pointCount: orderedPoints.length,
        legCount: parsed.length,
      );
      return parsed;
    } on ItineraryRouteException catch (error) {
      _debugRoute(
        status: error.googleStatus ?? error.kind.name,
        pointCount: error.pointCount ?? orderedPoints.length,
        legCount: error.legCount,
        httpStatus: error.httpStatus,
      );
      rethrow;
    } catch (_) {
      _debugRoute(
        status: ItineraryRouteFailure.upstream.name,
        pointCount: orderedPoints.length,
      );
      throw ItineraryRouteException(
        kind: ItineraryRouteFailure.upstream,
        pointCount: orderedPoints.length,
      );
    }
  }
}

bool _validPoint(LatLng point) =>
    point.latitude.isFinite &&
    point.longitude.isFinite &&
    point.latitude.abs() <= 90 &&
    point.longitude.abs() <= 180 &&
    !(point.latitude == 0 && point.longitude == 0);

ItineraryRouteFailure _failureForGoogleResponse(
  Map<String, dynamic> body,
  String status,
) {
  final safeError = body['error_message']?.toString().toLowerCase() ?? '';
  if (status == 'REQUEST_DENIED' &&
      (safeError.contains('not enabled') ||
          safeError.contains('not activated') ||
          safeError.contains('enable'))) {
    return ItineraryRouteFailure.apiNotEnabled;
  }
  return switch (status) {
    'REQUEST_DENIED' => ItineraryRouteFailure.unauthorized,
    'OVER_QUERY_LIMIT' => ItineraryRouteFailure.rateLimited,
    'ZERO_RESULTS' || 'NOT_FOUND' => ItineraryRouteFailure.noRoute,
    'INVALID_REQUEST' => ItineraryRouteFailure.invalidRequest,
    'NO_MAPS' => ItineraryRouteFailure.notConfigured,
    _ => ItineraryRouteFailure.upstream,
  };
}

void _debugRoute({
  required String status,
  required int pointCount,
  int? legCount,
  int? httpStatus,
}) {
  if (!kDebugMode) return;
  developer.log(
    'operation=directions status=$status httpStatus=${httpStatus ?? '-'} '
    'points=$pointCount legs=${legCount ?? '-'}',
    name: 'ItineraryScheduleService',
  );
}
