import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/province_reports_screen.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/admin_metric_card.dart';
import 'package:touristrike/screens/admin/widgets/admin_page_header.dart';
import 'package:touristrike/screens/admin/widgets/admin_section_card.dart';
import 'package:touristrike/screens/admin/widgets/admin_status_pill.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class CityTenantDetailsScreen extends StatefulWidget {
  const CityTenantDetailsScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  State<CityTenantDetailsScreen> createState() =>
      _CityTenantDetailsScreenState();
}

class _CityTenantDetailsScreenState extends State<CityTenantDetailsScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();
  late Future<CityTenantDetailsData> _future;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchTenantDetails(widget.tenantId);
  }

  void _reload() {
    setState(() => _future = _service.fetchTenantDetails(widget.tenantId));
  }

  Future<void> _setStatus(CityTenantDetailsData data, String status) async {
    setState(() => _saving = true);
    try {
      await _service.updateTenantStatus(data.tenant, status);
      if (!mounted) return;
      showAdminSnack(context, 'Tenant status updated.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Status update needs profiles.status: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _verify(CityTenantDetailsData data) async {
    setState(() => _saving = true);
    try {
      await _service.verifyTenant(data.tenant);
      if (!mounted) return;
      showAdminSnack(context, 'Tenant verified.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Verification needs profiles.verified: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);

    return ProvincialAdminShell(
      current: ProvincialAdminDestination.cityTenants,
      title: 'City Tenant Details',
      subtitle: 'Tenant profile, account status, and tourism performance.',
      child: FutureBuilder<CityTenantDetailsData>(
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
          final tenant = data.tenant;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: AdminPageContainer(
              children: [
                AdminPageHeader(
                  eyebrow: 'City Tenant Profile',
                  title: tenant.city,
                  subtitle:
                      '${tenant.adminName}  ·  ${tenant.email.isEmpty ? 'No email saved' : tenant.email}',
                  icon: Icons.location_city_rounded,
                  trailing: _HeroTrailing(tenant: tenant),
                ),
                const SizedBox(height: 18),
                AdminResponsiveGrid(
                  minItemWidth: 190,
                  maxColumns: 5,
                  desktopAspectRatio: 1.42,
                  children: [
                    AdminMetricCard(
                      icon: Icons.place_rounded,
                      label: 'Tourist Spots',
                      value: '${tenant.spotsCount}',
                    ),
                    AdminMetricCard(
                      icon: Icons.inventory_2_rounded,
                      label: 'Packages',
                      value: '${tenant.packagesCount}',
                      color: ProvincialAdminColors.cyan,
                    ),
                    AdminMetricCard(
                      icon: Icons.badge_rounded,
                      label: 'Drivers',
                      value: '${data.driversCount}',
                      color: ProvincialAdminColors.green,
                    ),
                    AdminMetricCard(
                      icon: Icons.receipt_long_rounded,
                      label: 'Bookings',
                      value: '${tenant.bookingsCount}',
                      color: ProvincialAdminColors.purple,
                    ),
                    AdminMetricCard(
                      icon: Icons.payments_rounded,
                      label: 'Revenue',
                      value: money.format(data.revenue),
                      color: ProvincialAdminColors.green,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1050;
                    final profile = _ProfileCard(
                      data: data,
                      saving: _saving,
                      onActivate: () => _setStatus(data, 'active'),
                      onDeactivate: () => _setStatus(data, 'inactive'),
                      onVerify: () => _verify(data),
                      onReports: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProvinceReportsScreen(),
                          ),
                        );
                      },
                    );
                    final recent = _RecentLists(data: data);
                    if (!wide) {
                      return Column(
                        children: [
                          profile,
                          const SizedBox(height: 16),
                          recent,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 420, child: profile),
                        const SizedBox(width: 18),
                        Expanded(child: recent),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Hero trailing: status pill + verified badge ──────────────────────────────

class _HeroTrailing extends StatelessWidget {
  const _HeroTrailing({required this.tenant});

  final CityTenant tenant;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AdminStatusPill(status: tenant.status),
        if (tenant.verified) ...[
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, color: Colors.white, size: 12),
                SizedBox(width: 5),
                Text(
                  'Verified',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Profile card ─────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.data,
    required this.saving,
    required this.onActivate,
    required this.onDeactivate,
    required this.onVerify,
    required this.onReports,
  });

  final CityTenantDetailsData data;
  final bool saving;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  final VoidCallback onVerify;
  final VoidCallback onReports;

  @override
  Widget build(BuildContext context) {
    final tenant = data.tenant;
    final initial =
        tenant.city.isNotEmpty ? tenant.city[0].toUpperCase() : 'C';
    final joined = tenant.createdAt != null
        ? DateFormat('MMMM yyyy').format(tenant.createdAt!)
        : null;
    final contact = [
      if (tenant.mobile.isNotEmpty) tenant.mobile,
      if (tenant.email.isNotEmpty) tenant.email,
    ].join('  ·  ');

    return AdminSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Gradient header band ──────────────────────────────────────────
          Container(
            height: 110,
            decoration: const BoxDecoration(
              gradient: ProvincialAdminColors.gradient,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.40),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (tenant.verified)
                  Positioned(
                    top: 10,
                    right: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.32),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Info section ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tenant Account',
                  style: TextStyle(
                    color: ProvincialAdminColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'SubTenant admin profile and contact information.',
                  style: TextStyle(
                    color: ProvincialAdminColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                AdminInfoTile(
                  icon: Icons.person_rounded,
                  title: 'Admin',
                  subtitle: tenant.adminName,
                ),
                AdminInfoTile(
                  icon: Icons.phone_rounded,
                  title: 'Contact',
                  subtitle: contact.isEmpty ? 'No contact saved' : contact,
                ),
                AdminInfoTile(
                  icon: Icons.home_rounded,
                  title: 'Office Address',
                  subtitle: tenant.address.isEmpty
                      ? 'No address saved'
                      : tenant.address,
                ),
                if (joined != null)
                  AdminInfoTile(
                    icon: Icons.calendar_today_rounded,
                    title: 'Member Since',
                    subtitle: joined,
                  ),
                AdminInfoTile(
                  icon: Icons.star_rounded,
                  title: 'Feedback',
                  subtitle:
                      '${data.feedback.length} review${data.feedback.length == 1 ? '' : 's'}  ·  Avg. ${data.averageRating.toStringAsFixed(1)} ★',
                ),
              ],
            ),
          ),

          // ── Action buttons ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: saving ? null : onVerify,
                  icon: const Icon(Icons.verified_rounded, size: 18),
                  label: const Text('Verify Tenant'),
                  style: FilledButton.styleFrom(
                    backgroundColor: ProvincialAdminColors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: saving ? null : onActivate,
                        icon: const Icon(Icons.check_circle_rounded, size: 17),
                        label: const Text('Activate'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ProvincialAdminColors.green,
                          side: BorderSide(
                            color: ProvincialAdminColors.green.withValues(
                              alpha: 0.55,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: saving ? null : onDeactivate,
                        icon: const Icon(Icons.block_rounded, size: 17),
                        label: const Text('Deactivate'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ProvincialAdminColors.red,
                          side: BorderSide(
                            color: ProvincialAdminColors.red.withValues(
                              alpha: 0.50,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onReports,
                  icon: const Icon(Icons.query_stats_rounded, size: 17),
                  label: const Text('Open Reports'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ProvincialAdminColors.muted,
                    side: const BorderSide(color: ProvincialAdminColors.line),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                if (saving) ...[
                  const SizedBox(height: 14),
                  const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recent lists ─────────────────────────────────────────────────────────────

class _RecentLists extends StatelessWidget {
  const _RecentLists({required this.data});

  final CityTenantDetailsData data;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);

    return Column(
      children: [
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AdminSectionHeader(
                title: 'Recent Packages',
                subtitle: 'Latest package records for this city.',
              ),
              const SizedBox(height: 14),
              if (data.packages.isEmpty)
                const _EmptySection(
                  icon: Icons.inventory_2_rounded,
                  title: 'No packages yet',
                  message: 'This city tenant has not created any packages.',
                )
              else
                ...data.packages.take(5).map(
                  (pkg) => _PackageListItem(package: pkg),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AdminSectionHeader(
                title: 'Recent Bookings',
                subtitle: 'Latest package bookings from this tenant.',
              ),
              const SizedBox(height: 14),
              if (data.bookings.isEmpty)
                const _EmptySection(
                  icon: Icons.receipt_long_rounded,
                  title: 'No bookings yet',
                  message: 'No booking records found for this city tenant.',
                )
              else
                ...data.bookings.take(5).map(
                  (booking) => _BookingListItem(
                    booking: booking,
                    money: money,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Package list item ────────────────────────────────────────────────────────

class _PackageListItem extends StatefulWidget {
  const _PackageListItem({required this.package});

  final ProvincePackage package;

  @override
  State<_PackageListItem> createState() => _PackageListItemState();
}

class _PackageListItemState extends State<_PackageListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final pkg = widget.package;
    final color = _statusToColor(pkg.status);
    final priceLabel = [
      if (pkg.priceText.isNotEmpty) pkg.priceText,
      if (pkg.durationText.isNotEmpty) pkg.durationText,
    ].join('  ·  ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _hovered
              ? ProvincialAdminColors.blue.withValues(alpha: 0.04)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.75), color],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pkg.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ProvincialAdminColors.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    priceLabel.isEmpty ? 'No price set' : priceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ProvincialAdminColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (pkg.bookingsCount > 0) ...[
                    const SizedBox(height: 5),
                    _StatBadge(
                      '${pkg.bookingsCount} booking${pkg.bookingsCount == 1 ? '' : 's'}',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            AdminStatusPill(status: pkg.status),
          ],
        ),
      ),
    );
  }
}

// ─── Booking list item ────────────────────────────────────────────────────────

class _BookingListItem extends StatefulWidget {
  const _BookingListItem({
    required this.booking,
    required this.money,
  });

  final ProvinceBooking booking;
  final NumberFormat money;

  @override
  State<_BookingListItem> createState() => _BookingListItemState();
}

class _BookingListItemState extends State<_BookingListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final color = _statusToColor(booking.status);
    final dateLabel = booking.travelDate != null
        ? DateFormat('MMM d, y').format(booking.travelDate!)
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _hovered
              ? ProvincialAdminColors.blue.withValues(alpha: 0.04)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.75), color],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.packageTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ProvincialAdminColors.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${booking.touristName}  ·  ${widget.money.format(booking.totalAmount)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ProvincialAdminColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (dateLabel != null) ...[
                    const SizedBox(height: 4),
                    _StatBadge(dateLabel),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            AdminStatusPill(status: booking.status),
          ],
        ),
      ),
    );
  }
}

// ─── Stat badge chip ──────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  const _StatBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ProvincialAdminColors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ProvincialAdminColors.blue.withValues(alpha: 0.14),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: ProvincialAdminColors.blue,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ─── Empty section ────────────────────────────────────────────────────────────

class _EmptySection extends StatelessWidget {
  const _EmptySection({
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
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: ProvincialAdminColors.blue.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: ProvincialAdminColors.blue, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ProvincialAdminColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Color _statusToColor(String status) {
  return switch (status.toLowerCase().trim()) {
    'active' ||
    'published' ||
    'completed' ||
    'verified' =>
      ProvincialAdminColors.green,
    'inactive' ||
    'deactivated' ||
    'cancelled' ||
    'rejected' ||
    'hidden' =>
      ProvincialAdminColors.red,
    'pending' || 'under_review' || 'review' => ProvincialAdminColors.amber,
    'draft' => ProvincialAdminColors.lightMuted,
    _ => ProvincialAdminColors.blue,
  };
}
