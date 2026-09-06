import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/models/convoy_state.dart';
import 'package:touristrike/core/services/booking_driver_markers.dart';
import 'package:touristrike/core/services/stable_arrival_detector.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

ConvoyDriverSnapshot driver(String id, {bool located = true}) =>
    ConvoyDriverSnapshot(
      driverId: id,
      driverName: 'Driver $id',
      plateNumber: id,
      journeyState: ConvoyJourneyState.enRouteStop,
      currentStopIndex: 0,
      stateUpdatedAt: DateTime.utc(2026, 9, 6),
      latitude: located ? 15 : null,
      longitude: located ? 121 : null,
      lastLocationAt: located ? DateTime.utc(2026, 9, 6) : null,
    );

void main() {
  test(
    'all viewers get identical membership and icons; only YOU label changes',
    () {
      final roster = [driver('A'), driver('B')];
      final icon = BitmapDescriptor.defaultMarker;
      for (final viewer in ['tourist', 'A', 'B']) {
        final markers = buildBookingDriverMarkers(
          drivers: roster,
          icon: icon,
          viewerId: viewer,
        );
        expect(markers.map((m) => m.markerId.value).toSet(), {
          'driver_A',
          'driver_B',
        });
        expect(markers.every((m) => identical(m.icon, icon)), isTrue);
        final own = markers.where((m) => m.infoWindow.title!.contains('(YOU)'));
        expect(own.length, viewer == 'tourist' ? 0 : 1);
        if (viewer != 'tourist') {
          expect(own.single.markerId.value, 'driver_$viewer');
        }
      }
    },
  );

  test('late first GPS fix adds B and moving A preserves B without reload', () {
    var roster = [driver('A'), driver('B', located: false)];
    Set<Marker> markers() => buildBookingDriverMarkers(
      drivers: roster,
      icon: BitmapDescriptor.defaultMarker,
    );
    expect(roster.length, 2);
    expect(markers().length, 1);
    roster = mergeBookingDriverLocation(roster, {
      'driver_id': 'B',
      'latitude': 15.1,
      'longitude': 121.1,
      'updated_at': '2026-09-06T00:01:00Z',
    });
    expect(markers().length, 2);
    final b = roster.last;
    roster = mergeBookingDriverLocation(roster, {
      'driver_id': 'A',
      'latitude': 15.2,
      'longitude': 121.2,
      'updated_at': '2026-09-06T00:02:00Z',
    });
    expect(identical(roster.last, b), isTrue);
    expect(markers().first.position, const LatLng(15.2, 121.2));
    final a = roster.first;
    for (final row in [
      {
        'driver_id': 'A',
        'latitude': 15,
        'longitude': 121,
        'updated_at': '2026-09-05T00:00:00Z',
      },
      {
        'driver_id': 'A',
        'latitude': 0,
        'longitude': 0,
        'updated_at': '2026-09-07T00:00:00Z',
      },
      {
        'driver_id': 'outsider',
        'latitude': 15,
        'longitude': 121,
        'updated_at': '2026-09-07T00:00:00Z',
      },
    ]) {
      roster = mergeBookingDriverLocation(roster, row);
    }
    expect(identical(roster.first, a), isTrue);
    expect(roster.length, 2);
  });

  for (final enabled in [false, true]) {
    test(
      'test=$enabled: automatic GPS uses real RPC, manual uses authorized mode',
      () async {
        final paths = <String>[];
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            paths.add(request.url.path.split('/').last);
            return http.Response(
              jsonEncode(
                paths.last == 'debug_get_test_booking_state'
                    ? {'enabled': enabled}
                    : {'success': true},
              ),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        final repo = TourisTrikeRepository(client: client);
        await repo.advanceDriverJourneyState(
          bookingId: 'booking',
          targetState: ConvoyJourneyState.enRoutePickup,
        );
        expect(
          paths.last,
          enabled
              ? 'debug_advance_driver_journey_state'
              : 'advance_driver_journey_state',
        );
        paths.clear();
        final detector = StableArrivalDetector(radiusMeters: 150);
        for (final seconds in [0, 3, 6]) {
          final time = DateTime.utc(2026, 9, 6).add(Duration(seconds: seconds));
          if (detector.observe(
            target: 'stop',
            distanceMeters: 30,
            accuracyMeters: 5,
            sampledAt: time,
            now: time,
          )) {
            await repo.advanceDriverJourneyState(
              bookingId: 'booking',
              targetState: ConvoyJourneyState.atStop,
              automaticArrival: true,
            );
          }
        }
        expect(paths, ['advance_driver_journey_state']);
        // Even callers omitting the automaticArrival hint cannot use the
        // operational bypass for an arrival transition.
        for (final stage in [
          ConvoyJourneyState.atPickup,
          ConvoyJourneyState.atStop,
          ConvoyJourneyState.atDropoff,
        ]) {
          paths.clear();
          await repo.advanceDriverJourneyState(
            bookingId: 'booking',
            targetState: stage,
          );
          expect(paths, ['advance_driver_journey_state']);
        }
        await client.dispose();
      },
    );
  }

  test('tracking keeps GPS automation enabled independently of bypass', () {
    final source = File(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    ).readAsStringSync();
    for (final name in [
      '_detectAutomaticArrival(Position position)',
      '_recoverGpsFix()',
    ]) {
      final start = source.indexOf('Future<void> $name');
      final end = source.indexOf('\n  Future', start + 1);
      expect(
        source.substring(start, end < 0 ? source.length : end),
        isNot(contains('_bypassTransactionValidation')),
      );
    }
    expect(source, contains('automaticArrival: true'));
  });
}
