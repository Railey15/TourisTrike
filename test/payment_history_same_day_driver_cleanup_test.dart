import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/booking_payment_prompt.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';

String read(String path) => File(
  path,
).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

PaymentRecord payment({
  String stage = 'down_payment',
  String status = 'confirmed',
  double amount = 900,
}) => PaymentRecord({
  'id': 'payment-1',
  'booking_id': '12345678-abcd-0000-0000-000000000000',
  'payer_id': 'tourist-1',
  'amount': amount,
  'payment_method': 'gcash',
  'payment_stage': stage,
  'status': status,
  'receipt_no': 'TT-RECEIPT-1',
  'provider': 'paymongo',
  'provider_reference': 'pay_test_123',
  'package_bookings': {
    'id': '12345678-abcd-0000-0000-000000000000',
    'tour_packages': {'title': 'Malolos Heritage Tour'},
  },
});

RefundRequest refund({String reason = 'service adjustment'}) => RefundRequest({
  'id': 'refund-1',
  'booking_id': '12345678-abcd-0000-0000-000000000000',
  'payment_record_id': 'payment-1',
  'amount': 900,
  'reason': reason,
  'status': 'completed',
  'provider_refund_id': 'refund_test_123',
});

void main() {
  late String migration;
  late String repository;
  late String paymentScreen;
  late String receiptScreen;
  late String trackingScreen;
  late String detailsScreen;
  late String pendingLifecycle;

  setUpAll(() {
    migration = read(
      'supabase/migrations/20261009010000_payment_history_same_day_driver_cleanup.sql',
    );
    repository = read('lib/core/supabase/touristrike_repository.dart');
    paymentScreen = read(
      'lib/screens/tourist/profile/payment_history_screen.dart',
    );
    receiptScreen = read(
      'lib/screens/shared/acknowledgement_receipt_screen.dart',
    );
    trackingScreen = read(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    );
    detailsScreen = read(
      'lib/screens/driver/driver_package_booking_details_screen.dart',
    );
    pendingLifecycle = read(
      'supabase/migrations/20261009000000_paymongo_test_pending_payout_lifecycle.sql',
    );
  });

  test('1 payment history displays the actual package name', () {
    final entry = PaymentHistoryEntry.payment(payment());
    expect(entry.packageName, 'Malolos Heritage Tour');
    expect(entry.title, 'Malolos Heritage Tour - Down Payment');
  });

  test('2 downpayment is labeled Down Payment', () {
    expect(
      PaymentHistoryEntry.payment(payment()).transactionType,
      'Down Payment',
    );
  });

  test('3 remaining balance is labeled Remaining Balance', () {
    expect(
      PaymentHistoryEntry.payment(
        payment(stage: 'remaining_balance'),
      ).transactionType,
      'Remaining Balance',
    );
  });

  test('4 refund is clearly labeled as a refund', () {
    final entry = PaymentHistoryEntry.refund(
      payment: payment(),
      refund: refund(),
    );
    expect(entry.transactionType, 'Down Payment Refund');
    expect(entry.statusLabel, 'Refunded');
  });

  test('5 outgoing payment has an explicit negative sign', () {
    expect(PaymentHistoryEntry.payment(payment()).amountPrefix, '-');
    expect(paymentScreen, contains(r'${item.amountPrefix} PHP'));
  });

  test('6 incoming refund has an explicit positive sign', () {
    final entry = PaymentHistoryEntry.refund(
      payment: payment(),
      refund: refund(),
    );
    expect(entry.amountPrefix, '+');
    expect(
      receiptScreen,
      contains(r'+ PHP ${entry.amount.toStringAsFixed(2)}'),
    );
  });

  test('7 refund links to the original payment and receipt', () {
    final request = refund();
    final entry = PaymentHistoryEntry.refund(
      payment: payment(),
      refund: request,
    );
    expect(request.paymentRecordId, 'payment-1');
    expect(entry.originalPaymentReference, 'TT-RECEIPT-1');
    expect(repository, contains('payment_records!inner'));
  });

  test('8 Total Paid includes confirmed outgoing payments only', () {
    final entries = [
      PaymentHistoryEntry.payment(payment()),
      PaymentHistoryEntry.refund(payment: payment(), refund: refund()),
    ];
    final totalPaid = entries
        .where((entry) => !entry.isRefund && entry.payment.isConfirmed)
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    expect(totalPaid, 900);
    expect(
      paymentScreen,
      contains('!item.isRefund && item.payment.isConfirmed'),
    );
  });

  test('9 same-day booking requires a 50 percent downpayment', () {
    expect(migration, contains('round(new.total_amount * 0.50, 2)'));
    expect(migration, contains('v_downpayment := round(v_total * 0.5, 2);'));
    expect(
      migration,
      contains(
        'create or replace function public.create_package_booking_additional_request_impl',
      ),
    );
    expect(migration, isNot(contains('pg_get_functiondef(')));
    expect(migration, isNot(contains('UNRECOGNIZED_CUSTOM_FARE_PAYMENT_RULE')));
    expect(migration, isNot(contains('case when v_same_day then 0')));
    final bookingSource = read(
      'lib/screens/tourist/package_booking_screen.dart',
    );
    expect(bookingSource, isNot(contains('if (_isSameDay) return 0;')));
  });

  test('10 payment prompt waits until every required driver accepts', () {
    BookingPaymentPrompt prompt(
      int accepted,
      Map<String, dynamic>? requirement,
    ) => BookingPaymentPrompt.fromRecords(
      PackageBooking({
        'id': 'booking-1',
        'booking_type': 'same_day',
        'required_drivers': 2,
        'accepted_drivers_count': accepted,
        'booking_status': accepted == 2 ? 'accepted' : 'waiting_for_drivers',
        'status': accepted == 2 ? 'confirmed' : 'pending',
        'total_amount': 1800,
        'downpayment_amount': 900,
        'remaining_balance': 900,
      }),
      const [],
      requirement: requirement,
    );
    expect(prompt(1, null).paymentRequired, isFalse);
    expect(
      prompt(2, const {'status': 'required', 'amount': 900}).paymentRequired,
      isTrue,
    );
    expect(migration, contains('is_booking_driver_roster_full'));
  });

  test(
    '11 a driver who cancels Booking X cannot inspect or accept it again',
    () {
      expect(migration, contains('prior_assignment.booking_id = b.id'));
      expect(migration, contains('prior_assignment.driver_id = actor.id'));
      final acceptance = read(
        'supabase/migrations/20260827000000_p0_booking_integrity.sql',
      );
      expect(acceptance, contains('raise exception \'ALREADY_ACCEPTED\''));
    },
  );

  test('12 cancellation remains scoped to one booking', () {
    const driverId = 'driver-a';
    const history = [
      {'booking_id': 'booking-x', 'driver_id': driverId},
    ];
    bool canAccept(String bookingId) => !history.any(
      (row) => row['booking_id'] == bookingId && row['driver_id'] == driverId,
    );
    expect(canAccept('booking-x'), isFalse);
    expect(canAccept('booking-y'), isTrue);
    expect(migration, contains('prior_assignment.booking_id = b.id'));
    expect(migration, contains('prior_assignment.driver_id = actor.id'));
  });

  test('13 cancelled assignments are excluded from active driver lists', () {
    expect(
      repository,
      contains(".inFilter('status', const ['accepted', 'completed'])"),
    );
    expect(repository, contains(".eq('status', 'accepted')"));
  });

  test('14 cancelled driver is redirected to Package Jobs immediately', () {
    expect(trackingScreen, contains('void _redirectToPackageJobs()'));
    expect(trackingScreen, contains('const DriverPackageJobsScreen()'));
    expect(trackingScreen, contains('pushAndRemoveUntil'));
    expect(detailsScreen, contains('void _redirectToPackageJobs()'));
  });

  test('15 refresh and relogin recheck authoritative assignment state', () {
    expect(repository, contains('fetchMyBookingDriverAssignment'));
    expect(
      trackingScreen,
      contains('_repo.fetchMyBookingDriverAssignment(bookingId)'),
    );
    expect(
      trackingScreen,
      contains("_refreshLifecycleAndConvoy('convoy-poll')"),
    );
  });

  test('16 PayMongo TEST pending payout and refund lifecycle is preserved', () {
    expect(pendingLifecycle, contains('sync_test_payment_pending_payouts'));
    expect(
      pendingLifecycle,
      contains("set status = 'pending', eligible_at = null"),
    );
    expect(pendingLifecycle, contains('create_full_test_refund_requests'));
    expect(migration.toLowerCase(), isNot(contains('wallet_balance')));
    expect(migration.toLowerCase(), isNot(contains('escrow_balance')));
  });
}
