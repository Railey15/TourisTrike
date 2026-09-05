import 'package:flutter/material.dart';

import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/admin_empty_state.dart';
import 'package:touristrike/screens/admin/widgets/admin_status_pill.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Local colors
// ─────────────────────────────────────────────────────────────────────────────

const _pageBackground = Color(0xFFF4F7FB);
const _softBlue = Color(0xFFF3F8FF);
const _softGreen = Color(0xFFF0FDF4);
const _softAmber = Color(0xFFFFFBEB);
const _softRed = Color(0xFFFEF2F2);
const _softPurple = Color(0xFFF7F3FF);

const _green = Color(0xFF16A34A);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFDC2626);
const _purple = Color(0xFF7C3AED);
const _cyan = Color(0xFF0EA5E9);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class ProvincialSpotsScreen extends StatefulWidget {
  const ProvincialSpotsScreen({
    super.key,
    this.initialSearch = '',
  });

  final String initialSearch;

  @override
  State<ProvincialSpotsScreen> createState() =>
      _ProvincialSpotsScreenState();
}

class _ProvincialSpotsScreenState extends State<ProvincialSpotsScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();
  final TextEditingController _searchCtrl = TextEditingController();

  late Future<List<ProvinceSpot>> _future;

  String _cityFilter = 'all';
  String _spotStatusFilter = 'all';
  String _verificationFilter = 'all';

  // ───────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ───────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _searchCtrl.text = widget.initialSearch;
    _future = _service.fetchProvinceSpots();

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
      _future = _service.fetchProvinceSpots();
    });

    await _future;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Filtering
  // ───────────────────────────────────────────────────────────────────────────

  bool get _hasActiveFilters {
    return _searchCtrl.text.trim().isNotEmpty ||
        _cityFilter != 'all' ||
        _spotStatusFilter != 'all' ||
        _verificationFilter != 'all';
  }

  void _clearFilters() {
    setState(() {
      _searchCtrl.clear();
      _cityFilter = 'all';
      _spotStatusFilter = 'all';
      _verificationFilter = 'all';
    });
  }

  List<ProvinceSpot> _filtered(List<ProvinceSpot> spots) {
    final query = _searchCtrl.text.trim().toLowerCase();

    return spots.where((spot) {
      final city = spot.city.trim();
      final status = spot.status.trim().toLowerCase();
      final verification =
          spot.verificationStatus.trim().toLowerCase();

      final matchesCity =
          _cityFilter == 'all' || city == _cityFilter;

      final matchesStatus =
          _spotStatusFilter == 'all' ||
          status == _spotStatusFilter;

      final matchesVerification =
          _verificationFilter == 'all' ||
          (_verificationFilter == 'verified' &&
              verification == 'verified') ||
          (_verificationFilter == 'flagged' &&
              verification == 'flagged') ||
          (_verificationFilter == 'unverified' &&
              verification != 'verified' &&
              verification != 'flagged');

      if (!matchesCity ||
          !matchesStatus ||
          !matchesVerification) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final searchable = [
        spot.title,
        spot.description,
        spot.city,
        spot.barangay,
        spot.status,
        spot.verificationStatus,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList(growable: false);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Spot details / moderation
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _showSpotDetails(
    ProvinceSpot spot,
  ) async {
    final action = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .32),
      builder: (context) {
        return _SpotDetailsDialog(
          spot: spot,
        );
      },
    );

    if (action == null || !mounted) {
      return;
    }

    await _moderateSpot(
      spot,
      action,
    );
  }

  Future<void> _moderateSpot(
    ProvinceSpot spot,
    String action,
  ) async {
    final verb = switch (action) {
      'verify' => 'verify',
      'flag' => 'flag',
      'archive' => 'archive',
      'unarchive' => 'restore',
      _ => action,
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            '${_titleCase(verb)} tourist spot?',
          ),
          content: Text(
            'This will $verb "${spot.title}" for ${spot.city}.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: Text(
                _titleCase(verb),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      switch (action) {
        case 'verify':
          await _service.verifySpot(spot);
          break;

        case 'flag':
          await _service.flagSpot(spot);
          break;

        case 'archive':
          await _service.archiveSpot(spot);
          break;

        case 'unarchive':
          await _service.unarchiveSpot(spot);
          break;
      }

      if (!mounted) {
        return;
      }

      showAdminSnack(
        context,
        'Tourist spot updated.',
        error: false,
      );

      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }

      showAdminSnack(
        context,
        'Unable to update tourist spot: $error',
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return ProvincialAdminShell(
      current: ProvincialAdminDestination.tourismData,
      title: 'Tourism Data',
      subtitle:
          'Review, verify, and manage tourist spots submitted by city tenants.',
      child: FutureBuilder<List<ProvinceSpot>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const AdminLoadingView();
          }

          if (snapshot.hasError) {
            return AdminErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final allSpots =
              snapshot.data ?? const <ProvinceSpot>[];

          final spots = _filtered(allSpots);

          final cities = allSpots
              .map((spot) => spot.city.trim())
              .where((city) => city.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

          final activeCount = allSpots.where((spot) {
            return spot.status.trim().toLowerCase() ==
                'active';
          }).length;

          final verifiedCount = allSpots.where((spot) {
            return spot.verificationStatus
                    .trim()
                    .toLowerCase() ==
                'verified';
          }).length;

          final flaggedCount = allSpots.where((spot) {
            return spot.verificationStatus
                    .trim()
                    .toLowerCase() ==
                'flagged';
          }).length;

          final ratedSpots = allSpots
              .where(
                (spot) => spot.rating > 0,
              )
              .toList();

          final averageRating = ratedSpots.isEmpty
              ? 0.0
              : ratedSpots.fold<double>(
                    0,
                    (sum, spot) =>
                        sum + spot.rating,
                  ) /
                  ratedSpots.length;

          return ColoredBox(
            color: _pageBackground,
            child: RefreshIndicator(
              onRefresh: _reload,
              child: SingleChildScrollView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  mobile ? 14 : 22,
                  mobile ? 14 : 18,
                  mobile ? 14 : 22,
                  32,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    _PageSummaryHeader(
                      total: allSpots.length,
                      filtered: spots.length,
                      hasActiveFilters:
                          _hasActiveFilters,
                    ),

                    const SizedBox(height: 14),

                    _StatisticsGrid(
                      total: allSpots.length,
                      active: activeCount,
                      verified: verifiedCount,
                      flagged: flaggedCount,
                      averageRating:
                          averageRating,
                    ),

                    const SizedBox(height: 16),

                    _SpotToolbar(
                      searchController:
                          _searchCtrl,
                      cities: cities,
                      cityFilter:
                          _cityFilter,
                      spotStatusFilter:
                          _spotStatusFilter,
                      verificationFilter:
                          _verificationFilter,
                      hasActiveFilters:
                          _hasActiveFilters,
                      resultCount:
                          spots.length,
                      totalCount:
                          allSpots.length,
                      onCityChanged:
                          (value) {
                        setState(() {
                          _cityFilter =
                              value ?? 'all';
                        });
                      },
                      onStatusChanged:
                          (value) {
                        setState(() {
                          _spotStatusFilter =
                              value ?? 'all';
                        });
                      },
                      onVerificationChanged:
                          (value) {
                        setState(() {
                          _verificationFilter =
                              value ?? 'all';
                        });
                      },
                      onClearFilters:
                          _clearFilters,
                    ),

                    const SizedBox(height: 18),

                    if (spots.isEmpty)
                      _NoResultsState(
                        hasFilters:
                            _hasActiveFilters,
                        onClearFilters:
                            _clearFilters,
                      )
                    else
                      _SpotGrid(
                        spots: spots,
                        onViewDetails:
                            _showSpotDetails,
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
// Page summary
// ─────────────────────────────────────────────────────────────────────────────

class _PageSummaryHeader extends StatelessWidget {
  const _PageSummaryHeader({
    required this.total,
    required this.filtered,
    required this.hasActiveFilters,
  });

  final int total;
  final int filtered;
  final bool hasActiveFilters;

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        mobile ? 16 : 18,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: ProvincialAdminColors.line,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: .025,
            ),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: mobile
          ? Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _SummaryIdentity(),
                const SizedBox(height: 12),
                _ResultBadge(
                  total: total,
                  filtered: filtered,
                  hasActiveFilters:
                      hasActiveFilters,
                ),
              ],
            )
          : Row(
              children: [
                const Expanded(
                  child: _SummaryIdentity(),
                ),
                const SizedBox(width: 18),
                _ResultBadge(
                  total: total,
                  filtered: filtered,
                  hasActiveFilters:
                      hasActiveFilters,
                ),
              ],
            ),
    );
  }
}

class _SummaryIdentity extends StatelessWidget {
  const _SummaryIdentity();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: ProvincialAdminColors.blue
                .withValues(alpha: .09),
            borderRadius:
                BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.travel_explore_rounded,
            color: ProvincialAdminColors.blue,
            size: 23,
          ),
        ),
        const SizedBox(width: 13),
        const Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'Tourist Spot Management',
                style: TextStyle(
                  color:
                      ProvincialAdminColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.25,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Review tourism information submitted by municipal and city tourism offices.',
                maxLines: 2,
                overflow:
                    TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      ProvincialAdminColors.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({
    required this.total,
    required this.filtered,
    required this.hasActiveFilters,
  });

  final int total;
  final int filtered;
  final bool hasActiveFilters;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: hasActiveFilters
            ? ProvincialAdminColors.blue
                .withValues(alpha: .08)
            : const Color(0xFFF8FAFC),
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color: hasActiveFilters
              ? ProvincialAdminColors.blue
                  .withValues(alpha: .18)
              : ProvincialAdminColors.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasActiveFilters
                ? Icons.filter_alt_outlined
                : Icons.place_outlined,
            size: 16,
            color: hasActiveFilters
                ? ProvincialAdminColors.blue
                : ProvincialAdminColors.muted,
          ),
          const SizedBox(width: 7),
          Text(
            hasActiveFilters
                ? '$filtered of $total shown'
                : '$total tourist spots',
            style: TextStyle(
              color: hasActiveFilters
                  ? ProvincialAdminColors
                      .deepBlue
                  : ProvincialAdminColors
                      .muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Statistics
// ─────────────────────────────────────────────────────────────────────────────

class _StatisticsGrid extends StatelessWidget {
  const _StatisticsGrid({
    required this.total,
    required this.active,
    required this.verified,
    required this.flagged,
    required this.averageRating,
  });

  final int total;
  final int active;
  final int verified;
  final int flagged;
  final double averageRating;

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatData(
        label: 'Total Spots',
        value: '$total',
        helper: 'Province records',
        icon: Icons.place_outlined,
        color: ProvincialAdminColors.blue,
        background: _softBlue,
      ),
      _StatData(
        label: 'Active',
        value: '$active',
        helper: 'Currently available',
        icon: Icons.public_rounded,
        color: _green,
        background: _softGreen,
      ),
      _StatData(
        label: 'Verified',
        value: '$verified',
        helper: 'Approved records',
        icon: Icons.verified_outlined,
        color: _cyan,
        background:
            const Color(0xFFF0F9FF),
      ),
      _StatData(
        label: 'Flagged',
        value: '$flagged',
        helper: flagged == 0
            ? 'No issues reported'
            : 'Requires review',
        icon: Icons.flag_outlined,
        color: _red,
        background: _softRed,
      ),
      _StatData(
        label: 'Average Rating',
        value: averageRating <= 0
            ? '—'
            : averageRating
                .toStringAsFixed(1),
        helper: averageRating <= 0
            ? 'No ratings yet'
            : 'Rated destinations',
        icon: Icons.star_outline_rounded,
        color: _amber,
        background: _softAmber,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final columns = width >= 1100
            ? 5
            : width >= 760
                ? 3
                : width >= 480
                    ? 2
                    : 1;

        const gap = 10.0;

        final cardWidth =
            (width - ((columns - 1) * gap)) /
                columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items.map((item) {
            return SizedBox(
              width: cardWidth,
              child: _StatCard(
                item: item,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _StatData {
  const _StatData({
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.item,
  });

  final _StatData item;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          const BoxConstraints(
        minHeight: 94,
      ),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(15),
        border: Border.all(
          color: ProvincialAdminColors.line,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: .022,
            ),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: item.background,
              borderRadius:
                  BorderRadius.circular(11),
            ),
            child: Icon(
              item.icon,
              color: item.color,
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    color:
                        ProvincialAdminColors
                            .muted,
                    fontSize: 9.5,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.value,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    color:
                        ProvincialAdminColors
                            .text,
                    fontSize: 19,
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: -.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.helper,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    color:
                        ProvincialAdminColors
                            .lightMuted,
                    fontSize: 8.5,
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

class _SpotToolbar extends StatelessWidget {
  const _SpotToolbar({
    required this.searchController,
    required this.cities,
    required this.cityFilter,
    required this.spotStatusFilter,
    required this.verificationFilter,
    required this.hasActiveFilters,
    required this.resultCount,
    required this.totalCount,
    required this.onCityChanged,
    required this.onStatusChanged,
    required this.onVerificationChanged,
    required this.onClearFilters,
  });

  final TextEditingController searchController;

  final List<String> cities;

  final String cityFilter;
  final String spotStatusFilter;
  final String verificationFilter;

  final bool hasActiveFilters;

  final int resultCount;
  final int totalCount;

  final ValueChanged<String?>
      onCityChanged;
  final ValueChanged<String?>
      onStatusChanged;
  final ValueChanged<String?>
      onVerificationChanged;

  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: ProvincialAdminColors.line,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow =
              constraints.maxWidth < 850;

          if (narrow) {
            return Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                _SearchField(
                  controller:
                      searchController,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: constraints
                                  .maxWidth >=
                              580
                          ? 180
                          : constraints
                              .maxWidth,
                      child: _FilterDropdown<
                          String>(
                        label: 'City',
                        value: cityFilter,
                        icon: Icons
                            .location_city_outlined,
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text(
                              'All Cities',
                            ),
                          ),
                          ...cities.map(
                            (city) =>
                                DropdownMenuItem(
                              value: city,
                              child: Text(
                                city,
                                overflow:
                                    TextOverflow
                                        .ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged:
                            onCityChanged,
                      ),
                    ),
                    SizedBox(
                      width: constraints
                                  .maxWidth >=
                              580
                          ? 180
                          : constraints
                              .maxWidth,
                      child: _FilterDropdown<
                          String>(
                        label:
                            'Spot Status',
                        value:
                            spotStatusFilter,
                        icon: Icons
                            .toggle_on_outlined,
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child:
                                Text('All Status'),
                          ),
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value:
                                'maintenance',
                            child:
                                Text('Maintenance'),
                          ),
                          DropdownMenuItem(
                            value: 'archived',
                            child:
                                Text('Archived'),
                          ),
                        ],
                        onChanged:
                            onStatusChanged,
                      ),
                    ),
                    SizedBox(
                      width: constraints
                                  .maxWidth >=
                              580
                          ? 190
                          : constraints
                              .maxWidth,
                      child: _FilterDropdown<
                          String>(
                        label:
                            'Verification',
                        value:
                            verificationFilter,
                        icon: Icons
                            .verified_outlined,
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text(
                              'All Verification',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'verified',
                            child:
                                Text('Verified'),
                          ),
                          DropdownMenuItem(
                            value:
                                'unverified',
                            child:
                                Text('Unverified'),
                          ),
                          DropdownMenuItem(
                            value: 'flagged',
                            child:
                                Text('Flagged'),
                          ),
                        ],
                        onChanged:
                            onVerificationChanged,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ToolbarBottomRow(
                  hasActiveFilters:
                      hasActiveFilters,
                  resultCount:
                      resultCount,
                  totalCount:
                      totalCount,
                  onClearFilters:
                      onClearFilters,
                ),
              ],
            );
          }

          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SearchField(
                      controller:
                          searchController,
                    ),
                  ),
                  const SizedBox(width: 9),
                  SizedBox(
                    width: 170,
                    child: _FilterDropdown<
                        String>(
                      label: 'City',
                      value: cityFilter,
                      icon: Icons
                          .location_city_outlined,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            'All Cities',
                          ),
                        ),
                        ...cities.map(
                          (city) =>
                              DropdownMenuItem(
                            value: city,
                            child: Text(
                              city,
                              overflow:
                                  TextOverflow
                                      .ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged:
                          onCityChanged,
                    ),
                  ),
                  const SizedBox(width: 9),
                  SizedBox(
                    width: 170,
                    child: _FilterDropdown<
                        String>(
                      label: 'Spot Status',
                      value:
                          spotStatusFilter,
                      icon: Icons
                          .toggle_on_outlined,
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child:
                              Text('All Status'),
                        ),
                        DropdownMenuItem(
                          value: 'active',
                          child: Text('Active'),
                        ),
                        DropdownMenuItem(
                          value:
                              'maintenance',
                          child:
                              Text('Maintenance'),
                        ),
                        DropdownMenuItem(
                          value: 'archived',
                          child:
                              Text('Archived'),
                        ),
                      ],
                      onChanged:
                          onStatusChanged,
                    ),
                  ),
                  const SizedBox(width: 9),
                  SizedBox(
                    width: 190,
                    child: _FilterDropdown<
                        String>(
                      label: 'Verification',
                      value:
                          verificationFilter,
                      icon: Icons
                          .verified_outlined,
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            'All Verification',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'verified',
                          child:
                              Text('Verified'),
                        ),
                        DropdownMenuItem(
                          value:
                              'unverified',
                          child:
                              Text('Unverified'),
                        ),
                        DropdownMenuItem(
                          value: 'flagged',
                          child:
                              Text('Flagged'),
                        ),
                      ],
                      onChanged:
                          onVerificationChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ToolbarBottomRow(
                hasActiveFilters:
                    hasActiveFilters,
                resultCount: resultCount,
                totalCount: totalCount,
                onClearFilters:
                    onClearFilters,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ToolbarBottomRow extends StatelessWidget {
  const _ToolbarBottomRow({
    required this.hasActiveFilters,
    required this.resultCount,
    required this.totalCount,
    required this.onClearFilters,
  });

  final bool hasActiveFilters;
  final int resultCount;
  final int totalCount;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 14,
          color:
              ProvincialAdminColors.lightMuted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            hasActiveFilters
                ? 'Showing $resultCount of $totalCount tourist spots'
                : '$totalCount tourist spots available for provincial review',
            style: const TextStyle(
              color:
                  ProvincialAdminColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (hasActiveFilters)
          TextButton.icon(
            onPressed: onClearFilters,
            icon: const Icon(
              Icons.close_rounded,
              size: 15,
            ),
            label: const Text(
              'Clear Filters',
            ),
            style: TextButton.styleFrom(
              foregroundColor:
                  ProvincialAdminColors
                      .deepBlue,
              visualDensity:
                  VisualDensity.compact,
              textStyle:
                  const TextStyle(
                fontSize: 10.5,
                fontWeight:
                    FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
  });

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        textInputAction:
            TextInputAction.search,
        decoration: InputDecoration(
          hintText:
              'Search tourist spot, city, barangay...',
          hintStyle: const TextStyle(
            color:
                ProvincialAdminColors
                    .lightMuted,
            fontWeight: FontWeight.w600,
            fontSize: 11.5,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color:
                ProvincialAdminColors
                    .lightMuted,
            size: 19,
          ),
          suffixIcon:
              controller.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      onPressed:
                          controller.clear,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 17,
                      ),
                    )
                  : null,
          filled: true,
          fillColor:
              const Color(0xFFF8FAFC),
          contentPadding:
              const EdgeInsets.symmetric(
            horizontal: 12,
          ),
          border:
              OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(10),
            borderSide:
                const BorderSide(
              color:
                  ProvincialAdminColors
                      .line,
            ),
          ),
          enabledBorder:
              OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(10),
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
                BorderRadius.circular(10),
            borderSide:
                const BorderSide(
              color:
                  ProvincialAdminColors
                      .blue,
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final IconData icon;

  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 18,
      ),
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color:
              ProvincialAdminColors.muted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(
          icon,
          size: 16,
          color:
              ProvincialAdminColors
                  .lightMuted,
        ),
        filled: true,
        fillColor:
            const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 7,
        ),
        enabledBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(10),
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
              BorderRadius.circular(10),
          borderSide:
              const BorderSide(
            color:
                ProvincialAdminColors
                    .blue,
            width: 1.2,
          ),
        ),
      ),
      style: const TextStyle(
        color: ProvincialAdminColors.text,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid
// ─────────────────────────────────────────────────────────────────────────────

class _SpotGrid extends StatelessWidget {
  const _SpotGrid({
    required this.spots,
    required this.onViewDetails,
  });

  final List<ProvinceSpot> spots;
  final ValueChanged<ProvinceSpot>
      onViewDetails;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final columns = width >= 1180
            ? 3
            : width >= 680
                ? 2
                : 1;

        const spacing = 12.0;

        final itemWidth =
            (width -
                    ((columns - 1) *
                        spacing)) /
                columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: spots.map((spot) {
            return SizedBox(
              width: itemWidth,
              child: _SpotCard(
                spot: spot,
                onViewDetails: () {
                  onViewDetails(spot);
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Spot card
// ─────────────────────────────────────────────────────────────────────────────

class _SpotCard extends StatelessWidget {
  const _SpotCard({
    required this.spot,
    required this.onViewDetails,
  });

  final ProvinceSpot spot;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final verification =
        spot.verificationStatus
            .trim()
            .toLowerCase();

    final isVerified =
        verification == 'verified';

    final isFlagged =
        verification == 'flagged';

    return Material(
      color: Colors.white,
      borderRadius:
          BorderRadius.circular(17),
      child: InkWell(
        onTap: onViewDetails,
        borderRadius:
            BorderRadius.circular(17),
        child: Container(
          constraints:
              const BoxConstraints(
            minHeight: 210,
          ),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(17),
            border: Border.all(
              color:
                  ProvincialAdminColors.line,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: .022),
                blurRadius: 10,
                offset:
                    const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              // ───────────────────────────────
              // Main information
              // ───────────────────────────────

              Padding(
                padding:
                    const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    _SpotImage(
                      url: spot.imageUrl,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            spot.title,
                            maxLines: 2,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                const TextStyle(
                              color:
                                  ProvincialAdminColors
                                      .text,
                              fontSize: 14,
                              fontWeight:
                                  FontWeight
                                      .w900,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(
                            height: 5,
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons
                                    .location_city_outlined,
                                size: 13,
                                color:
                                    ProvincialAdminColors
                                        .lightMuted,
                              ),
                              const SizedBox(
                                width: 4,
                              ),
                              Expanded(
                                child: Text(
                                  spot.city
                                          .trim()
                                          .isEmpty
                                      ? 'Unassigned city'
                                      : spot.city,
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
                                        10.5,
                                    fontWeight:
                                        FontWeight
                                            .w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(
                            height: 8,
                          ),
                          AdminStatusPill(
                            status:
                                spot.status,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(
                height: 1,
                color:
                    ProvincialAdminColors.line,
              ),

              // ───────────────────────────────
              // Metadata
              // ───────────────────────────────

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  14,
                  12,
                  14,
                  12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _SpotInfo(
                        icon: Icons
                            .place_outlined,
                        label: 'Barangay',
                        value: spot.barangay
                                .trim()
                                .isEmpty
                            ? 'Not specified'
                            : spot.barangay,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 34,
                      color:
                          ProvincialAdminColors
                              .line,
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child: _SpotInfo(
                        icon: Icons
                            .star_outline_rounded,
                        label: 'Rating',
                        value:
                            spot.rating <= 0
                                ? 'No rating'
                                : '${spot.rating.toStringAsFixed(1)} / 5',
                      ),
                    ),
                  ],
                ),
              ),

              // ───────────────────────────────
              // Verification status
              // ───────────────────────────────

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  14,
                  0,
                  14,
                  13,
                ),
                child:
                    _VerificationStatusBar(
                  verified: isVerified,
                  flagged: isFlagged,
                  rawStatus:
                      spot.verificationStatus,
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
// Spot image
// ─────────────────────────────────────────────────────────────────────────────

class _SpotImage extends StatelessWidget {
  const _SpotImage({
    required this.url,
  });

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius:
            BorderRadius.circular(13),
        border: Border.all(
          color: ProvincialAdminColors.line,
        ),
      ),
      child: url.trim().isEmpty
          ? const _ImageFallback()
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) {
                return const _ImageFallback();
              },
              loadingBuilder: (
                context,
                child,
                progress,
              ) {
                if (progress == null) {
                  return child;
                }

                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.travel_explore_rounded,
        color: ProvincialAdminColors.blue,
        size: 28,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metadata
// ─────────────────────────────────────────────────────────────────────────────

class _SpotInfo extends StatelessWidget {
  const _SpotInfo({
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
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius:
                BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            color:
                ProvincialAdminColors
                    .lightMuted,
            size: 14,
          ),
        ),
        const SizedBox(width: 7),
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
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .text,
                  fontSize: 10,
                  fontWeight:
                      FontWeight.w700,
                  height: 1.25,
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
// Verification bar
// ─────────────────────────────────────────────────────────────────────────────

class _VerificationStatusBar
    extends StatelessWidget {
  const _VerificationStatusBar({
    required this.verified,
    required this.flagged,
    required this.rawStatus,
  });

  final bool verified;
  final bool flagged;
  final String rawStatus;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final Color background;
    final IconData icon;
    final String title;
    final String subtitle;

    if (flagged) {
      color = _red;
      background = _softRed;
      icon = Icons.flag_rounded;
      title = 'Flagged';
      subtitle = 'Requires provincial review';
    } else if (verified) {
      color = _green;
      background = _softGreen;
      icon = Icons.verified_rounded;
      title = 'Verified';
      subtitle = 'Approved tourism data';
    } else {
      color = _amber;
      background = _softAmber;
      icon = Icons.pending_actions_rounded;
      title = rawStatus.trim().isEmpty
          ? 'Pending'
          : _titleCase(
              rawStatus
                  .replaceAll('_', ' '),
            );
      subtitle = 'Awaiting verification';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color:
              color.withValues(alpha: .16),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title  ',
                    style: TextStyle(
                      color: color,
                      fontSize: 10.5,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: subtitle,
                    style:
                        const TextStyle(
                      color:
                          ProvincialAdminColors
                              .muted,
                      fontSize: 9.5,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color:
                ProvincialAdminColors
                    .lightMuted,
            size: 17,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// No-results state
// ─────────────────────────────────────────────────────────────────────────────

class _NoResultsState extends StatelessWidget {
  const _NoResultsState({
    required this.hasFilters,
    required this.onClearFilters,
  });

  final bool hasFilters;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    if (!hasFilters) {
      return const AdminEmptyState(
        icon: Icons.travel_explore_outlined,
        title: 'No tourist spots yet',
        message:
            'Tourist spots submitted by city tenants will appear here for provincial review.',
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 42,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: ProvincialAdminColors.line,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: ProvincialAdminColors.blue
                  .withValues(alpha: .08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color:
                  ProvincialAdminColors.blue,
              size: 25,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No matching tourist spots',
            style: TextStyle(
              color:
                  ProvincialAdminColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Try changing your search term or removing one of the active filters.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  ProvincialAdminColors.muted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onClearFilters,
            icon: const Icon(
              Icons.filter_alt_off_rounded,
              size: 16,
            ),
            label:
                const Text('Clear Filters'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Details dialog
// ─────────────────────────────────────────────────────────────────────────────

class _SpotDetailsDialog extends StatelessWidget {
  const _SpotDetailsDialog({
    required this.spot,
  });

  final ProvinceSpot spot;

  @override
  Widget build(BuildContext context) {
    final verification =
        spot.verificationStatus
            .trim()
            .toLowerCase();

    final verified =
        verification == 'verified';

    final flagged =
        verification == 'flagged';

    final archived =
        spot.status.trim().toLowerCase() ==
            'archived';

    final screenWidth =
        MediaQuery.sizeOf(context).width;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight:
              MediaQuery.sizeOf(context)
                      .height *
                  .90,
        ),
        child: Material(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─────────────────────────────
              // Dialog header
              // ─────────────────────────────

              Container(
                padding:
                    const EdgeInsets.fromLTRB(
                  20,
                  16,
                  14,
                  16,
                ),
                decoration:
                    const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color:
                          ProvincialAdminColors
                              .line,
                    ),
                  ),
                ),
                child: Row(
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
                                .circular(10),
                      ),
                      child:
                          const Icon(
                        Icons
                            .travel_explore_rounded,
                        color:
                            ProvincialAdminColors
                                .blue,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            'Tourist Spot Details',
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
                            'Review submitted tourism information and moderation status.',
                            maxLines: 1,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                TextStyle(
                              color:
                                  ProvincialAdminColors
                                      .muted,
                              fontSize:
                                  10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                      ),
                    ),
                  ],
                ),
              ),

              // ─────────────────────────────
              // Content
              // ─────────────────────────────

              Flexible(
                child:
                    SingleChildScrollView(
                  padding:
                      const EdgeInsets.all(
                    20,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      _DialogHero(
                        spot: spot,
                      ),

                      const SizedBox(
                        height: 18,
                      ),

                      Text(
                        spot.title,
                        style:
                            const TextStyle(
                          color:
                              ProvincialAdminColors
                                  .text,
                          fontSize: 19,
                          fontWeight:
                              FontWeight.w900,
                          height: 1.2,
                        ),
                      ),

                      const SizedBox(
                        height: 6,
                      ),

                      Row(
                        children: [
                          const Icon(
                            Icons
                                .location_city_outlined,
                            size: 14,
                            color:
                                ProvincialAdminColors
                                    .lightMuted,
                          ),
                          const SizedBox(
                            width: 5,
                          ),
                          Text(
                            spot.city,
                            style:
                                const TextStyle(
                              color:
                                  ProvincialAdminColors
                                      .muted,
                              fontSize:
                                  11.5,
                              fontWeight:
                                  FontWeight
                                      .w700,
                            ),
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          AdminStatusPill(
                            status:
                                spot.status,
                          ),
                        ],
                      ),

                      if (spot.description
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(
                          height: 16,
                        ),
                        const Text(
                          'Description',
                          style: TextStyle(
                            color:
                                ProvincialAdminColors
                                    .text,
                            fontSize: 11,
                            fontWeight:
                                FontWeight
                                    .w900,
                          ),
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        Text(
                          spot.description,
                          style:
                              const TextStyle(
                            color:
                                ProvincialAdminColors
                                    .muted,
                            fontSize:
                                11.5,
                            height: 1.5,
                          ),
                        ),
                      ],

                      const SizedBox(
                        height: 18,
                      ),

                      const Text(
                        'Tourism Information',
                        style:
                            TextStyle(
                          color:
                              ProvincialAdminColors
                                  .text,
                          fontSize: 12,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),

                      const SizedBox(
                        height: 9,
                      ),

                      _DetailsGrid(
                        children: [
                          _DetailTile(
                            icon: Icons
                                .location_city_outlined,
                            label: 'City',
                            value: spot.city
                                    .trim()
                                    .isEmpty
                                ? 'N/A'
                                : spot.city,
                          ),
                          _DetailTile(
                            icon: Icons
                                .place_outlined,
                            label:
                                'Barangay',
                            value: spot.barangay
                                    .trim()
                                    .isEmpty
                                ? 'N/A'
                                : spot.barangay,
                          ),
                          _DetailTile(
                            icon: Icons
                                .toggle_on_outlined,
                            label: 'Status',
                            value:
                                _titleCase(
                              spot.status
                                  .replaceAll(
                                '_',
                                ' ',
                              ),
                            ),
                          ),
                          _DetailTile(
                            icon: Icons
                                .star_outline_rounded,
                            label: 'Rating',
                            value:
                                spot.rating <=
                                        0
                                    ? 'No rating'
                                    : '${spot.rating.toStringAsFixed(1)} / 5',
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 18,
                      ),

                      _DialogVerificationBox(
                        verified: verified,
                        flagged: flagged,
                        rawStatus: spot
                            .verificationStatus,
                      ),
                    ],
                  ),
                ),
              ),

              // ─────────────────────────────
              // Dialog actions
              // ─────────────────────────────

              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(14),
                decoration:
                    const BoxDecoration(
                  color:
                      Color(0xFFF8FAFC),
                  border: Border(
                    top: BorderSide(
                      color:
                          ProvincialAdminColors
                              .line,
                    ),
                  ),
                ),
                child: screenWidth < 620
                    ? Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .stretch,
                        children: [
                          if (!verified)
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(
                                  context,
                                  'verify',
                                );
                              },
                              icon:
                                  const Icon(
                                Icons
                                    .verified_rounded,
                                size: 17,
                              ),
                              label:
                                  const Text(
                                'Verify',
                              ),
                            ),
                          if (!verified)
                            const SizedBox(
                              height: 8,
                            ),
                          if (!flagged)
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(
                                  context,
                                  'flag',
                                );
                              },
                              icon:
                                  const Icon(
                                Icons
                                    .flag_outlined,
                                size: 17,
                              ),
                              label:
                                  const Text(
                                'Flag',
                              ),
                            ),
                          if (!flagged)
                            const SizedBox(
                              height: 8,
                            ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(
                                context,
                                archived
                                    ? 'unarchive'
                                    : 'archive',
                              );
                            },
                            icon: Icon(
                              archived
                                  ? Icons
                                      .restore_rounded
                                  : Icons
                                      .archive_outlined,
                              size: 17,
                            ),
                            label: Text(
                              archived
                                  ? 'Restore'
                                  : 'Archive',
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          TextButton(
                            onPressed: () {
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
                          if (!flagged)
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(
                                  context,
                                  'flag',
                                );
                              },
                              icon:
                                  const Icon(
                                Icons
                                    .flag_outlined,
                                size: 16,
                              ),
                              label:
                                  const Text(
                                'Flag',
                              ),
                            ),
                          if (!flagged)
                            const SizedBox(
                              width: 8,
                            ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(
                                context,
                                archived
                                    ? 'unarchive'
                                    : 'archive',
                              );
                            },
                            icon: Icon(
                              archived
                                  ? Icons
                                      .restore_rounded
                                  : Icons
                                      .archive_outlined,
                              size: 16,
                            ),
                            label: Text(
                              archived
                                  ? 'Restore'
                                  : 'Archive',
                            ),
                          ),
                          if (!verified)
                            const SizedBox(
                              width: 8,
                            ),
                          if (!verified)
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(
                                  context,
                                  'verify',
                                );
                              },
                              icon:
                                  const Icon(
                                Icons
                                    .verified_rounded,
                                size: 16,
                              ),
                              label:
                                  const Text(
                                'Verify Spot',
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogHero extends StatelessWidget {
  const _DialogHero({
    required this.spot,
  });

  final ProvinceSpot spot;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 230,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius:
            BorderRadius.circular(15),
        border: Border.all(
          color: ProvincialAdminColors.line,
        ),
      ),
      child: spot.imageUrl.trim().isEmpty
          ? const Center(
              child: Icon(
                Icons
                    .travel_explore_rounded,
                color:
                    ProvincialAdminColors.blue,
                size: 54,
              ),
            )
          : Image.network(
              spot.imageUrl,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) {
                return const Center(
                  child: Icon(
                    Icons
                        .travel_explore_rounded,
                    color:
                        ProvincialAdminColors
                            .blue,
                    size: 54,
                  ),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog detail grid
// ─────────────────────────────────────────────────────────────────────────────

class _DetailsGrid extends StatelessWidget {
  const _DetailsGrid({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 500) {
          return Column(
            children: children
                .map(
                  (child) => Padding(
                    padding:
                        const EdgeInsets
                            .only(
                      bottom: 8,
                    ),
                    child: child,
                  ),
                )
                .toList(),
          );
        }

        final width =
            (constraints.maxWidth - 8) /
                2;

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: children
              .map(
                (child) => SizedBox(
                  width: width,
                  child: child,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color: ProvincialAdminColors.line,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: ProvincialAdminColors.blue
                  .withValues(alpha: .08),
              borderRadius:
                  BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color:
                  ProvincialAdminColors.blue,
              size: 16,
            ),
          ),
          const SizedBox(width: 9),
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
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow:
                      TextOverflow.ellipsis,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog verification
// ─────────────────────────────────────────────────────────────────────────────

class _DialogVerificationBox
    extends StatelessWidget {
  const _DialogVerificationBox({
    required this.verified,
    required this.flagged,
    required this.rawStatus,
  });

  final bool verified;
  final bool flagged;
  final String rawStatus;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final Color background;
    final IconData icon;
    final String title;
    final String message;

    if (flagged) {
      color = _red;
      background = _softRed;
      icon = Icons.flag_rounded;
      title = 'Flagged for Review';
      message =
          'This tourist spot has been flagged and may contain information that requires further provincial review.';
    } else if (verified) {
      color = _green;
      background = _softGreen;
      icon = Icons.verified_rounded;
      title = 'Verified Tourism Data';
      message =
          'This tourist spot has been reviewed and verified by the Provincial Tourism Office.';
    } else {
      color = _amber;
      background = _softAmber;
      icon = Icons.pending_actions_rounded;
      title = rawStatus.trim().isEmpty
          ? 'Pending Verification'
          : _titleCase(
              rawStatus
                  .replaceAll('_', ' '),
            );
      message =
          'This tourist spot is awaiting provincial review and verification.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(11),
        border: Border.all(
          color:
              color.withValues(alpha: .18),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color:
                  color.withValues(alpha: .10),
              borderRadius:
                  BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style:
                      const TextStyle(
                    color:
                        ProvincialAdminColors
                            .muted,
                    fontSize: 10,
                    height: 1.4,
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
// Utilities
// ─────────────────────────────────────────────────────────────────────────────

String _titleCase(String value) {
  final clean =
      value.trim().replaceAll(
            RegExp(r'\s+'),
            ' ',
          );

  if (clean.isEmpty) {
    return 'Unknown';
  }

  return clean.split(' ').map((word) {
    if (word.isEmpty) {
      return word;
    }

    if (word.length == 1) {
      return word.toUpperCase();
    }

    return '${word[0].toUpperCase()}'
        '${word.substring(1).toLowerCase()}';
  }).join(' ');
}