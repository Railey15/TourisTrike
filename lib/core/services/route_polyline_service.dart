import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class RouteResult {
  const RouteResult({required this.points, this.durationText, this.isFallback = false});

  final List<LatLng> points;
  final String? durationText;
  final bool isFallback;
}

class RoutePolylineService {
  const RoutePolylineService({required this.apiKey});

  final String apiKey;

  /// Fetches a driving route from [origin] to [dest] using the Google
  /// Directions API. Returns decoded step-level polyline points for smooth
  /// road-following lines. Falls back to overview polyline, then to a
  /// straight-line segment if the API is unavailable.
  Future<RouteResult> fetchRoute(LatLng origin, LatLng dest) async {
    final tag = '[RoutePolyline]';
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${dest.latitude},${dest.longitude}'
        '&mode=driving'
        '&key=$apiKey',
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        debugPrint('$tag HTTP ${res.statusCode}: ${res.reasonPhrase}');
        return RouteResult(points: [origin, dest], isFallback: true);
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final status = body['status'] as String? ?? 'UNKNOWN';

      if (status != 'OK') {
        final msg = body['error_message'] as String? ?? '(no error_message)';
        debugPrint('$tag Directions API status=$status — $msg');
        return RouteResult(points: [origin, dest], isFallback: true);
      }

      final routes = (body['routes'] as List?) ?? const [];
      if (routes.isEmpty) {
        debugPrint('$tag No routes returned for '
            '${origin.latitude},${origin.longitude} → '
            '${dest.latitude},${dest.longitude}');
        return RouteResult(points: [origin, dest], isFallback: true);
      }

      final route = routes.first as Map;
      final legs = (route['legs'] as List?) ?? const [];
      String? durationText;
      final points = <LatLng>[];

      if (legs.isNotEmpty) {
        final leg = legs.first as Map;
        durationText = leg['duration']?['text'] as String?;
        final steps = (leg['steps'] as List?) ?? const [];
        for (final step in steps) {
          final encoded = (step as Map)['polyline']?['points'] as String?;
          if (encoded != null) points.addAll(_decodePolyline(encoded));
        }
      }

      if (points.isNotEmpty) {
        debugPrint('$tag Road route: ${points.length} points, ETA=$durationText');
        return RouteResult(points: points, durationText: durationText);
      }

      // Step polylines were empty — try overview polyline
      final overviewEncoded = route['overview_polyline']?['points'] as String?;
      if (overviewEncoded != null) {
        final overviewPoints = _decodePolyline(overviewEncoded);
        debugPrint('$tag Using overview polyline: ${overviewPoints.length} points');
        return RouteResult(points: overviewPoints, durationText: durationText);
      }

      debugPrint('$tag No polyline data in route; using straight line fallback');
      return RouteResult(points: [origin, dest], isFallback: true, durationText: durationText);
    } on Exception catch (e) {
      debugPrint('$tag Exception fetching route: $e');
      return RouteResult(points: [origin, dest], isFallback: true);
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    final len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
