import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class FeedbackTrendsScreen extends StatefulWidget {
  const FeedbackTrendsScreen({super.key});

  @override
  State<FeedbackTrendsScreen> createState() => _FeedbackTrendsScreenState();
}

class _FeedbackTrendsScreenState extends State<FeedbackTrendsScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();

  late Future<FeedbackTrendData> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchFeedbackTrends();
  }

  void _reload() {
    setState(() => _future = _service.fetchFeedbackTrends());
  }

  @override
  Widget build(BuildContext context) {
    return ProvincialAdminShell(
      current: ProvincialAdminDestination.feedback,
      title: 'Feedback',
      subtitle: 'Review tourist feedback trends and low-rated experiences.',
      
      child: FutureBuilder<FeedbackTrendData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AdminLoadingView();
          }

          if (snapshot.hasError) {
            return AdminErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final data = snapshot.data!;
          final feedback = data.feedback;
          final lowRated = data.lowRated;
          final averageRating = data.averageRating;
          final totalFeedback = feedback.length;
          final driverFeedback = feedback.where((item) {
            final source = item.source.toLowerCase();
            return source.contains('ride') ||
                source.contains('driver') ||
                adminId(item.raw['driver_id']).isNotEmpty;
          }).length;

          final reviewsByCity = _countByCity(feedback);
          final ratingDistribution = _ratingDistribution(feedback);

          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1150;

              if (!wide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                  child: _MobileFeedbackLayout(
                    data: data,
                    averageRating: averageRating,
                    totalFeedback: totalFeedback,
                    lowRated: lowRated,
                    driverFeedback: driverFeedback,
                    reviewsByCity: reviewsByCity,
                    ratingDistribution: ratingDistribution,
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
                child: _DesktopFeedbackLayout(
                  height: (constraints.maxHeight - 28).clamp(
                    0.0,
                    double.infinity,
                  ),
                  data: data,
                  averageRating: averageRating,
                  totalFeedback: totalFeedback,
                  lowRated: lowRated,
                  driverFeedback: driverFeedback,
                  reviewsByCity: reviewsByCity,
                  ratingDistribution: ratingDistribution,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Map<String, int> _countByCity(List<ProvinceFeedback> feedback) {
    final counts = <String, int>{};

    for (final item in feedback) {
      final city = item.city.trim().isEmpty ? 'Unassigned' : item.city;
      counts.update(city, (value) => value + 1, ifAbsent: () => 1);
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {for (final entry in entries) entry.key: entry.value};
  }

  Map<int, int> _ratingDistribution(List<ProvinceFeedback> feedback) {
    final counts = <int, int>{5: 0, 4: 0, 3: 0, 2: 0, 1: 0};

    for (final item in feedback) {
      if (item.rating <= 0) continue;
      final rounded = item.rating.round().clamp(1, 5).toInt();
      counts[rounded] = (counts[rounded] ?? 0) + 1;
    }

    return counts;
  }
}

class _DesktopFeedbackLayout extends StatelessWidget {
  const _DesktopFeedbackLayout({
    required this.height,
    required this.data,
    required this.averageRating,
    required this.totalFeedback,
    required this.lowRated,
    required this.driverFeedback,
    required this.reviewsByCity,
    required this.ratingDistribution,
  });

  final double height;
  final FeedbackTrendData data;
  final double averageRating;
  final int totalFeedback;
  final List<ProvinceFeedback> lowRated;
  final int driverFeedback;
  final Map<String, int> reviewsByCity;
  final Map<int, int> ratingDistribution;

  @override
  Widget build(BuildContext context) {
    const gap = 14.0;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          _FeedbackHero(
            averageRating: averageRating,
            totalFeedback: totalFeedback,
            lowRatedCount: lowRated.length,
          ),
          const SizedBox(height: gap),
          _MetricRow(
            averageRating: averageRating,
            totalFeedback: totalFeedback,
            lowRatedCount: lowRated.length,
            driverFeedback: driverFeedback,
          ),
          const SizedBox(height: gap),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 7,
                  child: Column(
                    children: [
                      Expanded(
                        child: _FeedbackPanel(
                          title: 'Low-Rated Reviews',
                          subtitle: 'Tourist feedback below 3 stars.',
                          icon: Icons.warning_rounded,
                          color: ProvincialAdminColors.red,
                          child: _FeedbackList(
                            items: lowRated,
                            empty: 'No low-rated reviews found.',
                          ),
                        ),
                      ),
                      const SizedBox(height: gap),
                      Expanded(
                        child: _FeedbackPanel(
                          title: 'Recent Feedback',
                          subtitle: 'Latest reviews and tourist comments.',
                          icon: Icons.forum_rounded,
                          color: ProvincialAdminColors.blue,
                          child: _FeedbackList(
                            items: data.feedback.take(6).toList(),
                            empty: 'No feedback records yet.',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      Expanded(
                        child: _FeedbackPanel(
                          title: 'Reviews by City',
                          subtitle: 'Feedback grouped by city where available.',
                          icon: Icons.location_city_rounded,
                          color: ProvincialAdminColors.cyan,
                          child: _CityReviewRows(
                            rows: reviewsByCity,
                            empty: 'No city-linked feedback yet.',
                          ),
                        ),
                      ),
                      const SizedBox(height: gap),
                      Expanded(
                        child: _FeedbackPanel(
                          title: 'Rating Distribution',
                          subtitle: 'Breakdown of tourist ratings.',
                          icon: Icons.star_rounded,
                          color: ProvincialAdminColors.amber,
                          child: _RatingDistribution(
                            ratings: ratingDistribution,
                            total: totalFeedback,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  flex: 5,
                  child: _FeedbackInsightsPanel(
                    averageRating: averageRating,
                    totalFeedback: totalFeedback,
                    lowRatedCount: lowRated.length,
                    driverFeedback: driverFeedback,
                    cityCount: reviewsByCity.length,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileFeedbackLayout extends StatelessWidget {
  const _MobileFeedbackLayout({
    required this.data,
    required this.averageRating,
    required this.totalFeedback,
    required this.lowRated,
    required this.driverFeedback,
    required this.reviewsByCity,
    required this.ratingDistribution,
  });

  final FeedbackTrendData data;
  final double averageRating;
  final int totalFeedback;
  final List<ProvinceFeedback> lowRated;
  final int driverFeedback;
  final Map<String, int> reviewsByCity;
  final Map<int, int> ratingDistribution;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FeedbackHero(
          compact: true,
          averageRating: averageRating,
          totalFeedback: totalFeedback,
          lowRatedCount: lowRated.length,
        ),
        const SizedBox(height: 14),
        _MetricGrid(
          averageRating: averageRating,
          totalFeedback: totalFeedback,
          lowRatedCount: lowRated.length,
          driverFeedback: driverFeedback,
        ),
        const SizedBox(height: 14),
        _FeedbackPanel(
          expand: false,
          title: 'Low-Rated Reviews',
          subtitle: 'Tourist feedback below 3 stars.',
          icon: Icons.warning_rounded,
          color: ProvincialAdminColors.red,
          child: _FeedbackList(
            items: lowRated,
            empty: 'No low-rated reviews found.',
          ),
        ),
        const SizedBox(height: 14),
        _FeedbackPanel(
          expand: false,
          title: 'Recent Feedback',
          subtitle: 'Latest reviews and tourist comments.',
          icon: Icons.forum_rounded,
          color: ProvincialAdminColors.blue,
          child: _FeedbackList(
            items: data.feedback.take(6).toList(),
            empty: 'No feedback records yet.',
          ),
        ),
        const SizedBox(height: 14),
        _FeedbackPanel(
          expand: false,
          title: 'Reviews by City',
          subtitle: 'Feedback grouped by city where available.',
          icon: Icons.location_city_rounded,
          color: ProvincialAdminColors.cyan,
          child: _CityReviewRows(
            rows: reviewsByCity,
            empty: 'No city-linked feedback yet.',
          ),
        ),
        const SizedBox(height: 14),
        _FeedbackPanel(
          expand: false,
          title: 'Rating Distribution',
          subtitle: 'Breakdown of tourist ratings.',
          icon: Icons.star_rounded,
          color: ProvincialAdminColors.amber,
          child: _RatingDistribution(
            ratings: ratingDistribution,
            total: totalFeedback,
          ),
        ),
      ],
    );
  }
}

class _FeedbackHero extends StatelessWidget {
  const _FeedbackHero({
    required this.averageRating,
    required this.totalFeedback,
    required this.lowRatedCount,
    this.compact = false,
  });

  final double averageRating;
  final int totalFeedback;
  final int lowRatedCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconBadge = Container(
      width: compact ? 46 : 58,
      height: compact ? 46 : 58,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
      ),
      child: Icon(
        Icons.rate_review_rounded,
        color: Colors.white,
        size: compact ? 24 : 30,
      ),
    );

    final titleBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FEEDBACK TRENDS',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .86),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Tourist Experience Review',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 19 : 27,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Monitor tourist ratings, comments, driver feedback, and low-rated service experiences.',
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .92),
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ],
    );

    final chips = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _HeroValueChip(
          label: 'Avg Rating',
          value: averageRating.toStringAsFixed(1),
          icon: Icons.star_rounded,
        ),
        _HeroValueChip(
          label: 'Low Rated',
          value: '$lowRatedCount',
          icon: Icons.warning_rounded,
        ),
        _HeroValueChip(
          label: 'Reviews',
          value: '$totalFeedback',
          icon: Icons.forum_rounded,
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 22,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4AA3FF), Color(0xFF1D63E9)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    iconBadge,
                    const SizedBox(width: 14),
                    Expanded(child: titleBlock),
                  ],
                ),
                const SizedBox(height: 14),
                chips,
              ],
            )
          : Row(
              children: [
                iconBadge,
                const SizedBox(width: 16),
                Expanded(child: titleBlock),
                const SizedBox(width: 14),
                chips,
              ],
            ),
    );
  }
}

class _HeroValueChip extends StatelessWidget {
  const _HeroValueChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 136,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$value\n',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .86),
                      fontSize: 11,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.averageRating,
    required this.totalFeedback,
    required this.lowRatedCount,
    required this.driverFeedback,
  });

  final double averageRating;
  final int totalFeedback;
  final int lowRatedCount;
  final int driverFeedback;

  @override
  Widget build(BuildContext context) {
    final items = _metricItems(
      averageRating: averageRating,
      totalFeedback: totalFeedback,
      lowRatedCount: lowRatedCount,
      driverFeedback: driverFeedback,
    );

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(child: _MetricCard(item: items[i])),
          if (i != items.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.averageRating,
    required this.totalFeedback,
    required this.lowRatedCount,
    required this.driverFeedback,
  });

  final double averageRating;
  final int totalFeedback;
  final int lowRatedCount;
  final int driverFeedback;

  @override
  Widget build(BuildContext context) {
    final items = _metricItems(
      averageRating: averageRating,
      totalFeedback: totalFeedback,
      lowRatedCount: lowRatedCount,
      driverFeedback: driverFeedback,
    );

    return AdminResponsiveGrid(
      minItemWidth: 230,
      maxColumns: 3,
      mobileAspectRatio: 2.8,
      tabletAspectRatio: 2.6,
      desktopAspectRatio: 2.6,
      children: [
        for (final item in items) _MetricCard(item: item),
      ],
    );
  }
}

List<_MetricItem> _metricItems({
  required double averageRating,
  required int totalFeedback,
  required int lowRatedCount,
  required int driverFeedback,
}) {
  return [
    _MetricItem(
      label: 'Average Rating',
      value: averageRating.toStringAsFixed(1),
      subtitle: 'tourist satisfaction',
      icon: Icons.star_rounded,
      color: ProvincialAdminColors.amber,
    ),
    _MetricItem(
      label: 'Total Feedback',
      value: '$totalFeedback',
      subtitle: 'submitted reviews',
      icon: Icons.rate_review_rounded,
      color: ProvincialAdminColors.blue,
    ),
    _MetricItem(
      label: 'Low Rated',
      value: '$lowRatedCount',
      subtitle: 'below 3 stars',
      icon: Icons.warning_rounded,
      color: ProvincialAdminColors.red,
    ),
    _MetricItem(
      label: 'Driver Feedback',
      value: '$driverFeedback',
      subtitle: 'transport reviews',
      icon: Icons.directions_bike_rounded,
      color: ProvincialAdminColors.cyan,
    ),
  ];
}

class _MetricItem {
  const _MetricItem({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});

  final _MetricItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: ProvincialAdminColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .022),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: item.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${item.value}\n',
                    style: const TextStyle(
                      color: ProvincialAdminColors.text,
                      fontSize: 25,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: '${item.label}\n',
                    style: const TextStyle(
                      color: ProvincialAdminColors.text,
                      fontSize: 13.5,
                      height: 1.25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: item.subtitle,
                    style: const TextStyle(
                      color: ProvincialAdminColors.muted,
                      fontSize: 11.8,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  const _FeedbackPanel({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.child,
    this.expand = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget child;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ProvincialAdminColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .022),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 37,
                height: 37,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$title\n',
                        style: const TextStyle(
                          color: ProvincialAdminColors.text,
                          fontSize: 17,
                          height: 1.2,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text: subtitle,
                        style: const TextStyle(
                          color: ProvincialAdminColors.muted,
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          expand ? Expanded(child: child) : child,
        ],
      ),
    );
  }
}

class _FeedbackList extends StatelessWidget {
  const _FeedbackList({required this.items, required this.empty});

  final List<ProvinceFeedback> items;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _PanelEmpty(title: empty, icon: Icons.rate_review_rounded);
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length > 6 ? 6 : items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        final date = item.createdAt == null
            ? 'No date'
            : DateFormat.yMMMd().format(item.createdAt!);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ProvincialAdminColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _ratingColor(item.rating).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.star_rounded,
                  color: _ratingColor(item.rating),
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.subjectName.isEmpty
                          ? 'Tourist experience'
                          : item.subjectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProvincialAdminColors.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.comment.isEmpty
                          ? 'No comment provided.'
                          : item.comment,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProvincialAdminColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${item.city} - ${item.reviewerName} - $date',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProvincialAdminColors.lightMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _RatingBadge(rating: item.rating),
            ],
          ),
        );
      },
    );
  }

  Color _ratingColor(double rating) {
    if (rating >= 4) return ProvincialAdminColors.green;
    if (rating >= 3) return ProvincialAdminColors.amber;
    return ProvincialAdminColors.red;
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final color = rating >= 4
        ? ProvincialAdminColors.green
        : rating >= 3
        ? ProvincialAdminColors.amber
        : ProvincialAdminColors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Text(
        rating.toStringAsFixed(1),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CityReviewRows extends StatelessWidget {
  const _CityReviewRows({required this.rows, required this.empty});

  final Map<String, int> rows;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return _PanelEmpty(title: empty, icon: Icons.location_city_rounded);
    }

    final entries = rows.entries.toList();
    final max = entries.first.value == 0 ? 1 : entries.first.value;

    return ListView.separated(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length > 6 ? 6 : entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final factor = entry.value / max;

        return Row(
          children: [
            Container(
              width: 29,
              height: 29,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: index == 0
                    ? ProvincialAdminColors.amber
                    : const Color(0xFFE8EEF7),
                shape: BoxShape.circle,
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: index == 0
                      ? Colors.white
                      : ProvincialAdminColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ProvincialAdminColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(
                          color: ProvincialAdminColors.amber,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: factor.clamp(.05, 1),
                      color: ProvincialAdminColors.amber,
                      backgroundColor: const Color(0xFFEAF2FF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RatingDistribution extends StatelessWidget {
  const _RatingDistribution({required this.ratings, required this.total});

  final Map<int, int> ratings;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (total == 0) {
      return const _PanelEmpty(
        title: 'No rating data yet.',
        icon: Icons.star_rounded,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final rating in [5, 4, 3, 2, 1]) ...[
          _RatingDistributionRow(
            stars: rating,
            count: ratings[rating] ?? 0,
            total: total,
          ),
          if (rating != 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _RatingDistributionRow extends StatelessWidget {
  const _RatingDistributionRow({
    required this.stars,
    required this.count,
    required this.total,
  });

  final int stars;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0.0 : count / total;

    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            '$stars★',
            style: const TextStyle(
              color: ProvincialAdminColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: count == 0 ? 0 : percent.clamp(.04, 1),
              color: ProvincialAdminColors.amber,
              backgroundColor: const Color(0xFFEAF2FF),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedbackInsightsPanel extends StatelessWidget {
  const _FeedbackInsightsPanel({
    required this.averageRating,
    required this.totalFeedback,
    required this.lowRatedCount,
    required this.driverFeedback,
    required this.cityCount,
  });

  final double averageRating;
  final int totalFeedback;
  final int lowRatedCount;
  final int driverFeedback;
  final int cityCount;

  @override
  Widget build(BuildContext context) {
    final items = [
      _InsightItem(
        icon: Icons.star_rounded,
        label: 'Average satisfaction',
        value: '${averageRating.toStringAsFixed(1)} out of 5.0',
      ),
      _InsightItem(
        icon: Icons.forum_rounded,
        label: 'Feedback volume',
        value: '$totalFeedback submitted reviews',
      ),
      _InsightItem(
        icon: Icons.warning_rounded,
        label: 'Needs attention',
        value: '$lowRatedCount low-rated reviews',
      ),
      _InsightItem(
        icon: Icons.directions_bike_rounded,
        label: 'Driver feedback',
        value: '$driverFeedback transport reviews',
      ),
      _InsightItem(
        icon: Icons.location_city_rounded,
        label: 'City coverage',
        value: '$cityCount cities with feedback',
      ),
    ];

    return _FeedbackPanel(
      title: 'Quick Insights',
      subtitle: 'Province-level feedback snapshot.',
      icon: Icons.auto_graph_rounded,
      color: ProvincialAdminColors.blue,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = items[index];

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFF),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: ProvincialAdminColors.line),
            ),
            child: Row(
              children: [
                Icon(item.icon, color: ProvincialAdminColors.blue, size: 19),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${item.label}\n',
                          style: const TextStyle(
                            color: ProvincialAdminColors.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                          ),
                        ),
                        TextSpan(
                          text: item.value,
                          style: const TextStyle(
                            color: ProvincialAdminColors.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InsightItem {
  const _InsightItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _PanelEmpty extends StatelessWidget {
  const _PanelEmpty({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: ProvincialAdminColors.lightMuted.withValues(alpha: .75),
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
