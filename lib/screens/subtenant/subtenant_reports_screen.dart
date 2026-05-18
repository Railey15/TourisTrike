import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_feedback_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantReportsScreen extends StatefulWidget {
  const SubTenantReportsScreen({super.key});

  @override
  State<SubTenantReportsScreen> createState() => _SubTenantReportsScreenState();
}

class _SubTenantReportsScreenState extends State<SubTenantReportsScreen> {
  final SubTenantService _service = SubTenantService();
  late Future<_ReportLoad> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReportLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final report = await _service.fetchReports(profile);
    return _ReportLoad(profile: profile, report: report);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: 5,
      title: 'City Reports',
      subtitle: 'Tourism package performance and driver-linked feedback.',
      child: FutureBuilder<_ReportLoad>(
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
          final report = load.report;
          final revenue = NumberFormat.currency(
            symbol: 'PHP ',
            decimalDigits: 0,
          ).format(report.estimatedRevenue);

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ResponsivePageContainer(
              children: [
                DashboardHeader(
                  eyebrow: 'Tourism Analytics',
                  title: load.profile.assignedCity,
                  subtitle:
                      'City-level tourism package, booking, transport, and feedback activity.',
                  icon: Icons.query_stats_rounded,
                ),
                const SizedBox(height: 18),
                ResponsiveGrid(
                  minItemWidth: 190,
                  maxColumns: 6,
                  mobileAspectRatio: 1.72,
                  tabletAspectRatio: 1.55,
                  desktopAspectRatio: 1.42,
                  children: [
                    DashboardMetricCard(
                      icon: Icons.place_rounded,
                      label: 'Spots',
                      value: '${report.totalSpots}',
                    ),
                    DashboardMetricCard(
                      icon: Icons.inventory_2_rounded,
                      label: 'Packages',
                      value: '${report.totalPackages}',
                    ),
                    DashboardMetricCard(
                      icon: Icons.receipt_long_rounded,
                      label: 'Bookings',
                      value: '${report.totalBookings}',
                      color: const Color(0xFF0EA5E9),
                    ),
                    DashboardMetricCard(
                      icon: Icons.payments_rounded,
                      label: 'Revenue',
                      value: revenue,
                      color: const Color(0xFF16A34A),
                    ),
                    DashboardMetricCard(
                      icon: Icons.check_circle_rounded,
                      label: 'Completed',
                      value: '${report.completedBookings}',
                      color: const Color(0xFF16A34A),
                    ),
                    DashboardMetricCard(
                      icon: Icons.cancel_rounded,
                      label: 'Cancelled',
                      value: '${report.cancelledBookings}',
                      color: const Color(0xFFDC2626),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _ReportChart(report: report),
                const SizedBox(height: 18),
                if (Responsive.isDesktop(context))
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ReportListCard(
                          title: 'Top Packages',
                          empty: 'No package booking data yet.',
                          rows: report.topPackages,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _ReportListCard(
                          title: 'Top Viewed Tourist Spots',
                          empty:
                              'No tourist_spot_views data is available for this city.',
                          rows: report.topSpots,
                        ),
                      ),
                    ],
                  )
                else ...[
                  _ReportListCard(
                    title: 'Top Packages',
                    empty: 'No package booking data yet.',
                    rows: report.topPackages,
                  ),
                  const SizedBox(height: 16),
                  _ReportListCard(
                    title: 'Top Viewed Tourist Spots',
                    empty:
                        'No tourist_spot_views data is available for this city.',
                    rows: report.topSpots,
                  ),
                ],
                const SizedBox(height: 18),
                _FeedbackSummary(report: report),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReportChart extends StatelessWidget {
  const _ReportChart({required this.report});

  final SubTenantReportData report;

  @override
  Widget build(BuildContext context) {
    final values = [
      report.totalBookings,
      report.completedBookings,
      report.cancelledBookings,
    ];
    final maxValue = values.fold<int>(
      1,
      (max, item) => item > max ? item : max,
    );

    return DashboardSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Booking Mix',
            subtitle: 'Completed and cancelled bookings compared to total.',
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: Responsive.isDesktop(context) ? 180 : 150,
            child: Row(
              children: [
                _HorizontalBar(
                  label: 'Total',
                  value: report.totalBookings,
                  maxValue: maxValue,
                  color: SubTenantColors.blue,
                ),
                _HorizontalBar(
                  label: 'Completed',
                  value: report.completedBookings,
                  maxValue: maxValue,
                  color: const Color(0xFF16A34A),
                ),
                _HorizontalBar(
                  label: 'Cancelled',
                  value: report.cancelledBookings,
                  maxValue: maxValue,
                  color: const Color(0xFFDC2626),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalBar extends StatelessWidget {
  const _HorizontalBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final String label;
  final int value;
  final int maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final factor = maxValue == 0 ? 0.0 : value / maxValue;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                color: SubTenantColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: (0.16 + (factor * 0.84)).clamp(0.16, 1.0),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SubTenantColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportListCard extends StatelessWidget {
  const _ReportListCard({
    required this.title,
    required this.empty,
    required this.rows,
  });

  final String title;
  final String empty;
  final List<SubTenantReportRow> rows;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Column(
        children: [
          SubTenantSectionHeader(title: title),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            _InlineNoData(message: empty)
          else
            ...rows.map(
              (row) => SubTenantInfoTile(
                icon: Icons.trending_up_rounded,
                title: row.title,
                subtitle: row.subtitle,
                trailing: Text(
                  row.value,
                  style: const TextStyle(
                    color: SubTenantColors.blue,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedbackSummary extends StatelessWidget {
  const _FeedbackSummary({required this.report});

  final SubTenantReportData report;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Column(
        children: [
          SubTenantSectionHeader(
            title: 'Feedback Summary',
            subtitle:
                '${report.feedbackCount} reviews - average ${report.averageRating.toStringAsFixed(1)}',
            trailing: 'View',
            onTrailingTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SubTenantFeedbackScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFF59E0B),
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                report.averageRating.toStringAsFixed(1),
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Filtered where ride_reviews can be connected to local drivers.',
                  style: TextStyle(
                    color: SubTenantColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineNoData extends StatelessWidget {
  const _InlineNoData({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights_outlined, color: SubTenantColors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: SubTenantColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportLoad {
  const _ReportLoad({required this.profile, required this.report});

  final SubTenantProfile profile;
  final SubTenantReportData report;
}
