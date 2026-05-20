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
          return _DashboardContent(
            data: data,
            onRefresh: _reload,
            onAddSpot: () => _open(const SubTenantSpotFormScreen()),
            onCreatePackage: () => _open(const SubTenantPackageFormScreen()),
            onDrivers: () => _open(const SubTenantDriversScreen()),
            onBookings: () => _open(const SubTenantBookingsScreen()),
            onReports: () => _open(const SubTenantReportsScreen()),
            onAnnouncements: () => _open(const SubTenantAnnouncementsScreen()),
            onProfile: () => _open(const SubTenantCityProfileScreen()),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.data,
    required this.onRefresh,
    required this.onAddSpot,
    required this.onCreatePackage,
    required this.onDrivers,
    required this.onBookings,
    required this.onReports,
    required this.onAnnouncements,
    required this.onProfile,
  });

  final SubTenantDashboardData data;
  final VoidCallback onRefresh;
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

    // ── Mobile / tablet ─────────────────────────────────────────────────────
    if (!desktop) {
      return RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 22),
          child: Column(
            children: [
              _CompactHeader(data: data),
              const SizedBox(height: 12),
              _MobileMetricsGrid(
                data: data,
                onAddSpot: onAddSpot,
                onCreatePackage: onCreatePackage,
                onDrivers: onDrivers,
                onBookings: onBookings,
              ),
              const SizedBox(height: 12),
              _QuickActions(
                onAddSpot: onAddSpot,
                onCreatePackage: onCreatePackage,
                onDrivers: onDrivers,
                onBookings: onBookings,
                onReports: onReports,
                onAnnouncements: onAnnouncements,
              ),
              const SizedBox(height: 12),
              _RecentBookings(
                bookings: data.recentBookings,
                onViewAll: onBookings,
              ),
              const SizedBox(height: 12),
              _AnalyticsCard(data: data),
              const SizedBox(height: 12),
              _SidePanel(
                data: data,
                onAnnouncements: onAnnouncements,
                onProfile: onProfile,
              ),
            ],
          ),
        ),
      );
    }

    // ── Desktop ─────────────────────────────────────────────────────────────
    // Full-height, no page scroll. Sections scroll internally when needed.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CompactHeader(data: data),
          const SizedBox(height: 8),
          _DesktopMetricsRow(
            data: data,
            onAddSpot: onAddSpot,
            onCreatePackage: onCreatePackage,
            onDrivers: onDrivers,
            onBookings: onBookings,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: Quick Actions (compact/natural) + Analytics (fills rest)
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _QuickActions(
                        onAddSpot: onAddSpot,
                        onCreatePackage: onCreatePackage,
                        onDrivers: onDrivers,
                        onBookings: onBookings,
                        onReports: onReports,
                        onAnnouncements: onAnnouncements,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _AnalyticsCard(data: data),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Center: Recent Bookings with internal scroll
                Expanded(
                  flex: 4,
                  child: _CompactRecentBookings(
                    bookings: data.recentBookings,
                    onViewAll: onBookings,
                  ),
                ),
                const SizedBox(width: 8),
                // Right: Profile (natural) + Announcements + Activity Feed
                Expanded(
                  flex: 3,
                  child: _CompactSidePanel(
                    data: data,
                    onAnnouncements: onAnnouncements,
                    onProfile: onProfile,
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

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({required this.data});

  final SubTenantDashboardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A86FF), Color(0xFF0EA5E9)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: SubTenantColors.blue.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Icon(
              Icons.location_city_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'City Tourism Dashboard',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Hello, ${data.profile.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Managing ${data.profile.assignedCity} packages, bookings & drivers.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _CityScopeBadge(profile: data.profile),
        ],
      ),
    );
  }
}

class _CityScopeBadge extends StatelessWidget {
  const _CityScopeBadge({required this.profile});

  final SubTenantProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_user_rounded, color: Colors.white, size: 17),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.assignedCity,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${profile.province} scope',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 10,
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

// ---------------------------------------------------------------------------
// Metric rows
// ---------------------------------------------------------------------------

class _DesktopMetricsRow extends StatelessWidget {
  const _DesktopMetricsRow({
    required this.data,
    required this.onAddSpot,
    required this.onCreatePackage,
    required this.onDrivers,
    required this.onBookings,
  });

  final SubTenantDashboardData data;
  final VoidCallback onAddSpot;
  final VoidCallback onCreatePackage;
  final VoidCallback onDrivers;
  final VoidCallback onBookings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: Row(
        children: [
          Expanded(
            child: _CompactMetricCard(
              icon: Icons.place_rounded,
              label: 'Tourist Spots',
              value: '${data.totalSpots}',
              color: const Color(0xFF2A86FF),
              onTap: onAddSpot,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CompactMetricCard(
              icon: Icons.inventory_2_rounded,
              label: 'Packages',
              value: '${data.totalPackages}',
              color: const Color(0xFF0EA5E9),
              onTap: onCreatePackage,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CompactMetricCard(
              icon: Icons.badge_rounded,
              label: 'Drivers',
              value: '${data.totalDrivers}',
              color: const Color(0xFF16A34A),
              onTap: onDrivers,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CompactMetricCard(
              icon: Icons.pending_actions_rounded,
              label: 'Pending Bookings',
              value: '${data.pendingBookings}',
              subtitle: '${data.activeTours} active tours',
              color: const Color(0xFFF59E0B),
              onTap: onBookings,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMetricsGrid extends StatelessWidget {
  const _MobileMetricsGrid({
    required this.data,
    required this.onAddSpot,
    required this.onCreatePackage,
    required this.onDrivers,
    required this.onBookings,
  });

  final SubTenantDashboardData data;
  final VoidCallback onAddSpot;
  final VoidCallback onCreatePackage;
  final VoidCallback onDrivers;
  final VoidCallback onBookings;

  @override
  Widget build(BuildContext context) {
    return ResponsiveGrid(
      minItemWidth: 170,
      maxColumns: 2,
      mobileAspectRatio: 2.1,
      tabletAspectRatio: 2.2,
      desktopAspectRatio: 2.4,
      children: [
        _CompactMetricCard(
          icon: Icons.place_rounded,
          label: 'Tourist Spots',
          value: '${data.totalSpots}',
          color: const Color(0xFF2A86FF),
          onTap: onAddSpot,
        ),
        _CompactMetricCard(
          icon: Icons.inventory_2_rounded,
          label: 'Packages',
          value: '${data.totalPackages}',
          color: const Color(0xFF0EA5E9),
          onTap: onCreatePackage,
        ),
        _CompactMetricCard(
          icon: Icons.badge_rounded,
          label: 'Drivers',
          value: '${data.totalDrivers}',
          color: const Color(0xFF16A34A),
          onTap: onDrivers,
        ),
        _CompactMetricCard(
          icon: Icons.pending_actions_rounded,
          label: 'Pending',
          value: '${data.pendingBookings}',
          subtitle: '${data.activeTours} active',
          color: const Color(0xFFF59E0B),
          onTap: onBookings,
        ),
      ],
    );
  }
}

class _CompactMetricCard extends StatefulWidget {
  const _CompactMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  State<_CompactMetricCard> createState() => _CompactMetricCardState();
}

class _CompactMetricCardState extends State<_CompactMetricCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor:
          widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _hovered
                    ? widget.color.withValues(alpha: 0.24)
                    : SubTenantColors.line,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      Colors.black.withValues(alpha: _hovered ? 0.07 : 0.032),
                  blurRadius: _hovered ? 18 : 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SubTenantColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SubTenantColors.text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SubTenantColors.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
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

// ---------------------------------------------------------------------------
// Quick Actions
// ---------------------------------------------------------------------------

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
    final isDesktop = Responsive.isDesktop(context);
    return DashboardSectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _CompactSectionTitle(
            title: 'Quick Actions',
            subtitle: 'Common admin tasks',
          ),
          const SizedBox(height: 8),
          // LayoutBuilder derives a stable cell height from the available width
          // so buttons never clip on any desktop resolution.
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = isDesktop ? 3 : 2;
              const spacing = 8.0;
              const targetHeight = 46.0;
              final cellWidth =
                  (constraints.maxWidth - (cols - 1) * spacing) / cols;
              final ar = (cellWidth / targetHeight).clamp(1.4, 5.0);
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                crossAxisSpacing: spacing,
                mainAxisSpacing: 8,
                childAspectRatio: ar,
                children: [
                  _ActionButton(
                    icon: Icons.add_location_alt_rounded,
                    label: 'Add Spot',
                    onTap: onAddSpot,
                  ),
                  _ActionButton(
                    icon: Icons.add_box_rounded,
                    label: 'Create Package',
                    onTap: onCreatePackage,
                  ),
                  _ActionButton(
                    icon: Icons.badge_rounded,
                    label: 'Drivers',
                    onTap: onDrivers,
                  ),
                  _ActionButton(
                    icon: Icons.receipt_long_rounded,
                    label: 'Bookings',
                    onTap: onBookings,
                  ),
                  _ActionButton(
                    icon: Icons.bar_chart_rounded,
                    label: 'Reports',
                    onTap: onReports,
                  ),
                  _ActionButton(
                    icon: Icons.campaign_rounded,
                    label: 'Announcements',
                    onTap: onAnnouncements,
                  ),
                ],
              );
            },
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
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _hovered
                  ? SubTenantColors.blue.withValues(alpha: 0.09)
                  : const Color(0xFFF8FBFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hovered
                    ? SubTenantColors.blue.withValues(alpha: 0.22)
                    : SubTenantColors.line,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: SubTenantColors.blue.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.icon,
                    color: SubTenantColors.blue,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SubTenantColors.text,
                      fontSize: 11.5,
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

// ---------------------------------------------------------------------------
// Recent Bookings
// ---------------------------------------------------------------------------

// Desktop variant — sits inside Expanded, internal ListView scrolls.
class _CompactRecentBookings extends StatelessWidget {
  const _CompactRecentBookings({
    required this.bookings,
    required this.onViewAll,
  });

  final List<SubTenantBooking> bookings;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _CompactSectionTitle(
            title: 'Recent Bookings',
            subtitle: 'Latest package requests',
            trailing: 'View All',
            onTrailingTap: onViewAll,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: bookings.isEmpty
                ? const _SmallEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No bookings yet',
                    message: 'New bookings will appear here.',
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: bookings.take(7).length,
                    separatorBuilder: (_, _) => const SizedBox(height: 5),
                    itemBuilder: (_, i) =>
                        _BookingCompactTile(booking: bookings[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

// Mobile variant — static list, natural height.
class _RecentBookings extends StatelessWidget {
  const _RecentBookings({
    required this.bookings,
    required this.onViewAll,
  });

  final List<SubTenantBooking> bookings;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CompactSectionTitle(
            title: 'Recent Bookings',
            subtitle: 'Latest package requests',
            trailing: 'View All',
            onTrailingTap: onViewAll,
          ),
          const SizedBox(height: 8),
          if (bookings.isEmpty)
            const _SmallEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No bookings yet',
              message: 'New bookings will appear here.',
            )
          else
            ...bookings.take(5).map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: _BookingCompactTile(booking: b),
                  ),
                ),
        ],
      ),
    );
  }
}

class _BookingCompactTile extends StatelessWidget {
  const _BookingCompactTile({required this.booking});

  final SubTenantBooking booking;

  @override
  Widget build(BuildContext context) {
    final date = booking.travelDate == null
        ? 'No date'
        : DateFormat('MMM d').format(booking.travelDate!);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: SubTenantColors.blue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.confirmation_number_rounded,
              color: SubTenantColors.blue,
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${booking.packageTitle}\n',
                    style: const TextStyle(
                      color: SubTenantColors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                  TextSpan(
                    text: '${booking.touristName} • $date',
                    style: const TextStyle(
                      color: SubTenantColors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SubTenantStatusPill(status: booking.status),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Analytics / Operations Snapshot
// ---------------------------------------------------------------------------

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({required this.data});

  final SubTenantDashboardData data;

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final values = [
      data.totalSpots,
      data.totalPackages,
      data.totalDrivers,
      data.pendingBookings,
      data.activeTours,
    ];
    final maxValue = values.fold<int>(1, (m, v) => v > m ? v : m);

    final chart = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _ChartBar(label: 'Spots', value: data.totalSpots, maxValue: maxValue, color: const Color(0xFF2A86FF)),
        _ChartBar(label: 'Packages', value: data.totalPackages, maxValue: maxValue, color: const Color(0xFF0EA5E9)),
        _ChartBar(label: 'Drivers', value: data.totalDrivers, maxValue: maxValue, color: const Color(0xFF16A34A)),
        _ChartBar(label: 'Pending', value: data.pendingBookings, maxValue: maxValue, color: const Color(0xFFF59E0B)),
        _ChartBar(label: 'Active', value: data.activeTours, maxValue: maxValue, color: const Color(0xFF7C3AED)),
      ],
    );

    return DashboardSectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        // max on desktop: Expanded(chart) fills the bounded card height.
        // min on mobile: card wraps the fixed-height SizedBox.
        mainAxisSize: isDesktop ? MainAxisSize.max : MainAxisSize.min,
        children: [
          const _CompactSectionTitle(
            title: 'Operations Snapshot',
            subtitle: 'City workspace volume',
          ),
          const SizedBox(height: 8),
          if (isDesktop)
            Expanded(child: chart)
          else
            SizedBox(height: 120, child: chart),
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
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '$value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SubTenantColors.text,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: (0.12 + (factor * 0.88)).clamp(0.12, 1.0),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color.withValues(alpha: 0.80), color],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SubTenantColors.muted,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Side panels
// ---------------------------------------------------------------------------

// Desktop: Profile at natural height, Announcements + Activity fill the rest.
class _CompactSidePanel extends StatelessWidget {
  const _CompactSidePanel({
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileSummary(data: data, onProfile: onProfile),
        const SizedBox(height: 8),
        Expanded(
          child: _AnnouncementsCard(
            data: data,
            onAnnouncements: onAnnouncements,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _ActivityFeed(bookings: data.recentBookings),
        ),
      ],
    );
  }
}

// Mobile: all sections stacked, each with natural height.
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
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProfileSummary(data: data, onProfile: onProfile),
        const SizedBox(height: 12),
        _AnnouncementsCard(data: data, onAnnouncements: onAnnouncements),
        const SizedBox(height: 12),
        _ActivityFeed(bookings: data.recentBookings),
      ],
    );
  }
}

// Profile summary — always intrinsic height (no Expanded children).
class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.data, required this.onProfile});

  final SubTenantDashboardData data;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _CompactSectionTitle(
            title: 'Profile',
            subtitle: 'City office settings',
          ),
          const SizedBox(height: 8),
          _MiniInfoTile(
            icon: Icons.location_city_rounded,
            title: data.profile.assignedCity,
            subtitle: '${data.profile.province} Tourism Office',
            onTap: onProfile,
          ),
        ],
      ),
    );
  }
}

class _AnnouncementsCard extends StatelessWidget {
  const _AnnouncementsCard({
    required this.data,
    required this.onAnnouncements,
  });

  final SubTenantDashboardData data;
  final VoidCallback onAnnouncements;

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final items = data.announcements.take(4).toList();

    return DashboardSectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: isDesktop ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _CompactSectionTitle(
            title: 'Announcements',
            subtitle: data.announcementsTableAvailable
                ? 'City updates'
                : 'Table unavailable',
            trailing: 'Manage',
            onTrailingTap: onAnnouncements,
          ),
          const SizedBox(height: 8),
          if (isDesktop)
            Expanded(
              child: data.announcements.isEmpty
                  ? const _SmallEmptyState(
                      icon: Icons.campaign_outlined,
                      title: 'No announcements',
                      message: 'Published updates appear here.',
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) => _MiniInfoTile(
                        icon: Icons.campaign_rounded,
                        title: items[i].title,
                        subtitle: items[i].body,
                        trailing: SubTenantStatusPill(status: items[i].status),
                      ),
                    ),
            )
          else if (data.announcements.isEmpty)
            const _SmallEmptyState(
              icon: Icons.campaign_outlined,
              title: 'No announcements',
              message: 'Published updates appear here.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _MiniInfoTile(
                icon: Icons.campaign_rounded,
                title: items[i].title,
                subtitle: items[i].body,
                trailing: SubTenantStatusPill(status: items[i].status),
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
    final isDesktop = Responsive.isDesktop(context);
    final items = bookings.take(4).toList();

    return DashboardSectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: isDesktop ? MainAxisSize.max : MainAxisSize.min,
        children: [
          const _CompactSectionTitle(
            title: 'Activity Feed',
            subtitle: 'Recent local activity',
          ),
          const SizedBox(height: 8),
          if (isDesktop)
            Expanded(
              child: bookings.isEmpty
                  ? const _SmallEmptyState(
                      icon: Icons.timeline_rounded,
                      title: 'Quiet for now',
                      message: 'Booking changes appear here.',
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final b = items[i];
                        final created = b.createdAt == null
                            ? 'Recently'
                            : DateFormat('MMM d, h:mm a').format(b.createdAt!);
                        return _MiniInfoTile(
                          icon: Icons.timeline_rounded,
                          title: b.packageTitle,
                          subtitle: '${b.touristName} • $created',
                          trailing: SubTenantStatusPill(status: b.status),
                        );
                      },
                    ),
            )
          else if (bookings.isEmpty)
            const _SmallEmptyState(
              icon: Icons.timeline_rounded,
              title: 'Quiet for now',
              message: 'Booking changes appear here.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final b = items[i];
                final created = b.createdAt == null
                    ? 'Recently'
                    : DateFormat('MMM d, h:mm a').format(b.createdAt!);
                return _MiniInfoTile(
                  icon: Icons.timeline_rounded,
                  title: b.packageTitle,
                  subtitle: '${b.touristName} • $created',
                  trailing: SubTenantStatusPill(status: b.status),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _CompactSectionTitle extends StatelessWidget {
  const _CompactSectionTitle({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTrailingTap,
  });

  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$title\n',
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: subtitle,
                  style: const TextStyle(
                    color: SubTenantColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null)
          TextButton(
            onPressed: onTrailingTap,
            style: TextButton.styleFrom(
              foregroundColor: SubTenantColors.blue,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              trailing!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniInfoTile extends StatelessWidget {
  const _MiniInfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FBFF),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: SubTenantColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: SubTenantColors.blue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 14, color: SubTenantColors.blue),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$title\n',
                        style: const TextStyle(
                          color: SubTenantColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                      TextSpan(
                        text: subtitle,
                        style: const TextStyle(
                          color: SubTenantColors.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallEmptyState extends StatelessWidget {
  const _SmallEmptyState({
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
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SubTenantColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: SubTenantColors.blue, size: 20),
            const SizedBox(height: 5),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SubTenantColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SubTenantColors.muted,
                fontSize: 10.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
