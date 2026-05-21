import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

const _allCities = 'All Cities';

class ProvinceReportsScreen extends StatefulWidget {
  const ProvinceReportsScreen({super.key});

  @override
  State<ProvinceReportsScreen> createState() => _ProvinceReportsScreenState();
}

class _ProvinceReportsScreenState extends State<ProvinceReportsScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();

  late Future<AdminReportData> _future;
  _ReportsTab _tab = _ReportsTab.overview;
  _ProvinceReportType _exportType = _ProvinceReportType.overview;
  String _exportCity = _allCities;
  _ReportDatePreset _exportDatePreset = _ReportDatePreset.monthly;
  DateTimeRange? _customRange;
  final Set<_ReportSection> _exportSections = _ReportSection.values.toSet();
  _ReportSnapshot? _exportPreview;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchReports();
  }

  void _reload() {
    setState(() {
      _exportPreview = null;
      _future = _service.fetchReports();
    });
  }

  void _setExportType(_ProvinceReportType type) {
    setState(() {
      _exportType = type;
      _exportPreview = null;
    });
  }

  void _setExportCity(String? city) {
    if (city == null) return;
    setState(() {
      _exportCity = city;
      _exportPreview = null;
    });
  }

  void _setExportDatePreset(_ReportDatePreset preset) {
    setState(() {
      _exportDatePreset = preset;
      _exportPreview = null;
    });
    if (preset == _ReportDatePreset.custom && _customRange == null) {
      _pickCustomRange();
    }
  }

  void _toggleExportSection(_ReportSection section, bool selected) {
    setState(() {
      if (selected) {
        _exportSections.add(section);
      } else {
        _exportSections.remove(section);
      }
      _exportPreview = null;
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange:
          _customRange ??
          DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: ProvincialAdminColors.deepBlue,
              secondary: ProvincialAdminColors.blue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;
    setState(() {
      _exportDatePreset = _ReportDatePreset.custom;
      _customRange = picked;
      _exportPreview = null;
    });
  }

  void _generatePreview(AdminReportData data) {
    setState(() => _exportPreview = _buildReportSnapshot(data, _exportConfig));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Report preview generated.')));
  }

  Future<void> _exportPdf(AdminReportData data) async {
    if (_isExporting) return;

    final report = _exportPreview ?? _buildReportSnapshot(data, _exportConfig);

    setState(() {
      _isExporting = true;
      _exportPreview = report;
    });

    try {
      final bytes = await _buildPdf(report);
      await Printing.sharePdf(bytes: bytes, filename: _pdfFileName(report));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PDF report is ready.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to export PDF: $error')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  _ReportConfig get _exportConfig {
    return _ReportConfig(
      type: _exportType,
      city: _exportCity,
      datePreset: _exportDatePreset,
      customRange: _customRange,
      sections: _exportSections.toSet(),
    );
  }

  _ReportConfig _tabConfig(_ReportsTab tab) {
    return _ReportConfig(
      type: tab.reportType ?? _ProvinceReportType.overview,
      city: _allCities,
      datePreset: _ReportDatePreset.monthly,
      customRange: null,
      sections: _ReportSection.values.toSet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProvincialAdminShell(
      current: ProvincialAdminDestination.reports,
      title: 'Reports',
      subtitle: 'Province-wide tourism reports organized by category.',
      
      child: FutureBuilder<AdminReportData>(
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
          final cityOptions = [_allCities, ..._availableCities(data)];
          if (!cityOptions.contains(_exportCity)) {
            _exportCity = _allCities;
          }

          final dashboard = _buildReportSnapshot(data, _tabConfig(_tab));
          final exportPreview = _exportPreview;

          return LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 1050;
              if (!desktop) {
                return _MobileReportsLayout(
                  data: data,
                  tab: _tab,
                  dashboard: dashboard,
                  cityOptions: cityOptions,
                  exportConfig: _exportConfig,
                  exportPreview: exportPreview,
                  isExporting: _isExporting,
                  onTabChanged: (tab) => setState(() => _tab = tab),
                  onExportTypeChanged: _setExportType,
                  onExportCityChanged: _setExportCity,
                  onExportDatePresetChanged: _setExportDatePreset,
                  onPickCustomRange: _pickCustomRange,
                  onExportSectionChanged: _toggleExportSection,
                  onGeneratePreview: () => _generatePreview(data),
                  onExportPdf: () => _exportPdf(data),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 22),
                child: SizedBox(
                  height: constraints.maxHeight - 38,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 96,
                        child: _ReportsHero(report: dashboard, tab: _tab),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 88,
                        child: _SummaryMetricRow(metrics: dashboard.metrics),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 48,
                        child: _ReportsTabBar(
                          selected: _tab,
                          onChanged: (tab) => setState(() => _tab = tab),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _ReportsTabContent(
                          data: data,
                          tab: _tab,
                          report: dashboard,
                          cityOptions: cityOptions,
                          exportConfig: _exportConfig,
                          exportPreview: exportPreview,
                          isExporting: _isExporting,
                          onExportTypeChanged: _setExportType,
                          onExportCityChanged: _setExportCity,
                          onExportDatePresetChanged: _setExportDatePreset,
                          onPickCustomRange: _pickCustomRange,
                          onExportSectionChanged: _toggleExportSection,
                          onGeneratePreview: () => _generatePreview(data),
                          onExportPdf: () => _exportPdf(data),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  List<String> _availableCities(AdminReportData data) {
    final cities =
        <String>{
              ...data.tenants.map((item) => item.city),
              ...data.packages.map((item) => item.city),
              ...data.spots.map((item) => item.city),
              ...data.bookings.map((item) => item.city),
              ...data.feedback.map((item) => item.city),
            }
            .map((city) => city.trim())
            .where((city) => city.isNotEmpty && city.toLowerCase() != 'unknown')
            .toSet()
            .toList()
          ..sort();
    return cities;
  }

  _ReportSnapshot _buildReportSnapshot(
    AdminReportData data,
    _ReportConfig config,
  ) {
    final generatedAt = DateTime.now();
    final window = config.resolveWindow(generatedAt);

    bool cityMatches(String city) {
      return config.city == _allCities || _sameCity(city, config.city);
    }

    final tenants = data.tenants
        .where((item) => cityMatches(item.city))
        .toList(growable: false);
    final packages = data.packages
        .where((item) => cityMatches(item.city))
        .toList(growable: false);
    final spots = data.spots
        .where((item) => cityMatches(item.city))
        .toList(growable: false);
    final bookings = data.bookings
        .where((item) {
          final date = item.travelDate ?? item.createdAt;
          return cityMatches(item.city) && window.contains(date);
        })
        .toList(growable: false);
    final feedback = data.feedback
        .where((item) {
          return cityMatches(item.city) && window.contains(item.createdAt);
        })
        .toList(growable: false);

    final cityRows = _buildCityRows(
      tenants: tenants,
      packages: packages,
      spots: spots,
      bookings: bookings,
      feedback: feedback,
    );

    final completed = bookings
        .where((item) => item.status.toLowerCase() == 'completed')
        .length;
    final cancelled = bookings
        .where((item) => item.status.toLowerCase() == 'cancelled')
        .length;
    final revenue = bookings.fold<double>(
      0,
      (sum, booking) => booking.status.toLowerCase() == 'completed'
          ? sum + booking.totalAmount
          : sum,
    );
    final drivers = tenants.fold<int>(
      0,
      (sum, tenant) => sum + tenant.driversCount,
    );
    final averageRating = feedback.isEmpty
        ? 0.0
        : feedback.fold<double>(0, (sum, item) => sum + item.rating) /
              feedback.length;

    final metrics = <_SummaryMetric>[
      _SummaryMetric(
        label: 'Bookings',
        value: '${bookings.length}',
        helper: '${window.shortLabel} activity',
        icon: Icons.receipt_long_rounded,
        color: ProvincialAdminColors.blue,
      ),
      _SummaryMetric(
        label: 'Revenue',
        value: _money(revenue),
        helper: 'completed bookings',
        icon: Icons.payments_rounded,
        color: ProvincialAdminColors.amber,
      ),
      _SummaryMetric(
        label: 'Tourism Assets',
        value: '${packages.length} / ${spots.length}',
        helper: 'packages and spots',
        icon: Icons.map_rounded,
        color: ProvincialAdminColors.purple,
      ),
      _SummaryMetric(
        label: 'Coverage',
        value: '${tenants.length} cities',
        helper: '$drivers drivers, ${feedback.length} reviews',
        icon: Icons.location_city_rounded,
        color: ProvincialAdminColors.cyan,
      ),
    ];

    return _ReportSnapshot(
      config: config,
      generatedAt: generatedAt,
      window: window,
      title: config.type.label,
      metrics: metrics,
      cityRows: cityRows,
      tenants: tenants,
      packages: packages,
      spots: spots,
      bookings: bookings,
      feedback: feedback,
      totalBookings: bookings.length,
      completedBookings: completed,
      cancelledBookings: cancelled,
      totalRevenue: revenue,
      totalPackages: packages.length,
      totalSpots: spots.length,
      totalDrivers: drivers,
      totalFeedback: feedback.length,
      averageRating: averageRating,
    );
  }

  List<_CityPerformanceRow> _buildCityRows({
    required List<CityTenant> tenants,
    required List<ProvincePackage> packages,
    required List<ProvinceSpot> spots,
    required List<ProvinceBooking> bookings,
    required List<ProvinceFeedback> feedback,
  }) {
    final cityNames = <String>{
      ...tenants.map((item) => item.city),
      ...packages.map((item) => item.city),
      ...spots.map((item) => item.city),
      ...bookings.map((item) => item.city),
      ...feedback.map((item) => item.city),
    }.map((city) => city.trim().isEmpty ? 'Unassigned' : city.trim()).toSet();

    final rows = <_CityPerformanceRow>[];
    for (final city in cityNames) {
      final cityTenants = tenants.where((item) => _sameCity(item.city, city));
      final cityPackages = packages.where((item) => _sameCity(item.city, city));
      final citySpots = spots.where((item) => _sameCity(item.city, city));
      final cityBookings = bookings.where((item) => _sameCity(item.city, city));
      final cityFeedback = feedback.where((item) => _sameCity(item.city, city));
      final completed = cityBookings
          .where((item) => item.status.toLowerCase() == 'completed')
          .length;
      final cancelled = cityBookings
          .where((item) => item.status.toLowerCase() == 'cancelled')
          .length;
      final revenue = cityBookings.fold<double>(
        0,
        (sum, booking) => booking.status.toLowerCase() == 'completed'
            ? sum + booking.totalAmount
            : sum,
      );
      final ratings = cityFeedback.where((item) => item.rating > 0).toList();
      final averageRating = ratings.isEmpty
          ? 0.0
          : ratings.fold<double>(0, (sum, item) => sum + item.rating) /
                ratings.length;

      rows.add(
        _CityPerformanceRow(
          city: city,
          bookings: cityBookings.length,
          completed: completed,
          cancelled: cancelled,
          revenue: revenue,
          packages: cityPackages.length,
          spots: citySpots.length,
          drivers: cityTenants.fold<int>(
            0,
            (sum, tenant) => sum + tenant.driversCount,
          ),
          feedbackCount: cityFeedback.length,
          averageRating: averageRating,
        ),
      );
    }

    rows.sort((a, b) {
      final bookingCompare = b.bookings.compareTo(a.bookings);
      if (bookingCompare != 0) return bookingCompare;
      return b.revenue.compareTo(a.revenue);
    });

    return rows;
  }

  Future<Uint8List> _buildPdf(_ReportSnapshot report) async {
    final doc = pw.Document();
    final tables = _tablesForReport(report);
    final generatedLabel = DateFormat(
      'MMM d, y h:mm a',
    ).format(report.generatedAt);
    final blue = PdfColor.fromInt(0xFF1E63E9);
    final text = PdfColor.fromInt(0xFF0F172A);
    final muted = PdfColor.fromInt(0xFF64748B);

    pw.Widget detail(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(
          children: [
            pw.SizedBox(
              width: 105,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 9,
                  color: muted,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                value,
                style: pw.TextStyle(fontSize: 9, color: text),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget metric(_SummaryMetric item) {
      return pw.Container(
        width: 150,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.blue100),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(item.label, style: pw.TextStyle(fontSize: 8, color: muted)),
            pw.SizedBox(height: 4),
            pw.Text(
              item.value,
              style: pw.TextStyle(
                fontSize: 14,
                color: text,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              item.helper,
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      );
    }

    pw.Widget table(_ReportTable table) {
      final rows = table.rows.isEmpty
          ? [
              List<String>.generate(
                table.columns.length,
                (index) => index == 0 ? table.emptyMessage : '',
              ),
            ]
          : table.rows.take(40).toList();

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            table.title,
            style: pw.TextStyle(
              color: text,
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            table.subtitle,
            style: pw.TextStyle(color: muted, fontSize: 8),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
            headerDecoration: pw.BoxDecoration(color: PdfColors.blue50),
            headerStyle: pw.TextStyle(
              color: blue,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: pw.TextStyle(color: text, fontSize: 7.5),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 4,
            ),
            headers: table.columns,
            data: rows,
          ),
          pw.SizedBox(height: 16),
        ],
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 30, 30, 34),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated by TourisTrike Provincial Admin - $generatedLabel',
              style: pw.TextStyle(color: muted, fontSize: 8),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(color: muted, fontSize: 8),
            ),
          ],
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              border: pw.Border.all(color: PdfColors.blue100),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 42,
                  height: 42,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    color: blue,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    'TT',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'TourisTrike / Bulacan Provincial Tourism',
                        style: pw.TextStyle(
                          color: blue,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        report.title,
                        style: pw.TextStyle(
                          color: text,
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Formal provincial tourism report generated from selected administrative filters.',
                        style: pw.TextStyle(color: muted, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              children: [
                detail('Date Generated', generatedLabel),
                detail('City/Subtenant', report.config.city),
                detail('Report Type', report.config.type.label),
                detail('Date Range', report.window.label),
                detail(
                  'Included Sections',
                  report.config.sections.map((item) => item.label).join(', '),
                ),
              ],
            ),
          ),
          if (report.config.sections.contains(_ReportSection.summaryCards)) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'Summary Section',
              style: pw.TextStyle(
                color: text,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: report.metrics.map(metric).toList(),
            ),
          ],
          if (report.config.sections.contains(_ReportSection.charts)) ...[
            pw.SizedBox(height: 18),
            table(_chartDataTable(report)),
          ],
          if (tables.isEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'No table sections were included, or no matching rows were found.',
              style: pw.TextStyle(color: muted, fontSize: 9),
            ),
          ] else ...[
            pw.SizedBox(height: 18),
            ...tables.map(table),
          ],
        ],
      ),
    );

    return doc.save();
  }

  String _pdfFileName(_ReportSnapshot report) {
    final type = _slug(report.config.type.label);
    final city = _slug(report.config.city);
    final stamp = DateFormat('yyyyMMdd-HHmm').format(report.generatedAt);
    return 'touristrike-bulacan-$type-$city-$stamp.pdf';
  }
}

class _MobileReportsLayout extends StatelessWidget {
  const _MobileReportsLayout({
    required this.data,
    required this.tab,
    required this.dashboard,
    required this.cityOptions,
    required this.exportConfig,
    required this.exportPreview,
    required this.isExporting,
    required this.onTabChanged,
    required this.onExportTypeChanged,
    required this.onExportCityChanged,
    required this.onExportDatePresetChanged,
    required this.onPickCustomRange,
    required this.onExportSectionChanged,
    required this.onGeneratePreview,
    required this.onExportPdf,
  });

  final AdminReportData data;
  final _ReportsTab tab;
  final _ReportSnapshot dashboard;
  final List<String> cityOptions;
  final _ReportConfig exportConfig;
  final _ReportSnapshot? exportPreview;
  final bool isExporting;
  final ValueChanged<_ReportsTab> onTabChanged;
  final ValueChanged<_ProvinceReportType> onExportTypeChanged;
  final ValueChanged<String?> onExportCityChanged;
  final ValueChanged<_ReportDatePreset> onExportDatePresetChanged;
  final VoidCallback onPickCustomRange;
  final void Function(_ReportSection section, bool selected)
  onExportSectionChanged;
  final VoidCallback onGeneratePreview;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        children: [
          SizedBox(
            height: 132,
            child: _ReportsHero(report: dashboard, tab: tab),
          ),
          const SizedBox(height: 12),
          _SummaryMetricWrap(metrics: dashboard.metrics),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: _ReportsTabBar(selected: tab, onChanged: onTabChanged),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: tab == _ReportsTab.export ? 700 : 580,
            child: _ReportsTabContent(
              data: data,
              tab: tab,
              report: dashboard,
              cityOptions: cityOptions,
              exportConfig: exportConfig,
              exportPreview: exportPreview,
              isExporting: isExporting,
              onExportTypeChanged: onExportTypeChanged,
              onExportCityChanged: onExportCityChanged,
              onExportDatePresetChanged: onExportDatePresetChanged,
              onPickCustomRange: onPickCustomRange,
              onExportSectionChanged: onExportSectionChanged,
              onGeneratePreview: onGeneratePreview,
              onExportPdf: onExportPdf,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsHero extends StatelessWidget {
  const _ReportsHero({required this.report, required this.tab});

  final _ReportSnapshot report;
  final _ReportsTab tab;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        gradient: ProvincialAdminColors.gradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [provincialAdminShadow(alpha: .075)],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .25)),
            ),
            child: Icon(tab.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'PROVINCIAL REPORTS\n',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .86),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .4,
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: '${tab.label} Dashboard\n',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  TextSpan(
                    text: '${report.config.city} - ${report.window.label}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .92),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          _HeroChip(
            icon: Icons.receipt_long_rounded,
            value: '${report.totalBookings}',
            label: 'Bookings',
          ),
          const SizedBox(width: 10),
          _HeroChip(
            icon: Icons.payments_rounded,
            value: _money(report.totalRevenue),
            label: 'Revenue',
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 145,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$value\n',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  TextSpan(
                    text: label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .85),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      height: 1.45,
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

class _SummaryMetricRow extends StatelessWidget {
  const _SummaryMetricRow({required this.metrics});

  final List<_SummaryMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          Expanded(child: _MetricCard(item: metrics[i])),
          if (i != metrics.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _SummaryMetricWrap extends StatelessWidget {
  const _SummaryMetricWrap({required this.metrics});

  final List<_SummaryMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = constraints.maxWidth >= 700 ? 2 : 1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map(
                (item) => SizedBox(
                  width: width,
                  height: 86,
                  child: _MetricCard(item: item),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});

  final _SummaryMetric item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: ProvincialAdminColors.line),
        boxShadow: [provincialAdminShadow(alpha: .032)],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(item.icon, color: item.color, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${item.value}\n',
                    style: const TextStyle(
                      color: ProvincialAdminColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  TextSpan(
                    text: '${item.label}\n',
                    style: const TextStyle(
                      color: ProvincialAdminColors.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      height: 1.35,
                    ),
                  ),
                  TextSpan(
                    text: item.helper,
                    style: const TextStyle(
                      color: ProvincialAdminColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
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

class _ReportsTabBar extends StatelessWidget {
  const _ReportsTabBar({required this.selected, required this.onChanged});

  final _ReportsTab selected;
  final ValueChanged<_ReportsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _ReportsTab.values.map((tab) {
            final active = tab == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Tooltip(
                message: tab.label,
                child: InkWell(
                  onTap: () => onChanged(tab),
                  borderRadius: BorderRadius.circular(13),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: active
                          ? ProvincialAdminColors.deepBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          tab.icon,
                          size: 17,
                          color: active
                              ? Colors.white
                              : ProvincialAdminColors.muted,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          tab.label,
                          style: TextStyle(
                            color: active
                                ? Colors.white
                                : ProvincialAdminColors.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ReportsTabContent extends StatelessWidget {
  const _ReportsTabContent({
    required this.data,
    required this.tab,
    required this.report,
    required this.cityOptions,
    required this.exportConfig,
    required this.exportPreview,
    required this.isExporting,
    required this.onExportTypeChanged,
    required this.onExportCityChanged,
    required this.onExportDatePresetChanged,
    required this.onPickCustomRange,
    required this.onExportSectionChanged,
    required this.onGeneratePreview,
    required this.onExportPdf,
  });

  final AdminReportData data;
  final _ReportsTab tab;
  final _ReportSnapshot report;
  final List<String> cityOptions;
  final _ReportConfig exportConfig;
  final _ReportSnapshot? exportPreview;
  final bool isExporting;
  final ValueChanged<_ProvinceReportType> onExportTypeChanged;
  final ValueChanged<String?> onExportCityChanged;
  final ValueChanged<_ReportDatePreset> onExportDatePresetChanged;
  final VoidCallback onPickCustomRange;
  final void Function(_ReportSection section, bool selected)
  onExportSectionChanged;
  final VoidCallback onGeneratePreview;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    switch (tab) {
      case _ReportsTab.overview:
        return _OverviewTab(report: report);
      case _ReportsTab.bookings:
        return _TwoCardTab(
          first: _DashboardCard(
            title: 'Booking Status',
            subtitle: 'Outcomes within the selected month.',
            icon: Icons.donut_large_rounded,
            color: ProvincialAdminColors.blue,
            child: _StatusBreakdown(report: report),
          ),
          second: _DashboardCard(
            title: 'Recent Bookings',
            subtitle: 'Latest booking records.',
            icon: Icons.receipt_long_rounded,
            color: ProvincialAdminColors.cyan,
            child: _CompactTable(table: _bookingTable(report.bookings)),
          ),
        );
      case _ReportsTab.revenue:
        return _TwoCardTab(
          first: _DashboardCard(
            title: 'Revenue by City',
            subtitle: 'Completed booking value grouped by LGU.',
            icon: Icons.location_city_rounded,
            color: ProvincialAdminColors.green,
            child: _CompactTable(table: _revenueByCityTable(report.cityRows)),
          ),
          second: _DashboardCard(
            title: 'Package Revenue',
            subtitle: 'Top packages by completed revenue.',
            icon: Icons.payments_rounded,
            color: ProvincialAdminColors.amber,
            child: _CompactTable(table: _packageRevenueTable(report)),
          ),
        );
      case _ReportsTab.packages:
        return _TwoCardTab(
          first: _DashboardCard(
            title: 'Package Performance',
            subtitle: 'Booking activity by tour package.',
            icon: Icons.inventory_2_rounded,
            color: ProvincialAdminColors.green,
            child: _CompactTable(table: _packagePerformanceTable(report)),
          ),
          second: _DashboardCard(
            title: 'Packages by City',
            subtitle: 'Distribution of listed tours.',
            icon: Icons.bar_chart_rounded,
            color: ProvincialAdminColors.blue,
            child: _RankedRows(rows: _countPackagesByCity(report.packages)),
          ),
        );
      case _ReportsTab.spots:
        return _TwoCardTab(
          first: _DashboardCard(
            title: 'Spot Inventory',
            subtitle: 'Submitted tourist spots by city.',
            icon: Icons.place_rounded,
            color: ProvincialAdminColors.cyan,
            child: _CompactTable(table: _spotCityTable(report)),
          ),
          second: _DashboardCard(
            title: 'Top Tourist Spots',
            subtitle: 'Spot records sorted by available rating.',
            icon: Icons.star_rounded,
            color: ProvincialAdminColors.amber,
            child: _CompactTable(table: _topSpotTable(report.spots)),
          ),
        );
      case _ReportsTab.drivers:
        return _TwoCardTab(
          first: _DashboardCard(
            title: 'Driver Coverage',
            subtitle: 'Registered drivers by city/subtenant.',
            icon: Icons.directions_bike_rounded,
            color: ProvincialAdminColors.deepBlue,
            child: _CompactTable(table: _driverCoverageTable(report)),
          ),
          second: _DashboardCard(
            title: 'Coverage Ranking',
            subtitle: 'Cities with the most registered drivers.',
            icon: Icons.leaderboard_rounded,
            color: ProvincialAdminColors.purple,
            child: _RankedRows(rows: _countDriversByCity(report.tenants)),
          ),
        );
      case _ReportsTab.feedback:
        return _TwoCardTab(
          first: _DashboardCard(
            title: 'Ratings by City',
            subtitle: 'Review volume and average rating.',
            icon: Icons.forum_rounded,
            color: ProvincialAdminColors.purple,
            child: _CompactTable(table: _feedbackCityTable(report.cityRows)),
          ),
          second: _DashboardCard(
            title: 'Recent Feedback',
            subtitle: 'Latest tourist comments.',
            icon: Icons.rate_review_rounded,
            color: ProvincialAdminColors.blue,
            child: _CompactTable(table: _recentFeedbackTable(report.feedback)),
          ),
        );
      case _ReportsTab.export:
        return _ExportTab(
          cityOptions: cityOptions,
          config: exportConfig,
          preview: exportPreview,
          isExporting: isExporting,
          onTypeChanged: onExportTypeChanged,
          onCityChanged: onExportCityChanged,
          onDatePresetChanged: onExportDatePresetChanged,
          onPickCustomRange: onPickCustomRange,
          onSectionChanged: onExportSectionChanged,
          onGeneratePreview: onGeneratePreview,
          onExportPdf: onExportPdf,
        );
    }
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.report});

  final _ReportSnapshot report;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 7,
          child: _DashboardCard(
            title: 'City Performance',
            subtitle: 'Bookings, revenue, assets, drivers, and feedback.',
            icon: Icons.analytics_rounded,
            color: ProvincialAdminColors.blue,
            child: _CompactTable(table: _cityPerformanceTable(report.cityRows)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: Column(
            children: [
              Expanded(
                child: _DashboardCard(
                  title: 'Booking Outcome',
                  subtitle: 'Completed, cancelled, and pending tours.',
                  icon: Icons.donut_large_rounded,
                  color: ProvincialAdminColors.green,
                  child: _StatusBreakdown(report: report),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _DashboardCard(
                  title: 'Tourism Coverage',
                  subtitle: 'Inventory and operating coverage.',
                  icon: Icons.map_rounded,
                  color: ProvincialAdminColors.purple,
                  child: _CoverageSummary(report: report),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TwoCardTab extends StatelessWidget {
  const _TwoCardTab({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ProvincialAdminColors.line),
        boxShadow: [provincialAdminShadow(alpha: .032)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
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
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          height: 1.25,
                        ),
                      ),
                      TextSpan(
                        text: subtitle,
                        style: const TextStyle(
                          color: ProvincialAdminColors.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
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
          const SizedBox(height: 13),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.report});

  final _ReportSnapshot report;

  @override
  Widget build(BuildContext context) {
    final pending =
        (report.totalBookings -
                report.completedBookings -
                report.cancelledBookings)
            .clamp(0, report.totalBookings);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ProgressRow(
          label: 'Completed',
          value: report.completedBookings,
          total: report.totalBookings,
          color: ProvincialAdminColors.green,
        ),
        const SizedBox(height: 13),
        _ProgressRow(
          label: 'Cancelled',
          value: report.cancelledBookings,
          total: report.totalBookings,
          color: ProvincialAdminColors.red,
        ),
        const SizedBox(height: 13),
        _ProgressRow(
          label: 'Other / Pending',
          value: pending,
          total: report.totalBookings,
          color: ProvincialAdminColors.amber,
        ),
      ],
    );
  }
}

class _CoverageSummary extends StatelessWidget {
  const _CoverageSummary({required this.report});

  final _ReportSnapshot report;

  @override
  Widget build(BuildContext context) {
    final items = [
      _CoverageItem(
        icon: Icons.location_city_rounded,
        label: 'Cities',
        value: '${report.tenants.length}',
      ),
      _CoverageItem(
        icon: Icons.inventory_2_rounded,
        label: 'Packages',
        value: '${report.totalPackages}',
      ),
      _CoverageItem(
        icon: Icons.place_rounded,
        label: 'Spots',
        value: '${report.totalSpots}',
      ),
      _CoverageItem(
        icon: Icons.directions_bike_rounded,
        label: 'Drivers',
        value: '${report.totalDrivers}',
      ),
      _CoverageItem(
        icon: Icons.forum_rounded,
        label: 'Feedback',
        value: report.averageRating == 0
            ? '${report.totalFeedback}'
            : '${report.totalFeedback} - ${report.averageRating.toStringAsFixed(1)} avg',
      ),
    ];

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3.6,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) => _CoverageTile(item: items[index]),
    );
  }
}

class _CoverageTile extends StatelessWidget {
  const _CoverageTile({required this.item});

  final _CoverageItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: ProvincialAdminColors.blue, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${item.value}\n',
                    style: const TextStyle(
                      color: ProvincialAdminColors.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  TextSpan(
                    text: item.label,
                    style: const TextStyle(
                      color: ProvincialAdminColors.muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      height: 1.4,
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

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0.0 : value / total;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: ProvincialAdminColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '$value - ${(percent * 100).round()}%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: percent.clamp(.04, 1),
            minHeight: 8,
            color: color,
            backgroundColor: const Color(0xFFEAF2FF),
          ),
        ),
      ],
    );
  }
}

class _ExportTab extends StatelessWidget {
  const _ExportTab({
    required this.cityOptions,
    required this.config,
    required this.preview,
    required this.isExporting,
    required this.onTypeChanged,
    required this.onCityChanged,
    required this.onDatePresetChanged,
    required this.onPickCustomRange,
    required this.onSectionChanged,
    required this.onGeneratePreview,
    required this.onExportPdf,
  });

  final List<String> cityOptions;
  final _ReportConfig config;
  final _ReportSnapshot? preview;
  final bool isExporting;
  final ValueChanged<_ProvinceReportType> onTypeChanged;
  final ValueChanged<String?> onCityChanged;
  final ValueChanged<_ReportDatePreset> onDatePresetChanged;
  final VoidCallback onPickCustomRange;
  final void Function(_ReportSection section, bool selected) onSectionChanged;
  final VoidCallback onGeneratePreview;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 410,
          child: _DashboardCard(
            title: 'PDF Report Builder',
            subtitle: 'Customize one formal report at a time.',
            icon: Icons.tune_rounded,
            color: ProvincialAdminColors.deepBlue,
            child: _ExportControls(
              cityOptions: cityOptions,
              config: config,
              isExporting: isExporting,
              onTypeChanged: onTypeChanged,
              onCityChanged: onCityChanged,
              onDatePresetChanged: onDatePresetChanged,
              onPickCustomRange: onPickCustomRange,
              onSectionChanged: onSectionChanged,
              onGeneratePreview: onGeneratePreview,
              onExportPdf: onExportPdf,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DashboardCard(
            title: 'Export Preview',
            subtitle: 'Preview the generated report before exporting.',
            icon: Icons.article_rounded,
            color: ProvincialAdminColors.green,
            child: preview == null
                ? const _EmptyBox(
                    icon: Icons.preview_rounded,
                    title: 'No preview generated yet.',
                    message:
                        'Choose filters, then select Generate Preview to review the report.',
                  )
                : _ExportPreview(report: preview!),
          ),
        ),
      ],
    );
  }
}

class _ExportControls extends StatelessWidget {
  const _ExportControls({
    required this.cityOptions,
    required this.config,
    required this.isExporting,
    required this.onTypeChanged,
    required this.onCityChanged,
    required this.onDatePresetChanged,
    required this.onPickCustomRange,
    required this.onSectionChanged,
    required this.onGeneratePreview,
    required this.onExportPdf,
  });

  final List<String> cityOptions;
  final _ReportConfig config;
  final bool isExporting;
  final ValueChanged<_ProvinceReportType> onTypeChanged;
  final ValueChanged<String?> onCityChanged;
  final ValueChanged<_ReportDatePreset> onDatePresetChanged;
  final VoidCallback onPickCustomRange;
  final void Function(_ReportSection section, bool selected) onSectionChanged;
  final VoidCallback onGeneratePreview;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel('Report Type'),
        _ReportDropdown<_ProvinceReportType>(
          value: config.type,
          items: _ProvinceReportType.values
              .map(
                (item) =>
                    DropdownMenuItem(value: item, child: Text(item.label)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onTypeChanged(value);
          },
        ),
        const SizedBox(height: 10),
        _FieldLabel('City/Subtenant'),
        _ReportDropdown<String>(
          value: config.city,
          items: cityOptions
              .map((city) => DropdownMenuItem(value: city, child: Text(city)))
              .toList(),
          onChanged: onCityChanged,
        ),
        const SizedBox(height: 10),
        _FieldLabel('Date Range'),
        _ReportDropdown<_ReportDatePreset>(
          value: config.datePreset,
          items: _ReportDatePreset.values
              .map(
                (item) =>
                    DropdownMenuItem(value: item, child: Text(item.label)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onDatePresetChanged(value);
          },
        ),
        if (config.datePreset == _ReportDatePreset.custom) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPickCustomRange,
            style: _outlinedButtonStyle,
            icon: const Icon(Icons.date_range_rounded, size: 17),
            label: Text(config.resolveWindow(DateTime.now()).label),
          ),
        ],
        const SizedBox(height: 12),
        _FieldLabel('Included Sections'),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: _ReportSection.values.map((section) {
                final selected = config.sections.contains(section);
                return FilterChip(
                  selected: selected,
                  visualDensity: VisualDensity.compact,
                  label: Text(section.label),
                  onSelected: (value) => onSectionChanged(section, value),
                  selectedColor: ProvincialAdminColors.blue.withValues(
                    alpha: .13,
                  ),
                  checkmarkColor: ProvincialAdminColors.deepBlue,
                  side: BorderSide(
                    color: selected
                        ? ProvincialAdminColors.blue.withValues(alpha: .35)
                        : ProvincialAdminColors.line,
                  ),
                  labelStyle: TextStyle(
                    color: selected
                        ? ProvincialAdminColors.deepBlue
                        : ProvincialAdminColors.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onGeneratePreview,
                style: _primaryButtonStyle,
                icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                label: const Text('Generate Preview'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 52,
              height: 46,
              child: OutlinedButton(
                onPressed: isExporting ? null : onExportPdf,
                style: _iconButtonStyle,
                child: isExporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 20),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ExportPreview extends StatelessWidget {
  const _ExportPreview({required this.report});

  final _ReportSnapshot report;

  @override
  Widget build(BuildContext context) {
    final tables = _tablesForReport(report);
    final table = tables.isEmpty ? null : tables.first;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: ProvincialAdminColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ProvincialAdminColors.blue.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.account_balance_rounded,
                  color: ProvincialAdminColors.deepBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'TourisTrike / Bulacan Provincial Tourism\n',
                        style: TextStyle(
                          color: ProvincialAdminColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          height: 1.35,
                        ),
                      ),
                      TextSpan(
                        text:
                            '${report.title} - ${report.config.city} - ${report.window.shortLabel}',
                        style: const TextStyle(
                          color: ProvincialAdminColors.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
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
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 74,
          child: Row(
            children: report.metrics.take(3).map((metric) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _MiniMetric(item: metric),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: table == null
              ? const _EmptyBox(
                  icon: Icons.table_rows_rounded,
                  title: 'No preview table available.',
                  message:
                      'The PDF will still include the selected summary sections.',
                )
              : _CompactTable(table: table, maxRows: 4),
        ),
        if (tables.length > 1) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${tables.length - 1} additional table section(s) will be included in the PDF.',
              style: const TextStyle(
                color: ProvincialAdminColors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.item});

  final _SummaryMetric item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${item.value}\n',
              style: const TextStyle(
                color: ProvincialAdminColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
            TextSpan(
              text: item.label,
              style: const TextStyle(
                color: ProvincialAdminColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _CompactTable extends StatelessWidget {
  const _CompactTable({required this.table, this.maxRows = 6});

  final _ReportTable table;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    if (table.rows.isEmpty) {
      return _EmptyBox(
        icon: Icons.inbox_rounded,
        title: table.emptyMessage,
        message: 'Try another date range or city/subtenant.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 42,
                dataRowMinHeight: 42,
                dataRowMaxHeight: 48,
                columnSpacing: 24,
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF1F7FF),
                ),
                headingTextStyle: const TextStyle(
                  color: ProvincialAdminColors.deepBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
                dataTextStyle: const TextStyle(
                  color: ProvincialAdminColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                columns: table.columns
                    .map((column) => DataColumn(label: Text(column)))
                    .toList(),
                rows: table.rows.take(maxRows).map((row) {
                  return DataRow(
                    cells: row
                        .map(
                          (cell) => DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 210),
                              child: Text(
                                cell,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        if (table.rows.length > maxRows) ...[
          const SizedBox(height: 8),
          Text(
            '${table.rows.length - maxRows} more row(s) available in export.',
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _RankedRows extends StatelessWidget {
  const _RankedRows({required this.rows});

  final Map<String, int> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyBox(
        icon: Icons.bar_chart_rounded,
        title: 'No records found.',
        message: 'Data will appear when city tenants submit records.',
      );
    }

    final entries = rows.entries.take(6).toList();
    final max = entries.first.value == 0 ? 1 : entries.first.value;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: entries.map((entry) {
        final index = entries.indexOf(entry);
        final factor = entry.value / max;
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == entries.length - 1 ? 0 : 10,
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
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
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${entry.value}',
                          style: const TextStyle(
                            color: ProvincialAdminColors.amber,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: factor.clamp(.05, 1),
                        minHeight: 8,
                        color: ProvincialAdminColors.amber,
                        backgroundColor: const Color(0xFFEAF2FF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: ProvincialAdminColors.lightMuted.withValues(alpha: .78),
            size: 30,
          ),
          const SizedBox(height: 9),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ProvincialAdminColors.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: ProvincialAdminColors.text,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ReportDropdown<T> extends StatelessWidget {
  const _ReportDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      items: items,
      onChanged: onChanged,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF8FBFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: ProvincialAdminColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(
            color: ProvincialAdminColors.blue,
            width: 1.2,
          ),
        ),
      ),
      style: const TextStyle(
        color: ProvincialAdminColors.text,
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

enum _ReportsTab {
  overview,
  bookings,
  revenue,
  packages,
  spots,
  drivers,
  feedback,
  export,
}

extension _ReportsTabLabel on _ReportsTab {
  String get label {
    switch (this) {
      case _ReportsTab.overview:
        return 'Overview';
      case _ReportsTab.bookings:
        return 'Bookings';
      case _ReportsTab.revenue:
        return 'Revenue';
      case _ReportsTab.packages:
        return 'Packages';
      case _ReportsTab.spots:
        return 'Tourist Spots';
      case _ReportsTab.drivers:
        return 'Drivers';
      case _ReportsTab.feedback:
        return 'Feedback';
      case _ReportsTab.export:
        return 'Export';
    }
  }

  IconData get icon {
    switch (this) {
      case _ReportsTab.overview:
        return Icons.dashboard_rounded;
      case _ReportsTab.bookings:
        return Icons.receipt_long_rounded;
      case _ReportsTab.revenue:
        return Icons.payments_rounded;
      case _ReportsTab.packages:
        return Icons.inventory_2_rounded;
      case _ReportsTab.spots:
        return Icons.place_rounded;
      case _ReportsTab.drivers:
        return Icons.directions_bike_rounded;
      case _ReportsTab.feedback:
        return Icons.forum_rounded;
      case _ReportsTab.export:
        return Icons.picture_as_pdf_rounded;
    }
  }

  _ProvinceReportType? get reportType {
    switch (this) {
      case _ReportsTab.overview:
        return _ProvinceReportType.overview;
      case _ReportsTab.bookings:
        return _ProvinceReportType.booking;
      case _ReportsTab.revenue:
        return _ProvinceReportType.revenue;
      case _ReportsTab.packages:
        return _ProvinceReportType.packagePerformance;
      case _ReportsTab.spots:
        return _ProvinceReportType.spotPerformance;
      case _ReportsTab.drivers:
        return _ProvinceReportType.driverPerformance;
      case _ReportsTab.feedback:
        return _ProvinceReportType.feedbackRatings;
      case _ReportsTab.export:
        return null;
    }
  }
}

enum _ProvinceReportType {
  overview,
  booking,
  revenue,
  packagePerformance,
  spotPerformance,
  driverPerformance,
  feedbackRatings,
  cancellation,
}

extension _ProvinceReportTypeLabel on _ProvinceReportType {
  String get label {
    switch (this) {
      case _ProvinceReportType.overview:
        return 'Overview Report';
      case _ProvinceReportType.booking:
        return 'Booking Report';
      case _ProvinceReportType.revenue:
        return 'Revenue Report';
      case _ProvinceReportType.packagePerformance:
        return 'Package Performance Report';
      case _ProvinceReportType.spotPerformance:
        return 'Tourist Spot Performance Report';
      case _ProvinceReportType.driverPerformance:
        return 'Driver Performance Report';
      case _ProvinceReportType.feedbackRatings:
        return 'Feedback and Ratings Report';
      case _ProvinceReportType.cancellation:
        return 'Cancellation Report';
    }
  }
}

enum _ReportDatePreset { daily, weekly, monthly, yearly, custom }

extension _ReportDatePresetLabel on _ReportDatePreset {
  String get label {
    switch (this) {
      case _ReportDatePreset.daily:
        return 'Daily';
      case _ReportDatePreset.weekly:
        return 'Weekly';
      case _ReportDatePreset.monthly:
        return 'Monthly';
      case _ReportDatePreset.yearly:
        return 'Yearly';
      case _ReportDatePreset.custom:
        return 'Custom Date Range';
    }
  }
}

enum _ReportSection {
  summaryCards,
  charts,
  tables,
  revenueData,
  bookingData,
  packageData,
  touristSpotData,
  driverData,
  feedbackData,
}

extension _ReportSectionLabel on _ReportSection {
  String get label {
    switch (this) {
      case _ReportSection.summaryCards:
        return 'Summary cards';
      case _ReportSection.charts:
        return 'Charts';
      case _ReportSection.tables:
        return 'Tables';
      case _ReportSection.revenueData:
        return 'Revenue data';
      case _ReportSection.bookingData:
        return 'Booking data';
      case _ReportSection.packageData:
        return 'Package data';
      case _ReportSection.touristSpotData:
        return 'Tourist spot data';
      case _ReportSection.driverData:
        return 'Driver data';
      case _ReportSection.feedbackData:
        return 'Feedback data';
    }
  }
}

class _ReportConfig {
  const _ReportConfig({
    required this.type,
    required this.city,
    required this.datePreset,
    required this.customRange,
    required this.sections,
  });

  final _ProvinceReportType type;
  final String city;
  final _ReportDatePreset datePreset;
  final DateTimeRange? customRange;
  final Set<_ReportSection> sections;

  _DateWindow resolveWindow(DateTime now) {
    DateTime start;
    DateTime end;
    String label;
    String shortLabel;

    switch (datePreset) {
      case _ReportDatePreset.daily:
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        shortLabel = 'Today';
        label = 'Daily - ${_date(start)}';
      case _ReportDatePreset.weekly:
        start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - 1));
        end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        shortLabel = 'This Week';
        label = 'Weekly - ${_date(start)} to ${_date(end)}';
      case _ReportDatePreset.monthly:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
        shortLabel = DateFormat.yMMMM().format(start);
        label = 'Monthly - $shortLabel';
      case _ReportDatePreset.yearly:
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, 12, 31, 23, 59, 59, 999);
        shortLabel = '${now.year}';
        label = 'Yearly - $shortLabel';
      case _ReportDatePreset.custom:
        final range =
            customRange ??
            DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
        start = DateTime(range.start.year, range.start.month, range.start.day);
        end = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
          23,
          59,
          59,
          999,
        );
        shortLabel = '${_date(start)} to ${_date(end)}';
        label = 'Custom - $shortLabel';
    }

    return _DateWindow(
      start: start,
      end: end,
      label: label,
      shortLabel: shortLabel,
    );
  }
}

class _DateWindow {
  const _DateWindow({
    required this.start,
    required this.end,
    required this.label,
    required this.shortLabel,
  });

  final DateTime start;
  final DateTime end;
  final String label;
  final String shortLabel;

  bool contains(DateTime? date) {
    if (date == null) return false;
    return !date.isBefore(start) && !date.isAfter(end);
  }
}

class _ReportSnapshot {
  const _ReportSnapshot({
    required this.config,
    required this.generatedAt,
    required this.window,
    required this.title,
    required this.metrics,
    required this.cityRows,
    required this.tenants,
    required this.packages,
    required this.spots,
    required this.bookings,
    required this.feedback,
    required this.totalBookings,
    required this.completedBookings,
    required this.cancelledBookings,
    required this.totalRevenue,
    required this.totalPackages,
    required this.totalSpots,
    required this.totalDrivers,
    required this.totalFeedback,
    required this.averageRating,
  });

  final _ReportConfig config;
  final DateTime generatedAt;
  final _DateWindow window;
  final String title;
  final List<_SummaryMetric> metrics;
  final List<_CityPerformanceRow> cityRows;
  final List<CityTenant> tenants;
  final List<ProvincePackage> packages;
  final List<ProvinceSpot> spots;
  final List<ProvinceBooking> bookings;
  final List<ProvinceFeedback> feedback;
  final int totalBookings;
  final int completedBookings;
  final int cancelledBookings;
  final double totalRevenue;
  final int totalPackages;
  final int totalSpots;
  final int totalDrivers;
  final int totalFeedback;
  final double averageRating;
}

class _SummaryMetric {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color color;
}

class _CityPerformanceRow {
  const _CityPerformanceRow({
    required this.city,
    required this.bookings,
    required this.completed,
    required this.cancelled,
    required this.revenue,
    required this.packages,
    required this.spots,
    required this.drivers,
    required this.feedbackCount,
    required this.averageRating,
  });

  final String city;
  final int bookings;
  final int completed;
  final int cancelled;
  final double revenue;
  final int packages;
  final int spots;
  final int drivers;
  final int feedbackCount;
  final double averageRating;
}

class _ReportTable {
  const _ReportTable({
    required this.title,
    required this.subtitle,
    required this.columns,
    required this.rows,
    required this.emptyMessage,
  });

  final String title;
  final String subtitle;
  final List<String> columns;
  final List<List<String>> rows;
  final String emptyMessage;
}

class _CoverageItem {
  const _CoverageItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _MutableReportStats {
  int count = 0;
  double amount = 0;
}

class _PackageReportRow {
  const _PackageReportRow({
    required this.title,
    required this.city,
    required this.status,
    required this.bookings,
    required this.revenue,
    this.budget = 0,
  });

  final String title;
  final String city;
  final String status;
  final int bookings;
  final double revenue;
  final double budget;
}

List<_ReportTable> _tablesForReport(_ReportSnapshot report) {
  if (!report.config.sections.contains(_ReportSection.tables)) {
    return const [];
  }

  bool wants(_ReportSection section) =>
      report.config.sections.contains(section);

  switch (report.config.type) {
    case _ProvinceReportType.overview:
      return [
        _cityPerformanceTable(report.cityRows),
        if (wants(_ReportSection.bookingData))
          _bookingStatusTable(report.bookings),
        if (wants(_ReportSection.revenueData))
          _revenueByCityTable(report.cityRows),
      ];
    case _ProvinceReportType.booking:
      return wants(_ReportSection.bookingData)
          ? [
              _bookingTable(report.bookings),
              _bookingStatusTable(report.bookings),
            ]
          : const [];
    case _ProvinceReportType.revenue:
      return wants(_ReportSection.revenueData)
          ? [_revenueByCityTable(report.cityRows), _packageRevenueTable(report)]
          : const [];
    case _ProvinceReportType.packagePerformance:
      return wants(_ReportSection.packageData)
          ? [_packagePerformanceTable(report)]
          : const [];
    case _ProvinceReportType.spotPerformance:
      return wants(_ReportSection.touristSpotData)
          ? [_spotCityTable(report), _topSpotTable(report.spots)]
          : const [];
    case _ProvinceReportType.driverPerformance:
      return wants(_ReportSection.driverData)
          ? [_driverCoverageTable(report)]
          : const [];
    case _ProvinceReportType.feedbackRatings:
      return wants(_ReportSection.feedbackData)
          ? [
              _feedbackCityTable(report.cityRows),
              _recentFeedbackTable(report.feedback),
            ]
          : const [];
    case _ProvinceReportType.cancellation:
      return wants(_ReportSection.bookingData)
          ? [
              _cancellationSummaryTable(report.cityRows),
              _cancelledBookingsTable(report.bookings),
            ]
          : const [];
  }
}

_ReportTable _cityPerformanceTable(List<_CityPerformanceRow> rows) {
  return _ReportTable(
    title: 'City Performance Summary',
    subtitle: 'Bookings, revenue, assets, drivers, and feedback by LGU.',
    columns: const [
      'City/Subtenant',
      'Bookings',
      'Completed',
      'Revenue',
      'Packages',
      'Spots',
      'Drivers',
      'Rating',
    ],
    rows: rows
        .map(
          (row) => [
            row.city,
            '${row.bookings}',
            '${row.completed}',
            _money(row.revenue),
            '${row.packages}',
            '${row.spots}',
            '${row.drivers}',
            row.averageRating == 0
                ? 'N/A'
                : row.averageRating.toStringAsFixed(1),
          ],
        )
        .toList(),
    emptyMessage: 'No city performance records found.',
  );
}

_ReportTable _bookingTable(List<ProvinceBooking> bookings) {
  final rows = [...bookings]
    ..sort((a, b) {
      final left = a.travelDate ?? a.createdAt ?? DateTime(1900);
      final right = b.travelDate ?? b.createdAt ?? DateTime(1900);
      return right.compareTo(left);
    });

  return _ReportTable(
    title: 'Booking Transactions',
    subtitle: 'Recent booking records for the selected period.',
    columns: const ['Date', 'City', 'Tourist', 'Package', 'Status', 'Amount'],
    rows: rows
        .map(
          (booking) => [
            _date(booking.travelDate ?? booking.createdAt),
            booking.city,
            booking.touristName,
            booking.packageTitle,
            adminTitleCase(booking.status),
            _money(booking.totalAmount),
          ],
        )
        .toList(),
    emptyMessage: 'No bookings matched this view.',
  );
}

_ReportTable _bookingStatusTable(List<ProvinceBooking> bookings) {
  final counts = <String, int>{};
  for (final booking in bookings) {
    final status = booking.status.trim().isEmpty ? 'pending' : booking.status;
    counts.update(status, (value) => value + 1, ifAbsent: () => 1);
  }
  final rows = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return _ReportTable(
    title: 'Booking Status Distribution',
    subtitle: 'Summarized booking outcomes.',
    columns: const ['Status', 'Count', 'Share'],
    rows: rows
        .map(
          (entry) => [
            adminTitleCase(entry.key),
            '${entry.value}',
            _percent(entry.value, bookings.length),
          ],
        )
        .toList(),
    emptyMessage: 'No booking status data available.',
  );
}

_ReportTable _revenueByCityTable(List<_CityPerformanceRow> rows) {
  final revenueRows =
      rows.where((row) => row.revenue > 0 || row.completed > 0).toList()
        ..sort((a, b) => b.revenue.compareTo(a.revenue));

  return _ReportTable(
    title: 'Revenue by City/Subtenant',
    subtitle: 'Completed booking value grouped by LGU.',
    columns: const ['City/Subtenant', 'Completed', 'Revenue', 'Avg. Value'],
    rows: revenueRows
        .map(
          (row) => [
            row.city,
            '${row.completed}',
            _money(row.revenue),
            row.completed == 0
                ? _money(0)
                : _money(row.revenue / row.completed),
          ],
        )
        .toList(),
    emptyMessage: 'No completed booking revenue found.',
  );
}

_ReportTable _packageRevenueTable(_ReportSnapshot report) {
  final stats = _packageStats(report.bookings, completedOnly: true);
  final rows = report.packages.map((item) {
    final stat =
        stats[_packageKey(item.id, item.title)] ?? _MutableReportStats();
    return _PackageReportRow(
      title: item.title,
      city: item.city,
      status: item.status,
      bookings: stat.count,
      revenue: stat.amount,
    );
  }).toList()..sort((a, b) => b.revenue.compareTo(a.revenue));

  return _ReportTable(
    title: 'Package Revenue Performance',
    subtitle: 'Completed revenue by package.',
    columns: const ['Package', 'City', 'Bookings', 'Revenue', 'Status'],
    rows: rows
        .where((row) => row.revenue > 0 || row.bookings > 0)
        .map(
          (row) => [
            row.title,
            row.city,
            '${row.bookings}',
            _money(row.revenue),
            adminTitleCase(row.status),
          ],
        )
        .toList(),
    emptyMessage: 'No package revenue found.',
  );
}

_ReportTable _packagePerformanceTable(_ReportSnapshot report) {
  final stats = _packageStats(report.bookings);
  final rows = report.packages.map((item) {
    final stat =
        stats[_packageKey(item.id, item.title)] ?? _MutableReportStats();
    return _PackageReportRow(
      title: item.title,
      city: item.city,
      status: item.status,
      bookings: stat.count,
      revenue: stat.amount,
      budget: item.estimatedBudget,
    );
  }).toList()..sort((a, b) => b.bookings.compareTo(a.bookings));

  return _ReportTable(
    title: 'Package Performance',
    subtitle: 'Booking activity and completed revenue by package.',
    columns: const [
      'Package',
      'City',
      'Bookings',
      'Revenue',
      'Budget',
      'Status',
    ],
    rows: rows
        .map(
          (row) => [
            row.title,
            row.city,
            '${row.bookings}',
            _money(row.revenue),
            row.budget == 0 ? 'N/A' : _money(row.budget),
            adminTitleCase(row.status),
          ],
        )
        .toList(),
    emptyMessage: 'No package records found.',
  );
}

_ReportTable _spotCityTable(_ReportSnapshot report) {
  return _ReportTable(
    title: 'Tourist Spot Inventory by City',
    subtitle: 'Submitted and verified tourist spots by LGU.',
    columns: const ['City/Subtenant', 'Spots', 'Verified', 'Avg. Rating'],
    rows: report.cityRows.where((row) => row.spots > 0).map((row) {
      final citySpots = report.spots.where(
        (spot) => _sameCity(spot.city, row.city),
      );
      final verified = citySpots.where((spot) {
        final status = spot.verificationStatus.toLowerCase();
        return status == 'verified' || status == 'approved';
      }).length;
      final ratings = citySpots.where((spot) => spot.rating > 0).toList();
      final avg = ratings.isEmpty
          ? 0.0
          : ratings.fold<double>(0, (sum, spot) => sum + spot.rating) /
                ratings.length;
      return [
        row.city,
        '${row.spots}',
        '$verified',
        avg == 0 ? 'N/A' : avg.toStringAsFixed(1),
      ];
    }).toList(),
    emptyMessage: 'No tourist spot inventory found.',
  );
}

_ReportTable _topSpotTable(List<ProvinceSpot> spots) {
  final rows = [...spots]..sort((a, b) => b.rating.compareTo(a.rating));
  return _ReportTable(
    title: 'Tourist Spot Performance',
    subtitle: 'Spot records sorted by available rating.',
    columns: const ['Tourist Spot', 'City', 'Barangay', 'Rating', 'Status'],
    rows: rows
        .map(
          (spot) => [
            spot.title,
            spot.city,
            spot.barangay.isEmpty ? 'N/A' : spot.barangay,
            spot.rating == 0 ? 'N/A' : spot.rating.toStringAsFixed(1),
            adminTitleCase(spot.verificationStatus),
          ],
        )
        .toList(),
    emptyMessage: 'No tourist spot records found.',
  );
}

_ReportTable _driverCoverageTable(_ReportSnapshot report) {
  return _ReportTable(
    title: 'Driver Coverage by City/Subtenant',
    subtitle: 'Registered driver counts and city context.',
    columns: const [
      'City/Subtenant',
      'Admin Office',
      'Drivers',
      'Bookings',
      'Packages',
      'Status',
    ],
    rows: report.tenants.map((tenant) {
      final cityRow = report.cityRows.where(
        (row) => _sameCity(row.city, tenant.city),
      );
      final bookings = cityRow.isEmpty
          ? tenant.bookingsCount
          : cityRow.first.bookings;
      return [
        tenant.city,
        tenant.adminName,
        '${tenant.driversCount}',
        '$bookings',
        '${tenant.packagesCount}',
        adminTitleCase(tenant.status),
      ];
    }).toList(),
    emptyMessage: 'No driver coverage records found.',
  );
}

_ReportTable _feedbackCityTable(List<_CityPerformanceRow> rows) {
  final feedbackRows = rows.where((row) => row.feedbackCount > 0).toList()
    ..sort((a, b) => b.feedbackCount.compareTo(a.feedbackCount));

  return _ReportTable(
    title: 'Feedback and Ratings by City',
    subtitle: 'Review volume and average rating by LGU.',
    columns: const ['City/Subtenant', 'Feedback', 'Avg. Rating', 'Bookings'],
    rows: feedbackRows
        .map(
          (row) => [
            row.city,
            '${row.feedbackCount}',
            row.averageRating == 0
                ? 'N/A'
                : row.averageRating.toStringAsFixed(1),
            '${row.bookings}',
          ],
        )
        .toList(),
    emptyMessage: 'No feedback records found.',
  );
}

_ReportTable _recentFeedbackTable(List<ProvinceFeedback> feedback) {
  final rows = [...feedback]
    ..sort((a, b) {
      final left = a.createdAt ?? DateTime(1900);
      final right = b.createdAt ?? DateTime(1900);
      return right.compareTo(left);
    });

  return _ReportTable(
    title: 'Recent Feedback Details',
    subtitle: 'Latest tourist comments and rating subjects.',
    columns: const ['Date', 'City', 'Reviewer', 'Subject', 'Rating', 'Comment'],
    rows: rows
        .map(
          (item) => [
            _date(item.createdAt),
            item.city,
            item.reviewerName,
            item.subjectName,
            item.rating == 0 ? 'N/A' : item.rating.toStringAsFixed(1),
            _shortText(item.comment, 64),
          ],
        )
        .toList(),
    emptyMessage: 'No feedback details found.',
  );
}

_ReportTable _cancellationSummaryTable(List<_CityPerformanceRow> rows) {
  final cancellationRows = rows.where((row) => row.cancelled > 0).toList()
    ..sort((a, b) => b.cancelled.compareTo(a.cancelled));

  return _ReportTable(
    title: 'Cancellation Summary by City',
    subtitle: 'Cancelled booking counts by LGU.',
    columns: const ['City/Subtenant', 'Cancelled', 'Bookings', 'Rate'],
    rows: cancellationRows
        .map(
          (row) => [
            row.city,
            '${row.cancelled}',
            '${row.bookings}',
            _percent(row.cancelled, row.bookings),
          ],
        )
        .toList(),
    emptyMessage: 'No cancellations found.',
  );
}

_ReportTable _cancelledBookingsTable(List<ProvinceBooking> bookings) {
  final rows =
      bookings
          .where((booking) => booking.status.toLowerCase() == 'cancelled')
          .toList()
        ..sort((a, b) {
          final left = a.travelDate ?? a.createdAt ?? DateTime(1900);
          final right = b.travelDate ?? b.createdAt ?? DateTime(1900);
          return right.compareTo(left);
        });

  return _ReportTable(
    title: 'Cancelled Booking Records',
    subtitle: 'Cancelled transactions and estimated booking value.',
    columns: const ['Date', 'City', 'Tourist', 'Package', 'Amount'],
    rows: rows
        .map(
          (booking) => [
            _date(booking.travelDate ?? booking.createdAt),
            booking.city,
            booking.touristName,
            booking.packageTitle,
            _money(booking.totalAmount),
          ],
        )
        .toList(),
    emptyMessage: 'No cancelled booking records found.',
  );
}

_ReportTable _chartDataTable(_ReportSnapshot report) {
  return _ReportTable(
    title: 'Chart Data Summary',
    subtitle: 'Tabular source data for chart sections.',
    columns: const [
      'City/Subtenant',
      'Bookings',
      'Revenue',
      'Packages',
      'Spots',
    ],
    rows: report.cityRows
        .map(
          (row) => [
            row.city,
            '${row.bookings}',
            _money(row.revenue),
            '${row.packages}',
            '${row.spots}',
          ],
        )
        .toList(),
    emptyMessage: 'No chart source data found.',
  );
}

Map<String, int> _countPackagesByCity(List<ProvincePackage> rows) {
  final counts = <String, int>{};
  for (final item in rows) {
    final city = item.city.trim().isEmpty ? 'Unassigned' : item.city;
    counts.update(city, (value) => value + 1, ifAbsent: () => 1);
  }
  return _sortedMap(counts);
}

Map<String, int> _countDriversByCity(List<CityTenant> rows) {
  final counts = <String, int>{};
  for (final item in rows) {
    final city = item.city.trim().isEmpty ? 'Unassigned' : item.city;
    counts[city] = item.driversCount;
  }
  return _sortedMap(counts);
}

Map<String, int> _sortedMap(Map<String, int> source) {
  final entries = source.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {for (final entry in entries) entry.key: entry.value};
}

Map<String, _MutableReportStats> _packageStats(
  List<ProvinceBooking> bookings, {
  bool completedOnly = false,
}) {
  final stats = <String, _MutableReportStats>{};
  for (final booking in bookings) {
    if (completedOnly && booking.status.toLowerCase() != 'completed') continue;
    final key = _packageKey(booking.packageId, booking.packageTitle);
    final stat = stats.putIfAbsent(key, () => _MutableReportStats());
    stat.count++;
    if (booking.status.toLowerCase() == 'completed') {
      stat.amount += booking.totalAmount;
    }
  }
  return stats;
}

String _money(num value) {
  return NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0).format(value);
}

String _date(DateTime? value) {
  if (value == null) return 'N/A';
  return DateFormat.yMMMd().format(value);
}

String _percent(int value, int total) {
  if (total <= 0) return '0%';
  return '${((value / total) * 100).round()}%';
}

String _normalize(String value) => value.trim().toLowerCase();

bool _sameCity(String left, String right) =>
    _normalize(left) == _normalize(right);

String _packageKey(dynamic id, String title) {
  final value = adminId(id).trim();
  if (value.isNotEmpty) return value;
  return 'title:${_normalize(title)}';
}

String _shortText(String value, int maxLength) {
  final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.isEmpty) return 'N/A';
  if (clean.length <= maxLength) return clean;
  return '${clean.substring(0, maxLength - 3)}...';
}

String _slug(String value) {
  final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return normalized.replaceAll(RegExp(r'^-+|-+$'), '');
}

ButtonStyle get _primaryButtonStyle {
  return ElevatedButton.styleFrom(
    backgroundColor: ProvincialAdminColors.deepBlue,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    textStyle: const TextStyle(fontWeight: FontWeight.w900),
  );
}

ButtonStyle get _outlinedButtonStyle {
  return OutlinedButton.styleFrom(
    foregroundColor: ProvincialAdminColors.deepBlue,
    side: const BorderSide(color: ProvincialAdminColors.line),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
  );
}

ButtonStyle get _iconButtonStyle {
  return OutlinedButton.styleFrom(
    foregroundColor: ProvincialAdminColors.deepBlue,
    side: const BorderSide(color: ProvincialAdminColors.line),
    padding: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
  );
}
