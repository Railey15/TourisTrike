import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/presentation/cancellation_display.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/widgets/cancelled_booking_details.dart';

String source(String path) => File(path).readAsStringSync();

PackageBooking booking({
  double refundableAmount = 0,
  String refundStatus = 'not_required',
}) => PackageBooking({
  'id': 'booking-1',
  'package_title_snapshot': 'Bustos Town Tour',
  'package_city_snapshot': 'Bustos',
  'municipality': 'Bustos',
  'province': 'Bulacan',
  'travel_date': '2026-10-10',
  'scheduled_start_at': '2026-10-10T08:00:00',
  'estimated_end_at': '2026-10-10T12:00:00',
  'total_passengers': 3,
  'cancelled_at': '2026-10-09T15:39:00',
  'cancelled_reason': 'change_of_plans',
  'refundable_amount': refundableAmount,
  'refund_status': refundStatus,
  'tour_packages': {'title': 'Renamed Package', 'city': 'Renamed City'},
});

BookingItineraryItem spot(int index, String name) => BookingItineraryItem({
  'id': 'spot-$index',
  'booking_id': 'booking-1',
  'destination_order': index,
  'destination_name': name,
  'destination_address': 'Bustos, Bulacan',
});

void main() {
  test('cancellation reason formatter maps and safely humanizes slugs', () {
    expect(cancellationReasonLabel('change_of_plans'), 'Change of Plans');
    expect(cancellationReasonLabel('emergency'), 'Emergency');
    expect(cancellationReasonLabel('weather_condition'), 'Weather Condition');
    expect(
      cancellationReasonLabel('operator_safety_issue'),
      'Operator Safety Issue',
    );
    expect(
      cancellationReasonLabel('operator_safety_issue'),
      isNot(contains('_')),
    );
  });

  test('cancelled before payment displays zero refund and no-payment copy', () {
    final summary = CancellationRefundDisplay.fromBooking(
      booking: booking(),
      payments: const [],
      refunds: const [],
    );

    expect(summary.amount, 0);
    expect(summary.status, 'No payment was made.');
  });

  test('actual refund request amount and status override booking estimate', () {
    const payment = PaymentRecord({'status': 'confirmed', 'amount': 990});
    const completedRefund = RefundRequest({
      'amount': 495,
      'status': 'completed',
    });
    const pendingRefund = RefundRequest({'amount': 495, 'status': 'approved'});

    final refunded = CancellationRefundDisplay.fromBooking(
      booking: booking(refundableAmount: 990),
      payments: const [payment],
      refunds: const [completedRefund],
    );
    final processing = CancellationRefundDisplay.fromBooking(
      booking: booking(refundableAmount: 990),
      payments: const [payment],
      refunds: const [pendingRefund],
    );

    expect(refunded.amount, 495);
    expect(refunded.status, 'Refunded');
    expect(processing.amount, 495);
    expect(processing.status, 'Refund Processing');
  });

  test('package title uses the immutable booking snapshot', () {
    expect(booking().packageTitle, 'Bustos Town Tour');
    expect(booking().municipality, 'Bustos');
  });

  testWidgets('cancelled details show package, spots, reason and zero refund', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CancelledBookingDetails(
            packageName: 'Bustos Town Tour',
            municipality: 'Bustos',
            province: 'Bulacan',
            travelDate: DateTime(2026, 10, 10),
            scheduledStartAt: DateTime(2026, 10, 10, 8),
            estimatedEndAt: DateTime(2026, 10, 10, 12),
            touristCount: 3,
            spots: [
              spot(1, 'Cafe Galilea Bustos'),
              spot(2, 'Bustos Municipal Hall'),
              spot(3, 'Cafe Portillo'),
            ],
            cancelledAt: DateTime(2026, 10, 9, 15, 39),
            cancellationReason: 'change_of_plans',
            refund: const CancellationRefundDisplay(
              amount: 0,
              status: 'No payment was made.',
            ),
            onBack: () {},
          ),
        ),
      ),
    );

    expect(find.text('Booking Cancelled'), findsOneWidget);
    expect(find.text('Bustos Town Tour'), findsOneWidget);
    expect(find.text('Bustos, Bulacan'), findsWidgets);
    expect(find.text('3 Destinations'), findsOneWidget);
    expect(find.text('Cafe Galilea Bustos'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('No payment was made.'),
      250,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Change of Plans'), findsOneWidget);
    expect(find.text('₱0.00'), findsOneWidget);
    expect(find.text('No payment was made.'), findsOneWidget);
    expect(find.text('Cafe Portillo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('history surfaces share the formatter and persisted details flow', () {
    final touristTracking = source(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    );
    final driverTracking = source(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    );
    final activity = source('lib/screens/tourist/tourist_activity_screen.dart');
    final history = source('lib/screens/tourist/tourist_history_screen.dart');
    final result = source(
      'lib/screens/tourist/booking_cancellation_result_screen.dart',
    );
    final migration = source(
      'supabase/migrations/20261009170000_cancelled_booking_package_snapshot.sql',
    );

    expect(touristTracking, contains('CancelledBookingDetails'));
    expect(touristTracking, contains('fetchBookingRefundRequests'));
    expect(driverTracking, contains('cancellationReasonLabel(reason)'));
    expect(activity, contains('cancellationReasonLabel'));
    expect(history, contains('ActivityTrackingScreen'));
    expect(result, contains('fetchBookingItinerary'));
    expect(result, contains('fetchBookingRefundRequests'));
    expect(migration, contains('package_title_snapshot'));
    expect(migration, contains('before insert on public.package_bookings'));
  });
}
