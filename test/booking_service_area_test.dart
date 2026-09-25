import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:touristrike/core/places/booking_service_area.dart';
import 'package:touristrike/core/places/booking_location_service.dart';
import 'package:touristrike/widgets/booking_location_map_picker.dart';
import 'fixtures/booking_service_area_fixture.dart';

class _Maps extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    void Function(int) onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) => const SizedBox.expand();
}

Map<String, dynamic> place(double lat, double lng) => {
  'formatted_address': 'A location labelled Bustos, Philippines',
  'geometry': {
    'location': {'lat': lat, 'lng': lng},
  },
  'address_components': [
    {
      'types': ['country'],
      'long_name': 'Philippines',
      'short_name': 'PH',
    },
  ],
};
http.Response reply(Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), 200);

void main() {
  test(
    'holes, islands, edges and near-boundary points match SQL semantics',
    () {
      final area = BookingServiceArea.fromJson({
        ...testAreaJson,
        'geometry': {
          'type': 'MultiPolygon',
          'coordinates': [
            [
              [
                [120, 14],
                [121, 14],
                [121, 15],
                [120, 15],
                [120, 14],
              ],
              [
                [120.4, 14.4],
                [120.6, 14.4],
                [120.6, 14.6],
                [120.4, 14.6],
                [120.4, 14.4],
              ],
            ],
            [
              [
                [122, 14],
                [123, 14],
                [123, 15],
                [122, 15],
                [122, 14],
              ],
            ],
          ],
        },
      });
      for (final point in [
        (14.2, 120.2, true),
        (14.2, 119.9, false),
        (14.0, 120.5, true),
        (14.0, 120.0, true),
        (14 - 1e-8, 120.5, false),
        (14 + 1e-8, 120.5, true),
        (14.5, 120.5, false),
        (14.4, 120.5, true),
        (14.5, 122.5, true),
        (14.5, 121.5, false),
        (double.nan, 120.0, false),
        (double.infinity, 120.0, false),
      ]) {
        expect(
          area.contains(point.$1, point.$2),
          point.$3,
          reason: '${point.$1},${point.$2}',
        );
      }
    },
  );

  test(
    'full-resolution municipality geometries cover their centres and vertices',
    () {
      final features =
          (jsonDecode(
                    File(
                      'supabase/service_areas/bulacan.geojson',
                    ).readAsStringSync(),
                  )
                  as Map)['features']
              as List;
      final centres = {
        'Baliuag': (14.9549, 120.9004),
        'Bustos': (14.9539783, 120.9185984),
        'City of Malolos': (14.8433, 120.8114),
      };
      for (final feature in features) {
        final area = BookingServiceArea.fromJson({
          ...testAreaJson,
          'geometry': feature['geometry'],
        });
        final centre = centres[feature['properties']['shapeName']]!;
        expect(area.contains(centre.$1, centre.$2), true);
        for (final polygon in area.rings) {
          for (final ring in polygon) {
            for (final p in ring) {
              expect(area.contains(p[1], p[0]), true);
            }
          }
        }
      }
    },
  );

  test(
    'search filters outside coordinates despite misleading municipal labels; selection rechecks',
    () async {
      var inside = true;
      final api = BookingLocationService(
        serviceArea: testServiceArea,
        apiKey: 'test',
        client: MockClient((r) async {
          if (r.url.path.contains('autocomplete')) {
            expect(r.url.queryParameters['strictbounds'], 'true');
            expect(r.url.queryParameters['location'], isNotNull);
            return reply({
              'status': 'OK',
              'predictions': [
                {'place_id': 'inside', 'description': 'Inside'},
                {'place_id': 'outside', 'description': 'Bustos, Philippines'},
              ],
            });
          }
          return reply({
            'status': 'OK',
            'result': place(
              r.url.queryParameters['place_id'] == 'inside' && inside
                  ? 14.95
                  : 14.6,
              120.92,
            ),
          });
        }),
      );
      final suggestions = await api.search('Bustos');
      expect(suggestions.map((s) => s.placeId), ['inside']);
      inside = false;
      await expectLater(
        api.select(suggestions.single),
        throwsA(isA<OutsideBookingServiceArea>()),
      );
    },
  );

  test(
    'GPS outside fails before geocoding; inside preserves exact coordinates',
    () async {
      var calls = 0;
      var noAddress = false;
      final api = BookingLocationService(
        serviceArea: testServiceArea,
        apiKey: 'test',
        client: MockClient((r) async {
          calls++;
          return reply(
            noAddress
                ? {'status': 'ZERO_RESULTS', 'results': []}
                : {
                    'status': 'OK',
                    'results': [place(14.96, 120.93)],
                  },
          );
        }),
      );
      await expectLater(
        api.currentLocation(14.6, 120.92),
        throwsA(isA<OutsideBookingServiceArea>()),
      );
      expect(calls, 0);
      final selected = await api.currentLocation(14.95, 120.92);
      expect(selected.latitude, 14.95);
      expect(selected.longitude, 120.92);
      noAddress = true;
      await expectLater(
        api.currentLocation(14.95, 120.92),
        throwsA(isA<BookingLocationException>()),
      );
    },
  );

  testWidgets(
    'map confirmation follows tap/drag containment and reverse-geocode success; stale response cannot win',
    (tester) async {
      final previous = GoogleMapsFlutterPlatform.instance;
      GoogleMapsFlutterPlatform.instance = _Maps();
      addTearDown(() => GoogleMapsFlutterPlatform.instance = previous);
      Completer<http.Response>? pending;
      var fail = false;
      var calls = 0;
      final api = BookingLocationService(
        serviceArea: testServiceArea,
        apiKey: 'test',
        client: MockClient((r) async {
          calls++;
          if (pending != null) return pending.future;
          return reply(
            fail
                ? {'status': 'ZERO_RESULTS', 'results': []}
                : {
                    'status': 'OK',
                    'results': [place(14.96, 120.93)],
                  },
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: BookingLocationMapPicker(service: api)),
      );
      GoogleMap map() => tester.widget<GoogleMap>(find.byType(GoogleMap));
      FilledButton confirm() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm Location'),
      );
      expect(confirm().onPressed, isNull);
      map().onTap!(const LatLng(14.95, 120.92));
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNotNull);
      final marker = map().markers.single;
      marker.onDragStart!(marker.position);
      await tester.pump();
      expect(confirm().onPressed, isNull);
      marker.onDragEnd!(const LatLng(14.6, 120.92));
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNull);
      expect(find.textContaining('Outside service area'), findsOneWidget);
      expect(calls, 1);
      pending = Completer<http.Response>();
      map().onTap!(const LatLng(14.95, 120.92));
      await tester.pump();
      map().onTap!(const LatLng(14.6, 120.92));
      pending.complete(
        reply({
          'status': 'OK',
          'results': [place(14.95, 120.92)],
        }),
      );
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNull);
      expect(map().markers.single.position, const LatLng(14.6, 120.92));
      pending = null;
      fail = true;
      map().onTap!(const LatLng(14.95, 120.92));
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNull);
      expect(find.textContaining('Could not verify'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
