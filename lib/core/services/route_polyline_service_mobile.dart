// Native (iOS/Android) implementation.
// Uses Routes API computeRoutes over HTTP — no CORS restrictions on native.
// Conditional export in route_polyline_service.dart selects this for non-web targets.

import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../places/google_maps_api_key_resolver.dart';
import 'google_routes_api.dart';

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

    final points = [origin, ...waypoints, dest];
    final uri = Uri.parse(googleRoutesEndpoint);

    // ignore: avoid_print
    print('$tag POST computeRoutes (key omitted from log)');

    try {
      final res = await http
          .post(
            uri,
            headers: googleRoutesHeaders(effectiveApiKey),
            body: googleRoutesRequestBody(points, trafficAware: true),
          )
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

      final routes = (body['routes'] as List?) ?? const [];
      if (routes.isEmpty) {
        // ignore: avoid_print
        print('$tag No routes returned');
        return RouteResult(points: [origin, dest]);
      }

      final route = routes.first as Map;
      final durationText = googleDurationText(route['duration']);
      final overviewEnc =
          (route['polyline'] as Map?)?['encodedPolyline'] as String? ?? '';
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
      return RouteResult(
        points: [origin, dest],
        durationText: durationText.isEmpty ? null : durationText,
      );
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
