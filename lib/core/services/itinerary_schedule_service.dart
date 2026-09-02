import 'dart:convert';
import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

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

class ItineraryScheduleService {
  const ItineraryScheduleService({required this.apiKey});

  final String apiKey;

  Future<List<ItineraryTravelLeg>> fetchTravelLegs(
    List<LatLng> orderedPoints,
  ) async {
    if (orderedPoints.length < 2) return const [];

    final googleLegs = await _fetchGoogleDirectionsLegs(orderedPoints);
    if (googleLegs != null && googleLegs.length == orderedPoints.length - 1) {
      return googleLegs;
    }

    return List<ItineraryTravelLeg>.generate(orderedPoints.length - 1, (i) {
      final meters = _haversineMeters(orderedPoints[i], orderedPoints[i + 1]);
      // Existing TourisTrike fallback assumes an urban tricycle average of
      // 28 km/h. Google Directions remains authoritative whenever available.
      final minutes = math.max(1, ((meters / 1000) / 28 * 60).round());
      return ItineraryTravelLeg(
        durationMinutes: minutes,
        distanceMeters: meters.round(),
        usedGoogleMaps: false,
      );
    });
  }

  Future<List<ItineraryTravelLeg>?> _fetchGoogleDirectionsLegs(
    List<LatLng> points,
  ) async {
    if (apiKey.trim().isEmpty) return null;

    final origin = points.first;
    final destination = points.last;
    final waypoints = points
        .skip(1)
        .take(points.length - 2)
        .map((p) => '${p.latitude},${p.longitude}')
        .join('|');
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '${waypoints.isEmpty ? '' : '&waypoints=${Uri.encodeQueryComponent(waypoints)}'}'
      '&mode=driving&region=ph&key=$apiKey',
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return null;
      final routes = body['routes'] as List? ?? const [];
      if (routes.isEmpty) return null;
      final legs = (routes.first as Map)['legs'] as List? ?? const [];
      return legs
          .map((raw) {
            final leg = raw as Map;
            final seconds = ((leg['duration'] as Map?)?['value'] as num?)
                ?.toInt();
            final meters = ((leg['distance'] as Map?)?['value'] as num?)
                ?.toInt();
            if (seconds == null || meters == null) {
              throw const FormatException('Directions leg is incomplete.');
            }
            return ItineraryTravelLeg(
              durationMinutes: math.max(1, (seconds / 60).ceil()),
              distanceMeters: meters,
              usedGoogleMaps: true,
            );
          })
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  double _haversineMeters(LatLng a, LatLng b) {
    const radiusMeters = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final deltaLat = (b.latitude - a.latitude) * math.pi / 180;
    final deltaLng = (b.longitude - a.longitude) * math.pi / 180;
    final h =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    return radiusMeters * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }
}
