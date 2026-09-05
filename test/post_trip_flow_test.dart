import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/components/tourist/driver_review_modal.dart';
import 'package:touristrike/core/models/booking_feedback.dart';
import 'package:touristrike/core/models/booking_payment_prompt.dart';
import 'package:touristrike/core/services/stable_arrival_detector.dart';
import 'package:touristrike/core/services/itinerary_schedule_service.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/widgets/booking_feedback_card.dart';
import 'package:touristrike/widgets/booking_payment_sheet.dart';
import 'booking_review_payment_flow_test.dart' show capture;

BookingFeedback feedback({bool complete = false}) => BookingFeedback({
  'booking_id': 'booking',
  'package_name': 'Baliwag Tour',
  'can_review': true,
  'package_review': complete
      ? {'rating': 5, 'review_text': 'Great tour'}
      : null,
  'drivers': [
    for (final id in ['A', 'B'])
      {
        'driver_id': id,
        'name': 'Driver $id',
        'review': complete
            ? {'rating': 4, 'review_text': 'Helpful driver $id'}
            : null,
      },
  ],
});

BookingPaymentPrompt remaining({
  bool stopsDone = true,
  bool dropoff = false,
  String type = 'same_day',
  List<PaymentRecord> records = const [],
  List<PaymentAllocation> allocations = const [],
}) => BookingPaymentPrompt.fromRecords(
  PackageBooking({
    'id': 'booking',
    'booking_type': type,
    'required_drivers': 2,
    'accepted_drivers_count': 2,
    'booking_status': 'awaiting_remaining_payment',
    'status': 'ongoing',
    'total_amount': 7200,
    'remaining_balance': 3600,
    'downpayment_amount': 3600,
    'tour_packages': {'title': 'Baliwag Tour'},
  }),
  records,
  stage: 'remaining_balance',
  itineraryComplete: stopsDone,
  dropoffStarted: dropoff,
  allocations: allocations,
);

class FeedbackRepository extends TourisTrikeRepository {
  FeedbackRepository()
    : super(
        client: SupabaseClient(
          'https://example.supabase.co',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  int calls = 0;
  List<Json> submitted = [];
  Completer<Json> pending = Completer<Json>();
  @override
  Future<Json> submitBookingFeedback({
    required String bookingId,
    int? packageRating,
    String packageComment = '',
    required List<Json> driverReviews,
  }) {
    calls++;
    submitted = driverReviews;
    return pending.future;
  }
}

void main() {
  setUpAll(() async {
    final fonts =
        '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts';
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final file = File('$fonts/${entry.value}');
      if (file.existsSync()) {
        final loader = FontLoader(entry.key)
          ..addFont(
            file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
      }
    }
  });
  test(
    'live routing requests traffic on individual legs and retains route order',
    () async {
      final requests = <Uri>[];
      final result = await http.runWithClient(
        () => const ItineraryScheduleService.live(apiKey: 'test')
            .fetchTravelLegs([
              const LatLng(15, 121),
              const LatLng(15.1, 121.1),
              const LatLng(15.2, 121.2),
            ]),
        () => MockClient((request) async {
          requests.add(request.url);
          expect(request.url.queryParameters['departure_time'], 'now');
          expect(request.url.queryParameters.containsKey('waypoints'), isFalse);
          final first = request.url.queryParameters['origin'] == '15.0,121.0';
          return http.Response(
            jsonEncode({
              'status': 'OK',
              'routes': [
                {
                  'legs': [
                    {
                      'duration': {'value': 600},
                      if (first) 'duration_in_traffic': {'value': 901},
                      'distance': {'value': 2000},
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );
      expect(requests.length, 2);
      expect(result.map((leg) => leg.durationMinutes), [16, 10]);
    },
  );

  test(
    'undersized confirmed payment does not hide remaining payment action',
    () {
      expect(
        remaining(
          records: [
            const PaymentRecord({
              'payment_stage': 'remaining_balance',
              'status': 'confirmed',
              'amount': 1,
            }),
          ],
        ).paymentRequired,
        isTrue,
      );
    },
  );
  test('arrival needs three distinct fixes and six stable seconds', () {
    final detector = StableArrivalDetector(radiusMeters: 150);
    final start = DateTime.utc(2026, 9, 6);
    bool sample(
      int seconds, {
      String target = 'pickup',
      double distance = 100,
      double accuracy = 10,
      int age = 0,
    }) => detector.observe(
      target: target,
      distanceMeters: distance,
      accuracyMeters: accuracy,
      sampledAt: start.add(Duration(seconds: seconds)),
      now: start.add(Duration(seconds: seconds + age)),
    );
    expect(sample(0), isFalse);
    expect(sample(0), isFalse); // same fix from stream + recovery
    expect(sample(3), isFalse);
    expect(sample(6), isTrue);
    expect(sample(7, target: 'stop-1'), isFalse);
    expect(sample(10, target: 'stop-1', distance: 151), isFalse);
    expect(sample(13, target: 'stop-1'), isFalse);
    expect(sample(16, target: 'stop-1'), isFalse);
    expect(sample(19, target: 'stop-1'), isTrue);
    expect(sample(22, target: 'stop-1', accuracy: 90), isFalse);
    expect(sample(25, target: 'stop-1', age: 30), isFalse);
    expect(sample(60, target: 'stop-1'), isFalse); // gap resets stability
    expect(sample(63, target: 'stop-1'), isFalse);
    expect(sample(66, target: 'stop-1'), isTrue);
  });

  test('actual arrival anchors stay, elapsed stay clamps to zero', () {
    final arrival = DateTime(2026, 9, 6, 8, 17);
    expect(
      remainingStopStay(
        arrivedAt: arrival,
        stayMinutes: 60,
        now: DateTime(2026, 9, 6, 9, 10),
      ),
      const Duration(minutes: 7),
    );
    expect(
      remainingStopStay(
        arrivedAt: arrival,
        stayMinutes: 60,
        now: DateTime(2026, 9, 6, 9, 20),
      ),
      Duration.zero,
    );
  });

  test(
    'feedback reserves before asynchronous reads and needs every driver',
    () {
      final gate = BookingFeedbackGate();
      expect(gate.reserve(), isTrue);
      for (var i = 0; i < 10; i++) {
        expect(gate.reserve(), isFalse);
      }
      expect(feedback().complete, isFalse);
      expect(feedback(complete: true).complete, isTrue);
      final partial = feedback(complete: true).row;
      (partial['drivers'] as List).last['review'] = null;
      expect(BookingFeedback(partial).complete, isFalse);
    },
  );

  for (final type in ['same_day', 'advanced']) {
    test('$type remaining payment needs all stops before drop-off, once', () {
      final gate = BookingPaymentPromptGate();
      expect(
        gate.shouldPresent(remaining(type: type, stopsDone: false)),
        isFalse,
      );
      expect(gate.shouldPresent(remaining(type: type)), isTrue);
      expect(gate.shouldPresent(remaining(type: type)), isFalse);
      expect(remaining(type: type, dropoff: true).paymentRequired, isFalse);
      for (final stage in ['remaining_balance', 'full']) {
        expect(
          remaining(
            type: type,
            records: [
              PaymentRecord({
                'payment_stage': stage,
                'status': 'confirmed',
                'amount': 7200,
              }),
            ],
          ).paymentRequired,
          isFalse,
        );
      }
    });
  }

  testWidgets(
    'remaining sheet updates to cash progress and confirmed in place',
    (tester) async {
      final state = ValueNotifier<BookingPaymentPrompt?>(
        remaining(
          records: [
            const PaymentRecord({
              'payment_stage': 'down_payment',
              'status': 'confirmed',
              'amount': 3600,
            }),
          ],
        ),
      );
      var paid = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookingPaymentSheet(state: state, onPay: () => paid++),
          ),
        ),
      );
      expect(find.text('Downpayment Paid'), findsOneWidget);
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      expect(paid, 1);
      state.value = remaining(
        records: [
          const PaymentRecord({
            'payment_stage': 'remaining_balance',
            'status': 'pending_confirmation',
            'provider': 'manual',
            'payment_method': 'cash',
          }),
        ],
        allocations: [
          const PaymentAllocation({
            'status': 'cash_confirmed',
            'payment_records': {'payment_stage': 'remaining_balance'},
          }),
        ],
      );
      await tester.pump();
      expect(find.textContaining('1 driver shares confirmed'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      state.value = remaining(
        records: [
          const PaymentRecord({
            'payment_stage': 'remaining_balance',
            'status': 'confirmed',
            'amount': 7200,
          }),
        ],
      );
      await tester.pump();
      expect(find.text('Payment Confirmed'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'one feedback sheet submits all drivers, blocks duplicate taps, retries failure',
    (tester) async {
      final repo = FeedbackRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .9,
                  ),
                  builder: (_) =>
                      DriverReviewModal(feedback: feedback(), repository: repo),
                ),
                child: const Text('Open feedback'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open feedback'));
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Submit Feedback');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      for (var section = 0; section < 3; section++) {
        final star = find.byType(IconButton).at(section * 5 + 4);
        await tester.ensureVisible(star);
        await tester.tap(star);
        await tester.pump();
      }
      final comment = find.byType(TextField).last;
      await tester.ensureVisible(comment);
      await tester.enterText(comment, 'Very accommodating');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(repo.calls, 1);
      expect(repo.submitted.map((r) => r['driver_id']), ['A', 'B']);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      repo.pending.completeError(StateError('connection lost'));
      await tester.pumpAndSettle();
      expect(find.text('Very accommodating'), findsOneWidget);
      repo.pending = Completer<Json>();
      await tester.tap(submit);
      await tester.pump();
      expect(repo.calls, 2);
      repo.pending.complete(feedback(complete: true).row);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Rate Your Tour'), findsNothing);
    },
  );

  testWidgets('booking history displays submitted transaction comments', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingFeedbackCard(
            feedback: feedback(complete: true),
            onReview: () {},
          ),
        ),
      ),
    );
    expect(find.text('Great tour'), findsOneWidget);
    expect(find.text('Helpful driver A'), findsOneWidget);
    expect(find.text('Helpful driver B'), findsOneWidget);
  });

  testWidgets('remaining and feedback layouts fit a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final state = ValueNotifier<BookingPaymentPrompt?>(remaining());
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          home: Scaffold(
            body: BookingPaymentSheet(state: state, onPay: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, key, 'remaining-balance-320');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          home: Scaffold(
            body: DriverReviewModal(
              feedback: feedback(),
              repository: FeedbackRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, key, 'feedback-320');
    await tester.ensureVisible(find.text('Submit Feedback'));
    await tester.pumpAndSettle();
    await capture(tester, key, 'feedback-submit-320');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
