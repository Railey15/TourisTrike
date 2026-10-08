import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/booking_payment_prompt.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';

void main() {
  final migration = File(
    'supabase/migration_hold/20260930020000_booking_notices_cancellation_policy.sql',
  ).readAsStringSync();
  final bookingScreen = File(
    'lib/screens/tourist/package_booking_screen.dart',
  ).readAsStringSync();

  test('same-day booking asks for no downpayment at creation', () {
    expect(bookingScreen, contains('if (_isSameDay) return 0;'));
    expect(migration, contains("''same_day'' then 0"));
  });

  test('server journey gate treats same-day downpayment as satisfied', () {
    expect(
      migration,
      contains("lower(coalesce(b.booking_type,''))='same_day'"),
    );
    expect(migration, contains('return true;'));
  });

  test('same-day booking with zero downpayment shows no payment prompt', () {
    final booking = PackageBooking({
      'id': 'same-day',
      'booking_type': 'same_day',
      'booking_status': 'accepted',
      'status': 'confirmed',
      'required_drivers': 1,
      'accepted_drivers_count': 1,
      'downpayment_amount': 0,
      'remaining_balance': 750,
    });
    final prompt = BookingPaymentPrompt.fromRecords(
      booking,
      const [],
      requirement: null,
    );
    expect(prompt.paymentRequired, isFalse);
  });
}
