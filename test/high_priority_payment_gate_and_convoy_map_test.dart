import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(
  path,
).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

List<int> splitCentavos(int total, int drivers) {
  final base = total ~/ drivers;
  final remainder = total % drivers;
  return List.generate(drivers, (index) => base + (index < remainder ? 1 : 0));
}

void main() {
  late String migration;
  late String cashMigration;
  late String touristTracking;
  late String driverTracking;
  late String repository;

  setUpAll(() {
    migration = read(
      'supabase/migrations/20260831010000_transaction_lifecycle_consistency.sql',
    );
    cashMigration = read(
      'supabase/migrations/20260827060000_connect_paymongo_and_group_cash.sql',
    );
    touristTracking = read(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    );
    driverTracking = read(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    );
    repository = read('lib/core/supabase/touristrike_repository.dart');
  });

  test('one authoritative roster keeps completed assignments payable', () {
    expect(migration, contains('required_booking_driver_roster'));
    expect(migration, contains("bd.status in ('accepted', 'completed')"));
    expect(migration, contains('is_booking_driver_roster_full'));
    expect(migration, contains('prepare_paymongo_payment_authenticated_impl'));
    expect(migration, contains('from public.required_booking_driver_roster'));
  });

  test('remaining GCash and cash retain exact dynamic N-way allocation', () {
    for (final drivers in [1, 2, 3]) {
      final shares = splitCentavos(360000, drivers);
      expect(shares.length, drivers);
      expect(shares.reduce((a, b) => a + b), 360000);
    }
    expect(migration, contains('compute_equal_split_centavos'));
    expect(migration, contains("split.basis_points, 'PHP', 'held'"));
    expect(migration, contains("split.basis_points, 'PHP', 'awaiting_cash'"));
  });

  test('cash stays pending until every assignment allocation confirms', () {
    expect(cashMigration, contains('confirm_group_cash_share'));
    expect(cashMigration, contains("v_allocation.status = 'cash_confirmed'"));
    expect(cashMigration, contains("status <> 'cash_confirmed'"));
    expect(cashMigration, contains("set status = 'satisfied'"));
    expect(touristTracking, contains('drivers confirmed'));
    expect(driverTracking, contains('Drop-off stays locked until everyone'));
  });

  test('last stop enters a backend-enforced pre-dropoff payment gate', () {
    expect(migration, contains("then 'awaiting_remaining_payment'"));
    expect(
      migration,
      contains(
        "v_current = 'stop_done' and p_target_state = 'en_route_dropoff'",
      ),
    );
    expect(
      migration,
      contains("raise exception 'REMAINING_BALANCE_NOT_CONFIRMED'"),
    );
    expect(migration, contains("set remaining_balance = 0"));
    expect(driverTracking, contains('Waiting for remaining payment'));
    expect(touristTracking, contains('TOUR ITINERARY COMPLETED'));
  });

  test('remaining payment cannot be started before itinerary completion', () {
    expect(migration, contains('is_booking_itinerary_complete'));
    expect(migration, contains("raise exception 'REMAINING_PAYMENT_NOT_DUE'"));
    expect(touristTracking, contains('itineraryComplete ||'));
  });

  test('test mode preserves payment ordering', () {
    expect(
      migration,
      contains('Test Mode intentionally does not bypass transaction/payment'),
    );
    expect(
      migration,
      contains("raise exception 'REMAINING_BALANCE_NOT_CONFIRMED'"),
    );
    expect(driverTracking, contains('Mark Remaining Balance Paid'));
    expect(repository, contains('debug_mark_remaining_balance_paid'));
  });

  test('tourist and driver maps keep unique markers and routes per driver', () {
    for (final source in [touristTracking, driverTracking]) {
      expect(source, contains("MarkerId('driver_\${driver.driverId}')"));
      expect(
        source,
        contains("PolylineId('driver_route_\${result.driverId}')"),
      );
      expect(source, contains("table: 'driver_live_locations'"));
    }
    expect(driverTracking, isNot(contains("MarkerId('convoy_")));
  });

  test('completed assignment does not remove convoy map membership', () {
    expect(
      repository,
      contains("bd.status == 'accepted' || bd.status == 'completed'"),
    );
    expect(touristTracking, isNot(contains('if (!_isTourCompleted()) {')));
    expect(
      driverTracking,
      isNot(contains('_isBookingClosed ? const <ConvoyDriverSnapshot>[]')),
    );
  });
}
