import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/city_tenant_details_screen.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/admin_empty_state.dart';
import 'package:touristrike/screens/admin/widgets/admin_section_card.dart';
import 'package:touristrike/screens/admin/widgets/admin_status_pill.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class CityTenantsScreen extends StatefulWidget {
  const CityTenantsScreen({super.key});

  @override
  State<CityTenantsScreen> createState() => _CityTenantsScreenState();
}

class _CityTenantsScreenState extends State<CityTenantsScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();
  final TextEditingController _searchCtrl = TextEditingController();

  late Future<_CityTenantWorkbenchData> _future;
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _future = _loadData();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = _loadData());
  }

  Future<_CityTenantWorkbenchData> _loadData() async {
    final results = await Future.wait<dynamic>([
      _service.fetchCityTenants(),
      _service.fetchRegistrations(),
    ]);

    return _CityTenantWorkbenchData(
      tenants: results[0] as List<CityTenant>,
      registrations: results[1] as TableResult<CityRegistration>,
    );
  }

  List<CityTenant> _filtered(List<CityTenant> tenants) {
    final query = _searchCtrl.text.trim().toLowerCase();

    return tenants.where((tenant) {
      final status = tenant.status.toLowerCase().trim();

      final matchesStatus = _status == 'all' ||
          (_status == 'active' &&
              ['active', 'approved', 'verified'].contains(status)) ||
          (_status == 'inactive' &&
              ['inactive', 'disabled', 'deactivated', 'suspended']
                  .contains(status)) ||
          (_status == 'pending' && status == 'pending') ||
          (_status == 'verified' && tenant.verified);

      if (!matchesStatus) return false;

      if (query.isEmpty) return true;

      final searchable = [
        tenant.city,
        tenant.province,
        tenant.adminName,
        tenant.email,
        tenant.mobile,
        tenant.address,
        tenant.status,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList(growable: false);
  }

  int _countByStatus(List<CityTenant> tenants, String statusFilter) {
    if (statusFilter == 'all') return tenants.length;

    return tenants.where((tenant) {
      final status = tenant.status.toLowerCase().trim();

      if (statusFilter == 'active') {
        return ['active', 'approved', 'verified'].contains(status);
      }

      if (statusFilter == 'inactive') {
        return ['inactive', 'disabled', 'deactivated', 'suspended']
            .contains(status);
      }

      if (statusFilter == 'pending') return status == 'pending';
      if (statusFilter == 'verified') return tenant.verified;

      return false;
    }).length;
  }

  List<CityRegistration> _filteredPendingRegistrations(
    List<CityRegistration> registrations,
  ) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return registrations.where((r) {
      if (r.status.toLowerCase().trim() != 'pending') return false;
      if (query.isEmpty) return true;
      return [
        r.city,
        r.officeName,
        r.contactPerson,
        r.contactNumber,
        r.email,
        r.address,
      ].join(' ').toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<void> _setStatus(CityTenant tenant, String status) async {
    try {
      await _service.updateTenantStatus(tenant, status);
      if (!mounted) return;
      showAdminSnack(context, 'City tenant updated.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Failed to update tenant: $e');
    }
  }

  Future<void> _editCity(CityTenant tenant) async {
    final controller = TextEditingController(text: tenant.city);

    final city = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Edit Assigned City',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'City / Municipality',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (city == null || city.isEmpty || city == tenant.city) return;

    try {
      await _service.updateTenantCity(tenant, city);
      if (!mounted) return;
      showAdminSnack(context, 'Assigned city updated.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Failed to update city: $e');
    }
  }

  void _openDetails(CityTenant tenant) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CityTenantDetailsScreen(tenantId: tenant.id),
      ),
    ).then((_) => _reload());
  }

  Future<void> _approveRegistration(CityRegistration registration) async {
    try {
      await _service.reviewRegistration(registration, 'approved');
      if (!mounted) return;
      showAdminSnack(context, 'Registration approved.', error: false);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Failed to approve registration: $e');
    }
  }

  Future<void> _rejectRegistration(CityRegistration registration) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Reject Registration',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: 'Rejection reason (optional)',
            alignLabelWithHint: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ProvincialAdminColors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;

    try {
      await _service.reviewRegistration(
        registration,
        'rejected',
        rejectionReason: reason,
      );
      if (!mounted) return;
      showAdminSnack(context, 'Registration rejected.', error: false);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Failed to reject registration: $e');
    }
  }

  void _viewRegistration(CityRegistration registration) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RegistrationDetailsSheet(registration: registration),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return ProvincialAdminShell(
      current: ProvincialAdminDestination.cityTenants,
      title: 'City Tenants',
      subtitle:
          'Manage city tourism accounts and review registration requests.',
      child: FutureBuilder<_CityTenantWorkbenchData>(
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
          final allTenants = data.tenants;
          final tenants = _filtered(allTenants);
          final registrationsResult = data.registrations;
          final allRegistrations = registrationsResult.items;

          final pendingRegCount = registrationsResult.available
              ? allRegistrations
                    .where((r) => r.status.toLowerCase().trim() == 'pending')
                    .length
              : 0;

          final counts = {
            'all': _countByStatus(allTenants, 'all'),
            'active': _countByStatus(allTenants, 'active'),
            'inactive': _countByStatus(allTenants, 'inactive'),
            'pending':
                _countByStatus(allTenants, 'pending') + pendingRegCount,
            'verified': _countByStatus(allTenants, 'verified'),
          };

          final pendingRegistrations =
              (_status == 'pending' && registrationsResult.available)
                  ? _filteredPendingRegistrations(allRegistrations)
                  : <CityRegistration>[];

          final showingPendingTab = _status == 'pending';

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    mobile ? 14 : 26,
                    mobile ? 14 : 18,
                    mobile ? 14 : 26,
                    28,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TenantsHero(
                        total: counts['all'] ?? 0,
                        active: counts['active'] ?? 0,
                        pending: counts['pending'] ?? 0,
                        verified: counts['verified'] ?? 0,
                      ),
                      const SizedBox(height: 16),
                      _TenantToolbar(
                        controller: _searchCtrl,
                        status: _status,
                        counts: counts,
                        onStatusChanged: (value) {
                          setState(() => _status = value);
                        },
                      ),
                      const SizedBox(height: 16),
                      if (!showingPendingTab) ...[
                        const _SectionHeader(
                          title: 'Tenant Accounts',
                          subtitle:
                              'Approved and active city tourism admin accounts.',
                        ),
                        const SizedBox(height: 10),
                        if (tenants.isEmpty)
                          const AdminEmptyState(
                            icon: Icons.location_city_outlined,
                            title: 'No city tenants found',
                            message:
                                'Approved subtenant accounts will appear here.',
                          )
                        else if (mobile)
                          ...tenants.map(
                            (tenant) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _TenantCard(
                                tenant: tenant,
                                onTap: () => _openDetails(tenant),
                                onEditCity: () => _editCity(tenant),
                                onActivate: () => _setStatus(tenant, 'active'),
                                onDeactivate: () =>
                                    _setStatus(tenant, 'inactive'),
                              ),
                            ),
                          )
                        else
                          _TenantGrid(
                            tenants: tenants,
                            onOpen: _openDetails,
                            onEditCity: _editCity,
                            onStatus: _setStatus,
                          ),
                      ],
                      if (showingPendingTab) ...[
                        const _SectionHeader(
                          title: 'Pending Registrations',
                          subtitle:
                              'New city tourism office applications awaiting your review.',
                        ),
                        const SizedBox(height: 10),
                        if (!registrationsResult.available)
                          const AdminEmptyState(
                            icon: Icons.info_outline_rounded,
                            title: 'Registrations table unavailable',
                            message:
                                'Create or connect the registrations table to review city applications.',
                          )
                        else if (pendingRegistrations.isEmpty)
                          const AdminEmptyState(
                            icon: Icons.how_to_reg_outlined,
                            title: 'No pending registrations',
                            message:
                                'All registration requests have been processed.',
                          )
                        else if (mobile)
                          ...pendingRegistrations.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _RegistrationCard(
                                registration: r,
                                onView: () => _viewRegistration(r),
                                onApprove: () => _approveRegistration(r),
                                onReject: () => _rejectRegistration(r),
                              ),
                            ),
                          )
                        else
                          _RegistrationsTable(
                            registrations: pendingRegistrations,
                            onView: _viewRegistration,
                            onApprove: _approveRegistration,
                            onReject: _rejectRegistration,
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CityTenantWorkbenchData {
  const _CityTenantWorkbenchData({
    required this.tenants,
    required this.registrations,
  });

  final List<CityTenant> tenants;
  final TableResult<CityRegistration> registrations;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: ProvincialAdminColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: ProvincialAdminColors.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TenantsHero extends StatelessWidget {
  const _TenantsHero({
    required this.total,
    required this.active,
    required this.pending,
    required this.verified,
  });

  final int total;
  final int active;
  final int pending;
  final int verified;

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(desktop ? 22 : 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4AA3FF), Color(0xFF1D63E9)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D63E9).withValues(alpha: .16),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: desktop
          ? Row(
              children: [
                _HeroIcon(),
                const SizedBox(width: 16),
                const Expanded(child: _HeroText()),
                const SizedBox(width: 16),
                _HeroStats(
                  total: total,
                  active: active,
                  pending: pending,
                  verified: verified,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _HeroIcon(),
                    const SizedBox(width: 12),
                    const Expanded(child: _HeroText()),
                  ],
                ),
                const SizedBox(height: 16),
                _HeroStats(
                  total: total,
                  active: active,
                  pending: pending,
                  verified: verified,
                ),
              ],
            ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
      ),
      child: const Icon(
        Icons.location_city_rounded,
        color: Colors.white,
        size: 30,
      ),
    );
  }
}

class _HeroText extends StatelessWidget {
  const _HeroText();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Provincial Tenant Management',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .86),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'City Tourism Offices',
          style: TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Monitor LGU tenant accounts, verify assignments, and manage city-level tourism access.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .90),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _HeroStats extends StatelessWidget {
  const _HeroStats({
    required this.total,
    required this.active,
    required this.pending,
    required this.verified,
  });

  final int total;
  final int active;
  final int pending;
  final int verified;

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    final items = [
      _HeroStatData('Total', total, Icons.domain_rounded),
      _HeroStatData('Active', active, Icons.verified_rounded),
      _HeroStatData('Pending', pending, Icons.pending_actions_rounded),
      _HeroStatData('Verified', verified, Icons.fact_check_rounded),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) {
        return Container(
          width: desktop ? 105 : 135,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .22)),
          ),
          child: Row(
            children: [
              Icon(item.icon, color: Colors.white, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${item.value}\n',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      TextSpan(
                        text: item.label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .86),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _HeroStatData {
  const _HeroStatData(this.label, this.value, this.icon);

  final String label;
  final int value;
  final IconData icon;
}

class _TenantToolbar extends StatelessWidget {
  const _TenantToolbar({
    required this.controller,
    required this.status,
    required this.counts,
    required this.onStatusChanged,
  });

  final TextEditingController controller;
  final String status;
  final Map<String, int> counts;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    final searchField = SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Search city, admin, email, contact...',
          hintStyle: const TextStyle(
            color: ProvincialAdminColors.lightMuted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: ProvincialAdminColors.lightMuted,
          ),
          filled: true,
          fillColor: const Color(0xFFF8FBFF),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(
              color: ProvincialAdminColors.line,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(
              color: ProvincialAdminColors.line,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(
              color: ProvincialAdminColors.blue,
              width: 1.3,
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ProvincialAdminColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .025),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Flex(
        direction: desktop ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment:
            desktop ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
        children: [
          if (desktop) Expanded(child: searchField) else searchField,
          SizedBox(width: desktop ? 14 : 0, height: desktop ? 0 : 12),
          _FilterChips(
            selected: status,
            counts: counts,
            onSelected: onStatusChanged,
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final String selected;
  final Map<String, int> counts;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const filters = [
      ('all', 'All'),
      ('active', 'Active'),
      ('inactive', 'Inactive'),
      ('pending', 'Pending'),
      ('verified', 'Verified'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((item) {
          final key = item.$1;
          final label = item.$2;
          final active = selected == key;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onSelected(key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: active ? ProvincialAdminColors.blue : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active
                        ? ProvincialAdminColors.blue
                        : ProvincialAdminColors.line,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color:
                            active ? Colors.white : ProvincialAdminColors.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white.withValues(alpha: .22)
                            : const Color(0xFFF1F6FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${counts[key] ?? 0}',
                        style: TextStyle(
                          color: active
                              ? Colors.white
                              : ProvincialAdminColors.blue,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TenantGrid extends StatelessWidget {
  const _TenantGrid({
    required this.tenants,
    required this.onOpen,
    required this.onEditCity,
    required this.onStatus,
  });

  final List<CityTenant> tenants;
  final ValueChanged<CityTenant> onOpen;
  final ValueChanged<CityTenant> onEditCity;
  final void Function(CityTenant tenant, String status) onStatus;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1250 ? 3 : 2;
        final aspectRatio = columns == 3 ? 2.2 : 2.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tenants.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) {
            final tenant = tenants[index];

            return _TenantCard(
              tenant: tenant,
              onTap: () => onOpen(tenant),
              onEditCity: () => onEditCity(tenant),
              onActivate: () => onStatus(tenant, 'active'),
              onDeactivate: () => onStatus(tenant, 'inactive'),
            );
          },
        );
      },
    );
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({
    required this.tenant,
    required this.onTap,
    required this.onEditCity,
    required this.onActivate,
    required this.onDeactivate,
  });

  final CityTenant tenant;
  final VoidCallback onTap;
  final VoidCallback onEditCity;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final active = ['active', 'approved', 'verified']
        .contains(tenant.status.toLowerCase().trim());

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: ProvincialAdminColors.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .025),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: active
                          ? const LinearGradient(
                              colors: [Color(0xFF4AA3FF), Color(0xFF1D63E9)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: active ? null : const Color(0xFFEAF4FF),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.location_city_rounded,
                      color: active ? Colors.white : ProvincialAdminColors.blue,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tenant.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ProvincialAdminColors.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          tenant.adminName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ProvincialAdminColors.muted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AdminStatusPill(status: tenant.status),
                  
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: ProvincialAdminColors.line),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _TenantInfo(
                      icon: Icons.email_rounded,
                      label: 'Email',
                      value: tenant.email.isEmpty ? 'No email' : tenant.email,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TenantInfo(
                      icon: Icons.phone_rounded,
                      label: 'Contact',
                      value:
                          tenant.mobile.isEmpty ? 'No contact' : tenant.mobile,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _TenantMetric(
                      label: 'Spots',
                      value: tenant.spotsCount,
                      icon: Icons.place_rounded,
                      color: ProvincialAdminColors.cyan,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TenantMetric(
                      label: 'Packages',
                      value: tenant.packagesCount,
                      icon: Icons.inventory_2_rounded,
                      color: ProvincialAdminColors.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TenantMetric(
                      label: 'Bookings',
                      value: tenant.bookingsCount,
                      icon: Icons.receipt_long_rounded,
                      color: ProvincialAdminColors.purple,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _RegistrationsTable extends StatelessWidget {
  const _RegistrationsTable({
    required this.registrations,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  final List<CityRegistration> registrations;
  final ValueChanged<CityRegistration> onView;
  final ValueChanged<CityRegistration> onApprove;
  final ValueChanged<CityRegistration> onReject;

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            const _RegistrationTableHeader(),
            const Divider(height: 1, color: ProvincialAdminColors.line),
            ...registrations.asMap().entries.map((entry) {
              final index = entry.key;
              final registration = entry.value;
              return Column(
                children: [
                  _RegistrationTableRow(
                    registration: registration,
                    shaded: index.isOdd,
                    onView: () => onView(registration),
                    onApprove: () => onApprove(registration),
                    onReject: () => onReject(registration),
                  ),
                  if (index < registrations.length - 1)
                    const Divider(
                      height: 1,
                      color: ProvincialAdminColors.line,
                      indent: 16,
                      endIndent: 16,
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _RegistrationTableHeader extends StatelessWidget {
  const _RegistrationTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ProvincialAdminColors.backgroundAlt,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: const Row(
        children: [
          Expanded(flex: 3, child: _HeadCell('City')),
          Expanded(flex: 4, child: _HeadCell('Office')),
          Expanded(flex: 4, child: _HeadCell('Contact')),
          Expanded(flex: 5, child: _HeadCell('Email')),
          Expanded(flex: 3, child: _HeadCell('Submitted')),
          SizedBox(width: 100, child: _HeadCell('Status')),
          SizedBox(width: 132, child: _HeadCell('Actions')),
        ],
      ),
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: ProvincialAdminColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _RegistrationTableRow extends StatelessWidget {
  const _RegistrationTableRow({
    required this.registration,
    required this.shaded,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  final CityRegistration registration;
  final bool shaded;
  final VoidCallback onView;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final pending = registration.status.toLowerCase() == 'pending';
    final submitted = registration.submittedAt == null
        ? '-'
        : DateFormat('MMM d, yyyy').format(registration.submittedAt!);

    return InkWell(
      onTap: onView,
      child: Container(
        color: shaded
            ? ProvincialAdminColors.background.withValues(alpha: .6)
            : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                registration.city,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ProvincialAdminColors.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                registration.officeName.isEmpty
                    ? 'Tourism Office'
                    : registration.officeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ProvincialAdminColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                registration.contactPerson.isEmpty
                    ? 'No contact person'
                    : registration.contactPerson,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ProvincialAdminColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Text(
                registration.email.isEmpty ? 'No email' : registration.email,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ProvincialAdminColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                submitted,
                style: const TextStyle(
                  color: ProvincialAdminColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
            SizedBox(
              width: 100,
              child: AdminStatusPill(status: registration.status),
            ),
            SizedBox(
              width: 132,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IconAction(
                    icon: Icons.visibility_rounded,
                    tooltip: 'View details',
                    color: ProvincialAdminColors.blue,
                    onPressed: onView,
                  ),
                  if (pending) ...[
                    const SizedBox(width: 4),
                    _IconAction(
                      icon: Icons.check_circle_rounded,
                      tooltip: 'Approve',
                      color: ProvincialAdminColors.green,
                      onPressed: onApprove,
                    ),
                    const SizedBox(width: 4),
                    _IconAction(
                      icon: Icons.cancel_rounded,
                      tooltip: 'Reject',
                      color: ProvincialAdminColors.red,
                      onPressed: onReject,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
      ),
    );
  }
}

class _RegistrationCard extends StatelessWidget {
  const _RegistrationCard({
    required this.registration,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  final CityRegistration registration;
  final VoidCallback onView;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final pending = registration.status.toLowerCase() == 'pending';
    final submitted = registration.submittedAt == null
        ? '-'
        : DateFormat('MMM d, yyyy').format(registration.submittedAt!);

    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      registration.city,
                      style: const TextStyle(
                        color: ProvincialAdminColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      registration.officeName.isEmpty
                          ? 'Tourism Office'
                          : registration.officeName,
                      style: const TextStyle(
                        color: ProvincialAdminColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AdminStatusPill(status: registration.status),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: ProvincialAdminColors.line, height: 1),
          const SizedBox(height: 12),
          _CardInfoRow(
            icon: Icons.person_rounded,
            text: registration.contactPerson.isEmpty
                ? 'No contact person'
                : registration.contactPerson,
          ),
          const SizedBox(height: 6),
          _CardInfoRow(
            icon: Icons.email_rounded,
            text: registration.email.isEmpty ? 'No email' : registration.email,
          ),
          const SizedBox(height: 6),
          _CardInfoRow(
            icon: Icons.calendar_today_rounded,
            text: 'Submitted $submitted',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onView,
                icon: const Icon(Icons.visibility_rounded, size: 16),
                label: const Text('View'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ProvincialAdminColors.blue,
                  side: const BorderSide(color: ProvincialAdminColors.blue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (pending) ...[
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: ProvincialAdminColors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Reject'),
                  style: FilledButton.styleFrom(
                    backgroundColor: ProvincialAdminColors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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

class _CardInfoRow extends StatelessWidget {
  const _CardInfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: ProvincialAdminColors.lightMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _RegistrationDetailsSheet extends StatelessWidget {
  const _RegistrationDetailsSheet({required this.registration});

  final CityRegistration registration;

  @override
  Widget build(BuildContext context) {
    final submitted = registration.submittedAt == null
        ? '-'
        : DateFormat('MMM d, yyyy - h:mm a').format(registration.submittedAt!);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: ProvincialAdminColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ProvincialAdminColors.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        registration.city,
                        style: const TextStyle(
                          color: ProvincialAdminColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        registration.officeName.isEmpty
                            ? 'Tourism Office'
                            : registration.officeName,
                        style: const TextStyle(
                          color: ProvincialAdminColors.muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                AdminStatusPill(status: registration.status),
              ],
            ),
            const SizedBox(height: 18),
            AdminSectionCard(
              child: Column(
                children: [
                  _DetailTile(
                    icon: Icons.person_rounded,
                    label: 'Contact Person',
                    value: registration.contactPerson.isEmpty
                        ? 'No contact person'
                        : registration.contactPerson,
                  ),
                  _DetailTile(
                    icon: Icons.phone_rounded,
                    label: 'Contact Number',
                    value: registration.contactNumber.isEmpty
                        ? 'No contact number'
                        : registration.contactNumber,
                  ),
                  _DetailTile(
                    icon: Icons.email_rounded,
                    label: 'Email',
                    value: registration.email.isEmpty
                        ? 'No email'
                        : registration.email,
                  ),
                  _DetailTile(
                    icon: Icons.home_rounded,
                    label: 'Office Address',
                    value: registration.address.isEmpty
                        ? 'No address submitted'
                        : registration.address,
                  ),
                  _DetailTile(
                    icon: Icons.calendar_today_rounded,
                    label: 'Submitted',
                    value: submitted,
                    isLast: registration.rejectionReason.isEmpty,
                  ),
                  if (registration.rejectionReason.isNotEmpty)
                    _DetailTile(
                      icon: Icons.info_outline_rounded,
                      label: 'Rejection Reason',
                      value: registration.rejectionReason,
                      valueColor: ProvincialAdminColors.red,
                      isLast: true,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: ProvincialAdminColors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: ProvincialAdminColors.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        color: valueColor ?? ProvincialAdminColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1, color: ProvincialAdminColors.line),
      ],
    );
  }
}

class _TenantInfo extends StatelessWidget {
  const _TenantInfo({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: ProvincialAdminColors.lightMuted, size: 15),
        const SizedBox(width: 7),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label\n',
                  style: const TextStyle(
                    color: ProvincialAdminColors.lightMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: ProvincialAdminColors.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    height: 1.5,
                  ),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _TenantMetric extends StatelessWidget {
  const _TenantMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .10)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$value\n',
                    style: TextStyle(
                      color: color,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  TextSpan(
                    text: label,
                    style: const TextStyle(
                      color: ProvincialAdminColors.muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
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
