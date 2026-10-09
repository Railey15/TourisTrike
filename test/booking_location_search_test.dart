import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:touristrike/core/places/booking_location_service.dart';
import 'package:touristrike/widgets/booking_location_picker.dart';
import 'fixtures/booking_service_area_fixture.dart';

Map<String, dynamic> place({
  String code = 'PH',
  String country = 'Philippines',
  String address = 'Bustos Municipal Hall, Bulacan',
  bool withCountry = true,
}) => {
  'formatted_address': address,
  'geometry': {
    'location': {'lat': 14.9539783, 'lng': 120.9185984},
  },
  'address_components': [
    if (withCountry)
      {
        'types': ['country'],
        'short_name': code,
        'long_name': country,
      },
    {
      'types': ['administrative_area_level_1'],
      'long_name': 'Central Luzon',
    },
    {
      'types': ['administrative_area_level_2'],
      'long_name': 'Bulacan',
    },
    {
      'types': ['locality'],
      'long_name': 'Bustos',
    },
  ],
};

http.Response response(Object body) => http.Response(jsonEncode(body), 200);
Map<String, dynamic> newPlace([Map<String, dynamic>? legacy]) {
  final source = legacy ?? place();
  final location = (source['geometry'] as Map)['location'] as Map;
  return {
    'id': 'bustos-place',
    'displayName': {'text': 'Bustos Municipal Hall'},
    'formattedAddress': source['formatted_address'],
    'location': {'latitude': location['lat'], 'longitude': location['lng']},
    'addressComponents': ((source['address_components'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (component) => {
            'types': component['types'],
            'shortText': component['short_name'],
            'longText': component['long_name'],
          },
        )
        .toList(),
  };
}

http.Response detailsResponse([Map<String, dynamic>? legacy]) =>
    response(newPlace(legacy));

http.Response autocompleteResponse(String id, String description) => response({
  'suggestions': [
    {
      'placePrediction': {
        'placeId': id,
        'text': {'text': description},
      },
    },
  ],
});

bool isDetailsRequest(http.Request request) =>
    request.method == 'GET' && request.url.host == 'places.googleapis.com';

const suggestion = BookingPlaceSuggestion(
  placeId: 'bustos-place',
  description: 'Bustos Municipal Hall',
);
BookingLocationService service(
  Future<http.Response> Function(http.Request) handler,
) => BookingLocationService(
  serviceArea: testServiceArea,
  apiKey: 'test-key',
  client: MockClient(handler),
);

void main() {
  test(
    'PH details pass without Philippines in text and preserve structured data',
    () async {
      final api = service((request) async {
        expect(request.url.path, '/v1/places/bustos-place');
        expect(
          request.headers['x-goog-fieldmask'],
          contains('addressComponents'),
        );
        return detailsResponse();
      });
      final result = await api.select(suggestion);
      expect(result.countryCode, 'PH');
      expect(result.country, 'Philippines');
      expect(result.placeId, suggestion.placeId);
      expect(result.latitude, 14.9539783);
      expect(result.longitude, 120.9185984);
      expect(result.province, 'Bulacan');
      expect(result.locality, 'Bustos');
    },
  );

  test(
    'explicit foreign country overrides misleading Philippines address text',
    () async {
      final api = service(
        (_) async => detailsResponse(
          place(code: 'US', country: 'United States', address: 'Philippines'),
        ),
      );
      await expectLater(
        api.select(suggestion),
        throwsA(
          isA<BookingLocationException>().having(
            (e) => e.message,
            'message',
            contains('within the Philippines'),
          ),
        ),
      );
    },
  );

  test(
    'missing details country resolves coordinates before validating',
    () async {
      final calls = <String>[];
      final api = service((r) async {
        calls.add(r.url.path);
        if (isDetailsRequest(r)) {
          return detailsResponse(place(withCountry: false));
        }
        expect(r.url.queryParameters['latlng'], '14.9539783,120.9185984');
        return response({
          'status': 'OK',
          'results': [place()],
        });
      });
      final result = await api.select(suggestion);
      expect(calls.length, 2);
      expect(result.isPhilippines, isTrue);
      expect(result.placeId, suggestion.placeId);
    },
  );

  test(
    'reverse country name works without short country code or place ID',
    () async {
      final api = service(
        (_) async => response({
          'status': 'OK',
          'results': [place(code: '')],
        }),
      );
      final result = await api.currentLocation(14.95, 120.91);
      expect(result.latitude, 14.95);
      expect(result.longitude, 120.91);
      expect(result.placeId, isNull);
      expect(result.countryCode, 'PH');
    },
  );

  test(
    'formatted address is only fallback after successful reverse geocoding',
    () async {
      final api = service(
        (_) async => response({
          'status': 'OK',
          'results': [
            place(withCountry: false, address: 'Bustos, Bulacan, Philippines'),
          ],
        }),
      );
      expect((await api.currentLocation(14.95, 120.91)).isPhilippines, isTrue);
    },
  );

  test(
    'reverse geocoding denial is a service error, never a country error',
    () async {
      final api = service(
        (_) async => response({
          'status': 'REQUEST_DENIED',
          'error_message': 'You must enable Billing',
        }),
      );
      await expectLater(
        api.currentLocation(14.95, 120.91),
        throwsA(
          isA<BookingLocationException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('rejected the configured API key'),
              isNot(contains('within the Philippines')),
            ),
          ),
        ),
      );
    },
  );

  test(
    'unverifiable or invalid coordinates do not become selections',
    () async {
      var calls = 0;
      final api = service((_) async {
        calls++;
        return response({'status': 'ZERO_RESULTS', 'results': []});
      });
      await expectLater(
        api.currentLocation(double.nan, 120),
        throwsA(isA<BookingLocationException>()),
      );
      expect(calls, 0);
      await expectLater(
        api.currentLocation(14.95, 120.91),
        throwsA(isA<BookingLocationException>()),
      );
    },
  );

  test(
    'autocomplete retains PH filter and uses user query without municipality suffix',
    () async {
      final api = service((r) async {
        if (isDetailsRequest(r)) {
          return detailsResponse();
        }
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        expect(body['includedRegionCodes'], ['ph']);
        expect(body['locationRestriction'], isNotNull);
        expect(body['input'], 'SM City Baliwag');
        return autocompleteResponse('sm', 'SM City Baliwag');
      });
      expect((await api.search('SM City Baliwag')).single.placeId, 'sm');
    },
  );

  testWidgets(
    'Pickup and Drop-off select independently; free text clears only edited field',
    (tester) async {
      BookingLocation? pickup, dropoff;
      final api = service(
        (r) async => r.url.path.contains('autocomplete')
            ? autocompleteResponse('bustos', 'Bustos Hall')
            : detailsResponse(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  BookingLocationPicker(
                    serviceArea: testServiceArea,
                    label: 'Pickup',
                    service: api,
                    onLocationSelected: (p) => pickup = p,
                  ),
                  BookingLocationPicker(
                    serviceArea: testServiceArea,
                    label: 'Drop-off',
                    service: api,
                    onLocationSelected: (p) => dropoff = p,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('valid location within'), findsNothing);
      for (final i in [0, 1]) {
        await tester.enterText(find.byType(TextField).at(i), 'Bustos');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        await tester.tap(find.text('Bustos Hall'));
        await tester.pumpAndSettle();
      }
      expect(pickup?.isPhilippines, isTrue);
      expect(dropoff?.isPhilippines, isTrue);
      await tester.enterText(
        find.byType(TextField).first,
        'arbitrary free text',
      );
      expect(pickup, isNull);
      expect(dropoff?.isPhilippines, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late autocomplete response cannot replace newer query results', (
    tester,
  ) async {
    final old = Completer<http.Response>();
    final api = service((r) async {
      if (isDetailsRequest(r)) {
        return detailsResponse();
      }
      if ((jsonDecode(r.body) as Map)['input'] == 'old') return old.future;
      return autocompleteResponse('new', 'New result');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingLocationPicker(
            serviceArea: testServiceArea,
            label: 'Pickup',
            service: api,
            onLocationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    old.complete(autocompleteResponse('old', 'Old result'));
    await tester.pumpAndSettle();
    expect(find.text('New result'), findsOneWidget);
    expect(find.text('Old result'), findsNothing);
  });

  testWidgets(
    'editing during details invalidates late selection without country errors',
    (tester) async {
      final details = Completer<http.Response>();
      BookingLocation? selected;
      String? validation;
      var detailsCalls = 0;
      final api = service(
        (r) async => isDetailsRequest(r)
            ? (++detailsCalls == 1 ? detailsResponse() : details.future)
            : autocompleteResponse('bustos', 'Bustos Hall'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookingLocationPicker(
              serviceArea: testServiceArea,
              label: 'Pickup',
              service: api,
              onLocationSelected: (p) => selected = p,
              onValidationMessageChanged: (e) => validation = e,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Bustos');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.tap(find.text('Bustos Hall'));
      await tester.pump();
      expect(selected, isNull);
      expect(validation, isNull);
      await tester.enterText(find.byType(TextField), 'Changed');
      details.complete(detailsResponse());
      await tester.pump();
      expect(selected, isNull);
      expect(validation, isNull);
      expect(find.text('Changed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'service failure is visible with retry instead of silent missing suggestions',
    (tester) async {
      var denied = true;
      final api = service((r) async {
        return denied
            ? http.Response(
                jsonEncode({
                  'error': {
                    'status': 'PERMISSION_DENIED',
                    'message': 'Permission denied',
                  },
                }),
                403,
              )
            : isDetailsRequest(r)
            ? detailsResponse()
            : autocompleteResponse('bustos', 'Bustos Hall');
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookingLocationPicker(
              serviceArea: testServiceArea,
              label: 'Pickup',
              service: api,
              onLocationSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Bustos');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      expect(
        find.textContaining('rejected the configured API key'),
        findsOneWidget,
      );
      expect(find.textContaining('within the Philippines'), findsNothing);
      denied = false;
      await tester.tap(find.text('Retry search'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      expect(find.text('Bustos Hall'), findsOneWidget);
    },
  );

  testWidgets('current location uses reverse country and needs no Places ID', (
    tester,
  ) async {
    BookingLocation? selected;
    final api = service(
      (_) async => response({
        'status': 'OK',
        'results': [place()],
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingLocationPicker(
            serviceArea: testServiceArea,
            label: 'Pickup',
            service: api,
            onLocationSelected: (p) => selected = p,
            positionLoader: () async => Position(
              latitude: 14.95,
              longitude: 120.91,
              timestamp: DateTime.now(),
              accuracy: 5,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Use Current Location'));
    await tester.pumpAndSettle();
    expect(selected?.latitude, 14.95);
    expect(selected?.placeId, isNull);
    expect(selected?.countryCode, 'PH');
  });
}
