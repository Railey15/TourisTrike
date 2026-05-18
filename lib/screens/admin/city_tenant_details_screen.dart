import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
                      '${tenant.adminName} - ${tenant.email.isEmpty ? 'No email saved' : tenant.email}',
                  icon: Icons.location_city_rounded,
                  trailing: AdminStatusPill(status: tenant.status),
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
    return AdminSectionCard(
      child: Column(
        children: [
          const AdminSectionHeader(
            title: 'Tenant Account',
            subtitle: 'SubTenant admin profile and contact information.',
          ),
          const SizedBox(height: 14),
          AdminInfoTile(
            icon: Icons.person_rounded,
            title: 'Admin',
            subtitle: tenant.adminName,
          ),
          AdminInfoTile(
            icon: Icons.phone_rounded,
            title: 'Contact',
            subtitle: [
              if (tenant.mobile.isNotEmpty) tenant.mobile,
              if (tenant.email.isNotEmpty) tenant.email,
            ].join(' / ').isEmpty
                ? 'No contact saved'
                : [
                    if (tenant.mobile.isNotEmpty) tenant.mobile,
                    if (tenant.email.isNotEmpty) tenant.email,
                  ].join(' / '),
          ),
          AdminInfoTile(
            icon: Icons.home_rounded,
            title: 'Office Address',
            subtitle: tenant.address.isEmpty ? 'No address saved' : tenant.address,
          ),
          AdminInfoTile(
            icon: Icons.star_rounded,
            title: 'Feedback Summary',
            subtitle:
                '${data.feedback.length} reviews - average ${data.averageRating.toStringAsFixed(1)}',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: saving ? null : onActivate,
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('Activate'),
              ),
              OutlinedButton.icon(
                onPressed: saving ? null : onDeactivate,
                icon: const Icon(Icons.block_rounded),
                label: const Text('Deactivate'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ProvincialAdminColors.red,
                ),
              ),
              FilledButton.icon(
                onPressed: saving ? null : onVerify,
                icon: const Icon(Icons.verified_rounded),
                label: const Text('Verify'),
              ),
              TextButton.icon(
                onPressed: onReports,
                icon: const Icon(Icons.query_stats_rounded),
                label: const Text('Open Reports'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentLists extends StatelessWidget {
  const _RecentLists({required this.data});

  final CityTenantDetailsData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AdminSectionCard(
          child: Column(
            children: [
              const AdminSectionHeader(
                title: 'Recent Packages',
                subtitle: 'Latest package records for this city.',
              ),
              const SizedBox(height: 12),
              if (data.packages.isEmpty)
                const _InlineEmpty(message: 'No packages yet.')
              else
                ...data.packages.take(5).map(
                      (package) => AdminInfoTile(
                        icon: Icons.inventory_2_rounded,
                        title: package.title,
                        subtitle:
                            '${package.priceText.isEmpty ? 'No price text' : package.priceText} - ${package.bookingsCount} bookings',
                        trailing: AdminStatusPill(status: package.status),
                      ),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        AdminSectionCard(
          child: Column(
            children: [
              const AdminSectionHeader(
                title: 'Recent Bookings',
                subtitle: 'Latest package bookings from this tenant.',
              ),
              const SizedBox(height: 12),
              if (data.bookings.isEmpty)
                const _InlineEmpty(message: 'No recent bookings yet.')
              else
                ...data.bookings.take(5).map(
                      (booking) => AdminInfoTile(
                        icon: Icons.receipt_long_rounded,
                        title: booking.packageTitle,
                        subtitle:
                            '${booking.touristName} - ${NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0).format(booking.totalAmount)}',
                        trailing: AdminStatusPill(status: booking.status),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: ProvincialAdminColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
