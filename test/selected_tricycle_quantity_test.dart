import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/booking_capacity.dart';

void main() {
  test('adult minimum and maximum preserve separate seating validation', () {
    const minimums = <int, int>{1: 1, 2: 1, 3: 1, 4: 2, 6: 2, 9: 3};
    for (final entry in minimums.entries) {
      final adults = entry.key;
      final minimum = entry.value;
      expect(BookingCapacity.minimumForAdults(adults, 3), minimum);
      for (var selected = minimum; selected <= adults; selected++) {
        expect(() => BookingCapacity.validateSelectedTricycles(
          adults: adults, children: 0, tricycles: selected, capacity: 3,
        ), returnsNormally);
      }
      expect(() => BookingCapacity.validateSelectedTricycles(
        adults: adults, children: 0, tricycles: adults + 1, capacity: 3,
      ), throwsArgumentError);
    }
    expect(() => BookingCapacity.validateSelectedTricycles(
      adults: 1, children: 3, tricycles: 1, capacity: 3,
    ), throwsArgumentError);
    expect(() => BookingCapacity.validateSelectedTricycles(
      adults: 2, children: 2, tricycles: 2, capacity: 3,
    ), returnsNormally);
  });
}
