import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;
  late String repository;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260827010000_fix_initial_package_booking_state.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    repository = File(
      'lib/core/supabase/touristrike_repository.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  });

  test('solo booking starts waiting for one driver', () {
    expect(repository, contains("'required_drivers': requiredDrivers"));
    expect(repository, contains("'booking_status': 'waiting_for_drivers'"));
    expect(migration, contains('new.required_drivers < 1'));
  });

  test('two-driver booking is a valid unassigned initial state', () {
    expect(migration, contains("not in ('pending', 'waiting_for_drivers')"));
    expect(migration, contains("new.booking_status := 'waiting_for_drivers'"));
    expect(migration, contains('new.accepted_drivers_count := 0'));
  });

  test(
    'larger convoy booking is accepted when required drivers is positive',
    () {
      expect(migration, contains('new.required_drivers < 1'));
      expect(migration, isNot(contains('new.required_drivers > 2')));
    },
  );

  test('initial assignment and nonzero accepted count remain invalid', () {
    expect(migration, contains('new.assigned_driver_id is not null'));
    expect(migration, contains('coalesce(new.accepted_drivers_count, 0) <> 0'));
  });

  test('package activity synchronization trigger remains the creator', () {
    final syncMigration = File(
      'supabase/migrations/20260517000000_wallet_system.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    expect(syncMigration, contains('CREATE TRIGGER trg_sync_package_activity'));
    expect(
      syncMigration,
      contains('AFTER INSERT OR UPDATE ON public.package_bookings'),
    );
    expect(syncMigration, contains('ON CONFLICT (booking_id) DO UPDATE'));
  });
}
