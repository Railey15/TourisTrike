import 'package:flutter/material.dart';
import 'package:touristrike/core/policies/touristrike_notices.dart';

/// A snapshot of the validated booking. No scheduling or payment work happens
/// inside this sheet; the caller submits this same snapshot after agreement.
class BookingReviewSheet extends StatefulWidget {
  const BookingReviewSheet({
    super.key,
    required this.summary,
    required this.itinerary,
    required this.onViewPolicies,
    this.isSameDay = false,
  });

  final List<({String label, String value})> summary;
  final List<Widget> itinerary;
  final VoidCallback onViewPolicies;
  final bool isSameDay;

  @override
  State<BookingReviewSheet> createState() => _BookingReviewSheetState();
}

class _BookingReviewSheetState extends State<BookingReviewSheet> {
  bool _agreed = false;

  Widget _summarySection(
    String title,
    Iterable<({String label, String value})> rows,
  ) {
    final items = rows.toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4EBF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const Divider(height: 18),
          for (final row in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Text(
                      row.value,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontWeight: row.label == 'Total'
                            ? FontWeight.w900
                            : FontWeight.w700,
                        color: row.label == 'Total'
                            ? const Color(0xFF2A86FF)
                            : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2A86FF);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Review Your Booking',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isSameDay
                  ? 'Submit your request, then wait for all required drivers to accept before paying the 50% down payment.'
                  : 'Submit your request, then wait for all required drivers to accept. Your downpayment is due after your drivers are confirmed.',
              style: const TextStyle(color: Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _summarySection(
                      'Tour and locations',
                      widget.summary.where(
                        (row) => !const {
                          'Total',
                          'Downpayment Required',
                          'Remaining Balance',
                          'Payment Method',
                          'Included Driver Waiting',
                          'Additional Waiting',
                          'Waiting Rate Set By',
                          'If Time of Stay Is Exceeded',
                        }.contains(row.label),
                      ),
                    ),
                    _summarySection(
                      'Fare and payment',
                      widget.summary.where(
                        (row) => const {
                          'Total',
                          'Downpayment Required',
                          'Remaining Balance',
                          'Payment Method',
                        }.contains(row.label),
                      ),
                    ),
                    _summarySection(
                      'Time of Stay and waiting',
                      widget.summary.where(
                        (row) => const {
                          'Included Driver Waiting',
                          'Additional Waiting',
                          'Waiting Rate Set By',
                          'If Time of Stay Is Exceeded',
                        }.contains(row.label),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tour Itinerary',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...widget.itinerary,
                    TextButton(
                      onPressed: widget.onViewPolicies,
                      child: const Text(
                        'TourisTrike Booking Terms and Conditions',
                      ),
                    ),
                    const Text(
                      'Cancellation Policy',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      cancellationPolicySummary,
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: primary,
                      value: _agreed,
                      onChanged: (value) =>
                          setState(() => _agreed = value == true),
                      title: const Text(
                        'I have read and agree to the TourisTrike Booking Terms and Conditions and acknowledge the applicable cancellation and payment policies.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _agreed ? () => Navigator.pop(context, true) : null,
                child: const Text('Confirm & Submit Booking'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back to booking'),
            ),
          ],
        ),
      ),
    );
  }
}
