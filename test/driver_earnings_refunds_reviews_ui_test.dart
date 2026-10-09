import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/widgets/driver_ratings_reviews_sheet.dart';

String source(String path) => File(path).readAsStringSync();

PaymentAllocation allocation(String earningStatus) => PaymentAllocation({
  'driver_id': 'driver-1',
  'driver_amount': 420.0,
  'earning_status': earningStatus,
  'payment_record_status': 'confirmed',
});

DriverReview review(int index) => DriverReview({
  'booking_id': 'booking-$index',
  'driver_id': 'driver-1',
  'tourist_id': 'tourist-$index',
  'rating': index.isEven ? 5 : 4,
  'review_text': 'Review entry $index',
  'created_at': DateTime.utc(2026, 10, index.clamp(1, 9)).toIso8601String(),
  'package_bookings': {
    'tour_packages': {'title': 'Heritage Tour $index'},
  },
});

void main() {
  test('only confirmed completed allocations count toward driver earnings', () {
    expect(allocation('completed').countsTowardDriverEarnings, isTrue);
    expect(allocation('refund_pending').countsTowardDriverEarnings, isFalse);
    expect(allocation('refunded').countsTowardDriverEarnings, isFalse);
    expect(allocation('disputed').countsTowardDriverEarnings, isFalse);
  });

  test('refunded direct records are not finalized driver earnings', () {
    const confirmed = PaymentRecord({'status': 'confirmed'});
    const refundPending = PaymentRecord({'status': 'refund_pending'});
    const refunded = PaymentRecord({'status': 'refunded'});

    expect(confirmed.isFinalizedDriverEarning, isTrue);
    expect(refundPending.isRefundRelated, isTrue);
    expect(refundPending.isFinalizedDriverEarning, isFalse);
    expect(refunded.isRefundRelated, isTrue);
    expect(refunded.isFinalizedDriverEarning, isFalse);
  });

  testWidgets('ratings modal is scrollable and safe on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDriverRatingsReviewsSheet(
                  context,
                  averageRating: 4.7,
                  totalReviews: 12,
                  reviews: Future.value(
                    List.generate(12, (index) => review(index + 1)),
                  ),
                ),
                child: const Text('Open reviews'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reviews'));
    await tester.pumpAndSettle();

    expect(find.text('Ratings & Reviews'), findsOneWidget);
    expect(find.text('12 reviews'), findsOneWidget);
    expect(find.text('Review entry 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Review entry 12'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Review entry 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ratings modal has an empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverRatingsReviewsSheet(
            averageRating: 0,
            totalReviews: 0,
            reviews: Future.value(const <DriverReview>[]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New'), findsOneWidget);
    expect(find.text('No reviews yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('earnings, export, and home sources use the refund-safe UX', () {
    final earnings = source('lib/screens/driver/driver_earnings_screen.dart');
    final report = source('lib/core/reports/personal_report_service.dart');
    final home = source('lib/screens/driver/driver_home_screen.dart');
    final overview = source('lib/widgets/driver_overview_details.dart');
    final migration = source(
      'supabase/migrations/20261009160000_driver_earnings_refunds_and_reviews.sql',
    );

    expect(earnings, contains('FilledButton.icon'));
    expect(earnings, contains('Preparing PDF'));
    expect(earnings, contains('Excluded from total earnings'));
    expect(earnings, contains('countsTowardDriverEarnings'));
    expect(report, contains('completedAllocations'));
    expect(report, contains('isFinalizedDriverEarning'));
    expect(home, contains('showDriverRatingsReviewsSheet'));
    expect(home, contains('fetchMyDriverReviews'));
    expect(overview, isNot(contains("data['recent_reviews']")));
    expect(migration, contains("pa.earning_status = 'completed'"));
    expect(migration, isNot(contains("pa.status not in ('cancelled'")));
  });
}
