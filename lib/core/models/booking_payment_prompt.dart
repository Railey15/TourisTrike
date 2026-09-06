import '../supabase/touristrike_models.dart';

class BookingPaymentPrompt {
  const BookingPaymentPrompt({
    required this.booking,
    required this.confirmed,
    required this.awaitingReview,
    this.stage = 'down_payment',
    this.itineraryComplete = false,
    this.dropoffStarted = false,
    this.downpaymentPaid = 0,
    this.cashPending = false,
    this.cashConfirmedCount = 0,
  });
  final PackageBooking booking;
  final bool confirmed;
  final bool awaitingReview;
  final String stage;
  final bool itineraryComplete;
  final bool dropoffStarted;
  final double downpaymentPaid;
  final bool cashPending;
  final int cashConfirmedCount;
  bool get isRemaining => stage == 'remaining_balance';
  double get amount =>
      isRemaining ? booking.remainingBalance : booking.downpaymentAmount;

  factory BookingPaymentPrompt.fromRecords(
    PackageBooking booking,
    List<PaymentRecord> records, {
    String stage = 'down_payment',
    bool itineraryComplete = false,
    bool dropoffStarted = false,
    List<PaymentAllocation> allocations = const [],
  }) {
    final downpayments = records.where(
      (p) => p.paymentStage == stage || p.paymentStage == 'full',
    );
    return BookingPaymentPrompt(
      booking: booking,
      stage: stage,
      itineraryComplete: itineraryComplete,
      dropoffStarted: dropoffStarted,
      downpaymentPaid: records
          .where((p) => p.isConfirmed && p.paymentStage == 'down_payment')
          .fold(0.0, (sum, p) => sum + p.amount),
      cashPending: downpayments.any(
        (p) => p.isGroupCash && p.status == 'pending_confirmation',
      ),
      cashConfirmedCount: allocations
          .where((a) => a.paymentStage == stage && a.isCashConfirmed)
          .length,
      confirmed: downpayments.any(
        (p) =>
            p.isConfirmed &&
            p.amount >=
                (p.paymentStage == 'full'
                    ? booking.totalAmount
                    : stage == 'remaining_balance'
                    ? booking.remainingBalance
                    : booking.downpaymentAmount),
      ),
      awaitingReview: downpayments.any(
        (p) =>
            p.status == 'disputed' ||
            (p.status == 'pending_confirmation' && !p.isPayMongo),
      ),
    );
  }

  bool get rosterComplete =>
      booking.requiredDrivers > 0 &&
      booking.acceptedDriversCount >= booking.requiredDrivers;
  bool get paymentRequired =>
      rosterComplete &&
      !confirmed &&
      (!awaitingReview || cashPending) &&
      amount > 0 &&
      (isRemaining
          // Test progression (or an older trip) may already be at drop-off.
          // Physical progress does not settle an outstanding payment.
          ? itineraryComplete
          : const {
              'accepted',
              'confirmed',
            }.contains(booking.bookingStatus.toLowerCase())) &&
      !const {
        'cancelled',
        'completed',
        'expired',
        'rejected',
      }.contains(booking.status.toLowerCase()) &&
      !const {
        'cancelled',
        'completed',
        'done',
        'rejected',
        'expired',
      }.contains(booking.bookingStatus.toLowerCase());
}

/// Consumes one automatic presentation per complete roster phase. A user may
/// reopen manually; rebuilds, refreshes and checkout retries do not reset it.
class BookingPaymentPromptGate {
  bool _handled = false;
  void markHandled() => _handled = true;
  void observe(BookingPaymentPrompt state) {
    if (!state.rosterComplete) _handled = false;
  }

  bool shouldPresent(BookingPaymentPrompt state) {
    observe(state);
    if (!state.paymentRequired || _handled) return false;
    _handled = true;
    return true;
  }
}
