import 'package:flutter/material.dart';

import '../core/models/booking_feedback.dart';

class BookingFeedbackCard extends StatelessWidget {
  const BookingFeedbackCard({
    super.key,
    required this.feedback,
    required this.onReview,
    this.error,
  });

  final BookingFeedback? feedback;
  final VoidCallback onReview;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final value = feedback;
    final submitted = value?.complete == true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EBF3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Feedback',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
              if (submitted) const _SubmittedBadge(),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (value?.packageReview case final package?) ...[
            const SizedBox(height: 12),
            _RatingSummaryRow(label: 'Package Rating', review: package),
          ],
          if (value != null)
            for (final driver in value.drivers)
              if (driver['review'] is Map) ...[
                const SizedBox(height: 8),
                _RatingSummaryRow(
                  label: value.drivers.length == 1
                      ? 'Driver Rating'
                      : '${driver['name'] ?? 'Driver'} Rating',
                  review: driver['review'] as Map,
                ),
              ],
          if (submitted) ...[
            const SizedBox(height: 12),
            const Text(
              'Thank you for your feedback.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onReview,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2563EB),
                side: const BorderSide(color: Color(0xFFBFDBFE)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              icon: const Icon(Icons.star_outline_rounded, size: 19),
              label: Text(error != null ? 'Retry Feedback' : 'Rate This Tour'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubmittedBadge extends StatelessWidget {
  const _SubmittedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, color: Color(0xFF15803D), size: 14),
          SizedBox(width: 4),
          Text(
            'Submitted',
            style: TextStyle(
              color: Color(0xFF15803D),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingSummaryRow extends StatelessWidget {
  const _RatingSummaryRow({required this.label, required this.review});

  final String label;
  final Map review;

  @override
  Widget build(BuildContext context) {
    final rawRating = review['rating'];
    final rating = rawRating is num
        ? rawRating.toDouble()
        : double.tryParse(rawRating?.toString() ?? '') ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 18),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
