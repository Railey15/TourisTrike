import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';

class BookingCancellationResultScreen extends StatelessWidget {
  const BookingCancellationResultScreen({
    super.key,
    required this.result,
    required this.packageTitle,
    required this.travelDate,
  });

  final BookingCancellationResult result;
  final String packageTitle;
  final DateTime? travelDate;

  String get _refundText {
    final eligibility = result.eligibility;
    if (eligibility.amountPaid <= 0) return 'No payment was made';
    if (eligibility.refundableAmount <= 0) {
      return 'Non-refundable due to late cancellation';
    }
    final amount = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
    ).format(eligibility.refundableAmount);
    return '$amount refund pending';
  }

  @override
  Widget build(BuildContext context) {
    final cancelled = result.cancelledAt ?? DateTime.now();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5EBF3)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F0F172A),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF2F2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.event_busy_rounded,
                        color: Color(0xFFDC2626),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Booking Cancelled',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Your booking has been cancelled successfully.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 22),
                    _ResultRow(label: 'Booking', value: packageTitle),
                    _ResultRow(
                      label: 'Tour date',
                      value:
                          (result.eligibility.scheduledAt ?? travelDate) == null
                          ? 'Schedule unavailable'
                          : DateFormat('MMM d, yyyy • h:mm a').format(
                              result.eligibility.scheduledAt ?? travelDate!,
                            ),
                    ),
                    _ResultRow(label: 'Reason', value: result.reason),
                    _ResultRow(
                      label: 'Cancelled',
                      value: DateFormat(
                        'MMM d, yyyy • h:mm a',
                      ).format(cancelled),
                    ),
                    _ResultRow(label: 'Refund', value: _refundText),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Back to Bookings'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFE5EBF3))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(label, style: const TextStyle(color: Color(0xFF64748B))),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
