import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';

const googleRoutesEndpoint =
    'https://routes.googleapis.com/directions/v2:computeRoutes';

const googleRoutesFieldMask =
    'routes.duration,'
    'routes.distanceMeters,'
    'routes.polyline.encodedPolyline,'
    'routes.legs.duration,'
    'routes.legs.distanceMeters';

Map<String, String> googleRoutesHeaders(String apiKey) => {
  'Content-Type': 'application/json',
  'X-Goog-Api-Key': apiKey,
  'X-Goog-FieldMask': googleRoutesFieldMask,
};

String googleRoutesRequestBody(
  List<LatLng> points, {
  bool trafficAware = false,
}) {
  Map<String, dynamic> waypoint(LatLng point) => {
    'location': {
      'latLng': {'latitude': point.latitude, 'longitude': point.longitude},
    },
  };

  return jsonEncode({
    'origin': waypoint(points.first),
    'destination': waypoint(points.last),
    if (points.length > 2)
      'intermediates': points
          .skip(1)
          .take(points.length - 2)
          .map(waypoint)
          .toList(),
    'travelMode': 'DRIVE',
    'routingPreference': trafficAware ? 'TRAFFIC_AWARE' : 'TRAFFIC_UNAWARE',
    'polylineQuality': 'OVERVIEW',
    'computeAlternativeRoutes': false,
    'languageCode': 'en-US',
    'regionCode': 'PH',
    'units': 'METRIC',
  });
}

double? googleDurationSeconds(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (!raw.endsWith('s')) return null;
  return double.tryParse(raw.substring(0, raw.length - 1));
}

String googleDurationText(Object? value) {
  final seconds = googleDurationSeconds(value);
  if (seconds == null || !seconds.isFinite || seconds < 0) return '';
  final minutes = (seconds / 60).ceil();
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  return remaining == 0 ? '$hours hr' : '$hours hr $remaining min';
}

Map<String, dynamic> normalizeRoutesForItinerary(Map<String, dynamic> body) {
  final routes = (body['routes'] as List?) ?? const [];
  final normalizedRoutes = <Map<String, dynamic>>[];
  for (final rawRoute in routes.whereType<Map>()) {
    final legs = ((rawRoute['legs'] as List?) ?? const []).whereType<Map>().map(
      (leg) {
        final seconds = googleDurationSeconds(leg['duration']);
        final meters = (leg['distanceMeters'] as num?)?.toDouble();
        return {
          'duration': {'value': seconds},
          'distance': {'value': meters},
        };
      },
    ).toList();
    normalizedRoutes.add({
      'legs': legs,
      'overview_polyline': {
        'points': (rawRoute['polyline'] as Map?)?['encodedPolyline'] ?? '',
      },
    });
  }
  return {
    'status': normalizedRoutes.isEmpty ? 'ZERO_RESULTS' : 'OK',
    'routes': normalizedRoutes,
  };
}
