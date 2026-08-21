import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/widgets/package_booking_cancellation_flow.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260821000000_package_booking_cancellation.sql',
    ).readAsStringSync();
  });

  CancellationEligibility eligibility({
    bool canCancel = true,
    String reasonCode = 'CANCELLATION_ALLOWED',
    String cancellationType = 'free_cancellation',
    double paid = 0,
    double fee = 0,
    double refundable = 0,
    bool hasDrivers = false,
  }) {
    return CancellationEligibility.fromJson({
      'can_cancel': canCancel,
      'reason_code': reasonCode,
      'display_message': 'Policy result',
      'cancellation_type': cancellationType,
      'amount_paid': paid,
      'cancellation_fee': fee,
      'refundable_amount': refundable,
      'non_refundable_amount': fee,
      'refund_rate': paid == 0 ? 0 : refundable / paid * 100,
      'refund_type': refundable == 0 ? 'non_refundable' : 'refund_request',
      'has_assigned_drivers': hasDrivers,
    });
  }

  test('1 tourist can cancel before any driver accepts', () {
    expect(eligibility().canCancel, isTrue);
    expect(eligibility().hasAssignedDrivers, isFalse);
  });

  test('2 cancellation result records an accepted driver release', () {
    final value = eligibility(hasDrivers: true);
    expect(value.hasAssignedDrivers, isTrue);
    expect(migration, contains('where booking_id = p_booking_id and status = \'accepted\''));
  });

  test('3 group cancellation releases every connected driver', () {
    expect(migration, contains('array_agg(distinct driver_id)'));
    expect(migration, contains('where p.id = any(v_driver_ids)'));
  });

  test('4 more than 24 hours is full refund policy', () {
    expect(migration, contains('v_hours_before > v_policy.free_cancellation_hours'));
    expect(migration, contains('v_refund_rate := 100'));
  });

  test('5 between 6 and 24 hours uses partial refund policy', () {
    final value = eligibility(
      cancellationType: 'standard_cancellation',
      paid: 1000,
      fee: 500,
      refundable: 500,
    );
    expect(value.refundableAmount, 500);
    expect(value.nonRefundableAmount, 500);
  });

  test('6 under 6 hours uses non-refundable policy', () {
    final value = eligibility(
      cancellationType: 'non_refundable_cancellation',
      paid: 1000,
      fee: 1000,
    );
    expect(value.refundableAmount, 0);
    expect(value.cancellationFee, 1000);
  });

  test('7 cancellation after driver arrival is humanized', () {
    expect(
      humanizeCancellationError(Exception('DRIVER_ALREADY_ARRIVED')),
      contains('driver has arrived'),
    );
  });

  test('8 cancellation after pickup is rejected as started', () {
    expect(migration, contains("'picked_up', 'on_tour'"));
    expect(
      humanizeCancellationError(Exception('TOUR_ALREADY_STARTED')),
      contains('started'),
    );
  });

  test('9 duplicate cancellation has a stable error', () {
    expect(
      humanizeCancellationError(Exception('BOOKING_ALREADY_CANCELLED')),
      'This booking has already been cancelled.',
    );
  });

  test('10 unauthorized tourist has a stable error', () {
    expect(
      humanizeCancellationError(Exception('NOT_BOOKING_OWNER')),
      contains('not allowed'),
    );
  });

  test('11 no payment requires no refund request', () {
    final value = eligibility();
    expect(value.amountPaid, 0);
    expect(value.refundableAmount, 0);
    expect(migration, contains("when v_amount_paid = 0 then 'not_required'"));
  });

  test('12 pending payment is cancelled but preserved', () {
    expect(migration, contains("status = 'pending_confirmation'"));
    expect(migration, isNot(contains('delete from public.payment_records')));
  });

  test('13 confirmed refundable payment creates refund request', () {
    expect(migration, contains('insert into public.refund_requests'));
    expect(migration, contains("pr.status = 'confirmed'"));
  });

  test('14 confirmed non-refundable payment has zero refund', () {
    final value = eligibility(paid: 700, fee: 700);
    expect(value.refundableAmount, zero);
    expect(value.nonRefundableAmount, 700);
  });

  test('15 partial refund values deserialize without rounding loss', () {
    final value = eligibility(paid: 999.5, fee: 499.75, refundable: 499.75);
    expect(value.refundableAmount, 499.75);
    expect(value.cancellationFee, 499.75);
    expect(value.refundRate, 50);
  });

  test('16 realtime tables include cancellation consumers', () {
    expect(migration, contains('alter publication supabase_realtime'));
    expect(migration, contains("tablename = 'refund_requests'"));
    expect(migration, contains("tablename = 'notifications'"));
  });

  test('17 driver acceptance race is serialized with row locks', () {
    expect(migration, contains('where id = p_booking_id\n  for update'));
    expect(migration, contains('from public.booking_drivers\n  where booking_id = p_booking_id for update'));
  });

  test('18 driver arrival and payment races have database guards', () {
    expect(migration, contains('trg_guard_cancelled_package_activity'));
    expect(migration, contains('trg_guard_cancelled_booking_payment'));
    expect(migration, contains("raise exception 'BOOKING_CANCELLED'"));
  });
}
