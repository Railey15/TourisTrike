import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:touristrike/core/models/booking_capacity.dart';
import 'package:touristrike/core/recommendations/tourist_ai_recommendation_service.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/driver/driver_package_jobs_screen.dart';
import 'package:touristrike/screens/tourist/spot_details_screen.dart';
import 'package:touristrike/widgets/cash_confirmation_dialog.dart';
import 'package:touristrike/widgets/payment_contact_sheet.dart';
import 'package:touristrike/widgets/tour_stay_details.dart';
import 'package:touristrike/widgets/tourist/home_spot_link.dart';
import 'package:touristrike/widgets/tourist_reputation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  test('required tricycles follow the server supplied capacity exactly', () {
    const capacity = 3;
    expect(BookingCapacity.requiredTricycles(1, capacity), 1);
    expect(BookingCapacity.requiredTricycles(3, capacity), 1);
    expect(BookingCapacity.requiredTricycles(4, capacity), 2);
    expect(BookingCapacity.requiredTricycles(6, capacity), 2);
    expect(BookingCapacity.requiredTricycles(7, capacity), 3);
    expect(BookingCapacity.requiredTricycles(2, capacity), 1);
    expect(() => BookingCapacity.validate(1, 2, capacity), throwsArgumentError);
    expect(() => BookingCapacity.validate(4, 1, capacity), throwsArgumentError);
    expect(() => BookingCapacity.validate(4, 2, capacity), returnsNormally);
  });

  test('registered contact prefills but missing data stays empty', () {
    final contact = PaymentContact.fromAccount(
      profile: {'full_name': 'Juan Dela Cruz', 'first_name': 'Different'},
      authEmail: 'juan@example.com',
    );
    expect(contact.name, 'Juan Dela Cruz');
    expect(contact.email, 'juan@example.com');
    expect(
      PaymentContact.fromAccount(
        profile: {'first_name': 'Juan', 'last_name': 'Dela Cruz'},
      ).name,
      'Juan Dela Cruz',
    );
    expect(PaymentContact.fromAccount().name, isEmpty);
    expect(PaymentContact.fromAccount().email, isEmpty);
  });

  test(
    'edited payment contact is sent only to the checkout function',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'payment_record_id': 'payment-1',
              'checkout_url': 'https://checkout.example.test',
              'reused': false,
              'livemode': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final checkout = await TourisTrikeRepository(client: client)
          .createPayMongoCheckout(
            bookingId: 'booking-1',
            paymentStage: 'remaining_balance',
            customerName: 'Maria Dela Cruz',
            customerEmail: 'maria@example.com',
          );
      expect(checkout.paymentRecordId, 'payment-1');
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/functions/v1/paymongo-create-payment');
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['customer_name'], 'Maria Dela Cruz');
      expect(body['customer_email'], 'maria@example.com');
      expect(body.containsKey('amount'), false);
      expect(requests.single.url.path.contains('profiles'), false);
      expect(requests.single.url.path.contains('auth'), false);
    },
  );

  testWidgets('payment contact remains editable on narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PaymentContact? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                submitted = await showModalBottomSheet<PaymentContact>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const PaymentContactSheet(
                    name: 'Juan',
                    email: 'juan@example.com',
                  ),
                );
              },
              child: const Text('Pay'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<TextFormField>(find.byType(TextFormField)).length,
      2,
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'Juan',
    );
    await tester.enterText(find.byType(TextFormField).first, 'Maria');
    await tester.enterText(
      find.byType(TextFormField).last,
      'maria@example.com',
    );
    await tester.ensureVisible(find.text('Continue to PayMongo'));
    await tester.tap(find.text('Continue to PayMongo'));
    await tester.pumpAndSettle();
    expect(submitted?.name, 'Maria');
    expect(submitted?.email, 'maria@example.com');
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets('assignment shows saved locations and rating at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final longPickup =
          'SM City Baliwag, Baliwag, Bulacan — '
          'long saved entrance and landmark directions for the Tourist pickup';
      final job = PackageActivity({
        'id': 'activity-1',
        'booking_id': 'booking-1',
        'status': 'pending',
        'price': 150,
        'tour_packages': {'title': 'Sample Package', 'city': 'Baliwag'},
        'package_bookings': {
          'id': 'booking-1',
          'travel_date': '2026-09-30',
          'adults': 1,
          'children': 0,
          'total_passengers': 1,
          'booking_type': 'same_day',
          'required_drivers': 1,
          'accepted_drivers_count': 0,
          'municipality': 'Baliwag',
          'province': 'Bulacan',
          'pickup_address': longPickup,
          'dropoff_address': 'Bustos Municipal Hall, Bustos, Bulacan',
          'total_amount': 150,
        },
      });
      var acceptCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DriverAssignmentCard(
                job: job,
                itineraryCount: 3,
                itineraryItems: const [],
                accepting: false,
                disabledReason: null,
                reputationLoader: (_) async => {
                  'display_name': 'Juan Dela Cruz',
                  'average_rating': 4.5,
                  'total_reviews': 2,
                  'distribution': {'5': 1, '4': 1},
                  'reviews': [
                    {
                      'rating': 5,
                      'review_text': 'Helpful',
                      'created_at': '2026-09-01T00:00:00Z',
                    },
                  ],
                },
                onAccept: () => acceptCount++,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(longPickup), findsOneWidget);
      expect(
        find.text('Bustos Municipal Hall, Bustos, Bulacan'),
        findsOneWidget,
      );
      expect(find.text('★ 4.5 · 2 reviews'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Juan Dela Cruz'));
      await tester.tap(find.text('Juan Dela Cruz'));
      await tester.pumpAndSettle();
      expect(find.byType(TouristRatingSheet), findsOneWidget);
      expect(find.text('Helpful'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Accept Assignment'));
      await tester.tap(find.text('Accept Assignment'));
      expect(acceptCount, 1);
    });
  }

  testWidgets('unrated tourist has no fake zero rating', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TouristReputation(
            bookingId: 'booking',
            load: (_) async => {
              'display_name': 'Tourist A',
              'average_rating': null,
              'total_reviews': 0,
              'distribution': {},
              'reviews': [],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No ratings yet'), findsOneWidget);
    await tester.tap(find.text('Tourist A'));
    await tester.pumpAndSettle();
    expect(find.text('No ratings yet'), findsWidgets);
    expect(find.textContaining('0.0'), findsNothing);
  });

  testWidgets('cash modal prevents double taps and stays on failure', (
    tester,
  ) async {
    final gate = CashConfirmationPromptGate();
    expect(gate.shouldPresent('payment-1'), true);
    expect(gate.shouldPresent('payment-1'), false);
    expect(gate.shouldPresent('payment-2'), true);
    final first = Completer<void>();
    var calls = 0;
    var successful = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CashConfirmationDialog(
                  amount: 50,
                  onConfirm: () {
                    calls++;
                    if (calls == 2) {
                      throw StateError('CASH_PAYMENT_STATE_CHANGED');
                    }
                    if (!successful) return first.future;
                    return Future.value();
                  },
                ),
              ),
              child: const Text('Show cash'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show cash'));
    await tester.pumpAndSettle();
    expect(find.text('₱50.00'), findsOneWidget);
    await tester.tap(find.text('Confirm Cash Received'));
    await tester.pump();
    expect(find.text('Confirming…'), findsOneWidget);
    first.completeError(StateError('failure'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('could not be confirmed'), findsOneWidget);
    expect(find.byType(CashConfirmationDialog), findsOneWidget);
    await tester.tap(find.text('Confirm Cash Received'));
    await tester.pumpAndSettle();
    expect(find.textContaining('amount changed'), findsOneWidget);
    expect(find.byType(CashConfirmationDialog), findsOneWidget);
    successful = true;
    await tester.tap(find.text('Confirm Cash Received'));
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(find.byType(CashConfirmationDialog), findsNothing);
  });

  testWidgets('shared stop and payment summary render on narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                TourStayDetails(
                  destination: 'Baliwag, Bulacan',
                  includedMinutes: 60,
                  secondsRemaining: -1080,
                  rate: 50,
                  intervalMinutes: 20,
                  accruedWaiting: 100,
                ),
                TourPaymentSummary(
                  packageBalance: 50,
                  additionalWaiting: 100,
                  totalRemaining: 150,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Free grace: 2 min remaining'), findsOneWidget);
    expect(find.text('Included stay: 60 min'), findsOneWidget);
    expect(find.text('₱50.00 / started 20 min'), findsNothing);
    expect(
      find.textContaining('₱50.00 / 20 min after one free interval'),
      findsOneWidget,
    );
    expect(find.text('₱150.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home spot uses existing Details route with correct ID', (
    tester,
  ) async {
    const spot = TouristAiRecommendationSpot(
      id: '123',
      title: 'Rosario Chapel',
      address: 'Bustos, Bulacan',
      distanceText: '2 km away',
      distanceKm: 2,
      category: 'Religious',
      rating: 4.8,
      imageUrl: '',
      latitude: 14.96,
      longitude: 120.92,
      municipality: 'Bustos',
      googlePlaceId: '',
      description: 'Chapel',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeSpotLink(spot: spot, child: Text('Recommended spot')),
        ),
      ),
    );
    await tester.tap(find.text('Recommended spot'));
    await tester.pumpAndSettle();
    expect(find.byType(TouristSpotDetailsScreen), findsOneWidget);
    expect(
      tester
          .widget<TouristSpotDetailsScreen>(
            find.byType(TouristSpotDetailsScreen),
          )
          .spot
          .id,
      '123',
    );
  });
}
