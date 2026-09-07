import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:touristrike/core/models/convoy_state.dart';
import 'package:touristrike/core/services/booking_driver_markers.dart';
import 'package:touristrike/core/services/convoy_route_polylines.dart';
import 'package:touristrike/core/services/route_polyline_service.dart';

LatLng point(double x, double y) =>
    LatLng(15 + y / 111195, 121 + x / (111195 * math.cos(15 * math.pi / 180)));
RouteResult route(List<LatLng> points) =>
    RouteResult(points: points, durationText: '6 min');
double length(Set<Polyline> lines) => lines.fold(0.0, (sum, line) {
  var total = sum;
  for (var i = 1; i < line.points.length; i++) {
    final a = line.points[i - 1], b = line.points[i];
    final x =
        (b.longitude - a.longitude) * 111195 * math.cos(15 * math.pi / 180);
    final y = (b.latitude - a.latitude) * 111195;
    total += math.sqrt(x * x + y * y);
  }
  return total;
});

ConvoyDriverSnapshot driver(String id, ConvoyJourneyState state) =>
    ConvoyDriverSnapshot(
      driverId: id,
      driverName: id,
      plateNumber: '',
      journeyState: state,
      currentStopIndex: 0,
      stateUpdatedAt: DateTime(2026),
      latitude: 15,
      longitude: 121,
    );

void main() {
  test('one driver renders one route', () {
    final lines = buildConvoyRoutePolylines({
      'one': route([point(0, 0), point(100, 0)]),
    });
    expect(lines, hasLength(1));
    expect(length(lines), closeTo(100, .01));
  });

  test('different approaches remain visible', () {
    final lines = buildConvoyRoutePolylines({
      'one': route([point(-100, -100), point(0, 0)]),
      'two': route([point(-100, 100), point(0, 0)]),
    });
    expect(lines, hasLength(2));
    expect(length(lines), closeTo(2 * math.sqrt(20000), .01));
  });

  test('identical routes with unequal sampling render once', () {
    final lines = buildConvoyRoutePolylines({
      'one': route([point(0, 0), point(100, 0)]),
      'two': route([point(0, 0), point(25, 0), point(70, 0), point(100, 0)]),
    });
    expect(lines, hasLength(1));
    expect(length(lines), closeTo(100, .01));
  });

  test('distinct branches meet a single shared trunk', () {
    final lines = buildConvoyRoutePolylines({
      'one': route([point(-100, 0), point(0, 0), point(100, 0)]),
      'two': route([point(0, -100), point(0, 0), point(50, 0), point(100, 0)]),
    });
    expect(length(lines), closeTo(300, .01)); // Not 400m of stacked strokes.
    expect(lines.expand((line) => line.points), contains(point(0, -100)));
  });

  test('joining inside an existing edge preserves the approach', () {
    final lines = buildConvoyRoutePolylines({
      'one': route([point(0, 0), point(100, 0)]),
      'two': route([point(50, -50), point(50, 0), point(100, 0)]),
    });
    expect(length(lines), closeTo(150, .01));
    expect(lines, hasLength(2));
  });

  test('shared middle segment retains branches after divergence', () {
    final lines = buildConvoyRoutePolylines({
      'one': route([point(0, 0), point(100, 0), point(200, 100)]),
      'two': route([
        point(0, -100),
        point(0, 0),
        point(100, 0),
        point(200, -100),
      ]),
    });
    expect(lines, hasLength(3));
    expect(length(lines), closeTo(200 + 2 * math.sqrt(20000), .01));
  });

  test('near-identical geometry shares a stroke; separate roads do not', () {
    for (final offset in [1.0, 10.0]) {
      final lines = buildConvoyRoutePolylines({
        'one': route([point(0, 0), point(100, 0)]),
        'two': route([point(0, offset), point(100, offset)]),
      });
      expect(lines, hasLength(offset == 1 ? 1 : 2));
    }
  });

  test('crossing roads are not mistaken for a common path', () {
    final lines = buildConvoyRoutePolylines({
      'one': route([point(-100, 0), point(100, 0)]),
      'two': route([point(0, -100), point(0, 100)]),
    });
    expect(length(lines), closeTo(400, .01));
  });

  test('driver order cannot change shared geometry ownership', () {
    final a = route([point(0, 0), point(100, 0)]);
    final b = route([point(50, -50), point(50, 0), point(100, 0)]);
    expect(
      buildConvoyRoutePolylines({'two': b, 'one': a}),
      buildConvoyRoutePolylines({'one': a, 'two': b}),
    );
  });

  test(
    'GPS replaces only that driver route and retains other cached routes',
    () async {
      final state = ConvoyRouteState();
      final a = point(0, 0), b = point(0, 100), target = point(100, 0);
      final calls = <LatLng>[];
      Future<RouteResult> load(LatLng origin, LatLng destination) async {
        calls.add(origin);
        return route([origin, destination]);
      }

      Future<void> update(LatLng origin) => state.refresh(
        origins: {'one': origin, 'two': b},
        destination: target,
        phase: 'driver_en_route',
        load: load,
        onChanged: () {},
      );
      await update(a);
      final second = state.routes['two'];
      await update(point(20, 0));
      expect(state.routes, hasLength(2));
      expect(state.routes['one']!.points.first, point(20, 0));
      expect(identical(state.routes['two'], second), isTrue);
      expect(calls.where((p) => p == b), hasLength(1));
      await update(point(20, 0));
      expect(calls, hasLength(3));
    },
  );

  test('late GPS response cannot restore the previous route', () async {
    final state = ConvoyRouteState();
    final old = Completer<RouteResult>(), latest = Completer<RouteResult>();
    final a = point(0, 0), moved = point(20, 0), target = point(100, 0);
    Future<void> update(LatLng origin, Completer<RouteResult> result) =>
        state.refresh(
          origins: {'one': origin},
          destination: target,
          phase: 'driver_en_route',
          load: (_, _) => result.future,
          onChanged: () {},
        );
    final first = update(a, old), second = update(moved, latest);
    latest.complete(route([moved, target]));
    await second;
    old.complete(route([a, target]));
    await first;
    expect(state.routes['one']!.points.first, moved);
  });

  test(
    'arrival removes pickup route immediately but keeps both markers',
    () async {
      final state = ConvoyRouteState();
      var drivers = [
        driver('one', ConvoyJourneyState.enRoutePickup),
        driver('two', ConvoyJourneyState.enRoutePickup),
      ];
      Future<void> refresh() => state.refresh(
        origins: convoyRouteOrigins(
          drivers: drivers,
          tourStatus: 'driver_en_route',
        ),
        destination: point(100, 0),
        phase: 'driver_en_route',
        load: (a, b) async => route([a, b]),
        onChanged: () {},
      );
      await refresh();
      drivers = [driver('one', ConvoyJourneyState.atPickup), drivers[1]];
      final pending = refresh();
      expect(state.routes.keys, ['two']);
      await pending;
      expect(
        buildBookingDriverMarkers(
          drivers: drivers,
          icon: BitmapDescriptor.defaultMarker,
        ),
        hasLength(2),
      );
      expect(buildConvoyRoutePolylines(state.routes), hasLength(1));
    },
  );

  test('clearing destination invalidates all pending responses', () async {
    final state = ConvoyRouteState();
    final pending = Completer<RouteResult>();
    final request = state.refresh(
      origins: {'one': point(0, 0)},
      destination: point(100, 0),
      phase: 'driver_en_route',
      load: (_, _) => pending.future,
      onChanged: () {},
    );
    await state.refresh(
      origins: {},
      destination: null,
      phase: '',
      load: (_, _) => throw StateError('must not fetch'),
      onChanged: () {},
    );
    pending.complete(route([point(0, 0), point(100, 0)]));
    await request;
    expect(state.routes, isEmpty);
  });
}
