import 'package:flutter/material.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class ProvinceReportsScreen extends StatefulWidget {
  const ProvinceReportsScreen({super.key});

  @override
  State<ProvinceReportsScreen> createState() => _ProvinceReportsScreenState();
}

class _ProvinceReportsScreenState extends State<ProvinceReportsScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();
  late Future<AdminReportData> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchReports();
  }

  void _reload() {
    setState(() => _future = _service.fetchReports());
  }

  @override
  Widget build(BuildContext context) {
    return ProvincialAdminShell(
      current: ProvincialAdminDestination.reports,
      title: 'Reports',
      subtitle: 'Overall province-wide tourism reporting dashboard.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => showAdminSnack(
            context,
            'Export report is a placeholder for CSV/PDF generation.',
            error: false,
          ),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Export Report'),
        ),
      ],
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
          final totalBookings = data.bookings.length;
          final completed = data.completedTours;
          final cancelled = data.cancelledBookings;

          final activeCities = data.tenants.where((tenant) {
            final status = tenant.status.toLowerCase();
            return status == 'active' ||
                status == 'approved' ||
                status == 'verified';
          }).length;

          final bookingsByCity = _countBookingsByCity(data.bookings);
          final packagesByCity = _countPackagesByCity(data.packages);
          final spotsByCity = _countSpotsByCity(data.spots);
          final driversByCity = _countDriversByCity(data.tenants);

          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1150;

              if (!wide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                  child: _MobileReportsLayout(
                    data: data,
                    activeCities: activeCities,
                    totalBookings: totalBookings,
                    completed: completed,
                    cancelled: cancelled,
                    bookingsByCity: bookingsByCity,
                    packagesByCity: packagesByCity,
                    spotsByCity: spotsByCity,
                    driversByCity: driversByCity,
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
                child: _DesktopReportsLayout(
                  height: constraints.maxHeight - 28,
                  data: data,
                  activeCities: activeCities,
                  totalBookings: totalBookings,
                  completed: completed,
                  cancelled: cancelled,
                  bookingsByCity: bookingsByCity,
                  packagesByCity: packagesByCity,
                  spotsByCity: spotsByCity,
                  driversByCity: driversByCity,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Map<String, int> _countBookingsByCity(List<ProvinceBooking> rows) {
    final counts = <String, int>{};

    for (final item in rows) {
      final city = item.city.trim().isEmpty ? 'Unassigned' : item.city;
      counts.update(city, (value) => value + 1, ifAbsent: () => 1);
    }

    return _sortedMap(counts);
  }

  Map<String, int> _countPackagesByCity(List<ProvincePackage> rows) {
    final counts = <String, int>{};

    for (final item in rows) {
      final city = item.city.trim().isEmpty ? 'Unassigned' : item.city;
      counts.update(city, (value) => value + 1, ifAbsent: () => 1);
    }

    return _sortedMap(counts);
  }

  Map<String, int> _countSpotsByCity(List<ProvinceSpot> rows) {
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
      if (item.city.trim().isEmpty) continue;
      counts[item.city] = item.driversCount;
    }

    return _sortedMap(counts);
  }

  Map<String, int> _sortedMap(Map<String, int> source) {
    final entries = source.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {for (final entry in entries) entry.key: entry.value};
  }
}

class _DesktopReportsLayout extends StatelessWidget {
  const _DesktopReportsLayout({
    required this.height,
    required this.data,
    required this.activeCities,
    required this.totalBookings,
    required this.completed,
    required this.cancelled,
    required this.bookingsByCity,
    required this.packagesByCity,
    required this.spotsByCity,
    required this.driversByCity,
  });

  final double height;
  final AdminReportData data;
  final int activeCities;
  final int totalBookings;
  final int completed;
  final int cancelled;
  final Map<String, int> bookingsByCity;
  final Map<String, int> packagesByCity;
  final Map<String, int> spotsByCity;
  final Map<String, int> driversByCity;

  @override
  Widget build(BuildContext context) {
    const gap = 14.0;
    const heroHeight = 106.0;
    const metricHeight = 100.0;

    final bodyHeight = height - heroHeight - metricHeight - gap * 3;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          SizedBox(
            height: heroHeight,
            child: _ReportsHero(
              activeCities: activeCities,
              totalCities: data.tenants.length,
              totalBookings: totalBookings,
              completed: completed,
              cancelled: cancelled,
            ),
          ),
          const SizedBox(height: gap),
          SizedBox(
            height: metricHeight,
            child: _MetricRow(
              totalBookings: totalBookings,
              cities: data.tenants.length,
              packages: data.packages.length,
              completed: completed,
              cancelled: cancelled,
            ),
          ),
          const SizedBox(height: gap),
          SizedBox(
            height: bodyHeight,
            child: Row(
              children: [
                Expanded(
                  flex: 7,
                  child: _ReportPanel(
                    title: 'Bookings by City',
                    subtitle: 'Package bookings grouped by LGU.',
                    icon: Icons.receipt_long_rounded,
                    color: ProvincialAdminColors.blue,
                    child: _RankedRows(
                      rows: bookingsByCity,
                      emptyTitle: 'No booking data yet.',
                    ),
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  flex: 7,
                  child: Column(
                    children: [
                      Expanded(
                        child: _ReportPanel(
                          title: 'Tourist Spots per City',
                          subtitle: 'Tourism records submitted by LGUs.',
                          icon: Icons.place_rounded,
                          color: ProvincialAdminColors.cyan,
                          child: _RankedRows(
                            rows: spotsByCity,
                            emptyTitle: 'No tourist spot data yet.',
                          ),
                        ),
                      ),
                      const SizedBox(height: gap),
                      Expanded(
                        child: _ReportPanel(
                          title: 'Packages per City',
                          subtitle: 'Tour packages created by each city.',
                          icon: Icons.inventory_2_rounded,
                          color: ProvincialAdminColors.green,
                          child: _RankedRows(
                            rows: packagesByCity,
                            emptyTitle: 'No package data yet.',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 205,
                        child: _OutcomePanel(
                          total: totalBookings,
                          completed: completed,
                          cancelled: cancelled,
                        ),
                      ),
                      const SizedBox(height: gap),
                      Expanded(
                        child: _InsightsPanel(
                          activeCities: activeCities,
                          totalCities: data.tenants.length,
                          packages: data.packages.length,
                          spots: data.spots.length,
                          bookings: totalBookings,
                          driversByCity: driversByCity,
                        ),
                      ),
                    ],
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

class _MobileReportsLayout extends StatelessWidget {
  const _MobileReportsLayout({
    required this.data,
    required this.activeCities,
    required this.totalBookings,
    required this.completed,
    required this.cancelled,
    required this.bookingsByCity,
    required this.packagesByCity,
    required this.spotsByCity,
    required this.driversByCity,
  });

  final AdminReportData data;
  final int activeCities;
  final int totalBookings;
  final int completed;
  final int cancelled;
  final Map<String, int> bookingsByCity;
  final Map<String, int> packagesByCity;
  final Map<String, int> spotsByCity;
  final Map<String, int> driversByCity;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 140,
          child: _ReportsHero(
            activeCities: activeCities,
            totalCities: data.tenants.length,
            totalBookings: totalBookings,
            completed: completed,
            cancelled: cancelled,
          ),
        ),
        const SizedBox(height: 14),
        _MetricGrid(
          totalBookings: totalBookings,
          cities: data.tenants.length,
          packages: data.packages.length,
          completed: completed,
          cancelled: cancelled,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 280,
          child: _ReportPanel(
            title: 'Bookings by City',
            subtitle: 'Package bookings grouped by LGU.',
            icon: Icons.receipt_long_rounded,
            color: ProvincialAdminColors.blue,
            child: _RankedRows(
              rows: bookingsByCity,
              emptyTitle: 'No booking data yet.',
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 280,
          child: _ReportPanel(
            title: 'Tourist Spots per City',
            subtitle: 'Tourism records submitted by LGUs.',
            icon: Icons.place_rounded,
            color: ProvincialAdminColors.cyan,
            child: _RankedRows(
              rows: spotsByCity,
              emptyTitle: 'No tourist spot data yet.',
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 280,
          child: _ReportPanel(
            title: 'Packages per City',
            subtitle: 'Tour packages created by each city.',
            icon: Icons.inventory_2_rounded,
            color: ProvincialAdminColors.green,
            child: _RankedRows(
              rows: packagesByCity,
              emptyTitle: 'No package data yet.',
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 205,
          child: _OutcomePanel(
            total: totalBookings,
            completed: completed,
            cancelled: cancelled,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 300,
          child: _InsightsPanel(
            activeCities: activeCities,
            totalCities: data.tenants.length,
            packages: data.packages.length,
            spots: data.spots.length,
            bookings: totalBookings,
            driversByCity: driversByCity,
          ),
        ),
      ],
    );
  }
}

class _ReportsHero extends StatelessWidget {
  const _ReportsHero({
    required this.activeCities,
    required this.totalCities,
    required this.totalBookings,
    required this.completed,
    required this.cancelled,
  });

  final int activeCities;
  final int totalCities;
  final int totalBookings;
  final int completed;
  final int cancelled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4AA3FF), Color(0xFF1D63E9)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: .22)),
            ),
            child: const Icon(
              Icons.analytics_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PROVINCE ANALYTICS',
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
                const Text(
                  'Bulacan Tourism Reports',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Compare city activity, package availability, driver coverage, and booking outcomes.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .92),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          _HeroValueChip(
            label: 'Cities',
            value: '$activeCities/$totalCities',
            icon: Icons.location_city_rounded,
          ),
          const SizedBox(width: 10),
          _HeroValueChip(
            label: 'Bookings',
            value: '$totalBookings',
            icon: Icons.receipt_long_rounded,
          ),
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
      width: 148,
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
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .86),
                      fontSize: 11,
                      height: 1.8,
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
    required this.totalBookings,
    required this.cities,
    required this.packages,
    required this.completed,
    required this.cancelled,
  });

  final int totalBookings;
  final int cities;
  final int packages;
  final int completed;
  final int cancelled;

  @override
  Widget build(BuildContext context) {
    final items = _metricItems(
      totalBookings: totalBookings,
      cities: cities,
      packages: packages,
      completed: completed,
      cancelled: cancelled,
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
    required this.totalBookings,
    required this.cities,
    required this.packages,
    required this.completed,
    required this.cancelled,
  });

  final int totalBookings;
  final int cities;
  final int packages;
  final int completed;
  final int cancelled;

  @override
  Widget build(BuildContext context) {
    final items = _metricItems(
      totalBookings: totalBookings,
      cities: cities,
      packages: packages,
      completed: completed,
      cancelled: cancelled,
    );

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.8,
      ),
      itemBuilder: (_, index) => _MetricCard(item: items[index]),
    );
  }
}

List<_MetricItem> _metricItems({
  required int totalBookings,
  required int cities,
  required int packages,
  required int completed,
  required int cancelled,
}) {
  return [
    _MetricItem(
      label: 'Bookings',
      value: '$totalBookings',
      subtitle: 'province-wide',
      icon: Icons.receipt_long_rounded,
      color: ProvincialAdminColors.blue,
    ),
    _MetricItem(
      label: 'Cities',
      value: '$cities',
      subtitle: 'tenant offices',
      icon: Icons.location_city_rounded,
      color: ProvincialAdminColors.cyan,
    ),
    _MetricItem(
      label: 'Packages',
      value: '$packages',
      subtitle: 'listed tours',
      icon: Icons.inventory_2_rounded,
      color: ProvincialAdminColors.green,
    ),
    _MetricItem(
      label: 'Completed',
      value: '$completed',
      subtitle: 'finished tours',
      icon: Icons.check_circle_rounded,
      color: ProvincialAdminColors.green,
    ),
    _MetricItem(
      label: 'Cancelled',
      value: '$cancelled',
      subtitle: 'cancelled requests',
      icon: Icons.cancel_rounded,
      color: ProvincialAdminColors.red,
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: item.color, size: 21),
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
                      fontSize: 24,
                      height: 1.3,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: '${item.label}\n',
                    style: const TextStyle(
                      color: ProvincialAdminColors.text,
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: item.subtitle,
                    style: const TextStyle(
                      color: ProvincialAdminColors.muted,
                      fontSize: 11.5,
                      height: 1.5,
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

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({
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
                          height: 1.3,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text: subtitle,
                        style: const TextStyle(
                          color: ProvincialAdminColors.muted,
                          fontSize: 12,
                          height: 1.5,
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
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _RankedRows extends StatelessWidget {
  const _RankedRows({
    required this.rows,
    required this.emptyTitle,
  });

  final Map<String, int> rows;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return _PanelEmpty(title: emptyTitle);
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
                  color: index == 0 ? Colors.white : ProvincialAdminColors.muted,
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
                      const SizedBox(width: 8),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(
                          color: ProvincialAdminColors.amber,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(factor * 100).round()}%',
                        style: const TextStyle(
                          color: ProvincialAdminColors.lightMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
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

class _OutcomePanel extends StatelessWidget {
  const _OutcomePanel({
    required this.total,
    required this.completed,
    required this.cancelled,
  });

  final int total;
  final int completed;
  final int cancelled;

  @override
  Widget build(BuildContext context) {
    final other = (total - completed - cancelled).clamp(0, total);

    return _ReportPanel(
      title: 'Booking Outcome',
      subtitle: 'Completed, cancelled, and pending tours.',
      icon: Icons.pie_chart_rounded,
      color: ProvincialAdminColors.purple,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _OutcomeRow(
            label: 'Completed',
            value: completed,
            total: total,
            color: ProvincialAdminColors.green,
          ),
          const SizedBox(height: 10),
          _OutcomeRow(
            label: 'Cancelled',
            value: cancelled,
            total: total,
            color: ProvincialAdminColors.red,
          ),
          const SizedBox(height: 10),
          _OutcomeRow(
            label: 'Other / Pending',
            value: other,
            total: total,
            color: ProvincialAdminColors.amber,
          ),
        ],
      ),
    );
  }
}

class _OutcomeRow extends StatelessWidget {
  const _OutcomeRow({
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
              '$value • ${(percent * 100).round()}%',
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: percent.clamp(.04, 1),
            color: color,
            backgroundColor: const Color(0xFFEAF2FF),
          ),
        ),
      ],
    );
  }
}

class _InsightsPanel extends StatelessWidget {
  const _InsightsPanel({
    required this.activeCities,
    required this.totalCities,
    required this.packages,
    required this.spots,
    required this.bookings,
    required this.driversByCity,
  });

  final int activeCities;
  final int totalCities;
  final int packages;
  final int spots;
  final int bookings;
  final Map<String, int> driversByCity;

  @override
  Widget build(BuildContext context) {
    final totalDrivers = driversByCity.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );

    final items = [
      _InsightItem(
        icon: Icons.location_city_rounded,
        label: 'Active tenant coverage',
        value: '$activeCities of $totalCities cities',
      ),
      _InsightItem(
        icon: Icons.inventory_2_rounded,
        label: 'Package availability',
        value: '$packages listed packages',
      ),
      _InsightItem(
        icon: Icons.place_rounded,
        label: 'Tourist spot inventory',
        value: '$spots submitted spots',
      ),
      _InsightItem(
        icon: Icons.directions_bike_rounded,
        label: 'Driver coverage',
        value: '$totalDrivers registered drivers',
      ),
      _InsightItem(
        icon: Icons.receipt_long_rounded,
        label: 'Booking activity',
        value: '$bookings total bookings',
      ),
    ];

    return _ReportPanel(
      title: 'Quick Insights',
      subtitle: 'Province-level operating snapshot.',
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
                            height: 1.9,
                          ),
                        ),
                        TextSpan(
                          text: item.value,
                          style: const TextStyle(
                            color: ProvincialAdminColors.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            height: 1.9,
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
  const _PanelEmpty({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
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
              Icons.bar_chart_rounded,
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
      ),
    );
  }
}