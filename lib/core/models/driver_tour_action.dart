import 'convoy_state.dart';

enum DriverTourSlideStage {
  confirmPickup('SLIDE TO CONFIRM PICKUP'),
  startTour('SLIDE TO START TOUR'),
  nextStop('SLIDE TO NEXT STOP'),
  leaveFinalStop('SLIDE TO LEAVE FINAL STOP'),
  dropOff('SLIDE TO DROP OFF'),
  completeTour('SLIDE TO COMPLETE TOUR');

  const DriverTourSlideStage(this.label);
  final String label;

  static DriverTourSlideStage? forJourney(
    ConvoyJourneyState state, {
    required int stopIndex,
    required int totalStops,
  }) => switch (state) {
    ConvoyJourneyState.atPickup => confirmPickup,
    ConvoyJourneyState.boarded => startTour,
    ConvoyJourneyState.atStop =>
      stopIndex >= totalStops - 1 ? leaveFinalStop : nextStop,
    ConvoyJourneyState.stopDone =>
      stopIndex >= totalStops - 1 ? dropOff : nextStop,
    ConvoyJourneyState.atDropoff => completeTour,
    _ => null,
  };
}

/// Amounts and eligibility come from the server; receipts never unlock travel.
class DriverTourPaymentGate {
  const DriverTourPaymentGate({
    required this.packageRemaining,
    required this.finalizedWaiting,
    required this.totalRemaining,
    required this.paymentSatisfied,
  });

  final double packageRemaining;
  final double finalizedWaiting;
  final double totalRemaining;
  final bool paymentSatisfied;

  bool get canDropOff => paymentSatisfied && totalRemaining == 0;

  factory DriverTourPaymentGate.fromMap(Map<String, dynamic> data) {
    double amount(String key) {
      final value = data[key];
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse('$value');
      if (parsed == null || !parsed.isFinite || parsed < 0) {
        throw FormatException('Invalid server payment amount: $key');
      }
      return parsed;
    }

    return DriverTourPaymentGate(
      packageRemaining: amount('package_remaining'),
      finalizedWaiting: amount('finalized_waiting'),
      totalRemaining: amount('total_remaining'),
      paymentSatisfied: data['payment_satisfied'] == true,
    );
  }
}
