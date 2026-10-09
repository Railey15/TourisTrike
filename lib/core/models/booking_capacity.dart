abstract final class BookingCapacity {
  static int requiredTricycles(int passengers, int capacity) {
    if (passengers < 1 || capacity < 1) {
      throw ArgumentError('Invalid passenger count or tricycle capacity.');
    }
    return (passengers + capacity - 1) ~/ capacity;
  }

  static void validate(int passengers, int tricycles, int capacity) {
    if (tricycles != requiredTricycles(passengers, capacity)) {
      throw ArgumentError('Invalid passenger/tricycle quantity.');
    }
  }

  static int minimumForAdults(int adults, int capacity) =>
      requiredTricycles(adults, capacity);

  static void validateSelectedTricycles({
    required int adults,
    required int children,
    required int tricycles,
    required int capacity,
  }) {
    if (adults < 1 ||
        children < 0 ||
        capacity < 1 ||
        tricycles < minimumForAdults(adults, capacity) ||
        tricycles > adults ||
        adults + children > tricycles * capacity) {
      throw ArgumentError('Invalid passenger/tricycle quantity.');
    }
  }
}
