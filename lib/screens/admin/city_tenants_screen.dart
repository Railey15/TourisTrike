import 'package:flutter/material.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/city_tenant_details_screen.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/admin_empty_state.dart';
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

  late Future<List<CityTenant>> _future;
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _future = _service.fetchCityTenants();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = _service.fetchCityTenants());
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

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return ProvincialAdminShell(
      current: ProvincialAdminDestination.cityTenants,
      title: 'City Tenants',
      subtitle: 'Manage all city and municipality tourism tenant accounts.',
      child: FutureBuilder<List<CityTenant>>(
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

          final allTenants = snapshot.data ?? const <CityTenant>[];
          final tenants = _filtered(allTenants);

          final counts = {
            'all': _countByStatus(allTenants, 'all'),
            'active': _countByStatus(allTenants, 'active'),
            'inactive': _countByStatus(allTenants, 'inactive'),
            'pending': _countByStatus(allTenants, 'pending'),
            'verified': _countByStatus(allTenants, 'verified'),
          };

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
                      if (tenants.isEmpty)
                        const AdminEmptyState(
                          icon: Icons.location_city_outlined,
                          title: 'No city tenants found',
                          message:
                              'Subtenant accounts with profiles.role = subtenant will appear here.',
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
          Expanded(
            flex: desktop ? 1 : 0,
            child: SizedBox(
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
            ),
          ),
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

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tenants.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 2.15,
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
                  PopupMenuButton<String>(
                    tooltip: 'Tenant actions',
                    onSelected: (value) {
                      switch (value) {
                        case 'open':
                          onTap();
                          break;
                        case 'edit_city':
                          onEditCity();
                          break;
                        case 'active':
                          onActivate();
                          break;
                        case 'inactive':
                          onDeactivate();
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'open', child: Text('View Details')),
                      PopupMenuItem(
                        value: 'edit_city',
                        child: Text('Edit Assigned City'),
                      ),
                      PopupMenuItem(value: 'active', child: Text('Activate')),
                      PopupMenuItem(
                        value: 'inactive',
                        child: Text('Deactivate'),
                      ),
                    ],
                  ),
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
                    height: 1.1,
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