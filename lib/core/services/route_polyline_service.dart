// Platform selector: web targets use the Maps JavaScript Routes Library (no CORS),
// native targets (Android/iOS) use Routes API computeRoutes over HTTP.
// Both files export the same public API: RouteResult + RoutePolylineService.
export 'route_polyline_service_mobile.dart'
    if (dart.library.html) 'route_polyline_service_web.dart';
