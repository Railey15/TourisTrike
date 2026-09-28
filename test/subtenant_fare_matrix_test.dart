import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/subtenant/subtenant_city_profile_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

const _actor = '10000000-0000-4000-8000-000000000001';
const _hourly = 'Waiting Fee (PHP / hour)';
const _tour = 'Tour Additional Waiting Fee (PHP / 15 min)';
const _helper =
    'Charged per started 15 minutes after the tourist exceeds the included Time of Stay.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic>? fareRow;
  late String assignedCity;
  late String assignedProvince;
  late String actualRole;
  late bool active;
  final requests = <http.Request>[];
  final saved = <Map<String, dynamic>>[];
  late SubTenantService service;

  SubTenantProfile profile({
    String city = 'Bustos',
    String province = 'Bulacan',
    String id = _actor,
  }) => SubTenantProfile(
    id: id,
    role: 'subtenant',
    fullName: 'Tourism Officer',
    firstName: '',
    lastName: '',
    email: 'fixture@example.test',
    mobile: '',
    address: '',
    city: city,
    province: province,
    profileImageUrl: '',
    raw: const {},
  );
  SubTenantFareSettings settings({
    String city = 'Bustos',
    String owner = _actor,
    double? tour = 25,
  }) => SubTenantFareSettings(
    subtenantId: owner,
    city: city,
    baseFare: 50,
    farePerKm: 10,
    minimumFare: 100,
    waitingFee: 200,
    tourWaitingFeePer15Minutes: tour,
  );

  http.Response response(
    http.Request request,
    Object? body, {
    int status = 200,
  }) => http.Response(
    body == null ? '' : jsonEncode(body),
    status,
    request: request,
    headers: {'content-type': 'application/json'},
  );

  setUpAll(() async {
    // Use the SDK's actual Material font, not the wide Ahem test font, so the
    // existing navigation shell has the same text metrics as the application.
    final fonts = File(Platform.resolvedExecutable).parent.parent.parent;
    final loader = FontLoader('Roboto')
      ..addFont(
        File(
          '${fonts.path}/material_fonts/roboto-regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await loader.load();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        final table = request.url.path.split('/').last;
        if (request.method == 'GET') {
          final row = switch (table) {
            'profiles' => <String, dynamic>{
              'id': _actor,
              'role': actualRole,
              'full_name': 'Tourism Officer',
              'city': assignedCity,
              'province': assignedProvince,
            },
            'subtenant_details' => <String, dynamic>{
              'id': _actor,
              'city': assignedCity,
              'province': assignedProvince,
              'is_active': active,
              'contact_person': 'Tourism Officer',
            },
            'subtenant_fare_settings' => fareRow,
            _ => null,
          };
          return response(request, row == null ? <Object>[] : [row]);
        }
        if (table == 'subtenant_fare_settings' && request.method == 'POST') {
          final body = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          saved.add(body);
          fareRow = {...body, 'id': 'fare-row'};
          return response(request, {'id': 'fare-row'});
        }
        if (table == 'audit_logs' && request.method == 'POST') {
          return response(request, null, status: 201);
        }
        throw StateError(
          'Unexpected configuration request ${request.method} ${request.url}',
        );
      }),
    );
    final expiry =
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
        1000;
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${encode({'alg': 'HS256'})}.${encode({'sub': _actor, 'exp': expiry})}.fixture';
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'local-test-only',
        'token_type': 'bearer',
        'expires_in': 7200,
        'expires_at': expiry,
        'user': {
          'id': _actor,
          'aud': 'authenticated',
          'role': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
          'email': 'fixture@example.test',
        },
      }),
    );
    service = SubTenantService(client: Supabase.instance.client);
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    requests.clear();
    saved.clear();
    assignedCity = 'Bustos';
    assignedProvince = 'Bulacan';
    actualRole = 'subtenant';
    active = true;
    fareRow = {
      'id': 'fare-row',
      'subtenant_id': _actor,
      'city': 'Bustos',
      'base_fare': 50,
      'fare_per_km': 10,
      'minimum_fare': 100,
      'waiting_fee': 200,
      'tour_waiting_fee_per_15_minutes': 25,
      'is_active': true,
    };
  });

  test(
    'loads own authoritative row with separate hourly and tour rates',
    () async {
      final loaded = await service.loadFareSettings(profile());
      expect(loaded.waitingFee, 200);
      expect(loaded.tourWaitingFeePer15Minutes, 25);
      final query = requests
          .singleWhere((r) => r.url.path.endsWith('/subtenant_fare_settings'))
          .url
          .queryParameters;
      expect(query['subtenant_id'], 'eq.$_actor');
      expect(query['city'], 'eq.Bustos');
      expect(query['is_active'], 'eq.true');
    },
  );
  test(
    'saves explicit tour amount through the existing scoped upsert',
    () async {
      await service.saveFareSettings(profile(), settings(tour: 35.5));
      expect(saved.single['tour_waiting_fee_per_15_minutes'], 35.5);
      expect(saved.single['waiting_fee'], 200);
      final post = requests.singleWhere(
        (r) => r.url.path.endsWith('/subtenant_fare_settings'),
      );
      expect(post.url.queryParameters['on_conflict'], 'subtenant_id,city');
      expect(saved.single['subtenant_id'], _actor);
      expect(saved.single['city'], 'Bustos');
    },
  );
  test(
    'uses the authoritative city name for reads and unique-key upserts',
    () async {
      final actor = profile(city: ' bustos ');
      await service.loadFareSettings(actor);
      final query = requests
          .singleWhere((r) => r.url.path.endsWith('/subtenant_fare_settings'))
          .url
          .queryParameters;
      expect(query['city'], 'eq.Bustos');
      await service.saveFareSettings(actor, settings(city: 'BUSTOS'));
      expect(saved.single['city'], 'Bustos');
    },
  );
  test(
    'missing tour rate remains unset and never uses hourly waiting_fee',
    () async {
      fareRow!['tour_waiting_fee_per_15_minutes'] = null;
      final loaded = await service.loadFareSettings(profile());
      expect(loaded.tourWaitingFeePer15Minutes, isNull);
      await service.saveFareSettings(profile(), settings(tour: null));
      expect(saved.single['tour_waiting_fee_per_15_minutes'], isNull);
      expect(saved.single['waiting_fee'], 200);
    },
  );
  test(
    'Malolos missing row loads without writing; explicit values can create it',
    () async {
      assignedCity = 'Malolos';
      fareRow = null;
      final loaded = await service.loadFareSettings(profile(city: 'Malolos'));
      expect(loaded.id, isNull);
      expect(loaded.tourWaitingFeePer15Minutes, isNull);
      expect(saved, isEmpty);
      await service.saveFareSettings(
        profile(city: 'Malolos'),
        settings(city: 'Malolos', tour: 30),
      );
      expect(saved.single['city'], 'Malolos');
      expect(saved.single['tour_waiting_fee_per_15_minutes'], 30);
    },
  );
  test(
    'rejects different municipality and different owner before any write',
    () async {
      for (final input in [
        settings(city: 'Baliwag'),
        settings(owner: 'another-subtenant'),
      ]) {
        await expectLater(
          service.saveFareSettings(profile(), input),
          throwsStateError,
        );
      }
      expect(saved, isEmpty);
    },
  );
  test(
    'rejects different province, inactive office and changed Main Tenant role',
    () async {
      assignedProvince = 'Another Province';
      await expectLater(
        service.saveFareSettings(profile(), settings()),
        throwsStateError,
      );
      assignedProvince = 'Bulacan';
      active = false;
      await expectLater(
        service.saveFareSettings(profile(), settings()),
        throwsStateError,
      );
      active = true;
      actualRole = 'main_tenant';
      await expectLater(
        service.saveFareSettings(profile(), settings()),
        throwsStateError,
      );
      expect(saved, isEmpty);
    },
  );
  test(
    'rejects a foreign authenticated identity for loading and saving',
    () async {
      await expectLater(
        service.loadFareSettings(profile(id: 'other-account')),
        throwsStateError,
      );
      await expectLater(
        service.saveFareSettings(
          profile(id: 'other-account'),
          settings(owner: 'other-account'),
        ),
        throwsStateError,
      );
      expect(saved, isEmpty);
    },
  );
  test(
    'rejects nonfinite, negative and fractional-cent rates before persistence',
    () async {
      for (final amount in [double.nan, double.infinity, -1.0, 1.234]) {
        await expectLater(
          service.saveFareSettings(profile(), settings(tour: amount)),
          throwsFormatException,
        );
      }
      expect(saved, isEmpty);
    },
  );
  test(
    'validates monetary text without silently coercing invalid values to zero',
    () {
      for (final value in [
        'NaN',
        'Infinity',
        '-1',
        'abc',
        '1,2',
        '1.234',
        '1e4',
        '',
      ]) {
        expect(
          SubTenantFareSettings.parseMoneyAmount(value),
          isNull,
          reason: value,
        );
      }
      expect(SubTenantFareSettings.parseMoneyAmount('0'), 0);
      expect(SubTenantFareSettings.parseMoneyAmount('1,234.50'), 1234.5);
      expect(
        () => SubTenantFareSettings.fromMap({
          'tour_waiting_fee_per_15_minutes': 'invalid',
        }, profile()),
        throwsFormatException,
      );
    },
  );
  test('tour overtime is excluded from the ordinary hourly fare sample', () {
    expect(
      settings(tour: 5).calculate(routeDistanceKm: 8).total,
      settings(tour: 500).calculate(routeDistanceKm: 8).total,
    );
    expect(settings().calculate(routeDistanceKm: 8).waitingFee, 200);
  });

  Finder field(String label) => find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is SubTenantTextField && w.label == label,
    ),
    matching: find.byType(TextFormField),
  );
  String text(WidgetTester tester, String label) =>
      tester.widget<TextFormField>(field(label)).controller!.text;
  Future<void> openFareMatrix(
    WidgetTester tester, {
    Size size = const Size(1500, 1050),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: const SubTenantCityProfileScreen(),
      ),
    );
    await tester.pumpAndSettle();
    if (size.width < 600) {
      await tester.scrollUntilVisible(
        find.text('Fare Matrix'),
        150,
        scrollable: find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is ListView && w.scrollDirection == Axis.horizontal,
          ),
          matching: find.byType(Scrollable),
        ),
      );
    }
    await tester.tap(find.text('Fare Matrix').first);
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester, String label, String value) async {
    await tester.ensureVisible(field(label));
    await tester.enterText(field(label), value);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.text('Save Settings');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'desktop renders both exact labels and helper and loads current tour value',
    (tester) async {
      await openFareMatrix(tester);
      expect(find.text(_hourly), findsOneWidget);
      expect(find.text(_tour), findsOneWidget);
      expect(find.text(_helper), findsOneWidget);
      expect(text(tester, _tour), '25');
      expect(text(tester, _hourly), '200');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'mobile Fare Matrix displays and saves the independent tour field',
    (tester) async {
      await openFareMatrix(tester, size: const Size(430, 950));
      await edit(tester, _tour, '35.50');
      await save(tester);
      expect(saved.single['tour_waiting_fee_per_15_minutes'], 35.5);
      expect(saved.single['waiting_fee'], 200);
      expect(
        requests.where(
          (r) =>
              r.method != 'GET' &&
              (r.url.path.endsWith('/profiles') ||
                  r.url.path.endsWith('/subtenant_details')),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('NaN entry is rejected by the rendered form without saving', (
    tester,
  ) async {
    await openFareMatrix(tester);
    await edit(tester, _tour, 'NaN');
    await save(tester);
    expect(saved, isEmpty);
    expect(
      find.text('Enter a valid non-negative amount (up to 2 decimals)'),
      findsOneWidget,
    );
  });
  testWidgets(
    'Malolos first-time form starts blank and requires entered ride fares',
    (tester) async {
      assignedCity = 'Malolos';
      fareRow = null;
      await openFareMatrix(tester);
      for (final label in [
        'Base Fare (PHP)',
        'Fare per Kilometer',
        'Minimum Fare',
        _hourly,
        _tour,
      ]) {
        expect(text(tester, label), isEmpty);
      }
      await edit(tester, _tour, '30');
      await save(tester);
      expect(saved, isEmpty);
      for (final entry in {
        'Base Fare (PHP)': '50',
        'Fare per Kilometer': '10',
        'Minimum Fare': '100',
        _hourly: '200',
      }.entries) {
        await edit(tester, entry.key, entry.value);
      }
      await save(tester);
      expect(saved.single['city'], 'Malolos');
      expect(saved.single['tour_waiting_fee_per_15_minutes'], 30);
      expect(tester.takeException(), isNull);
    },
  );
}
