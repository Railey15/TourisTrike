abstract final class BookingCapacity {
  static int minimumTricycles(int passengers) =>
      ((passengers / 3).ceil()).clamp(1, 99);

  static int normalize(int passengers, int selected) =>
      passengers <= 1 ? 1 : selected.clamp(minimumTricycles(passengers), 99);

  static bool canAdd(int passengers, int selected) =>
      passengers >= 2 && selected < 99;

  static void validate(int passengers, int tricycles) {
    if (passengers < 1 ||
        tricycles < minimumTricycles(passengers) ||
        tricycles > 99 ||
        (passengers == 1 && tricycles != 1)) {
      throw ArgumentError('Invalid passenger/tricycle quantity.');
    }
  }
}
