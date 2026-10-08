import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';

String read(String path) => File(
  path,
).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

void main() {
  late String migration;
  late String createPayment;
  late String refundFunction;
  late String touristTracking;
  late String driverEarnings;
  late String driverTracking;

  setUpAll(() {
    migration = read(
      'supabase/migrations/20261009000000_paymongo_test_pending_payout_lifecycle.sql',
    );
    createPayment = read('supabase/functions/paymongo-create-payment/index.ts');
    refundFunction = read(
      'supabase/functions/paymongo-process-test-refund/index.ts',
    );
    touristTracking = read(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    );
    driverEarnings = read('lib/screens/driver/driver_earnings_screen.dart');
    driverTracking = read(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    );
  });

  test('1 confirmed test payment leaves every driver payout pending', () {
    expect(migration, contains('sync_test_payment_pending_payouts'));
    expect(migration, contains("set status = 'pending', eligible_at = null"));
    expect(touristTracking, contains('Downpayment Paid'));
    expect(touristTracking, contains('Driver Payout Pending'));
  });

  test('2 payment success never marks a payout paid or succeeded', () {
    final syncStart = migration.indexOf(
      'create or replace function public.sync_test_payment_pending_payouts',
    );
    final syncEnd = migration.indexOf(
      'create or replace function public.apply_test_payout_outcome',
    );
    final syncBody = migration.substring(syncStart, syncEnd);
    expect(syncBody, isNot(contains("status = 'paid'")));
    expect(syncBody, isNot(contains("status = 'processing'")));
  });

  test('3 driver withdrawal cancels only their payout and starts search', () {
    expect(
      migration,
      contains("set status = 'cancelled', cancelled_at = now()"),
    );
    expect(migration, contains("replacement_status = 'awaiting_replacement'"));
    expect(migration, contains('notify_eligible_replacement_drivers'));
    expect(migration, contains("'payment_preserved', true"));
  });

  test('4 replacement reuses the original booking payment allocation', () {
    expect(migration, contains('replaces_allocation_id'));
    expect(
      migration,
      contains('v_replacement.payment_record_id, new.booking_id'),
    );
    expect(
      migration,
      contains("when v_replacement.payment_status = 'confirmed'"),
    );
  });

  test('5 replacement does not create another downpayment requirement', () {
    expect(migration, contains("'additional_downpayment_required', false"));
    expect(touristTracking, contains('No additional downpayment required.'));
  });

  test('6 expired replacement window creates a TEST refund', () {
    expect(migration, contains('process_expired_driver_replacements'));
    expect(migration, contains("'system', 'no_replacement_driver'"));
    expect(migration, contains('create_full_test_refund_requests'));
    expect(migration, contains("'touristrike-expired-driver-replacements'"));
    expect(refundFunction, contains('https://api.paymongo.com/v1/refunds'));
  });

  test(
    '7 tourist cancellation beyond configurable 12h is fully refundable',
    () {
      expect(migration, contains('free_cancellation_hours = 12'));
      expect(migration, contains('make_interval(hours => v_cutoff)'));
      expect(migration, contains("when v_early then 100 else 0"));
      expect(migration, contains("when v_early then 'processing'"));
    },
  );

  test(
    '8 tourist cancellation inside cutoff is not refundable and eligible',
    () {
      expect(migration, contains("else 'not_eligible'"));
      expect(migration, contains("'eligible', 'tourist_late_cancellation'"));
    },
  );

  test('9 verified driver no-show cancels payout and refunds if needed', () {
    expect(migration, contains('resolve_booking_no_show_report'));
    expect(
      migration,
      contains("cancellation_reason='verified_driver_no_show'"),
    );
    expect(migration, contains("'cancelled','verified_driver_no_show'"));
    expect(migration, contains("'driver','verified_driver_no_show'"));
    expect(touristTracking, contains('Report Driver No-Show'));
  });

  test('10 tourist no-show requires arrival evidence and enables payout', () {
    expect(
      migration,
      contains("raise exception 'DRIVER_ARRIVAL_EVIDENCE_REQUIRED'"),
    );
    expect(migration, contains("booking_status='tourist_no_show'"));
    expect(migration, contains("refund_status='not_eligible'"));
    expect(migration, contains("'eligible','verified_tourist_no_show'"));
    expect(driverTracking, contains('Report Tourist No-Show'));
  });

  test('11 completion is an explicit payout eligibility outcome', () {
    expect(migration, contains('mark_completed_booking_payout_eligible'));
    expect(migration, contains("new.id, 'eligible', 'tour_completed'"));
  });

  test(
    '12 one group driver replacement preserves other active allocations',
    () {
      expect(migration, contains('where booking_driver_id = old.id'));
      expect(
        migration,
        contains('(p_driver_id is null or pa.driver_id = p_driver_id)'),
      );
      expect(
        migration,
        contains('payment_allocations_active_replacement_uidx'),
      );
    },
  );

  test('13 lifecycle introduces no wallet, escrow, or stored value', () {
    final added = '$migration\n$refundFunction';
    expect(added, isNot(contains('wallet_balance')));
    expect(added.toLowerCase(), isNot(contains('escrow_balance')));
    expect(added.toLowerCase(), isNot(contains('stored_value')));
    expect(
      driverEarnings,
      contains('pending payout is not money already received'),
    );
  });

  test('test mode rejects live environment and live keys', () {
    expect(createPayment, contains('PAYMONGO_TEST_MODE_REQUIRED'));
    expect(createPayment, contains('sk_test_'));
    expect(refundFunction, contains('PAYMONGO_TEST_MODE_REQUIRED'));
    expect(refundFunction, contains('test_mode: true'));
  });

  test(
    'model labels pending and eligible allocations without implying receipt',
    () {
      const pending = PaymentAllocation({
        'status': 'pending',
        'payment_records': {'status': 'confirmed'},
      });
      const eligible = PaymentAllocation({
        'status': 'eligible',
        'payment_records': {'status': 'confirmed'},
      });
      const paid = PaymentAllocation({
        'status': 'paid',
        'payment_records': {'status': 'confirmed'},
      });

      expect(pending.isPayoutPending, isTrue);
      expect(pending.isPaidOut, isFalse);
      expect(pending.payoutStatusLabel, 'Pending payout');
      expect(eligible.isPayoutEligible, isTrue);
      expect(eligible.payoutStatusLabel, 'Eligible after tour completion');
      expect(paid.isPaidOut, isTrue);
    },
  );
}
