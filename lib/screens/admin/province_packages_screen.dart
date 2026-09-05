import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/admin_empty_state.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class ProvincePackagesScreen extends StatefulWidget {
  const ProvincePackagesScreen({super.key, this.initialSearch = ''});

  final String initialSearch;

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
    _searchCtrl.text = widget.initialSearch;
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

  String _packagePrice(ProvincePackage package) {
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);
    if (package.priceText.trim().isNotEmpty) return package.priceText;
    return money.format(package.estimatedBudget);
  }

  Future<void> _showPackageDetails(ProvincePackage package) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _PackageDetailsDialog(
        package: package,
        priceText: _packagePrice(package),
        spotsFuture: _service.fetchPackageSpotTitles(package.id),
      ),
    );
  }

  List<ProvincePackage> _filtered(List<ProvincePackage> packages) {
    final query = _searchCtrl.text.trim().toLowerCase();

    return packages
        .where((package) {
          final city = package.city.trim();
          final status = package.status.toLowerCase().trim();
          final visibility = package.visibilityStatus.toLowerCase().trim();

          final matchesCity = _cityFilter == 'all' || city == _cityFilter;
          final matchesStatus =
              _statusFilter == 'all' || status == _statusFilter;
          final matchesVisibility =
              _visibilityFilter == 'all' || visibility == _visibilityFilter;

          if (!matchesCity || !matchesStatus || !matchesVisibility) {
            return false;
          }

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
        })
        .toList(growable: false);
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
        .where(
          (item) => item.visibilityStatus.toLowerCase().trim() == visibility,
        )
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

          final cities =
              allPackages
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
                          onTap: () => _showPackageDetails(package),
                          onPublish: () => _updateStatus(package, 'published'),
                          onReturn: () => _updateStatus(package, 'returned'),
                          onDraft: () => _updateStatus(package, 'draft'),
                          onVisible: () =>
                              _updateVisibility(package, 'visible'),
                          onHidden: () => _updateVisibility(package, 'hidden'),
                        ),
                      ),
                    )
                  else
                    _PackageGrid(
                      packages: packages,
                      onTap: _showPackageDetails,
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
      _HeroStatData(
        'Pending',
        pending.toString(),
        Icons.pending_actions_rounded,
      ),
      _HeroStatData(
        'Bookings',
        bookings.toString(),
        Icons.receipt_long_rounded,
      ),
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

  int get _activeFilterCount {
    var count = 0;
    if (cityFilter != 'all') count++;
    if (statusFilter != 'all') count++;
    if (visibilityFilter != 'all') count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    final searchField = SizedBox(
      height: 50,
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: ProvincialAdminColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: ProvincialAdminColors.line),
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
        crossAxisAlignment: desktop
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.stretch,
        children: [
          if (desktop) Expanded(child: searchField) else searchField,
          SizedBox(width: desktop ? 14 : 0, height: desktop ? 0 : 12),
          _PackageFilterButton(
            cities: cities,
            cityFilter: cityFilter,
            statusFilter: statusFilter,
            visibilityFilter: visibilityFilter,
            activeCount: _activeFilterCount,
            counts: counts,
            onCityChanged: onCityChanged,
            onStatusChanged: onStatusChanged,
            onVisibilityChanged: onVisibilityChanged,
          ),
        ],
      ),
    );
  }
}

class _PackageFilterButton extends StatelessWidget {
  const _PackageFilterButton({
    required this.cities,
    required this.cityFilter,
    required this.statusFilter,
    required this.visibilityFilter,
    required this.activeCount,
    required this.counts,
    required this.onCityChanged,
    required this.onStatusChanged,
    required this.onVisibilityChanged,
  });

  final List<String> cities;
  final String cityFilter;
  final String statusFilter;
  final String visibilityFilter;
  final int activeCount;
  final Map<String, int> counts;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onVisibilityChanged;

  String get _label {
    if (activeCount == 0) return 'Filters';

    final labels = <String>[];
    if (cityFilter != 'all') labels.add(cityFilter);
    if (statusFilter != 'all') labels.add(_filterLabel(statusFilter));
    if (visibilityFilter != 'all') labels.add(_filterLabel(visibilityFilter));

    return labels.join(' • ');
  }

  static String _filterLabel(String value) {
    switch (value) {
      case 'sold_out':
        return 'Sold Out';
      case 'all':
        return 'All';
      default:
        final normalized = value.replaceAll('_', ' ');
        return normalized
            .split(' ')
            .map(
              (word) => word.isEmpty
                  ? word
                  : '${word[0].toUpperCase()}${word.substring(1)}',
            )
            .join(' ');
    }
  }

  Future<void> _openFilters(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PackageFilterSheet(
        cities: cities,
        cityFilter: cityFilter,
        statusFilter: statusFilter,
        visibilityFilter: visibilityFilter,
        counts: counts,
        onApply:
            ({
              required String city,
              required String status,
              required String visibility,
            }) {
              onCityChanged(city);
              onStatusChanged(status);
              onVisibilityChanged(visibility);
            },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    return SizedBox(
      height: 50,
      width: desktop ? 245 : double.infinity,
      child: InkWell(
        onTap: () => _openFilters(context),
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: activeCount == 0
                ? const Color(0xFFF8FBFF)
                : ProvincialAdminColors.blue.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: activeCount == 0
                  ? ProvincialAdminColors.line
                  : ProvincialAdminColors.blue.withValues(alpha: .35),
              width: activeCount == 0 ? 1 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                color: activeCount == 0
                    ? ProvincialAdminColors.muted
                    : ProvincialAdminColors.blue,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: activeCount == 0
                        ? ProvincialAdminColors.text
                        : ProvincialAdminColors.blue,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (activeCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ProvincialAdminColors.blue,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$activeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: activeCount == 0
                    ? ProvincialAdminColors.muted
                    : ProvincialAdminColors.blue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackageFilterSheet extends StatefulWidget {
  const _PackageFilterSheet({
    required this.cities,
    required this.cityFilter,
    required this.statusFilter,
    required this.visibilityFilter,
    required this.counts,
    required this.onApply,
  });

  final List<String> cities;
  final String cityFilter;
  final String statusFilter;
  final String visibilityFilter;
  final Map<String, int> counts;
  final void Function({
    required String city,
    required String status,
    required String visibility,
  })
  onApply;

  @override
  State<_PackageFilterSheet> createState() => _PackageFilterSheetState();
}

class _PackageFilterSheetState extends State<_PackageFilterSheet> {
  late String _city;
  late String _status;
  late String _visibility;

  @override
  void initState() {
    super.initState();
    _city = widget.cityFilter;
    _status = widget.statusFilter;
    _visibility = widget.visibilityFilter;
  }

  int get _activeCount {
    var count = 0;
    if (_city != 'all') count++;
    if (_status != 'all') count++;
    if (_visibility != 'all') count++;
    return count;
  }

  void _reset() {
    setState(() {
      _city = 'all';
      _status = 'all';
      _visibility = 'all';
    });
  }

  void _apply() {
    widget.onApply(city: _city, status: _status, visibility: _visibility);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: ProvincialAdminColors.line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .10),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: ProvincialAdminColors.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: ProvincialAdminColors.blue.withValues(
                          alpha: .10,
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        color: ProvincialAdminColors.blue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'Package Filters\n',
                              style: TextStyle(
                                color: ProvincialAdminColors.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                            ),
                            TextSpan(
                              text: _activeCount == 0
                                  ? 'No active filters'
                                  : '$_activeCount active filter${_activeCount == 1 ? '' : 's'}',
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
                    ),
                    TextButton(onPressed: _reset, child: const Text('Reset')),
                  ],
                ),
                const SizedBox(height: 18),
                _FilterSection(
                  title: 'City / Municipality',
                  children: [
                    _ChoiceChipButton(
                      label: 'All Cities',
                      selected: _city == 'all',
                      count: null,
                      onTap: () => setState(() => _city = 'all'),
                    ),
                    ...widget.cities.map(
                      (city) => _ChoiceChipButton(
                        label: city,
                        selected: _city == city,
                        count: null,
                        onTap: () => setState(() => _city = city),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _FilterSection(
                  title: 'Package Status',
                  children: [
                    _ChoiceChipButton(
                      label: 'All',
                      selected: _status == 'all',
                      count: widget.counts['all'],
                      onTap: () => setState(() => _status = 'all'),
                    ),
                    _ChoiceChipButton(
                      label: 'Draft',
                      selected: _status == 'draft',
                      count: widget.counts['draft'],
                      onTap: () => setState(() => _status = 'draft'),
                    ),
                    _ChoiceChipButton(
                      label: 'Pending',
                      selected: _status == 'pending',
                      count: widget.counts['pending'],
                      onTap: () => setState(() => _status = 'pending'),
                    ),
                    _ChoiceChipButton(
                      label: 'Published',
                      selected: _status == 'published',
                      count: widget.counts['published'],
                      onTap: () => setState(() => _status = 'published'),
                    ),
                    _ChoiceChipButton(
                      label: 'Returned',
                      selected: _status == 'returned',
                      count: widget.counts['returned'],
                      onTap: () => setState(() => _status = 'returned'),
                    ),
                    _ChoiceChipButton(
                      label: 'Sold Out',
                      selected: _status == 'sold_out',
                      count: widget.counts['sold_out'],
                      onTap: () => setState(() => _status = 'sold_out'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _FilterSection(
                  title: 'Visibility',
                  children: [
                    _ChoiceChipButton(
                      label: 'All Visibility',
                      selected: _visibility == 'all',
                      count: widget.counts['all'],
                      onTap: () => setState(() => _visibility = 'all'),
                    ),
                    _ChoiceChipButton(
                      label: 'Visible',
                      selected: _visibility == 'visible',
                      count: widget.counts['visible'],
                      onTap: () => setState(() => _visibility = 'visible'),
                    ),
                    _ChoiceChipButton(
                      label: 'Hidden',
                      selected: _visibility == 'hidden',
                      count: widget.counts['hidden'],
                      onTap: () => setState(() => _visibility = 'hidden'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Cancel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ProvincialAdminColors.muted,
                          side: const BorderSide(
                            color: ProvincialAdminColors.line,
                          ),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _apply,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Apply Filters'),
                        style: FilledButton.styleFrom(
                          backgroundColor: ProvincialAdminColors.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: ProvincialAdminColors.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 11),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}

class _ChoiceChipButton extends StatelessWidget {
  const _ChoiceChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? ProvincialAdminColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? ProvincialAdminColors.blue
                : ProvincialAdminColors.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : ProvincialAdminColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: .22)
                      : const Color(0xFFF1F6FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? Colors.white : ProvincialAdminColors.blue,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PackageGrid extends StatelessWidget {
  const _PackageGrid({
    required this.packages,
    required this.onTap,
    required this.onStatus,
    required this.onVisibility,
  });

  final List<ProvincePackage> packages;
  final ValueChanged<ProvincePackage> onTap;
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
              onTap: () => onTap(package),
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
    required this.onTap,
    required this.onPublish,
    required this.onReturn,
    required this.onDraft,
    required this.onVisible,
    required this.onHidden,
  });

  final ProvincePackage package;
  final VoidCallback onTap;
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
        onTap: onTap,
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
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tap card to view package details',
                  style: const TextStyle(
                    color: ProvincialAdminColors.lightMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackageDetailsDialog extends StatelessWidget {
  const _PackageDetailsDialog({
    required this.package,
    required this.priceText,
    required this.spotsFuture,
  });

  final ProvincePackage package;
  final String priceText;
  final Future<List<String>> spotsFuture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: ProvincialAdminColors.line),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .08),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                              package.title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: ProvincialAdminColors.text,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              package.city,
                              style: const TextStyle(
                                color: ProvincialAdminColors.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: ProvincialAdminColors.lightMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _PackageDetailBlock(
                          icon: Icons.payments_rounded,
                          label: 'Price',
                          value: priceText,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PackageDetailBlock(
                          icon: Icons.schedule_rounded,
                          label: 'Duration',
                          value: package.durationText.trim().isEmpty
                              ? 'Not set'
                              : package.durationText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Included Spots',
                    style: TextStyle(
                      color: ProvincialAdminColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<String>>(
                    future: spotsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return _PackageSpotsMessage(
                          icon: Icons.error_outline_rounded,
                          message: 'Unable to load package spots right now.',
                        );
                      }

                      final spots = snapshot.data ?? const <String>[];
                      if (spots.isEmpty) {
                        return _PackageSpotsMessage(
                          icon: Icons.place_outlined,
                          message:
                              'No linked spots were found for this package.',
                        );
                      }

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FBFF),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: ProvincialAdminColors.line),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < spots.length; i++) ...[
                              _PackageSpotRow(index: i + 1, title: spots[i]),
                              if (i != spots.length - 1)
                                const Divider(
                                  height: 16,
                                  color: ProvincialAdminColors.line,
                                ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PackageDetailBlock extends StatelessWidget {
  const _PackageDetailBlock({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: ProvincialAdminColors.blue, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label\n',
                    style: const TextStyle(
                      color: ProvincialAdminColors.lightMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      color: ProvincialAdminColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
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

class _PackageSpotsMessage extends StatelessWidget {
  const _PackageSpotsMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: ProvincialAdminColors.lightMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: ProvincialAdminColors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageSpotRow extends StatelessWidget {
  const _PackageSpotRow({required this.index, required this.title});

  final int index;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFDCEBFF),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              color: ProvincialAdminColors.blue,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: ProvincialAdminColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ),
      ],
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
              errorBuilder: (_, _, _) => const Icon(
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
    final color = visible
        ? ProvincialAdminColors.green
        : ProvincialAdminColors.red;

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
