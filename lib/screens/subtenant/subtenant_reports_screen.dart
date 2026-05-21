import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
  SubTenantReportRange _range = SubTenantReportRange.currentMonth();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReportLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final report = await _service.fetchReports(profile, range: _range);
    return _ReportLoad(profile: profile, report: report);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  void _setRange(SubTenantReportRange range) {
    setState(() {
      _range = range;
      _future = _load();
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _range.start, end: _range.end),
    );
    if (picked == null) return;
    _setRange(SubTenantReportRange.custom(picked.start, picked.end));
  }

  Future<void> _downloadPdf(_ReportLoad load) async {
    final report = load.report;
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);
    final doc = pw.Document();

    pw.Widget metric(String label, String value) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.blue100),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      );
    }

    pw.Widget row(SubTenantReportRow item) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          children: [
            pw.Expanded(child: pw.Text(item.title)),
            pw.Text(item.value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            'TourisTrike City Tourism Report',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('${load.profile.assignedCity} - ${report.rangeLabel}'),
          pw.Text(
            '${DateFormat.yMMMd().format(_range.start)} to ${DateFormat.yMMMd().format(_range.end)}',
          ),
          pw.SizedBox(height: 20),
          pw.Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              metric('Bookings', '${report.totalBookings}'),
              metric('Completed', '${report.completedBookings}'),
              metric('Cancelled', '${report.cancelledBookings}'),
              metric('Revenue', money.format(report.estimatedRevenue)),
              metric('Packages', '${report.totalPackages}'),
              metric('Spots', '${report.totalSpots}'),
              metric('Drivers', '${report.totalDrivers}'),
              metric('Feedback Avg.', report.averageRating.toStringAsFixed(1)),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Text('Top Packages', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ...report.topPackages.map(row),
          pw.SizedBox(height: 16),
          pw.Text('Top Tourist Spots', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ...report.topSpots.map(row),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename:
          'touristrike-${load.profile.assignedCity.toLowerCase()}-${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: 5,
      title: 'City Reports',
      subtitle: 'Tourism package performance and driver-linked feedback.',
      actions: [
        IconButton(
          onPressed: () async {
            final load = await _future;
            await _downloadPdf(load);
          },
          tooltip: 'Download PDF',
          icon: const Icon(Icons.picture_as_pdf_rounded),
        ),
      ],
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
                      '${report.rangeLabel} - city-level tourism package, booking, transport, and feedback activity.',
                  icon: Icons.query_stats_rounded,
                ),
                const SizedBox(height: 18),
                _ReportRangeBar(
                  range: _range,
                  onWeekly: () => _setRange(SubTenantReportRange.weekly()),
                  onMonthly: () =>
                      _setRange(SubTenantReportRange.currentMonth()),
                  onYearly: () => _setRange(SubTenantReportRange.yearly()),
                  onCustom: _pickCustomRange,
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
                      icon: Icons.badge_rounded,
                      label: 'Drivers',
                      value: '${report.totalDrivers}',
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

class _ReportRangeBar extends StatelessWidget {
  const _ReportRangeBar({
    required this.range,
    required this.onWeekly,
    required this.onMonthly,
    required this.onYearly,
    required this.onCustom,
  });

  final SubTenantReportRange range;
  final VoidCallback onWeekly;
  final VoidCallback onMonthly;
  final VoidCallback onYearly;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final selected = range.label;
    return DashboardSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubTenantSectionHeader(
            title: 'Report Range',
            subtitle:
                '${DateFormat.yMMMd().format(range.start)} - ${DateFormat.yMMMd().format(range.end)}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RangeChip(
                label: 'Weekly',
                selected: selected == 'This Week',
                onTap: onWeekly,
              ),
              _RangeChip(
                label: 'Monthly',
                selected: selected == 'Current Month',
                onTap: onMonthly,
              ),
              _RangeChip(
                label: 'Yearly',
                selected: selected == 'This Year',
                onTap: onYearly,
              ),
              _RangeChip(
                label: 'Custom',
                selected: selected == 'Custom Range',
                onTap: onCustom,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: SubTenantColors.blue,
      labelStyle: TextStyle(
        color: selected ? Colors.white : SubTenantColors.text,
        fontWeight: FontWeight.w900,
      ),
      side: const BorderSide(color: SubTenantColors.line),
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
