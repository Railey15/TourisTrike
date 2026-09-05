import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'itinerary_directions_mobile.dart'
    if (dart.library.js_interop) 'itinerary_directions_web.dart';

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
    if (orderedPoints.length < 2) return const [];
    try {
      final body = await directionsLoader(apiKey, orderedPoints);
      if (body['status'] != 'OK') {
        throw const FormatException('Route unavailable.');
      }
      final routes = body['routes'] as List;
      final legs = (routes.first as Map)['legs'] as List;
      if (legs.length != orderedPoints.length - 1) {
        throw const FormatException('Missing route legs.');
      }
      return legs
          .map((raw) {
            final leg = raw as Map;
            final seconds = ((leg['duration'] as Map?)?['value'] as num?);
            final meters = ((leg['distance'] as Map?)?['value'] as num?);
            if (seconds == null ||
                meters == null ||
                !seconds.isFinite ||
                !meters.isFinite ||
                seconds < 0 ||
                meters < 0) {
              throw const FormatException('Directions leg is incomplete.');
            }
            return ItineraryTravelLeg(
              durationMinutes: (seconds / 60).ceil(),
              distanceMeters: meters.round(),
              usedGoogleMaps: true,
            );
          })
          .toList(growable: false);
    } catch (_) {
      throw const ItineraryRouteException();
    }
  }
}

class ItineraryRouteException implements Exception {
  const ItineraryRouteException();
  String get message =>
      'Google Maps could not calculate this route. Check your connection or locations and retry.';
}
