import 'package:touristrike/core/supabase/touristrike_models.dart';

const packageCancellationReasons = <String, String>{
  'change_of_plans': 'Change of Plans',
  'emergency': 'Emergency',
  'health_emergency': 'Health Emergency',
  'weather_condition': 'Weather Condition',
  'weather_concern': 'Weather Concern',
  'tourist_unavailable': 'Tourist Unavailable',
  'driver_unavailable': 'Driver Unavailable',
  'duplicate_booking': 'Duplicate Booking',
  'payment_issue': 'Payment Issue',
  'schedule_conflict': 'Schedule Conflict',
  'incorrect_booking': 'Incorrect Booking',
  'transportation_issue': 'Transportation Issue',
  'no_replacement_driver': 'No Replacement Driver Available',
  'driver_withdrawal': 'Driver Unavailable',
  'verified_driver_no_show': 'Driver Did Not Arrive',
  'verified_tourist_no_show': 'Tourist Did Not Arrive',
  'other': 'Other',
};

String cancellationReasonLabel(
  String? value, {
  String fallback = 'Not specified',
}) {
  final normalized = value?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) return fallback;
  final mapped = packageCancellationReasons[normalized];
  if (mapped != null) return mapped;

  return normalized
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

class CancellationRefundDisplay {
  const CancellationRefundDisplay({required this.amount, required this.status});

  final double amount;
  final String status;

  factory CancellationRefundDisplay.fromBooking({
    required PackageBooking? booking,
    required Iterable<PaymentRecord> payments,
    required Iterable<RefundRequest> refunds,
  }) {
    final hasRecordedPayment = payments.any(
      (payment) =>
          payment.isConfirmed ||
          payment.isRefundRelated ||
          payment.paidAt != null ||
          payment.payeeConfirmedAt != null,
    );
    final refundList = refunds.toList(growable: false);

    if (!hasRecordedPayment &&
        refundList.isEmpty &&
        (booking?.refundableAmount ?? 0) <= 0) {
      return const CancellationRefundDisplay(
        amount: 0,
        status: 'No payment was made.',
      );
    }

    final amount = refundList.isNotEmpty
        ? refundList.fold<double>(0, (total, refund) => total + refund.amount)
        : booking?.refundableAmount ?? 0;
    final statuses = refundList
        .map((refund) => refund.status.trim().toLowerCase())
        .toSet();

    if (statuses.any(
      (status) => const {'pending', 'approved', 'processing'}.contains(status),
    )) {
      return CancellationRefundDisplay(
        amount: amount,
        status: 'Refund Processing',
      );
    }
    if (statuses.isNotEmpty &&
        statuses.every(
          (status) => const {'completed', 'refunded'}.contains(status),
        )) {
      return CancellationRefundDisplay(amount: amount, status: 'Refunded');
    }
    if (statuses.any(
      (status) => const {'failed', 'rejected'}.contains(status),
    )) {
      return CancellationRefundDisplay(amount: amount, status: 'Refund Failed');
    }

    final bookingStatus = booking?.refundStatus.trim().toLowerCase() ?? '';
    final status = switch (bookingStatus) {
      'completed' || 'refunded' => 'Refunded',
      'pending' || 'approved' || 'processing' => 'Refund Processing',
      'review_required' => 'Refund Under Review',
      'not_eligible' => 'Refund Not Eligible',
      _ when amount > 0 => 'Refund Processing',
      _ => 'Non-refundable',
    };
    return CancellationRefundDisplay(amount: amount, status: status);
  }

  factory CancellationRefundDisplay.fromResult(
    BookingCancellationResult result,
  ) {
    final eligibility = result.eligibility;
    if (eligibility.amountPaid <= 0) {
      return const CancellationRefundDisplay(
        amount: 0,
        status: 'No payment was made.',
      );
    }
    final status = switch (result.refundStatus.trim().toLowerCase()) {
      'completed' || 'refunded' => 'Refunded',
      'pending' || 'approved' || 'processing' => 'Refund Processing',
      'review_required' => 'Refund Under Review',
      'not_eligible' => 'Refund Not Eligible',
      _ when eligibility.refundableAmount > 0 => 'Refund Processing',
      _ => 'Non-refundable',
    };
    return CancellationRefundDisplay(
      amount: eligibility.refundableAmount,
      status: status,
    );
  }
}
