abstract final class AdditionalTricycleReasons {
  static const extraLuggage = 'extra_luggage';
  static const accessibilityNeeds = 'accessibility_needs';
  static const additionalSpace = 'additional_space';
  static const other = 'other';

  static const labels = <String, String>{
    extraLuggage: 'Extra luggage',
    accessibilityNeeds: 'Accessibility needs',
    additionalSpace: 'Need additional space',
    other: 'Other',
  };
}

class AdditionalTricycleRequest {
  const AdditionalTricycleRequest({
    required this.count,
    this.reason,
    this.explanation,
  });

  final int count;
  final String? reason;
  final String? explanation;

  bool get isRequested => count > 0;
  String get reasonLabel => AdditionalTricycleReasons.labels[reason] ?? '';

  void validate() {
    final detail = explanation?.trim() ?? '';
    if (count < 0 || count > 3) {
      throw ArgumentError('Up to three additional tricycles may be requested.');
    }
    if (count == 0) {
      if (reason != null || explanation != null) {
        throw ArgumentError('A removed request cannot keep a reason.');
      }
      return;
    }
    if (!AdditionalTricycleReasons.labels.containsKey(reason)) {
      throw ArgumentError('Select a reason for the additional tricycle.');
    }
    if (reason == AdditionalTricycleReasons.other) {
      if (detail.length < 5 || detail.length > 200) {
        throw ArgumentError('Explain the request in 5 to 200 characters.');
      }
    } else if (detail.isNotEmpty) {
      throw ArgumentError('Only Other accepts an explanation.');
    }
  }
}
