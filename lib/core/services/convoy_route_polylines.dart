import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/convoy_state.dart';
import 'booking_driver_markers.dart';
import 'route_polyline_service.dart';

typedef ConvoyRouteLoader =
    Future<RouteResult> Function(LatLng origin, LatLng destination);

/// Route visibility only; never advances an assignment or changes a marker.
Map<String, LatLng> convoyRouteOrigins({
  required List<ConvoyDriverSnapshot> drivers,
  required String tourStatus,
  Map<String, LatLng> positions = const {},
}) {
  final eligibleStates = switch (tourStatus) {
    'driver_accepted' || 'driver_en_route' || 'driver_arrived' => {
      ConvoyJourneyState.assigned,
      ConvoyJourneyState.enRoutePickup,
    },
    'picked_up' ||
    'on_tour' ||
    'en_route_to_spot' ||
    'at_spot' => {ConvoyJourneyState.boarded, ConvoyJourneyState.enRouteStop},
    'en_route_to_dropoff' ||
    'ready_to_complete' => {ConvoyJourneyState.enRouteDropoff},
    _ => <ConvoyJourneyState>{},
  };
  return {
    for (final driver in drivers)
      if (driver.assignmentStatus == 'accepted' &&
          eligibleStates.contains(driver.journeyState))
        if (positions[driver.driverId] ??
                (driver.latitude != null && driver.longitude != null
                    ? LatLng(driver.latitude!, driver.longitude!)
                    : null)
            case final point?)
          if (validDriverCoordinates(point.latitude, point.longitude))
            driver.driverId: point,
  };
}

class _Request {
  _Request(this.origin, this.destination, this.phase);
  final LatLng origin;
  final LatLng destination;
  final String phase;
  bool loading = false;
}

/// Retains independent raw routes by driver ID. Only changed origins/targets
/// are fetched again. Removed/arrived drivers invalidate their pending requests.
class ConvoyRouteState {
  final _requests = <String, _Request>{};
  final _routes = <String, RouteResult>{};
  Map<String, RouteResult> get routes => Map.unmodifiable(_routes);

  void clear() {
    _requests.clear();
    _routes.clear();
  }

  Future<void> refresh({
    required Map<String, LatLng> origins,
    required LatLng? destination,
    required String phase,
    required ConvoyRouteLoader load,
    required VoidCallback onChanged,
  }) async {
    // One driver's arrival changes the aggregate tour_status, but should not
    // refetch another driver's unchanged approach to the same pickup.
    final routePhase = switch (phase) {
      'driver_accepted' || 'driver_en_route' || 'driver_arrived' => 'pickup',
      'picked_up' || 'on_tour' || 'en_route_to_spot' || 'at_spot' => 'tour',
      'en_route_to_dropoff' || 'ready_to_complete' => 'dropoff',
      _ => phase,
    };
    if (destination == null || origins.isEmpty) {
      clear();
      onChanged();
      return;
    }
    _requests.removeWhere((id, _) => !origins.containsKey(id));
    _routes.removeWhere((id, _) => !origins.containsKey(id));
    final pending = <(String, _Request)>[];
    for (final entry in origins.entries) {
      var request = _requests[entry.key];
      if (request == null ||
          request.origin != entry.value ||
          request.destination != destination ||
          request.phase != routePhase) {
        request = _Request(entry.value, destination, routePhase);
        _requests[entry.key] = request;
        _routes.remove(entry.key);
      }
      if (!request.loading && !_routes.containsKey(entry.key)) {
        request.loading = true;
        pending.add((entry.key, request));
      }
    }
    // Prune obsolete geometry immediately, before any network responses.
    onChanged();
    await Future.wait(
      pending.map((entry) async {
        final (id, request) = entry;
        try {
          final route = await load(
            request.origin,
            request.destination,
          ).timeout(const Duration(seconds: 20));
          if (identical(_requests[id], request)) _routes[id] = route;
        } catch (_) {
          if (identical(_requests[id], request)) _routes.remove(id);
        } finally {
          request.loading = false;
          if (identical(_requests[id], request)) onChanged();
        }
      }),
    );
  }
}

typedef _Point = math.Point<double>;
typedef _Edge = ({_Point a, _Point b});

/// Draw the union of convoy paths, not one full overlaid stroke per driver.
/// A stable driver order owns shared geometry. Later routes keep ALL uncovered
/// branches, even when Google samples the same road with different vertices.
/// Only nearly parallel segments within 3m are shared; crossings and separate
/// approaches stay distinct. Raw per-driver routes/ETAs are never merged.
Set<Polyline> buildConvoyRoutePolylines(
  Map<String, RouteResult> routes, {
  double toleranceMeters = 3,
  Color color = const Color(0xFF2A86FF),
}) {
  final ids = routes.keys.toList()..sort();
  final firstPoint = ids.expand((id) => routes[id]!.points).firstOrNull;
  if (firstPoint == null) return {};
  const metersPerDegree = 111195.0;
  final longitudeScale =
      metersPerDegree * math.cos(firstPoint.latitude * math.pi / 180);
  _Point project(LatLng p) => _Point(
    (p.longitude - firstPoint.longitude) * longitudeScale,
    (p.latitude - firstPoint.latitude) * metersPerDegree,
  );
  LatLng unproject(_Point p) => LatLng(
    firstPoint.latitude + p.y / metersPerDegree,
    firstPoint.longitude + p.x / longitudeScale,
  );
  final covered = <_Edge>[];
  final lines = <Polyline>{};
  for (final id in ids) {
    final points = routes[id]!.points;
    var fragment = <_Point>[];
    var part = 0;
    void flush() {
      if (fragment.length > 1) {
        lines.add(
          Polyline(
            polylineId: PolylineId('driver_route_${id}_${part++}'),
            points: fragment.map(unproject).toList(),
            color: color,
            width: 5,
            geodesic: true,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        );
      }
      fragment = [];
    }

    for (var i = 1; i < points.length; i++) {
      final a = project(points[i - 1]);
      final b = project(points[i]);
      final vector = b - a;
      if (vector.magnitude < .01) continue;
      var visible = <(double, double)>[(0, 1)];
      for (final edge in covered) {
        final overlap = _overlap(a, b, edge, toleranceMeters);
        if (overlap == null) continue;
        final (start, end) = overlap;
        visible = [
          for (final (lo, hi) in visible)
            if (end <= lo || start >= hi)
              (lo, hi)
            else ...[
              if (start > lo) (lo, start),
              if (end < hi) (end, hi),
            ],
        ];
        if (visible.isEmpty) break;
      }
      if (visible.isEmpty) {
        flush();
        continue;
      }
      for (final (lo, hi) in visible) {
        final start = a + vector * lo;
        final end = a + vector * hi;
        if (start.distanceTo(end) < .01) continue;
        if (fragment.isNotEmpty && fragment.last.distanceTo(start) > .01) {
          flush();
        }
        if (fragment.isEmpty) fragment.add(start);
        fragment.add(end);
        covered.add((a: start, b: end));
        if (hi < 1) flush();
      }
    }
    flush();
  }
  return lines;
}

double _dot(_Point a, _Point b) => a.x * b.x + a.y * b.y;
double _cross(_Point a, _Point b) => a.x * b.y - a.y * b.x;

/// Candidate-edge parameter interval covered by an existing road segment.
/// Projection handles partial overlap and unequal polyline sampling. The
/// perpendicular-distance interval handles slight Directions rounding drift.
(double, double)? _overlap(_Point a, _Point b, _Edge edge, double tolerance) {
  final u = b - a;
  final v = edge.b - edge.a;
  final length = u.magnitude;
  final otherLength = v.magnitude;
  if (length < .01 ||
      otherLength < .01 ||
      _dot(u, v).abs() / (length * otherLength) < .995) {
    return null;
  }
  final p = _dot(edge.a - a, u) / (length * length);
  final q = _dot(edge.b - a, u) / (length * length);
  var lo = math.max(0.0, math.min(p, q));
  var hi = math.min(1.0, math.max(p, q));
  if (hi <= lo) return null;
  final distance = _cross(a - edge.a, v) / otherLength;
  final slope = _cross(u, v) / otherLength;
  if (slope.abs() < 1e-9) {
    if (distance.abs() > tolerance) return null;
  } else {
    final t1 = (-tolerance - distance) / slope;
    final t2 = (tolerance - distance) / slope;
    lo = math.max(lo, math.min(t1, t2));
    hi = math.min(hi, math.max(t1, t2));
  }
  return (hi - lo) * length > .01 ? (lo, hi) : null;
}
