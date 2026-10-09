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

  static int minimumForParticipants({
    required int adults,
    required int children,
    required int capacity,
  }) {
    validateParticipants(adults: adults, children: children);
    return requiredTricycles(adults + children, capacity);
  }

  static int maximumSelectableTricycles({
    required int adults,
    required int children,
  }) {
    validateParticipants(adults: adults, children: children);
    return adults + children;
  }

  static void validateParticipants({
    required int adults,
    required int children,
  }) {
    if (children > 0 && adults == 0) {
      throw ArgumentError(
        'Children must be accompanied by at least one adult.',
      );
    }
    if (adults < 1 || children < 0) {
      throw ArgumentError('Invalid passenger quantity.');
    }
  }

  static void validateSelectedTricycles({
    required int adults,
    required int children,
    required int tricycles,
    required int capacity,
  }) {
    validateParticipants(adults: adults, children: children);
    final passengers = adults + children;
    if (capacity < 1 ||
        tricycles < requiredTricycles(passengers, capacity) ||
        tricycles > passengers) {
      throw ArgumentError('Invalid passenger/tricycle quantity.');
    }
  }
}
