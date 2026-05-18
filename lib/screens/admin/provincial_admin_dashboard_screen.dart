import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/city_registrations_screen.dart';
import 'package:touristrike/screens/admin/city_tenants_screen.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/province_packages_screen.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/revenue_summary_screen.dart';
import 'package:touristrike/screens/admin/tourism_data_verification_screen.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/admin_status_pill.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class ProvincialAdminDashboardScreen extends StatefulWidget {
  const ProvincialAdminDashboardScreen({super.key});

  @override
  State<ProvincialAdminDashboardScreen> createState() =>
      _ProvincialAdminDashboardScreenState();
}

class _ProvincialAdminDashboardScreenState
    extends State<ProvincialAdminDashboardScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();
  late Future<AdminDashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.loadDashboard();
  }

  void _reload() {
    setState(() => _future = _service.loadDashboard());
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return ProvincialAdminShell(
      current: ProvincialAdminDestination.dashboard,
      title: 'Dashboard',
      subtitle: 'Province-wide tourism overview for Bulacan.',
      child: FutureBuilder<AdminDashboardData>(
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
          final money = NumberFormat.currency(
            symbol: 'PHP ',
            decimalDigits: 0,
          );

          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1180;

              if (!wide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                  child: _StackedDashboard(
                    data: data,
                    money: money,
                    openTenants: () => _open(const CityTenantsScreen()),
                    openRegistrations: () =>
                        _open(const CityRegistrationsScreen()),
                    openSpots: () =>
                        _open(const TourismDataVerificationScreen()),
                    openPackages: () => _open(const ProvincePackagesScreen()),
                    openRevenue: () => _open(const RevenueSummaryScreen()),
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
                child: _WideDashboard(
                  data: data,
                  money: money,
                  availableHeight: constraints.maxHeight - 28,
                  openTenants: () => _open(const CityTenantsScreen()),
                  openRegistrations: () =>
                      _open(const CityRegistrationsScreen()),
                  openSpots: () =>
                      _open(const TourismDataVerificationScreen()),
                  openPackages: () => _open(const ProvincePackagesScreen()),
                  openRevenue: () => _open(const RevenueSummaryScreen()),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _WideDashboard extends StatelessWidget {
  const _WideDashboard({
    required this.data,
    required this.money,
    required this.availableHeight,
    required this.openTenants,
    required this.openRegistrations,
    required this.openSpots,
    required this.openPackages,
    required this.openRevenue,
  });

  final AdminDashboardData data;
  final NumberFormat money;
  final double availableHeight;
  final VoidCallback openTenants;
  final VoidCallback openRegistrations;
  final VoidCallback openSpots;
  final VoidCallback openPackages;
  final VoidCallback openRevenue;

  @override
  Widget build(BuildContext context) {
    const gap = 16.0;
    const heroHeight = 118.0;
    const metricHeight = 96.0;

    final bodyHeight = availableHeight - heroHeight - metricHeight - gap * 3;
    final topHeight = bodyHeight * .54;
    final bottomHeight = bodyHeight * .46;

    return SizedBox(
      height: availableHeight,
      child: Column(
        children: [
          SizedBox(
            height: heroHeight,
            child: _HeroBanner(
              name: data.profile.displayName,
              activeCities: data.activeCities,
            ),
          ),
          const SizedBox(height: gap),
          SizedBox(
            height: metricHeight,
            child: _MetricsRow(
              money: money,
              data: data,
              onOpenTenants: openTenants,
              onOpenRegistrations: openRegistrations,
              onOpenSpots: openSpots,
              onOpenPackages: openPackages,
              onOpenRevenue: openRevenue,
            ),
          ),
          const SizedBox(height: gap),
          SizedBox(
            height: topHeight,
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: _TopCities(rows: data.bookingsByCity.take(6).toList()),
                ),
                const SizedBox(width: gap),
                Expanded(
                  flex: 6,
                  child: _RecentActivity(data: data),
                ),
                const SizedBox(width: gap),
                Expanded(
                  flex: 5,
                  child: _TopPackages(
                    packages: data.topPackages.take(4).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: gap),
          SizedBox(
            height: bottomHeight,
            child: Row(
              children: [
                Expanded(
                  flex: 12,
                  child: _BookingsOverview(data: data),
                ),
                const SizedBox(width: gap),
                Expanded(
                  flex: 5,
                  child: _Alerts(data: data),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StackedDashboard extends StatelessWidget {
  const _StackedDashboard({
    required this.data,
    required this.money,
    required this.openTenants,
    required this.openRegistrations,
    required this.openSpots,
    required this.openPackages,
    required this.openRevenue,
  });

  final AdminDashboardData data;
  final NumberFormat money;
  final VoidCallback openTenants;
  final VoidCallback openRegistrations;
  final VoidCallback openSpots;
  final VoidCallback openPackages;
  final VoidCallback openRevenue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 108,
          child: _HeroBanner(
            name: data.profile.displayName,
            activeCities: data.activeCities,
          ),
        ),
        const SizedBox(height: 14),
        _MetricsGrid(
          money: money,
          data: data,
          onOpenTenants: openTenants,
          onOpenRegistrations: openRegistrations,
          onOpenSpots: openSpots,
          onOpenPackages: openPackages,
          onOpenRevenue: openRevenue,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 280,
          child: _TopCities(rows: data.bookingsByCity.take(5).toList()),
        ),
        const SizedBox(height: 14),
        SizedBox(height: 280, child: _RecentActivity(data: data)),
        const SizedBox(height: 14),
        SizedBox(
          height: 260,
          child: _TopPackages(packages: data.topPackages.take(4).toList()),
        ),
        const SizedBox(height: 14),
        SizedBox(height: 300, child: _Alerts(data: data)),
        const SizedBox(height: 14),
        _BookingsOverview(data: data),
      ],
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.name,
    required this.activeCities,
  });

  final String name;
  final int activeCities;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4AA3FF), Color(0xFF1D63E9)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.account_balance_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bulacan Provincial Tourism Office',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .88),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Hello, $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Manage tenants, tourism data, packages, revenue, and reports across Bulacan.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .92),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$activeCities active cities',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({
    required this.money,
    required this.data,
    required this.onOpenTenants,
    required this.onOpenRegistrations,
    required this.onOpenSpots,
    required this.onOpenPackages,
    required this.onOpenRevenue,
  });

  final NumberFormat money;
  final AdminDashboardData data;
  final VoidCallback onOpenTenants;
  final VoidCallback onOpenRegistrations;
  final VoidCallback onOpenSpots;
  final VoidCallback onOpenPackages;
  final VoidCallback onOpenRevenue;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricCard(
        icon: Icons.location_city_rounded,
        label: 'City Tenants',
        value: '${data.tenants.length}',
        subtitle: '${data.activeCities} active',
        color: ProvincialAdminColors.blue,
        onTap: onOpenTenants,
      ),
      _MetricCard(
        icon: Icons.how_to_reg_rounded,
        label: 'Pending',
        value: '${data.pendingRegistrations}',
        subtitle: 'registrations',
        color: ProvincialAdminColors.amber,
        onTap: onOpenRegistrations,
      ),
      _MetricCard(
        icon: Icons.place_rounded,
        label: 'Tourist Spots',
        value: '${data.spots.length}',
        subtitle: 'province-wide',
        color: ProvincialAdminColors.cyan,
        onTap: onOpenSpots,
      ),
      _MetricCard(
        icon: Icons.inventory_2_rounded,
        label: 'Packages',
        value: '${data.packages.length}',
        subtitle: 'listed tours',
        color: ProvincialAdminColors.green,
        onTap: onOpenPackages,
      ),
      _MetricCard(
        icon: Icons.receipt_long_rounded,
        label: 'Bookings',
        value: '${data.bookings.length}',
        subtitle: 'total requests',
        color: ProvincialAdminColors.purple,
      ),
      _MetricCard(
        icon: Icons.payments_rounded,
        label: 'Revenue',
        value: money.format(data.totalRevenue),
        subtitle: 'completed value',
        color: ProvincialAdminColors.green,
        onTap: onOpenRevenue,
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(child: items[i]),
          if (i != items.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.money,
    required this.data,
    required this.onOpenTenants,
    required this.onOpenRegistrations,
    required this.onOpenSpots,
    required this.onOpenPackages,
    required this.onOpenRevenue,
  });

  final NumberFormat money;
  final AdminDashboardData data;
  final VoidCallback onOpenTenants;
  final VoidCallback onOpenRegistrations;
  final VoidCallback onOpenSpots;
  final VoidCallback onOpenPackages;
  final VoidCallback onOpenRevenue;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricCard(
        icon: Icons.location_city_rounded,
        label: 'City Tenants',
        value: '${data.tenants.length}',
        subtitle: '${data.activeCities} active',
        color: ProvincialAdminColors.blue,
        onTap: onOpenTenants,
      ),
      _MetricCard(
        icon: Icons.how_to_reg_rounded,
        label: 'Pending',
        value: '${data.pendingRegistrations}',
        subtitle: 'registrations',
        color: ProvincialAdminColors.amber,
        onTap: onOpenRegistrations,
      ),
      _MetricCard(
        icon: Icons.place_rounded,
        label: 'Tourist Spots',
        value: '${data.spots.length}',
        subtitle: 'province-wide',
        color: ProvincialAdminColors.cyan,
        onTap: onOpenSpots,
      ),
      _MetricCard(
        icon: Icons.inventory_2_rounded,
        label: 'Packages',
        value: '${data.packages.length}',
        subtitle: 'listed tours',
        color: ProvincialAdminColors.green,
        onTap: onOpenPackages,
      ),
      _MetricCard(
        icon: Icons.receipt_long_rounded,
        label: 'Bookings',
        value: '${data.bookings.length}',
        subtitle: 'total requests',
        color: ProvincialAdminColors.purple,
      ),
      _MetricCard(
        icon: Icons.payments_rounded,
        label: 'Revenue',
        value: money.format(data.totalRevenue),
        subtitle: 'completed value',
        color: ProvincialAdminColors.green,
        onTap: onOpenRevenue,
      ),
    ];

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
      itemBuilder: (_, index) => items[index],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ProvincialAdminColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$value\n',
                        style: const TextStyle(
                          color: ProvincialAdminColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                          height: .95,
                        ),
                      ),
                      TextSpan(
                        text: '$label\n',
                        style: const TextStyle(
                          color: ProvincialAdminColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                          height: 1.1,
                        ),
                      ),
                      TextSpan(
                        text: subtitle,
                        style: const TextStyle(
                          color: ProvincialAdminColors.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 1.15,
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
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Column(
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ProvincialAdminColors.text,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _TopCities extends StatelessWidget {
  const _TopCities({required this.rows});

  final List<CityMetricRow> rows;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Top Cities by Bookings',
      subtitle: 'Package bookings grouped by city.',
      child: rows.isEmpty
          ? const _CenteredEmpty(
              icon: Icons.map_rounded,
              title: 'No city booking data yet.',
              message: 'Bookings data will appear once tours are booked.',
            )
          : Column(
              children: rows.map((row) {
                final max = rows.first.value == 0 ? 1 : rows.first.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _BarRow(
                    label: row.city,
                    value: row.value,
                    factor: row.value / max,
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    final bookings = data.bookings.take(5).toList(growable: false);
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);

    return _SectionCard(
      title: 'Recent Activity',
      subtitle: 'Latest package bookings across Bulacan.',
      child: bookings.isEmpty
          ? const _CenteredEmpty(
              icon: Icons.receipt_long_rounded,
              title: 'No recent activity',
              message: 'Recent booking activity will appear here.',
            )
          : ListView.separated(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bookings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, index) {
                final booking = bookings[index];

                return _CompactTile(
                  icon: Icons.receipt_long_rounded,
                  title: booking.packageTitle,
                  subtitle:
                      '${booking.city} • ${booking.touristName} • ${money.format(booking.totalAmount)}',
                  trailing: AdminStatusPill(status: booking.status),
                );
              },
            ),
    );
  }
}

class _TopPackages extends StatelessWidget {
  const _TopPackages({required this.packages});

  final List<ProvincePackage> packages;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Top Packages',
      subtitle: 'Most booked provincial tour packages.',
      child: packages.isEmpty
          ? const _CenteredEmpty(
              icon: Icons.inventory_2_rounded,
              title: 'No packages yet',
              message: 'Top packages will appear here.',
            )
          : ListView.separated(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: packages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, index) {
                final package = packages[index];
                return _CompactTile(
                  icon: Icons.inventory_2_rounded,
                  title: package.title,
                  subtitle:
                      '${package.city} • ${package.bookingsCount} bookings',
                  trailing: AdminStatusPill(status: package.status),
                );
              },
            ),
    );
  }
}

class _Alerts extends StatelessWidget {
  const _Alerts({required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    final pendingPackages = data.packages
        .where((item) => item.status.toLowerCase() == 'pending')
        .length;
    final unverifiedSpots = data.spots
        .where((item) => item.verificationStatus.toLowerCase() != 'verified')
        .length;
    final lowFeedback = data.feedback.where((item) => item.rating < 3).length;

    final items = [
      _AlertItem(
        icon: Icons.how_to_reg_rounded,
        title: 'Pending city registrations',
        subtitle: data.registrationsTableAvailable
            ? '${data.pendingRegistrations} waiting for action'
            : 'Registration table not connected',
        status: data.pendingRegistrations == 0 ? 'clear' : 'pending',
      ),
      _AlertItem(
        icon: Icons.inventory_2_rounded,
        title: 'Packages needing review',
        subtitle: '$pendingPackages pending submissions',
        status: pendingPackages == 0 ? 'clear' : 'pending',
      ),
      _AlertItem(
        icon: Icons.travel_explore_rounded,
        title: 'Tourism data verification',
        subtitle: '$unverifiedSpots spots not verified',
        status: unverifiedSpots == 0 ? 'verified' : 'review',
      ),
      _AlertItem(
        icon: Icons.rate_review_rounded,
        title: 'Low-rated feedback',
        subtitle: '$lowFeedback reviews below 3 stars',
        status: lowFeedback == 0 ? 'clear' : 'flagged',
      ),
    ];

    return _SectionCard(
      title: 'Alerts & Review Items',
      subtitle: 'Items needing provincial review.',
      child: ListView.separated(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, index) {
          final item = items[index];
          return _CompactTile(
            icon: item.icon,
            title: item.title,
            subtitle: item.subtitle,
            trailing: AdminStatusPill(status: item.status),
          );
        },
      ),
    );
  }
}

class _BookingsOverview extends StatelessWidget {
  const _BookingsOverview({required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    final total = data.bookings.length;
    final pending = data.bookings
        .where((item) => item.status.toLowerCase() == 'pending')
        .length;
    final confirmed = data.bookings
        .where((item) => item.status.toLowerCase() == 'confirmed')
        .length;
    final completed = data.bookings
        .where((item) => item.status.toLowerCase() == 'completed')
        .length;
    final cancelled = data.bookings
        .where((item) => item.status.toLowerCase() == 'cancelled')
        .length;

    return _SectionCard(
      title: 'Bookings Overview',
      subtitle: 'Summary of booking statuses across the province.',
      child: Center(
        child: SizedBox(
          height: 108,
          child: Row(
            children: [
              Expanded(
                child: _BookingStatusBox(
                  label: 'Total',
                  value: total,
                  subtitle: 'All time',
                  color: ProvincialAdminColors.blue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _BookingStatusBox(
                  label: 'Pending',
                  value: pending,
                  subtitle: _percent(pending, total),
                  color: ProvincialAdminColors.amber,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _BookingStatusBox(
                  label: 'Confirmed',
                  value: confirmed,
                  subtitle: _percent(confirmed, total),
                  color: ProvincialAdminColors.purple,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _BookingStatusBox(
                  label: 'Completed',
                  value: completed,
                  subtitle: _percent(completed, total),
                  color: ProvincialAdminColors.green,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _BookingStatusBox(
                  label: 'Cancelled',
                  value: cancelled,
                  subtitle: _percent(cancelled, total),
                  color: ProvincialAdminColors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _percent(int value, int total) {
    if (total == 0) return '0%';
    return '${((value / total) * 100).round()}%';
  }
}

class _BookingStatusBox extends StatelessWidget {
  const _BookingStatusBox({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  final String label;
  final int value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: .95,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            label,
            style: const TextStyle(
              color: ProvincialAdminColors.text,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertItem {
  const _AlertItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
}

class _CompactTile extends StatelessWidget {
  const _CompactTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: ProvincialAdminColors.blue,
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title\n',
                    style: const TextStyle(
                      color: ProvincialAdminColors.text,
                      fontSize: 13.5,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: subtitle,
                    style: const TextStyle(
                      color: ProvincialAdminColors.muted,
                      fontSize: 12,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.factor,
  });

  final String label;
  final int value;
  final double factor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ProvincialAdminColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    height: 1,
                  ),
                ),
              ),
              Text(
                '$value',
                style: const TextStyle(
                  color: ProvincialAdminColors.muted,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: factor.clamp(.08, 1),
              color: ProvincialAdminColors.blue,
              backgroundColor: const Color(0xFFEAF2FF),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredEmpty extends StatelessWidget {
  const _CenteredEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.translate(
        offset: const Offset(0, -8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icon,
                color: ProvincialAdminColors.blue,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ProvincialAdminColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ProvincialAdminColors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}