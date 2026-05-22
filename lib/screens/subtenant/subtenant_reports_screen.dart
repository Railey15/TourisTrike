import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_feedback_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

// ─── Extra accent colors ──────────────────────────────────────────────────────
const _stGreen  = Color(0xFF16A34A);
const _stAmber  = Color(0xFFF59E0B);
const _stPurple = Color(0xFF7C3AED);
const _stCyan   = Color(0xFF0EA5E9);
const _stRed    = Color(0xFFDC2626);

// ─── Enums ────────────────────────────────────────────────────────────────────
enum _STTab {
  overview('Overview',  Icons.dashboard_rounded),
  bookings('Bookings',  Icons.receipt_long_rounded),
  packages('Packages',  Icons.inventory_2_rounded),
  spots   ('Spots',     Icons.place_rounded),
  drivers ('Drivers',   Icons.badge_rounded),
  feedback('Feedback',  Icons.star_half_rounded),
  export  ('Export',    Icons.picture_as_pdf_rounded);

  const _STTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _STDatePreset {
  weekly  ('This Week'),
  monthly ('This Month'),
  yearly  ('This Year'),
  allTime ('All Time'),
  custom  ('Custom Range');

  const _STDatePreset(this.label);
  final String label;
}

enum _STReportType {
  summary     ('Summary'),
  detailed    ('Detailed'),
  bookingsOnly('Bookings Only');

  const _STReportType(this.label);
  final String label;
}

enum _STSection {
  overview('Overview'),
  bookings('Bookings'),
  packages('Packages'),
  spots   ('Tourist Spots'),
  drivers ('Drivers'),
  feedback('Feedback');

  const _STSection(this.label);
  final String label;
}

// ─── Data models ──────────────────────────────────────────────────────────────
class _FullLoad {
  const _FullLoad({required this.profile, required this.data});
  final SubTenantProfile profile;
  final SubTenantReportData data;
}

class _STDateWindow {
  const _STDateWindow({
    required this.start,
    required this.end,
    required this.label,
  });

  factory _STDateWindow.fromRange(SubTenantReportRange r) =>
      _STDateWindow(start: r.start, end: r.end, label: r.label);

  factory _STDateWindow.fromPreset(_STDatePreset p, [DateTimeRange? custom]) {
    final now = DateTime.now();
    switch (p) {
      case _STDatePreset.weekly:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return _STDateWindow(
          start: DateTime(monday.year, monday.month, monday.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
          label: 'This Week',
        );
      case _STDatePreset.monthly:
        return _STDateWindow(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
          label: 'This Month',
        );
      case _STDatePreset.yearly:
        return _STDateWindow(
          start: DateTime(now.year, 1, 1),
          end: DateTime(now.year, 12, 31, 23, 59, 59),
          label: 'This Year',
        );
      case _STDatePreset.allTime:
        return _STDateWindow(
          start: DateTime(2020),
          end: DateTime(now.year + 1),
          label: 'All Time',
        );
      case _STDatePreset.custom:
        if (custom != null) {
          return _STDateWindow(
            start: custom.start,
            end: DateTime(
              custom.end.year, custom.end.month, custom.end.day, 23, 59, 59,
            ),
            label: 'Custom Range',
          );
        }
        return _STDateWindow.fromPreset(_STDatePreset.monthly);
    }
  }

  final DateTime start;
  final DateTime end;
  final String label;

  bool contains(DateTime? dt) {
    if (dt == null) return false;
    return !dt.isBefore(start) && !dt.isAfter(end);
  }

  String get formatted =>
      '${DateFormat.yMMMd().format(start)} – ${DateFormat.yMMMd().format(end)}';
}

class _STSnapshot {
  const _STSnapshot({
    required this.city,
    required this.window,
    required this.totalBookings,
    required this.completedBookings,
    required this.cancelledBookings,
    required this.pendingBookings,
    required this.revenue,
    required this.totalPackages,
    required this.activePackages,
    required this.totalSpots,
    required this.activeSpots,
    required this.totalDrivers,
    required this.activeDrivers,
    required this.avgRating,
    required this.feedbackCount,
    required this.bookings,
    required this.feedback,
    required this.packages,
    required this.spots,
    required this.drivers,
  });

  final String city;
  final _STDateWindow window;
  final int totalBookings;
  final int completedBookings;
  final int cancelledBookings;
  final int pendingBookings;
  final double revenue;
  final int totalPackages;
  final int activePackages;
  final int totalSpots;
  final int activeSpots;
  final int totalDrivers;
  final int activeDrivers;
  final double avgRating;
  final int feedbackCount;
  final List<SubTenantBooking> bookings;
  final List<SubTenantFeedback> feedback;
  final List<SubTenantPackage> packages;
  final List<SubTenantSpot> spots;
  final List<SubTenantDriver> drivers;
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class SubTenantReportsScreen extends StatefulWidget {
  const SubTenantReportsScreen({super.key});

  @override
  State<SubTenantReportsScreen> createState() =>
      _SubTenantReportsScreenState();
}

class _SubTenantReportsScreenState extends State<SubTenantReportsScreen>
    with SingleTickerProviderStateMixin {
  final _service = SubTenantService();
  late Future<_FullLoad> _future;
  late TabController _tabController;

  SubTenantReportRange _range = SubTenantReportRange.currentMonth();

  _STReportType _exportType    = _STReportType.summary;
  _STDatePreset _exportPreset  = _STDatePreset.monthly;
  DateTimeRange? _customExport;
  final Set<_STSection> _exportSections = {..._STSection.values};
  _STSnapshot? _exportPreview;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _STTab.values.length, vsync: this);
    _future = _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<_FullLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final data    = await _service.fetchReports(profile);
    return _FullLoad(profile: profile, data: data);
  }

  void _reload() => setState(() => _future = _load());

  void _setRange(SubTenantReportRange r) =>
      setState(() { _range = r; _future = _load(); });

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _range.start, end: _range.end),
    );
    if (picked != null && mounted) {
      _setRange(SubTenantReportRange.custom(picked.start, picked.end));
    }
  }

  Future<void> _pickExportCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _customExport = picked;
        _exportPreset = _STDatePreset.custom;
        _exportPreview = null;
      });
    }
  }

  _STSnapshot _buildSnapshot(_FullLoad load, _STDateWindow win) {
    final d  = load.data;
    final bk = d.bookings.where((b) => win.contains(b.travelDate ?? b.createdAt)).toList();
    final fb = d.feedback.where((f) => win.contains(f.createdAt)).toList();

    final completed = bk.where((b) => b.status == 'completed').length;
    final cancelled = bk.where((b) => b.status == 'cancelled').length;
    final pending   = bk.length - completed - cancelled;
    final revenue   = bk
        .where((b) => b.status == 'completed')
        .fold<double>(0, (s, b) => s + b.totalAmount);
    final avgRating = fb.isEmpty
        ? 0.0
        : fb.fold<double>(0, (s, f) => s + f.rating) / fb.length;

    return _STSnapshot(
      city:              load.profile.assignedCity,
      window:            win,
      totalBookings:     bk.length,
      completedBookings: completed,
      cancelledBookings: cancelled,
      pendingBookings:   pending,
      revenue:           revenue,
      totalPackages:     d.allPackages.length,
      activePackages:    d.allPackages.where((p) => p.status == 'active').length,
      totalSpots:        d.allSpots.length,
      activeSpots:       d.allSpots.where((s) => s.status == 'active').length,
      totalDrivers:      d.allDrivers.length,
      activeDrivers:     d.allDrivers.where((dr) => dr.status == 'active').length,
      avgRating:         avgRating,
      feedbackCount:     fb.length,
      bookings:          bk,
      feedback:          fb,
      packages:          d.allPackages,
      spots:             d.allSpots,
      drivers:           d.allDrivers,
    );
  }

  void _generatePreview(_FullLoad load) {
    final win = _STDateWindow.fromPreset(_exportPreset, _customExport);
    setState(() => _exportPreview = _buildSnapshot(load, win));
  }

  Future<void> _exportPdf(_FullLoad load) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final win  = _STDateWindow.fromPreset(_exportPreset, _customExport);
      final snap = _buildSnapshot(load, win);
      final doc  = await _buildPdf(snap);
      final bytes = await doc.save();
      final fname = 'touristrike-${_slugify(snap.city)}-${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: fname);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<pw.Document> _buildPdf(_STSnapshot s) async {
    final doc   = pw.Document();
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);
    final accent = PdfColor.fromHex('#1E63E9');

    pw.Widget metricBox(String label, String value) => pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue100),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );

    pw.Widget tableBlock(String title, List<String> cols, List<List<String>> rows) {
      if (rows.isEmpty) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
            pw.SizedBox(height: 4),
            pw.Text('No data',
                style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
            pw.SizedBox(height: 14),
          ],
        );
      }
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: cols,
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: pw.BoxDecoration(color: accent),
            headerAlignment: pw.Alignment.centerLeft,
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 14),
        ],
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'TourisTrike Municipality Tourism Report',
              style: pw.TextStyle(
                  fontSize: 18, fontWeight: pw.FontWeight.bold, color: accent),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${s.city} – ${s.window.formatted}',
              style: const pw.TextStyle(
                  fontSize: 11, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: accent),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated by TourisTrike Municipality Admin – ${DateFormat.yMMMd().format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
        build: (ctx) {
          final items = <pw.Widget>[];

          if (_exportSections.contains(_STSection.overview)) {
            items.add(pw.Wrap(spacing: 8, runSpacing: 8, children: [
              metricBox('Total Bookings',  '${s.totalBookings}'),
              metricBox('Completed',       '${s.completedBookings}'),
              metricBox('Cancelled',       '${s.cancelledBookings}'),
              metricBox('Revenue',         money.format(s.revenue)),
              metricBox('Packages',        '${s.totalPackages}'),
              metricBox('Spots',           '${s.totalSpots}'),
              metricBox('Drivers',         '${s.totalDrivers}'),
              metricBox('Avg Rating',      s.avgRating.toStringAsFixed(1)),
            ]));
            items.add(pw.SizedBox(height: 14));
          }

          if (_exportSections.contains(_STSection.bookings) &&
              _exportType != _STReportType.summary) {
            items.add(tableBlock(
              'Bookings',
              ['Tourist', 'Package', 'Status', 'Amount', 'Date'],
              s.bookings.take(50).map((b) => [
                _shortText(b.touristName, 20),
                _shortText(b.packageTitle, 20),
                b.status,
                money.format(b.totalAmount),
                _dateStr(b.travelDate ?? b.createdAt),
              ]).toList(),
            ));
          }

          if (_exportSections.contains(_STSection.packages) &&
              _exportType == _STReportType.detailed) {
            items.add(tableBlock(
              'Packages',
              ['Title', 'Status', 'Budget'],
              s.packages.take(30).map((p) => [
                _shortText(p.title, 28),
                p.status,
                money.format(p.estimatedBudget),
              ]).toList(),
            ));
          }

          if (_exportSections.contains(_STSection.spots) &&
              _exportType == _STReportType.detailed) {
            items.add(tableBlock(
              'Tourist Spots',
              ['Name', 'Barangay', 'Status', 'Rating'],
              s.spots.take(30).map((sp) => [
                _shortText(sp.title, 25),
                sp.barangay,
                sp.status,
                sp.rating.toStringAsFixed(1),
              ]).toList(),
            ));
          }

          if (_exportSections.contains(_STSection.drivers) &&
              _exportType == _STReportType.detailed) {
            items.add(tableBlock(
              'Drivers',
              ['Name', 'Status', 'TODA', 'License'],
              s.drivers.take(30).map((dr) => [
                _shortText(dr.fullName, 22),
                dr.status,
                dr.todaName,
                dr.licenseNumber,
              ]).toList(),
            ));
          }

          if (_exportSections.contains(_STSection.feedback) &&
              _exportType == _STReportType.detailed) {
            items.add(tableBlock(
              'Feedback',
              ['Tourist', 'Driver', 'Rating', 'Comment', 'Date'],
              s.feedback.take(30).map((f) => [
                _shortText(f.touristName, 16),
                _shortText(f.driverName, 16),
                f.rating.toStringAsFixed(1),
                _shortText(f.comment, 32),
                _dateStr(f.createdAt),
              ]).toList(),
            ));
          }

          return items;
        },
      ),
    );

    return doc;
  }

  void _onRangeSelect(_STDatePreset p) {
    switch (p) {
      case _STDatePreset.weekly:
        _setRange(SubTenantReportRange.weekly());
      case _STDatePreset.monthly:
        _setRange(SubTenantReportRange.currentMonth());
      case _STDatePreset.yearly:
        _setRange(SubTenantReportRange.yearly());
      case _STDatePreset.allTime:
        _setRange(SubTenantReportRange.custom(DateTime(2020), DateTime.now()));
      case _STDatePreset.custom:
        _pickCustomRange();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: 5,
      title: 'Municipality Reports',
      subtitle: 'Tourism analytics for your assigned city.',
      child: FutureBuilder<_FullLoad>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: SubTenantColors.blue),
                  SizedBox(height: 16),
                  Text(
                    'Loading report data…',
                    style: TextStyle(color: SubTenantColors.muted, fontSize: 13),
                  ),
                ],
              ),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: _stRed, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    snap.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: SubTenantColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final load     = snap.data!;
          final window   = _STDateWindow.fromRange(_range);
          final snapshot = _buildSnapshot(load, window);

          return Column(
            children: [
              _ReportHero(
                snapshot: snapshot,
                onRangeSelect: _onRangeSelect,
              ),
              _MetricsStrip(snapshot: snapshot),
              _STTabBar(controller: _tabController),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _OverviewTab(snapshot: snapshot),
                    _BookingsTab(snapshot: snapshot),
                    _PackagesTab(snapshot: snapshot),
                    _SpotsTab(snapshot: snapshot),
                    _DriversTab(snapshot: snapshot),
                    _FeedbackTab(snapshot: snapshot),
                    _ExportTab(
                      exportType:     _exportType,
                      exportPreset:   _exportPreset,
                      exportSections: _exportSections,
                      preview:        _exportPreview,
                      isExporting:    _isExporting,
                      onTypeChange: (t) => setState(() {
                        _exportType    = t!;
                        _exportPreview = null;
                      }),
                      onPresetChange: (p) => setState(() {
                        _exportPreset  = p!;
                        _exportPreview = null;
                      }),
                      onPickCustom: _pickExportCustomRange,
                      onToggleSection: (s) => setState(() {
                        if (_exportSections.contains(s)) {
                          if (_exportSections.length > 1) {
                            _exportSections.remove(s);
                          }
                        } else {
                          _exportSections.add(s);
                        }
                        _exportPreview = null;
                      }),
                      onGeneratePreview: () => _generatePreview(load),
                      onExportPdf:        () => _exportPdf(load),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Hero ─────────────────────────────────────────────────────────────────────
class _ReportHero extends StatelessWidget {
  const _ReportHero({
    required this.snapshot,
    required this.onRangeSelect,
  });

  final _STSnapshot snapshot;
  final ValueChanged<_STDatePreset> onRangeSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 96,
      decoration: const BoxDecoration(gradient: SubTenantColors.gradient),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.location_city_rounded,
              color: Colors.white70, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  snapshot.city,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Municipality Tourism Report',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75), fontSize: 11),
                ),
              ],
            ),
          ),
          _HeroPill(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.receipt_long_rounded,
                    color: Colors.white, size: 12),
                const SizedBox(width: 4),
                Text(
                  '${snapshot.totalBookings} bookings',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<_STDatePreset>(
            onSelected: onRangeSelect,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            itemBuilder: (_) => _STDatePreset.values
                .map((p) => PopupMenuItem(
                    value: p, child: Text(p.label)))
                .toList(),
            child: _HeroPill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.window.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.expand_more,
                      color: Colors.white, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: child,
    );
  }
}

// ─── Metrics strip ────────────────────────────────────────────────────────────
class _MetricsStrip extends StatelessWidget {
  const _MetricsStrip({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);
    final metrics = [
      _Metric('Bookings',    '${snapshot.totalBookings}',            SubTenantColors.blue),
      _Metric('Completed',   '${snapshot.completedBookings}',        _stGreen),
      _Metric('Cancelled',   '${snapshot.cancelledBookings}',        _stRed),
      _Metric('Revenue',     money.format(snapshot.revenue),         _stPurple),
      _Metric('Avg Rating',  snapshot.avgRating.toStringAsFixed(1),  _stAmber),
      _Metric('Feedback',    '${snapshot.feedbackCount}',            _stCyan),
    ];

    return Container(
      height: 88,
      color: SubTenantColors.backgroundAlt,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: metrics
            .map((m) => Expanded(child: _MetricCard(m)))
            .toList(),
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.metric);
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: SubTenantColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.value,
            style: TextStyle(
              color: metric.color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            metric.label,
            style: const TextStyle(
              color: SubTenantColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab bar ──────────────────────────────────────────────────────────────────
class _STTabBar extends StatelessWidget {
  const _STTabBar({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: SubTenantColors.card,
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: SubTenantColors.deepBlue,
        labelColor: SubTenantColors.deepBlue,
        unselectedLabelColor: SubTenantColors.muted,
        indicatorWeight: 2.5,
        labelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700),
        tabs: _STTab.values
            .map((t) => Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t.icon, size: 14),
                      const SizedBox(width: 5),
                      Text(t.label),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ─── Overview tab ─────────────────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth > 640) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _BookingOutcomeCard(snapshot: snapshot)),
                  const SizedBox(width: 12),
                  Expanded(child: _CoverageSummaryCard(snapshot: snapshot)),
                ],
              );
            }
            return Column(children: [
              _BookingOutcomeCard(snapshot: snapshot),
              const SizedBox(height: 12),
              _CoverageSummaryCard(snapshot: snapshot),
            ]);
          }),
          const SizedBox(height: 12),
          _TopPackagesCard(snapshot: snapshot),
        ],
      ),
    );
  }
}

class _BookingOutcomeCard extends StatelessWidget {
  const _BookingOutcomeCard({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final total = snapshot.totalBookings;
    return _SectionCard(
      title: 'Booking Outcome',
      subtitle: '${snapshot.window.label} · $total total',
      child: total == 0
          ? const _EmptyBox(message: 'No bookings in this period.')
          : Column(children: [
              _ProgressRow(label: 'Completed',     value: snapshot.completedBookings, total: total, color: _stGreen),
              _ProgressRow(label: 'Cancelled',     value: snapshot.cancelledBookings, total: total, color: _stRed),
              _ProgressRow(label: 'Pending/Other', value: snapshot.pendingBookings,   total: total, color: _stAmber),
            ]),
    );
  }
}

class _CoverageSummaryCard extends StatelessWidget {
  const _CoverageSummaryCard({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Coverage Summary',
      subtitle: 'Assets registered in ${snapshot.city}',
      child: Column(children: [
        _CoverageTile(
          icon: Icons.inventory_2_rounded,
          label: 'Packages',
          active: snapshot.activePackages,
          total: snapshot.totalPackages,
          color: SubTenantColors.blue,
        ),
        _CoverageTile(
          icon: Icons.place_rounded,
          label: 'Tourist Spots',
          active: snapshot.activeSpots,
          total: snapshot.totalSpots,
          color: _stCyan,
        ),
        _CoverageTile(
          icon: Icons.badge_rounded,
          label: 'Drivers',
          active: snapshot.activeDrivers,
          total: snapshot.totalDrivers,
          color: _stPurple,
        ),
      ]),
    );
  }
}

class _CoverageTile extends StatelessWidget {
  const _CoverageTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.total,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int active;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label,
                        style: const TextStyle(
                          color: SubTenantColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        )),
                    Text('$active / $total active',
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: total == 0 ? 0 : active / total,
                  backgroundColor: SubTenantColors.line,
                  color: color,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopPackagesCard extends StatelessWidget {
  const _TopPackagesCard({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final b in snapshot.bookings) {
      final key = b.packageId?.toString();
      if (key != null && key.isNotEmpty) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }

    final sorted = List<SubTenantPackage>.from(snapshot.packages)
      ..sort((a, b) =>
          (counts[b.id?.toString() ?? ''] ?? 0)
              .compareTo(counts[a.id?.toString() ?? ''] ?? 0));
    final top = sorted.take(5).toList();

    var maxCount = 1;
    for (final p in top) {
      final c = counts[p.id?.toString() ?? ''] ?? 0;
      if (c > maxCount) maxCount = c;
    }

    return _SectionCard(
      title: 'Top Packages',
      subtitle: 'By booking count – ${snapshot.window.label}',
      child: top.isEmpty
          ? const _EmptyBox(message: 'No bookings to rank packages.')
          : Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  _RankedRow(
                    rank:  i + 1,
                    label: top[i].title,
                    count: counts[top[i].id?.toString() ?? ''] ?? 0,
                    max:   maxCount,
                    color: SubTenantColors.blue,
                  ),
              ],
            ),
    );
  }
}

class _RankedRow extends StatelessWidget {
  const _RankedRow({
    required this.rank,
    required this.label,
    required this.count,
    required this.max,
    required this.color,
  });

  final int rank;
  final String label;
  final int count;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              style: TextStyle(
                color: rank == 1 ? _stAmber : SubTenantColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(
                color: SubTenantColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: max == 0 ? 0 : count / max,
                backgroundColor: color.withValues(alpha: 0.1),
                color: color,
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bookings tab ─────────────────────────────────────────────────────────────
class _BookingsTab extends StatelessWidget {
  const _BookingsTab({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth > 640) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: _BookingTableCard(snapshot: snapshot)),
              const SizedBox(width: 12),
              Expanded(child: _BookingStatusCard(snapshot: snapshot)),
            ],
          );
        }
        return Column(children: [
          _BookingStatusCard(snapshot: snapshot),
          const SizedBox(height: 12),
          _BookingTableCard(snapshot: snapshot),
        ]);
      }),
    );
  }
}

class _BookingStatusCard extends StatelessWidget {
  const _BookingStatusCard({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final total = snapshot.totalBookings;
    return _SectionCard(
      title: 'Status Breakdown',
      subtitle: 'Booking outcomes for ${snapshot.window.label}',
      child: total == 0
          ? const _EmptyBox(message: 'No bookings in this period.')
          : Column(children: [
              _ProgressRow(label: 'Completed',     value: snapshot.completedBookings, total: total, color: _stGreen),
              _ProgressRow(label: 'Cancelled',     value: snapshot.cancelledBookings, total: total, color: _stRed),
              _ProgressRow(label: 'Pending/Other', value: snapshot.pendingBookings,   total: total, color: _stAmber),
            ]),
    );
  }
}

class _BookingTableCard extends StatelessWidget {
  const _BookingTableCard({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);
    return _SectionCard(
      title: 'Booking List',
      subtitle: '${snapshot.bookings.length} bookings in period',
      child: snapshot.bookings.isEmpty
          ? const _EmptyBox(message: 'No bookings in this date range.')
          : _CompactTable(
              columns: const ['Tourist', 'Package', 'Status', 'Amount', 'Date'],
              rows: snapshot.bookings.take(50).map((b) => [
                _shortText(b.touristName, 16),
                _shortText(b.packageTitle, 16),
                b.status,
                money.format(b.totalAmount),
                _dateStr(b.travelDate ?? b.createdAt),
              ]).toList(),
            ),
    );
  }
}

// ─── Packages tab ─────────────────────────────────────────────────────────────
class _PackagesTab extends StatelessWidget {
  const _PackagesTab({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);
    final counts = <String, int>{};
    for (final b in snapshot.bookings) {
      final key = b.packageId?.toString();
      if (key != null && key.isNotEmpty) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _SectionCard(
        title: 'Package Inventory',
        subtitle: '${snapshot.totalPackages} packages · ${snapshot.activePackages} active',
        child: snapshot.packages.isEmpty
            ? const _EmptyBox(message: 'No packages found.')
            : _CompactTable(
                columns: const ['Title', 'Status', 'Budget', 'Bookings'],
                rows: snapshot.packages.map((p) => [
                  _shortText(p.title, 22),
                  p.status,
                  money.format(p.estimatedBudget),
                  '${counts[p.id?.toString() ?? ''] ?? 0}',
                ]).toList(),
              ),
      ),
    );
  }
}

// ─── Spots tab ────────────────────────────────────────────────────────────────
class _SpotsTab extends StatelessWidget {
  const _SpotsTab({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _SectionCard(
        title: 'Tourist Spots',
        subtitle: '${snapshot.totalSpots} spots · ${snapshot.activeSpots} active',
        child: snapshot.spots.isEmpty
            ? const _EmptyBox(message: 'No tourist spots found.')
            : _CompactTable(
                columns: const ['Name', 'Barangay', 'Status', 'Rating', 'Verification'],
                rows: snapshot.spots.map((s) => [
                  _shortText(s.title, 20),
                  s.barangay,
                  s.status,
                  s.rating.toStringAsFixed(1),
                  s.verificationStatus.isEmpty ? '-' : s.verificationStatus,
                ]).toList(),
              ),
      ),
    );
  }
}

// ─── Drivers tab ──────────────────────────────────────────────────────────────
class _DriversTab extends StatelessWidget {
  const _DriversTab({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _SectionCard(
        title: 'Driver Registry',
        subtitle: '${snapshot.totalDrivers} drivers · ${snapshot.activeDrivers} active',
        child: snapshot.drivers.isEmpty
            ? const _EmptyBox(message: 'No drivers found.')
            : _CompactTable(
                columns: const ['Name', 'Status', 'TODA', 'License', 'Plate'],
                rows: snapshot.drivers.map((d) => [
                  _shortText(d.fullName, 18),
                  d.status,
                  d.todaName.isEmpty ? '-' : d.todaName,
                  d.licenseNumber.isEmpty ? '-' : d.licenseNumber,
                  d.plateNumber.isEmpty ? '-' : d.plateNumber,
                ]).toList(),
              ),
      ),
    );
  }
}

// ─── Feedback tab ─────────────────────────────────────────────────────────────
class _FeedbackTab extends StatelessWidget {
  const _FeedbackTab({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final f in snapshot.feedback) {
      final star = f.rating.round().clamp(1, 5);
      dist[star] = (dist[star] ?? 0) + 1;
    }
    var maxDist = 1;
    for (final v in dist.values) {
      if (v > maxDist) maxDist = v;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth > 640) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _FeedbackSummaryCard(
                      snapshot: snapshot, dist: dist, maxDist: maxDist)),
              const SizedBox(width: 12),
              Expanded(
                  flex: 2,
                  child: _FeedbackTableCard(snapshot: snapshot)),
            ],
          );
        }
        return Column(children: [
          _FeedbackSummaryCard(
              snapshot: snapshot, dist: dist, maxDist: maxDist),
          const SizedBox(height: 12),
          _FeedbackTableCard(snapshot: snapshot),
        ]);
      }),
    );
  }
}

class _FeedbackSummaryCard extends StatelessWidget {
  const _FeedbackSummaryCard({
    required this.snapshot,
    required this.dist,
    required this.maxDist,
  });

  final _STSnapshot snapshot;
  final Map<int, int> dist;
  final int maxDist;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Ratings Summary',
      subtitle: '${snapshot.feedbackCount} reviews',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: _stAmber, size: 32),
              const SizedBox(width: 8),
              Text(
                snapshot.avgRating.toStringAsFixed(1),
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '/ 5.0',
                style: TextStyle(color: SubTenantColors.muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int star = 5; star >= 1; star--)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$star★',
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxDist == 0 ? 0 : (dist[star] ?? 0) / maxDist,
                        backgroundColor: const Color(0xFFFFF7E6),
                        color: _stAmber,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${dist[star] ?? 0}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SubTenantFeedbackScreen()),
            ),
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('View All Feedback'),
            style: TextButton.styleFrom(
              foregroundColor: SubTenantColors.blue,
              textStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackTableCard extends StatelessWidget {
  const _FeedbackTableCard({required this.snapshot});
  final _STSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Recent Feedback',
      subtitle: '${snapshot.feedbackCount} entries in period',
      child: snapshot.feedback.isEmpty
          ? const _EmptyBox(message: 'No feedback in this period.')
          : _CompactTable(
              columns: const ['Tourist', 'Driver', 'Rating', 'Comment', 'Date'],
              rows: snapshot.feedback.take(30).map((f) => [
                _shortText(f.touristName, 14),
                _shortText(f.driverName, 14),
                f.rating.toStringAsFixed(1),
                _shortText(f.comment, 30),
                _dateStr(f.createdAt),
              ]).toList(),
            ),
    );
  }
}

// ─── Export tab ───────────────────────────────────────────────────────────────
class _ExportTab extends StatelessWidget {
  const _ExportTab({
    required this.exportType,
    required this.exportPreset,
    required this.exportSections,
    required this.preview,
    required this.isExporting,
    required this.onTypeChange,
    required this.onPresetChange,
    required this.onPickCustom,
    required this.onToggleSection,
    required this.onGeneratePreview,
    required this.onExportPdf,
  });

  final _STReportType exportType;
  final _STDatePreset exportPreset;
  final Set<_STSection> exportSections;
  final _STSnapshot? preview;
  final bool isExporting;
  final ValueChanged<_STReportType?> onTypeChange;
  final ValueChanged<_STDatePreset?> onPresetChange;
  final VoidCallback onPickCustom;
  final ValueChanged<_STSection> onToggleSection;
  final VoidCallback onGeneratePreview;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth > 680) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 340,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _ExportControls(
                  exportType:        exportType,
                  exportPreset:      exportPreset,
                  exportSections:    exportSections,
                  isExporting:       isExporting,
                  onTypeChange:      onTypeChange,
                  onPresetChange:    onPresetChange,
                  onPickCustom:      onPickCustom,
                  onToggleSection:   onToggleSection,
                  onGeneratePreview: onGeneratePreview,
                  onExportPdf:       onExportPdf,
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _ExportPreview(
                    preview: preview, isExporting: isExporting),
              ),
            ),
          ],
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _ExportControls(
              exportType:        exportType,
              exportPreset:      exportPreset,
              exportSections:    exportSections,
              isExporting:       isExporting,
              onTypeChange:      onTypeChange,
              onPresetChange:    onPresetChange,
              onPickCustom:      onPickCustom,
              onToggleSection:   onToggleSection,
              onGeneratePreview: onGeneratePreview,
              onExportPdf:       onExportPdf,
            ),
            const SizedBox(height: 16),
            _ExportPreview(preview: preview, isExporting: isExporting),
          ],
        ),
      );
    });
  }
}

class _ExportControls extends StatelessWidget {
  const _ExportControls({
    required this.exportType,
    required this.exportPreset,
    required this.exportSections,
    required this.isExporting,
    required this.onTypeChange,
    required this.onPresetChange,
    required this.onPickCustom,
    required this.onToggleSection,
    required this.onGeneratePreview,
    required this.onExportPdf,
  });

  final _STReportType exportType;
  final _STDatePreset exportPreset;
  final Set<_STSection> exportSections;
  final bool isExporting;
  final ValueChanged<_STReportType?> onTypeChange;
  final ValueChanged<_STDatePreset?> onPresetChange;
  final VoidCallback onPickCustom;
  final ValueChanged<_STSection> onToggleSection;
  final VoidCallback onGeneratePreview;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Export Configuration',
      subtitle: 'Configure and download your municipality PDF report',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Report Type',
              style: TextStyle(
                  color: SubTenantColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          DropdownButtonFormField<_STReportType>(
            initialValue: exportType,
            onChanged: onTypeChange,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            items: _STReportType.values
                .map((t) =>
                    DropdownMenuItem(value: t, child: Text(t.label)))
                .toList(),
          ),
          const SizedBox(height: 14),
          const Text('Date Range',
              style: TextStyle(
                  color: SubTenantColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          DropdownButtonFormField<_STDatePreset>(
            initialValue: exportPreset,
            onChanged: onPresetChange,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            items: _STDatePreset.values
                .map((p) =>
                    DropdownMenuItem(value: p, child: Text(p.label)))
                .toList(),
          ),
          if (exportPreset == _STDatePreset.custom) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: onPickCustom,
              icon: const Icon(Icons.date_range, size: 14),
              label: const Text('Pick Date Range'),
              style: TextButton.styleFrom(
                foregroundColor: SubTenantColors.blue,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text('Sections to Include',
              style: TextStyle(
                  color: SubTenantColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _STSection.values.map((s) {
              final sel = exportSections.contains(s);
              return FilterChip(
                label: Text(
                  s.label,
                  style: TextStyle(
                    color: sel ? Colors.white : SubTenantColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                selected: sel,
                onSelected: (_) => onToggleSection(s),
                selectedColor: SubTenantColors.deepBlue,
                checkmarkColor: Colors.white,
                side: BorderSide(
                    color: sel
                        ? SubTenantColors.deepBlue
                        : SubTenantColors.line),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGeneratePreview,
                  icon: const Icon(Icons.preview, size: 14),
                  label: const Text('Preview'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SubTenantColors.blue,
                    side: const BorderSide(color: SubTenantColors.blue),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isExporting ? null : onExportPdf,
                  icon: isExporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download, size: 14),
                  label: Text(isExporting ? 'Exporting…' : 'Export PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SubTenantColors.deepBlue,
                    foregroundColor: Colors.white,
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

class _ExportPreview extends StatelessWidget {
  const _ExportPreview({
    required this.preview,
    required this.isExporting,
  });

  final _STSnapshot? preview;
  final bool isExporting;

  @override
  Widget build(BuildContext context) {
    if (preview == null) {
      return _SectionCard(
        title: 'Report Preview',
        subtitle: 'Configure options then tap "Preview"',
        child: const _EmptyBox(
            message:
                'No preview generated yet. Adjust settings and click Preview.'),
      );
    }

    final s     = preview!;
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    return _SectionCard(
      title: 'Report Preview',
      subtitle: '${s.city} · ${s.window.formatted}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniMetric('Bookings',   '${s.totalBookings}',           SubTenantColors.blue),
              _MiniMetric('Completed',  '${s.completedBookings}',       _stGreen),
              _MiniMetric('Cancelled',  '${s.cancelledBookings}',       _stRed),
              _MiniMetric('Revenue',    money.format(s.revenue),        _stPurple),
              _MiniMetric('Packages',   '${s.totalPackages}',           _stCyan),
              _MiniMetric('Spots',      '${s.totalSpots}',              _stCyan),
              _MiniMetric('Drivers',    '${s.totalDrivers}',            _stPurple),
              _MiniMetric('Avg Rating', s.avgRating.toStringAsFixed(1), _stAmber),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Click "Export PDF" to download this report.',
            style: TextStyle(
              color: SubTenantColors.muted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w900)),
          Text(label,
              style: const TextStyle(
                  color: SubTenantColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SubTenantColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SubTenantColors.line),
        boxShadow: [
          BoxShadow(
            color: SubTenantColors.shadow,
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                color: SubTenantColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              )),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: const TextStyle(
                  color: SubTenantColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                )),
          ],
          const SizedBox(height: 14),
          child,
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
    final pct = total == 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  )),
              Text('$value (${_percent(pct)})',
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: pct,
            backgroundColor: SubTenantColors.line,
            color: color,
            minHeight: 5,
            borderRadius: BorderRadius.circular(5),
          ),
        ],
      ),
    );
  }
}

class _CompactTable extends StatelessWidget {
  const _CompactTable({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 40,
        headingTextStyle: const TextStyle(
          color: SubTenantColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: const TextStyle(
          color: SubTenantColors.text,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        columns: columns.map((c) => DataColumn(label: Text(c))).toList(),
        rows: rows
            .map((row) => DataRow(
                cells: row.map((cell) => DataCell(Text(cell))).toList()))
            .toList(),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights_outlined,
              color: SubTenantColors.blue, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                  color: SubTenantColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ],
      ),
    );
  }
}

// ─── Utilities ────────────────────────────────────────────────────────────────
String _dateStr(DateTime? dt) =>
    dt == null ? '-' : DateFormat('MM/dd/yy').format(dt);

String _percent(double f) =>
    '${(f * 100).toStringAsFixed(0)}%';

String _shortText(String? text, int max) {
  if (text == null || text.isEmpty) return '-';
  return text.length > max ? '${text.substring(0, max)}…' : text;
}

String _slugify(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
