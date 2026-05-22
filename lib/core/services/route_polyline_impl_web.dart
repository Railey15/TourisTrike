// ignore_for_file: avoid_web_libraries_in_flutter
//
// Web-only implementation. Delegates to window._flutterGetRoute() — a small
// async JS helper injected in web/index.html — which uses
// google.maps.DirectionsService (already loaded, no CORS issues).

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteResult {
  const RouteResult({required this.points, this.durationText});
  final List<LatLng> points;
  final String? durationText;
}

class RoutePolylineService {
  const RoutePolylineService({required this.apiKey});

  // API key unused on web — Maps JS API is loaded with its key in index.html.
  // ignore: unused_field
  final String apiKey;

  Future<RouteResult> fetchRoute(
    LatLng origin,
    LatLng dest, {
    List<LatLng> waypoints = const [],
  }) async {
    const tag = '[RoutePolyline/Web]';

    // ignore: avoid_print
    print('$tag ${_fmt(origin)} → ${_fmt(dest)}'
        '${waypoints.isNotEmpty ? " via ${waypoints.length} wp" : ""}');

    try {
      // Encode all params as a single JSON string so callMethod stays within
      // its 4-argument limit (method + up to 4 positional args).
      final paramsJson = jsonEncode({
        'originLat': origin.latitude,
        'originLng': origin.longitude,
        'destLat': dest.latitude,
        'destLng': dest.longitude,
        'waypoints': waypoints
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
      });

      // Get window._flutterGetRoute and call it: fn.call(window, paramsJson)
      final JSObject window = globalContext;
      final fn = window.getProperty<JSObject>('_flutterGetRoute'.toJS);

      // callMethod('call', thisArg, arg0) → fn.call(window, paramsJson) in JS
      final JSAny? promise = fn.callMethod(
        'call'.toJS,
        window,
        paramsJson.toJS,
      );

      if (promise == null) {
        // ignore: avoid_print
        print('$tag _flutterGetRoute returned null — helper not installed');
        return RouteResult(points: [origin, dest]);
      }

      // Await the JS Promise<string>
      final String jsonStr;
      try {
        jsonStr = await (promise as JSPromise<JSString>).toDart
            .then((v) => v.toDart);
      } catch (e) {
        // ignore: avoid_print
        print('$tag Promise rejected: $e');
        return RouteResult(points: [origin, dest]);
      }

      // ignore: avoid_print
      print('$tag raw result: ${jsonStr.length > 200 ? '${jsonStr.substring(0, 200)}…' : jsonStr}');

      final Map<String, dynamic> data;
      try {
        data = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (e) {
        // ignore: avoid_print
        print('$tag JSON parse error: $e');
        return RouteResult(points: [origin, dest]);
      }

      final status = data['status'] as String? ?? 'UNKNOWN';
      // ignore: avoid_print
      print('$tag status=$status');

      if (status != 'OK') {
        final err = data['error'] as String? ?? '';
        // ignore: avoid_print
        print('$tag non-OK${err.isNotEmpty ? ": $err" : ""}');
        return RouteResult(points: [origin, dest]);
      }

      final eta = data['eta'] as String?;
      final rawPts = data['points'] as List<dynamic>? ?? [];

      if (rawPts.isEmpty) {
        // ignore: avoid_print
        print('$tag OK but empty points array');
        return RouteResult(points: [origin, dest], durationText: eta);
      }

      final pts = rawPts.map((p) {
        final pair = p as List<dynamic>;
        return LatLng((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
      }).toList();

      // ignore: avoid_print
      print('$tag decoded ${pts.length} pts, ETA=$eta');
      return RouteResult(points: pts, durationText: eta);
    } catch (e, st) {
      // ignore: avoid_print
      print('$tag Exception: $e\n$st');
      return RouteResult(points: [origin, dest]);
    }
  }

  String _fmt(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';
}
