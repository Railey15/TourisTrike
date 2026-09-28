import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/models/driver_tour_action.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/widgets/driver_tour_payment_required_card.dart';
import 'package:touristrike/widgets/driver_tour_slide_action.dart';

void main() {
  Map<String, dynamic> payload({
    double package = 750,
    double waiting = 40,
    double total = 790,
    bool satisfied = false,
  }) => {
    'package_remaining': package,
    'finalized_waiting': waiting,
    'total_remaining': total,
    'payment_satisfied': satisfied,
  };

  for (final (name, data) in [
    ('package debt', payload(package: 750, waiting: 0, total: 750)),
    ('waiting debt', payload(package: 0, waiting: 40, total: 40)),
    ('combined debt', payload()),
    ('pending settlement', payload(total: 0)),
    ('historical confirmed receipt with new debt', payload(satisfied: true)),
  ]) {
    test('$name cannot unlock drop-off', () {
      expect(DriverTourPaymentGate.fromMap(data).canDropOff, isFalse);
    });
  }
  test('only zero outstanding and authoritative settlement unlock', () {
    final paid = DriverTourPaymentGate.fromMap(
      payload(package: 0, waiting: 40, total: 0, satisfied: true),
    );
    expect(paid.canDropOff, isTrue);
    expect(
      paid.finalizedWaiting,
      40,
      reason: 'Historical waiting remains visible after payment',
    );
  });
  test('missing or malformed server amounts fail closed', () {
    for (final value in [null, 'NaN', -1, 'unknown']) {
      expect(
        () => DriverTourPaymentGate.fromMap({
          ...payload(),
          'total_remaining': value,
        }),
        throwsFormatException,
      );
    }
  });
  testWidgets(
    'authoritative refetch replaces payment card with drop-off slide',
    (tester) async {
      var response = payload(package: 1350, waiting: 40, total: 1390);
      final client = (await tester.runAsync(
        () async => SupabaseClient(
          'https://example.test',
          'fixture',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            expect(
              request.url.path,
              '/rest/v1/rpc/get_driver_tour_payment_gate',
            );
            expect(jsonDecode(request.body), {'p_booking_id': 'booking'});
            return http.Response(
              jsonEncode(response),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      ))!;
      addTearDown(() => tester.runAsync(client.dispose));
      final repo = TourisTrikeRepository(client: client);
      Future<void> render() async {
        final gate = DriverTourPaymentGate.fromMap(
          (await tester.runAsync(
            () => repo.fetchDriverTourPaymentGate('booking'),
          ))!,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: gate.canDropOff
                  ? DriverTourSlideAction(
                      actionId: 'stop_done:1',
                      label: DriverTourSlideStage.dropOff.label,
                      onConfirmed: () async {},
                    )
                  : DriverTourPaymentRequiredCard(gate: gate),
            ),
          ),
        );
      }

      await render();
      expect(find.text('PAYMENT REQUIRED'), findsOneWidget);
      expect(find.text('₱1,350.00'), findsOneWidget);
      expect(find.text('₱40.00'), findsOneWidget);
      expect(find.text('₱1,390.00'), findsOneWidget);
      expect(find.byType(DriverTourSlideAction), findsNothing);
      response = payload(package: 0, waiting: 40, total: 0, satisfied: true);
      await render();
      expect(find.text('PAYMENT REQUIRED'), findsNothing);
      expect(find.text('SLIDE TO DROP OFF'), findsOneWidget);
    },
  );
  testWidgets('unknown payment state stays locked on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DriverTourPaymentRequiredCard(gate: null)),
      ),
    );
    expect(find.text('CHECKING PAYMENT'), findsOneWidget);
    expect(find.byType(DriverTourSlideAction), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test(
    'existing realtime and reconnect callbacks refetch authoritative gate',
    () {
      final source = File(
        'lib/screens/driver/driver_package_tracking_screen.dart',
      ).readAsStringSync();
      for (final table in [
        'payment_records',
        'payment_allocations',
        'booking_payment_requirements',
      ]) {
        expect(source, contains("table: '$table'"));
      }
      expect(source, contains('fetchDriverTourPaymentGate(bookingId)'));
      expect(source, contains("logTag: 'tracking-resumed'"));
      expect(source, contains('generation != _trackingRefreshGeneration'));
      expect(
        source,
        isNot(contains("_hasConfirmedPayment('remaining_balance'")),
      );
    },
  );
}
