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
}
