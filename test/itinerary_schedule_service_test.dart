import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:touristrike/core/places/google_maps_api_key_resolver.dart';
import 'package:touristrike/core/services/itinerary_schedule_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('touristrike/config');
  const points = [
    LatLng(14.940, 120.900), // pickup
    LatLng(14.950, 120.910), // stop 1
    LatLng(14.960, 120.920), // stop 2
    LatLng(14.970, 120.930), // stop 3
    LatLng(14.980, 120.940), // drop-off
  ];

  tearDown(() {
    GoogleMapsApiKeyResolver.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'shared key resolver prefers injection then uses native fallback',
    () async {
      var nativeCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getGoogleMapsApiKey');
            nativeCalls++;
            return 'native-test-key';
          });

      expect(
        await GoogleMapsApiKeyResolver.resolve(explicitKey: 'injected-key'),
        'injected-key',
      );
      expect(nativeCalls, 0);
      expect(await GoogleMapsApiKeyResolver.resolve(), 'native-test-key');
      expect(await GoogleMapsApiKeyResolver.resolve(), 'native-test-key');
      expect(nativeCalls, 1);
    },
  );

  test('pickup, three stops and drop-off require exactly four legs', () async {
    final service = ItineraryScheduleService(
      apiKey: 'test-key',
      directionsLoader: (_, requestedPoints) async {
        expect(requestedPoints, points);
        return {
          'status': 'OK',
          'routes': [
            {
              'legs': [
                for (final values in const [
                  (600, 1000),
                  (720, 2000),
                  (480, 3000),
                  (900, 4000),
                ])
                  {
                    'duration': {'value': values.$1},
                    'distance': {'value': values.$2},
                  },
              ],
            },
          ],
        };
      },
    );

    final legs = await service.fetchTravelLegs(points);
    expect(legs.map((leg) => leg.durationMinutes), [10, 12, 8, 15]);
    expect(legs.map((leg) => leg.distanceMeters), [1000, 2000, 3000, 4000]);

    final timings = calculateItineraryTimings(
      pickupMinutes: 8 * 60,
      stayDurationMinutes: const [60, 30, 45],
      travelDurationMinutes: legs
          .take(3)
          .map((leg) => leg.durationMinutes)
          .toList(),
    );
    expect(timings[0].arrivalMinutes, 8 * 60 + 10);
    expect(timings[0].departureMinutes, 9 * 60 + 10);
    expect(timings[1].arrivalMinutes, 9 * 60 + 22);
    expect(timings[1].departureMinutes, 9 * 60 + 52);
    expect(timings[2].arrivalMinutes, 10 * 60);
    expect(timings[2].departureMinutes, 10 * 60 + 45);
    expect(
      calculateEstimatedDropoffMinutes(
        stopTimings: timings,
        finalTravelDurationMinutes: legs.last.durationMinutes,
      ),
      11 * 60,
    );
  });

  test('stay and pickup-time changes do not change the route cache key', () {
    final key = buildItineraryRouteKey(points);
    final before = calculateItineraryTimings(
      pickupMinutes: 8 * 60,
      stayDurationMinutes: const [30, 30, 30],
      travelDurationMinutes: const [10, 10, 10],
    );
    final after = calculateItineraryTimings(
      pickupMinutes: 9 * 60,
      stayDurationMinutes: const [60, 30, 30],
      travelDurationMinutes: const [10, 10, 10],
    );

    expect(buildItineraryRouteKey(points), key);
    expect(after.first.arrivalMinutes - before.first.arrivalMinutes, 60);
    expect(after[1].arrivalMinutes - before[1].arrivalMinutes, 90);
  });

  test('the final route leg participates in the 5 PM cutoff', () {
    final timings = calculateItineraryTimings(
      pickupMinutes: 16 * 60,
      stayDurationMinutes: const [30],
      travelDurationMinutes: const [10],
    );

    expect(timings.single.departureMinutes, 16 * 60 + 40);
    expect(
      calculateEstimatedDropoffMinutes(
        stopTimings: timings,
        finalTravelDurationMinutes: 30,
      ),
      greaterThan(17 * 60),
    );
  });

  test('destination reordering changes the route cache key', () {
    final reordered = [points[0], points[2], points[1], points[3], points[4]];
    expect(
      buildItineraryRouteKey(reordered),
      isNot(buildItineraryRouteKey(points)),
    );
  });

  test(
    'arrival and departure remain automatic while only stay is editable',
    () {
      final source = File(
        'lib/screens/tourist/package_booking_screen.dart',
      ).readAsStringSync();
      final start = source.indexOf('class _EditableItineraryTile');
      final end = source.indexOf('class _EditableTimeButton', start);
      final tile = source.substring(start, end);

      expect(tile, contains("label: 'Arrival (auto)'"));
      expect(tile, contains("label: 'Departure (auto)'"));
      expect(RegExp(r'onTap: null').allMatches(tile), hasLength(2));
      expect(RegExp(r'TextFormField\(').allMatches(tile), hasLength(1));
      expect(tile, contains("labelText: 'Time of Stay'"));
      expect(tile, isNot(contains('showTimePicker')));
      expect(RegExp(r'showTimePicker\(').allMatches(source), hasLength(1));
    },
  );

  test(
    'invalid coordinates are rejected before the loader is called',
    () async {
      var calls = 0;
      final service = ItineraryScheduleService(
        apiKey: 'test-key',
        directionsLoader: (_, _) async {
          calls++;
          return const {};
        },
      );

      await expectLater(
        service.fetchTravelLegs(const [LatLng(0, 0), LatLng(14, 120)]),
        throwsA(
          isA<ItineraryRouteException>().having(
            (error) => error.kind,
            'kind',
            ItineraryRouteFailure.invalidCoordinates,
          ),
        ),
      );
      expect(calls, 0);
    },
  );

  test('Google statuses and incomplete legs remain distinguishable', () async {
    for (final scenario in <(String, ItineraryRouteFailure)>[
      ('REQUEST_DENIED', ItineraryRouteFailure.unauthorized),
      ('OVER_QUERY_LIMIT', ItineraryRouteFailure.rateLimited),
      ('ZERO_RESULTS', ItineraryRouteFailure.noRoute),
      ('INVALID_REQUEST', ItineraryRouteFailure.invalidRequest),
    ]) {
      final service = ItineraryScheduleService(
        apiKey: 'test-key',
        directionsLoader: (_, _) async => {'status': scenario.$1},
      );
      await expectLater(
        service.fetchTravelLegs(points),
        throwsA(
          isA<ItineraryRouteException>().having(
            (error) => error.kind,
            'kind',
            scenario.$2,
          ),
        ),
      );
    }

    final disabled = ItineraryScheduleService(
      apiKey: 'test-key',
      directionsLoader: (_, _) async => {
        'status': 'REQUEST_DENIED',
        'error_message': 'This API is not enabled for the project.',
      },
    );
    await expectLater(
      disabled.fetchTravelLegs(points),
      throwsA(
        isA<ItineraryRouteException>().having(
          (error) => error.kind,
          'kind',
          ItineraryRouteFailure.apiNotEnabled,
        ),
      ),
    );

    final incomplete = ItineraryScheduleService(
      apiKey: 'test-key',
      directionsLoader: (_, _) async => {
        'status': 'OK',
        'routes': [
          {
            'legs': [
              {
                'duration': {'value': 60},
                'distance': {'value': 100},
              },
            ],
          },
        ],
      },
    );
    await expectLater(
      incomplete.fetchTravelLegs(points),
      throwsA(
        isA<ItineraryRouteException>().having(
          (error) => error.kind,
          'kind',
          ItineraryRouteFailure.incompleteLegs,
        ),
      ),
    );
  });

  test('mobile Directions classifies HTTP authorization failures', () async {
    await http.runWithClient(
      () async {
        final service = ItineraryScheduleService(apiKey: 'test-key');
        await expectLater(
          service.fetchTravelLegs(points),
          throwsA(
            isA<ItineraryRouteException>().having(
              (error) => error.kind,
              'kind',
              ItineraryRouteFailure.unauthorized,
            ),
          ),
        );
      },
      () => MockClient((request) async {
        expect(request.url.host, 'maps.googleapis.com');
        expect(request.url.queryParameters['key'], 'test-key');
        return http.Response(jsonEncode({'status': 'REQUEST_DENIED'}), 403);
      }),
    );
  });

  test(
    'mobile Directions distinguishes missing key and network failure',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => '');
      await expectLater(
        const ItineraryScheduleService(apiKey: '').fetchTravelLegs(points),
        throwsA(
          isA<ItineraryRouteException>().having(
            (error) => error.kind,
            'kind',
            ItineraryRouteFailure.notConfigured,
          ),
        ),
      );

      await http.runWithClient(() async {
        await expectLater(
          const ItineraryScheduleService(
            apiKey: 'test-key',
          ).fetchTravelLegs(points),
          throwsA(
            isA<ItineraryRouteException>().having(
              (error) => error.kind,
              'kind',
              ItineraryRouteFailure.network,
            ),
          ),
        );
      }, () => MockClient((_) async => throw const SocketException('offline')));
    },
  );
}
