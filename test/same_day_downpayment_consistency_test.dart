import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/booking_payment_prompt.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261009010000_payment_history_same_day_driver_cleanup.sql',
  ).readAsStringSync();
  final bookingScreen = File(
    'lib/screens/tourist/package_booking_screen.dart',
  ).readAsStringSync();

  test('same-day booking requires the same 50% downpayment at creation', () {
    expect(bookingScreen, isNot(contains('if (_isSameDay) return 0;')));
    expect(bookingScreen, contains('_totalPrice(package) * 50'));
    expect(
      migration,
      contains('new.downpayment_amount <> round(new.total_amount * 0.50, 2)'),
    );
  });

  test('server journey gate has no same-day payment bypass', () {
    final gateStart = migration.indexOf(
      'create or replace function public.is_booking_downpayment_confirmed',
    );
    final gateEnd = migration.indexOf(
      'revoke all on function public.is_booking_downpayment_confirmed',
    );
    final gate = migration.substring(gateStart, gateEnd);
    expect(gate, isNot(contains("booking_type,''))='same_day'")));
    expect(gate, contains("pr.status = 'confirmed'"));
  });

  test('same-day payment prompt opens only after the full roster accepts', () {
    final booking = PackageBooking({
      'id': 'same-day',
      'booking_type': 'same_day',
      'booking_status': 'accepted',
      'status': 'confirmed',
      'required_drivers': 1,
      'accepted_drivers_count': 1,
      'downpayment_amount': 375,
      'remaining_balance': 375,
    });
    final prompt = BookingPaymentPrompt.fromRecords(
      booking,
      const [],
      requirement: const {'status': 'required', 'amount': 375},
    );
    expect(prompt.paymentRequired, isTrue);

    final waiting = PackageBooking({
      ...booking.row,
      'accepted_drivers_count': 0,
    });
    expect(
      BookingPaymentPrompt.fromRecords(
        waiting,
        const [],
        requirement: null,
      ).paymentRequired,
      isFalse,
    );
  });
}
