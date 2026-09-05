import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/models/booking_payment_prompt.dart';
import '../core/supabase/touristrike_models.dart';

class BookingPaymentSheet extends StatelessWidget {
  const BookingPaymentSheet({
    super.key,
    required this.state,
    required this.onPay,
  });
  final ValueListenable<BookingPaymentPrompt?> state;
  final VoidCallback onPay;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<BookingPaymentPrompt?>(
    valueListenable: state,
    builder: (context, value, _) {
      if (value == null) return const SizedBox.shrink();
      final booking = value.booking;
      final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
      final title = value.confirmed
          ? 'Payment Confirmed'
          : value.paymentRequired
          ? value.isRemaining
                ? 'Remaining Balance'
                : 'Payment Required'
          : value.awaitingReview
          ? 'Payment Under Review'
          : value.isRemaining
          ? 'Remaining Balance'
          : 'Waiting for Drivers';
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                value.confirmed
                    ? Icons.check_circle_outline
                    : Icons.payments_outlined,
                color: value.confirmed
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF2563EB),
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value.confirmed
                    ? value.isRemaining
                          ? 'Your remaining balance is confirmed. The convoy may proceed to drop-off.'
                          : 'Your downpayment is confirmed.'
                    : value.paymentRequired
                    ? value.cashPending
                          ? 'Cash selected. Each driver must confirm their received share before drop-off.'
                          : value.isRemaining
                          ? 'All tour destinations are completed. Settle the remaining balance before final drop-off.'
                          : 'Your drivers are confirmed. Pay your downpayment to prepare for your tour.'
                    : value.awaitingReview
                    ? 'Your existing payment is awaiting review.'
                    : value.isRemaining
                    ? 'Payment availability follows the current tour and payment status.'
                    : 'Payment will be available when all required drivers have accepted.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B), height: 1.4),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FB),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5EBF3)),
                ),
                child: Column(
                  children:
                      [
                            (
                              label: 'Booking',
                              value: dbString(
                                booking.packageRow?['title'],
                                fallback: 'Tour booking',
                              ),
                            ),
                            (
                              label: 'Drivers Confirmed',
                              value:
                                  '${booking.acceptedDriversCount} of ${booking.requiredDrivers}',
                            ),
                            (
                              label: 'Total Booking Amount',
                              value: money.format(booking.totalAmount),
                            ),
                            (
                              label: value.isRemaining
                                  ? 'Downpayment Paid'
                                  : 'Downpayment',
                              value: money.format(
                                value.isRemaining
                                    ? value.downpaymentPaid
                                    : booking.downpaymentAmount,
                              ),
                            ),
                            (
                              label: 'Remaining Balance',
                              value: money.format(booking.remainingBalance),
                            ),
                            (
                              label: 'Payment Method',
                              value: value.isRemaining
                                  ? value.cashPending
                                        ? 'Cash — driver confirmation required'
                                        : 'GCash via PayMongo / Cash'
                                  : 'GCash via PayMongo',
                            ),
                          ]
                          .map(
                            (row) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      row.label,
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      row.value,
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),
              const SizedBox(height: 20),
              if (value.cashPending)
                Text(
                  '${value.cashConfirmedCount} driver shares confirmed. Waiting for all ${booking.requiredDrivers} drivers.',
                ),
              if (value.paymentRequired && !value.cashPending)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: onPay,
                  child: Text(
                    'Pay ${money.format(value.amount)} ${value.isRemaining ? 'Remaining Balance' : 'Downpayment'}',
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(value.paymentRequired ? 'Pay later' : 'Close'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
