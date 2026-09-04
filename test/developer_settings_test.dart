import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:touristrike/core/services/developer_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Testing Mode defaults to OFF when no preference exists', () async {
    final settings = DeveloperSettings();

    await settings.initialize();

    expect(settings.testingModeEnabled, isFalse);
    expect(settings.testModeActive, isFalse);
    expect(settings.testBookingId, isEmpty);
    expect(settings.selectedTestDriverAssignmentId, isEmpty);
    expect(settings.simulatedLocationEnabled, isFalse);
  });

  test('debug settings persist across service instances', () async {
    expect(kDebugMode, isTrue);
    final settings = DeveloperSettings();
    await settings.initialize();

    await settings.setTestingModeEnabled(true);
    await settings.setTestBookingId('9f83-test-booking');
    await settings.selectTestDriverAssignment(
      assignmentId: 'assignment-a',
      driverId: 'driver-a',
    );
    await settings.setSimulatedDriverLocation(
      enabled: true,
      latitude: 14.9597,
      longitude: 120.9206,
    );

    final restored = DeveloperSettings();
    await restored.initialize();

    expect(restored.testModeActive, isTrue);
    expect(restored.testBookingId, '9f83-test-booking');
    expect(restored.selectedTestDriverAssignmentId, 'assignment-a');
    expect(restored.selectedTestDriverId, 'driver-a');
    expect(restored.simulatedLocationEnabled, isTrue);
    expect(
      restored.canSimulateLocationFor(
        bookingId: '9f83-test-booking',
        driverId: 'driver-a',
      ),
      isTrue,
    );
  });

  test(
    'turning Testing Mode OFF restores the guarded state immediately',
    () async {
      final settings = DeveloperSettings();
      await settings.initialize();
      await settings.setTestingModeEnabled(true);

      await settings.setTestingModeEnabled(false);

      expect(settings.testingModeEnabled, isFalse);
      expect(settings.testModeActive, isFalse);
    },
  );

  test(
    'changing the shared booking clears driver-specific overrides',
    () async {
      final settings = DeveloperSettings();
      await settings.initialize();
      await settings.setTestingModeEnabled(true);
      await settings.setTestBookingId('booking-a');
      await settings.selectTestDriverAssignment(
        assignmentId: 'assignment-a',
        driverId: 'driver-a',
      );
      await settings.setSimulatedDriverLocation(
        enabled: true,
        latitude: 14.9597,
        longitude: 120.9206,
      );

      await settings.setTestBookingId('booking-b');

      expect(settings.selectedTestDriverAssignmentId, isEmpty);
      expect(settings.selectedTestDriverId, isEmpty);
      expect(settings.simulatedLocationEnabled, isFalse);
    },
  );

  test('local mode only scopes the requested booking', () async {
    final settings = DeveloperSettings();
    await settings.initialize();
    await settings.setTestBookingId('booking-a');
    await settings.setTestingModeEnabled(true);

    expect(settings.isConfiguredTestBooking('booking-a'), isTrue);
    expect(settings.isConfiguredTestBooking('booking-b'), isFalse);

    await settings.setTestingModeEnabled(false);
    expect(settings.isConfiguredTestBooking('booking-a'), isFalse);
  });

  test('driver debug entry is centralized and reset preserves financial data', () {
    final tracking = File(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    ).readAsStringSync();
    final tools = File(
      'lib/screens/driver/profile/widgets/driver_developer_tools_section.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/core/supabase/touristrike_repository.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260830010000_debug_test_trip_reset.sql',
    ).readAsStringSync();
    final bypassMigration = File(
      'supabase/migrations/20260830020000_debug_transaction_progression_bypass.sql',
    ).readAsStringSync();
    final automaticModeMigration = File(
      'supabase/migrations/20260831000000_automatic_developer_test_mode.sql',
    ).readAsStringSync();
    final diagnosticsMigration = File(
      'supabase/migrations/20260903000000_developer_test_mode_diagnostics.sql',
    ).readAsStringSync();
    final testerAuthorizationMigration = File(
      'supabase/migrations/20260903001000_authorize_tourist_test_account.sql',
    ).readAsStringSync();

    expect(tracking, isNot(contains('kDriverActionTestMode')));
    expect(tracking, contains('fetchDeveloperTestBookingMode'));
    expect(tools, contains('!kDebugMode || !_settings.testModeActive'));
    expect(migration, contains('developer_test_bookings'));
    expect(migration, contains("'payments_preserved', true"));
    expect(migration, isNot(contains('delete from public.payment_records')));
    expect(migration, isNot(contains('update public.payment_records')));
    expect(
      migration,
      isNot(contains('delete from public.payment_allocations')),
    );
    expect(migration, isNot(contains('update public.payment_allocations')));
    expect(tracking, contains('_bypassTransactionValidation'));
    expect(tracking, contains("_testActionLabel('Arrived at Pickup')"));
    expect(tracking, isNot(contains('Mark Remaining Balance Paid')));
    expect(tracking, contains('Re-enable Testing Mode in Developer Tools'));
    expect(tools, contains('setDeveloperTestBookingMode'));
    expect(
      bypassMigration,
      contains('debug_test_driver_assignment(p_booking_id)'),
    );
    expect(bypassMigration, contains('debug_advance_driver_journey_state'));
    expect(bypassMigration, contains('debug_mark_itinerary_stop_arrived'));
    expect(bypassMigration, contains('debug_complete_package_tour'));
    expect(bypassMigration, contains('debug_force_complete_test_trip'));
    expect(bypassMigration, contains("'payments_modified', false"));
    expect(bypassMigration, isNot(contains('update public.payment_records')));
    expect(
      bypassMigration,
      isNot(contains('delete from public.payment_records')),
    );
    expect(
      bypassMigration,
      isNot(contains('update public.payment_allocations')),
    );
    expect(
      bypassMigration,
      isNot(contains('delete from public.payment_allocations')),
    );
    expect(automaticModeMigration, contains('debug_set_test_booking_mode'));
    expect(automaticModeMigration, contains('is_developer_test_booking'));
    expect(automaticModeMigration, contains('developer_test_users'));
    expect(automaticModeMigration, contains('NOT_TEST_BOOKING_PARTICIPANT'));
    expect(
      automaticModeMigration,
      contains('revoke all on table public.developer_test_users'),
    );
    expect(repository, contains('logDeveloperTestDiagnostics'));
    expect(repository, contains('auth_user_id'));
    expect(repository, isNot(contains('accessToken')));
    expect(repository, isNot(contains('refreshToken')));
    expect(diagnosticsMigration, contains('debug_get_test_mode_diagnostics'));
    expect(diagnosticsMigration, contains('tester_allowlist_enabled'));
    expect(diagnosticsMigration, contains('authorization_allowed'));
    expect(
      diagnosticsMigration,
      contains(
        'grant execute on function public.debug_get_test_mode_diagnostics(uuid)',
      ),
    );
    expect(
      testerAuthorizationMigration,
      contains("'9c7091f5-8797-4e72-a85d-585d65b3b312'::uuid"),
    );
    expect(
      testerAuthorizationMigration,
      contains("lower(u.email) = 'tourist1@gmail.com'"),
    );
    expect(
      testerAuthorizationMigration,
      contains('on conflict (user_id) do update'),
    );
    expect(testerAuthorizationMigration, isNot(contains('auth.uid()')));
  });
}
