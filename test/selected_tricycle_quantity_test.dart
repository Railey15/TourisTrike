import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/booking_capacity.dart';

void main() {
  const capacity = 3;

  test('minimum tricycles count adults and children', () {
    expect(
      BookingCapacity.minimumForParticipants(
        adults: 1,
        children: 2,
        capacity: capacity,
      ),
      1,
    );
    expect(
      BookingCapacity.minimumForParticipants(
        adults: 3,
        children: 3,
        capacity: capacity,
      ),
      2,
    );
    expect(
      BookingCapacity.minimumForParticipants(
        adults: 2,
        children: 0,
        capacity: capacity,
      ),
      1,
    );
  });

  test('children require one adult but not one adult per child', () {
    expect(
      () => BookingCapacity.validateSelectedTricycles(
        adults: 0,
        children: 2,
        tricycles: 1,
        capacity: capacity,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          'Children must be accompanied by at least one adult.',
        ),
      ),
    );
    expect(
      () => BookingCapacity.validateSelectedTricycles(
        adults: 1,
        children: 2,
        tricycles: 1,
        capacity: capacity,
      ),
      returnsNormally,
    );
  });

  test('selection may increase but cannot drop below passenger minimum', () {
    for (final selected in [2, 3, 4, 5, 6]) {
      expect(
        () => BookingCapacity.validateSelectedTricycles(
          adults: 3,
          children: 3,
          tricycles: selected,
          capacity: capacity,
        ),
        returnsNormally,
      );
    }
    expect(
      () => BookingCapacity.validateSelectedTricycles(
        adults: 3,
        children: 3,
        tricycles: 1,
        capacity: capacity,
      ),
      throwsArgumentError,
    );
    expect(
      () => BookingCapacity.validateSelectedTricycles(
        adults: 3,
        children: 3,
        tricycles: 7,
        capacity: capacity,
      ),
      throwsArgumentError,
    );
  });
}
