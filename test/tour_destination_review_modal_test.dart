import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/screens/driver/driver_package_tracking_screen.dart';
import 'package:touristrike/screens/tourist/tourist_activity_tracking_screen.dart';
import 'package:touristrike/widgets/driver_tourist_review_card.dart';

void main() {
  test('driver review prompt does not reopen on realtime rebuild', () {
    final gate = DriverTouristReviewPromptGate();
    expect(gate.hasPrompted('booking-1'), false);
    expect(gate.reserve('booking-1'), true);
    expect(gate.hasPrompted('booking-1'), true);
    expect(gate.reserve('booking-1'), false);
    expect(gate.reserve('booking-2'), true);
  });

  final longName = 'Cafe Galilea Bustos with a very long destination name';
  final longAddress =
      '1163 General Alejo G. Santos Highway, Bustos, Bulacan, Philippines, '
      'near the entrance on the opposite side of the road';

  BookingItineraryItem stop(String status) => BookingItineraryItem({
    'id': 'stop-1',
    'destination_name': longName,
    'destination_address': longAddress,
    'estimated_stay_duration_minutes': 42,
    'spot_status': status,
  });

  for (final width in [320.0, 430.0]) {
    for (final atSpot in [false, true]) {
      testWidgets(
        'driver destination is responsive at $width, atSpot=$atSpot',
        (tester) async {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.4)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: DriverTourDestinationCard(
                    bookingId: 'booking-1',
                    currentItem: stop(atSpot ? 'at_spot' : 'pending'),
                    completedCount: 0,
                    totalCount: 3,
                    eta: '1 min',
                    status: 'ongoing',
                    stayTiming: const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          );
          expect(find.text(longName), findsOneWidget);
          expect(find.text(longAddress), findsOneWidget);
          expect(find.text('Included stay: 42 min'), findsOneWidget);
          expect(find.text('Stop 1 of 3'), findsOneWidget);
          expect(find.text('1 min'), findsOneWidget);
          expect(
            find.text(atSpot ? 'CURRENT DESTINATION' : 'NEXT DESTINATION'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'tourist destination is responsive at $width, atSpot=$atSpot',
        (tester) async {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.4)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: TouristTourDestinationCard(
                    bookingId: 'booking-1',
                    spot: stop(atSpot ? 'at_spot' : 'pending'),
                    completedCount: 0,
                    totalCount: 3,
                    eta: '1 min',
                    stayTiming: const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          );
          expect(find.text(longName), findsOneWidget);
          expect(find.text(longAddress), findsOneWidget);
          expect(find.text('Included stay: 42 min'), findsOneWidget);
          expect(find.text('Stop 1 of 3'), findsOneWidget);
          expect(find.text('1 min'), findsOneWidget);
          expect(
            find.text(atSpot ? 'CURRENT DESTINATION' : 'NEXT DESTINATION'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test('destination card follows map and no standalone stay card remains', () {
    final driver = File(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    ).readAsStringSync();
    final tourist = File(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    ).readAsStringSync();
    expect(
      driver.indexOf('_NavigationMapCard('),
      lessThan(
        driver.indexOf(
          'DriverTourDestinationCard(',
          driver.indexOf('_NavigationMapCard('),
        ),
      ),
    );
    expect(
      tourist.indexOf('_TourMapCard('),
      lessThan(
        tourist.indexOf(
          'TouristTourDestinationCard(',
          tourist.indexOf('_TourMapCard('),
        ),
      ),
    );
    expect(
      driver.split('_NavigationMapCard(').first,
      isNot(contains('TourStayStatusCard(')),
    );
    expect(tourist, contains('showDestinationDetails: false'));
    expect(driver, isNot(contains('DriverTouristReviewCard(')));
  });

  testWidgets('review modal submits once, then closes', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DriverTouristReviewModal(
                    bookingId: 'booking-1',
                    touristName: 'Juan Dela Cruz',
                    submitReview: (bookingId, rating, comment) async {
                      calls++;
                      expect(bookingId, 'booking-1');
                      expect(rating, 5);
                      expect(comment, 'Helpful tourist');
                      await pending.future;
                    },
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Rate your tourist'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    await tester.tap(find.byTooltip('5 stars'));
    await tester.enterText(find.byType(TextField), 'Helpful tourist');
    await tester.tap(find.text('Submit Review'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Submitting...'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(result, true);
    expect(calls, 1);
  });

  testWidgets('failed review remains editable and Later dismisses', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<bool>(
                context: context,
                builder: (_) => DriverTouristReviewModal(
                  bookingId: 'booking-1',
                  touristName: 'Tourist',
                  submitReview: (_, _, _) async => throw StateError('private'),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('1 star'));
    await tester.pump();
    await tester.ensureVisible(find.text('Submit Review'));
    await tester.tap(find.text('Submit Review'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      find.text('Review could not be submitted. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Submit Review'), findsOneWidget);
    await tester.ensureVisible(find.text('Later'));
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Rate your tourist'), findsNothing);
  });
}
