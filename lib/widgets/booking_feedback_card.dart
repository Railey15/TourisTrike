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
    Widget review(String title, Map review) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title — ${review['rating']}/5',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if ((review['review_text']?.toString() ?? '').isNotEmpty)
            Text(review['review_text'].toString()),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Feedback for This Booking',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            if (error != null) Text(error!),
            if (value?.packageReview case final package?)
              review('Package', package),
            if (value != null)
              for (final driver in value.drivers)
                if (driver['review'] is Map)
                  review(driver['name'].toString(), driver['review'] as Map),
            if (value?.complete == true)
              const Text(
                'Feedback submitted. Thank you!',
                style: TextStyle(color: Color(0xFF16A34A)),
              )
            else
              TextButton(
                onPressed: onReview,
                child: Text(
                  error != null ? 'Retry feedback' : 'Rate this booking',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
