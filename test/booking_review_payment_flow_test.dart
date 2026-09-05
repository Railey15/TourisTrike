import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:touristrike/core/models/booking_payment_prompt.dart';
import 'package:touristrike/core/services/itinerary_schedule_service.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/widgets/booking_payment_sheet.dart';
import 'package:touristrike/widgets/booking_review_sheet.dart';

PackageBooking booking({
  int required = 2,
  int accepted = 2,
  String type = 'same_day',
  String? status,
}) => PackageBooking({
  'id': 'booking-1',
  'tourist_id': 'tourist-1',
  'required_drivers': required,
  'accepted_drivers_count': accepted,
  'booking_type': type,
  'booking_status':
      status ?? (accepted >= required ? 'accepted' : 'waiting_for_drivers'),
  'status': status ?? (accepted >= required ? 'confirmed' : 'pending'),
  'total_amount': 7200,
  'downpayment_amount': 3600,
  'remaining_balance': 3600,
  'tour_packages': {'title': 'Baliwag & Pulilan Tour'},
});

BookingPaymentPrompt prompt({
  int required = 2,
  int accepted = 2,
  String type = 'same_day',
  String? status,
  List<PaymentRecord> payments = const [],
}) => BookingPaymentPrompt.fromRecords(
  booking(required: required, accepted: accepted, type: type, status: status),
  payments,
);

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/booking_flow_qa');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Use the SDK's fonts for readable local layout captures when available.
    final fonts =
        '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts';
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final file = File('$fonts/${entry.value}');
      if (file.existsSync()) {
        final loader = FontLoader(entry.key)
          ..addFont(file.readAsBytes().then((b) => ByteData.sublistView(b)));
        await loader.load();
      }
    }
  });
  for (final type in ['same_day', 'advanced']) {
    for (final count in [1, 2, 3]) {
      test('$type: payment opens once only at $count/$count drivers', () {
        final gate = BookingPaymentPromptGate();
        for (var accepted = 0; accepted < count; accepted++) {
          expect(
            gate.shouldPresent(
              prompt(required: count, accepted: accepted, type: type),
            ),
            isFalse,
          );
        }
        final ready = prompt(required: count, accepted: count, type: type);
        expect(ready.paymentRequired, isTrue);
        expect(gate.shouldPresent(ready), isTrue);
        for (var refresh = 0; refresh < 5; refresh++) {
          expect(gate.shouldPresent(ready), isFalse);
        }
        expect(
          gate.shouldPresent(
            prompt(required: count, accepted: count - 1, type: type),
          ),
          isFalse,
        );
        expect(gate.shouldPresent(ready), isTrue);
      });
    }
  }

  test(
    'confirmed downpayment/full payment suppresses prompts even with a newer pending attempt',
    () {
      for (final stage in ['down_payment', 'full']) {
        final paid = prompt(
          payments: [
            PaymentRecord({
              'payment_stage': stage,
              'status': 'confirmed',
              'amount': 7200,
            }),
            const PaymentRecord({
              'payment_stage': 'down_payment',
              'status': 'pending_confirmation',
              'provider': 'paymongo',
            }),
          ],
        );
        expect(paid.confirmed, isTrue);
        expect(BookingPaymentPromptGate().shouldPresent(paid), isFalse);
      }
    },
  );

  test('terminal bookings and manual payments under review do not prompt', () {
    for (final status in [
      'cancelled',
      'completed',
      'expired',
      'rejected',
      'waiting_for_drivers',
    ]) {
      expect(prompt(status: status).paymentRequired, isFalse);
    }
    expect(
      prompt(
        payments: [
          const PaymentRecord({
            'payment_stage': 'down_payment',
            'status': 'pending_confirmation',
            'provider': 'manual',
          }),
        ],
      ).paymentRequired,
      isFalse,
    );
  });

  test(
    'Directions preserves every inbound leg and drop-off, rounding seconds up',
    () async {
      const points = [
        LatLng(14.95, 120.9),
        LatLng(14.96, 120.91),
        LatLng(14.97, 120.92),
        LatLng(14.98, 120.93),
      ];
      final service = ItineraryScheduleService(
        apiKey: 'test',
        directionsLoader: (_, sent) async {
          expect(sent, points);
          return {
            'status': 'OK',
            'routes': [
              {
                'legs': [
                  for (final seconds in [600, 601, 1500])
                    {
                      'duration': {'value': seconds},
                      'distance': {'value': 1000},
                    },
                ],
              },
            ],
          };
        },
      );
      final legs = await service.fetchTravelLegs(points);
      expect(legs.map((l) => l.durationMinutes), [10, 11, 25]);
      final times = calculateItineraryTimings(
        pickupMinutes: 480,
        stayDurationMinutes: [60, 30],
        travelDurationMinutes: legs
            .take(2)
            .map((l) => l.durationMinutes)
            .toList(),
      );
      expect(times.first.arrivalMinutes, 490);
      expect(times.first.departureMinutes, 550);
      expect(times.last.arrivalMinutes, 561);
      expect(times.last.departureMinutes + legs.last.durationMinutes, 616);
    },
  );

  test(
    'Maps failure, missing legs and malformed durations fail without invented times',
    () async {
      for (final response in <Map<String, dynamic>>[
        {'status': 'REQUEST_DENIED'},
        {'status': 'ZERO_RESULTS'},
        {
          'status': 'OK',
          'routes': [
            {'legs': []},
          ],
        },
        {
          'status': 'OK',
          'routes': [
            {
              'legs': [
                {
                  'duration': {'value': -1},
                  'distance': {'value': 20},
                },
              ],
            },
          ],
        },
        {
          'status': 'OK',
          'routes': [
            {
              'legs': [
                {
                  'distance': {'value': 20},
                },
              ],
            },
          ],
        },
      ]) {
        final service = ItineraryScheduleService(
          apiKey: '',
          directionsLoader: (_, _) async => response,
        );
        await expectLater(
          service.fetchTravelLegs([const LatLng(1, 1), const LatLng(2, 2)]),
          throwsA(isA<ItineraryRouteException>()),
        );
      }
      final service = ItineraryScheduleService(
        apiKey: '',
        directionsLoader: (_, _) async =>
            throw const SocketException('offline'),
      );
      await expectLater(
        service.fetchTravelLegs([const LatLng(1, 1), const LatLng(2, 2)]),
        throwsA(isA<ItineraryRouteException>()),
      );
    },
  );

  testWidgets(
    'review requires agreement, preserves details and returns submission only after confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      bool? submitted;
      var policyOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    submitted = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      constraints: const BoxConstraints(maxHeight: 775),
                      builder: (_) => BookingReviewSheet(
                        summary: const [
                          (
                            label: 'Tour Package',
                            value: 'Baliwag & Pulilan Tour',
                          ),
                          (label: 'Pickup', value: 'SM Baliwag'),
                          (label: 'Pickup Date', value: 'September 6, 2026'),
                          (label: 'Pickup Time', value: '8:00 AM'),
                          (label: 'Passengers', value: '6 passengers'),
                          (label: 'Tricycles', value: '2'),
                          (label: 'Total', value: '₱7,200'),
                          (label: 'Downpayment Required', value: '₱3,600'),
                          (label: 'Remaining Balance', value: '₱3,600'),
                        ],
                        itinerary: const [
                          ListTile(
                            title: Text('Cafe Beam'),
                            subtitle: Text(
                              'ETA 8:10 AM · Stay 60 min · Departure 9:10 AM',
                            ),
                          ),
                        ],
                        onViewPolicies: () => policyOpened = true,
                      ),
                    );
                  },
                  child: const Text('Confirm Booking'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Confirm Booking'));
      await tester.pumpAndSettle();
      expect(submitted, isNull);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.text('View TourisTrike booking policies'),
      );
      await tester.tap(find.text('View TourisTrike booking policies'));
      expect(policyOpened, isTrue);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Confirm & Submit Booking'));
      await tester.pumpAndSettle();
      expect(submitted, isTrue);
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'review layout fits ${width.toInt()}px with a scrollable itinerary',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Roboto'),
            home: Scaffold(
              body: RepaintBoundary(
                key: key,
                child: Material(
                  color: Colors.white,
                  child: BookingReviewSheet(
                    summary: const [
                      (label: 'Tour Package', value: 'Baliwag & Pulilan Tour'),
                      (label: 'Pickup', value: 'SM Baliwag'),
                      (label: 'Pickup Date', value: 'September 6, 2026'),
                      (label: 'Pickup Time', value: '8:00 AM'),
                      (label: 'Passengers', value: '6 passengers'),
                      (label: 'Tricycles', value: '2'),
                      (label: 'Booking Type', value: 'Advance Booking'),
                      (label: 'Estimated Tour Duration', value: '3h 20m'),
                      (label: 'Estimated Drop-off', value: '11:20 AM'),
                      (label: 'Total', value: '₱7,200'),
                      (label: 'Downpayment Required', value: '₱3,600'),
                      (label: 'Remaining Balance', value: '₱3,600'),
                    ],
                    itinerary: const [
                      ListTile(
                        title: Text('Cafe Beam'),
                        subtitle: Text(
                          'Travel 10 min · ETA 8:10 AM\nStay 60 min · Departure 9:10 AM',
                        ),
                      ),
                      ListTile(
                        title: Text('Jollibee Pulilan'),
                        subtitle: Text(
                          'Travel 10 min · ETA 9:20 AM\nStay 30 min · Departure 9:50 AM',
                        ),
                      ),
                    ],
                    onViewPolicies: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'review-${width.toInt()}');
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await capture(tester, key, 'review-agreement-${width.toInt()}');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'payment sheet updates from ready to incomplete to webhook confirmed',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = ValueNotifier<BookingPaymentPrompt?>(prompt());
      addTearDown(state.dispose);
      var checkoutCalls = 0;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: Colors.white,
                child: BookingPaymentSheet(
                  state: state,
                  onPay: () => checkoutCalls++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);
      await capture(tester, key, 'payment-required');
      await tester.tap(find.byType(FilledButton));
      expect(checkoutCalls, 1);
      state.value = prompt(accepted: 1);
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
      state.value = prompt(
        payments: [
          const PaymentRecord({
            'payment_stage': 'down_payment',
            'status': 'confirmed',
            'amount': 7200,
          }),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Payment Confirmed'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'payment-confirmed');
    },
  );
}
