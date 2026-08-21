import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/province_reports_screen.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/admin_metric_card.dart';
import 'package:touristrike/screens/admin/widgets/admin_page_header.dart';
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

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;
              final profileWidth = (constraints.maxWidth * 0.32).clamp(
                280.0,
                380.0,
              );

              final pageHeader = AdminPageHeader(
                eyebrow: 'City Tenant Profile',
                title: tenant.city,
                subtitle:
                    '${tenant.adminName}  ·  ${tenant.email.isEmpty ? 'No email saved' : tenant.email}',
                icon: Icons.location_city_rounded,
                trailing: _HeroTrailing(tenant: tenant),
              );

              final metricsRow = AdminResponsiveGrid(
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
              );

              void openReports() => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProvinceReportsScreen(),
                    ),
                  );

              final profileCard = _ProfileCard(
                data: data,
                saving: _saving,
                onActivate: () => _setStatus(data, 'active'),
                onDeactivate: () => _setStatus(data, 'inactive'),
                onVerify: () => _verify(data),
                onReports: openReports,
                fullHeight: isWide,
              );

              if (!isWide) {
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
                    children: [
                      pageHeader,
                      const SizedBox(height: 16),
                      metricsRow,
                      const SizedBox(height: 16),
                      profileCard,
                      const SizedBox(height: 16),
                      _RecentPanel(
                        data: data,
                        money: money,
                        narrow: true,
                      ),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    pageHeader,
                    const SizedBox(height: 16),
                    metricsRow,
                    const SizedBox(height: 16),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: profileWidth, child: profileCard),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _RecentPanel(
                              data: data,
                              money: money,
                              narrow: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ─── Hero trailing ────────────────────────────────────────────────────────────

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
    required this.fullHeight,
  });

  final CityTenantDetailsData data;
  final bool saving;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  final VoidCallback onVerify;
  final VoidCallback onReports;
  final bool fullHeight;

  @override
  Widget build(BuildContext context) {
    final tenant = data.tenant;
    final initial = tenant.city.isNotEmpty ? tenant.city[0].toUpperCase() : 'C';
    final joined = tenant.createdAt != null
        ? DateFormat('MMMM yyyy').format(tenant.createdAt!)
        : null;

    final contact = [
      if (tenant.mobile.isNotEmpty) tenant.mobile,
      if (tenant.email.isNotEmpty) tenant.email,
    ].join('  ·  ');

    final isVerified = tenant.verified;
    final isActive = tenant.status.toLowerCase().trim() == 'active';

    final infoContent = _InfoContent(
      data: data,
      joined: joined,
      contact: contact,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ProvincialAdminColors.line),
        boxShadow: [provincialAdminShadow()],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GradientHeader(tenant: tenant, initial: initial),
          if (fullHeight)
            Expanded(child: SingleChildScrollView(child: infoContent))
          else
            infoContent,
          const Divider(
            height: 1,
            thickness: 0.5,
            color: ProvincialAdminColors.line,
          ),
          _ActionSection(
            saving: saving,
            isVerified: isVerified,
            isActive: isActive,
            onVerify: onVerify,
            onActivate: onActivate,
            onDeactivate: onDeactivate,
            onReports: onReports,
          ),
        ],
      ),
    );
  }
}

class _GradientHeader extends StatelessWidget {
  const _GradientHeader({required this.tenant, required this.initial});

  final CityTenant tenant;
  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
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
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.44),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _StatusChip(status: tenant.status),
              ],
            ),
          ),
          if (tenant.verified)
            Positioned(
              top: 10,
              right: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.32)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, color: Colors.white, size: 11),
                    SizedBox(width: 4),
                    Text(
                      'Verified',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isActive = status.toLowerCase() == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF4ADE80) : Colors.white60,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoContent extends StatelessWidget {
  const _InfoContent({
    required this.data,
    required this.joined,
    required this.contact,
  });

  final CityTenantDetailsData data;
  final String? joined;
  final String contact;

  @override
  Widget build(BuildContext context) {
    final tenant = data.tenant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tenant Account',
            style: TextStyle(
              color: ProvincialAdminColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'SubTenant admin profile and contact information.',
            style: TextStyle(
              color: ProvincialAdminColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          _InfoRow(label: 'ADMIN', value: tenant.adminName),
          _InfoRow(
            label: 'CONTACT',
            value: contact.isEmpty ? 'No contact saved' : contact,
          ),
          _InfoRow(
            label: 'ADDRESS',
            value: tenant.address.isEmpty ? 'No address saved' : tenant.address,
          ),
          if (joined != null) _InfoRow(label: 'MEMBER SINCE', value: joined!),
          _InfoRow(
            label: 'FEEDBACK',
            value:
                '${data.feedback.length} review${data.feedback.length == 1 ? '' : 's'}  ·  Avg. ${data.averageRating.toStringAsFixed(1)} ★',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: Responsive.responsiveValue<double>(
                  context,
                  mobile: 88,
                  tablet: 92,
                  desktop: 96,
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: ProvincialAdminColors.lightMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ProvincialAdminColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(
            height: 1,
            thickness: 0.5,
            color: ProvincialAdminColors.line,
          ),
      ],
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.saving,
    required this.isVerified,
    required this.isActive,
    required this.onVerify,
    required this.onActivate,
    required this.onDeactivate,
    required this.onReports,
  });

  final bool saving;
  final bool isVerified;
  final bool isActive;
  final VoidCallback onVerify;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  final VoidCallback onReports;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isVerified) ...[
            FilledButton.icon(
              onPressed: saving ? null : onVerify,
              icon: const Icon(Icons.verified_rounded, size: 17),
              label: const Text('Verify Tenant'),
              style: FilledButton.styleFrom(
                backgroundColor: ProvincialAdminColors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          Row(
            children: [
              if (!isActive) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: saving ? null : onActivate,
                    icon: const Icon(Icons.check_circle_rounded, size: 16),
                    label: const Text('Activate'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ProvincialAdminColors.green,
                      side: BorderSide(
                        color: ProvincialAdminColors.green.withValues(
                          alpha: 0.55,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              Expanded(
                child: OutlinedButton.icon(
                  onPressed: saving ? null : onDeactivate,
                  icon: const Icon(Icons.block_rounded, size: 16),
                  label: const Text('Deactivate'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ProvincialAdminColors.red,
                    side: BorderSide(
                      color: ProvincialAdminColors.red.withValues(alpha: 0.50),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          OutlinedButton.icon(
            onPressed: saving ? null : onReports,
            icon: const Icon(Icons.query_stats_rounded, size: 16),
            label: const Text('Open Reports'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ProvincialAdminColors.muted,
              side: const BorderSide(color: ProvincialAdminColors.line),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),

          if (saving) ...[
            const SizedBox(height: 12),
            const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Recent panel ─────────────────────────────────────────────────────────────

class _RecentPanel extends StatelessWidget {
  const _RecentPanel({
    required this.data,
    required this.money,
    required this.narrow,
  });

  final CityTenantDetailsData data;
  final NumberFormat money;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final packagesCard = _ListCard(
      title: 'Recent Packages',
      subtitle: 'Latest package records for this city.',
      icon: Icons.inventory_2_rounded,
      count: data.packages.length,
      narrow: narrow,
      emptyWidget: const _EmptySection(
        icon: Icons.inventory_2_rounded,
        title: 'No packages yet',
        message: 'This city tenant has not created any packages.',
      ),
      children: data.packages
          .take(narrow ? 5 : 12)
          .map((pkg) => _PackageListItem(package: pkg))
          .toList(),
    );

    final bookingsCard = _ListCard(
      title: 'Recent Bookings',
      subtitle: 'Latest booking records from this tenant.',
      icon: Icons.receipt_long_rounded,
      count: data.bookings.length,
      narrow: narrow,
      emptyWidget: const _EmptySection(
        icon: Icons.receipt_long_rounded,
        title: 'No bookings yet',
        message: 'No booking records found for this city tenant.',
      ),
      children: data.bookings
          .take(narrow ? 5 : 12)
          .map((b) => _BookingListItem(booking: b, money: money))
          .toList(),
    );

    if (narrow) {
      return Column(
        children: [
          packagesCard,
          const SizedBox(height: 16),
          bookingsCard,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: packagesCard),
        const SizedBox(width: 16),
        Expanded(child: bookingsCard),
      ],
    );
  }
}

// ─── List card ────────────────────────────────────────────────────────────────

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.count,
    required this.narrow,
    required this.emptyWidget,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int count;
  final bool narrow;
  final Widget emptyWidget;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: ProvincialAdminColors.line),
      boxShadow: [provincialAdminShadow()],
    );

    if (narrow) {
      return Container(
        decoration: decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ListCardHeader(
                title: title, subtitle: subtitle, icon: icon, count: count),
            const Divider(
                height: 1, thickness: 0.5, color: ProvincialAdminColors.line),
            if (children.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(16), child: emptyWidget)
            else ...[
              ...children,
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
    }

    return Container(
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ListCardHeader(
              title: title, subtitle: subtitle, icon: icon, count: count),
          const Divider(
              height: 1, thickness: 0.5, color: ProvincialAdminColors.line),
          Expanded(
            child: children.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: emptyWidget,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    itemCount: children.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: ProvincialAdminColors.line,
                      indent: 14,
                      endIndent: 14,
                    ),
                    itemBuilder: (_, i) => children[i],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ListCardHeader extends StatelessWidget {
  const _ListCardHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.count,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ProvincialAdminColors.blue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: ProvincialAdminColors.blue, size: 19),
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
                    fontSize: 14.5,
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
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: ProvincialAdminColors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: ProvincialAdminColors.blue.withValues(alpha: 0.14),
                ),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: ProvincialAdminColors.blue,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: _hovered
              ? ProvincialAdminColors.blue.withValues(alpha: 0.04)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.75), color],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.20),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
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
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    priceLabel.isEmpty ? 'No price set' : priceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ProvincialAdminColors.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (pkg.bookingsCount > 0) ...[
                    const SizedBox(height: 4),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: _hovered
              ? ProvincialAdminColors.blue.withValues(alpha: 0.04)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.75), color],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.20),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: Colors.white,
                size: 18,
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
                      color: ProvincialAdminColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${booking.touristName}  ·  ${widget.money.format(booking.totalAmount)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ProvincialAdminColors.muted,
                      fontSize: 11.5,
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

// ─── Stat badge ───────────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  const _StatBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
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
          fontSize: 10,
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
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: ProvincialAdminColors.blue.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: ProvincialAdminColors.blue, size: 24),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ProvincialAdminColors.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontSize: 11.5,
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
    'active' || 'published' || 'completed' || 'verified' =>
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
