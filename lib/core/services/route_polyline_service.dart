import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class RouteResult {
  const RouteResult({required this.points, this.durationText});

  final List<LatLng> points;
  final String? durationText;
}

class RoutePolylineService {
  const RoutePolylineService({required this.apiKey});

  final String apiKey;

  /// Fetches a driving route from [origin] to [dest] via the Google Directions
  /// API and returns decoded road-following polyline points.
  ///
  /// Priority: step-level polylines (highest detail) → overview_polyline
  /// → straight-line segment (only when the API call itself fails).
  ///
  /// All diagnostic output uses [print] so it appears in the browser console
  /// even in release builds.
  Future<RouteResult> fetchRoute(
    LatLng origin,
    LatLng dest, {
    List<LatLng> waypoints = const [],
  }) async {
    const tag = '[RoutePolyline]';

    // Build URL
    final waypointsParam = waypoints.isNotEmpty
        ? '&waypoints=${waypoints.map((p) => '${p.latitude},${p.longitude}').join('|')}'
        : '';

    final url =
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${dest.latitude},${dest.longitude}'
        '&mode=driving'
        '$waypointsParam'
        '&key=$apiKey';

    // ignore: avoid_print
    print('$tag → ${origin.latitude.toStringAsFixed(5)},'
        '${origin.longitude.toStringAsFixed(5)} '
        'to ${dest.latitude.toStringAsFixed(5)},'
        '${dest.longitude.toStringAsFixed(5)}'
        '${waypoints.isNotEmpty ? " via ${waypoints.length} waypoints" : ""}');

    try {
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));

      // ignore: avoid_print
      print('$tag HTTP ${res.statusCode}, body length=${res.body.length}');

      if (res.statusCode != 200) {
        // ignore: avoid_print
        print('$tag Non-200 response. Body: ${_truncate(res.body)}');
        return RouteResult(points: [origin, dest]);
      }

      late final Map<String, dynamic> body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (e) {
        // ignore: avoid_print
        print('$tag JSON decode failed: $e. Body: ${_truncate(res.body)}');
        return RouteResult(points: [origin, dest]);
      }

      final status = body['status'] as String? ?? 'UNKNOWN';
      final errorMsg = body['error_message'] as String? ?? '';

      // ignore: avoid_print
      print(
          '$tag status=$status${errorMsg.isNotEmpty ? "  error_message=$errorMsg" : ""}');

      if (status != 'OK') {
        return RouteResult(points: [origin, dest]);
      }

      final routes = (body['routes'] as List?) ?? const [];
      if (routes.isEmpty) {
        // ignore: avoid_print
        print('$tag No routes in response.');
        return RouteResult(points: [origin, dest]);
      }

      final route = routes.first as Map;
      String? durationText;

      // ── Attempt 1: step-level polylines (maximum road detail) ──────────────
      final legs = (route['legs'] as List?) ?? const [];
      final stepPoints = <LatLng>[];
      if (legs.isNotEmpty) {
        final leg = legs.first as Map;
        durationText = leg['duration']?['text'] as String?;
        final steps = (leg['steps'] as List?) ?? const [];
        for (final step in steps) {
          final enc = (step as Map)['polyline']?['points'] as String?;
          if (enc != null && enc.isNotEmpty) {
            stepPoints.addAll(_decode(enc));
          }
        }
      }

      if (stepPoints.isNotEmpty) {
        // ignore: avoid_print
        print('$tag Step polylines OK — ${stepPoints.length} pts, ETA=$durationText');
        return RouteResult(points: stepPoints, durationText: durationText);
      }

      // ── Attempt 2: overview_polyline ────────────────────────────────────────
      final overviewEnc =
          route['overview_polyline']?['points'] as String? ?? '';
      if (overviewEnc.isNotEmpty) {
        final overviewPts = _decode(overviewEnc);
        // ignore: avoid_print
        print(
            '$tag overview_polyline — ${overviewPts.length} pts, ETA=$durationText');
        return RouteResult(points: overviewPts, durationText: durationText);
      }

      // ── Attempt 3: straight-line fallback ───────────────────────────────────
      // ignore: avoid_print
      print('$tag No polyline data found in route. Using straight-line fallback.');
      return RouteResult(points: [origin, dest], durationText: durationText);
    } catch (e, st) {
      // Plain catch — captures both Exception and Error (including JS errors
      // that the Flutter Web http client may throw via dart:html).
      // ignore: avoid_print
      print('$tag Exception: $e\n$st');
      return RouteResult(points: [origin, dest]);
    }
  }

  // Google Encoded Polyline Algorithm (https://developers.google.com/maps/documentation/utilities/polylinealgorithm)
  List<LatLng> _decode(String encoded) {
    final pts = <LatLng>[];
    int i = 0;
    final len = encoded.length;
    int lat = 0, lng = 0;

    while (i < len) {
      // Decode latitude delta
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      // Decode longitude delta
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      pts.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return pts;
  }

  String _truncate(String s, [int max = 500]) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}
