abstract final class ItineraryStayOptions {
  static const minutes = <int>[15, 30, 45, 60, 90, 120, 150, 180];

  static int nearest(int value) {
    var best = minutes.first;
    for (final option in minutes.skip(1)) {
      if ((option - value).abs() < (best - value).abs()) best = option;
    }
    return best;
  }

  static String label(int value) {
    if (value < 60) return '$value minutes';
    final hours = value ~/ 60;
    final remaining = value % 60;
    return '$hours hour${hours == 1 ? '' : 's'}'
        '${remaining == 0 ? '' : ' $remaining minutes'}';
  }
}
