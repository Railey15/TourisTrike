import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:touristrike/core/services/itinerary_schedule_service.dart';
import 'package:touristrike/widgets/booking_review_sheet.dart';

void main() {
  test('two-opt removes backtracking while retaining every requested stop', () {
    const pickup = LatLng(14, 120);
    const dropoff = LatLng(14, 124);
    const stops = [LatLng(14, 123), LatLng(14, 121), LatLng(14, 122)];
    final order = twoOptItineraryOrder(pickup, stops, dropoff);
    expect(order.toSet(), {0, 1, 2});
    expect(order, [1, 2, 0]);
  });

  testWidgets('review requires an unchecked terms acknowledgment', (tester) async {
    var openedTerms = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BookingReviewSheet(
      summary: const [
        (label: 'Tour Package', value: 'River tour'),
        (label: 'Pickup Time', value: '8:30 AM'),
        (label: 'Total', value: 'PHP 500.00'),
      ],
      itinerary: const [Text('Destination A')],
      onViewPolicies: () => openedTerms = true,
    ))));
    expect(find.text('Review Your Booking'), findsOneWidget);
    expect(find.text('8:30 AM'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Confirm & Submit Booking');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.ensureVisible(find.text('TourisTrike Booking Terms and Conditions'));
    await tester.tap(find.text('TourisTrike Booking Terms and Conditions'));
    expect(openedTerms, isTrue);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });
}
