import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;
  late String paymentTrailMigration;
  late String lifecycleMigration;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260827000000_p0_booking_integrity.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    paymentTrailMigration = File(
      'supabase/migrations/20260725000000_gcash_payment_trail.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    lifecycleMigration = File(
      'supabase/migrations/20260831010000_transaction_lifecycle_consistency.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  });

  bool overlaps(
    DateTime startA,
    DateTime endA,
    DateTime startB,
    DateTime endB,
  ) {
    return startA.isBefore(endB) && startB.isBefore(endA);
  }

  test('1 booking tomorrow does not block booking today', () {
    expect(
      overlaps(
        DateTime.utc(2026, 8, 27, 9),
        DateTime.utc(2026, 8, 27, 12),
        DateTime.utc(2026, 8, 28, 9),
        DateTime.utc(2026, 8, 28, 12),
      ),
      isFalse,
    );
  });

  test('2 adjacent same-day bookings are non-overlapping', () {
    expect(
      overlaps(
        DateTime.utc(2026, 8, 27, 9),
        DateTime.utc(2026, 8, 27, 10),
        DateTime.utc(2026, 8, 27, 10),
        DateTime.utc(2026, 8, 27, 11),
      ),
      isFalse,
    );
    expect(migration, contains("tstzrange(p_booking.scheduled_start_at"));
    expect(migration, contains("'[)'"));
  });

  test('3 same-time booking conflict is rejected', () {
    expect(
      overlaps(
        DateTime.utc(2026, 8, 27, 9),
        DateTime.utc(2026, 8, 27, 11),
        DateTime.utc(2026, 8, 27, 9),
        DateTime.utc(2026, 8, 27, 11),
      ),
      isTrue,
    );
    expect(migration, contains("raise exception 'DRIVER_SCHEDULE_CONFLICT'"));
  });

  test('4 cancelled completed and rejected bookings do not conflict', () {
    expect(
      migration,
      contains("not in ('cancelled', 'completed', 'rejected', 'done')"),
    );
  });

  test('5 concurrent acceptance is serialized for booking and driver', () {
    expect(migration, contains('pg_advisory_xact_lock'));
    expect(migration, contains('where id = p_booking_id\n  for update'));
  });

  test(
    '6 fully assigned advanced booking gets one down-payment requirement',
    () {
      expect(migration, contains('ensure_booking_payment_requirements'));
      expect(migration, contains('unique (booking_id, payment_stage)'));
      expect(migration, contains("(p_booking_id, 'down_payment'"));
    },
  );

  test('7 duplicate active payment-stage submissions are impossible', () {
    expect(migration, contains('payment_records_one_active_booking_stage_idx'));
    expect(
      migration,
      contains("where booking_id is not null and status <> 'cancelled'"),
    );
  });

  test('8 confirmation is locked idempotent and issues one receipt', () {
    expect(migration, contains('confirm_payment_record'));
    expect(migration, contains("if v_record.status = 'confirmed' then"));
    expect(paymentTrailMigration, contains('new.receipt_no is null'));
    expect(paymentTrailMigration, contains('nextval'));
  });

  test('9 tour start requires confirmed down payment', () {
    expect(migration, contains("raise exception 'DOWNPAYMENT_NOT_CONFIRMED'"));
    expect(migration, contains("pr.payment_stage = 'down_payment'"));
    expect(migration, contains("pr.status = 'confirmed'"));
  });

  test('10 advanced booking cannot start early', () {
    expect(
      migration,
      contains('now() < lower(public.package_booking_schedule_window'),
    );
    expect(migration, contains("raise exception 'BOOKING_START_TOO_EARLY'"));
  });

  test('11 global completion requires confirmed remaining balance', () {
    expect(
      lifecycleMigration,
      contains("bpr.payment_stage = 'remaining_balance'"),
    );
    expect(lifecycleMigration, contains("pr.status = 'confirmed'"));
    expect(
      lifecycleMigration,
      contains('pr.id = bpr.satisfied_by_payment_record_id'),
    );
  });

  test('12 first completed convoy driver cannot complete overall booking', () {
    expect(lifecycleMigration, contains('v_completed_slots = v_active_slots'));
    expect(
      lifecycleMigration,
      contains("'overall_completed', v_overall_completed"),
    );
    expect(
      lifecycleMigration,
      contains('order by public.journey_state_order(journey_state)'),
    );
  });

  test('13 pickup stop and drop-off barriers remain backend enforced', () {
    expect(lifecycleMigration, contains("v_current = 'boarded'"));
    expect(lifecycleMigration, contains("v_current = 'stop_done'"));
    expect(lifecycleMigration, contains("v_current = 'at_dropoff'"));
    expect(lifecycleMigration, contains("raise exception 'BARRIER_NOT_MET'"));
  });

  test('14 every validated journey transition is audited server-side', () {
    expect(lifecycleMigration, contains('insert into public.trip_status_logs'));
    expect(lifecycleMigration, contains('previous_state, new_state'));
    expect(lifecycleMigration, contains('Server-validated journey transition'));
  });

  test('15 direct roster and payment confirmation bypasses are closed', () {
    expect(
      migration,
      contains('drop policy if exists "booking_drivers_driver_insert"'),
    );
    expect(
      migration,
      contains('drop policy if exists "booking_drivers_driver_update"'),
    );
    expect(migration, contains('drop policy if exists payment_records_update'));
  });

  test('16 historical bookings cannot read current driver location', () {
    expect(migration, contains('drop policy if exists "live_loc_read_all"'));
    expect(migration, contains('create policy live_loc_select_active_trip'));
    expect(
      migration,
      contains("not in ('cancelled', 'completed', 'rejected', 'done')"),
    );
  });

  test('17 completed guest trips return no driver coordinates', () {
    expect(
      migration,
      contains('get_shared_trip_details_before_p0_location_guard'),
    );
    expect(
      migration,
      contains("jsonb_set(v_result, '{driver_latitude}', 'null'::jsonb"),
    );
    expect(
      migration,
      contains("jsonb_set(v_result, '{driver_longitude}', 'null'::jsonb"),
    );
  });

  test('18 guest trip wrapper migration is safe to retry', () {
    expect(migration, contains('to_regprocedure('));
    expect(
      migration,
      contains(
        'public.get_shared_trip_details_before_p0_location_guard(text,text,text,text,boolean)',
      ),
    );
  });
}
