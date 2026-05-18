import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/admin_empty_state.dart';
import 'package:touristrike/screens/admin/widgets/admin_status_pill.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class ProvincePackagesScreen extends StatefulWidget {
  const ProvincePackagesScreen({super.key});

  @override
  State<ProvincePackagesScreen> createState() => _ProvincePackagesScreenState();
}

class _ProvincePackagesScreenState extends State<ProvincePackagesScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();
  final TextEditingController _searchCtrl = TextEditingController();

  late Future<List<ProvincePackage>> _future;

  String _cityFilter = 'all';
  String _statusFilter = 'all';
  String _visibilityFilter = 'all';

  @override
  void initState() {
    super.initState();
    _future = _service.fetchProvincePackages();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = _service.fetchProvincePackages());
  }

  List<ProvincePackage> _filtered(List<ProvincePackage> packages) {
    final query = _searchCtrl.text.trim().toLowerCase();

    return packages.where((package) {
      final city = package.city.trim();
      final status = package.status.toLowerCase().trim();
      final visibility = package.visibilityStatus.toLowerCase().trim();

      final matchesCity = _cityFilter == 'all' || city == _cityFilter;
      final matchesStatus = _statusFilter == 'all' || status == _statusFilter;
      final matchesVisibility =
          _visibilityFilter == 'all' || visibility == _visibilityFilter;

      if (!matchesCity || !matchesStatus || !matchesVisibility) return false;

      if (query.isEmpty) return true;

      final searchable = [
        package.title,
        package.subtitle,
        package.description,
        package.city,
        package.status,
        package.visibilityStatus,
        package.priceText,
        package.durationText,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList(growable: false);
  }

  int _countByStatus(List<ProvincePackage> packages, String status) {
    if (status == 'all') return packages.length;
    return packages
        .where((item) => item.status.toLowerCase().trim() == status)
        .length;
  }

  int _countByVisibility(List<ProvincePackage> packages, String visibility) {
    if (visibility == 'all') return packages.length;
    return packages
        .where((item) => item.visibilityStatus.toLowerCase().trim() == visibility)
        .length;
  }

  Future<void> _updateStatus(ProvincePackage package, String status) async {
    try {
      await _service.updatePackageStatus(package, status);
      if (!mounted) return;
      showAdminSnack(context, 'Package status updated.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Failed to update package: $e');
    }
  }

  Future<void> _updateVisibility(
    ProvincePackage package,
    String visibility,
  ) async {
    try {
      await _service.updatePackageVisibility(package, visibility);
      if (!mounted) return;
      showAdminSnack(context, 'Package visibility updated.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Failed to update visibility: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return ProvincialAdminShell(
      current: ProvincialAdminDestination.packages,
      title: 'Packages',
      subtitle: 'Monitor packages from every city and municipality.',
      child: FutureBuilder<List<ProvincePackage>>(
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

          final allPackages = snapshot.data ?? const <ProvincePackage>[];
          final packages = _filtered(allPackages);

          final cities = allPackages
              .map((item) => item.city)
              .where((city) => city.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort();

          final totalBookings = allPackages.fold<int>(
            0,
            (sum, item) => sum + item.bookingsCount,
          );

          final estimatedRevenue = allPackages.fold<double>(
            0,
            (sum, item) => sum + item.revenue,
          );

          final counts = {
            'all': _countByStatus(allPackages, 'all'),
            'draft': _countByStatus(allPackages, 'draft'),
            'pending': _countByStatus(allPackages, 'pending'),
            'published': _countByStatus(allPackages, 'published'),
            'returned': _countByStatus(allPackages, 'returned'),
            'sold_out': _countByStatus(allPackages, 'sold_out'),
            'visible': _countByVisibility(allPackages, 'visible'),
            'hidden': _countByVisibility(allPackages, 'hidden'),
          };

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: SingleChildScrollView(
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
                  _PackagesHero(
                    total: allPackages.length,
                    published: counts['published'] ?? 0,
                    pending: counts['pending'] ?? 0,
                    bookings: totalBookings,
                    revenue: estimatedRevenue,
                  ),
                  const SizedBox(height: 16),
                  _PackageToolbar(
                    controller: _searchCtrl,
                    cities: cities,
                    cityFilter: _cityFilter,
                    statusFilter: _statusFilter,
                    visibilityFilter: _visibilityFilter,
                    counts: counts,
                    onCityChanged: (value) {
                      setState(() => _cityFilter = value);
                    },
                    onStatusChanged: (value) {
                      setState(() => _statusFilter = value);
                    },
                    onVisibilityChanged: (value) {
                      setState(() => _visibilityFilter = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (packages.isEmpty)
                    const AdminEmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No packages found',
                      message:
                          'Tour packages submitted by city tenants will appear here.',
                    )
                  else if (mobile)
                    ...packages.map(
                      (package) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PackageCard(
                          package: package,
                          onPublish: () => _updateStatus(package, 'published'),
                          onReturn: () => _updateStatus(package, 'returned'),
                          onDraft: () => _updateStatus(package, 'draft'),
                          onVisible: () => _updateVisibility(package, 'visible'),
                          onHidden: () => _updateVisibility(package, 'hidden'),
                        ),
                      ),
                    )
                  else
                    _PackageGrid(
                      packages: packages,
                      onStatus: _updateStatus,
                      onVisibility: _updateVisibility,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PackagesHero extends StatelessWidget {
  const _PackagesHero({
    required this.total,
    required this.published,
    required this.pending,
    required this.bookings,
    required this.revenue,
  });

  final int total;
  final int published;
  final int pending;
  final int bookings;
  final double revenue;

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);

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
                  published: published,
                  pending: pending,
                  bookings: bookings,
                  revenue: money.format(revenue),
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
                  published: published,
                  pending: pending,
                  bookings: bookings,
                  revenue: money.format(revenue),
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
        Icons.inventory_2_rounded,
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
          'Province-wide Package Monitoring',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .86),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tour Packages',
          style: TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Review package status, visibility, city coverage, bookings, and estimated revenue.',
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
    required this.published,
    required this.pending,
    required this.bookings,
    required this.revenue,
  });

  final int total;
  final int published;
  final int pending;
  final int bookings;
  final String revenue;

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    final items = [
      _HeroStatData('Total', total.toString(), Icons.inventory_2_rounded),
      _HeroStatData('Published', published.toString(), Icons.public_rounded),
      _HeroStatData('Pending', pending.toString(), Icons.pending_actions_rounded),
      _HeroStatData('Bookings', bookings.toString(), Icons.receipt_long_rounded),
      _HeroStatData('Revenue', revenue, Icons.payments_rounded),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) {
        return Container(
          width: desktop ? 116 : 145,
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
                          fontSize: 15.5,
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
  final String value;
  final IconData icon;
}

class _PackageToolbar extends StatelessWidget {
  const _PackageToolbar({
    required this.controller,
    required this.cities,
    required this.cityFilter,
    required this.statusFilter,
    required this.visibilityFilter,
    required this.counts,
    required this.onCityChanged,
    required this.onStatusChanged,
    required this.onVisibilityChanged,
  });

  final TextEditingController controller;
  final List<String> cities;
  final String cityFilter;
  final String statusFilter;
  final String visibilityFilter;
  final Map<String, int> counts;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onVisibilityChanged;

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
      child: Column(
        children: [
          Flex(
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
                      hintText: 'Search package title, city, price, duration...',
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
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14),
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
              _CityDropdown(
                cities: cities,
                value: cityFilter,
                onChanged: onCityChanged,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FilterRow(
            selected: statusFilter,
            counts: counts,
            filters: const [
              ('all', 'All'),
              ('draft', 'Draft'),
              ('pending', 'Pending'),
              ('published', 'Published'),
              ('returned', 'Returned'),
              ('sold_out', 'Sold Out'),
            ],
            onSelected: onStatusChanged,
          ),
          const SizedBox(height: 10),
          _FilterRow(
            selected: visibilityFilter,
            counts: counts,
            filters: const [
              ('all', 'All Visibility'),
              ('visible', 'Visible'),
              ('hidden', 'Hidden'),
            ],
            onSelected: onVisibilityChanged,
          ),
        ],
      ),
    );
  }
}

class _CityDropdown extends StatelessWidget {
  const _CityDropdown({
    required this.cities,
    required this.value,
    required this.onChanged,
  });

  final List<String> cities;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: Responsive.isDesktop(context) ? 230 : double.infinity,
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFF8FBFF),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: ProvincialAdminColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: ProvincialAdminColors.line),
          ),
        ),
        items: [
          const DropdownMenuItem(value: 'all', child: Text('All Cities')),
          ...cities.map(
            (city) => DropdownMenuItem(value: city, child: Text(city)),
          ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.selected,
    required this.counts,
    required this.filters,
    required this.onSelected,
  });

  final String selected;
  final Map<String, int> counts;
  final List<(String, String)> filters;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
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
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 13),
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
                        fontSize: 12,
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

class _PackageGrid extends StatelessWidget {
  const _PackageGrid({
    required this.packages,
    required this.onStatus,
    required this.onVisibility,
  });

  final List<ProvincePackage> packages;
  final void Function(ProvincePackage package, String status) onStatus;
  final void Function(ProvincePackage package, String visibility) onVisibility;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1250 ? 3 : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: packages.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 2.05,
          ),
          itemBuilder: (context, index) {
            final package = packages[index];

            return _PackageCard(
              package: package,
              onPublish: () => onStatus(package, 'published'),
              onReturn: () => onStatus(package, 'returned'),
              onDraft: () => onStatus(package, 'draft'),
              onVisible: () => onVisibility(package, 'visible'),
              onHidden: () => onVisibility(package, 'hidden'),
            );
          },
        );
      },
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.onPublish,
    required this.onReturn,
    required this.onDraft,
    required this.onVisible,
    required this.onHidden,
  });

  final ProvincePackage package;
  final VoidCallback onPublish;
  final VoidCallback onReturn;
  final VoidCallback onDraft;
  final VoidCallback onVisible;
  final VoidCallback onHidden;

  @override
  Widget build(BuildContext context) {
    final visible = package.visibilityStatus.toLowerCase().trim() == 'visible';
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
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
                  _PackageImage(url: package.imageUrl),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          package.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ProvincialAdminColors.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          package.city,
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
                  AdminStatusPill(status: package.status),
                  PopupMenuButton<String>(
                    tooltip: 'Package actions',
                    onSelected: (value) {
                      switch (value) {
                        case 'published':
                          onPublish();
                          break;
                        case 'returned':
                          onReturn();
                          break;
                        case 'draft':
                          onDraft();
                          break;
                        case 'visible':
                          onVisible();
                          break;
                        case 'hidden':
                          onHidden();
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'published',
                        child: Text('Mark as Published'),
                      ),
                      PopupMenuItem(
                        value: 'returned',
                        child: Text('Return for Revision'),
                      ),
                      PopupMenuItem(value: 'draft', child: Text('Set as Draft')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'visible', child: Text('Make Visible')),
                      PopupMenuItem(value: 'hidden', child: Text('Hide Package')),
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
                    child: _PackageInfo(
                      icon: Icons.payments_rounded,
                      label: 'Price',
                      value: package.priceText.isEmpty
                          ? money.format(package.estimatedBudget)
                          : package.priceText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PackageInfo(
                      icon: Icons.schedule_rounded,
                      label: 'Duration',
                      value: package.durationText.isEmpty
                          ? 'Not set'
                          : package.durationText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _PackageMetric(
                      label: 'Bookings',
                      value: package.bookingsCount,
                      icon: Icons.receipt_long_rounded,
                      color: ProvincialAdminColors.purple,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PackageMetric(
                      label: 'Revenue',
                      valueText: money.format(package.revenue),
                      icon: Icons.account_balance_wallet_rounded,
                      color: ProvincialAdminColors.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _VisibilityBox(
                      visible: visible,
                      onVisible: onVisible,
                      onHidden: onHidden,
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

class _PackageImage extends StatelessWidget {
  const _PackageImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: url.isEmpty
          ? const Icon(
              Icons.inventory_2_rounded,
              color: ProvincialAdminColors.blue,
              size: 28,
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.inventory_2_rounded,
                color: ProvincialAdminColors.blue,
                size: 28,
              ),
            ),
    );
  }
}

class _PackageInfo extends StatelessWidget {
  const _PackageInfo({
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

class _PackageMetric extends StatelessWidget {
  const _PackageMetric({
    this.value,
    this.valueText,
    required this.label,
    required this.icon,
    required this.color,
  });

  final int? value;
  final String? valueText;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final display = valueText ?? '${value ?? 0}';

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
                    text: '$display\n',
                    style: TextStyle(
                      color: color,
                      fontSize: display.length > 8 ? 13 : 17,
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _VisibilityBox extends StatelessWidget {
  const _VisibilityBox({
    required this.visible,
    required this.onVisible,
    required this.onHidden,
  });

  final bool visible;
  final VoidCallback onVisible;
  final VoidCallback onHidden;

  @override
  Widget build(BuildContext context) {
    final color = visible ? ProvincialAdminColors.green : ProvincialAdminColors.red;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: visible ? onHidden : onVisible,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .10)),
        ),
        child: Row(
          children: [
            Icon(
              visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: visible ? 'Visible\n' : 'Hidden\n',
                      style: TextStyle(
                        color: color,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const TextSpan(
                      text: 'Tap to toggle',
                      style: TextStyle(
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
      ),
    );
  }
}