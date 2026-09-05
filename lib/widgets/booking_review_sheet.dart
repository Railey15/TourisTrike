import 'package:flutter/material.dart';

/// A snapshot of the validated booking. No scheduling or payment work happens
/// inside this sheet; the caller submits this same snapshot after agreement.
class BookingReviewSheet extends StatefulWidget {
  const BookingReviewSheet({
    super.key,
    required this.summary,
    required this.itinerary,
    required this.onViewPolicies,
  });

  final List<({String label, String value})> summary;
  final List<Widget> itinerary;
  final VoidCallback onViewPolicies;

  @override
  State<BookingReviewSheet> createState() => _BookingReviewSheetState();
}

class _BookingReviewSheetState extends State<BookingReviewSheet> {
  bool _agreed = false;

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
            const Text(
              'Submit your request, then wait for all required drivers to accept. Your downpayment is due after your drivers are confirmed.',
              style: TextStyle(color: Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FB),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE4EBF4)),
                      ),
                      child: Column(
                        children: widget.summary
                            .map(
                              (row) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
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
                                      flex: 2,
                                      child: Text(
                                        row.value,
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
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
                      child: const Text('View TourisTrike booking policies'),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: primary,
                      value: _agreed,
                      onChanged: (value) =>
                          setState(() => _agreed = value == true),
                      title: const Text(
                        'I understand and agree to the TourisTrike booking, payment, cancellation, and trip policies.',
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
