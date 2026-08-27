import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/city_tenants_screen.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/province_packages_screen.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/provincial_spots_screen.dart';
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
    setState(() {
      _future = _service.loadDashboard();
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );

    if (mounted) {
      _reload();
    }
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

          if (!snapshot.hasData) {
            return AdminErrorView(
              message: 'No dashboard data is available.',
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
              final width = constraints.maxWidth;

              if (width >= 1280) {
                return _DesktopDashboard(
                  data: data,
                  money: money,
                  openTenants: () => _open(
                    const CityTenantsScreen(),
                  ),
                  openRegistrations: () => _open(
                    const CityTenantsScreen(),
                  ),
                  openSpots: () => _open(
                    const ProvincialSpotsScreen(),
                  ),
                  openPackages: () => _open(
                    const ProvincePackagesScreen(),
                  ),
                );
              }

              if (width >= 760) {
                return _TabletDashboard(
                  data: data,
                  money: money,
                  openTenants: () => _open(
                    const CityTenantsScreen(),
                  ),
                  openRegistrations: () => _open(
                    const CityTenantsScreen(),
                  ),
                  openSpots: () => _open(
                    const ProvincialSpotsScreen(),
                  ),
                  openPackages: () => _open(
                    const ProvincePackagesScreen(),
                  ),
                );
              }

              return _MobileDashboard(
                data: data,
                money: money,
                openTenants: () => _open(
                  const CityTenantsScreen(),
                ),
                openRegistrations: () => _open(
                  const CityTenantsScreen(),
                ),
                openSpots: () => _open(
                  const ProvincialSpotsScreen(),
                ),
                openPackages: () => _open(
                  const ProvincePackagesScreen(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================
// DESKTOP
// ============================================================

class _DesktopDashboard extends StatelessWidget {
  const _DesktopDashboard({
    required this.data,
    required this.money,
    required this.openTenants,
    required this.openRegistrations,
    required this.openSpots,
    required this.openPackages,
  });

  final AdminDashboardData data;
  final NumberFormat money;

  final VoidCallback openTenants;
  final VoidCallback openRegistrations;
  final VoidCallback openSpots;
  final VoidCallback openPackages;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeBanner(
            data: data,
            large: true,
          ),

          const SizedBox(height: 20),

          _MetricsGrid(
            data: data,
            money: money,
            columns: 6,
            onOpenTenants: openTenants,
            onOpenRegistrations: openRegistrations,
            onOpenSpots: openSpots,
            onOpenPackages: openPackages,
          ),

          const SizedBox(height: 20),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: SizedBox(
                  height: 370,
                  child: _TopCities(
                    rows: data.bookingsByCity.take(6).toList(),
                  ),
                ),
              ),

              const SizedBox(width: 18),

              Expanded(
                flex: 6,
                child: SizedBox(
                  height: 370,
                  child: _RecentActivity(
                    data: data,
                  ),
                ),
              ),

              const SizedBox(width: 18),

              Expanded(
                flex: 5,
                child: SizedBox(
                  height: 370,
                  child: _TopPackages(
                    packages: data.topPackages.take(4).toList(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: _BookingsOverview(
                  data: data,
                ),
              ),

              const SizedBox(width: 18),

              Expanded(
                flex: 5,
                child: SizedBox(
                  height: 270,
                  child: _Alerts(
                    data: data,
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

// ============================================================
// TABLET
// ============================================================

class _TabletDashboard extends StatelessWidget {
  const _TabletDashboard({
    required this.data,
    required this.money,
    required this.openTenants,
    required this.openRegistrations,
    required this.openSpots,
    required this.openPackages,
  });

  final AdminDashboardData data;
  final NumberFormat money;

  final VoidCallback openTenants;
  final VoidCallback openRegistrations;
  final VoidCallback openSpots;
  final VoidCallback openPackages;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeBanner(
            data: data,
            large: false,
          ),

          const SizedBox(height: 18),

          _MetricsGrid(
            data: data,
            money: money,
            columns: 3,
            onOpenTenants: openTenants,
            onOpenRegistrations: openRegistrations,
            onOpenSpots: openSpots,
            onOpenPackages: openPackages,
          ),

          const SizedBox(height: 18),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: 340,
                  child: _TopCities(
                    rows: data.bookingsByCity.take(5).toList(),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: SizedBox(
                  height: 340,
                  child: _RecentActivity(
                    data: data,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: 300,
                  child: _TopPackages(
                    packages: data.topPackages.take(4).toList(),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: SizedBox(
                  height: 300,
                  child: _Alerts(
                    data: data,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _BookingsOverview(
            data: data,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// MOBILE
// ============================================================

class _MobileDashboard extends StatelessWidget {
  const _MobileDashboard({
    required this.data,
    required this.money,
    required this.openTenants,
    required this.openRegistrations,
    required this.openSpots,
    required this.openPackages,
  });

  final AdminDashboardData data;
  final NumberFormat money;

  final VoidCallback openTenants;
  final VoidCallback openRegistrations;
  final VoidCallback openSpots;
  final VoidCallback openPackages;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeBanner(
            data: data,
            large: false,
          ),

          const SizedBox(height: 14),

          _MetricsGrid(
            data: data,
            money: money,
            columns: 2,
            onOpenTenants: openTenants,
            onOpenRegistrations: openRegistrations,
            onOpenSpots: openSpots,
            onOpenPackages: openPackages,
          ),

          const SizedBox(height: 14),

          SizedBox(
            height: 330,
            child: _TopCities(
              rows: data.bookingsByCity.take(5).toList(),
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            height: 350,
            child: _RecentActivity(
              data: data,
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            height: 310,
            child: _TopPackages(
              packages: data.topPackages.take(4).toList(),
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            height: 330,
            child: _Alerts(
              data: data,
            ),
          ),

          const SizedBox(height: 14),

          _BookingsOverview(
            data: data,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WELCOME BANNER
// ============================================================

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({
    required this.data,
    required this.large,
  });

  final AdminDashboardData data;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    final compact = width < 500;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        compact
            ? 17
            : large
                ? 26
                : 22,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1557D6),
            Color(0xFF2877EA),
            Color(0xFF39A8ED),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(
          compact ? 22 : 26,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1557D6).withValues(
              alpha: .18,
            ),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -55,
            top: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .07),
              ),
            ),
          ),

          Positioned(
            right: 70,
            bottom: -100,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .05),
              ),
            ),
          ),

          Row(
            children: [
              Container(
                width: compact ? 50 : 62,
                height: compact ? 50 : 62,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(
                    compact ? 16 : 20,
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .18),
                  ),
                ),
                child: Icon(
                  Icons.account_balance_rounded,
                  color: Colors.white,
                  size: compact ? 25 : 31,
                ),
              ),

              SizedBox(
                width: compact ? 12 : 16,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BULACAN PROVINCIAL TOURISM OFFICE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .78),
                        fontSize: compact ? 9.5 : 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      'Hello, ${data.profile.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact
                            ? 20
                            : large
                                ? 28
                                : 24,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.4,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      compact
                          ? '${data.activeCities} active cities'
                          : 'Manage tenants, tourism data, packages, revenue, and reports across Bulacan.',
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .88),
                        fontSize: compact ? 11 : 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),

              if (!compact) ...[
                const SizedBox(width: 14),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .14),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_city_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '${data.activeCities} active cities',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// METRICS
// ============================================================

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.data,
    required this.money,
    required this.columns,
    required this.onOpenTenants,
    required this.onOpenRegistrations,
    required this.onOpenSpots,
    required this.onOpenPackages,
  });

  final AdminDashboardData data;
  final NumberFormat money;
  final int columns;

  final VoidCallback onOpenTenants;
  final VoidCallback onOpenRegistrations;
  final VoidCallback onOpenSpots;
  final VoidCallback onOpenPackages;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricData(
        icon: Icons.location_city_rounded,
        label: 'City Tenants',
        value: '${data.tenants.length}',
        subtitle: '${data.activeCities} active',
        color: ProvincialAdminColors.blue,
        onTap: onOpenTenants,
      ),

      _MetricData(
        icon: Icons.pending_actions_rounded,
        label: 'Pending',
        value: '${data.pendingRegistrations}',
        subtitle: 'registrations',
        color: ProvincialAdminColors.amber,
        onTap: onOpenRegistrations,
      ),

      _MetricData(
        icon: Icons.place_rounded,
        label: 'Tourist Spots',
        value: '${data.spots.length}',
        subtitle: 'province-wide',
        color: ProvincialAdminColors.cyan,
        onTap: onOpenSpots,
      ),

      _MetricData(
        icon: Icons.inventory_2_rounded,
        label: 'Packages',
        value: '${data.packages.length}',
        subtitle: 'listed tours',
        color: ProvincialAdminColors.green,
        onTap: onOpenPackages,
      ),

      _MetricData(
        icon: Icons.receipt_long_rounded,
        label: 'Bookings',
        value: '${data.bookings.length}',
        subtitle: 'total requests',
        color: ProvincialAdminColors.purple,
      ),

      _MetricData(
        icon: Icons.payments_rounded,
        label: 'Revenue',
        value: money.format(data.totalRevenue),
        subtitle: 'completed value',
        color: ProvincialAdminColors.green,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: columns == 2
            ? 1.55
            : columns == 3
                ? 1.75
                : 1.65,
      ),
      itemBuilder: (context, index) {
        return _MetricCard(
          item: items[index],
          compact: columns == 2,
        );
      },
    );
  }
}

class _MetricData {
  const _MetricData({
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
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.item,
    required this.compact,
  });

  final _MetricData item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.all(
            compact ? 13 : 15,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ProvincialAdminColors.line,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .025),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 42 : 46,
                height: compact ? 42 : 46,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  item.icon,
                  color: item.color,
                  size: compact ? 20 : 22,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ProvincialAdminColors.muted,
                        fontSize: compact ? 10.5 : 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 3),

                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.value,
                        maxLines: 1,
                        style: TextStyle(
                          color: ProvincialAdminColors.text,
                          fontSize: compact ? 22 : 25,
                          height: .95,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: item.color,
                        fontSize: compact ? 9.5 : 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SECTION CARD
// ============================================================

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.actionLabel,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        18,
        18,
        18,
        16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: ProvincialAdminColors.line,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .025),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: ProvincialAdminColors.blue,
                  size: 20,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProvincialAdminColors.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        height: 1.05,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProvincialAdminColors.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

              if (actionLabel != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      color: ProvincialAdminColors.blue,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 17),

          Expanded(
            child: child,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TOP CITIES
// ============================================================

class _TopCities extends StatelessWidget {
  const _TopCities({
    required this.rows,
  });

  final List<CityMetricRow> rows;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Top Cities',
      subtitle: 'Package bookings grouped by city.',
      icon: Icons.location_city_rounded,
      actionLabel: 'BOOKINGS',
      child: rows.isEmpty
          ? const _CenteredEmpty(
              icon: Icons.map_outlined,
              title: 'No city booking data yet',
              message: 'Booking activity will appear here once tours are booked.',
            )
          : ListView.separated(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 11),
              itemBuilder: (_, index) {
                final row = rows[index];

                final max = rows.isEmpty
                    ? 1
                    : rows
                        .map((item) => item.value)
                        .reduce(
                          (a, b) => a > b ? a : b,
                        );

                final factor = max == 0
                    ? 0.0
                    : row.value / max;

                return _CityBarRow(
                  rank: index + 1,
                  city: row.city,
                  value: row.value,
                  factor: factor,
                );
              },
            ),
    );
  }
}

class _CityBarRow extends StatelessWidget {
  const _CityBarRow({
    required this.rank,
    required this.city,
    required this.value,
    required this.factor,
  });

  final int rank;
  final String city;
  final int value;
  final double factor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rank == 1
                    ? const Color(0xFFEAF3FF)
                    : const Color(0xFFF4F7FB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  color: rank == 1
                      ? ProvincialAdminColors.blue
                      : ProvincialAdminColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),

            const SizedBox(width: 9),

            Expanded(
              child: Text(
                city,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ProvincialAdminColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),

            Text(
              '$value',
              style: const TextStyle(
                color: ProvincialAdminColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),

        const SizedBox(height: 7),

        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(
                height: 7,
                width: double.infinity,
                color: const Color(0xFFEAF2FF),
              ),

              FractionallySizedBox(
                widthFactor: factor.clamp(.04, 1.0),
                child: Container(
                  height: 7,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF4AA3FF),
                        Color(0xFF1557D6),
                      ],
                    ),
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

// ============================================================
// RECENT ACTIVITY
// ============================================================

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({
    required this.data,
  });

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    final bookings = data.bookings.take(5).toList(
          growable: false,
        );

    final money = NumberFormat.currency(
      symbol: 'PHP ',
      decimalDigits: 0,
    );

    return _SectionCard(
      title: 'Recent Activity',
      subtitle: 'Latest package bookings across Bulacan.',
      icon: Icons.timeline_rounded,
      actionLabel: 'LATEST',
      child: bookings.isEmpty
          ? const _CenteredEmpty(
              icon: Icons.receipt_long_outlined,
              title: 'No recent activity',
              message: 'Recent booking activity will appear here.',
            )
          : ListView.separated(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bookings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final booking = bookings[index];

                return _ActivityTile(
                  icon: Icons.receipt_long_rounded,
                  title: booking.packageTitle,
                  subtitle:
                      '${booking.city} • ${booking.touristName}',
                  amount: money.format(
                    booking.totalAmount,
                  ),
                  status: booking.status,
                );
              },
            ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String amount;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: ProvincialAdminColors.line,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: ProvincialAdminColors.blue,
              size: 19,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ProvincialAdminColors.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ProvincialAdminColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  amount,
                  style: const TextStyle(
                    color: ProvincialAdminColors.blue,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          AdminStatusPill(
            status: status,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TOP PACKAGES
// ============================================================

class _TopPackages extends StatelessWidget {
  const _TopPackages({
    required this.packages,
  });

  final List<ProvincePackage> packages;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Top Packages',
      subtitle: 'Most booked provincial tour packages.',
      icon: Icons.inventory_2_rounded,
      actionLabel: 'POPULAR',
      child: packages.isEmpty
          ? const _CenteredEmpty(
              icon: Icons.inventory_2_outlined,
              title: 'No packages yet',
              message: 'Published packages will appear here.',
            )
          : ListView.separated(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: packages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final package = packages[index];

                return _PackageTile(
                  rank: index + 1,
                  title: package.title,
                  city: package.city,
                  bookings: package.bookingsCount,
                  status: package.status,
                );
              },
            ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.rank,
    required this.title,
    required this.city,
    required this.bookings,
    required this.status,
  });

  final int rank;
  final String title;
  final String city;
  final int bookings;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: ProvincialAdminColors.line,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rank == 1
                  ? const Color(0xFFEAF3FF)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                color: rank == 1
                    ? ProvincialAdminColors.blue
                    : ProvincialAdminColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ProvincialAdminColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  '$city • $bookings bookings',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ProvincialAdminColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 7),

          AdminStatusPill(
            status: status,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ALERTS
// ============================================================

class _Alerts extends StatelessWidget {
  const _Alerts({
    required this.data,
  });

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    final pendingPackages = data.packages
        .where(
          (item) =>
              item.status.toLowerCase() == 'pending',
        )
        .length;

    final unverifiedSpots = data.spots
        .where(
          (item) =>
              item.verificationStatus.toLowerCase() !=
              'verified',
        )
        .length;

    final lowFeedback = data.feedback
        .where(
          (item) => item.rating < 3,
        )
        .length;

    final items = [
      _AlertItem(
        icon: Icons.how_to_reg_rounded,
        title: 'Pending city registrations',
        subtitle: data.registrationsTableAvailable
            ? '${data.pendingRegistrations} waiting for action'
            : 'Registration table not connected',
        status: data.pendingRegistrations == 0
            ? 'clear'
            : 'pending',
        color: ProvincialAdminColors.amber,
      ),

      _AlertItem(
        icon: Icons.inventory_2_rounded,
        title: 'Packages needing review',
        subtitle: '$pendingPackages pending submissions',
        status: pendingPackages == 0
            ? 'clear'
            : 'pending',
        color: ProvincialAdminColors.blue,
      ),

      _AlertItem(
        icon: Icons.travel_explore_rounded,
        title: 'Tourism data verification',
        subtitle: '$unverifiedSpots spots not verified',
        status: unverifiedSpots == 0
            ? 'verified'
            : 'review',
        color: ProvincialAdminColors.cyan,
      ),

      _AlertItem(
        icon: Icons.rate_review_rounded,
        title: 'Low-rated feedback',
        subtitle: '$lowFeedback reviews below 3 stars',
        status: lowFeedback == 0
            ? 'clear'
            : 'flagged',
        color: ProvincialAdminColors.red,
      ),
    ];

    return _SectionCard(
      title: 'Alerts & Reviews',
      subtitle: 'Items that may need provincial attention.',
      icon: Icons.notifications_active_rounded,
      actionLabel: 'REVIEW',
      child: ListView.separated(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, index) {
          final item = items[index];

          return _AlertTile(
            item: item,
          );
        },
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
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final Color color;
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.item,
  });

  final _AlertItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: ProvincialAdminColors.line,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              item.icon,
              color: item.color,
              size: 19,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ProvincialAdminColors.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ProvincialAdminColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 7),

          AdminStatusPill(
            status: item.status,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BOOKINGS OVERVIEW
// ============================================================

class _BookingsOverview extends StatelessWidget {
  const _BookingsOverview({
    required this.data,
  });

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    final total = data.bookings.length;

    final pending = data.bookings
        .where(
          (item) =>
              item.status.toLowerCase() == 'pending',
        )
        .length;

    final confirmed = data.bookings
        .where(
          (item) =>
              item.status.toLowerCase() == 'confirmed',
        )
        .length;

    final completed = data.bookings
        .where(
          (item) =>
              item.status.toLowerCase() == 'completed',
        )
        .length;

    final cancelled = data.bookings
        .where(
          (item) =>
              item.status.toLowerCase() == 'cancelled',
        )
        .length;

    final boxes = [
      _BookingStatusBox(
        label: 'Total',
        value: total,
        subtitle: 'All time',
        color: ProvincialAdminColors.blue,
        icon: Icons.receipt_long_rounded,
      ),

      _BookingStatusBox(
        label: 'Pending',
        value: pending,
        subtitle: _percent(pending, total),
        color: ProvincialAdminColors.amber,
        icon: Icons.schedule_rounded,
      ),

      _BookingStatusBox(
        label: 'Confirmed',
        value: confirmed,
        subtitle: _percent(confirmed, total),
        color: ProvincialAdminColors.purple,
        icon: Icons.check_circle_outline_rounded,
      ),

      _BookingStatusBox(
        label: 'Completed',
        value: completed,
        subtitle: _percent(completed, total),
        color: ProvincialAdminColors.green,
        icon: Icons.task_alt_rounded,
      ),

      _BookingStatusBox(
        label: 'Cancelled',
        value: cancelled,
        subtitle: _percent(cancelled, total),
        color: ProvincialAdminColors.red,
        icon: Icons.cancel_outlined,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: ProvincialAdminColors.line,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .025),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: ProvincialAdminColors.blue,
                  size: 21,
                ),
              ),

              const SizedBox(width: 11),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bookings Overview',
                      style: TextStyle(
                        color: ProvincialAdminColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    SizedBox(height: 4),

                    Text(
                      'Summary of booking statuses across the province.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ProvincialAdminColors.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 17),

          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              if (width >= 650) {
                return SizedBox(
                  height: 112,
                  child: Row(
                    children: [
                      for (var i = 0; i < boxes.length; i++) ...[
                        Expanded(
                          child: boxes[i],
                        ),
                        if (i != boxes.length - 1)
                          const SizedBox(width: 10),
                      ],
                    ],
                  ),
                );
              }

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: boxes.length,
                gridDelegate:
                    SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: width < 390 ? 2 : 3,
                  crossAxisSpacing: 9,
                  mainAxisSpacing: 9,
                  childAspectRatio: 1.35,
                ),
                itemBuilder: (_, index) {
                  return boxes[index];
                },
              );
            },
          ),
        ],
      ),
    );
  }

  String _percent(
    int value,
    int total,
  ) {
    if (total == 0) {
      return '0%';
    }

    return '${((value / total) * 100).round()}%';
  }
}

class _BookingStatusBox extends StatelessWidget {
  const _BookingStatusBox({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final String label;
  final int value;
  final String subtitle;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .065),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: color.withValues(alpha: .13),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              color: color,
              size: 17,
            ),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$value',
                    style: TextStyle(
                      color: color,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      height: .95,
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ProvincialAdminColors.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ProvincialAdminColors.muted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
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

// ============================================================
// EMPTY STATE
// ============================================================

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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(19),
              ),
              child: Icon(
                icon,
                color: ProvincialAdminColors.blue,
                size: 28,
              ),
            ),

            const SizedBox(height: 13),

            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ProvincialAdminColors.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ProvincialAdminColors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}