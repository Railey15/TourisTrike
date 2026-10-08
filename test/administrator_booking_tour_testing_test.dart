import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/administrator/administrator_booking_tour_testing.dart';

void main() {
  test('production grace rule uses completed intervals', () {
    expect(bookingTestChargeableIntervals(0, 15), 0);
    expect(bookingTestChargeableIntervals(14, 15), 0);
    expect(bookingTestChargeableIntervals(15, 15), 1);
    expect(bookingTestChargeableIntervals(30, 15), 2);
    expect(bookingTestChargeableIntervals(45, 15), 3);
    expect(bookingTestChargeableIntervals(59, 15), 3);
    expect(bookingTestChargeableIntervals(60, 15), 4);
  });

  test('package stay remains immutable while runtime deadline changes', () {
    final sql = _migrationSql();
    expect(sql, contains('test_deadline_override = v_deadline'));
    expect(sql, isNot(contains('estimated_stay_duration_minutes = p_minutes')));
  });

  test('tourist receives authoritative override through shared summary', () {
    final sql = _migrationSql();
    final tourist = File(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    ).readAsStringSync();
    expect(sql, contains("'paid_until',coalesce(c.test_deadline_override"));
    expect(tourist, contains('TourStayStatusCard'));
  });

  test('driver receives authoritative override through shared summary', () {
    final stayWidget = File(
      'lib/widgets/tour_stay_status_card.dart',
    ).readAsStringSync();
    final driver = File(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    ).readAsStringSync();
    expect(stayWidget, contains("table: 'booking_stop_waiting_charges'"));
    expect(driver, contains('TourStayStatusCard'));
  });

  test('15 minute overtime uses one production billing interval', () {
    expect(bookingTestChargeableIntervals(15, 15), 1);
    expect(bookingTestChargeableIntervals(15, 15) * 30, 30);
  });

  test('30 minute overtime uses two production billing intervals', () {
    expect(bookingTestChargeableIntervals(30, 15), 2);
    expect(bookingTestChargeableIntervals(30, 15) * 30, 60);
  });

  test('partial interval follows the production completed-interval rule', () {
    expect(bookingTestChargeableIntervals(14, 15), 0);
    expect(bookingTestChargeableIntervals(29, 15), 1);
    expect(bookingTestChargeableIntervals(44, 15), 2);
  });

  test('configured-rate mode uses the waiting charge snapshot', () {
    final sql = _migrationSql();
    expect(
      sql,
      contains('v_rate := coalesce(p_custom_rate, v_charge.rate_per_interval'),
    );
    expect(sql, contains('v_booking.tour_waiting_rate_snapshot'));
  });

  test('custom test rate never updates the fare matrix', () {
    final sql = _migrationSql();
    expect(sql, contains('test_rate_per_interval_override = p_custom_rate'));
    expect(sql, isNot(contains('update public.subtenant_fare_settings')));
  });

  test('reset removes timer and overtime overrides', () {
    final sql = _migrationSql();
    expect(sql, contains('set test_deadline_override = null'));
    expect(sql, contains('then test_rate_per_interval_override else null end'));
  });

  test('active override persists in the booking ledger for reopen', () {
    final sql = _migrationSql();
    expect(sql, contains('add column if not exists test_deadline_override'));
    expect(sql, contains('add column if not exists test_override_updated_at'));
    expect(sql, contains("'override_active', v_charge.test_deadline_override"));
  });

  test('tourist role cannot satisfy developer RPC authorization', () {
    final authorization = _authorizationBlock();
    expect(authorization, isNot(contains("actor.role = 'tourist'")));
    expect(authorization, isNot(contains("actor.role='tourist'")));
  });

  test('driver role cannot satisfy developer RPC authorization', () {
    final authorization = _authorizationBlock();
    expect(authorization, isNot(contains("actor.role = 'driver'")));
    expect(authorization, isNot(contains("actor.role='driver'")));
  });

  test('subtenant cannot satisfy developer RPC authorization', () {
    final authorization = _authorizationBlock();
    expect(authorization, isNot(contains("actor.role = 'subtenant'")));
    expect(authorization, isNot(contains('office.city')));
  });

  test(
    'provincial administrator cannot satisfy developer RPC authorization',
    () {
      final authorization = _authorizationBlock();
      expect(authorization, isNot(contains("actor.role = 'main_tenant'")));
      expect(authorization, isNot(contains('actor.province')));
    },
  );

  test('system administrator is the only authorized mutation role', () {
    final authorization = _authorizationBlock();
    expect(authorization, contains('public.is_system_administrator()'));
    expect(authorization, contains('auth.uid() is not null'));
  });

  test('operational portals do not expose booking test controls', () {
    final subtenantDetails = File(
      'lib/screens/subtenant/subtenant_booking_details_screen.dart',
    ).readAsStringSync();
    final subtenantShell = File(
      'lib/screens/subtenant/layouts/subtenant_admin_shell.dart',
    ).readAsStringSync();
    final provincialNavigation = File(
      'lib/screens/main_tenant/main_tenant_nav.dart',
    ).readAsStringSync();
    for (final source in [
      subtenantDetails,
      subtenantShell,
      provincialNavigation,
    ]) {
      expect(source, isNot(contains('AdministratorBookingTourTesting')));
      expect(source, isNot(contains('Booking / Tour Testing')));
      expect(
        source,
        isNot(contains('administrator_apply_booking_timing_test')),
      );
    }
  });

  test('System Administrator page owns booking test controls', () {
    final screen = File(
      'lib/screens/administrator/administrator_developer_tools_screen.dart',
    ).readAsStringSync();
    expect(screen, contains('AdministratorBookingTourTesting'));
    expect(screen, contains('Booking / Tour Testing'));
    expect(screen, contains('developer-booking-tour-testing'));
  });

  test('booking selector searches required authoritative fields', () {
    final sql = File(
      'supabase/migrations/20261001050000_system_administrator_developer_testing.sql',
    ).readAsStringSync();
    expect(sql, contains("'#' || upper(substr(b.id::text, 1, 8))"));
    expect(sql, contains('t.full_name'));
    expect(sql, contains('tp.title'));
    expect(sql, contains('b.municipality'));
    expect(sql, contains('b.booking_status'));
  });

  test('state response includes recent System Administrator test actions', () {
    final sql = _migrationSql();
    expect(sql, contains("'recent_test_actions'"));
    expect(sql, contains("log.table_name = 'package_bookings'"));
    expect(sql, contains('log.actor_id'));
    expect(sql, contains('log.created_at'));
  });

  test('every mutation path writes booking-scoped audit history', () {
    final sql = _migrationSql();
    for (final action in const [
      'remaining_time_override',
      'overtime_triggered',
      'overtime_duration_override',
      'overtime_rate_override',
      'arrival_simulated',
      'departure_simulated',
      'stop_completed',
      'force_start',
      'force_complete',
      'reset_stay_timer_override',
      'reset_overtime_test',
    ]) {
      expect(sql, contains("'$action'"), reason: action);
    }
    expect(sql, contains("'booking_id', p_booking_id"));
    expect(sql, contains("'previous', v_previous"));
  });

  test('finalized test fee remains consistent with payments and reports', () {
    final sql = _migrationSql();
    expect(
      sql,
      contains('set remaining_balance=coalesce(remaining_balance,0)+v_amount'),
    );
    expect(sql, contains('public.booking_payment_requirements'));
    expect(
      sql,
      contains("sum(additional_amount) filter(where status='finalized')"),
    );
    expect(sql, contains("'total_remaining'"));
  });

  testWidgets('administrator can apply booking-only timing controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdministratorBookingTourTesting(
            bookingId: 'booking-1',
            gateway: gateway,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DEVELOPER / TESTING TOOLS'), findsOneWidget);
    expect(
      find.text(
        'Testing controls affect this booking only. Original package and fare configuration remain unchanged.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('60 min · Package configuration'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('developer-remaining-1')));
    await tester.pumpAndSettle();
    expect(gateway.lastMode, 'remaining');
    expect(gateway.lastMinutes, 1);
    expect(gateway.lastCustomRate, isNull);

    await tester.tap(find.byKey(const Key('developer-trigger-overtime')));
    await tester.pumpAndSettle();
    expect(gateway.lastMode, 'overtime');
    expect(gateway.lastMinutes, 0);

    await tester.ensureVisible(
      find.byKey(const Key('developer-apply-overtime')),
    );
    await tester.tap(find.text('45 min'));
    await tester.pump();
    expect(find.text('Billing Intervals'), findsWidgets);
    expect(find.text('PHP 90.00'), findsWidgets);

    await tester.tap(find.byKey(const Key('developer-apply-overtime')));
    await tester.pumpAndSettle();
    expect(gateway.lastMode, 'overtime');
    expect(gateway.lastMinutes, 45);
    expect(gateway.lastCustomRate, isNull);
  });

  testWidgets('locked session disables all mutation controls', (tester) async {
    final gateway = _FakeGateway(controlsEnabled: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdministratorBookingTourTesting(
            bookingId: 'booking-1',
            gateway: gateway,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Controls are locked'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('developer-remaining-1')),
          )
          .onPressed,
      isNull,
    );
  });

  test('migration enforces scope, audit, realtime and financial contracts', () {
    final sql = File(
      'supabase/migrations/20261008010000_booking_tour_developer_overrides.sql',
    ).readAsStringSync();
    final stayWidget = File(
      'lib/widgets/tour_stay_status_card.dart',
    ).readAsStringSync();

    expect(sql, contains('public.is_system_administrator()'));
    expect(sql, contains('ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED'));
    expect(sql, contains('SYSTEM_ADMINISTRATOR_REQUIRED'));
    expect(
      sql,
      contains(
        'revoke all on function public.administrator_apply_booking_timing_test',
      ),
    );
    expect(sql, contains('from public, anon'));
    expect(sql, contains("'remaining_time_override'"));
    expect(sql, contains("'overtime_triggered'"));
    expect(sql, contains("'arrival_simulated'"));
    expect(sql, contains("'force_complete'"));
    expect(sql, contains('public.tour_waiting_chargeable_intervals'));
    expect(sql, contains('test_deadline_override'));
    expect(sql, contains('test_rate_per_interval_override'));
    expect(sql, isNot(contains('update public.subtenant_fare_settings')));
    expect(sql, isNot(contains('estimated_stay_duration_minutes = p_minutes')));
    expect(sql, contains('public.booking_payment_requirements'));
    expect(sql, contains('public.finalize_package_booking_if_eligible'));
    expect(stayWidget, contains("table: 'booking_stop_waiting_charges'"));
    expect(stayWidget, contains("'get_booking_waiting_summary'"));
  });
}

String _migrationSql() => File(
  'supabase/migrations/20261008010000_booking_tour_developer_overrides.sql',
).readAsStringSync();

String _authorizationBlock() {
  final sql = _migrationSql();
  final start = sql.indexOf(
    'create or replace function public.system_administrator_booking_test_authorized',
  );
  final end = sql.indexOf(
    'create or replace function public.booking_test_session_active',
  );
  return sql.substring(start, end);
}

class _FakeGateway implements BookingDeveloperToolsGateway {
  _FakeGateway({this.controlsEnabled = true});

  final bool controlsEnabled;
  String? lastMode;
  int? lastMinutes;
  double? lastCustomRate;

  Map<String, dynamic> get state => {
    'booking_id': 'booking-1',
    'controls_enabled': controlsEnabled,
    'booking_status': 'on_tour',
    'tour_status': 'at_spot',
    'journey_state': 'at_stop',
    'current_stop_index': 0,
    'current_stop_id': 'stop-1',
    'current_stop_name': 'Cafe Supremo',
    'arrival_status': 'arrived',
    'departure_status': 'pending',
    'included_minutes': 60,
    'elapsed_minutes': 59,
    'effective_deadline': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 1))
        .toIso8601String(),
    'server_time': DateTime.now().toUtc().toIso8601String(),
    'remaining_minutes': 1,
    'overtime_minutes': 0,
    'overtime_active': false,
    'interval_minutes': 15,
    'configured_rate': 30,
    'custom_rate': null,
    'effective_rate': 30,
    'chargeable_intervals': 0,
    'additional_fee': 0,
    'booking_total': 1200,
    'override_active': lastMode != null,
    'override_kind': lastMode,
  };

  @override
  Future<Map<String, dynamic>> load(dynamic bookingId) async => state;

  @override
  Future<Map<String, dynamic>> applyTiming({
    required dynamic bookingId,
    required String mode,
    required int minutes,
    double? customRate,
  }) async {
    lastMode = mode;
    lastMinutes = minutes;
    lastCustomRate = customRate;
    return state;
  }

  @override
  Future<Map<String, dynamic>> progress({
    required dynamic bookingId,
    required String action,
  }) async => state;

  @override
  Future<Map<String, dynamic>> resetTiming({
    required dynamic bookingId,
    required String scope,
  }) async {
    lastMode = null;
    return state;
  }
}
