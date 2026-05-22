// Platform selector: web targets use dart:js_interop DirectionsService (no CORS),
// native targets (Android/iOS) use the Google Directions REST API over HTTP.
// Both files export the same public API: RouteResult + RoutePolylineService.
export 'route_polyline_service_mobile.dart'
    if (dart.library.html) 'route_polyline_service_web.dart';
