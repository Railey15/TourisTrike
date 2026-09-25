import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

/// The database supplies the same versioned GeoJSON used by booking triggers.
/// Coordinates are GeoJSON order (longitude, latitude). Ring edges are covered;
/// hole interiors are excluded. No address text participates in containment.
class BookingServiceArea {
  BookingServiceArea.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      municipality = json['municipality'] as String,
      province = json['province'] as String,
      version = json['version'] as String {
    final geometry = json['geometry'] as Map;
    final raw = geometry['coordinates'] as List;
    final polygons = switch (geometry['type']) {
      'Polygon' => [raw],
      'MultiPolygon' => raw,
      _ => throw const FormatException('Unsupported service-area boundary'),
    };
    rings = List.unmodifiable(
      polygons.map(
        (polygon) => List<List<List<double>>>.unmodifiable(
          (polygon as List).map(
            (ring) => List<List<double>>.unmodifiable(
              (ring as List).map(
                (point) => List<double>.unmodifiable(
                  (point as List).map((n) => (n as num).toDouble()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (rings.isEmpty ||
        rings.any(
          (p) =>
              p.isEmpty ||
              p.any(
                (r) =>
                    r.length < 4 ||
                    r.any(
                      (c) =>
                          c.length != 2 ||
                          !c[0].isFinite ||
                          !c[1].isFinite ||
                          c[0].abs() > 180 ||
                          c[1].abs() > 90,
                    ) ||
                    r.first[0] != r.last[0] ||
                    r.first[1] != r.last[1],
              ),
        )) {
      throw const FormatException('Invalid service-area boundary');
    }
    final points = rings.expand((p) => p).expand((r) => r);
    west = points.map((p) => p[0]).reduce(math.min);
    east = points.map((p) => p[0]).reduce(math.max);
    south = points.map((p) => p[1]).reduce(math.min);
    north = points.map((p) => p[1]).reduce(math.max);
  }

  final String id, municipality, province, version;
  late final List<List<List<List<double>>>> rings;
  late final double west, east, south, north;
  double get centerLatitude => (south + north) / 2;
  double get centerLongitude => (west + east) / 2;
  String get outsideMessage =>
      'Outside service area. Please select a location within $municipality.';

  // A conservative enclosing circle for Google's legacy autocomplete. The
  // polygon filter below remains authoritative, including holes and islands.
  Map<String, String> get searchBounds {
    final radius =
        (111320 *
                math.sqrt(
                  math.pow(north - south, 2) + math.pow(east - west, 2),
                ) /
                2)
            .ceil() +
        1;
    return {
      'location': '$centerLatitude,$centerLongitude',
      'radius': '${math.min(radius, 50000)}',
      if (radius <= 50000) 'strictbounds': 'true',
    };
  }

  bool contains(double latitude, double longitude) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        longitude < west - _epsilon ||
        longitude > east + _epsilon ||
        latitude < south - _epsilon ||
        latitude > north + _epsilon) {
      return false;
    }
    for (final polygon in rings) {
      final outer = _ring(polygon.first, longitude, latitude);
      if (outer == 2) return true;
      if (outer == 0) continue;
      var inHole = false;
      for (final hole in polygon.skip(1)) {
        final result = _ring(hole, longitude, latitude);
        if (result == 2) return true;
        if (result == 1) inHole = true;
      }
      if (!inHole) return true;
    }
    return false;
  }

  static const _epsilon = 1e-10;
  static int _ring(List<List<double>> ring, double x, double y) {
    var inside = false;
    for (var i = 1; i < ring.length; i++) {
      final a = ring[i - 1], b = ring[i];
      final dx = b[0] - a[0], dy = b[1] - a[1];
      final length = math.sqrt(dx * dx + dy * dy);
      if ((dx * (y - a[1]) - dy * (x - a[0])).abs() <= _epsilon * length &&
          x >= math.min(a[0], b[0]) - _epsilon &&
          x <= math.max(a[0], b[0]) + _epsilon &&
          y >= math.min(a[1], b[1]) - _epsilon &&
          y <= math.max(a[1], b[1]) + _epsilon) {
        return 2;
      }
      if ((a[1] > y) != (b[1] > y) && x < dx * (y - a[1]) / dy + a[0]) {
        inside = !inside;
      }
    }
    return inside ? 1 : 0;
  }

  static Future<BookingServiceArea> forPackage(dynamic packageId) async {
    try {
      final data = await Supabase.instance.client.rpc(
        'booking_service_area',
        params: {'p_package_id': packageId},
      );
      return BookingServiceArea.fromJson(
        Map<String, dynamic>.from(data as Map),
      );
    } catch (_) {
      throw StateError(
        'The service area for this package could not be verified. Please retry or contact support.',
      );
    }
  }
}
