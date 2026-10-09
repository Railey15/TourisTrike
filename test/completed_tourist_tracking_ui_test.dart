import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/booking_feedback.dart';
import 'package:touristrike/core/presentation/tourist_tracking_visibility.dart';
import 'package:touristrike/widgets/booking_feedback_card.dart';
import 'package:touristrike/widgets/report_assigned_driver_button.dart';

void main() {
  group('completed tourist tracking visibility', () {
    test('completed booking wins over stale live and payment statuses', () {
      final visibility = TouristTrackingVisibility.fromStatuses(
        bookingStatus: 'confirmed',
        bookingLifecycleStatus: 'completed',
        activityStatus: 'ongoing',
        tourStatus: 'awaiting_remaining_payment',
        hasPickedUpAt: true,
      );

      expect(visibility.isCompleted, isTrue);
      expect(visibility.isTerminal, isTrue);
      expect(visibility.showEmergency, isFalse);
      expect(visibility.showLivePaymentProgress, isFalse);
      expect(visibility.showLiveDriverControls, isFalse);
      expect(visibility.showRealtimeTourProgress, isFalse);
    });

    test('cancelled and refunded bookings cannot expose emergency actions', () {
      final cancelled = TouristTrackingVisibility.fromStatuses(
        bookingLifecycleStatus: 'cancelled',
        tourStatus: 'on_tour',
        hasPickedUpAt: true,
      );
      final refunded = TouristTrackingVisibility.fromStatuses(
        bookingLifecycleStatus: 'on_tour',
        tourStatus: 'on_tour',
        refundStatus: 'refunded',
        hasPickedUpAt: true,
      );

      expect(cancelled.showEmergency, isFalse);
      expect(refunded.showEmergency, isFalse);
      expect(cancelled.isTerminal, isTrue);
      expect(refunded.isTerminal, isTrue);
    });

    test('emergency remains available during a valid active tour', () {
      final visibility = TouristTrackingVisibility.fromStatuses(
        bookingLifecycleStatus: 'on_tour',
        tourStatus: 'at_spot',
        hasPickedUpAt: true,
      );

      expect(visibility.isTerminal, isFalse);
      expect(visibility.showEmergency, isTrue);
      expect(visibility.showLivePaymentProgress, isTrue);
    });
  });

  testWidgets('submitted feedback is compact and report action remains clear', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var reportPressed = false;
    final feedback = BookingFeedback({
      'booking_id': 'booking-1',
      'package_name': 'Heritage Tour',
      'can_review': true,
      'package_review': {'rating': 5, 'review_text': 'Great route'},
      'drivers': [
        {
          'name': 'Dina Driver',
          'review': {'rating': 4, 'review_text': 'Safe trip'},
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                BookingFeedbackCard(
                  feedback: feedback,
                  onReview: () => fail('completed feedback must not reopen'),
                ),
                const SizedBox(height: 12),
                ReportAssignedDriverButton(
                  onPressed: () => reportPressed = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Feedback'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Package Rating'), findsOneWidget);
    expect(find.text('Driver Rating'), findsOneWidget);
    expect(find.text('5.0'), findsOneWidget);
    expect(find.text('4.0'), findsOneWidget);
    expect(find.text('Rate This Tour'), findsNothing);
    expect(find.text('Report Assigned Driver'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Report Assigned Driver'));
    expect(reportPressed, isTrue);
  });
}
