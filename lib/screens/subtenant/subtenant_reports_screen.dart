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

// ─────────────────────────────────────────────────────────────────────────────
// Colors
// ─────────────────────────────────────────────────────────────────────────────

const _green = Color(0xFF16A34A);
const _amber = Color(0xFFF59E0B);
const _purple = Color(0xFF7C3AED);
const _cyan = Color(0xFF0EA5E9);
const _red = Color(0xFFDC2626);

const _paperWorkspace = Color(0xFFF1F5F9);
const _paperBorder = Color(0xFFDCE4EE);
const _paperText = Color(0xFF172033);
const _paperMuted = Color(0xFF667085);
const _paperSoft = Color(0xFFF8FAFC);

// ─────────────────────────────────────────────────────────────────────────────
// Tabs
// ─────────────────────────────────────────────────────────────────────────────

enum _ReportTab {
  overview(
    'Overview',
    'Municipality Tourism Summary Report',
    Icons.dashboard_outlined,
  ),
  bookings(
    'Bookings',
    'Booking Activity Report',
    Icons.receipt_long_outlined,
  ),
  packages(
    'Packages',
    'Tourism Package Performance Report',
    Icons.inventory_2_outlined,
  ),
  spots(
    'Spots',
    'Tourist Spot Report',
    Icons.place_outlined,
  ),
  drivers(
    'Drivers',
    'Driver Activity Report',
    Icons.badge_outlined,
  ),
  feedback(
    'Feedback',
    'Visitor Feedback Report',
    Icons.star_outline_rounded,
  );

  const _ReportTab(
    this.label,
    this.reportTitle,
    this.icon,
  );

  final String label;
  final String reportTitle;
  final IconData icon;
}

enum _DatePreset {
  weekly('This Week'),
  monthly('This Month'),
  yearly('This Year'),
  allTime('All Time'),
  custom('Custom Range');

  const _DatePreset(this.label);

  final String label;
}

// ─────────────────────────────────────────────────────────────────────────────
// Data
// ─────────────────────────────────────────────────────────────────────────────

class _FullLoad {
  const _FullLoad({
    required this.profile,
    required this.data,
  });

  final SubTenantProfile profile;
  final SubTenantReportData data;
}

class _ReportWindow {
  const _ReportWindow({
    required this.start,
    required this.end,
    required this.label,
  });

  factory _ReportWindow.fromRange(SubTenantReportRange range) {
    return _ReportWindow(
      start: range.start,
      end: range.end,
      label: range.label,
    );
  }

  final DateTime start;
  final DateTime end;
  final String label;

  bool contains(DateTime? date) {
    if (date == null) return false;

    return !date.isBefore(start) && !date.isAfter(end);
  }

  String get formatted {
    return '${DateFormat.yMMMd().format(start)} – '
        '${DateFormat.yMMMd().format(end)}';
  }
}

class _ReportSnapshot {
  const _ReportSnapshot({
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
  final _ReportWindow window;

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

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

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

  bool _isExporting = false;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: _ReportTab.values.length,
      vsync: this,
    );

    _future = _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<_FullLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final data = await _service.fetchReports(profile);

    return _FullLoad(
      profile: profile,
      data: data,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  void _setRange(SubTenantReportRange range) {
    setState(() {
      _range = range;
      _future = _load();
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: _range.start,
        end: _range.end,
      ),
    );

    if (picked != null && mounted) {
      _setRange(
        SubTenantReportRange.custom(
          picked.start,
          picked.end,
        ),
      );
    }
  }

  void _onRangeSelected(_DatePreset preset) {
    switch (preset) {
      case _DatePreset.weekly:
        _setRange(SubTenantReportRange.weekly());
        break;

      case _DatePreset.monthly:
        _setRange(SubTenantReportRange.currentMonth());
        break;

      case _DatePreset.yearly:
        _setRange(SubTenantReportRange.yearly());
        break;

      case _DatePreset.allTime:
        _setRange(
          SubTenantReportRange.custom(
            DateTime(2020),
            DateTime.now(),
          ),
        );
        break;

      case _DatePreset.custom:
        _pickCustomRange();
        break;
    }
  }

  _ReportSnapshot _buildSnapshot(
    _FullLoad load,
    _ReportWindow window,
  ) {
    final data = load.data;

    final bookings = data.bookings.where((booking) {
      return window.contains(
        booking.travelDate ?? booking.createdAt,
      );
    }).toList();

    final feedback = data.feedback.where((item) {
      return window.contains(item.createdAt);
    }).toList();

    final completed = bookings
        .where((booking) => booking.status == 'completed')
        .length;

    final cancelled = bookings
        .where((booking) => booking.status == 'cancelled')
        .length;

    final pending = bookings.length - completed - cancelled;

    final revenue = bookings
        .where((booking) => booking.status == 'completed')
        .fold<double>(
          0,
          (sum, booking) => sum + booking.totalAmount,
        );

    final averageRating = feedback.isEmpty
        ? 0.0
        : feedback.fold<double>(
              0,
              (sum, item) => sum + item.rating,
            ) /
            feedback.length;

    return _ReportSnapshot(
      city: load.profile.assignedCity,
      window: window,
      totalBookings: bookings.length,
      completedBookings: completed,
      cancelledBookings: cancelled,
      pendingBookings: pending,
      revenue: revenue,
      totalPackages: data.allPackages.length,
      activePackages:
          data.allPackages.where((p) => p.status == 'active').length,
      totalSpots: data.allSpots.length,
      activeSpots:
          data.allSpots.where((spot) => spot.status == 'active').length,
      totalDrivers: data.allDrivers.length,
      activeDrivers:
          data.allDrivers.where((driver) => driver.status == 'active').length,
      avgRating: averageRating,
      feedbackCount: feedback.length,
      bookings: bookings,
      feedback: feedback,
      packages: data.allPackages,
      spots: data.allSpots,
      drivers: data.allDrivers,
    );
  }

  Future<void> _downloadCurrentReport(
    _ReportSnapshot snapshot,
  ) async {
    if (_isExporting) return;

    final reportTab = _ReportTab.values[_tabController.index];

    setState(() {
      _isExporting = true;
    });

    try {
      final document = await _buildPdf(
        snapshot,
        reportTab,
      );

      final bytes = await document.save();

      final filename =
          'touristrike-${_slugify(snapshot.city)}-'
          '${_slugify(reportTab.label)}-'
          '${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';

      await Printing.sharePdf(
        bytes: bytes,
        filename: filename,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PDF
  // ───────────────────────────────────────────────────────────────────────────

  Future<pw.Document> _buildPdf(
    _ReportSnapshot snapshot,
    _ReportTab tab,
  ) async {
    final document = pw.Document();

    final blue = PdfColor.fromHex('#1557D6');
    final dark = PdfColor.fromHex('#172033');
    final muted = PdfColor.fromHex('#667085');
    final light = PdfColor.fromHex('#F3F6FA');

    final money = NumberFormat.currency(
      symbol: 'PHP ',
      decimalDigits: 0,
    );

    pw.Widget metric(
      String label,
      String value,
    ) {
      return pw.Container(
        width: 115,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: light,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8,
                color: muted,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: dark,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget sectionTitle(String title) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(
          top: 14,
          bottom: 6,
        ),
        child: pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: dark,
          ),
        ),
      );
    }

    pw.Widget table({
      required List<String> headers,
      required List<List<String>> rows,
    }) {
      if (rows.isEmpty) {
        return pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
              color: PdfColors.grey300,
            ),
          ),
          child: pw.Text(
            'No data available for this reporting period.',
            style: pw.TextStyle(
              fontSize: 9,
              color: muted,
            ),
          ),
        );
      }

      return pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        border: pw.TableBorder.all(
          color: PdfColors.grey300,
          width: 0.5,
        ),
        headerDecoration: pw.BoxDecoration(
          color: light,
        ),
        headerStyle: pw.TextStyle(
          color: dark,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: pw.TextStyle(
          color: dark,
          fontSize: 8,
        ),
        cellPadding: const pw.EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 5,
        ),
        headerAlignment: pw.Alignment.centerLeft,
        cellAlignment: pw.Alignment.centerLeft,
      );
    }

    List<pw.Widget> reportBody() {
      switch (tab) {
        case _ReportTab.overview:
          return [
            sectionTitle('Executive Summary'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Bookings',
                  '${snapshot.totalBookings}',
                ),
                metric(
                  'Completed',
                  '${snapshot.completedBookings}',
                ),
                metric(
                  'Cancelled',
                  '${snapshot.cancelledBookings}',
                ),
                metric(
                  'Revenue',
                  money.format(snapshot.revenue),
                ),
                metric(
                  'Packages',
                  '${snapshot.totalPackages}',
                ),
                metric(
                  'Tourist Spots',
                  '${snapshot.totalSpots}',
                ),
                metric(
                  'Drivers',
                  '${snapshot.totalDrivers}',
                ),
                metric(
                  'Average Rating',
                  snapshot.feedbackCount == 0
                      ? 'No ratings'
                      : snapshot.avgRating.toStringAsFixed(1),
                ),
              ],
            ),
            sectionTitle('Booking Performance'),
            table(
              headers: const [
                'Booking Status',
                'Count',
                'Percentage',
              ],
              rows: [
                [
                  'Completed',
                  '${snapshot.completedBookings}',
                  _pdfPercent(
                    snapshot.completedBookings,
                    snapshot.totalBookings,
                  ),
                ],
                [
                  'Cancelled',
                  '${snapshot.cancelledBookings}',
                  _pdfPercent(
                    snapshot.cancelledBookings,
                    snapshot.totalBookings,
                  ),
                ],
                [
                  'Pending / Other',
                  '${snapshot.pendingBookings}',
                  _pdfPercent(
                    snapshot.pendingBookings,
                    snapshot.totalBookings,
                  ),
                ],
              ],
            ),
            sectionTitle('Municipality Coverage'),
            table(
              headers: const [
                'Category',
                'Registered',
                'Active',
              ],
              rows: [
                [
                  'Tourism Packages',
                  '${snapshot.totalPackages}',
                  '${snapshot.activePackages}',
                ],
                [
                  'Tourist Spots',
                  '${snapshot.totalSpots}',
                  '${snapshot.activeSpots}',
                ],
                [
                  'Drivers',
                  '${snapshot.totalDrivers}',
                  '${snapshot.activeDrivers}',
                ],
              ],
            ),
          ];

        case _ReportTab.bookings:
          return [
            sectionTitle('Booking Summary'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Total Bookings',
                  '${snapshot.totalBookings}',
                ),
                metric(
                  'Completed',
                  '${snapshot.completedBookings}',
                ),
                metric(
                  'Cancelled',
                  '${snapshot.cancelledBookings}',
                ),
                metric(
                  'Revenue',
                  money.format(snapshot.revenue),
                ),
              ],
            ),
            sectionTitle('Booking Records'),
            table(
              headers: const [
                'Tourist',
                'Package',
                'Status',
                'Amount',
                'Travel Date',
              ],
              rows: snapshot.bookings.map((booking) {
                return [
                  _shortText(booking.touristName, 24),
                  _shortText(booking.packageTitle, 24),
                  _displayStatus(booking.status),
                  money.format(booking.totalAmount),
                  _dateStr(
                    booking.travelDate ?? booking.createdAt,
                  ),
                ];
              }).toList(),
            ),
          ];

        case _ReportTab.packages:
          final counts = <String, int>{};

          for (final booking in snapshot.bookings) {
            final id = booking.packageId?.toString();

            if (id != null && id.isNotEmpty) {
              counts[id] = (counts[id] ?? 0) + 1;
            }
          }

          return [
            sectionTitle('Package Summary'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Total Packages',
                  '${snapshot.totalPackages}',
                ),
                metric(
                  'Active Packages',
                  '${snapshot.activePackages}',
                ),
                metric(
                  'Period Bookings',
                  '${snapshot.totalBookings}',
                ),
              ],
            ),
            sectionTitle('Package Performance'),
            table(
              headers: const [
                'Package',
                'Status',
                'Estimated Budget',
                'Bookings',
              ],
              rows: snapshot.packages.map((package) {
                return [
                  _shortText(package.title, 30),
                  _displayStatus(package.status),
                  money.format(package.estimatedBudget),
                  '${counts[package.id?.toString() ?? ''] ?? 0}',
                ];
              }).toList(),
            ),
          ];

        case _ReportTab.spots:
          return [
            sectionTitle('Tourist Spot Summary'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Registered Spots',
                  '${snapshot.totalSpots}',
                ),
                metric(
                  'Active Spots',
                  '${snapshot.activeSpots}',
                ),
              ],
            ),
            sectionTitle('Tourist Spot Records'),
            table(
              headers: const [
                'Tourist Spot',
                'Barangay',
                'Status',
                'Rating',
                'Verification',
              ],
              rows: snapshot.spots.map((spot) {
                return [
                  _shortText(spot.title, 28),
                  spot.barangay.isEmpty ? '-' : spot.barangay,
                  _displayStatus(spot.status),
                  spot.rating == 0
                      ? 'No rating'
                      : spot.rating.toStringAsFixed(1),
                  spot.verificationStatus.isEmpty
                      ? '-'
                      : _displayStatus(
                          spot.verificationStatus,
                        ),
                ];
              }).toList(),
            ),
          ];

        case _ReportTab.drivers:
          return [
            sectionTitle('Driver Summary'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Registered Drivers',
                  '${snapshot.totalDrivers}',
                ),
                metric(
                  'Active Drivers',
                  '${snapshot.activeDrivers}',
                ),
              ],
            ),
            sectionTitle('Driver Records'),
            table(
              headers: const [
                'Driver',
                'Status',
                'TODA',
                'License',
                'Plate Number',
              ],
              rows: snapshot.drivers.map((driver) {
                return [
                  _shortText(driver.fullName, 26),
                  _displayStatus(driver.status),
                  driver.todaName.isEmpty
                      ? '-'
                      : _shortText(driver.todaName, 22),
                  driver.licenseNumber.isEmpty
                      ? '-'
                      : driver.licenseNumber,
                  driver.plateNumber.isEmpty
                      ? '-'
                      : driver.plateNumber,
                ];
              }).toList(),
            ),
          ];

        case _ReportTab.feedback:
          return [
            sectionTitle('Feedback Summary'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Feedback Entries',
                  '${snapshot.feedbackCount}',
                ),
                metric(
                  'Average Rating',
                  snapshot.feedbackCount == 0
                      ? 'No ratings'
                      : '${snapshot.avgRating.toStringAsFixed(1)} / 5',
                ),
              ],
            ),
            sectionTitle('Visitor Feedback Records'),
            table(
              headers: const [
                'Tourist',
                'Driver',
                'Rating',
                'Comment',
                'Date',
              ],
              rows: snapshot.feedback.map((item) {
                return [
                  _shortText(item.touristName, 18),
                  _shortText(item.driverName, 18),
                  item.rating.toStringAsFixed(1),
                  _shortText(item.comment, 42),
                  _dateStr(item.createdAt),
                ];
              }).toList(),
            ),
          ];
      }
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          38,
          38,
          38,
          38,
        ),
        header: (_) {
          return pw.Column(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 38,
                    height: 38,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: blue,
                      ),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      'TT',
                      style: pw.TextStyle(
                        color: blue,
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'TOURISTRIKE',
                          style: pw.TextStyle(
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                            color: dark,
                          ),
                        ),
                        pw.Text(
                          'Municipality Tourism Office',
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'OFFICIAL REPORT',
                        style: pw.TextStyle(
                          color: blue,
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Generated ${DateFormat.yMMMd().format(DateTime.now())}',
                        style: pw.TextStyle(
                          color: muted,
                          fontSize: 7,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(
                color: PdfColors.grey300,
                thickness: 0.8,
              ),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      tab.reportTitle.toUpperCase(),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        color: dark,
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Municipality of ${snapshot.city}',
                      style: pw.TextStyle(
                        color: dark,
                        fontSize: 10,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Reporting Period: ${snapshot.window.formatted}',
                      style: pw.TextStyle(
                        color: muted,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
            ],
          );
        },
        footer: (context) {
          return pw.Column(
            children: [
              pw.Divider(
                color: PdfColors.grey300,
                thickness: 0.6,
              ),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TourisTrike • Municipality of ${snapshot.city}',
                    style: pw.TextStyle(
                      color: muted,
                      fontSize: 7,
                    ),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: pw.TextStyle(
                      color: muted,
                      fontSize: 7,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
        build: (_) => reportBody(),
      ),
    );

    return document;
  }

  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: 5,
      title: 'Municipality Reports',
      subtitle:
          'Official tourism reports for your assigned municipality.',
      child: FutureBuilder<_FullLoad>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState ==
              ConnectionState.waiting) {
            return const _LoadingState();
          }

          if (snap.hasError) {
            return _ErrorState(
              message: snap.error.toString(),
              onRetry: _reload,
            );
          }

          final load = snap.data!;

          final snapshot = _buildSnapshot(
            load,
            _ReportWindow.fromRange(_range),
          );

          return Container(
            color: _paperWorkspace,
            child: Column(
              children: [
                _ReportToolbar(
                  snapshot: snapshot,
                  onRangeSelected: _onRangeSelected,
                  onDownload: () =>
                      _downloadCurrentReport(snapshot),
                  isDownloading: _isExporting,
                ),
                _ReportTabBar(
                  controller: _tabController,
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _OverviewReport(
                        snapshot: snapshot,
                      ),
                      _BookingsReport(
                        snapshot: snapshot,
                      ),
                      _PackagesReport(
                        snapshot: snapshot,
                      ),
                      _SpotsReport(
                        snapshot: snapshot,
                      ),
                      _DriversReport(
                        snapshot: snapshot,
                      ),
                      _FeedbackReport(
                        snapshot: snapshot,
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Top toolbar
// ─────────────────────────────────────────────────────────────────────────────

class _ReportToolbar extends StatelessWidget {
  const _ReportToolbar({
    required this.snapshot,
    required this.onRangeSelected,
    required this.onDownload,
    required this.isDownloading,
  });

  final _ReportSnapshot snapshot;
  final ValueChanged<_DatePreset> onRangeSelected;
  final VoidCallback onDownload;
  final bool isDownloading;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(
        18,
        14,
        18,
        12,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;

          final municipality = Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SubTenantColors.blue.withValues(
                    alpha: 0.08,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_city_outlined,
                  color: SubTenantColors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _paperText,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Municipality Tourism Reports',
                      style: TextStyle(
                        color: _paperMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final controls = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                ),
                decoration: BoxDecoration(
                  color: _paperSoft,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: _paperBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      size: 15,
                      color: _paperMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      snapshot.window.formatted,
                      style: const TextStyle(
                        color: _paperText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_DatePreset>(
                tooltip: 'Change reporting period',
                onSelected: onRangeSelected,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                itemBuilder: (_) {
                  return _DatePreset.values.map((preset) {
                    return PopupMenuItem(
                      value: preset,
                      child: Text(
                        preset.label,
                        style: const TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList();
                },
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: _paperBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.window.label,
                        style: const TextStyle(
                          color: _paperText,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: _paperMuted,
                      ),
                    ],
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed:
                    isDownloading ? null : onDownload,
                icon: isDownloading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.download_rounded,
                        size: 16,
                      ),
                label: Text(
                  isDownloading
                      ? 'Generating PDF...'
                      : 'Download PDF',
                ),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor:
                      SubTenantColors.deepBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(9),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                municipality,
                const SizedBox(height: 12),
                controls,
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: municipality,
              ),
              const SizedBox(width: 16),
              controls,
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab navigation
// ─────────────────────────────────────────────────────────────────────────────

class _ReportTabBar extends StatelessWidget {
  const _ReportTabBar({
    required this.controller,
  });

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(
        18,
        0,
        18,
        10,
      ),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: _paperSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _paperBorder,
          ),
        ),
        child: TabBar(
          controller: controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _paperBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: 0.04,
                ),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          labelColor: SubTenantColors.deepBlue,
          unselectedLabelColor: _paperMuted,
          labelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.all(4),
          tabs: _ReportTab.values.map((tab) {
            return Tab(
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tab.icon,
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Text(tab.label),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overview report
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewReport extends StatelessWidget {
  const _OverviewReport({
    required this.snapshot,
  });

  final _ReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      symbol: '₱',
      decimalDigits: 0,
    );

    final completion = snapshot.totalBookings == 0
        ? 0.0
        : snapshot.completedBookings /
            snapshot.totalBookings;

    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle:
            'Municipality Tourism Summary Report',
        municipality: snapshot.city,
        period: snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title: 'Executive Summary',
            subtitle:
                'Overall municipality tourism performance for the selected reporting period.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label: 'Total Bookings',
                value: '${snapshot.totalBookings}',
                helper: 'Bookings recorded',
              ),
              _PaperMetric(
                label: 'Completed',
                value:
                    '${snapshot.completedBookings}',
                helper:
                    '${_percent(completion)} completion rate',
              ),
              _PaperMetric(
                label: 'Cancelled',
                value:
                    '${snapshot.cancelledBookings}',
                helper: snapshot.totalBookings == 0
                    ? 'No bookings'
                    : '${_percent(snapshot.cancelledBookings / snapshot.totalBookings)} of bookings',
              ),
              _PaperMetric(
                label: 'Revenue',
                value: money.format(
                  snapshot.revenue,
                ),
                helper:
                    'Completed bookings only',
              ),
              _PaperMetric(
                label: 'Average Rating',
                value: snapshot.feedbackCount == 0
                    ? '—'
                    : snapshot.avgRating
                        .toStringAsFixed(1),
                helper: snapshot.feedbackCount == 0
                    ? 'No ratings yet'
                    : '${snapshot.feedbackCount} feedback entries',
              ),
              _PaperMetric(
                label: 'Active Drivers',
                value:
                    '${snapshot.activeDrivers}',
                helper:
                    '${snapshot.totalDrivers} registered',
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _PaperSectionTitle(
            title: 'Booking Performance',
          ),
          _PaperTable(
            columns: const [
              'Status',
              'Count',
              'Share',
            ],
            rows: [
              [
                'Completed',
                '${snapshot.completedBookings}',
                _percentageFromCount(
                  snapshot.completedBookings,
                  snapshot.totalBookings,
                ),
              ],
              [
                'Cancelled',
                '${snapshot.cancelledBookings}',
                _percentageFromCount(
                  snapshot.cancelledBookings,
                  snapshot.totalBookings,
                ),
              ],
              [
                'Pending / Other',
                '${snapshot.pendingBookings}',
                _percentageFromCount(
                  snapshot.pendingBookings,
                  snapshot.totalBookings,
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          const _PaperSectionTitle(
            title: 'Municipality Coverage',
            subtitle:
                'Registered tourism assets and active records.',
          ),
          _PaperTable(
            columns: const [
              'Category',
              'Registered',
              'Active',
              'Availability',
            ],
            rows: [
              [
                'Tourism Packages',
                '${snapshot.totalPackages}',
                '${snapshot.activePackages}',
                _percentageFromCount(
                  snapshot.activePackages,
                  snapshot.totalPackages,
                ),
              ],
              [
                'Tourist Spots',
                '${snapshot.totalSpots}',
                '${snapshot.activeSpots}',
                _percentageFromCount(
                  snapshot.activeSpots,
                  snapshot.totalSpots,
                ),
              ],
              [
                'Drivers',
                '${snapshot.totalDrivers}',
                '${snapshot.activeDrivers}',
                _percentageFromCount(
                  snapshot.activeDrivers,
                  snapshot.totalDrivers,
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          _ReportNotes(
            snapshot: snapshot,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Booking report
// ─────────────────────────────────────────────────────────────────────────────

class _BookingsReport extends StatelessWidget {
  const _BookingsReport({
    required this.snapshot,
  });

  final _ReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      symbol: '₱',
      decimalDigits: 0,
    );

    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle: 'Booking Activity Report',
        municipality: snapshot.city,
        period: snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title: 'Booking Summary',
            subtitle:
                'Booking activity recorded during the selected reporting period.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label: 'Bookings',
                value: '${snapshot.totalBookings}',
                helper: 'Total records',
              ),
              _PaperMetric(
                label: 'Completed',
                value:
                    '${snapshot.completedBookings}',
                helper: 'Successful bookings',
              ),
              _PaperMetric(
                label: 'Cancelled',
                value:
                    '${snapshot.cancelledBookings}',
                helper: 'Cancelled records',
              ),
              _PaperMetric(
                label: 'Pending / Other',
                value:
                    '${snapshot.pendingBookings}',
                helper: 'Other booking states',
              ),
              _PaperMetric(
                label: 'Revenue',
                value: money.format(
                  snapshot.revenue,
                ),
                helper:
                    'Completed bookings',
              ),
            ],
          ),
          const SizedBox(height: 28),
          _PaperSectionTitle(
            title: 'Booking Records',
            subtitle:
                '${snapshot.bookings.length} record(s) found.',
          ),
          if (snapshot.bookings.isEmpty)
            const _PaperEmptyState(
              message:
                  'No bookings were recorded during this reporting period.',
            )
          else
            _PaperTable(
              columns: const [
                'Tourist',
                'Package',
                'Status',
                'Amount',
                'Travel Date',
              ],
              rows: snapshot.bookings.map((booking) {
                return [
                  _shortText(
                    booking.touristName,
                    22,
                  ),
                  _shortText(
                    booking.packageTitle,
                    22,
                  ),
                  _displayStatus(
                    booking.status,
                  ),
                  money.format(
                    booking.totalAmount,
                  ),
                  _dateStr(
                    booking.travelDate ??
                        booking.createdAt,
                  ),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Packages report
// ─────────────────────────────────────────────────────────────────────────────

class _PackagesReport extends StatelessWidget {
  const _PackagesReport({
    required this.snapshot,
  });

  final _ReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      symbol: '₱',
      decimalDigits: 0,
    );

    final counts = <String, int>{};

    for (final booking in snapshot.bookings) {
      final id = booking.packageId?.toString();

      if (id != null && id.isNotEmpty) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }

    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle:
            'Tourism Package Performance Report',
        municipality: snapshot.city,
        period: snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title: 'Package Summary',
            subtitle:
                'Registered tourism packages and booking activity.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label: 'Total Packages',
                value:
                    '${snapshot.totalPackages}',
                helper: 'Registered packages',
              ),
              _PaperMetric(
                label: 'Active Packages',
                value:
                    '${snapshot.activePackages}',
                helper: 'Currently active',
              ),
              _PaperMetric(
                label: 'Period Bookings',
                value:
                    '${snapshot.totalBookings}',
                helper:
                    'Bookings in selected period',
              ),
            ],
          ),
          const SizedBox(height: 28),
          _PaperSectionTitle(
            title: 'Package Performance',
            subtitle:
                '${snapshot.packages.length} package(s) listed.',
          ),
          if (snapshot.packages.isEmpty)
            const _PaperEmptyState(
              message:
                  'No tourism packages are currently registered.',
            )
          else
            _PaperTable(
              columns: const [
                'Package',
                'Status',
                'Estimated Budget',
                'Bookings',
              ],
              rows: snapshot.packages.map((package) {
                return [
                  _shortText(
                    package.title,
                    32,
                  ),
                  _displayStatus(
                    package.status,
                  ),
                  money.format(
                    package.estimatedBudget,
                  ),
                  '${counts[package.id?.toString() ?? ''] ?? 0}',
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Spots report
// ─────────────────────────────────────────────────────────────────────────────

class _SpotsReport extends StatelessWidget {
  const _SpotsReport({
    required this.snapshot,
  });

  final _ReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle: 'Tourist Spot Report',
        municipality: snapshot.city,
        period: snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title: 'Tourist Spot Summary',
            subtitle:
                'Tourism destinations registered under the municipality.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label: 'Registered Spots',
                value:
                    '${snapshot.totalSpots}',
                helper: 'All destinations',
              ),
              _PaperMetric(
                label: 'Active Spots',
                value:
                    '${snapshot.activeSpots}',
                helper: 'Currently active',
              ),
            ],
          ),
          const SizedBox(height: 28),
          _PaperSectionTitle(
            title: 'Tourist Spot Records',
            subtitle:
                '${snapshot.spots.length} destination(s) listed.',
          ),
          if (snapshot.spots.isEmpty)
            const _PaperEmptyState(
              message:
                  'No tourist spots are currently registered.',
            )
          else
            _PaperTable(
              columns: const [
                'Tourist Spot',
                'Barangay',
                'Status',
                'Rating',
                'Verification',
              ],
              rows: snapshot.spots.map((spot) {
                return [
                  _shortText(
                    spot.title,
                    28,
                  ),
                  spot.barangay.isEmpty
                      ? '-'
                      : spot.barangay,
                  _displayStatus(
                    spot.status,
                  ),
                  spot.rating == 0
                      ? '—'
                      : spot.rating
                          .toStringAsFixed(1),
                  spot.verificationStatus.isEmpty
                      ? '-'
                      : _displayStatus(
                          spot.verificationStatus,
                        ),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drivers report
// ─────────────────────────────────────────────────────────────────────────────

class _DriversReport extends StatelessWidget {
  const _DriversReport({
    required this.snapshot,
  });

  final _ReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle: 'Driver Activity Report',
        municipality: snapshot.city,
        period: snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title: 'Driver Summary',
            subtitle:
                'Registered tricycle driver-tour guides for the municipality.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label: 'Registered Drivers',
                value:
                    '${snapshot.totalDrivers}',
                helper: 'Total records',
              ),
              _PaperMetric(
                label: 'Active Drivers',
                value:
                    '${snapshot.activeDrivers}',
                helper: 'Currently active',
              ),
            ],
          ),
          const SizedBox(height: 28),
          _PaperSectionTitle(
            title: 'Driver Records',
            subtitle:
                '${snapshot.drivers.length} driver(s) listed.',
          ),
          if (snapshot.drivers.isEmpty)
            const _PaperEmptyState(
              message:
                  'No drivers are currently registered.',
            )
          else
            _PaperTable(
              columns: const [
                'Driver',
                'Status',
                'TODA',
                'License',
                'Plate Number',
              ],
              rows: snapshot.drivers.map((driver) {
                return [
                  _shortText(
                    driver.fullName,
                    28,
                  ),
                  _displayStatus(
                    driver.status,
                  ),
                  driver.todaName.isEmpty
                      ? '-'
                      : _shortText(
                          driver.todaName,
                          22,
                        ),
                  driver.licenseNumber.isEmpty
                      ? '-'
                      : driver.licenseNumber,
                  driver.plateNumber.isEmpty
                      ? '-'
                      : driver.plateNumber,
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feedback report
// ─────────────────────────────────────────────────────────────────────────────

class _FeedbackReport extends StatelessWidget {
  const _FeedbackReport({
    required this.snapshot,
  });

  final _ReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final distribution = <int, int>{
      1: 0,
      2: 0,
      3: 0,
      4: 0,
      5: 0,
    };

    for (final feedback in snapshot.feedback) {
      final rating = feedback.rating.round().clamp(
            1,
            5,
          );

      distribution[rating] =
          (distribution[rating] ?? 0) + 1;
    }

    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle: 'Visitor Feedback Report',
        municipality: snapshot.city,
        period: snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title: 'Feedback Summary',
            subtitle:
                'Visitor ratings and comments received during the selected reporting period.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label: 'Feedback Entries',
                value:
                    '${snapshot.feedbackCount}',
                helper: 'Submitted reviews',
              ),
              _PaperMetric(
                label: 'Average Rating',
                value: snapshot.feedbackCount == 0
                    ? '—'
                    : snapshot.avgRating
                        .toStringAsFixed(1),
                helper: snapshot.feedbackCount == 0
                    ? 'No ratings yet'
                    : 'Out of 5.0',
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _PaperSectionTitle(
            title: 'Rating Distribution',
          ),
          _RatingDistribution(
            distribution: distribution,
            total: snapshot.feedbackCount,
          ),
          const SizedBox(height: 28),
          _PaperSectionTitle(
            title: 'Visitor Feedback Records',
            subtitle:
                '${snapshot.feedback.length} feedback record(s) found.',
            trailing: TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const SubTenantFeedbackScreen(),
                  ),
                );
              },
              icon: const Icon(
                Icons.open_in_new_rounded,
                size: 14,
              ),
              label: const Text(
                'Open Feedback Management',
              ),
              style: TextButton.styleFrom(
                foregroundColor:
                    SubTenantColors.blue,
                textStyle: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (snapshot.feedback.isEmpty)
            const _PaperEmptyState(
              message:
                  'No visitor feedback was submitted during this reporting period.',
            )
          else
            _PaperTable(
              columns: const [
                'Tourist',
                'Driver',
                'Rating',
                'Comment',
                'Date',
              ],
              rows: snapshot.feedback.map((item) {
                return [
                  _shortText(
                    item.touristName,
                    20,
                  ),
                  _shortText(
                    item.driverName,
                    20,
                  ),
                  item.rating
                      .toStringAsFixed(1),
                  _shortText(
                    item.comment,
                    40,
                  ),
                  _dateStr(
                    item.createdAt,
                  ),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Workspace
// ─────────────────────────────────────────────────────────────────────────────

class _ReportWorkspace extends StatelessWidget {
  const _ReportWorkspace({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: _paperWorkspace,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          24,
          28,
          24,
          48,
        ),
        child: Center(
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bond paper
// ─────────────────────────────────────────────────────────────────────────────

class _PaperReport extends StatelessWidget {
  const _PaperReport({
    required this.reportTitle,
    required this.municipality,
    required this.period,
    required this.children,
  });

  final String reportTitle;
  final String municipality;
  final String period;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        final paperWidth =
            availableWidth >= 820 ? 820.0 : availableWidth;

        final compact = paperWidth < 600;

        return Container(
          width: paperWidth,

          // Important:
          // Minimum paper height, but it can still grow
          // when the report contains more content.
          constraints: const BoxConstraints(
            minHeight: 1080,
          ),

          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: const Color(0xFFD8DEE8),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: 0.08,
                ),
                blurRadius: 24,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
            ],
          ),

          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 24 : 52,
              compact ? 30 : 46,
              compact ? 24 : 52,
              compact ? 22 : 28,
            ),

            // No Spacer.
            // No Expanded.
            // No IntrinsicHeight.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                // ─────────────────────────────────
                // EVERYTHING ABOVE THE FOOTER
                // ─────────────────────────────────
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    _PaperHeader(
                      reportTitle: reportTitle,
                      municipality: municipality,
                      period: period,
                    ),

                    SizedBox(
                      height: compact ? 24 : 34,
                    ),

                    ...children,

                    // Prevent content from sitting
                    // directly against footer on
                    // longer reports.
                    const SizedBox(height: 48),
                  ],
                ),

                // ─────────────────────────────────
                // PAPER FOOTER
                // ─────────────────────────────────
                _PaperFooter(
                  municipality: municipality,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Paper header
// ─────────────────────────────────────────────────────────────────────────────

class _PaperHeader extends StatelessWidget {
  const _PaperHeader({
    required this.reportTitle,
    required this.municipality,
    required this.period,
  });

  final String reportTitle;
  final String municipality;
  final String period;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: SubTenantColors.blue
                    .withValues(alpha: 0.08),
                borderRadius:
                    BorderRadius.circular(8),
                border: Border.all(
                  color: SubTenantColors.blue
                      .withValues(alpha: 0.18),
                ),
              ),
              child: const Icon(
                Icons.travel_explore_rounded,
                color: SubTenantColors.blue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOURISTRIKE',
                    style: TextStyle(
                      color: _paperText,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Municipality Tourism Office',
                    style: TextStyle(
                      color: _paperMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment:
                  CrossAxisAlignment.end,
              children: [
                const Text(
                  'OFFICIAL REPORT',
                  style: TextStyle(
                    color: SubTenantColors.blue,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Generated ${DateFormat.yMMMd().format(DateTime.now())}',
                  style: const TextStyle(
                    color: _paperMuted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Divider(
          height: 1,
          color: _paperBorder,
        ),
        const SizedBox(height: 26),
        Text(
          reportTitle.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _paperText,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Municipality of $municipality',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _paperText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Reporting Period: $period',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _paperMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Paper footer
// ─────────────────────────────────────────────────────────────────────────────

class _PaperFooter extends StatelessWidget {
  const _PaperFooter({
    required this.municipality,
  });

  final String municipality;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          height: 1,
          color: _paperBorder,
        ),

        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: Text(
                'TourisTrike • Municipality of $municipality',
                style: const TextStyle(
                  color: _paperMuted,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Text(
              'Municipality Tourism Report',
              style: TextStyle(
                color: _paperMuted,
                fontSize: 8.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section title
// ─────────────────────────────────────────────────────────────────────────────

class _PaperSectionTitle extends StatelessWidget {
  const _PaperSectionTitle({
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _paperText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: _paperMuted,
                      fontSize: 9.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metrics
// ─────────────────────────────────────────────────────────────────────────────

class _PaperMetric {
  const _PaperMetric({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.metrics,
  });

  final List<_PaperMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 650 ? 3 : 2;

        const spacing = 8.0;

        final itemWidth =
            (constraints.maxWidth -
                    ((columns - 1) * spacing)) /
                columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: metrics.map((metric) {
            return SizedBox(
              width: itemWidth,
              child: Container(
                padding:
                    const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _paperSoft,
                  borderRadius:
                      BorderRadius.circular(6),
                  border: Border.all(
                    color: _paperBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.label,
                      style: const TextStyle(
                        color: _paperMuted,
                        fontSize: 9,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metric.value,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _paperText,
                        fontSize: 16,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      metric.helper,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _paperMuted,
                        fontSize: 8.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Paper table
// ─────────────────────────────────────────────────────────────────────────────

class _PaperTable extends StatelessWidget {
  const _PaperTable({
    required this.columns,
    required this.rows,
    this.columnFlex,
  });

  final List<String> columns;
  final List<List<String>> rows;

  /// Optional flex values for each column.
  /// Example:
  /// [3, 2, 2, 1]
  ///
  /// If not supplied, all columns use equal widths.
  final List<int>? columnFlex;

  @override
  Widget build(BuildContext context) {
    final flexValues = columnFlex != null &&
            columnFlex!.length == columns.length
        ? columnFlex!
        : List<int>.filled(columns.length, 1);

    final columnWidths = <int, TableColumnWidth>{};

    for (var i = 0; i < columns.length; i++) {
      columnWidths[i] = FlexColumnWidth(
        flexValues[i].toDouble(),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(
          color: _paperBorder,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: columnWidths,
        defaultVerticalAlignment:
            TableCellVerticalAlignment.middle,
        border: const TableBorder(
          horizontalInside: BorderSide(
            color: _paperBorder,
            width: 0.8,
          ),
        ),
        children: [
          // Header
          TableRow(
            decoration: const BoxDecoration(
              color: _paperSoft,
            ),
            children: [
              for (final column in columns)
                _PaperTableCell(
                  text: column,
                  header: true,
                ),
            ],
          ),

          // Data
          for (var rowIndex = 0;
              rowIndex < rows.length;
              rowIndex++)
            TableRow(
              decoration: BoxDecoration(
                color: rowIndex.isEven
                    ? Colors.white
                    : const Color(0xFFFCFDFE),
              ),
              children: [
                for (final cell in rows[rowIndex])
                  _PaperTableCell(
                    text: cell,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PaperTableCell extends StatelessWidget {
  const _PaperTableCell({
    required this.text,
    this.header = false,
  });

  final String text;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minHeight: header ? 40 : 42,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: header
              ? _paperText
              : const Color(0xFF475467),
          fontSize: header ? 9.5 : 9.5,
          fontWeight: header
              ? FontWeight.w700
              : FontWeight.w500,
          height: 1.35,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rating distribution
// ─────────────────────────────────────────────────────────────────────────────

class _RatingDistribution extends StatelessWidget {
  const _RatingDistribution({
    required this.distribution,
    required this.total,
  });

  final Map<int, int> distribution;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (total == 0) {
      return const _PaperEmptyState(
        message:
            'No ratings were submitted during this reporting period.',
      );
    }

    return Column(
      children: [
        for (int star = 5; star >= 1; star--)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 4,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '$star ★',
                    style: const TextStyle(
                      color: _paperText,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(4),
                    child:
                        LinearProgressIndicator(
                      value:
                          (distribution[star] ?? 0) /
                              total,
                      minHeight: 7,
                      backgroundColor:
                          const Color(
                        0xFFF4F4F5,
                      ),
                      color: _amber,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${distribution[star] ?? 0}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: _paperMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Report notes
// ─────────────────────────────────────────────────────────────────────────────

class _ReportNotes extends StatelessWidget {
  const _ReportNotes({
    required this.snapshot,
  });

  final _ReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final completion = snapshot.totalBookings == 0
        ? 0.0
        : snapshot.completedBookings /
            snapshot.totalBookings;

    final notes = <String>[
      if (snapshot.totalBookings == 0)
        'No tourism package bookings were recorded during this reporting period.'
      else
        '${snapshot.completedBookings} of '
            '${snapshot.totalBookings} bookings were completed '
            '(${_percent(completion)}).',
      if (snapshot.feedbackCount == 0)
        'No visitor feedback was submitted during this reporting period.'
      else
        '${snapshot.feedbackCount} visitor feedback entries produced an average rating of '
            '${snapshot.avgRating.toStringAsFixed(1)} out of 5.',
      '${snapshot.activeSpots} of ${snapshot.totalSpots} registered tourist spots are active.',
      '${snapshot.activeDrivers} of ${snapshot.totalDrivers} registered drivers are active.',
    ];

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const _PaperSectionTitle(
          title: 'Report Notes',
          subtitle:
              'Automatically summarized from available municipality records.',
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _paperSoft,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: _paperBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              for (final note in notes)
                Padding(
                  padding:
                      const EdgeInsets.only(
                    bottom: 7,
                  ),
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        margin:
                            const EdgeInsets.only(
                          top: 5,
                        ),
                        decoration:
                            const BoxDecoration(
                          color:
                              SubTenantColors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          note,
                          style:
                              const TextStyle(
                            color: _paperMuted,
                            fontSize: 9.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / Loading / Error
// ─────────────────────────────────────────────────────────────────────────────

class _PaperEmptyState extends StatelessWidget {
  const _PaperEmptyState({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _paperSoft,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: _paperBorder,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.description_outlined,
            color: _paperMuted,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _paperMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: SubTenantColors.blue,
          ),
          SizedBox(height: 14),
          Text(
            'Preparing municipality reports...',
            style: TextStyle(
              color: SubTenantColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 420,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: _red,
              size: 38,
            ),
            const SizedBox(height: 12),
            const Text(
              'Unable to load reports',
              style: TextStyle(
                color: _paperText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _paperMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(
                Icons.refresh_rounded,
                size: 16,
              ),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Utilities
// ─────────────────────────────────────────────────────────────────────────────

String _dateStr(DateTime? date) {
  if (date == null) return '-';

  return DateFormat('MMM d, yyyy').format(date);
}

String _percent(double value) {
  return '${(value * 100).toStringAsFixed(0)}%';
}

String _percentageFromCount(
  int value,
  int total,
) {
  if (total <= 0) return '0%';

  return '${((value / total) * 100).toStringAsFixed(0)}%';
}

String _pdfPercent(
  int value,
  int total,
) {
  if (total == 0) return '0%';

  return '${((value / total) * 100).toStringAsFixed(0)}%';
}

String _shortText(
  String? text,
  int max,
) {
  if (text == null || text.trim().isEmpty) {
    return '-';
  }

  final value = text.trim();

  if (value.length <= max) {
    return value;
  }

  return '${value.substring(0, max)}…';
}

String _displayStatus(String value) {
  if (value.trim().isEmpty) {
    return '-';
  }

  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) {
        if (word.length == 1) {
          return word.toUpperCase();
        }

        return '${word[0].toUpperCase()}'
            '${word.substring(1).toLowerCase()}';
      })
      .join(' ');
}

String _slugify(String text) {
  return text
      .toLowerCase()
      .replaceAll(
        RegExp(r'[^a-z0-9]+'),
        '-',
      )
      .replaceAll(
        RegExp(r'^-+|-+$'),
        '',
      );
}