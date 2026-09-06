import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'itinerary_route_exception.dart';

Future<Map<String, dynamic>> fetchItineraryDirections(
  String apiKey,
  List<LatLng> points, {
  bool requestTraffic = false,
}) async {
  if (points.length < 2 ||
      points.any(
        (point) =>
            !point.latitude.isFinite ||
            !point.longitude.isFinite ||
            point.latitude.abs() > 90 ||
            point.longitude.abs() > 180 ||
            (point.latitude == 0 && point.longitude == 0),
      )) {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.invalidCoordinates,
      pointCount: points.length,
    );
  }

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
  try {
    final result = await promise.toDart.timeout(const Duration(seconds: 12));
    final decoded = jsonDecode(result.toDart);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    return decoded;
  } on ItineraryRouteException {
    rethrow;
  } on FormatException {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.malformedResponse,
      pointCount: points.length,
    );
  } catch (_) {
    throw ItineraryRouteException(
      kind: ItineraryRouteFailure.network,
      pointCount: points.length,
    );
  }
}
