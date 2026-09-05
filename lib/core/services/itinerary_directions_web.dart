import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Future<Map<String, dynamic>> fetchItineraryDirections(
  String apiKey,
  List<LatLng> points, {
  bool requestTraffic = false,
}) async {
  final params = jsonEncode({
    'originLat': points.first.latitude,
    'originLng': points.first.longitude,
    'destLat': points.last.latitude,
    'destLng': points.last.longitude,
    'stopovers': true,
    'requestTraffic': requestTraffic,
    'waypoints': points
        .skip(1)
        .take(points.length - 2)
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList(),
  });
  final fn = globalContext.getProperty<JSObject>('_flutterGetRoute'.toJS);
  final promise = fn.callMethod<JSPromise<JSString>>(
    'call'.toJS,
    globalContext,
    params.toJS,
  );
  final result = await promise.toDart.timeout(const Duration(seconds: 12));
  return jsonDecode(result.toDart) as Map<String, dynamic>;
}
