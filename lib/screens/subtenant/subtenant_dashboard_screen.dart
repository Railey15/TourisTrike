import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_announcements_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_bookings_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_city_profile_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_drivers_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_package_form_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_reports_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/subtenant_spot_form_screen.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantDashboardScreen extends StatefulWidget {
  const SubTenantDashboardScreen({super.key});

  @override
  State<SubTenantDashboardScreen> createState() =>
      _SubTenantDashboardScreenState();
}

class _SubTenantDashboardScreenState extends State<SubTenantDashboardScreen> {
  final SubTenantService _service = SubTenantService();
  late Future<SubTenantDashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.loadDashboard();
  }

  void _reload() {
    setState(() => _future = _service.loadDashboard());
  }

  Future<void> _open(Widget page) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (!mounted) return;
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: 0,
      title: 'Dashboard',
      subtitle: 'City tourism overview, package operations, and bookings.',
      child: FutureBuilder<SubTenantDashboardData>(
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

          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ResponsivePageContainer(
              children: [
                _DashboardContent(
                  data: data,
                  onAddSpot: () => _open(const SubTenantSpotFormScreen()),
                  onCreatePackage: () =>
                      _open(const SubTenantPackageFormScreen()),
                  onDrivers: () => _open(const SubTenantDriversScreen()),
                  onBookings: () => _open(const SubTenantBookingsScreen()),
                  onReports: () => _open(const SubTenantReportsScreen()),
                  onAnnouncements: () =>
                      _open(const SubTenantAnnouncementsScreen()),
                  onProfile: () => _open(const SubTenantCityProfileScreen()),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.data,
    required this.onAddSpot,
    required this.onCreatePackage,
    required this.onDrivers,
    required this.onBookings,
    required this.onReports,
    required this.onAnnouncements,
    required this.onProfile,
  });

  final SubTenantDashboardData data;
  final VoidCallback onAddSpot;
  final VoidCallback onCreatePackage;
  final VoidCallback onDrivers;
  final VoidCallback onBookings;
  final VoidCallback onReports;
  final VoidCallback onAnnouncements;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardHeader(
          eyebrow: 'City Admin Dashboard',
          title: 'Hello, ${data.profile.displayName}',
          subtitle:
              'Manage destinations, packages, bookings, and local tricycle tourism operations for ${data.profile.assignedCity}.',
          trailing: _CityScopeBadge(profile: data.profile),
        ),
        const SizedBox(height: 18),
        ResponsiveGrid(
          minItemWidth: 190,
          maxColumns: 4,
          mobileAspectRatio: 1.72,
          tabletAspectRatio: 1.55,
          desktopAspectRatio: 1.50,
          children: [
            DashboardMetricCard(
              icon: Icons.place_rounded,
              label: 'Tourist Spots',
              value: '${data.totalSpots}',
              color: const Color(0xFF2A86FF),
              onTap: onAddSpot,
            ),
            DashboardMetricCard(
              icon: Icons.inventory_2_rounded,
              label: 'Packages',
              value: '${data.totalPackages}',
              color: const Color(0xFF0EA5E9),
              onTap: onCreatePackage,
            ),
            DashboardMetricCard(
              icon: Icons.badge_rounded,
              label: 'Drivers/Guides',
              value: '${data.totalDrivers}',
              color: const Color(0xFF16A34A),
              onTap: onDrivers,
            ),
            DashboardMetricCard(
              icon: Icons.pending_actions_rounded,
              label: 'Pending Bookings',
              value: '${data.pendingBookings}',
              subtitle: 'Active tours: ${data.activeTours}',
              color: const Color(0xFFF59E0B),
              onTap: onBookings,
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (desktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  children: [
                    _QuickActions(
                      onAddSpot: onAddSpot,
                      onCreatePackage: onCreatePackage,
                      onDrivers: onDrivers,
                      onBookings: onBookings,
                      onReports: onReports,
                      onAnnouncements: onAnnouncements,
                    ),
                    const SizedBox(height: 18),
                    _RecentBookings(
                      bookings: data.recentBookings,
                      onViewAll: onBookings,
                    ),
                    const SizedBox(height: 18),
                    _AnalyticsCard(data: data),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 360,
                child: _SidePanel(
                  data: data,
                  onAnnouncements: onAnnouncements,
                  onProfile: onProfile,
                ),
              ),
            ],
          )
        else ...[
          _QuickActions(
            onAddSpot: onAddSpot,
            onCreatePackage: onCreatePackage,
            onDrivers: onDrivers,
            onBookings: onBookings,
            onReports: onReports,
            onAnnouncements: onAnnouncements,
          ),
          const SizedBox(height: 16),
          _RecentBookings(bookings: data.recentBookings, onViewAll: onBookings),
          const SizedBox(height: 16),
          _AnalyticsCard(data: data),
          const SizedBox(height: 16),
          _SidePanel(
            data: data,
            onAnnouncements: onAnnouncements,
            onProfile: onProfile,
          ),
        ],
      ],
    );
  }
}

class _CityScopeBadge extends StatelessWidget {
  const _CityScopeBadge({required this.profile});

  final SubTenantProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_user_rounded, color: Colors.white),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.assignedCity,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${profile.province} scope',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
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

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onAddSpot,
    required this.onCreatePackage,
    required this.onDrivers,
    required this.onBookings,
    required this.onReports,
    required this.onAnnouncements,
  });

  final VoidCallback onAddSpot;
  final VoidCallback onCreatePackage;
  final VoidCallback onDrivers;
  final VoidCallback onBookings;
  final VoidCallback onReports;
  final VoidCallback onAnnouncements;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Column(
        children: [
          const SubTenantSectionHeader(
            title: 'Quick Actions',
            subtitle: 'Common city tourism admin tasks.',
          ),
          const SizedBox(height: 14),
          ResponsiveGrid(
            minItemWidth: 230,
            maxColumns: Responsive.isDesktop(context) ? 3 : 2,
            mobileAspectRatio: 3.15,
            tabletAspectRatio: 3.35,
            desktopAspectRatio: 3.85,
            children: [
              _ActionButton(
                icon: Icons.add_location_alt_rounded,
                label: 'Add Tourist Spot',
                onTap: onAddSpot,
              ),
              _ActionButton(
                icon: Icons.add_box_rounded,
                label: 'Create Package',
                onTap: onCreatePackage,
              ),
              _ActionButton(
                icon: Icons.badge_rounded,
                label: 'Manage Drivers',
                onTap: onDrivers,
              ),
              _ActionButton(
                icon: Icons.receipt_long_rounded,
                label: 'View Bookings',
                onTap: onBookings,
              ),
              _ActionButton(
                icon: Icons.bar_chart_rounded,
                label: 'City Reports',
                onTap: onReports,
              ),
              _ActionButton(
                icon: Icons.campaign_rounded,
                label: 'Announcements',
                onTap: onAnnouncements,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(17),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: _hovered
                  ? SubTenantColors.blue.withValues(alpha: 0.10)
                  : const Color(0xFFF4F8FF),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: _hovered
                    ? SubTenantColors.blue.withValues(alpha: 0.22)
                    : SubTenantColors.line,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: SubTenantColors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    widget.icon,
                    color: SubTenantColors.blue,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SubTenantColors.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentBookings extends StatelessWidget {
  const _RecentBookings({required this.bookings, required this.onViewAll});

  final List<SubTenantBooking> bookings;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return EmptyStateCard(
        icon: Icons.receipt_long_outlined,
        title: 'No bookings yet',
        message: 'New package bookings for this city will appear here.',
        actionLabel: 'View Bookings',
        onAction: onViewAll,
      );
    }

    if (Responsive.isDesktop(context)) {
      return DashboardSectionCard(
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: SubTenantSectionHeader(
                title: 'Recent Bookings',
                subtitle: 'Latest package requests in your city.',
                trailing: 'View All',
                onTrailingTap: onViewAll,
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(22),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 760),
                  child: DataTable(
                    headingTextStyle: const TextStyle(
                      color: SubTenantColors.muted,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                    dataTextStyle: const TextStyle(
                      color: SubTenantColors.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    columns: const [
                      DataColumn(label: Text('Package')),
                      DataColumn(label: Text('Tourist')),
                      DataColumn(label: Text('Travel Date')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: bookings
                        .map((booking) {
                          final date = booking.travelDate == null
                              ? 'No date'
                              : DateFormat(
                                  'MMM d, yyyy',
                                ).format(booking.travelDate!);
                          return DataRow(
                            cells: [
                              DataCell(Text(booking.packageTitle)),
                              DataCell(Text(booking.touristName)),
                              DataCell(Text(date)),
                              DataCell(
                                SubTenantStatusPill(status: booking.status),
                              ),
                            ],
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return DashboardSectionCard(
      child: Column(
        children: [
          SubTenantSectionHeader(
            title: 'Recent Bookings',
            subtitle: 'Latest package requests in your city.',
            trailing: 'View All',
            onTrailingTap: onViewAll,
          ),
          const SizedBox(height: 12),
          ...bookings.map(
            (booking) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BookingMiniTile(booking: booking),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingMiniTile extends StatelessWidget {
  const _BookingMiniTile({required this.booking});

  final SubTenantBooking booking;

  @override
  Widget build(BuildContext context) {
    final date = booking.travelDate == null
        ? 'No date'
        : DateFormat('MMM d, yyyy').format(booking.travelDate!);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: SubTenantColors.blue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.confirmation_number_rounded,
              color: SubTenantColors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.packageTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${booking.touristName} - $date',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SubTenantColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SubTenantStatusPill(status: booking.status),
        ],
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({required this.data});

  final SubTenantDashboardData data;

  @override
  Widget build(BuildContext context) {
    final values = [
      data.totalSpots,
      data.totalPackages,
      data.totalDrivers,
      data.pendingBookings,
      data.activeTours,
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
            title: 'Operations Snapshot',
            subtitle: 'A quick visual read of active city workspace volume.',
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: Responsive.isDesktop(context) ? 190 : 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _ChartBar(
                  label: 'Spots',
                  value: data.totalSpots,
                  maxValue: maxValue,
                  color: const Color(0xFF2A86FF),
                ),
                _ChartBar(
                  label: 'Packages',
                  value: data.totalPackages,
                  maxValue: maxValue,
                  color: const Color(0xFF0EA5E9),
                ),
                _ChartBar(
                  label: 'Drivers',
                  value: data.totalDrivers,
                  maxValue: maxValue,
                  color: const Color(0xFF16A34A),
                ),
                _ChartBar(
                  label: 'Pending',
                  value: data.pendingBookings,
                  maxValue: maxValue,
                  color: const Color(0xFFF59E0B),
                ),
                _ChartBar(
                  label: 'Active',
                  value: data.activeTours,
                  maxValue: maxValue,
                  color: const Color(0xFF7C3AED),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartBar extends StatelessWidget {
  const _ChartBar({
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
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '$value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SubTenantColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: (0.14 + (factor * 0.86)).clamp(0.14, 1.0),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color.withValues(alpha: 0.82), color],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SubTenantColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.data,
    required this.onAnnouncements,
    required this.onProfile,
  });

  final SubTenantDashboardData data;
  final VoidCallback onAnnouncements;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfileSummary(data: data, onProfile: onProfile),
        const SizedBox(height: 16),
        _AnnouncementsCard(data: data, onAnnouncements: onAnnouncements),
        const SizedBox(height: 16),
        _ActivityFeed(bookings: data.recentBookings),
      ],
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.data, required this.onProfile});

  final SubTenantDashboardData data;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Column(
        children: [
          const SubTenantSectionHeader(
            title: 'Profile & Settings',
            subtitle: 'City profile, office contact, and media.',
          ),
          const SizedBox(height: 8),
          SubTenantInfoTile(
            icon: Icons.location_city_rounded,
            title: data.profile.assignedCity,
            subtitle: '${data.profile.province} Tourism Office settings',
            onTap: onProfile,
          ),
        ],
      ),
    );
  }
}

class _AnnouncementsCard extends StatelessWidget {
  const _AnnouncementsCard({required this.data, required this.onAnnouncements});

  final SubTenantDashboardData data;
  final VoidCallback onAnnouncements;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Column(
        children: [
          SubTenantSectionHeader(
            title: 'Announcements',
            subtitle: data.announcementsTableAvailable
                ? 'Latest city updates for tourism operations.'
                : 'Announcement table is not available yet.',
            trailing: 'Manage',
            onTrailingTap: onAnnouncements,
          ),
          const SizedBox(height: 10),
          if (data.announcements.isEmpty)
            const _InlineEmptyState(
              icon: Icons.campaign_outlined,
              title: 'No announcements',
              message: 'Published city updates will appear here.',
            )
          else
            ...data.announcements.map(
              (item) => SubTenantInfoTile(
                icon: Icons.campaign_rounded,
                title: item.title,
                subtitle: item.body,
                trailing: SubTenantStatusPill(status: item.status),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityFeed extends StatelessWidget {
  const _ActivityFeed({required this.bookings});

  final List<SubTenantBooking> bookings;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Column(
        children: [
          const SubTenantSectionHeader(
            title: 'Activity Feed',
            subtitle: 'Recent booking activity across local packages.',
          ),
          const SizedBox(height: 10),
          if (bookings.isEmpty)
            const _InlineEmptyState(
              icon: Icons.timeline_rounded,
              title: 'Quiet for now',
              message: 'Booking changes and local activity will appear here.',
            )
          else
            ...bookings.take(4).map((booking) {
              final created = booking.createdAt == null
                  ? 'Recently'
                  : DateFormat('MMM d, h:mm a').format(booking.createdAt!);
              return SubTenantInfoTile(
                icon: Icons.timeline_rounded,
                title: booking.packageTitle,
                subtitle: '${booking.touristName} - $created',
                trailing: SubTenantStatusPill(status: booking.status),
              );
            }),
        ],
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, color: SubTenantColors.blue, size: 28),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SubTenantColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SubTenantColors.muted,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
