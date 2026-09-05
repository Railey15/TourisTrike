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

// ─────────────────────────────────────────────────────────────────────────────
// Local design colors
// ─────────────────────────────────────────────────────────────────────────────

const _pageBackground = Color(0xFFF4F7FB);

const _softBlue = Color(0xFFF2F7FF);
const _softGreen = Color(0xFFF0FDF4);
const _softAmber = Color(0xFFFFFBEB);
const _softRed = Color(0xFFFEF2F2);
const _softPurple = Color(0xFFF7F3FF);
const _softCyan = Color(0xFFF0F9FF);

const _green = Color(0xFF16A34A);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFDC2626);
const _purple = Color(0xFF7C3AED);
const _cyan = Color(0xFF0EA5E9);

// ─────────────────────────────────────────────────────────────────────────────
// Dialog actions
// ─────────────────────────────────────────────────────────────────────────────

enum _PackageDialogAction {
  publish,
  draft,
  returnPackage,
  makeVisible,
  makeHidden,
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class ProvincePackagesScreen extends StatefulWidget {
  const ProvincePackagesScreen({
    super.key,
    this.initialSearch = '',
  });

  final String initialSearch;

  @override
  State<ProvincePackagesScreen> createState() =>
      _ProvincePackagesScreenState();
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

    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _reload() async {
    setState(() {
      _future = _service.fetchProvincePackages();
    });

    await _future;
  }

  bool get _hasActiveFilters {
    return _searchCtrl.text.trim().isNotEmpty ||
        _cityFilter != 'all' ||
        _statusFilter != 'all' ||
        _visibilityFilter != 'all';
  }

  void _clearFilters() {
    setState(() {
      _searchCtrl.clear();
      _cityFilter = 'all';
      _statusFilter = 'all';
      _visibilityFilter = 'all';
    });
  }

  String _packagePrice(
    ProvincePackage package,
  ) {
    final money = NumberFormat.currency(
      symbol: '₱',
      decimalDigits: 0,
    );

    if (package.priceText.trim().isNotEmpty) {
      return package.priceText;
    }

    return money.format(
      package.estimatedBudget,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Package details
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _showPackageDetails(
    ProvincePackage package,
  ) async {
    final action = await showDialog<_PackageDialogAction>(
      context: context,
      barrierColor: Colors.black.withValues(
        alpha: .35,
      ),
      builder: (dialogContext) {
        return _PackageDetailsDialog(
          package: package,
          priceText: _packagePrice(package),
          spotsFuture:
              _service.fetchPackageSpotTitles(
            package.id,
          ),
        );
      },
    );

    if (action == null || !mounted) {
      return;
    }

    switch (action) {
      case _PackageDialogAction.publish:
        await _updateStatus(
          package,
          'published',
        );
        break;

      case _PackageDialogAction.draft:
        await _updateStatus(
          package,
          'draft',
        );
        break;

      case _PackageDialogAction.returnPackage:
        await _updateStatus(
          package,
          'returned',
        );
        break;

      case _PackageDialogAction.makeVisible:
        await _updateVisibility(
          package,
          'visible',
        );
        break;

      case _PackageDialogAction.makeHidden:
        await _updateVisibility(
          package,
          'hidden',
        );
        break;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Filtering
  // ───────────────────────────────────────────────────────────────────────────

  List<ProvincePackage> _filtered(
    List<ProvincePackage> packages,
  ) {
    final query = _searchCtrl.text
        .trim()
        .toLowerCase();

    return packages.where((package) {
      final city =
          package.city.trim();

      final status =
          package.status
              .trim()
              .toLowerCase();

      final visibility =
          package.visibilityStatus
              .trim()
              .toLowerCase();

      final matchesCity =
          _cityFilter == 'all' ||
          city == _cityFilter;

      final matchesStatus =
          _statusFilter == 'all' ||
          status == _statusFilter;

      final matchesVisibility =
          _visibilityFilter == 'all' ||
          visibility == _visibilityFilter;

      if (!matchesCity ||
          !matchesStatus ||
          !matchesVisibility) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

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

  int _countByStatus(
    List<ProvincePackage> packages,
    String status,
  ) {
    if (status == 'all') {
      return packages.length;
    }

    return packages.where((item) {
      return item.status
              .trim()
              .toLowerCase() ==
          status;
    }).length;
  }

  int _countByVisibility(
    List<ProvincePackage> packages,
    String visibility,
  ) {
    if (visibility == 'all') {
      return packages.length;
    }

    return packages.where((item) {
      return item.visibilityStatus
              .trim()
              .toLowerCase() ==
          visibility;
    }).length;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Actions
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _updateStatus(
    ProvincePackage package,
    String status,
  ) async {
    try {
      await _service.updatePackageStatus(
        package,
        status,
      );

      if (!mounted) {
        return;
      }

      showAdminSnack(
        context,
        'Package status updated.',
        error: false,
      );

      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }

      showAdminSnack(
        context,
        'Failed to update package: $error',
      );
    }
  }

  Future<void> _updateVisibility(
    ProvincePackage package,
    String visibility,
  ) async {
    try {
      await _service.updatePackageVisibility(
        package,
        visibility,
      );

      if (!mounted) {
        return;
      }

      showAdminSnack(
        context,
        'Package visibility updated.',
        error: false,
      );

      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }

      showAdminSnack(
        context,
        'Failed to update visibility: $error',
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mobile =
        Responsive.isMobile(context);

    return ProvincialAdminShell(
      current:
          ProvincialAdminDestination.packages,
      title: 'Packages',
      subtitle:
          'Monitor packages from every city and municipality.',
      child: FutureBuilder<List<ProvincePackage>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const AdminLoadingView();
          }

          if (snapshot.hasError) {
            return AdminErrorView(
              message:
                  snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final allPackages =
              snapshot.data ??
                  const <ProvincePackage>[];

          final packages =
              _filtered(allPackages);

          final cities = allPackages
              .map(
                (item) =>
                    item.city.trim(),
              )
              .where(
                (city) => city.isNotEmpty,
              )
              .toSet()
              .toList()
            ..sort();

          final totalBookings =
              allPackages.fold<int>(
            0,
            (sum, item) =>
                sum + item.bookingsCount,
          );

          final totalRevenue =
              allPackages.fold<double>(
            0,
            (sum, item) =>
                sum + item.revenue,
          );

          final counts =
              <String, int>{
            'all':
                _countByStatus(
              allPackages,
              'all',
            ),
            'draft':
                _countByStatus(
              allPackages,
              'draft',
            ),
            'pending':
                _countByStatus(
              allPackages,
              'pending',
            ),
            'published':
                _countByStatus(
              allPackages,
              'published',
            ),
            'returned':
                _countByStatus(
              allPackages,
              'returned',
            ),
            'sold_out':
                _countByStatus(
              allPackages,
              'sold_out',
            ),
            'visible':
                _countByVisibility(
              allPackages,
              'visible',
            ),
            'hidden':
                _countByVisibility(
              allPackages,
              'hidden',
            ),
          };

          return ColoredBox(
            color: _pageBackground,
            child: RefreshIndicator(
              onRefresh: _reload,
              child:
                  SingleChildScrollView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding:
                    EdgeInsets.fromLTRB(
                  mobile ? 14 : 22,
                  mobile ? 14 : 18,
                  mobile ? 14 : 22,
                  32,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    // ─────────────────────────
                    // Summary cards
                    // ─────────────────────────

                    _PackageSummaryGrid(
                      total:
                          allPackages.length,
                      published:
                          counts['published'] ??
                              0,
                      pending:
                          counts['pending'] ??
                              0,
                      bookings:
                          totalBookings,
                      revenue:
                          totalRevenue,
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    // ─────────────────────────
                    // Search + filters
                    // ─────────────────────────

                    _PackageToolbar(
                      controller:
                          _searchCtrl,
                      cities: cities,
                      cityFilter:
                          _cityFilter,
                      statusFilter:
                          _statusFilter,
                      visibilityFilter:
                          _visibilityFilter,
                      counts: counts,
                      hasActiveFilters:
                          _hasActiveFilters,
                      onClearFilters:
                          _clearFilters,
                      onCityChanged:
                          (value) {
                        setState(() {
                          _cityFilter =
                              value;
                        });
                      },
                      onStatusChanged:
                          (value) {
                        setState(() {
                          _statusFilter =
                              value;
                        });
                      },
                      onVisibilityChanged:
                          (value) {
                        setState(() {
                          _visibilityFilter =
                              value;
                        });
                      },
                    ),

                    const SizedBox(
                      height: 18,
                    ),

                    const _PackageSectionHeader(),

                    const SizedBox(
                      height: 10,
                    ),

                    if (packages.isEmpty)
                      _PackageEmptyState(
                        hasFilters:
                            _hasActiveFilters,
                        onClear:
                            _clearFilters,
                      )
                    else if (mobile)
                      ...packages.map(
                        (package) {
                          return Padding(
                            padding:
                                const EdgeInsets
                                    .only(
                              bottom: 12,
                            ),
                            child:
                                _PackageCard(
                              package:
                                  package,
                              onTap: () {
                                _showPackageDetails(
                                  package,
                                );
                              },
                              onPublish: () {
                                _updateStatus(
                                  package,
                                  'published',
                                );
                              },
                              onReturn: () {
                                _updateStatus(
                                  package,
                                  'returned',
                                );
                              },
                              onDraft: () {
                                _updateStatus(
                                  package,
                                  'draft',
                                );
                              },
                              onVisible: () {
                                _updateVisibility(
                                  package,
                                  'visible',
                                );
                              },
                              onHidden: () {
                                _updateVisibility(
                                  package,
                                  'hidden',
                                );
                              },
                            ),
                          );
                        },
                      )
                    else
                      _PackageGrid(
                        packages:
                            packages,
                        onTap:
                            _showPackageDetails,
                        onStatus:
                            _updateStatus,
                        onVisibility:
                            _updateVisibility,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary cards
// ─────────────────────────────────────────────────────────────────────────────

class _PackageSummaryGrid extends StatelessWidget {
  const _PackageSummaryGrid({
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
    final money =
        NumberFormat.currency(
      symbol: '₱',
      decimalDigits: 0,
    );

    final items = [
      _SummaryData(
        label: 'Total Packages',
        value: '$total',
        helper: 'Province-wide',
        icon:
            Icons.inventory_2_outlined,
        color:
            ProvincialAdminColors.blue,
        background: _softBlue,
      ),
      _SummaryData(
        label: 'Published',
        value: '$published',
        helper:
            'Currently published',
        icon: Icons.public_rounded,
        color: _green,
        background: _softGreen,
      ),
      _SummaryData(
        label: 'Pending',
        value: '$pending',
        helper: pending == 0
            ? 'No pending review'
            : 'Needs review',
        icon:
            Icons.pending_actions_outlined,
        color: _amber,
        background: _softAmber,
      ),
      _SummaryData(
        label: 'Bookings',
        value: '$bookings',
        helper: 'Package bookings',
        icon:
            Icons.receipt_long_outlined,
        color: _purple,
        background: _softPurple,
      ),
      _SummaryData(
        label: 'Revenue',
        value:
            money.format(revenue),
        helper:
            'Recorded package revenue',
        icon:
            Icons.payments_outlined,
        color: _cyan,
        background: _softCyan,
      ),
    ];

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final width =
            constraints.maxWidth;

        final columns =
            width >= 1100
                ? 5
                : width >= 760
                    ? 3
                    : width >= 480
                        ? 2
                        : 1;

        const gap = 10.0;

        final itemWidth =
            (width -
                    ((columns - 1) *
                        gap)) /
                columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children:
              items.map((item) {
            return SizedBox(
              width: itemWidth,
              child:
                  _SummaryCard(
                data: item,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _SummaryData {
  const _SummaryData({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String label;
  final String value;
  final String helper;

  final IconData icon;

  final Color color;
  final Color background;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.data,
  });

  final _SummaryData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          const BoxConstraints(
        minHeight: 94,
      ),
      padding:
          const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(15),
        border: Border.all(
          color:
              ProvincialAdminColors.line,
        ),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(
              alpha: .02,
            ),
            blurRadius: 10,
            offset:
                const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: data.background,
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
            ),
            child: Icon(
              data.icon,
              color: data.color,
              size: 19,
            ),
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                    color:
                        ProvincialAdminColors
                            .muted,
                    fontSize: 9,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  data.value,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                    color:
                        ProvincialAdminColors
                            .text,
                    fontSize: 18,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  data.helper,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                    color:
                        ProvincialAdminColors
                            .lightMuted,
                    fontSize: 8.2,
                    fontWeight:
                        FontWeight.w600,
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

// ─────────────────────────────────────────────────────────────────────────────
// Toolbar
// ─────────────────────────────────────────────────────────────────────────────

class _PackageToolbar extends StatelessWidget {
  const _PackageToolbar({
    required this.controller,
    required this.cities,
    required this.cityFilter,
    required this.statusFilter,
    required this.visibilityFilter,
    required this.counts,
    required this.hasActiveFilters,
    required this.onClearFilters,
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

  final bool hasActiveFilters;

  final VoidCallback onClearFilters;

  final ValueChanged<String>
      onCityChanged;

  final ValueChanged<String>
      onStatusChanged;

  final ValueChanged<String>
      onVisibilityChanged;

  int get _activeFilterCount {
    var result = 0;

    if (cityFilter != 'all') {
      result++;
    }

    if (statusFilter != 'all') {
      result++;
    }

    if (visibilityFilter != 'all') {
      result++;
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(15),
        border: Border.all(
          color:
              ProvincialAdminColors.line,
        ),
      ),
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final narrow =
              constraints.maxWidth <
                  700;

          final searchField =
              SizedBox(
            height: 44,
            child: TextField(
              controller: controller,
              textInputAction:
                  TextInputAction.search,
              decoration:
                  InputDecoration(
                hintText:
                    'Search package title, city, price or duration...',
                hintStyle:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .lightMuted,
                  fontWeight:
                      FontWeight.w600,
                  fontSize: 10.5,
                ),
                prefixIcon:
                    const Icon(
                  Icons.search_rounded,
                  color:
                      ProvincialAdminColors
                          .lightMuted,
                  size: 18,
                ),
                suffixIcon:
                    controller.text
                            .trim()
                            .isNotEmpty
                        ? IconButton(
                            tooltip:
                                'Clear search',
                            onPressed:
                                controller.clear,
                            icon:
                                const Icon(
                              Icons
                                  .close_rounded,
                              size: 16,
                            ),
                          )
                        : null,
                filled: true,
                fillColor:
                    const Color(
                  0xFFF8FAFC,
                ),
                contentPadding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 12,
                ),
                enabledBorder:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius
                          .circular(9),
                  borderSide:
                      const BorderSide(
                    color:
                        ProvincialAdminColors
                            .line,
                  ),
                ),
                focusedBorder:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius
                          .circular(9),
                  borderSide:
                      const BorderSide(
                    color:
                        ProvincialAdminColors
                            .blue,
                    width: 1.2,
                  ),
                ),
                border:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius
                          .circular(9),
                ),
              ),
            ),
          );

          final filterButton =
              _PackageFilterButton(
            cities: cities,
            cityFilter:
                cityFilter,
            statusFilter:
                statusFilter,
            visibilityFilter:
                visibilityFilter,
            activeCount:
                _activeFilterCount,
            counts: counts,
            onCityChanged:
                onCityChanged,
            onStatusChanged:
                onStatusChanged,
            onVisibilityChanged:
                onVisibilityChanged,
          );

          if (narrow) {
            return Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .stretch,
              children: [
                searchField,
                const SizedBox(
                  height: 9,
                ),
                filterButton,
                if (hasActiveFilters) ...[
                  const SizedBox(
                    height: 8,
                  ),
                  Align(
                    alignment:
                        Alignment.centerRight,
                    child:
                        TextButton.icon(
                      onPressed:
                          onClearFilters,
                      icon:
                          const Icon(
                        Icons
                            .filter_alt_off_rounded,
                        size: 15,
                      ),
                      label:
                          const Text(
                        'Clear Filters',
                      ),
                    ),
                  ),
                ],
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: searchField,
              ),

              const SizedBox(
                width: 9,
              ),

              SizedBox(
                width: 210,
                child: filterButton,
              ),

              if (hasActiveFilters) ...[
                const SizedBox(
                  width: 7,
                ),
                TextButton.icon(
                  onPressed:
                      onClearFilters,
                  icon:
                      const Icon(
                    Icons
                        .filter_alt_off_rounded,
                    size: 15,
                  ),
                  label:
                      const Text(
                    'Clear',
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter button
// ─────────────────────────────────────────────────────────────────────────────

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

  final ValueChanged<String>
      onCityChanged;

  final ValueChanged<String>
      onStatusChanged;

  final ValueChanged<String>
      onVisibilityChanged;

  Future<void> _openFilters(
    BuildContext context,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Colors.transparent,
      builder: (_) {
        return _PackageFilterSheet(
          cities: cities,
          cityFilter:
              cityFilter,
          statusFilter:
              statusFilter,
          visibilityFilter:
              visibilityFilter,
          counts: counts,
          onApply: ({
            required String city,
            required String status,
            required String visibility,
          }) {
            onCityChanged(city);
            onStatusChanged(status);
            onVisibilityChanged(
              visibility,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final active =
        activeCount > 0;

    return SizedBox(
      height: 44,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _openFilters(context);
          },
          borderRadius:
              BorderRadius.circular(9),
          child: Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 12,
            ),
            decoration: BoxDecoration(
              color: active
                  ? ProvincialAdminColors
                      .blue
                      .withValues(
                        alpha: .08,
                      )
                  : const Color(
                      0xFFF8FAFC,
                    ),
              borderRadius:
                  BorderRadius.circular(
                9,
              ),
              border: Border.all(
                color: active
                    ? ProvincialAdminColors
                        .blue
                        .withValues(
                          alpha: .25,
                        )
                    : ProvincialAdminColors
                        .line,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 17,
                  color: active
                      ? ProvincialAdminColors
                          .blue
                      : ProvincialAdminColors
                          .muted,
                ),

                const SizedBox(
                  width: 7,
                ),

                Expanded(
                  child: Text(
                    'Filters',
                    style: TextStyle(
                      color: active
                          ? ProvincialAdminColors
                              .blue
                          : ProvincialAdminColors
                              .text,
                      fontSize: 10.5,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                ),

                if (active) ...[
                  Container(
                    constraints:
                        const BoxConstraints(
                      minWidth: 20,
                    ),
                    alignment:
                        Alignment.center,
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          ProvincialAdminColors
                              .blue,
                      borderRadius:
                          BorderRadius
                              .circular(
                        999,
                      ),
                    ),
                    child: Text(
                      '$activeCount',
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                        fontSize: 8.5,
                        fontWeight:
                            FontWeight
                                .w900,
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 5,
                  ),
                ],

                const Icon(
                  Icons
                      .keyboard_arrow_down_rounded,
                  size: 17,
                  color:
                      ProvincialAdminColors
                          .muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter sheet
// ─────────────────────────────────────────────────────────────────────────────

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
  }) onApply;

  @override
  State<_PackageFilterSheet> createState() =>
      _PackageFilterSheetState();
}

class _PackageFilterSheetState extends State<_PackageFilterSheet> {
  late String _city;
  late String _status;
  late String _visibility;

  @override
  void initState() {
    super.initState();

    _city =
        widget.cityFilter;

    _status =
        widget.statusFilter;

    _visibility =
        widget.visibilityFilter;
  }

  void _reset() {
    setState(() {
      _city = 'all';
      _status = 'all';
      _visibility = 'all';
    });
  }

  void _apply() {
    widget.onApply(
      city: _city,
      status: _status,
      visibility:
          _visibility,
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom =
        MediaQuery.of(context)
            .viewInsets
            .bottom;

    return Padding(
      padding:
          EdgeInsets.only(
        bottom: bottom,
      ),
      child: Align(
        alignment:
            Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints:
              const BoxConstraints(
            maxWidth: 720,
          ),
          margin:
              const EdgeInsets.all(16),
          padding:
              const EdgeInsets.fromLTRB(
            18,
            12,
            18,
            18,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(
              22,
            ),
            border: Border.all(
              color:
                  ProvincialAdminColors
                      .line,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black
                        .withValues(
                  alpha: .10,
                ),
                blurRadius: 28,
                offset:
                    const Offset(
                  0,
                  14,
                ),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child:
                SingleChildScrollView(
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment
                        .stretch,
                children: [
                  Align(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration:
                          BoxDecoration(
                        color:
                            ProvincialAdminColors
                                .line,
                        borderRadius:
                            BorderRadius
                                .circular(
                          999,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 14,
                  ),

                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration:
                            BoxDecoration(
                          color:
                              ProvincialAdminColors
                                  .blue
                                  .withValues(
                            alpha: .08,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            10,
                          ),
                        ),
                        child:
                            const Icon(
                          Icons
                              .tune_rounded,
                          size: 18,
                          color:
                              ProvincialAdminColors
                                  .blue,
                        ),
                      ),

                      const SizedBox(
                        width: 10,
                      ),

                      const Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              'Package Filters',
                              style:
                                  TextStyle(
                                color:
                                    ProvincialAdminColors
                                        .text,
                                fontSize:
                                    15,
                                fontWeight:
                                    FontWeight
                                        .w900,
                              ),
                            ),
                            SizedBox(
                              height: 2,
                            ),
                            Text(
                              'Filter packages by LGU, status, or visibility.',
                              style:
                                  TextStyle(
                                color:
                                    ProvincialAdminColors
                                        .muted,
                                fontSize:
                                    10,
                                fontWeight:
                                    FontWeight
                                        .w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      TextButton(
                        onPressed:
                            _reset,
                        child:
                            const Text(
                          'Reset',
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 15,
                  ),

                  _FilterSection(
                    title:
                        'City / Municipality',
                    children: [
                      _ChoiceChipButton(
                        label:
                            'All Cities',
                        selected:
                            _city == 'all',
                        onTap: () {
                          setState(() {
                            _city =
                                'all';
                          });
                        },
                      ),
                      ...widget.cities.map(
                        (city) {
                          return _ChoiceChipButton(
                            label: city,
                            selected:
                                _city ==
                                    city,
                            onTap: () {
                              setState(() {
                                _city =
                                    city;
                              });
                            },
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  _FilterSection(
                    title:
                        'Package Status',
                    children: [
                      _ChoiceChipButton(
                        label: 'All',
                        count:
                            widget.counts[
                                'all'],
                        selected:
                            _status ==
                                'all',
                        onTap: () {
                          setState(() {
                            _status =
                                'all';
                          });
                        },
                      ),
                      _ChoiceChipButton(
                        label: 'Draft',
                        count:
                            widget.counts[
                                'draft'],
                        selected:
                            _status ==
                                'draft',
                        onTap: () {
                          setState(() {
                            _status =
                                'draft';
                          });
                        },
                      ),
                      _ChoiceChipButton(
                        label: 'Pending',
                        count:
                            widget.counts[
                                'pending'],
                        selected:
                            _status ==
                                'pending',
                        onTap: () {
                          setState(() {
                            _status =
                                'pending';
                          });
                        },
                      ),
                      _ChoiceChipButton(
                        label:
                            'Published',
                        count:
                            widget.counts[
                                'published'],
                        selected:
                            _status ==
                                'published',
                        onTap: () {
                          setState(() {
                            _status =
                                'published';
                          });
                        },
                      ),
                      _ChoiceChipButton(
                        label:
                            'Returned',
                        count:
                            widget.counts[
                                'returned'],
                        selected:
                            _status ==
                                'returned',
                        onTap: () {
                          setState(() {
                            _status =
                                'returned';
                          });
                        },
                      ),
                      _ChoiceChipButton(
                        label:
                            'Sold Out',
                        count:
                            widget.counts[
                                'sold_out'],
                        selected:
                            _status ==
                                'sold_out',
                        onTap: () {
                          setState(() {
                            _status =
                                'sold_out';
                          });
                        },
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  _FilterSection(
                    title: 'Visibility',
                    children: [
                      _ChoiceChipButton(
                        label:
                            'All Visibility',
                        selected:
                            _visibility ==
                                'all',
                        onTap: () {
                          setState(() {
                            _visibility =
                                'all';
                          });
                        },
                      ),
                      _ChoiceChipButton(
                        label: 'Visible',
                        count:
                            widget.counts[
                                'visible'],
                        selected:
                            _visibility ==
                                'visible',
                        onTap: () {
                          setState(() {
                            _visibility =
                                'visible';
                          });
                        },
                      ),
                      _ChoiceChipButton(
                        label: 'Hidden',
                        count:
                            widget.counts[
                                'hidden'],
                        selected:
                            _visibility ==
                                'hidden',
                        onTap: () {
                          setState(() {
                            _visibility =
                                'hidden';
                          });
                        },
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 17,
                  ),

                  Row(
                    children: [
                      Expanded(
                        child:
                            OutlinedButton(
                          onPressed: () {
                            Navigator.pop(
                              context,
                            );
                          },
                          style:
                              OutlinedButton
                                  .styleFrom(
                            minimumSize:
                                const Size
                                    .fromHeight(
                              43,
                            ),
                          ),
                          child:
                              const Text(
                            'Cancel',
                          ),
                        ),
                      ),

                      const SizedBox(
                        width: 10,
                      ),

                      Expanded(
                        child:
                            FilledButton.icon(
                          onPressed:
                              _apply,
                          icon:
                              const Icon(
                            Icons
                                .check_rounded,
                            size: 16,
                          ),
                          label:
                              const Text(
                            'Apply Filters',
                          ),
                          style:
                              FilledButton
                                  .styleFrom(
                            minimumSize:
                                const Size
                                    .fromHeight(
                              43,
                            ),
                            backgroundColor:
                                ProvincialAdminColors
                                    .blue,
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
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            const Color(0xFFF8FAFC),
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color:
              ProvincialAdminColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                const TextStyle(
              color:
                  ProvincialAdminColors
                      .text,
              fontSize: 11,
              fontWeight:
                  FontWeight.w900,
            ),
          ),

          const SizedBox(
            height: 9,
          ),

          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: children,
          ),
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
    return Material(
      color:
          Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(
          999,
        ),
        child:
            AnimatedContainer(
          duration:
              const Duration(
            milliseconds: 140,
          ),
          height: 34,
          padding:
              const EdgeInsets.symmetric(
            horizontal: 11,
          ),
          decoration: BoxDecoration(
            color: selected
                ? ProvincialAdminColors
                    .blue
                : Colors.white,
            borderRadius:
                BorderRadius.circular(
              999,
            ),
            border: Border.all(
              color: selected
                  ? ProvincialAdminColors
                      .blue
                  : ProvincialAdminColors
                      .line,
            ),
          ),
          child: Row(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Text(
                label,
                style:
                    TextStyle(
                  color: selected
                      ? Colors.white
                      : ProvincialAdminColors
                          .muted,
                  fontSize: 9.5,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),

              if (count != null) ...[
                const SizedBox(
                  width: 6,
                ),
                Container(
                  constraints:
                      const BoxConstraints(
                    minWidth: 18,
                  ),
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  alignment:
                      Alignment.center,
                  decoration:
                      BoxDecoration(
                    color: selected
                        ? Colors.white
                            .withValues(
                              alpha: .18,
                            )
                        : _softBlue,
                    borderRadius:
                        BorderRadius.circular(
                      999,
                    ),
                  ),
                  child: Text(
                    '$count',
                    style:
                        TextStyle(
                      color: selected
                          ? Colors.white
                          : ProvincialAdminColors
                              .blue,
                      fontSize: 8,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Package section
// ─────────────────────────────────────────────────────────────────────────────

class _PackageSectionHeader extends StatelessWidget {
  const _PackageSectionHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          'Package Directory',
          style: TextStyle(
            color:
                ProvincialAdminColors.text,
            fontSize: 15,
            fontWeight:
                FontWeight.w900,
          ),
        ),
        SizedBox(height: 3),
        Text(
          'Tour packages submitted and managed by city and municipal tourism offices.',
          style: TextStyle(
            color:
                ProvincialAdminColors.muted,
            fontSize: 10,
            fontWeight:
                FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Package grid
// ─────────────────────────────────────────────────────────────────────────────

class _PackageGrid extends StatelessWidget {
  const _PackageGrid({
    required this.packages,
    required this.onTap,
    required this.onStatus,
    required this.onVisibility,
  });

  final List<ProvincePackage> packages;

  final ValueChanged<ProvincePackage>
      onTap;

  final void Function(
    ProvincePackage package,
    String status,
  ) onStatus;

  final void Function(
    ProvincePackage package,
    String visibility,
  ) onVisibility;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final width =
            constraints.maxWidth;

        final columns =
            width >= 1150
                ? 3
                : width >= 680
                    ? 2
                    : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics:
              const NeverScrollableScrollPhysics(),
          itemCount:
              packages.length,
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                columns,
            crossAxisSpacing:
                12,
            mainAxisSpacing:
                12,

            // Fixed vertical extent gives every package
            // card the same height.
            mainAxisExtent:
                248,
          ),
          itemBuilder:
              (context, index) {
            final package =
                packages[index];

            return _PackageCard(
              package: package,
              onTap: () {
                onTap(package);
              },
              onPublish: () {
                onStatus(
                  package,
                  'published',
                );
              },
              onReturn: () {
                onStatus(
                  package,
                  'returned',
                );
              },
              onDraft: () {
                onStatus(
                  package,
                  'draft',
                );
              },
              onVisible: () {
                onVisibility(
                  package,
                  'visible',
                );
              },
              onHidden: () {
                onVisibility(
                  package,
                  'hidden',
                );
              },
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Package card
// ─────────────────────────────────────────────────────────────────────────────

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
    final visible =
        package.visibilityStatus
                .trim()
                .toLowerCase() ==
            'visible';

    final status =
        package.status
            .trim()
            .toLowerCase();

    final money =
        NumberFormat.currency(
      symbol: '₱',
      decimalDigits: 0,
    );

    final price =
        package.priceText
                .trim()
                .isEmpty
            ? money.format(
                package.estimatedBudget,
              )
            : package.priceText;

    return Material(
      color: Colors.white,
      borderRadius:
          BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(
              16,
            ),
            border: Border.all(
              color:
                  ProvincialAdminColors
                      .line,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black
                        .withValues(
                  alpha: .018,
                ),
                blurRadius: 9,
                offset:
                    const Offset(
                  0,
                  3,
                ),
              ),
            ],
          ),
          clipBehavior:
              Clip.antiAlias,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .stretch,
            children: [
              // ─────────────────────────
              // Header
              // ─────────────────────────

              Padding(
                padding:
                    const EdgeInsets
                        .fromLTRB(
                  13,
                  13,
                  7,
                  10,
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    _PackageImage(
                      url:
                          package.imageUrl,
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            package.title,
                            maxLines: 1,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                const TextStyle(
                              color:
                                  ProvincialAdminColors
                                      .text,
                              fontSize:
                                  13.5,
                              fontWeight:
                                  FontWeight
                                      .w900,
                            ),
                          ),

                          const SizedBox(
                            height: 3,
                          ),

                          Row(
                            children: [
                              const Icon(
                                Icons
                                    .location_city_outlined,
                                size: 12,
                                color:
                                    ProvincialAdminColors
                                        .lightMuted,
                              ),
                              const SizedBox(
                                width: 4,
                              ),
                              Expanded(
                                child: Text(
                                  package.city
                                          .trim()
                                          .isEmpty
                                      ? 'Unassigned LGU'
                                      : package
                                          .city,
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow
                                          .ellipsis,
                                  style:
                                      const TextStyle(
                                    color:
                                        ProvincialAdminColors
                                            .muted,
                                    fontSize:
                                        9.5,
                                    fontWeight:
                                        FontWeight
                                            .w700,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(
                            height: 6,
                          ),

                          Wrap(
                            spacing: 5,
                            runSpacing: 4,
                            children: [
                              _PackageStatusPill(
                                status:
                                    package
                                        .status,
                              ),
                              _PackageVisibilityPill(
                                visible:
                                    visible,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    _PackageMenu(
                      status:
                          status,
                      visible:
                          visible,
                      onView:
                          onTap,
                      onPublish:
                          onPublish,
                      onReturn:
                          onReturn,
                      onDraft:
                          onDraft,
                      onVisible:
                          onVisible,
                      onHidden:
                          onHidden,
                    ),
                  ],
                ),
              ),

              const Divider(
                height: 1,
                color:
                    ProvincialAdminColors
                        .line,
              ),

              // ─────────────────────────
              // Price / duration
              // ─────────────────────────

              Padding(
                padding:
                    const EdgeInsets
                        .fromLTRB(
                  13,
                  9,
                  13,
                  8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child:
                          _PackageInfo(
                        icon: Icons
                            .payments_outlined,
                        label: 'Price',
                        value: price,
                      ),
                    ),

                    Container(
                      width: 1,
                      height: 30,
                      color:
                          ProvincialAdminColors
                              .line,
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child:
                          _PackageInfo(
                        icon: Icons
                            .schedule_outlined,
                        label: 'Duration',
                        value: package
                                .durationText
                                .trim()
                                .isEmpty
                            ? 'Not set'
                            : package
                                .durationText,
                      ),
                    ),
                  ],
                ),
              ),

              // ─────────────────────────
              // Performance metrics
              // ─────────────────────────

              Padding(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 13,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child:
                          _PackageMetric(
                        label: 'Bookings',
                        value:
                            '${package.bookingsCount}',
                        icon: Icons
                            .receipt_long_outlined,
                        color: _purple,
                      ),
                    ),

                    const SizedBox(
                      width: 7,
                    ),

                    Expanded(
                      child:
                          _PackageMetric(
                        label: 'Revenue',
                        value:
                            money.format(
                          package.revenue,
                        ),
                        icon: Icons
                            .account_balance_wallet_outlined,
                        color: _green,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 9,
              ),

              // ─────────────────────────
              // Footer
              // ─────────────────────────

              const Divider(
                height: 1,
                color:
                    ProvincialAdminColors
                        .line,
              ),

              SizedBox(
                height: 36,
                child: TextButton(
                  onPressed:
                      onTap,
                  style:
                      TextButton.styleFrom(
                    foregroundColor:
                        ProvincialAdminColors
                            .blue,
                    shape:
                        const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.zero,
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment:
                        MainAxisAlignment
                            .spaceBetween,
                    children: [
                      Text(
                        'View package details',
                        style:
                            TextStyle(
                          fontSize: 9.5,
                          fontWeight:
                              FontWeight
                                  .w800,
                        ),
                      ),
                      Icon(
                        Icons
                            .arrow_forward_rounded,
                        size: 14,
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Package image
// ─────────────────────────────────────────────────────────────────────────────

class _PackageImage extends StatelessWidget {
  const _PackageImage({
    required this.url,
  });

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 55,
      height: 55,
      clipBehavior:
          Clip.antiAlias,
      decoration: BoxDecoration(
        color: _softBlue,
        borderRadius:
            BorderRadius.circular(11),
        border: Border.all(
          color:
              ProvincialAdminColors.line,
        ),
      ),
      child: url.trim().isEmpty
          ? const Icon(
              Icons
                  .inventory_2_outlined,
              color:
                  ProvincialAdminColors
                      .blue,
              size: 24,
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) {
                return const Icon(
                  Icons
                      .inventory_2_outlined,
                  color:
                      ProvincialAdminColors
                          .blue,
                  size: 24,
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status / visibility pills
// ─────────────────────────────────────────────────────────────────────────────

class _PackageStatusPill extends StatelessWidget {
  const _PackageStatusPill({
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized =
        status
            .trim()
            .toLowerCase();

    final Color color;
    final Color background;
    final IconData icon;

    switch (normalized) {
      case 'published':
        color = _green;
        background =
            _softGreen;
        icon =
            Icons.public_rounded;
        break;

      case 'pending':
        color = _amber;
        background =
            _softAmber;
        icon = Icons
            .pending_actions_rounded;
        break;

      case 'returned':
        color = _red;
        background =
            _softRed;
        icon = Icons
            .assignment_return_outlined;
        break;

      case 'sold_out':
        color = _purple;
        background =
            _softPurple;
        icon = Icons
            .inventory_outlined;
        break;

      default:
        color =
            ProvincialAdminColors
                .muted;
        background =
            const Color(
          0xFFF8FAFC,
        );
        icon =
            Icons.edit_note_rounded;
    }

    return _SmallPill(
      icon: icon,
      label:
          _titleCaseStatus(
        normalized,
      ),
      color: color,
      background:
          background,
    );
  }
}

class _PackageVisibilityPill extends StatelessWidget {
  const _PackageVisibilityPill({
    required this.visible,
  });

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return _SmallPill(
      icon: visible
          ? Icons
              .visibility_outlined
          : Icons
              .visibility_off_outlined,
      label:
          visible
              ? 'Visible'
              : 'Hidden',
      color:
          visible
              ? _cyan
              : _red,
      background:
          visible
              ? _softCyan
              : _softRed,
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;

  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(
          999,
        ),
        border: Border.all(
          color:
              color.withValues(
            alpha: .14,
          ),
        ),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10,
            color: color,
          ),
          const SizedBox(
            width: 4,
          ),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Package info
// ─────────────────────────────────────────────────────────────────────────────

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
        Icon(
          icon,
          size: 13,
          color:
              ProvincialAdminColors
                  .lightMuted,
        ),

        const SizedBox(
          width: 6,
        ),

        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .lightMuted,
                  fontSize: 8,
                  fontWeight:
                      FontWeight.w700,
                ),
              ),

              const SizedBox(
                height: 2,
              ),

              Text(
                value,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .text,
                  fontSize: 9.5,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Package metric
// ─────────────────────────────────────────────────────────────────────────────

class _PackageMetric extends StatelessWidget {
  const _PackageMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;

  final IconData icon;

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 43,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color:
            color.withValues(
          alpha: .07,
        ),
        borderRadius:
            BorderRadius.circular(8),
        border: Border.all(
          color:
              color.withValues(
            alpha: .12,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 13,
            color: color,
          ),

          const SizedBox(
            width: 5,
          ),

          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight:
                        FontWeight.w900,
                    height: 1,
                  ),
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  label,
                  style:
                      const TextStyle(
                    color:
                        ProvincialAdminColors
                            .muted,
                    fontSize: 7.5,
                    fontWeight:
                        FontWeight.w700,
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

// ─────────────────────────────────────────────────────────────────────────────
// Package menu
// ─────────────────────────────────────────────────────────────────────────────

class _PackageMenu extends StatelessWidget {
  const _PackageMenu({
    required this.status,
    required this.visible,
    required this.onView,
    required this.onPublish,
    required this.onReturn,
    required this.onDraft,
    required this.onVisible,
    required this.onHidden,
  });

  final String status;
  final bool visible;

  final VoidCallback onView;
  final VoidCallback onPublish;
  final VoidCallback onReturn;
  final VoidCallback onDraft;
  final VoidCallback onVisible;
  final VoidCallback onHidden;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip:
          'Package actions',
      padding:
          EdgeInsets.zero,
      icon: const Icon(
        Icons.more_horiz_rounded,
        size: 20,
        color:
            ProvincialAdminColors
                .muted,
      ),
      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(
          12,
        ),
      ),
      onSelected:
          (value) {
        switch (value) {
          case 'view':
            onView();
            break;

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
      itemBuilder:
          (_) {
        return [
          const PopupMenuItem(
            value: 'view',
            child:
                _PackageMenuItem(
              icon: Icons
                  .visibility_outlined,
              label:
                  'View details',
            ),
          ),

          const PopupMenuDivider(),

          if (status !=
              'published')
            const PopupMenuItem(
              value:
                  'published',
              child:
                  _PackageMenuItem(
                icon: Icons
                    .public_rounded,
                label:
                    'Publish',
                color: _green,
              ),
            ),

          if (status !=
              'draft')
            const PopupMenuItem(
              value: 'draft',
              child:
                  _PackageMenuItem(
                icon: Icons
                    .edit_note_rounded,
                label:
                    'Move to draft',
              ),
            ),

          if (status !=
              'returned')
            const PopupMenuItem(
              value:
                  'returned',
              child:
                  _PackageMenuItem(
                icon: Icons
                    .assignment_return_outlined,
                label:
                    'Return package',
                color: _amber,
              ),
            ),

          const PopupMenuDivider(),

          if (visible)
            const PopupMenuItem(
              value: 'hidden',
              child:
                  _PackageMenuItem(
                icon: Icons
                    .visibility_off_outlined,
                label:
                    'Hide package',
                color: _red,
              ),
            )
          else
            const PopupMenuItem(
              value: 'visible',
              child:
                  _PackageMenuItem(
                icon: Icons
                    .visibility_outlined,
                label:
                    'Make visible',
                color: _green,
              ),
            ),
        ];
      },
    );
  }
}

class _PackageMenuItem extends StatelessWidget {
  const _PackageMenuItem({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final actualColor =
        color ??
            ProvincialAdminColors
                .muted;

    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: actualColor,
        ),

        const SizedBox(
          width: 9,
        ),

        Text(
          label,
          style: TextStyle(
            color:
                color ??
                    ProvincialAdminColors
                        .text,
            fontSize: 11,
            fontWeight:
                FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Package details dialog
// ─────────────────────────────────────────────────────────────────────────────

class _PackageDetailsDialog extends StatelessWidget {
  const _PackageDetailsDialog({
    required this.package,
    required this.priceText,
    required this.spotsFuture,
  });

  final ProvincePackage package;

  final String priceText;

  final Future<List<String>>
      spotsFuture;

  @override
  Widget build(BuildContext context) {
    final screen =
        MediaQuery.sizeOf(context);

    final status =
        package.status
            .trim()
            .toLowerCase();

    final visible =
        package.visibilityStatus
                .trim()
                .toLowerCase() ==
            'visible';

    final money =
        NumberFormat.currency(
      symbol: '₱',
      decimalDigits: 0,
    );

    return Dialog(
      backgroundColor:
          Colors.transparent,
      insetPadding:
          const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(
          maxWidth: 760,
          maxHeight:
              screen.height * .90,
        ),
        child:
            SingleChildScrollView(
          child: Material(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(
              20,
            ),
            clipBehavior:
                Clip.antiAlias,
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment
                      .stretch,
              children: [
                // ───────────────────────
                // Image
                // ───────────────────────

                _PackageDialogImage(
                  url:
                      package.imageUrl,
                ),

                // ───────────────────────
                // Main content
                // ───────────────────────

                Padding(
                  padding:
                      const EdgeInsets
                          .fromLTRB(
                    20,
                    18,
                    20,
                    20,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Row(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(
                                  package
                                      .title,
                                  style:
                                      const TextStyle(
                                    color:
                                        ProvincialAdminColors
                                            .text,
                                    fontSize:
                                        20,
                                    fontWeight:
                                        FontWeight
                                            .w900,
                                    height:
                                        1.2,
                                  ),
                                ),

                                if (package
                                    .subtitle
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(
                                    height:
                                        5,
                                  ),
                                  Text(
                                    package
                                        .subtitle,
                                    style:
                                        const TextStyle(
                                      color:
                                          ProvincialAdminColors
                                              .muted,
                                      fontSize:
                                          11,
                                      fontWeight:
                                          FontWeight
                                              .w600,
                                      height:
                                          1.4,
                                    ),
                                  ),
                                ],

                                const SizedBox(
                                  height: 8,
                                ),

                                Row(
                                  children: [
                                    const Icon(
                                      Icons
                                          .location_city_outlined,
                                      size:
                                          14,
                                      color:
                                          ProvincialAdminColors
                                              .lightMuted,
                                    ),
                                    const SizedBox(
                                      width:
                                          5,
                                    ),
                                    Text(
                                      package
                                          .city,
                                      style:
                                          const TextStyle(
                                        color:
                                            ProvincialAdminColors
                                                .muted,
                                        fontSize:
                                            10.5,
                                        fontWeight:
                                            FontWeight
                                                .w700,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(
                                  height: 9,
                                ),

                                Wrap(
                                  spacing: 6,
                                  runSpacing:
                                      6,
                                  children: [
                                    _PackageStatusPill(
                                      status:
                                          package
                                              .status,
                                    ),
                                    _PackageVisibilityPill(
                                      visible:
                                          visible,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          IconButton(
                            tooltip:
                                'Close',
                            onPressed: () {
                              Navigator.pop(
                                context,
                              );
                            },
                            icon:
                                const Icon(
                              Icons
                                  .close_rounded,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 20,
                      ),

                      // ─────────────────
                      // Key information
                      // ─────────────────

                      const _DialogSectionTitle(
                        title:
                            'Package Summary',
                        subtitle:
                            'Current package information and performance.',
                      ),

                      const SizedBox(
                        height: 9,
                      ),

                      _PackageDetailGrid(
                        children: [
                          _PackageDetailBlock(
                            icon:
                                Icons.payments_outlined,
                            label:
                                'Price',
                            value:
                                priceText,
                            color:
                                ProvincialAdminColors
                                    .blue,
                          ),
                          _PackageDetailBlock(
                            icon:
                                Icons.schedule_outlined,
                            label:
                                'Duration',
                            value: package
                                    .durationText
                                    .trim()
                                    .isEmpty
                                ? 'Not set'
                                : package
                                    .durationText,
                            color:
                                _amber,
                          ),
                          _PackageDetailBlock(
                            icon:
                                Icons.receipt_long_outlined,
                            label:
                                'Bookings',
                            value:
                                '${package.bookingsCount}',
                            color:
                                _purple,
                          ),
                          _PackageDetailBlock(
                            icon:
                                Icons.account_balance_wallet_outlined,
                            label:
                                'Revenue',
                            value:
                                money.format(
                              package
                                  .revenue,
                            ),
                            color:
                                _green,
                          ),
                        ],
                      ),

                      if (package
                          .description
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(
                          height: 22,
                        ),

                        const _DialogSectionTitle(
                          title:
                              'Description',
                        ),

                        const SizedBox(
                          height: 8,
                        ),

                        Container(
                          width:
                              double.infinity,
                          padding:
                              const EdgeInsets
                                  .all(
                            13,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                const Color(
                              0xFFF8FAFC,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              10,
                            ),
                            border:
                                Border.all(
                              color:
                                  ProvincialAdminColors
                                      .line,
                            ),
                          ),
                          child: Text(
                            package
                                .description,
                            style:
                                const TextStyle(
                              color:
                                  ProvincialAdminColors
                                      .muted,
                              fontSize:
                                  10.5,
                              height:
                                  1.55,
                              fontWeight:
                                  FontWeight
                                      .w600,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(
                        height: 22,
                      ),

                      // ─────────────────
                      // Included spots
                      // ─────────────────

                      const _DialogSectionTitle(
                        title:
                            'Included Tourist Spots',
                        subtitle:
                            'Destinations currently linked to this tour package.',
                      ),

                      const SizedBox(
                        height: 9,
                      ),

                      FutureBuilder<List<String>>(
                        future:
                            spotsFuture,
                        builder:
                            (
                          context,
                          snapshot,
                        ) {
                          if (snapshot.connectionState ==
                              ConnectionState
                                  .waiting) {
                            return const _PackageSpotsLoading();
                          }

                          if (snapshot
                              .hasError) {
                            return const _PackageSpotsMessage(
                              icon: Icons
                                  .error_outline_rounded,
                              message:
                                  'Unable to load the tourist spots included in this package.',
                            );
                          }

                          final spots =
                              snapshot.data ??
                                  const <
                                      String>[];

                          if (spots
                              .isEmpty) {
                            return const _PackageSpotsMessage(
                              icon: Icons
                                  .place_outlined,
                              message:
                                  'No tourist spots are currently linked to this package.',
                            );
                          }

                          return Container(
                            width:
                                double.infinity,
                            decoration:
                                BoxDecoration(
                              color:
                                  const Color(
                                0xFFF8FAFC,
                              ),
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                10,
                              ),
                              border:
                                  Border.all(
                                color:
                                    ProvincialAdminColors
                                        .line,
                              ),
                            ),
                            clipBehavior:
                                Clip.antiAlias,
                            child: Column(
                              children: [
                                for (var i = 0;
                                    i <
                                        spots
                                            .length;
                                    i++) ...[
                                  _PackageSpotRow(
                                    index:
                                        i +
                                            1,
                                    title:
                                        spots[
                                            i],
                                  ),
                                  if (i <
                                      spots.length -
                                          1)
                                    const Divider(
                                      height:
                                          1,
                                      color:
                                          ProvincialAdminColors
                                              .line,
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

                // ───────────────────────
                // Dialog actions
                // ───────────────────────

                Container(
                  padding:
                      const EdgeInsets
                          .all(
                    14,
                  ),
                  decoration:
                      const BoxDecoration(
                    color:
                        Color(
                      0xFFF8FAFC,
                    ),
                    border:
                        Border(
                      top:
                          BorderSide(
                        color:
                            ProvincialAdminColors
                                .line,
                      ),
                    ),
                  ),
                  child:
                      LayoutBuilder(
                    builder:
                        (
                      context,
                      constraints,
                    ) {
                      final narrow =
                          constraints
                                  .maxWidth <
                              480;

                      final visibilityButton =
                          OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            visible
                                ? _PackageDialogAction
                                    .makeHidden
                                : _PackageDialogAction
                                    .makeVisible,
                          );
                        },
                        icon: Icon(
                          visible
                              ? Icons
                                  .visibility_off_outlined
                              : Icons
                                  .visibility_outlined,
                          size: 16,
                        ),
                        label: Text(
                          visible
                              ? 'Hide Package'
                              : 'Make Visible',
                        ),
                      );

                      final statusButton =
                          PopupMenuButton<
                              _PackageDialogAction>(
                        tooltip:
                            'Change package status',
                        onSelected:
                            (action) {
                          Navigator.pop(
                            context,
                            action,
                          );
                        },
                        itemBuilder:
                            (_) {
                          return [
                            if (status !=
                                'published')
                              const PopupMenuItem(
                                value:
                                    _PackageDialogAction
                                        .publish,
                                child:
                                    _PackageMenuItem(
                                  icon: Icons
                                      .public_rounded,
                                  label:
                                      'Publish',
                                  color:
                                      _green,
                                ),
                              ),
                            if (status !=
                                'draft')
                              const PopupMenuItem(
                                value:
                                    _PackageDialogAction
                                        .draft,
                                child:
                                    _PackageMenuItem(
                                  icon: Icons
                                      .edit_note_rounded,
                                  label:
                                      'Move to draft',
                                ),
                              ),
                            if (status !=
                                'returned')
                              const PopupMenuItem(
                                value:
                                    _PackageDialogAction
                                        .returnPackage,
                                child:
                                    _PackageMenuItem(
                                  icon: Icons
                                      .assignment_return_outlined,
                                  label:
                                      'Return package',
                                  color:
                                      _amber,
                                ),
                              ),
                          ];
                        },
                        child:
                            Container(
                          height: 40,
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal:
                                13,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                ProvincialAdminColors
                                    .blue,
                            borderRadius:
                                BorderRadius
                                    .circular(
                              9,
                            ),
                          ),
                          child:
                              const Row(
                            mainAxisSize:
                                MainAxisSize
                                    .min,
                            mainAxisAlignment:
                                MainAxisAlignment
                                    .center,
                            children: [
                              Icon(
                                Icons
                                    .edit_outlined,
                                size:
                                    16,
                                color:
                                    Colors.white,
                              ),
                              SizedBox(
                                width:
                                    6,
                              ),
                              Text(
                                'Change Status',
                                style:
                                    TextStyle(
                                  color:
                                      Colors.white,
                                  fontSize:
                                      10.5,
                                  fontWeight:
                                      FontWeight
                                          .w800,
                                ),
                              ),
                              SizedBox(
                                width:
                                    4,
                              ),
                              Icon(
                                Icons
                                    .keyboard_arrow_down_rounded,
                                size:
                                    16,
                                color:
                                    Colors.white,
                              ),
                            ],
                          ),
                        ),
                      );

                      if (narrow) {
                        return Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .stretch,
                          children: [
                            visibilityButton,
                            const SizedBox(
                              height:
                                  8,
                            ),
                            statusButton,
                            const SizedBox(
                              height:
                                  8,
                            ),
                            TextButton(
                              onPressed:
                                  () {
                                Navigator.pop(
                                  context,
                                );
                              },
                              child:
                                  const Text(
                                'Close',
                              ),
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          TextButton(
                            onPressed:
                                () {
                              Navigator.pop(
                                context,
                              );
                            },
                            child:
                                const Text(
                              'Close',
                            ),
                          ),

                          const Spacer(),

                          visibilityButton,

                          const SizedBox(
                            width: 8,
                          ),

                          statusButton,
                        ],
                      );
                    },
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

// ─────────────────────────────────────────────────────────────────────────────
// Dialog image
// ─────────────────────────────────────────────────────────────────────────────

class _PackageDialogImage extends StatelessWidget {
  const _PackageDialogImage({
    required this.url,
  });

  final String url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 185,
      child: url.trim().isEmpty
          ? Container(
              color: _softBlue,
              alignment:
                  Alignment.center,
              child: const Icon(
                Icons
                    .inventory_2_outlined,
                size: 52,
                color:
                    ProvincialAdminColors
                        .blue,
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) {
                return Container(
                  color:
                      _softBlue,
                  alignment:
                      Alignment.center,
                  child:
                      const Icon(
                    Icons
                        .inventory_2_outlined,
                    size: 52,
                    color:
                        ProvincialAdminColors
                            .blue,
                  ),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog sections
// ─────────────────────────────────────────────────────────────────────────────

class _DialogSectionTitle extends StatelessWidget {
  const _DialogSectionTitle({
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
              const TextStyle(
            color:
                ProvincialAdminColors
                    .text,
            fontSize: 12,
            fontWeight:
                FontWeight.w900,
          ),
        ),

        if (subtitle != null) ...[
          const SizedBox(
            height: 3,
          ),
          Text(
            subtitle!,
            style:
                const TextStyle(
              color:
                  ProvincialAdminColors
                      .muted,
              fontSize: 9.5,
              fontWeight:
                  FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog detail grid
// ─────────────────────────────────────────────────────────────────────────────

class _PackageDetailGrid extends StatelessWidget {
  const _PackageDetailGrid({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        if (constraints.maxWidth <
            500) {
          return Column(
            children:
                children.map(
              (child) {
                return Padding(
                  padding:
                      const EdgeInsets
                          .only(
                    bottom: 8,
                  ),
                  child: child,
                );
              },
            ).toList(),
          );
        }

        const gap = 8.0;

        final width =
            (constraints.maxWidth -
                    gap) /
                2;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children:
              children.map(
            (child) {
              return SizedBox(
                width: width,
                child: child,
              );
            },
          ).toList(),
        );
      },
    );
  }
}

class _PackageDetailBlock extends StatelessWidget {
  const _PackageDetailBlock({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;

  final String label;
  final String value;

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            const Color(0xFFF8FAFC),
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color:
              ProvincialAdminColors.line,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color:
                  color.withValues(
                alpha: .08,
              ),
              borderRadius:
                  BorderRadius.circular(
                8,
              ),
            ),
            child: Icon(
              icon,
              color: color,
              size: 16,
            ),
          ),

          const SizedBox(
            width: 9,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style:
                      const TextStyle(
                    color:
                        ProvincialAdminColors
                            .lightMuted,
                    fontSize: 8.5,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  value,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                    color:
                        ProvincialAdminColors
                            .text,
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w900,
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

// ─────────────────────────────────────────────────────────────────────────────
// Included spots
// ─────────────────────────────────────────────────────────────────────────────

class _PackageSpotsLoading extends StatelessWidget {
  const _PackageSpotsLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:
            const Color(0xFFF8FAFC),
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color:
              ProvincialAdminColors.line,
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child:
              CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}

class _PackageSpotsMessage extends StatelessWidget {
  const _PackageSpotsMessage({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color:
            const Color(0xFFF8FAFC),
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color:
              ProvincialAdminColors.line,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color:
                ProvincialAdminColors
                    .lightMuted,
          ),

          const SizedBox(
            width: 8,
          ),

          Expanded(
            child: Text(
              message,
              style:
                  const TextStyle(
                color:
                    ProvincialAdminColors
                        .muted,
                fontSize: 10,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageSpotRow extends StatelessWidget {
  const _PackageSpotRow({
    required this.index,
    required this.title,
  });

  final int index;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      child: Row(
        children: [
          Container(
            width: 25,
            height: 25,
            alignment:
                Alignment.center,
            decoration: BoxDecoration(
              color: _softBlue,
              borderRadius:
                  BorderRadius.circular(
                999,
              ),
            ),
            child: Text(
              '$index',
              style:
                  const TextStyle(
                color:
                    ProvincialAdminColors
                        .blue,
                fontSize: 9,
                fontWeight:
                    FontWeight.w900,
              ),
            ),
          ),

          const SizedBox(
            width: 9,
          ),

          const Icon(
            Icons.place_outlined,
            color:
                ProvincialAdminColors
                    .lightMuted,
            size: 15,
          ),

          const SizedBox(
            width: 6,
          ),

          Expanded(
            child: Text(
              title,
              style:
                  const TextStyle(
                color:
                    ProvincialAdminColors
                        .text,
                fontSize: 10.5,
                fontWeight:
                    FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _PackageEmptyState extends StatelessWidget {
  const _PackageEmptyState({
    required this.hasFilters,
    required this.onClear,
  });

  final bool hasFilters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (!hasFilters) {
      return const AdminEmptyState(
        icon:
            Icons.inventory_2_outlined,
        title:
            'No packages found',
        message:
            'Tour packages submitted by city tenants will appear here.',
      );
    }

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 40,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(15),
        border: Border.all(
          color:
              ProvincialAdminColors.line,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color:
                  ProvincialAdminColors
                      .blue
                      .withValues(
                alpha: .08,
              ),
              shape:
                  BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color:
                  ProvincialAdminColors
                      .blue,
              size: 23,
            ),
          ),

          const SizedBox(
            height: 11,
          ),

          const Text(
            'No matching packages',
            style: TextStyle(
              color:
                  ProvincialAdminColors
                      .text,
              fontSize: 14,
              fontWeight:
                  FontWeight.w900,
            ),
          ),

          const SizedBox(
            height: 5,
          ),

          const Text(
            'Try changing your search or clearing one of the active filters.',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  ProvincialAdminColors
                      .muted,
              fontSize: 10,
              height: 1.4,
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(
              Icons
                  .filter_alt_off_rounded,
              size: 15,
            ),
            label:
                const Text(
              'Clear Filters',
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _titleCaseStatus(
  String value,
) {
  final clean = value
      .trim()
      .replaceAll(
        '_',
        ' ',
      );

  if (clean.isEmpty) {
    return 'Unknown';
  }

  return clean.split(' ').map(
    (word) {
      if (word.isEmpty) {
        return word;
      }

      return '${word[0].toUpperCase()}'
          '${word.substring(1).toLowerCase()}';
    },
  ).join(' ');
}