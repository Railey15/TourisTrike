import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;
  late String driverTracking;
  late String touristTracking;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260831010000_transaction_lifecycle_consistency.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    driverTracking = File(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    ).readAsStringSync();
    touristTracking = File(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    ).readAsStringSync();
  });

  test('shared stop completion is exact, idempotent, and convoy atomic', () {
    expect(
      migration,
      contains(
        'drop function if exists public.complete_current_itinerary_item(uuid, uuid, text)',
      ),
    );
    expect(migration, contains('item.id = p_itinerary_item_id'));
    expect(migration, contains("'already_completed', true"));
    expect(migration, contains("raise exception 'STALE_ITINERARY_STOP'"));
    expect(migration, contains("raise exception 'BARRIER_NOT_MET'"));
    expect(
      migration,
      contains("raise exception 'CONVOY_ARRIVAL_NOT_RECORDED'"),
    );
    expect(migration, contains("set journey_state = 'stop_done'"));
    expect(migration, contains("and journey_state = 'at_stop'"));
  });

  test('one authoritative convoy progress rule includes completed members', () {
    expect(migration, contains('get_convoy_stage_progress'));
    expect(migration, contains("bd.status in ('accepted', 'completed')"));
    expect(
      migration,
      contains("bd.status = 'completed' or bd.journey_state = 'completed'"),
    );
    expect(migration, contains("'required_driver_count', v_required_count"));
    expect(migration, contains("'satisfied_driver_count', v_satisfied_count"));
    expect(migration, contains("'waiting_driver_ids', v_waiting_driver_ids"));
    expect(driverTracking, contains('fetchConvoyStageProgress'));
    expect(driverTracking, contains('progress.waitingDriverIds'));
    expect(driverTracking, contains('_refreshLifecycleAndConvoy'));
  });

  test('assignment completion and booking completion are separate states', () {
    expect(
      migration,
      contains("status = case when p_target_state = 'completed'"),
    );
    expect(migration, contains("booking_status = 'awaiting_final_payment'"));
    expect(
      migration,
      contains("'assignment_completed', p_target_state = 'completed'"),
    );
    expect(migration, contains("'overall_completed', v_overall_completed"));
    expect(driverTracking, contains('ASSIGNMENT COMPLETED'));
    expect(driverTracking, contains('completedDriverCount'));
  });

  test('global completion requires itinerary convoy and payment truth', () {
    expect(migration, contains('v_completed_items = v_total_items'));
    expect(migration, contains('v_completed_slots = v_active_slots'));
    expect(migration, contains('v_active_slots >= v_required_slots'));
    expect(migration, contains("bpr.payment_stage = 'remaining_balance'"));
    expect(migration, contains("pr.status = 'confirmed'"));
    expect(migration, contains('pr.id = bpr.satisfied_by_payment_record_id'));
  });

  test('test mode relaxes operations but preserves lifecycle invariants', () {
    expect(
      migration,
      contains('if not v_debug_bypass\n       and now() < lower'),
    );
    expect(
      migration,
      contains(
        'if not v_debug_bypass\n'
        '       and not public.is_booking_downpayment_confirmed(p_booking_id)',
      ),
    );
    expect(migration, contains("raise exception 'DOWNPAYMENT_NOT_CONFIRMED'"));
    expect(migration, contains("raise exception 'STOP_DWELL_TIME_NOT_MET'"));
    expect(migration, contains("raise exception 'INCOMPLETE_ITINERARY'"));
    expect(
      migration,
      contains("raise exception 'TEST_FORCE_ALL_ASSIGNMENTS_NOT_ALLOWED'"),
    );
    expect(driverTracking, contains('OPERATIONAL CONSTRAINTS BYPASSED'));
  });

  test(
    'test payment remains persisted but is not mixed into tour controls',
    () {
      expect(migration, contains('debug_mark_remaining_balance_paid'));
      expect(migration, contains("'manual', 'PHP', 'awaiting_cash_receipt'"));
      expect(
        migration,
        contains("set status = 'confirmed', provider_status = 'cash_received'"),
      );
      expect(migration, contains('insert into public.payment_allocations'));
      expect(migration, contains("set status = 'satisfied'"));
      expect(driverTracking, isNot(contains('Mark Remaining Balance Paid')));
    },
  );

  test('driver and tourist refresh all lifecycle tables in realtime', () {
    for (final table in [
      'package_bookings',
      'booking_itinerary_items',
      'payment_records',
      'payment_allocations',
      'booking_payment_requirements',
    ]) {
      expect(driverTracking, contains("table: '$table'"));
      expect(touristTracking, contains("table: '$table'"));
    }
    expect(touristTracking, contains('TOUR FINISHED — AWAITING FINAL PAYMENT'));
    for (final table in ['booking_drivers', 'package_activities']) {
      expect(driverTracking, contains("table: '$table'"));
    }
  });
}
