import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  late String repository;
  late String touristTracking;
  late String driverTracking;
  late String administratorScreen;
  late String migration;

  setUpAll(() {
    repository = source('lib/core/supabase/touristrike_repository.dart');
    touristTracking = source(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    );
    driverTracking = source(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    );
    administratorScreen = source(
      'lib/screens/administrator/administrator_developer_tools_screen.dart',
    );
    migration = source(
      'supabase/migrations/20261001060000_final_developer_tools_cutover.sql',
    );
  });

  test('participant Developer Tools and local settings are removed', () {
    for (final path in [
      'lib/core/services/developer_settings.dart',
      'lib/screens/tourist/profile/widgets/developer_tools_section.dart',
      'lib/screens/driver/profile/widgets/driver_developer_tools_section.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
    final application = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(application, isNot(contains('DeveloperSettings')));
    expect(application, isNot(contains('DeveloperToolsSection')));
    expect(application, isNot(contains('DriverDeveloperToolsSection')));
  });

  test('repository exposes only read-only participant authorization', () {
    expect(repository, contains('fetchMyBookingTestAuthorization'));
    expect(repository, contains("'get_my_booking_test_authorization'"));
    for (final legacy in [
      'debug_set_test_booking_mode',
      'debug_get_test_booking_state',
      'debug_advance_driver_journey_state',
      'debug_mark_itinerary_stop_arrived',
      'debug_complete_package_tour',
      'debug_force_complete_test_trip',
      'debug_mark_remaining_balance_paid',
    ]) {
      expect(repository, isNot(contains(legacy)), reason: legacy);
    }
  });

  test('driver always calls the canonical journey RPC', () {
    expect(repository, contains("'advance_driver_journey_state'"));
    expect(repository, isNot(contains("'debug_advance_driver_journey_state'")));
  });

  test(
    'both participant tracking screens use server authorization banners',
    () {
      for (final tracking in [touristTracking, driverTracking]) {
        expect(tracking, contains('fetchMyBookingTestAuthorization'));
        expect(tracking, contains('Administrator-authorized test session'));
        expect(tracking, isNot(contains('TEST MODE ACTIVE')));
      }
    },
  );

  test('driver has no local payment or simulated-GPS bypass', () {
    expect(driverTracking, isNot(contains('_bypassTransactionValidation')));
    expect(driverTracking, isNot(contains('_simulatedDriverLocation')));
    expect(driverTracking, isNot(contains('DeveloperSettings')));
    expect(driverTracking, contains("_hasConfirmedPayment('down_payment'"));
    expect(driverTracking, contains('Geolocator.getCurrentPosition'));
  });

  test('Administrator UI separates reset from deactivation', () {
    expect(administratorScreen, contains("Key('developer-session-reset')"));
    expect(
      administratorScreen,
      contains("Key('developer-session-confirm-reset')"),
    );
    expect(administratorScreen, contains('Reset Test Trip'));
    expect(administratorScreen, contains('Deactivate session'));
  });

  test('forward migration retires legacy authorization and debug RPCs', () {
    expect(migration, contains('delete from public.developer_test_bookings'));
    expect(migration, contains('delete from public.developer_test_users'));
    expect(migration, contains(r'select false $$;'));
    expect(migration, contains('from public, anon, authenticated'));
  });

  test('reset is admin-only, financially guarded, scoped, and audited', () {
    expect(migration, contains('administrator_reset_developer_test_trip'));
    expect(migration, contains('SYSTEM_ADMINISTRATOR_REQUIRED'));
    expect(migration, contains('ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED'));
    expect(migration, contains('RESET_BLOCKED_BY_PAYOUT_STATE'));
    expect(migration, contains('RESET_BLOCKED_BY_PAYMENT_DISPUTE'));
    expect(migration, contains('RESET_BLOCKED_BY_REFUND_STATE'));
    expect(migration, contains('RESET_BLOCKED_BY_FINALIZED_WAITING_CHARGE'));
    expect(migration, contains('DEVELOPER_TEST_TRIP_RESET'));
    expect(migration, contains("where booking_id = p_booking_id"));
  });

  test('reset preserves financial and authorization records', () {
    final resetStart = migration.indexOf(
      'create or replace function public.administrator_reset_developer_test_trip',
    );
    final resetBody = migration.substring(resetStart);
    expect(resetBody, isNot(contains('delete from public.payment_records')));
    expect(
      resetBody,
      isNot(contains('delete from public.payment_allocations')),
    );
    expect(resetBody, isNot(contains('delete from public.payout_records')));
    expect(resetBody, isNot(contains('delete from public.payment_disputes')));
    expect(resetBody, isNot(contains('update public.developer_test_sessions')));
    expect(resetBody, isNot(contains('update public.system_settings')));
  });

  test('normal notification delivery no longer suppresses test bookings', () {
    final emitStart = migration.indexOf(
      'create or replace function public.emit_tour_notification',
    );
    final normalizeStart = migration.indexOf(
      'create or replace function public.normalize_tour_notification',
    );
    final availableStart = migration.indexOf(
      'create or replace function public.notify_drivers_of_available_booking',
    );
    final revokeStart = migration.indexOf(
      'revoke all on function public.emit_tour_notification',
    );
    expect(
      migration.substring(emitStart, normalizeStart),
      isNot(contains('is_developer_test_booking')),
    );
    expect(
      migration.substring(availableStart, revokeStart),
      isNot(contains('is_developer_test_booking')),
    );
  });
}
