import 'dart:math' as math;
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

// ─────────────────────────────────────────────────────────────────────────────
// Constants / colors
// ─────────────────────────────────────────────────────────────────────────────

const _allCities = 'All Cities';

const _paperWorkspace = Color(0xFFF1F5F9);
const _paperBorder = Color(0xFFDCE4EE);
const _paperText = Color(0xFF172033);
const _paperMuted = Color(0xFF667085);
const _paperSoft = Color(0xFFF8FAFC);

const _green = Color(0xFF16A34A);
const _amber = Color(0xFFF59E0B);
const _purple = Color(0xFF7C3AED);
const _cyan = Color(0xFF0EA5E9);
const _red = Color(0xFFDC2626);

// ─────────────────────────────────────────────────────────────────────────────
// Tabs
// ─────────────────────────────────────────────────────────────────────────────

enum _ReportTab {
  overview(
    'Overview',
    'Provincial Tourism Summary Report',
    Icons.dashboard_outlined,
  ),
  bookings(
    'Bookings',
    'Provincial Booking Activity Report',
    Icons.receipt_long_outlined,
  ),
  revenue(
    'Revenue',
    'Provincial Revenue Report',
    Icons.payments_outlined,
  ),
  packages(
    'Packages',
    'Tourism Package Performance Report',
    Icons.inventory_2_outlined,
  ),
  spots(
    'Tourist Spots',
    'Tourist Spot Report',
    Icons.place_outlined,
  ),
  drivers(
    'Drivers',
    'Driver Coverage Report',
    Icons.badge_outlined,
  ),
  feedback(
    'Feedback',
    'Visitor Feedback and Ratings Report',
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
  daily('Today'),
  weekly('This Week'),
  monthly('This Month'),
  yearly('This Year'),
  allTime('All Time'),
  custom('Custom Range');

  const _DatePreset(this.label);

  final String label;
}

// ─────────────────────────────────────────────────────────────────────────────
// Date window
// ─────────────────────────────────────────────────────────────────────────────

class _ReportWindow {
  const _ReportWindow({
    required this.start,
    required this.end,
    required this.label,
  });

  final DateTime start;
  final DateTime end;
  final String label;

  bool contains(DateTime? date) {
    if (date == null) return false;

    return !date.isBefore(start) && !date.isAfter(end);
  }

  String get formatted {
    if (label == 'All Time') {
      return 'All available records';
    }

    return '${DateFormat.yMMMd().format(start)} – '
        '${DateFormat.yMMMd().format(end)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Report models
// ─────────────────────────────────────────────────────────────────────────────

class _ProvinceSnapshot {
  const _ProvinceSnapshot({
    required this.cityFilter,
    required this.window,
    required this.generatedAt,
    required this.tenants,
    required this.packages,
    required this.spots,
    required this.bookings,
    required this.feedback,
    required this.cityRows,
    required this.totalBookings,
    required this.completedBookings,
    required this.cancelledBookings,
    required this.pendingBookings,
    required this.totalRevenue,
    required this.totalPackages,
    required this.totalSpots,
    required this.totalDrivers,
    required this.totalFeedback,
    required this.averageRating,
  });

  final String cityFilter;
  final _ReportWindow window;
  final DateTime generatedAt;

  final List<CityTenant> tenants;
  final List<ProvincePackage> packages;
  final List<ProvinceSpot> spots;
  final List<ProvinceBooking> bookings;
  final List<ProvinceFeedback> feedback;

  final List<_CityPerformanceRow> cityRows;

  final int totalBookings;
  final int completedBookings;
  final int cancelledBookings;
  final int pendingBookings;

  final double totalRevenue;

  final int totalPackages;
  final int totalSpots;
  final int totalDrivers;
  final int totalFeedback;

  final double averageRating;
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

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class ProvinceReportsScreen extends StatefulWidget {
  const ProvinceReportsScreen({super.key});

  @override
  State<ProvinceReportsScreen> createState() =>
      _ProvinceReportsScreenState();
}

class _ProvinceReportsScreenState extends State<ProvinceReportsScreen>
    with SingleTickerProviderStateMixin {
  final ProvincialAdminService _service = ProvincialAdminService();

  late Future<AdminReportData> _future;
  late TabController _tabController;

  String _selectedCity = _allCities;
  _DatePreset _datePreset = _DatePreset.monthly;

  DateTimeRange? _customRange;

  bool _isExporting = false;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: _ReportTab.values.length,
      vsync: this,
    );

    _future = _service.fetchReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _service.fetchReports();
    });
  }

  void _setCity(String? city) {
    if (city == null) return;

    setState(() {
      _selectedCity = city;
    });
  }

  void _setDatePreset(_DatePreset preset) {
    if (preset == _DatePreset.custom) {
      _pickCustomRange();
      return;
    }

    setState(() {
      _datePreset = preset;
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(
        const Duration(days: 365),
      ),
      initialDateRange: _customRange ??
          DateTimeRange(
            start: DateTime(
              now.year,
              now.month,
              1,
            ),
            end: now,
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme:
                Theme.of(context).colorScheme.copyWith(
                      primary:
                          ProvincialAdminColors.deepBlue,
                    ),
          ),
          child: child!,
        );
      },
    );

    if (range == null || !mounted) return;

    setState(() {
      _customRange = range;
      _datePreset = _DatePreset.custom;
    });
  }

  _ReportWindow _resolveWindow() {
    final now = DateTime.now();

    switch (_datePreset) {
      case _DatePreset.daily:
        return _ReportWindow(
          start: DateTime(
            now.year,
            now.month,
            now.day,
          ),
          end: DateTime(
            now.year,
            now.month,
            now.day,
            23,
            59,
            59,
            999,
          ),
          label: 'Today',
        );

      case _DatePreset.weekly:
        final start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(
          Duration(
            days: now.weekday - 1,
          ),
        );

        return _ReportWindow(
          start: start,
          end: DateTime(
            now.year,
            now.month,
            now.day,
            23,
            59,
            59,
            999,
          ),
          label: 'This Week',
        );

      case _DatePreset.monthly:
        return _ReportWindow(
          start: DateTime(
            now.year,
            now.month,
            1,
          ),
          end: DateTime(
            now.year,
            now.month + 1,
            0,
            23,
            59,
            59,
            999,
          ),
          label: 'This Month',
        );

      case _DatePreset.yearly:
        return _ReportWindow(
          start: DateTime(
            now.year,
            1,
            1,
          ),
          end: DateTime(
            now.year,
            12,
            31,
            23,
            59,
            59,
            999,
          ),
          label: 'This Year',
        );

      case _DatePreset.allTime:
        return _ReportWindow(
          start: DateTime(2020),
          end: DateTime(
            now.year + 1,
            12,
            31,
          ),
          label: 'All Time',
        );

      case _DatePreset.custom:
        final range = _customRange ??
            DateTimeRange(
              start: DateTime(
                now.year,
                now.month,
                1,
              ),
              end: now,
            );

        return _ReportWindow(
          start: DateTime(
            range.start.year,
            range.start.month,
            range.start.day,
          ),
          end: DateTime(
            range.end.year,
            range.end.month,
            range.end.day,
            23,
            59,
            59,
            999,
          ),
          label: 'Custom Range',
        );
    }
  }

  List<String> _availableCities(
    AdminReportData data,
  ) {
    final result = <String>{
      ...data.tenants.map((e) => e.city),
      ...data.packages.map((e) => e.city),
      ...data.spots.map((e) => e.city),
      ...data.bookings.map((e) => e.city),
      ...data.feedback.map((e) => e.city),
    }
        .map(
          (city) => city.trim(),
        )
        .where(
          (city) =>
              city.isNotEmpty &&
              city.toLowerCase() != 'unknown',
        )
        .toSet()
        .toList();

    result.sort();

    return [
      _allCities,
      ...result,
    ];
  }

  _ProvinceSnapshot _buildSnapshot(
    AdminReportData data,
  ) {
    final window = _resolveWindow();

    bool cityMatches(String value) {
      if (_selectedCity == _allCities) {
        return true;
      }

      return _sameCity(
        value,
        _selectedCity,
      );
    }

    final tenants = data.tenants
        .where(
          (item) => cityMatches(item.city),
        )
        .toList();

    final packages = data.packages
        .where(
          (item) => cityMatches(item.city),
        )
        .toList();

    final spots = data.spots
        .where(
          (item) => cityMatches(item.city),
        )
        .toList();

    final bookings = data.bookings.where(
      (item) {
        final date =
            item.travelDate ?? item.createdAt;

        return cityMatches(item.city) &&
            window.contains(date);
      },
    ).toList();

    final feedback = data.feedback.where(
      (item) {
        return cityMatches(item.city) &&
            window.contains(item.createdAt);
      },
    ).toList();

    final completed = bookings
        .where(
          (item) =>
              item.status.toLowerCase() ==
              'completed',
        )
        .length;

    final cancelled = bookings
        .where(
          (item) =>
              item.status.toLowerCase() ==
              'cancelled',
        )
        .length;

    final pending = math.max(
      0,
      bookings.length -
          completed -
          cancelled,
    );

    final revenue = bookings.fold<double>(
      0,
      (sum, booking) {
        if (booking.status.toLowerCase() !=
            'completed') {
          return sum;
        }

        return sum + booking.totalAmount;
      },
    );

    final drivers = tenants.fold<int>(
      0,
      (sum, tenant) =>
          sum + tenant.driversCount,
    );

    final ratedFeedback = feedback
        .where(
          (item) => item.rating > 0,
        )
        .toList();

    final averageRating =
        ratedFeedback.isEmpty
            ? 0.0
            : ratedFeedback.fold<double>(
                    0,
                    (sum, item) =>
                        sum + item.rating,
                  ) /
                ratedFeedback.length;

    final cityRows = _buildCityRows(
      tenants: tenants,
      packages: packages,
      spots: spots,
      bookings: bookings,
      feedback: feedback,
    );

    return _ProvinceSnapshot(
      cityFilter: _selectedCity,
      window: window,
      generatedAt: DateTime.now(),
      tenants: tenants,
      packages: packages,
      spots: spots,
      bookings: bookings,
      feedback: feedback,
      cityRows: cityRows,
      totalBookings: bookings.length,
      completedBookings: completed,
      cancelledBookings: cancelled,
      pendingBookings: pending,
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
    final cities = <String>{
      ...tenants.map((e) => e.city),
      ...packages.map((e) => e.city),
      ...spots.map((e) => e.city),
      ...bookings.map((e) => e.city),
      ...feedback.map((e) => e.city),
    }
        .map(
          (city) => city.trim().isEmpty
              ? 'Unassigned'
              : city.trim(),
        )
        .toSet();

    final rows = <_CityPerformanceRow>[];

    for (final city in cities) {
      final cityTenants = tenants.where(
        (e) => _sameCity(e.city, city),
      );

      final cityPackages = packages.where(
        (e) => _sameCity(e.city, city),
      );

      final citySpots = spots.where(
        (e) => _sameCity(e.city, city),
      );

      final cityBookings = bookings
          .where(
            (e) => _sameCity(e.city, city),
          )
          .toList();

      final cityFeedback = feedback
          .where(
            (e) => _sameCity(e.city, city),
          )
          .toList();

      final completed = cityBookings
          .where(
            (e) =>
                e.status.toLowerCase() ==
                'completed',
          )
          .length;

      final cancelled = cityBookings
          .where(
            (e) =>
                e.status.toLowerCase() ==
                'cancelled',
          )
          .length;

      final revenue =
          cityBookings.fold<double>(
        0,
        (sum, item) {
          if (item.status.toLowerCase() !=
              'completed') {
            return sum;
          }

          return sum + item.totalAmount;
        },
      );

      final ratings = cityFeedback
          .where(
            (e) => e.rating > 0,
          )
          .toList();

      final avgRating =
          ratings.isEmpty
              ? 0.0
              : ratings.fold<double>(
                      0,
                      (sum, item) =>
                          sum + item.rating,
                    ) /
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
            (sum, tenant) =>
                sum + tenant.driversCount,
          ),
          feedbackCount:
              cityFeedback.length,
          averageRating: avgRating,
        ),
      );
    }

    rows.sort(
      (a, b) {
        final bookingComparison =
            b.bookings.compareTo(
          a.bookings,
        );

        if (bookingComparison != 0) {
          return bookingComparison;
        }

        return b.revenue.compareTo(
          a.revenue,
        );
      },
    );

    return rows;
  }

  Future<void> _downloadCurrentReport(
    _ProvinceSnapshot snapshot,
  ) async {
    if (_isExporting) return;

    final tab =
        _ReportTab.values[_tabController.index];

    setState(() {
      _isExporting = true;
    });

    try {
      final bytes = await _buildPdf(
        snapshot,
        tab,
      );

      final fileName =
          'touristrike-bulacan-'
          '${_slug(tab.label)}-'
          '${_slug(snapshot.cityFilter)}-'
          '${DateFormat('yyyyMMdd').format(DateTime.now())}'
          '.pdf';

      await Printing.sharePdf(
        bytes: bytes,
        filename: fileName,
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to generate PDF: $error',
          ),
        ),
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

  Future<Uint8List> _buildPdf(
    _ProvinceSnapshot report,
    _ReportTab tab,
  ) async {
    final document = pw.Document();

    final dark =
        PdfColor.fromHex('#172033');

    final muted =
        PdfColor.fromHex('#667085');

    final blue =
        PdfColor.fromHex('#1557D6');

    final soft =
        PdfColor.fromHex('#F8FAFC');

    final money = NumberFormat.currency(
      symbol: 'PHP ',
      decimalDigits: 0,
    );

    pw.Widget metric(
      String label,
      String value,
      String helper,
    ) {
      return pw.Container(
        width: 150,
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          color: soft,
          borderRadius:
              pw.BorderRadius.circular(4),
          border: pw.Border.all(
            color: PdfColors.grey300,
          ),
        ),
        child: pw.Column(
          crossAxisAlignment:
              pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 7.5,
                color: muted,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(
                color: dark,
                fontSize: 13,
                fontWeight:
                    pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              helper,
              style: pw.TextStyle(
                color: muted,
                fontSize: 7,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget section(
      String title, {
      String? subtitle,
    }) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(
          top: 16,
          bottom: 7,
        ),
        child: pw.Column(
          crossAxisAlignment:
              pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                color: dark,
                fontSize: 11,
                fontWeight:
                    pw.FontWeight.bold,
              ),
            ),
            if (subtitle != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                subtitle,
                style: pw.TextStyle(
                  color: muted,
                  fontSize: 7.5,
                ),
              ),
            ],
          ],
        ),
      );
    }

    pw.Widget table({
      required List<String> columns,
      required List<List<String>> rows,
      required String emptyMessage,
    }) {
      if (rows.isEmpty) {
        return pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: soft,
            border: pw.Border.all(
              color: PdfColors.grey300,
            ),
          ),
          child: pw.Text(
            emptyMessage,
            style: pw.TextStyle(
              fontSize: 8,
              color: muted,
            ),
          ),
        );
      }

      return pw.TableHelper.fromTextArray(
        headers: columns,
        data: rows,
        border: pw.TableBorder.all(
          color: PdfColors.grey300,
          width: .5,
        ),
        headerDecoration:
            pw.BoxDecoration(
          color: soft,
        ),
        headerStyle: pw.TextStyle(
          color: dark,
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: pw.TextStyle(
          color: dark,
          fontSize: 7.2,
        ),
        cellPadding:
            const pw.EdgeInsets.symmetric(
          horizontal: 5,
          vertical: 5,
        ),
      );
    }

    List<pw.Widget> body() {
      switch (tab) {
        case _ReportTab.overview:
          return [
            section(
              'Executive Summary',
              subtitle:
                  'Province-wide tourism performance for the selected reporting period.',
            ),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Bookings',
                  '${report.totalBookings}',
                  'Recorded bookings',
                ),
                metric(
                  'Completed',
                  '${report.completedBookings}',
                  'Completed transactions',
                ),
                metric(
                  'Revenue',
                  money.format(
                    report.totalRevenue,
                  ),
                  'Completed bookings',
                ),
                metric(
                  'Packages',
                  '${report.totalPackages}',
                  'Tourism packages',
                ),
                metric(
                  'Tourist Spots',
                  '${report.totalSpots}',
                  'Registered destinations',
                ),
                metric(
                  'Drivers',
                  '${report.totalDrivers}',
                  'Registered drivers',
                ),
              ],
            ),
            section(
              'City / Municipality Performance',
            ),
            table(
              columns: const [
                'City',
                'Bookings',
                'Completed',
                'Revenue',
                'Packages',
                'Spots',
                'Drivers',
                'Rating',
              ],
              rows: report.cityRows.map(
                (row) {
                  return [
                    row.city,
                    '${row.bookings}',
                    '${row.completed}',
                    money.format(
                      row.revenue,
                    ),
                    '${row.packages}',
                    '${row.spots}',
                    '${row.drivers}',
                    row.averageRating == 0
                        ? 'N/A'
                        : row.averageRating
                            .toStringAsFixed(1),
                  ];
                },
              ).toList(),
              emptyMessage:
                  'No city performance records available.',
            ),
          ];

        case _ReportTab.bookings:
          return [
            section('Booking Summary'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Total Bookings',
                  '${report.totalBookings}',
                  'All booking states',
                ),
                metric(
                  'Completed',
                  '${report.completedBookings}',
                  _percentageFromCount(
                    report.completedBookings,
                    report.totalBookings,
                  ),
                ),
                metric(
                  'Cancelled',
                  '${report.cancelledBookings}',
                  _percentageFromCount(
                    report.cancelledBookings,
                    report.totalBookings,
                  ),
                ),
                metric(
                  'Pending / Other',
                  '${report.pendingBookings}',
                  _percentageFromCount(
                    report.pendingBookings,
                    report.totalBookings,
                  ),
                ),
              ],
            ),
            section('Booking Records'),
            table(
              columns: const [
                'Date',
                'City',
                'Tourist',
                'Package',
                'Status',
                'Amount',
              ],
              rows: report.bookings.map(
                (booking) {
                  return [
                    _date(
                      booking.travelDate ??
                          booking.createdAt,
                    ),
                    booking.city,
                    _shortText(
                      booking.touristName,
                      20,
                    ),
                    _shortText(
                      booking.packageTitle,
                      24,
                    ),
                    adminTitleCase(
                      booking.status,
                    ),
                    money.format(
                      booking.totalAmount,
                    ),
                  ];
                },
              ).toList(),
              emptyMessage:
                  'No bookings were recorded during this reporting period.',
            ),
          ];

        case _ReportTab.revenue:
          return [
            section('Revenue Summary'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Completed Revenue',
                  money.format(
                    report.totalRevenue,
                  ),
                  'Completed bookings',
                ),
                metric(
                  'Completed Bookings',
                  '${report.completedBookings}',
                  'Revenue-generating bookings',
                ),
                metric(
                  'Average Value',
                  report.completedBookings == 0
                      ? money.format(0)
                      : money.format(
                          report.totalRevenue /
                              report.completedBookings,
                        ),
                  'Average completed booking',
                ),
              ],
            ),
            section('Revenue by City / Municipality'),
            table(
              columns: const [
                'City',
                'Completed',
                'Revenue',
                'Average Value',
              ],
              rows: report.cityRows
                  .where(
                    (row) =>
                        row.completed > 0 ||
                        row.revenue > 0,
                  )
                  .map(
                    (row) => [
                      row.city,
                      '${row.completed}',
                      money.format(
                        row.revenue,
                      ),
                      row.completed == 0
                          ? money.format(0)
                          : money.format(
                              row.revenue /
                                  row.completed,
                            ),
                    ],
                  )
                  .toList(),
              emptyMessage:
                  'No completed booking revenue is available.',
            ),
          ];

        case _ReportTab.packages:
          final stats =
              _packageStats(report.bookings);

          return [
            section('Package Summary'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Packages',
                  '${report.totalPackages}',
                  'Registered packages',
                ),
                metric(
                  'Bookings',
                  '${report.totalBookings}',
                  'Selected period',
                ),
                metric(
                  'Revenue',
                  money.format(
                    report.totalRevenue,
                  ),
                  'Completed bookings',
                ),
              ],
            ),
            section(
              'Package Performance',
            ),
            table(
              columns: const [
                'Package',
                'City',
                'Bookings',
                'Revenue',
                'Budget',
                'Status',
              ],
              rows: report.packages.map(
                (package) {
                  final stat = stats[
                          _packageKey(
                            package.id,
                            package.title,
                          )] ??
                      _MutableStats();

                  return [
                    _shortText(
                      package.title,
                      25,
                    ),
                    package.city,
                    '${stat.count}',
                    money.format(
                      stat.amount,
                    ),
                    package.estimatedBudget == 0
                        ? 'N/A'
                        : money.format(
                            package.estimatedBudget,
                          ),
                    adminTitleCase(
                      package.status,
                    ),
                  ];
                },
              ).toList(),
              emptyMessage:
                  'No tourism package records found.',
            ),
          ];

        case _ReportTab.spots:
          return [
            section('Tourist Spot Summary'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Tourist Spots',
                  '${report.totalSpots}',
                  'Registered destinations',
                ),
                metric(
                  'Cities Covered',
                  '${report.cityRows.where((e) => e.spots > 0).length}',
                  'With tourist spots',
                ),
              ],
            ),
            section('Tourist Spot Records'),
            table(
              columns: const [
                'Tourist Spot',
                'City',
                'Barangay',
                'Rating',
                'Verification',
              ],
              rows: report.spots.map(
                (spot) {
                  return [
                    _shortText(
                      spot.title,
                      28,
                    ),
                    spot.city,
                    spot.barangay.isEmpty
                        ? 'N/A'
                        : spot.barangay,
                    spot.rating == 0
                        ? 'N/A'
                        : spot.rating
                            .toStringAsFixed(1),
                    adminTitleCase(
                      spot.verificationStatus,
                    ),
                  ];
                },
              ).toList(),
              emptyMessage:
                  'No tourist spot records found.',
            ),
          ];

        case _ReportTab.drivers:
          return [
            section('Driver Coverage Summary'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Registered Drivers',
                  '${report.totalDrivers}',
                  'Across selected LGUs',
                ),
                metric(
                  'Municipal Offices',
                  '${report.tenants.length}',
                  'Included subtenants',
                ),
              ],
            ),
            section('Driver Coverage'),
            table(
              columns: const [
                'City',
                'Admin Office',
                'Drivers',
                'Bookings',
                'Packages',
                'Status',
              ],
              rows: report.tenants.map(
                (tenant) {
                  final row = report.cityRows
                      .where(
                        (e) => _sameCity(
                          e.city,
                          tenant.city,
                        ),
                      )
                      .toList();

                  final bookings =
                      row.isEmpty
                          ? tenant.bookingsCount
                          : row.first.bookings;

                  return [
                    tenant.city,
                    tenant.adminName,
                    '${tenant.driversCount}',
                    '$bookings',
                    '${tenant.packagesCount}',
                    adminTitleCase(
                      tenant.status,
                    ),
                  ];
                },
              ).toList(),
              emptyMessage:
                  'No driver coverage records found.',
            ),
          ];

        case _ReportTab.feedback:
          return [
            section('Feedback Summary'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                metric(
                  'Feedback',
                  '${report.totalFeedback}',
                  'Submitted reviews',
                ),
                metric(
                  'Average Rating',
                  report.averageRating == 0
                      ? 'N/A'
                      : '${report.averageRating.toStringAsFixed(1)} / 5',
                  'Province-wide average',
                ),
              ],
            ),
            section('Ratings by City'),
            table(
              columns: const [
                'City',
                'Feedback',
                'Average Rating',
                'Bookings',
              ],
              rows: report.cityRows
                  .where(
                    (row) =>
                        row.feedbackCount > 0,
                  )
                  .map(
                    (row) => [
                      row.city,
                      '${row.feedbackCount}',
                      row.averageRating == 0
                          ? 'N/A'
                          : row.averageRating
                              .toStringAsFixed(1),
                      '${row.bookings}',
                    ],
                  )
                  .toList(),
              emptyMessage:
                  'No visitor ratings were submitted.',
            ),
            section('Recent Feedback'),
            table(
              columns: const [
                'Date',
                'City',
                'Reviewer',
                'Subject',
                'Rating',
                'Comment',
              ],
              rows: report.feedback.map(
                (item) => [
                  _date(item.createdAt),
                  item.city,
                  _shortText(
                    item.reviewerName,
                    18,
                  ),
                  _shortText(
                    item.subjectName,
                    18,
                  ),
                  item.rating == 0
                      ? 'N/A'
                      : item.rating
                          .toStringAsFixed(1),
                  _shortText(
                    item.comment,
                    38,
                  ),
                ],
              ).toList(),
              emptyMessage:
                  'No feedback records were submitted.',
            ),
          ];
      }
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          36,
          36,
          36,
          36,
        ),
        header: (_) {
          return pw.Column(
            children: [
              pw.Row(
                children: [
                  pw.Container(
                    width: 40,
                    height: 40,
                    alignment:
                        pw.Alignment.center,
                    decoration:
                        pw.BoxDecoration(
                      border: pw.Border.all(
                        color: blue,
                      ),
                      borderRadius:
                          pw.BorderRadius.circular(
                        6,
                      ),
                    ),
                    child: pw.Text(
                      'TT',
                      style: pw.TextStyle(
                        color: blue,
                        fontSize: 13,
                        fontWeight:
                            pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment:
                          pw.CrossAxisAlignment
                              .start,
                      children: [
                        pw.Text(
                          'TOURISTRIKE',
                          style: pw.TextStyle(
                            color: dark,
                            fontSize: 15,
                            fontWeight:
                                pw.FontWeight
                                    .bold,
                          ),
                        ),
                        pw.Text(
                          'Bulacan Provincial Tourism Office',
                          style: pw.TextStyle(
                            color: muted,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'OFFICIAL PROVINCIAL REPORT',
                        style: pw.TextStyle(
                          color: blue,
                          fontSize: 7.5,
                          fontWeight:
                              pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Generated ${DateFormat.yMMMd().format(report.generatedAt)}',
                        style: pw.TextStyle(
                          color: muted,
                          fontSize: 7,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Divider(
                color: PdfColors.grey300,
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                tab.reportTitle.toUpperCase(),
                textAlign:
                    pw.TextAlign.center,
                style: pw.TextStyle(
                  color: dark,
                  fontSize: 14,
                  fontWeight:
                      pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                report.cityFilter ==
                        _allCities
                    ? 'Province of Bulacan'
                    : '${report.cityFilter}, Bulacan',
                style: pw.TextStyle(
                  color: dark,
                  fontSize: 10,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Reporting Period: ${report.window.formatted}',
                style: pw.TextStyle(
                  color: muted,
                  fontSize: 8,
                ),
              ),
              pw.SizedBox(height: 10),
            ],
          );
        },
        footer: (context) {
          return pw.Column(
            children: [
              pw.Divider(
                color: PdfColors.grey300,
              ),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment
                        .spaceBetween,
                children: [
                  pw.Text(
                    'TourisTrike • Bulacan Provincial Tourism Office',
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
        build: (_) => body(),
      ),
    );

    return document.save();
  }

  @override
  Widget build(BuildContext context) {
    return ProvincialAdminShell(
      current:
          ProvincialAdminDestination.reports,
      title: 'Provincial Reports',
      subtitle:
          'Official province-wide tourism reports and performance records.',
      child: FutureBuilder<AdminReportData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const AdminLoadingView();
          }

          if (snapshot.hasError) {
            return AdminErrorView(
              message:
                  snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final data = snapshot.data!;

          final cities =
              _availableCities(data);

          if (!cities.contains(
            _selectedCity,
          )) {
            _selectedCity = _allCities;
          }

          final report =
              _buildSnapshot(data);

          return Container(
            color: _paperWorkspace,
            child: Column(
              children: [
                _ReportsToolbar(
                  snapshot: report,
                  cityOptions: cities,
                  onCityChanged: _setCity,
                  onDateChanged:
                      _setDatePreset,
                  onDownload: () =>
                      _downloadCurrentReport(
                    report,
                  ),
                  isDownloading:
                      _isExporting,
                ),
                _ReportsTabBar(
                  controller:
                      _tabController,
                ),
                Expanded(
                  child: TabBarView(
                    controller:
                        _tabController,
                    children: [
                      _OverviewReport(
                        snapshot: report,
                      ),
                      _BookingsReport(
                        snapshot: report,
                      ),
                      _RevenueReport(
                        snapshot: report,
                      ),
                      _PackagesReport(
                        snapshot: report,
                      ),
                      _SpotsReport(
                        snapshot: report,
                      ),
                      _DriversReport(
                        snapshot: report,
                      ),
                      _FeedbackReport(
                        snapshot: report,
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
// Toolbar
// ─────────────────────────────────────────────────────────────────────────────

class _ReportsToolbar extends StatelessWidget {
  const _ReportsToolbar({
    required this.snapshot,
    required this.cityOptions,
    required this.onCityChanged,
    required this.onDateChanged,
    required this.onDownload,
    required this.isDownloading,
  });

  final _ProvinceSnapshot snapshot;
  final List<String> cityOptions;

  final ValueChanged<String?>
      onCityChanged;

  final ValueChanged<_DatePreset>
      onDateChanged;

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
          final compact =
              constraints.maxWidth < 850;

          final identity = Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      ProvincialAdminColors.blue
                          .withValues(
                    alpha: .08,
                  ),
                  borderRadius:
                      BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.account_balance_outlined,
                  color:
                      ProvincialAdminColors
                          .blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Province of Bulacan',
                      style: TextStyle(
                        color: _paperText,
                        fontSize: 15,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Provincial Tourism Reports',
                      style: TextStyle(
                        color: _paperMuted,
                        fontSize: 10.5,
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
            crossAxisAlignment:
                WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 160,
                child:
                    DropdownButtonFormField<
                        String>(
                  initialValue:
                      snapshot.cityFilter,
                  isExpanded: true,
                  decoration:
                      _toolbarInputDecoration(
                    Icons.location_city_outlined,
                  ),
                  style: const TextStyle(
                    color: _paperText,
                    fontSize: 10.5,
                    fontWeight:
                        FontWeight.w600,
                  ),
                  items: cityOptions
                      .map(
                        (city) =>
                            DropdownMenuItem(
                          value: city,
                          child: Text(
                            city,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged:
                      onCityChanged,
                ),
              ),
              Container(
                height: 38,
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 11,
                ),
                decoration: BoxDecoration(
                  color: _paperSoft,
                  borderRadius:
                      BorderRadius.circular(9),
                  border: Border.all(
                    color: _paperBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      color: _paperMuted,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      snapshot.window.formatted,
                      style:
                          const TextStyle(
                        color: _paperText,
                        fontSize: 10.5,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<
                  _DatePreset>(
                tooltip:
                    'Change reporting period',
                onSelected:
                    onDateChanged,
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(10),
                ),
                itemBuilder: (_) {
                  return _DatePreset.values
                      .map(
                    (preset) {
                      return PopupMenuItem(
                        value: preset,
                        child: Text(
                          preset.label,
                        ),
                      );
                    },
                  ).toList();
                },
                child: Container(
                  height: 38,
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(9),
                    border: Border.all(
                      color: _paperBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.window.label,
                        style:
                            const TextStyle(
                          color: _paperText,
                          fontSize: 10.5,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons
                            .keyboard_arrow_down_rounded,
                        color: _paperMuted,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: isDownloading
                    ? null
                    : onDownload,
                icon: isDownloading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child:
                            CircularProgressIndicator(
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
                      ? 'Generating...'
                      : 'Download PDF',
                ),
                style:
                    ElevatedButton.styleFrom(
                  elevation: 0,
                  minimumSize:
                      const Size(0, 38),
                  backgroundColor:
                      ProvincialAdminColors
                          .deepBlue,
                  foregroundColor:
                      Colors.white,
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 14,
                  ),
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(9),
                  ),
                  textStyle:
                      const TextStyle(
                    fontSize: 10.5,
                    fontWeight:
                        FontWeight.w700,
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
                identity,
                const SizedBox(height: 12),
                controls,
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: identity,
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

InputDecoration _toolbarInputDecoration(
  IconData icon,
) {
  return InputDecoration(
    prefixIcon: Icon(
      icon,
      size: 16,
      color: _paperMuted,
    ),
    filled: true,
    fillColor: _paperSoft,
    isDense: true,
    contentPadding:
        const EdgeInsets.symmetric(
      vertical: 10,
    ),
    enabledBorder:
        OutlineInputBorder(
      borderRadius:
          BorderRadius.circular(9),
      borderSide:
          const BorderSide(
        color: _paperBorder,
      ),
    ),
    focusedBorder:
        OutlineInputBorder(
      borderRadius:
          BorderRadius.circular(9),
      borderSide:
          const BorderSide(
        color:
            ProvincialAdminColors.blue,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tabs
// ─────────────────────────────────────────────────────────────────────────────

class _ReportsTabBar extends StatelessWidget {
  const _ReportsTabBar({
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
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _paperSoft,
          borderRadius:
              BorderRadius.circular(10),
          border: Border.all(
            color: _paperBorder,
          ),
        ),
        child: TabBar(
          controller: controller,
          isScrollable: true,
          tabAlignment:
              TabAlignment.start,
          dividerColor:
              Colors.transparent,
          indicatorSize:
              TabBarIndicatorSize.tab,
          indicator:
              BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(8),
            border: Border.all(
              color: _paperBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(
                  alpha: .04,
                ),
                blurRadius: 4,
                offset:
                    const Offset(0, 1),
              ),
            ],
          ),
          labelColor:
              ProvincialAdminColors
                  .deepBlue,
          unselectedLabelColor:
              _paperMuted,
          labelStyle:
              const TextStyle(
            fontSize: 11,
            fontWeight:
                FontWeight.w700,
          ),
          unselectedLabelStyle:
              const TextStyle(
            fontSize: 11,
            fontWeight:
                FontWeight.w600,
          ),
          tabs:
              _ReportTab.values.map(
            (tab) {
              return Tab(
                height: 36,
                child: Row(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Icon(
                      tab.icon,
                      size: 15,
                    ),
                    const SizedBox(
                      width: 6,
                    ),
                    Text(
                      tab.label,
                    ),
                  ],
                ),
              );
            },
          ).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overview
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewReport
    extends StatelessWidget {
  const _OverviewReport({
    required this.snapshot,
  });

  final _ProvinceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle:
            'Provincial Tourism Summary Report',
        location:
            snapshot.cityFilter ==
                    _allCities
                ? 'Province of Bulacan'
                : '${snapshot.cityFilter}, Bulacan',
        period:
            snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title: 'Executive Summary',
            subtitle:
                'Overall tourism activity and administrative coverage for the selected reporting period.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label: 'Bookings',
                value:
                    '${snapshot.totalBookings}',
                helper:
                    'Recorded bookings',
              ),
              _PaperMetric(
                label: 'Completed',
                value:
                    '${snapshot.completedBookings}',
                helper:
                    _percentageFromCount(
                  snapshot
                      .completedBookings,
                  snapshot.totalBookings,
                ),
              ),
              _PaperMetric(
                label: 'Revenue',
                value: _money(
                  snapshot.totalRevenue,
                ),
                helper:
                    'Completed bookings',
              ),
              _PaperMetric(
                label: 'Packages',
                value:
                    '${snapshot.totalPackages}',
                helper:
                    'Tourism packages',
              ),
              _PaperMetric(
                label: 'Tourist Spots',
                value:
                    '${snapshot.totalSpots}',
                helper:
                    'Registered destinations',
              ),
              _PaperMetric(
                label: 'Drivers',
                value:
                    '${snapshot.totalDrivers}',
                helper:
                    'Registered drivers',
              ),
            ],
          ),
          const SizedBox(height: 26),
          _PaperSectionTitle(
            title:
                'City / Municipality Performance',
            subtitle:
                '${snapshot.cityRows.length} LGU record(s) included.',
          ),
          _PaperTable(
            columns: const [
              'City',
              'Bookings',
              'Completed',
              'Revenue',
              'Packages',
              'Spots',
              'Drivers',
              'Rating',
            ],
            columnFlex: const [
              4,
              2,
              2,
              3,
              2,
              2,
              2,
              2,
            ],
            rows: snapshot.cityRows
                .take(9)
                .map(
                  (row) => [
                    row.city,
                    '${row.bookings}',
                    '${row.completed}',
                    _money(
                      row.revenue,
                    ),
                    '${row.packages}',
                    '${row.spots}',
                    '${row.drivers}',
                    row.averageRating == 0
                        ? '—'
                        : row.averageRating
                            .toStringAsFixed(
                              1,
                            ),
                  ],
                )
                .toList(),
          ),
          if (snapshot.cityRows.length >
              9)
            _MoreRowsNote(
              remaining:
                  snapshot.cityRows.length -
                      9,
            ),
          const SizedBox(height: 26),
          _OverviewNotes(
            snapshot: snapshot,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bookings
// ─────────────────────────────────────────────────────────────────────────────

class _BookingsReport
    extends StatelessWidget {
  const _BookingsReport({
    required this.snapshot,
  });

  final _ProvinceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle:
            'Provincial Booking Activity Report',
        location:
            _locationLabel(snapshot),
        period:
            snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title: 'Booking Summary',
            subtitle:
                'Booking activity recorded during the selected reporting period.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label:
                    'Total Bookings',
                value:
                    '${snapshot.totalBookings}',
                helper:
                    'All booking states',
              ),
              _PaperMetric(
                label: 'Completed',
                value:
                    '${snapshot.completedBookings}',
                helper:
                    _percentageFromCount(
                  snapshot
                      .completedBookings,
                  snapshot.totalBookings,
                ),
              ),
              _PaperMetric(
                label: 'Cancelled',
                value:
                    '${snapshot.cancelledBookings}',
                helper:
                    _percentageFromCount(
                  snapshot
                      .cancelledBookings,
                  snapshot.totalBookings,
                ),
              ),
              _PaperMetric(
                label:
                    'Pending / Other',
                value:
                    '${snapshot.pendingBookings}',
                helper:
                    'Other booking states',
              ),
              _PaperMetric(
                label: 'Revenue',
                value: _money(
                  snapshot.totalRevenue,
                ),
                helper:
                    'Completed bookings',
              ),
            ],
          ),
          const SizedBox(height: 26),
          _PaperSectionTitle(
            title: 'Booking Records',
            subtitle:
                '${snapshot.bookings.length} booking record(s) found.',
          ),
          if (snapshot.bookings.isEmpty)
            const _PaperEmptyState(
              message:
                  'No bookings were recorded during this reporting period.',
            )
          else
            _PaperTable(
              columns: const [
                'Date',
                'City',
                'Tourist',
                'Package',
                'Status',
                'Amount',
              ],
              columnFlex: const [
                2,
                2,
                3,
                4,
                2,
                2,
              ],
              rows: snapshot.bookings
                  .take(9)
                  .map(
                    (booking) => [
                      _date(
                        booking.travelDate ??
                            booking.createdAt,
                      ),
                      booking.city,
                      _shortText(
                        booking
                            .touristName,
                        18,
                      ),
                      _shortText(
                        booking
                            .packageTitle,
                        24,
                      ),
                      adminTitleCase(
                        booking.status,
                      ),
                      _money(
                        booking
                            .totalAmount,
                      ),
                    ],
                  )
                  .toList(),
            ),
          if (snapshot.bookings.length >
              9)
            _MoreRowsNote(
              remaining:
                  snapshot.bookings.length -
                      9,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Revenue
// ─────────────────────────────────────────────────────────────────────────────

class _RevenueReport
    extends StatelessWidget {
  const _RevenueReport({
    required this.snapshot,
  });

  final _ProvinceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final average =
        snapshot.completedBookings == 0
            ? 0
            : snapshot.totalRevenue /
                snapshot.completedBookings;

    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle:
            'Provincial Revenue Report',
        location:
            _locationLabel(snapshot),
        period:
            snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title: 'Revenue Summary',
            subtitle:
                'Revenue generated from completed tourism package bookings.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label:
                    'Completed Revenue',
                value: _money(
                  snapshot.totalRevenue,
                ),
                helper:
                    'Completed bookings',
              ),
              _PaperMetric(
                label:
                    'Completed Bookings',
                value:
                    '${snapshot.completedBookings}',
                helper:
                    'Revenue-generating bookings',
              ),
              _PaperMetric(
                label:
                    'Average Booking Value',
                value:
                    _money(average),
                helper:
                    'Per completed booking',
              ),
            ],
          ),
          const SizedBox(height: 26),
          const _PaperSectionTitle(
            title:
                'Revenue by City / Municipality',
          ),
          _PaperTable(
            columns: const [
              'City',
              'Completed',
              'Revenue',
              'Average Value',
            ],
            columnFlex: const [
              4,
              2,
              3,
              3,
            ],
            rows: snapshot.cityRows
                .where(
                  (row) =>
                      row.completed > 0 ||
                      row.revenue > 0,
                )
                .take(10)
                .map(
                  (row) => [
                    row.city,
                    '${row.completed}',
                    _money(
                      row.revenue,
                    ),
                    row.completed == 0
                        ? _money(0)
                        : _money(
                            row.revenue /
                                row.completed,
                          ),
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Packages
// ─────────────────────────────────────────────────────────────────────────────

class _PackagesReport
    extends StatelessWidget {
  const _PackagesReport({
    required this.snapshot,
  });

  final _ProvinceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final stats =
        _packageStats(snapshot.bookings);

    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle:
            'Tourism Package Performance Report',
        location:
            _locationLabel(snapshot),
        period:
            snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title: 'Package Summary',
            subtitle:
                'Tourism package inventory and booking performance.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label: 'Packages',
                value:
                    '${snapshot.totalPackages}',
                helper:
                    'Registered packages',
              ),
              _PaperMetric(
                label:
                    'Period Bookings',
                value:
                    '${snapshot.totalBookings}',
                helper:
                    'Selected period',
              ),
              _PaperMetric(
                label: 'Revenue',
                value: _money(
                  snapshot.totalRevenue,
                ),
                helper:
                    'Completed bookings',
              ),
            ],
          ),
          const SizedBox(height: 26),
          _PaperSectionTitle(
            title:
                'Package Performance',
            subtitle:
                '${snapshot.packages.length} package(s) listed.',
          ),
          if (snapshot.packages.isEmpty)
            const _PaperEmptyState(
              message:
                  'No tourism packages were found.',
            )
          else
            _PaperTable(
              columns: const [
                'Package',
                'City',
                'Bookings',
                'Revenue',
                'Budget',
                'Status',
              ],
              columnFlex: const [
                4,
                2,
                2,
                3,
                3,
                2,
              ],
              rows: snapshot.packages
                  .take(9)
                  .map(
                    (package) {
                      final stat =
                          stats[
                                  _packageKey(
                                    package
                                        .id,
                                    package
                                        .title,
                                  )] ??
                              _MutableStats();

                      return [
                        _shortText(
                          package.title,
                          26,
                        ),
                        package.city,
                        '${stat.count}',
                        _money(
                          stat.amount,
                        ),
                        package.estimatedBudget ==
                                0
                            ? '—'
                            : _money(
                                package
                                    .estimatedBudget,
                              ),
                        adminTitleCase(
                          package.status,
                        ),
                      ];
                    },
                  )
                  .toList(),
            ),
          if (snapshot.packages.length >
              9)
            _MoreRowsNote(
              remaining:
                  snapshot.packages.length -
                      9,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tourist spots
// ─────────────────────────────────────────────────────────────────────────────

class _SpotsReport
    extends StatelessWidget {
  const _SpotsReport({
    required this.snapshot,
  });

  final _ProvinceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final verified =
        snapshot.spots.where(
      (spot) {
        final status =
            spot.verificationStatus
                .toLowerCase();

        return status == 'verified' ||
            status == 'approved';
      },
    ).length;

    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle:
            'Tourist Spot Report',
        location:
            _locationLabel(snapshot),
        period:
            snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title:
                'Tourist Spot Summary',
            subtitle:
                'Tourism destinations registered within the selected provincial coverage.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label:
                    'Registered Spots',
                value:
                    '${snapshot.totalSpots}',
                helper:
                    'Tourist destinations',
              ),
              _PaperMetric(
                label:
                    'Verified Spots',
                value: '$verified',
                helper:
                    'Verified / approved',
              ),
              _PaperMetric(
                label:
                    'Cities Covered',
                value:
                    '${snapshot.cityRows.where((row) => row.spots > 0).length}',
                helper:
                    'With spot records',
              ),
            ],
          ),
          const SizedBox(height: 26),
          _PaperSectionTitle(
            title:
                'Tourist Spot Records',
            subtitle:
                '${snapshot.spots.length} destination(s) listed.',
          ),
          if (snapshot.spots.isEmpty)
            const _PaperEmptyState(
              message:
                  'No tourist spot records were found.',
            )
          else
            _PaperTable(
              columns: const [
                'Tourist Spot',
                'City',
                'Barangay',
                'Rating',
                'Verification',
              ],
              columnFlex: const [
                4,
                2,
                3,
                2,
                3,
              ],
              rows: snapshot.spots
                  .take(10)
                  .map(
                    (spot) => [
                      _shortText(
                        spot.title,
                        30,
                      ),
                      spot.city,
                      spot.barangay.isEmpty
                          ? '—'
                          : spot.barangay,
                      spot.rating == 0
                          ? '—'
                          : spot.rating
                              .toStringAsFixed(
                                1,
                              ),
                      adminTitleCase(
                        spot
                            .verificationStatus,
                      ),
                    ],
                  )
                  .toList(),
            ),
          if (snapshot.spots.length >
              10)
            _MoreRowsNote(
              remaining:
                  snapshot.spots.length -
                      10,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drivers
// ─────────────────────────────────────────────────────────────────────────────

class _DriversReport
    extends StatelessWidget {
  const _DriversReport({
    required this.snapshot,
  });

  final _ProvinceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle:
            'Driver Coverage Report',
        location:
            _locationLabel(snapshot),
        period:
            snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title:
                'Driver Coverage Summary',
            subtitle:
                'Driver-tour guide coverage by municipal or city tourism office.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label:
                    'Registered Drivers',
                value:
                    '${snapshot.totalDrivers}',
                helper:
                    'Province coverage',
              ),
              _PaperMetric(
                label:
                    'Municipal Offices',
                value:
                    '${snapshot.tenants.length}',
                helper:
                    'Included subtenants',
              ),
            ],
          ),
          const SizedBox(height: 26),
          _PaperSectionTitle(
            title:
                'Driver Coverage Records',
            subtitle:
                '${snapshot.tenants.length} tourism office record(s) found.',
          ),
          if (snapshot.tenants.isEmpty)
            const _PaperEmptyState(
              message:
                  'No city or municipality driver coverage records were found.',
            )
          else
            _PaperTable(
              columns: const [
                'City',
                'Admin Office',
                'Drivers',
                'Bookings',
                'Packages',
                'Status',
              ],
              columnFlex: const [
                3,
                4,
                2,
                2,
                2,
                2,
              ],
              rows: snapshot.tenants
                  .take(10)
                  .map(
                    (tenant) {
                      final matches =
                          snapshot.cityRows
                              .where(
                        (row) =>
                            _sameCity(
                          row.city,
                          tenant.city,
                        ),
                      );

                      final bookings =
                          matches.isEmpty
                              ? tenant
                                  .bookingsCount
                              : matches
                                  .first
                                  .bookings;

                      return [
                        tenant.city,
                        _shortText(
                          tenant.adminName,
                          26,
                        ),
                        '${tenant.driversCount}',
                        '$bookings',
                        '${tenant.packagesCount}',
                        adminTitleCase(
                          tenant.status,
                        ),
                      ];
                    },
                  )
                  .toList(),
            ),
          if (snapshot.tenants.length >
              10)
            _MoreRowsNote(
              remaining:
                  snapshot.tenants.length -
                      10,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feedback
// ─────────────────────────────────────────────────────────────────────────────

class _FeedbackReport
    extends StatelessWidget {
  const _FeedbackReport({
    required this.snapshot,
  });

  final _ProvinceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _ReportWorkspace(
      child: _PaperReport(
        reportTitle:
            'Visitor Feedback and Ratings Report',
        location:
            _locationLabel(snapshot),
        period:
            snapshot.window.formatted,
        children: [
          const _PaperSectionTitle(
            title: 'Feedback Summary',
            subtitle:
                'Tourist feedback and rating activity during the selected reporting period.',
          ),
          _MetricGrid(
            metrics: [
              _PaperMetric(
                label:
                    'Feedback Entries',
                value:
                    '${snapshot.totalFeedback}',
                helper:
                    'Submitted reviews',
              ),
              _PaperMetric(
                label:
                    'Average Rating',
                value:
                    snapshot.averageRating ==
                            0
                        ? '—'
                        : snapshot
                            .averageRating
                            .toStringAsFixed(
                              1,
                            ),
                helper:
                    snapshot.averageRating ==
                            0
                        ? 'No ratings yet'
                        : 'Out of 5.0',
              ),
            ],
          ),
          const SizedBox(height: 26),
          const _PaperSectionTitle(
            title: 'Ratings by City',
          ),
          _PaperTable(
            columns: const [
              'City',
              'Feedback',
              'Average Rating',
              'Bookings',
            ],
            columnFlex: const [
              4,
              2,
              3,
              2,
            ],
            rows: snapshot.cityRows
                .where(
                  (row) =>
                      row.feedbackCount > 0,
                )
                .take(8)
                .map(
                  (row) => [
                    row.city,
                    '${row.feedbackCount}',
                    row.averageRating == 0
                        ? '—'
                        : row.averageRating
                            .toStringAsFixed(
                              1,
                            ),
                    '${row.bookings}',
                  ],
                )
                .toList(),
          ),
          const SizedBox(height: 26),
          const _PaperSectionTitle(
            title: 'Recent Feedback',
          ),
          if (snapshot.feedback.isEmpty)
            const _PaperEmptyState(
              message:
                  'No visitor feedback was submitted during this reporting period.',
            )
          else
            _PaperTable(
              columns: const [
                'Date',
                'City',
                'Reviewer',
                'Subject',
                'Rating',
                'Comment',
              ],
              columnFlex: const [
                2,
                2,
                3,
                3,
                2,
                5,
              ],
              rows: snapshot.feedback
                  .take(6)
                  .map(
                    (item) => [
                      _date(
                        item.createdAt,
                      ),
                      item.city,
                      _shortText(
                        item.reviewerName,
                        18,
                      ),
                      _shortText(
                        item.subjectName,
                        18,
                      ),
                      item.rating == 0
                          ? '—'
                          : item.rating
                              .toStringAsFixed(
                                1,
                              ),
                      _shortText(
                        item.comment,
                        38,
                      ),
                    ],
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Paper workspace
// ─────────────────────────────────────────────────────────────────────────────

class _ReportWorkspace
    extends StatelessWidget {
  const _ReportWorkspace({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _paperWorkspace,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          22,
          24,
          22,
          42,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Paper report
//
// Uses an explicit page height.
//
// This avoids the Spacer / IntrinsicHeight / unbounded-scroll issues that
// caused the Flutter Web mouse_tracker and RenderBox layout exceptions.
//
// Screen preview is intentionally one fixed paper page. Long tables show a
// limited number of rows here; the downloaded PDF contains all rows.
// ─────────────────────────────────────────────────────────────────────────────

class _PaperReport
    extends StatelessWidget {
  const _PaperReport({
    required this.reportTitle,
    required this.location,
    required this.period,
    required this.children,
  });

  final String reportTitle;
  final String location;
  final String period;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final width = math.min(
          820.0,
          constraints.maxWidth,
        );

        final compact =
            width < 600;

        return SizedBox(
          width: width,
          height: compact
              ? 1000
              : 1080,
          child: Container(
            padding:
                EdgeInsets.fromLTRB(
              compact ? 24 : 50,
              compact ? 28 : 42,
              compact ? 24 : 50,
              compact ? 22 : 28,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: _paperBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(
                    alpha: .08,
                  ),
                  blurRadius: 22,
                  offset:
                      const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                _PaperHeader(
                  reportTitle:
                      reportTitle,
                  location: location,
                  period: period,
                ),
                SizedBox(
                  height:
                      compact ? 22 : 30,
                ),

                // Bounded page => Expanded is safe here.
                Expanded(
                  child: SingleChildScrollView(
                    physics:
                        const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .stretch,
                      children: children,
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                _PaperFooter(
                  location: location,
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

class _PaperHeader
    extends StatelessWidget {
  const _PaperHeader({
    required this.reportTitle,
    required this.location,
    required this.period,
  });

  final String reportTitle;
  final String location;
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
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color:
                    ProvincialAdminColors
                        .blue
                        .withValues(
                  alpha: .08,
                ),
                borderRadius:
                    BorderRadius.circular(
                  8,
                ),
                border: Border.all(
                  color:
                      ProvincialAdminColors
                          .blue
                          .withValues(
                    alpha: .18,
                  ),
                ),
              ),
              child: const Icon(
                Icons.travel_explore_rounded,
                color:
                    ProvincialAdminColors
                        .blue,
                size: 23,
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
                      fontWeight:
                          FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Bulacan Provincial Tourism Office',
                    style: TextStyle(
                      color: _paperMuted,
                      fontSize: 10,
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
                  'OFFICIAL PROVINCIAL REPORT',
                  style: TextStyle(
                    color:
                        ProvincialAdminColors
                            .blue,
                    fontSize: 8.5,
                    fontWeight:
                        FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Generated ${DateFormat.yMMMd().format(DateTime.now())}',
                  style:
                      const TextStyle(
                    color: _paperMuted,
                    fontSize: 8.5,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 17),
        const Divider(
          height: 1,
          color: _paperBorder,
        ),
        const SizedBox(height: 24),
        Text(
          reportTitle.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _paperText,
            fontSize: 17,
            fontWeight:
                FontWeight.w900,
            letterSpacing: .25,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          location,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _paperText,
            fontSize: 11.5,
            fontWeight:
                FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Reporting Period: $period',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _paperMuted,
            fontSize: 9.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Footer
// ─────────────────────────────────────────────────────────────────────────────

class _PaperFooter
    extends StatelessWidget {
  const _PaperFooter({
    required this.location,
  });

  final String location;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        Container(
          height: 1,
          color: _paperBorder,
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: Text(
                'TourisTrike • $location',
                style:
                    const TextStyle(
                  color: _paperMuted,
                  fontSize: 8,
                ),
              ),
            ),
            const Text(
              'Bulacan Provincial Tourism Report',
              style: TextStyle(
                color: _paperMuted,
                fontSize: 8,
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

class _PaperSectionTitle
    extends StatelessWidget {
  const _PaperSectionTitle({
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 11,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _paperText,
              fontSize: 13,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style:
                  const TextStyle(
                color: _paperMuted,
                fontSize: 9.2,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metrics
// ─────────────────────────────────────────────────────────────────────────────

class _MetricGrid
    extends StatelessWidget {
  const _MetricGrid({
    required this.metrics,
  });

  final List<_PaperMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final columns =
            constraints.maxWidth >=
                    620
                ? 3
                : 2;

        const gap = 8.0;

        final width =
            (constraints.maxWidth -
                    gap *
                        (columns - 1)) /
                columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: Container(
                    padding:
                        const EdgeInsets
                            .all(11),
                    decoration:
                        BoxDecoration(
                      color: _paperSoft,
                      borderRadius:
                          BorderRadius
                              .circular(5),
                      border:
                          Border.all(
                        color:
                            _paperBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          metric.label,
                          style:
                              const TextStyle(
                            color:
                                _paperMuted,
                            fontSize: 8.7,
                            fontWeight:
                                FontWeight
                                    .w600,
                          ),
                        ),
                        const SizedBox(
                          height: 4,
                        ),
                        Text(
                          metric.value,
                          maxLines: 1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              const TextStyle(
                            color:
                                _paperText,
                            fontSize: 15,
                            fontWeight:
                                FontWeight
                                    .w800,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          metric.helper,
                          maxLines: 1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              const TextStyle(
                            color:
                                _paperMuted,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-width paper table
// ─────────────────────────────────────────────────────────────────────────────

class _PaperTable
    extends StatelessWidget {
  const _PaperTable({
    required this.columns,
    required this.rows,
    this.columnFlex,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final List<int>? columnFlex;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _PaperEmptyState(
        message:
            'No matching records were found for this report.',
      );
    }

    final flex =
        columnFlex != null &&
                columnFlex!.length ==
                    columns.length
            ? columnFlex!
            : List<int>.filled(
                columns.length,
                1,
              );

    final widths =
        <int, TableColumnWidth>{};

    for (var index = 0;
        index < columns.length;
        index++) {
      widths[index] =
          FlexColumnWidth(
        flex[index].toDouble(),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(
          color: _paperBorder,
        ),
        borderRadius:
            BorderRadius.circular(5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: widths,
        defaultVerticalAlignment:
            TableCellVerticalAlignment
                .middle,
        border: const TableBorder(
          horizontalInside:
              BorderSide(
            color: _paperBorder,
            width: .8,
          ),
          verticalInside:
              BorderSide(
            color: Color(
              0xFFEEF2F6,
            ),
            width: .6,
          ),
        ),
        children: [
          TableRow(
            decoration:
                const BoxDecoration(
              color: _paperSoft,
            ),
            children: columns
                .map(
                  (column) =>
                      _PaperTableCell(
                    text: column,
                    header: true,
                  ),
                )
                .toList(),
          ),
          for (var rowIndex = 0;
              rowIndex < rows.length;
              rowIndex++)
            TableRow(
              decoration:
                  BoxDecoration(
                color:
                    rowIndex.isEven
                        ? Colors.white
                        : const Color(
                            0xFFFCFDFE,
                          ),
              ),
              children:
                  rows[rowIndex]
                      .map(
                        (cell) =>
                            _PaperTableCell(
                          text: cell,
                        ),
                      )
                      .toList(),
            ),
        ],
      ),
    );
  }
}

class _PaperTableCell
    extends StatelessWidget {
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
        minHeight:
            header ? 38 : 40,
      ),
      alignment:
          Alignment.centerLeft,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 9,
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow:
            TextOverflow.ellipsis,
        style: TextStyle(
          color: header
              ? _paperText
              : const Color(
                  0xFF475467,
                ),
          fontSize:
              header ? 8.8 : 8.7,
          fontWeight: header
              ? FontWeight.w700
              : FontWeight.w500,
          height: 1.3,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notes
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewNotes
    extends StatelessWidget {
  const _OverviewNotes({
    required this.snapshot,
  });

  final _ProvinceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final completion =
        snapshot.totalBookings == 0
            ? 0.0
            : snapshot
                    .completedBookings /
                snapshot.totalBookings;

    final notes = <String>[
      if (snapshot.totalBookings == 0)
        'No tourism bookings were recorded during this reporting period.'
      else
        '${snapshot.completedBookings} of ${snapshot.totalBookings} bookings were completed (${_percentDouble(completion)}).',
      '${snapshot.totalPackages} tourism packages and ${snapshot.totalSpots} tourist spots are included in the selected coverage.',
      '${snapshot.totalDrivers} registered driver-tour guides are represented in the report.',
      if (snapshot.totalFeedback == 0)
        'No visitor feedback was submitted during this reporting period.'
      else
        '${snapshot.totalFeedback} feedback entries produced an average rating of ${snapshot.averageRating.toStringAsFixed(1)} out of 5.',
    ];

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const _PaperSectionTitle(
          title: 'Report Notes',
          subtitle:
              'Automatically summarized from available provincial records.',
        ),
        Container(
          padding:
              const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _paperSoft,
            borderRadius:
                BorderRadius.circular(5),
            border: Border.all(
              color: _paperBorder,
            ),
          ),
          child: Column(
            children: notes
                .map(
                  (note) => Padding(
                    padding:
                        const EdgeInsets
                            .only(
                      bottom: 7,
                    ),
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          margin:
                              const EdgeInsets
                                  .only(
                            top: 5,
                          ),
                          decoration:
                              const BoxDecoration(
                            color:
                                ProvincialAdminColors
                                    .blue,
                            shape:
                                BoxShape.circle,
                          ),
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child: Text(
                            note,
                            style:
                                const TextStyle(
                              color:
                                  _paperMuted,
                              fontSize:
                                  9.2,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / additional rows
// ─────────────────────────────────────────────────────────────────────────────

class _PaperEmptyState
    extends StatelessWidget {
  const _PaperEmptyState({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _paperSoft,
        borderRadius:
            BorderRadius.circular(5),
        border: Border.all(
          color: _paperBorder,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.description_outlined,
            color: _paperMuted,
            size: 17,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style:
                  const TextStyle(
                color: _paperMuted,
                fontSize: 9.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreRowsNote
    extends StatelessWidget {
  const _MoreRowsNote({
    required this.remaining,
  });

  final int remaining;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(
        top: 8,
      ),
      child: Text(
        '+ $remaining additional record(s) are included in the downloadable PDF.',
        style: const TextStyle(
          color: _paperMuted,
          fontSize: 8.5,
          fontStyle:
              FontStyle.italic,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _MutableStats {
  int count = 0;
  double amount = 0;
}

Map<String, _MutableStats>
    _packageStats(
  List<ProvinceBooking> bookings,
) {
  final stats =
      <String, _MutableStats>{};

  for (final booking in bookings) {
    final key = _packageKey(
      booking.packageId,
      booking.packageTitle,
    );

    final item = stats.putIfAbsent(
      key,
      () => _MutableStats(),
    );

    item.count++;

    if (booking.status.toLowerCase() ==
        'completed') {
      item.amount +=
          booking.totalAmount;
    }
  }

  return stats;
}

String _packageKey(
  dynamic id,
  String title,
) {
  final value =
      adminId(id).trim();

  if (value.isNotEmpty) {
    return value;
  }

  return 'title:${_normalize(title)}';
}

String _locationLabel(
  _ProvinceSnapshot snapshot,
) {
  if (snapshot.cityFilter ==
      _allCities) {
    return 'Province of Bulacan';
  }

  return '${snapshot.cityFilter}, Bulacan';
}

String _money(num value) {
  return NumberFormat.currency(
    symbol: '₱',
    decimalDigits: 0,
  ).format(value);
}

String _date(DateTime? value) {
  if (value == null) {
    return 'N/A';
  }

  return DateFormat(
    'MMM d, yyyy',
  ).format(value);
}

String _percentageFromCount(
  int value,
  int total,
) {
  if (total <= 0) {
    return '0%';
  }

  return '${((value / total) * 100).round()}%';
}

String _percentDouble(
  double value,
) {
  return '${(value * 100).round()}%';
}

String _normalize(String value) {
  return value
      .trim()
      .toLowerCase();
}

bool _sameCity(
  String left,
  String right,
) {
  return _normalize(left) ==
      _normalize(right);
}

String _shortText(
  String value,
  int maxLength,
) {
  final clean = value
      .trim()
      .replaceAll(
        RegExp(r'\s+'),
        ' ',
      );

  if (clean.isEmpty) {
    return 'N/A';
  }

  if (clean.length <= maxLength) {
    return clean;
  }

  return '${clean.substring(0, maxLength - 1)}…';
}

String _slug(String value) {
  final result = value
      .toLowerCase()
      .replaceAll(
        RegExp(r'[^a-z0-9]+'),
        '-',
      )
      .replaceAll(
        RegExp(r'^-+|-+$'),
        '',
      );

  return result;
}