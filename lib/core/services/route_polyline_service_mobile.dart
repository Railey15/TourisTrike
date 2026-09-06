// Native (iOS/Android) implementation.
// Uses the Google Directions REST API over HTTP — no CORS restrictions on native.
// Conditional export in route_polyline_service.dart selects this for non-web targets.

import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../places/google_maps_api_key_resolver.dart';

class RouteResult {
  const RouteResult({required this.points, this.durationText});
  final List<LatLng> points;
  final String? durationText;
}

class RoutePolylineService {
  const RoutePolylineService({required this.apiKey});

  final String apiKey;

  Future<RouteResult> fetchRoute(
    LatLng origin,
    LatLng dest, {
    List<LatLng> waypoints = const [],
  }) async {
    const tag = '[RoutePolyline/MOBILE]';
    final effectiveApiKey = await GoogleMapsApiKeyResolver.resolve(
      explicitKey: apiKey,
    );

    // ignore: avoid_print
    print(
      '$tag platform=MOBILE '
      '${_fmt(origin)} → ${_fmt(dest)}'
      '${waypoints.isNotEmpty ? " via ${waypoints.length} wp" : ""}',
    );

    final waypointsParam = waypoints.isNotEmpty
        ? '&waypoints=${waypoints.map((p) => '${p.latitude},${p.longitude}').join('|')}'
        : '';

    final url =
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${dest.latitude},${dest.longitude}'
        '&mode=driving$waypointsParam'
        '&key=$effectiveApiKey';

    // ignore: avoid_print
    print('$tag GET directions (key omitted from log)');

    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      // ignore: avoid_print
      print('$tag HTTP ${res.statusCode}, body_len=${res.body.length}');

      if (res.statusCode != 200) {
        // ignore: avoid_print
        print('$tag Non-200: ${res.reasonPhrase}. Body: ${_clip(res.body)}');
        return RouteResult(points: [origin, dest]);
      }

      late final Map<String, dynamic> body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (e) {
        // ignore: avoid_print
        print('$tag JSON parse error: $e. Body: ${_clip(res.body)}');
        return RouteResult(points: [origin, dest]);
      }

      final status = body['status'] as String? ?? 'UNKNOWN';
      final errMsg = body['error_message'] as String? ?? '';
      // ignore: avoid_print
      print(
        '$tag API status=$status'
        '${errMsg.isNotEmpty ? "  error_message=$errMsg" : ""}',
      );

      if (status != 'OK') {
        // ignore: avoid_print
        print(
          '$tag Non-OK status → fallback straight line. '
          'Check: Directions API enabled, key restrictions, billing.',
        );
        return RouteResult(points: [origin, dest]);
      }

      final routes = (body['routes'] as List?) ?? const [];
      if (routes.isEmpty) {
        // ignore: avoid_print
        print('$tag No routes returned');
        return RouteResult(points: [origin, dest]);
      }

      final route = routes.first as Map;
      String? durationText;
      final pts = <LatLng>[];

      // Step-level polylines (highest detail)
      final legs = (route['legs'] as List?) ?? const [];
      if (legs.isNotEmpty) {
        final leg = legs.first as Map;
        durationText = leg['duration']?['text'] as String?;
        for (final step in (leg['steps'] as List?) ?? const []) {
          final enc = (step as Map)['polyline']?['points'] as String?;
          if (enc != null && enc.isNotEmpty) pts.addAll(_decode(enc));
        }
      }

      if (pts.isNotEmpty) {
        // ignore: avoid_print
        print(
          '$tag step_pts=${pts.length}, ETA=$durationText ✓ road-following',
        );
        return RouteResult(points: pts, durationText: durationText);
      }

      // overview_polyline fallback
      final overviewEnc =
          route['overview_polyline']?['points'] as String? ?? '';
      if (overviewEnc.isNotEmpty) {
        final ovPts = _decode(overviewEnc);
        // ignore: avoid_print
        print(
          '$tag overview_pts=${ovPts.length}, ETA=$durationText (fallback)',
        );
        return RouteResult(points: ovPts, durationText: durationText);
      }

      // ignore: avoid_print
      print('$tag No polyline data in response → straight-line fallback');
      return RouteResult(points: [origin, dest], durationText: durationText);
    } catch (e, st) {
      // ignore: avoid_print
      print('$tag Exception: $e\n$st');
      return RouteResult(points: [origin, dest]);
    }
  }

  List<LatLng> _decode(String encoded) {
    final pts = <LatLng>[];
    int i = 0;
    final len = encoded.length;
    int lat = 0, lng = 0;
    while (i < len) {
      int b, shift = 0, r = 0;
      do {
        b = encoded.codeUnitAt(i++) - 63;
        r |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (r & 1) != 0 ? ~(r >> 1) : r >> 1;
      shift = 0;
      r = 0;
      do {
        b = encoded.codeUnitAt(i++) - 63;
        r |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (r & 1) != 0 ? ~(r >> 1) : r >> 1;
      pts.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return pts;
  }

  String _clip(String s, [int max = 500]) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  String _fmt(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';
}
