import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/places/booking_location_service.dart';
import 'package:touristrike/screens/tourist/package_booking_screen.dart';
import 'package:touristrike/widgets/booking_location_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Future<http.Response> Function(http.Request) handle;
  var requests = 0;
  http.Response spots(http.Request request) => http.Response(
    jsonEncode([
      for (var i = 0; i < 4; i++)
        {
          'sort_order': i,
          'estimated_duration_minutes': 30,
          'tourist_spots': {
            'id': 'spot-$i',
            'name': 'Stop $i',
            'municipality': 'Bustos',
            'latitude': 14.95 + i / 1000,
            'longitude': 120.91,
          },
        },
    ]),
    200,
    request: request,
    headers: {'content-type': 'application/json'},
  );

  Widget screen(String id) => MaterialApp(
    home: PackageBookingScreen(
      key: const ValueKey('booking'),
      packageId: id,
      initialPackage: TourPackage({
        'id': id,
        'title': 'Package $id',
        'city': 'Bustos',
        'price': 1000,
      }),
    ),
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test',
      httpClient: MockClient((request) {
        requests++;
        return handle(request);
      }),
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() {
    dotenv.testLoad(fileInput: '');
    requests = 0;
    handle = (r) async => spots(r);
  });

  testWidgets(
    'real screen recalculates after time, stay, order, spots and fresh travel changes',
    (tester) async {
      dotenv.testLoad(fileInput: 'GOOGLE_MAPS_API_KEY=test-key');
      var travelMinutes = 10;
      var directionsCalls = 0;
      final maps = MockClient((r) async {
        if (!r.url.path.contains('directions')) {
          return http.Response('{"status":"ZERO_RESULTS","results":[]}', 200);
        }
        directionsCalls++;
        final waypoints = r.url.queryParameters['waypoints'];
        final count = waypoints == null ? 1 : waypoints.split('|').length + 1;
        return http.Response(
          jsonEncode({
            'status': 'OK',
            'routes': [
              {
                'legs': List.generate(
                  count,
                  (_) => {
                    'duration': {'value': travelMinutes * 60},
                    'distance': {'value': 1000},
                  },
                ),
              },
            ],
          }),
          200,
        );
      });
      Finder type(String name) =>
          find.byWidgetPredicate((w) => w.runtimeType.toString() == name);
      dynamic card() => tester.widget(type('_EditableItineraryCard'));
      Future<void> page(int index) async {
        tester
            .widget<PageView>(find.byType(PageView))
            .controller!
            .jumpToPage(index);
        await tester.pumpAndSettle();
      }

      Future<void> chooseTime(int hour) async {
        (tester.widget(type('_PickupTimeSelectionCard')) as dynamic).onTap();
        await tester.pumpAndSettle();
        Navigator.of(
          tester.element(find.byType(TimePickerDialog)),
        ).pop(TimeOfDay(hour: hour, minute: 0));
        await tester.pumpAndSettle();
      }

      await http.runWithClient(() async {
        await tester.pumpWidget(screen('a'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        (tester.widget(type('_DateSelectionCard')) as dynamic).onTap();
        await tester.pumpAndSettle();
        Navigator.of(
          tester.element(find.byType(DatePickerDialog)),
        ).pop(DateTime.now());
        await tester.pumpAndSettle();
        await chooseTime(8);
        await page(1);
        final pickers = tester
            .widgetList<BookingLocationPicker>(
              find.byType(BookingLocationPicker),
            )
            .toList();
        pickers[0].onLocationSelected(
          const BookingLocation(
            address: 'Pickup',
            latitude: 14.94,
            longitude: 120.91,
            countryCode: 'PH',
          ),
        );
        pickers[1].onLocationSelected(
          const BookingLocation(
            address: 'Drop-off',
            latitude: 14.96,
            longitude: 120.91,
            countryCode: 'PH',
          ),
        );
        await tester.pumpAndSettle();
        await page(3);
        await tester.ensureVisible(find.text('Customize Schedule'));
        await tester.tap(find.text('Customize Schedule'));
        await tester.pumpAndSettle();
        expect(card().items[0].arrivalTime, '08:10:00');
        expect(card().items[1].arrivalTime, '08:50:00');
        final callsBeforeStay = directionsCalls;
        card().onStayChanged(card().items[0], 60);
        await tester.pumpAndSettle();
        expect(card().items[1].arrivalTime, '09:20:00');
        expect(directionsCalls, callsBeforeStay);
        final previousSecond = card().items[1].localKey;
        card().onMoveDown(0);
        await tester.pumpAndSettle();
        expect(card().items[0].localKey, previousSecond);
        expect(card().items[0].arrivalTime, '08:10:00');
        expect(directionsCalls, greaterThan(callsBeforeStay));
        await page(0);
        await chooseTime(9);
        await page(3);
        expect(card().items[0].arrivalTime, '09:10:00');
        // Rebuild for the same package must retain custom order and stay edits.
        await tester.pumpWidget(screen('a'));
        await tester.pumpAndSettle();
        expect(card().items[0].localKey, previousSecond);
        expect(card().items[1].stayMinutes, 60);
        travelMinutes = 20;
        await page(1);
        tester
            .widgetList<BookingLocationPicker>(
              find.byType(BookingLocationPicker),
            )
            .first
            .onLocationSelected(
              const BookingLocation(
                address: 'New pickup',
                latitude: 14.93,
                longitude: 120.91,
                countryCode: 'PH',
              ),
            );
        await tester.pumpAndSettle();
        await page(3);
        expect(card().items[0].arrivalTime, '09:20:00');
        final beforeRemoval = directionsCalls;
        await page(2);
        (tester.widgetList(type('_SelectedBookingSpotCard')).last as dynamic)
            .onRemove();
        await tester.pumpAndSettle();
        await page(3);
        expect(card().items.length, 3);
        expect(card().items[0].arrivalTime, '09:20:00');
        expect(directionsCalls, greaterThan(beforeRemoval));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }, () => maps);
    },
  );

  testWidgets(
    'actual FutureBuilder initializes without setState during build; rebuild preserves Route controllers',
    (tester) async {
      await tester.pumpWidget(screen('a'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Package a'), findsOneWidget);
      expect(requests, 1);

      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
      await tester.pumpAndSettle();
      final pickers = find.byType(BookingLocationPicker);
      expect(pickers, findsNWidgets(2));
      final originalState = tester.state(pickers.first);
      final field = find.descendant(
        of: pickers.first,
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'Bustos');
      final originalController = tester.widget<TextField>(field).controller;

      // Rebuild while the debounce is pending, as a parent/keyboard update does.
      await tester.pumpWidget(screen('a'));
      await tester.pump();
      expect(tester.state(pickers.first), same(originalState));
      expect(
        tester.widget<TextField>(field).controller,
        same(originalController),
      );
      expect(originalController!.text, 'Bustos');
      expect(requests, 1);
      expect(tester.takeException(), isNull);
      tester
          .widgetList<BookingLocationPicker>(pickers)
          .first
          .onLocationSelected(
            const BookingLocation(
              address: 'Pickup',
              latitude: 14.94,
              longitude: 120.91,
              countryCode: 'PH',
            ),
          );
      tester
          .widgetList<BookingLocationPicker>(pickers)
          .last
          .onLocationSelected(
            const BookingLocation(
              address: 'Drop-off',
              latitude: 14.96,
              longitude: 120.91,
              countryCode: 'PH',
            ),
          );
      await tester.pumpAndSettle();
      await tester.pumpWidget(screen('a'));
      await tester.pumpAndSettle();
      final dynamic preview = tester.widget(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_SharedRouteMapPreview',
        ),
      );
      expect(preview.pickupLat, 14.94);
      expect(preview.dropoffLat, 14.96);
      expect(tester.state(pickers.first), same(originalState));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'changing package discards a late old load and initializes new package once',
    (tester) async {
      final old = Completer<http.Response>();
      late http.Request oldRequest;
      handle = (r) async {
        if (r.url.queryParameters['package_id'] == 'eq.a') {
          oldRequest = r;
          return old.future;
        }
        return spots(r);
      };
      await tester.pumpWidget(screen('a'));
      await tester.pump();
      await tester.pumpWidget(screen('b'));
      await tester.pumpAndSettle();
      expect(find.text('Package b'), findsOneWidget);
      old.complete(spots(oldRequest));
      await tester.pumpAndSettle();
      expect(find.text('Package b'), findsOneWidget);
      expect(find.text('Package a'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(requests, 2);
      await tester.pumpWidget(screen('b'));
      await tester.pumpAndSettle();
      expect(requests, 2);
    },
  );

  testWidgets('disposing before load completion never updates disposed State', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    late http.Request request;
    handle = (r) {
      request = r;
      return pending.future;
    };
    await tester.pumpWidget(screen('a'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(spots(request));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed load retry initializes through completion, not builder', (
    tester,
  ) async {
    handle = (r) async => http.Response(
      '{"message":"temporary error"}',
      500,
      request: r,
      headers: {'content-type': 'application/json'},
    );
    await tester.pumpWidget(screen('a'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    handle = (r) async => spots(r);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Package a'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
