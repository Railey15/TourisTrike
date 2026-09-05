import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> fetchItineraryDirections(
  String apiKey,
  List<LatLng> points, {
  bool requestTraffic = false,
}) async {
  if (apiKey.trim().isEmpty) throw StateError('Google Maps is not configured.');
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
    'key': apiKey,
  });
  final response = await http.get(uri).timeout(const Duration(seconds: 12));
  if (response.statusCode != 200) {
    throw StateError('Google Maps request failed.');
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}
