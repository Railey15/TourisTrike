// Conditional export: web targets use dart:js DirectionsService (no CORS),
// native targets use the Directions REST API over HTTP.
export 'route_polyline_impl_io.dart'
    if (dart.library.html) 'route_polyline_impl_web.dart';
