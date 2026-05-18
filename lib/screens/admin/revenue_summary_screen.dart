import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class RevenueSummaryScreen extends StatefulWidget {
  const RevenueSummaryScreen({super.key});

  @override
  State<RevenueSummaryScreen> createState() => _RevenueSummaryScreenState();
}

class _RevenueSummaryScreenState extends State<RevenueSummaryScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();
  late Future<RevenueSummaryData> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchRevenueSummary();
  }

  void _reload() {
    setState(() => _future = _service.fetchRevenueSummary());
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);

    return ProvincialAdminShell(
      current: ProvincialAdminDestination.revenue,
      title: 'Revenue',
      subtitle: 'Monitor province-wide booking value and top earning cities.',
      child: FutureBuilder<RevenueSummaryData>(
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
          final cityRows = _revenueByCity(data.bookings);
          final packageRows = _revenueByPackage(data.packages);

          final totalBookings = data.bookings.length;
          final completedCount = data.bookings
              .where((item) => item.status.toLowerCase() == 'completed')
              .length;
          final pendingCount = data.bookings
              .where((item) => item.status.toLowerCase() == 'pending')
              .length;

          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1150;

              if (!wide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                  child: _MobileRevenueLayout(
                    money: money,
                    data: data,
                    cityRows: cityRows,
                    packageRows: packageRows,
                    totalBookings: totalBookings,
                    completedCount: completedCount,
                    pendingCount: pendingCount,
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
                child: _DesktopRevenueLayout(
                  height: constraints.maxHeight - 28,
                  money: money,
                  data: data,
                  cityRows: cityRows,
                  packageRows: packageRows,
                  totalBookings: totalBookings,
                  completedCount: completedCount,
                  pendingCount: pendingCount,
                ),
              );
            },
          );
        },
      ),
    );
  }

  List<_RevenueRow> _revenueByCity(List<ProvinceBooking> bookings) {
    final map = <String, _MutableRevenue>{};

    for (final booking in bookings) {
      if (booking.status.toLowerCase() != 'completed') continue;

      final city = booking.city.trim().isEmpty ? 'Unassigned' : booking.city;
      map.putIfAbsent(city, () => _MutableRevenue());
      map[city]!.amount += booking.totalAmount;
      map[city]!.count++;
    }

    final rows = map.entries
        .map(
          (entry) => _RevenueRow(
            label: entry.key,
            amount: entry.value.amount,
            count: entry.value.count,
          ),
        )
        .toList();

    rows.sort((a, b) => b.amount.compareTo(a.amount));
    return rows;
  }

  List<_RevenueRow> _revenueByPackage(List<ProvincePackage> packages) {
    final rows = packages
        .where((item) => item.revenue > 0)
        .map(
          (item) => _RevenueRow(
            label: item.title,
            amount: item.revenue,
            count: item.bookingsCount,
          ),
        )
        .toList();

    rows.sort((a, b) => b.amount.compareTo(a.amount));
    return rows;
  }
}

class _DesktopRevenueLayout extends StatelessWidget {
  const _DesktopRevenueLayout({
    required this.height,
    required this.money,
    required this.data,
    required this.cityRows,
    required this.packageRows,
    required this.totalBookings,
    required this.completedCount,
    required this.pendingCount,
  });

  final double height;
  final NumberFormat money;
  final RevenueSummaryData data;
  final List<_RevenueRow> cityRows;
  final List<_RevenueRow> packageRows;
  final int totalBookings;
  final int completedCount;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    const gap = 14.0;

    // Taller blue banner.
    const heroHeight = 106.0;

    // Four blocks in one row below the banner.
    const metricHeight = 100.0;

    final bodyHeight = height - heroHeight - metricHeight - gap * 3;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          SizedBox(
            height: heroHeight,
            child: _RevenueHero(
              completedRevenue: data.completedRevenue,
              pendingValue: data.pendingValue,
              money: money,
            ),
          ),
          const SizedBox(height: gap),
          SizedBox(
            height: metricHeight,
            child: _MetricRow(
              money: money,
              completedRevenue: data.completedRevenue,
              pendingValue: data.pendingValue,
              bookings: totalBookings,
              packages: data.packages.length,
            ),
          ),
          const SizedBox(height: gap),
          SizedBox(
            height: bodyHeight,
            child: Row(
              children: [
                Expanded(
                  flex: 7,
                  child: _RevenuePanel(
                    title: 'Revenue by City',
                    subtitle: 'Completed booking value grouped by LGU.',
                    icon: Icons.location_city_rounded,
                    color: ProvincialAdminColors.green,
                    child: _RevenueRows(
                      rows: cityRows,
                      empty: 'No completed booking revenue yet.',
                    ),
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  flex: 7,
                  child: _RevenuePanel(
                    title: 'Revenue by Package',
                    subtitle: 'Top earning tour packages.',
                    icon: Icons.inventory_2_rounded,
                    color: ProvincialAdminColors.blue,
                    child: _RevenueRows(
                      rows: packageRows,
                      empty: 'No package revenue yet.',
                    ),
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 205,
                        child: _RevenueStatusPanel(
                          completedCount: completedCount,
                          pendingCount: pendingCount,
                          totalBookings: totalBookings,
                        ),
                      ),
                      const SizedBox(height: gap),
                      Expanded(
                        child: _RevenueInsightsPanel(
                          completedRevenue: data.completedRevenue,
                          pendingValue: data.pendingValue,
                          packages: data.packages.length,
                          bookings: totalBookings,
                          money: money,
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

class _MobileRevenueLayout extends StatelessWidget {
  const _MobileRevenueLayout({
    required this.money,
    required this.data,
    required this.cityRows,
    required this.packageRows,
    required this.totalBookings,
    required this.completedCount,
    required this.pendingCount,
  });

  final NumberFormat money;
  final RevenueSummaryData data;
  final List<_RevenueRow> cityRows;
  final List<_RevenueRow> packageRows;
  final int totalBookings;
  final int completedCount;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 140,
          child: _RevenueHero(
            completedRevenue: data.completedRevenue,
            pendingValue: data.pendingValue,
            money: money,
          ),
        ),
        const SizedBox(height: 14),
        _MetricGrid(
          money: money,
          completedRevenue: data.completedRevenue,
          pendingValue: data.pendingValue,
          bookings: totalBookings,
          packages: data.packages.length,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 280,
          child: _RevenuePanel(
            title: 'Revenue by City',
            subtitle: 'Completed booking value grouped by LGU.',
            icon: Icons.location_city_rounded,
            color: ProvincialAdminColors.green,
            child: _RevenueRows(
              rows: cityRows,
              empty: 'No completed booking revenue yet.',
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 280,
          child: _RevenuePanel(
            title: 'Revenue by Package',
            subtitle: 'Top earning tour packages.',
            icon: Icons.inventory_2_rounded,
            color: ProvincialAdminColors.blue,
            child: _RevenueRows(
              rows: packageRows,
              empty: 'No package revenue yet.',
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 205,
          child: _RevenueStatusPanel(
            completedCount: completedCount,
            pendingCount: pendingCount,
            totalBookings: totalBookings,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 300,
          child: _RevenueInsightsPanel(
            completedRevenue: data.completedRevenue,
            pendingValue: data.pendingValue,
            packages: data.packages.length,
            bookings: totalBookings,
            money: money,
          ),
        ),
      ],
    );
  }
}

class _RevenueHero extends StatelessWidget {
  const _RevenueHero({
    required this.completedRevenue,
    required this.pendingValue,
    required this.money,
  });

  final double completedRevenue;
  final double pendingValue;
  final NumberFormat money;

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
              Icons.payments_rounded,
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
                  'REVENUE SUMMARY',
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
                  'Bulacan Tourism Booking Value',
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
                  'Track completed revenue, pending value, and package booking performance.',
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
            label: 'Completed',
            value: money.format(completedRevenue),
            icon: Icons.check_circle_rounded,
          ),
          const SizedBox(width: 10),
          _HeroValueChip(
            label: 'Pending',
            value: money.format(pendingValue),
            icon: Icons.pending_actions_rounded,
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
    required this.money,
    required this.completedRevenue,
    required this.pendingValue,
    required this.bookings,
    required this.packages,
  });

  final NumberFormat money;
  final double completedRevenue;
  final double pendingValue;
  final int bookings;
  final int packages;

  @override
  Widget build(BuildContext context) {
    final items = _metricItems(
      money: money,
      completedRevenue: completedRevenue,
      pendingValue: pendingValue,
      bookings: bookings,
      packages: packages,
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
    required this.money,
    required this.completedRevenue,
    required this.pendingValue,
    required this.bookings,
    required this.packages,
  });

  final NumberFormat money;
  final double completedRevenue;
  final double pendingValue;
  final int bookings;
  final int packages;

  @override
  Widget build(BuildContext context) {
    final items = _metricItems(
      money: money,
      completedRevenue: completedRevenue,
      pendingValue: pendingValue,
      bookings: bookings,
      packages: packages,
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
  required NumberFormat money,
  required double completedRevenue,
  required double pendingValue,
  required int bookings,
  required int packages,
}) {
  return [
    _MetricItem(
      label: 'Completed Revenue',
      value: money.format(completedRevenue),
      subtitle: 'paid completed tours',
      icon: Icons.payments_rounded,
      color: ProvincialAdminColors.green,
    ),
    _MetricItem(
      label: 'Pending Value',
      value: money.format(pendingValue),
      subtitle: 'awaiting completion',
      icon: Icons.pending_actions_rounded,
      color: ProvincialAdminColors.amber,
    ),
    _MetricItem(
      label: 'Total Bookings',
      value: '$bookings',
      subtitle: 'all booking requests',
      icon: Icons.receipt_long_rounded,
      color: ProvincialAdminColors.purple,
    ),
    _MetricItem(
      label: 'Packages',
      value: '$packages',
      subtitle: 'listed tour packages',
      icon: Icons.inventory_2_rounded,
      color: ProvincialAdminColors.blue,
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

class _RevenuePanel extends StatelessWidget {
  const _RevenuePanel({
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

class _RevenueRows extends StatelessWidget {
  const _RevenueRows({
    required this.rows,
    required this.empty,
  });

  final List<_RevenueRow> rows;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);

    if (rows.isEmpty) {
      return _PanelEmpty(title: empty);
    }

    final max = rows.first.amount == 0 ? 1.0 : rows.first.amount;

    return ListView.separated(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length > 6 ? 6 : rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = rows[index];
        final factor = row.amount / max;

        return Row(
          children: [
            Container(
              width: 29,
              height: 29,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: index == 0
                    ? ProvincialAdminColors.green
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
                          row.label,
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
                        money.format(row.amount),
                        style: const TextStyle(
                          color: ProvincialAdminColors.green,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 8,
                            value: factor.clamp(.05, 1),
                            color: ProvincialAdminColors.green,
                            backgroundColor: const Color(0xFFEAF2FF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${row.count} bookings',
                        style: const TextStyle(
                          color: ProvincialAdminColors.lightMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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

class _RevenueStatusPanel extends StatelessWidget {
  const _RevenueStatusPanel({
    required this.completedCount,
    required this.pendingCount,
    required this.totalBookings,
  });

  final int completedCount;
  final int pendingCount;
  final int totalBookings;

  @override
  Widget build(BuildContext context) {
    final other = (totalBookings - completedCount - pendingCount).clamp(
      0,
      totalBookings,
    );

    return _RevenuePanel(
      title: 'Booking Status',
      subtitle: 'Completed, pending, and other requests.',
      icon: Icons.pie_chart_rounded,
      color: ProvincialAdminColors.purple,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _OutcomeRow(
            label: 'Completed',
            value: completedCount,
            total: totalBookings,
            color: ProvincialAdminColors.green,
          ),
          const SizedBox(height: 10),
          _OutcomeRow(
            label: 'Pending',
            value: pendingCount,
            total: totalBookings,
            color: ProvincialAdminColors.amber,
          ),
          const SizedBox(height: 10),
          _OutcomeRow(
            label: 'Other',
            value: other,
            total: totalBookings,
            color: ProvincialAdminColors.blue,
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

class _RevenueInsightsPanel extends StatelessWidget {
  const _RevenueInsightsPanel({
    required this.completedRevenue,
    required this.pendingValue,
    required this.packages,
    required this.bookings,
    required this.money,
  });

  final double completedRevenue;
  final double pendingValue;
  final int packages;
  final int bookings;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final items = [
      _InsightItem(
        icon: Icons.payments_rounded,
        label: 'Completed value',
        value: money.format(completedRevenue),
      ),
      _InsightItem(
        icon: Icons.pending_actions_rounded,
        label: 'Pending value',
        value: money.format(pendingValue),
      ),
      _InsightItem(
        icon: Icons.inventory_2_rounded,
        label: 'Package coverage',
        value: '$packages package records',
      ),
      _InsightItem(
        icon: Icons.receipt_long_rounded,
        label: 'Booking volume',
        value: '$bookings total requests',
      ),
    ];

    return _RevenuePanel(
      title: 'Quick Insights',
      subtitle: 'Province-level revenue snapshot.',
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
              Icons.payments_rounded,
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

class _RevenueRow {
  const _RevenueRow({
    required this.label,
    required this.amount,
    required this.count,
  });

  final String label;
  final double amount;
  final int count;
}

class _MutableRevenue {
  double amount = 0;
  int count = 0;
}