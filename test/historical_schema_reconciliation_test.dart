import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _lines(String source, int start, int end) {
  final lines = source.split('\n');
  return lines.sublist(start - 1, end).join('\n').trim();
}

void main() {
  const reconciliationPath =
      'supabase/migrations/20260927005000_historical_schema_reconciliation.sql';

  late String reconciliation;

  setUpAll(() {
    reconciliation = _read(reconciliationPath);
  });

  test('forward reconciliation has one transaction and no row backfill', () {
    expect(
      RegExp(r'^begin;$', multiLine: true).allMatches(reconciliation),
      hasLength(1),
    );
    expect(
      RegExp(r'^commit;$', multiLine: true).allMatches(reconciliation),
      hasLength(1),
    );
    expect(
      reconciliation,
      isNot(contains('update public.package_bookings pb')),
    );
    expect(
      reconciliation,
      contains(
        'RECONCILIATION_REQUIRES_REVIEW: eligible same-day rows now exist',
      ),
    );
  });

  test('reviewed historical function sections are copied exactly', () {
    final paymentSource = _read(
      'supabase/migrations/20260831010000_transaction_lifecycle_consistency.sql',
    );
    final phase4Source = _read(
      'supabase/migrations/20260905030000_phase4_stabilization.sql',
    );
    final settingsSource = _read(
      'supabase/migrations/20260926010000_provincial_admin_settings.sql',
    );

    for (final range in <(int, int)>[
      (5, 81),
      (102, 251),
      (486, 592),
      (615, 992),
      (1664, 1807),
    ]) {
      expect(
        reconciliation,
        contains(_lines(paymentSource, range.$1, range.$2)),
      );
    }
    final phase4Reviewed = _lines(phase4Source, 8, 325).replaceAll(
      '-- Supporting indexes for RLS EXISTS checks and participant lookups.\n'
          'create index if not exists tourist_spot_images_spot_idx\n'
          '  on public.tourist_spot_images(spot_id);',
      '-- Supporting indexes for RLS EXISTS checks and participant lookups. The live\n'
          '-- idx_tourist_spot_images_spot_id index already covers spot_id, so the\n'
          '-- historical duplicate tourist_spot_images_spot_idx is intentionally omitted.',
    );
    expect(reconciliation, contains(phase4Reviewed));

    for (final requiredFragment in <String>[
      'add column if not exists office_name text',
      'add column if not exists payment_dispute_notifications boolean not null default true',
      'create policy own_settings on public.admin_settings',
      'create or replace function public.protect_own_profile_scope()',
      'create or replace function public.enforce_provincial_admin_required_settings()',
      'create or replace function public.provincial_admin_notification_allowed(',
      'create or replace function public.apply_provincial_admin_notification_preference()',
      'create or replace function public.notify_provincial_admins(',
      'create or replace function public.notify_admin_city_application()',
      'create or replace function public.notify_admin_driver_status()',
      'create or replace function public.notify_admin_payment_dispute()',
      'create or replace function public.notify_admin_emergency_alert()',
    ]) {
      expect(settingsSource, contains(requiredFragment));
      expect(reconciliation, contains(requiredFragment));
    }
  });

  test('obsolete or superseded lifecycle definitions are excluded', () {
    for (final functionName in <String>[
      'complete_current_itinerary_item',
      'advance_driver_journey_state',
      'debug_advance_driver_journey_state',
      'complete_package_tour',
      'debug_complete_package_tour',
      'debug_force_complete_test_trip',
      'get_shared_trip_details',
      'complete_wallet_cash_in',
    ]) {
      expect(
        reconciliation,
        isNot(contains('create or replace function public.$functionName')),
      );
    }
  });

  test('broken live historical RPCs are explicitly repaired or retired', () {
    for (final functionName in <String>[
      'credit_driver_wallet',
      'deduct_wallet_balance',
      'driver_accept_group_booking',
      'admin_list_users',
      'admin_get_user',
    ]) {
      expect(
        reconciliation,
        contains('drop function if exists public.$functionName'),
      );
    }
    expect(
      reconciliation,
      contains('create or replace function public.approve_city_registration'),
    );
    expect(reconciliation, contains('where id::text = p_registration_id'));
    expect(reconciliation, contains('if not public.is_provincial_admin()'));
    expect(
      reconciliation,
      contains(
        'create or replace function public.record_payment_allocation_transfer_result',
      ),
    );
    expect(reconciliation, isNot(contains('paymongo_reference = case')));
  });

  test('RLS, policy, trigger, and index gaps are covered', () {
    for (final table in <String>[
      'admin_settings',
      'driver_details',
      'driver_documents',
      'ride_feedback',
      'ride_reviews',
      'tour_package_day_items',
      'tour_package_days',
      'tour_package_spots',
      'tour_package_views',
      'tourist_spot_images',
      'tourist_spot_views',
    ]) {
      expect(
        reconciliation,
        contains('alter table public.$table enable row level security;'),
      );
    }

    for (final policy in <String>[
      'spot_views_insert_authenticated',
      'package_views_insert_authenticated',
      'ride_reviews_insert_tourist',
      'ride_feedback_insert_tourist',
      'categories_read_authenticated',
      'categories_admin_write',
      'policies_select_published_staff',
      'policies_admin_write',
    ]) {
      expect(reconciliation, contains('create policy $policy'));
    }

    expect(
      RegExp(
        r'^create index if not exists ',
        multiLine: true,
      ).allMatches(reconciliation),
      hasLength(14),
    );
    expect(
      RegExp(r'^create trigger ', multiLine: true).allMatches(reconciliation),
      hasLength(16),
    );
  });
}
