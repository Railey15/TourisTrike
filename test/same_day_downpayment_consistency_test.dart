import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(
  path,
).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

void main() {
  late String migration;
  late String bookingScreen;
  late String touristTracking;
  late String driverTracking;
  late String repository;

  setUpAll(() {
    migration = read(
      'supabase/migrations/20260831010000_transaction_lifecycle_consistency.sql',
    );
    bookingScreen = read('lib/screens/tourist/package_booking_screen.dart');
    touristTracking = read(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    );
    driverTracking = read(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    );
    repository = read('lib/core/supabase/touristrike_repository.dart');
  });

  test('same-day and advance bookings use the same 50/50 GCash split', () {
    expect(
      migration,
      contains("raise exception 'PACKAGE_BOOKING_REQUIRES_GCASH'"),
    );
    expect(
      migration,
      contains('new.downpayment_amount <> round(new.total_amount * 0.50, 2)'),
    );
    expect(
      bookingScreen,
      contains('return (_totalPrice(package) * 50).roundToDouble() / 100'),
    );
    expect(bookingScreen, isNot(contains('Cash on Pick-up')));
    expect(bookingScreen, isNot(contains("if (_isSameDay) {\n      return 0")));
  });

  test('one server payment predicate gates every booking start', () {
    expect(migration, contains('is_booking_downpayment_confirmed'));
    expect(migration, contains("pr.payment_stage in ('down_payment', 'full')"));
    expect(migration, contains("pr.status = 'confirmed'"));
    expect(
      migration,
      contains(
        'if not v_debug_bypass\n'
        '       and not public.is_booking_downpayment_confirmed(p_booking_id)',
      ),
    );
    final startGate = migration
        .split(
          "if v_current = 'assigned' and p_target_state = 'en_route_pickup'",
        )[2]
        .split("if v_current = 'at_dropoff'")[0];
    expect(startGate, isNot(contains('booking_type')));
  });

  test('both booking types prepare down_payment records via one PayMongo RPC', () {
    final preparation = migration
        .split(
          'create or replace function public.prepare_paymongo_payment_authenticated_impl',
        )[1]
        .split(
          'create or replace function public.prepare_group_cash_remaining_balance',
        )[0];
    expect(preparation, contains("if v_stage = 'down_payment' then"));
    expect(preparation, contains('v_amount := v_booking.downpayment_amount'));
    expect(preparation, contains('insert into public.payment_records'));
    expect(preparation, isNot(contains("booking_type, 'same_day'")));
    expect(repository, contains("'paymongo-create-payment'"));
    expect(repository, contains("'payment_stage': paymentStage"));
  });

  test('tourist and driver UIs do not gate downpayment by booking type', () {
    final paymentUi = touristTracking
        .split('// PAYMENTS')[1]
        .split('// BOOKING SUMMARY')[0];
    expect(paymentUi, contains('onPay: _showPaymentPrompt'));
    expect(
      touristTracking,
      contains("await _openPayMongoCheckout(stage: 'down_payment')"),
    );
    expect(paymentUi, isNot(contains("bookingType == 'advanced'")));

    final driverGate = driverTracking
        .split('String? get _serverGateNotice')[1]
        .split('void _syncScheduleGateTimer')[0];
    expect(driverGate, contains("_hasConfirmedPayment('down_payment'"));
    expect(driverGate, isNot(contains("booking.bookingType == 'advanced'")));
  });

  test('debug bypass is temporary, allowlisted, and never confirms payment', () {
    expect(
      repository,
      contains('kDebugMode && await fetchDeveloperTestBookingMode(bookingId)'),
    );
    expect(
      migration,
      contains(
        "set_config('touristrike.debug_progression_bypass', 'true', true)",
      ),
    );
    expect(
      migration,
      contains("current_setting('touristrike.debug_progression_bypass', true)"),
    );
    final debugWrapper = migration
        .split(
          'create or replace function public.debug_advance_driver_journey_state',
        )[1]
        .split('create or replace function public.complete_package_tour')[0];
    expect(debugWrapper, contains('debug_test_driver_assignment'));
    expect(debugWrapper, isNot(contains('update public.payment_records')));
  });
}
