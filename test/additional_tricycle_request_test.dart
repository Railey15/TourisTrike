import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/additional_tricycle_request.dart';
import 'package:touristrike/core/models/booking_capacity.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';

void main() {
  test('optional request remains separate from passenger capacity', () {
    const capacity = 3;
    final request = AdditionalTricycleRequest(
      count: 1,
      reason: AdditionalTricycleReasons.extraLuggage,
    );
    request.validate();
    for (final (passengers, required) in [(1, 1), (3, 1), (4, 2), (7, 3)]) {
      expect(BookingCapacity.requiredTricycles(passengers, capacity), required);
      expect(required + request.count, required + 1);
    }
    expect(BookingCapacity.requiredTricycles(7, capacity), 3);
    expect(BookingCapacity.requiredTricycles(4, capacity), 2);
  });

  test('zero to three vehicles and a reason are allowed', () {
    expect(
      () => const AdditionalTricycleRequest(count: -1).validate(),
      throwsArgumentError,
    );
    expect(
      () => const AdditionalTricycleRequest(count: 4).validate(),
      throwsArgumentError,
    );
    expect(
      () => const AdditionalTricycleRequest(count: 1).validate(),
      throwsArgumentError,
    );
    expect(
      () => const AdditionalTricycleRequest(
        count: 1,
        reason: AdditionalTricycleReasons.other,
        explanation: '   ',
      ).validate(),
      throwsArgumentError,
    );
    expect(
      () => const AdditionalTricycleRequest(
        count: 1,
        reason: AdditionalTricycleReasons.other,
        explanation: 'Large instrument case',
      ).validate(),
      returnsNormally,
    );
    expect(
      () => const AdditionalTricycleRequest(count: 0).validate(),
      returnsNormally,
    );
    expect(
      () => const AdditionalTricycleRequest(
        count: 0,
        explanation: '   ',
      ).validate(),
      throwsArgumentError,
    );
    for (final count in [1, 2, 3]) {
      expect(
        () => AdditionalTricycleRequest(
          count: count,
          reason: AdditionalTricycleReasons.extraLuggage,
        ).validate(),
        returnsNormally,
      );
    }
    expect(
      () => const AdditionalTricycleRequest(count: 3).validate(),
      throwsArgumentError,
    );
  });

  test('booking row keeps required and optional counts separate', () {
    final booking = PackageBooking({
      'required_drivers': 3,
      'additional_tricycle_count': 2,
      'additional_tricycle_reason': AdditionalTricycleReasons.extraLuggage,
    });
    expect(booking.requiredDrivers, 3);
    expect(booking.additionalTricycleCount, 2);
    expect(
      booking.additionalTricycleReason,
      AdditionalTricycleReasons.extraLuggage,
    );
  });
}
