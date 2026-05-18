import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantFeedbackScreen extends StatefulWidget {
  const SubTenantFeedbackScreen({super.key});

  @override
  State<SubTenantFeedbackScreen> createState() =>
      _SubTenantFeedbackScreenState();
}

class _SubTenantFeedbackScreenState extends State<SubTenantFeedbackScreen> {
  final SubTenantService _service = SubTenantService();
  late Future<_FeedbackLoad> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_FeedbackLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final feedback = await _service.fetchFeedback(profile);
    return _FeedbackLoad(profile: profile, feedback: feedback);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SubTenantColors.background,
      appBar: subTenantAppBar(context, title: 'Feedback', showBack: true),
      body: FutureBuilder<_FeedbackLoad>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SubTenantLoadingView();
          }
          if (snapshot.hasError) {
            return SubTenantErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final load = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                SubTenantDashboardCard(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: SubTenantColors.blue,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Feedback is filtered through ride_reviews.driver_id when it matches a local driver in ${load.profile.assignedCity}.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: SubTenantColors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (load.feedback.isEmpty)
                  const SubTenantEmptyState(
                    icon: Icons.rate_review_outlined,
                    title: 'No feedback found',
                    message:
                        'If ride_reviews is not directly connected to city/package data, add city-safe relationships before showing broader feedback.',
                  )
                else
                  ...load.feedback.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _FeedbackCard(item: item),
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

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.item});

  final SubTenantFeedback item;

  @override
  Widget build(BuildContext context) {
    final date = item.createdAt == null
        ? 'No date'
        : DateFormat('MMM d, yyyy').format(item.createdAt!);

    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
              const SizedBox(width: 5),
              Text(
                item.rating.toStringAsFixed(1),
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                date,
                style: const TextStyle(
                  color: SubTenantColors.lightMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.comment.isEmpty ? 'No comment provided.' : item.comment,
            style: const TextStyle(
              color: SubTenantColors.text,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SubTenantStatusPill(
                status: item.touristName,
                icon: Icons.person_rounded,
              ),
              SubTenantStatusPill(
                status: item.driverName,
                icon: Icons.badge_rounded,
              ),
              if (item.relatedLabel.isNotEmpty)
                SubTenantStatusPill(
                  status: 'Ride ${item.relatedLabel}',
                  icon: Icons.route_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeedbackLoad {
  const _FeedbackLoad({required this.profile, required this.feedback});

  final SubTenantProfile profile;
  final List<SubTenantFeedback> feedback;
}
