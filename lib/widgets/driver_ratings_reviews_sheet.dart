import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';

Future<void> showDriverRatingsReviewsSheet(
  BuildContext context, {
  required double averageRating,
  required int totalReviews,
  required Future<List<DriverReview>> reviews,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DriverRatingsReviewsSheet(
      averageRating: averageRating,
      totalReviews: totalReviews,
      reviews: reviews,
    ),
  );
}

class DriverRatingsReviewsSheet extends StatelessWidget {
  const DriverRatingsReviewsSheet({
    super.key,
    required this.averageRating,
    required this.totalReviews,
    required this.reviews,
  });

  final double averageRating;
  final int totalReviews;
  final Future<List<DriverReview>> reviews;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Material(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7DEE8),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ratings & Reviews',
                                style: TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Feedback from completed tours',
                                style: TextStyle(
                                  color: Color(0xFF8A98AB),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: _RatingSummary(
                      averageRating: averageRating,
                      totalReviews: totalReviews,
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE9EEF5)),
                  Expanded(
                    child: FutureBuilder<List<DriverReview>>(
                      future: reviews,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF2F7EFF),
                              strokeWidth: 3,
                            ),
                          );
                        }
                        if (snapshot.hasError) {
                          return const _ReviewsMessage(
                            icon: Icons.cloud_off_outlined,
                            title: 'Unable to load reviews',
                            message: 'Close this panel and try again.',
                          );
                        }
                        final items = snapshot.data ?? const <DriverReview>[];
                        if (items.isEmpty) {
                          return const _ReviewsMessage(
                            icon: Icons.rate_review_outlined,
                            title: 'No reviews yet',
                            message:
                                'Ratings from completed tours will appear here.',
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) =>
                              _DriverReviewTile(review: items[index]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({
    required this.averageRating,
    required this.totalReviews,
  });

  final double averageRating;
  final int totalReviews;

  @override
  Widget build(BuildContext context) {
    final hasReviews = totalReviews > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFBEB), Color(0xFFFFF7ED)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE7B2)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.star_rounded,
              color: Color(0xFFF59E0B),
              size: 29,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasReviews ? averageRating.toStringAsFixed(1) : 'New',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasReviews
                      ? '$totalReviews review${totalReviews == 1 ? '' : 's'}'
                      : 'No ratings submitted yet',
                  style: const TextStyle(
                    color: Color(0xFF8A5A16),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (hasReviews)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                5,
                (index) => Icon(
                  index < averageRating.round()
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: const Color(0xFFF59E0B),
                  size: 17,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DriverReviewTile extends StatelessWidget {
  const _DriverReviewTile({required this.review});

  final DriverReview review;

  @override
  Widget build(BuildContext context) {
    final date = review.createdAt;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  5,
                  (index) => Icon(
                    index < review.rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: const Color(0xFFF59E0B),
                    size: 16,
                  ),
                ),
              ),
              const Spacer(),
              if (date != null)
                Text(
                  DateFormat('MMM d, yyyy').format(date.toLocal()),
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            review.reviewText.trim().isEmpty
                ? 'Rating submitted without a written review.'
                : review.reviewText.trim(),
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          if (review.packageName.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.tour_outlined,
                  color: Color(0xFF2F7EFF),
                  size: 14,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    review.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF57739A),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewsMessage extends StatelessWidget {
  const _ReviewsMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: const Color(0xFF2F7EFF), size: 29),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8A98AB),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
