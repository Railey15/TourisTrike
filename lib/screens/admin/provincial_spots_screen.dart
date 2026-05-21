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

class ProvincialSpotsScreen extends StatefulWidget {
  const ProvincialSpotsScreen({super.key});

  @override
  State<ProvincialSpotsScreen> createState() => _ProvincialSpotsScreenState();
}

class _ProvincialSpotsScreenState extends State<ProvincialSpotsScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();
  final TextEditingController _searchCtrl = TextEditingController();

  late Future<List<ProvinceSpot>> _future;

  String _cityFilter = 'all';
  String _spotStatusFilter = 'all';
  String _verificationFilter = 'all';

  @override
  void initState() {
    super.initState();
    _future = _service.fetchProvinceSpots();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = _service.fetchProvinceSpots());
  }

  List<ProvinceSpot> _filtered(List<ProvinceSpot> spots) {
    final query = _searchCtrl.text.trim().toLowerCase();

    return spots.where((spot) {
      final city = spot.city.trim();
      final status = spot.status.toLowerCase().trim();
      final verification = spot.verificationStatus.toLowerCase().trim();

      // City filter
      final matchesCity = _cityFilter == 'all' || city == _cityFilter;

      // Spot status filter
      final matchesSpotStatus = _spotStatusFilter == 'all' ||
          (_spotStatusFilter == 'active' && status == 'active') ||
          (_spotStatusFilter == 'maintenance' && status == 'maintenance') ||
          (_spotStatusFilter == 'archived' && status == 'archived');

      // Verification filter
      final matchesVerification = _verificationFilter == 'all' ||
          (_verificationFilter == 'verified' && verification == 'verified') ||
          (_verificationFilter == 'unverified' &&
              verification != 'verified' &&
              verification != 'flagged') ||
          (_verificationFilter == 'flagged' && verification == 'flagged');

      if (!matchesCity || !matchesSpotStatus || !matchesVerification) {
        return false;
      }

      if (query.isEmpty) return true;

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

  int _countCity(List<ProvinceSpot> spots) {
    if (_cityFilter == 'all') return spots.length;
    return spots.where((spot) => spot.city.trim() == _cityFilter).length;
  }

  int _countSpotStatus(List<ProvinceSpot> spots, String filter) {
    if (filter == 'all') return spots.length;
    return spots
        .where((spot) => spot.status.toLowerCase().trim() == filter)
        .length;
  }

  int _countVerification(List<ProvinceSpot> spots, String filter) {
    if (filter == 'all') return spots.length;

    return spots.where((spot) {
      final verification = spot.verificationStatus.toLowerCase().trim();

      if (filter == 'verified') return verification == 'verified';
      if (filter == 'flagged') return verification == 'flagged';
      if (filter == 'unverified') {
        return verification != 'verified' && verification != 'flagged';
      }

      return false;
    }).length;
  }

  Future<void> _verify(ProvinceSpot spot) async {
    try {
      await _service.verifySpot(spot);
      if (!mounted) return;
      showAdminSnack(context, 'Tourist spot verified.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Failed to verify spot: $e');
    }
  }

  Future<void> _flag(ProvinceSpot spot) async {
    try {
      await _service.flagSpot(spot);
      if (!mounted) return;
      showAdminSnack(context, 'Tourist spot flagged.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Failed to flag spot: $e');
    }
  }

  Future<void> _archive(ProvinceSpot spot) async {
    try {
      await _service.archiveSpot(spot);
      if (!mounted) return;
      showAdminSnack(context, 'Tourist spot archived.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Failed to archive spot: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return ProvincialAdminShell(
      current: ProvincialAdminDestination.tourismData,
      title: 'Tourism Data',
      subtitle: 'Verify tourist spots and flag inaccurate province data.',
      child: FutureBuilder<List<ProvinceSpot>>(
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

          final allSpots = snapshot.data ?? const <ProvinceSpot>[];
          final spots = _filtered(allSpots);

          final cities = allSpots
              .map((item) => item.city)
              .where((city) => city.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort();

          final avgRating = allSpots.isEmpty
              ? 0.0
              : allSpots.fold<double>(0, (sum, spot) => sum + spot.rating) /
                  allSpots.length;

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
                  _TourismHero(
                    total: allSpots.length,
                    active: allSpots
                        .where((s) =>
                            s.status.toLowerCase().trim() == 'active')
                        .length,
                    verified: allSpots
                        .where((s) =>
                            s.verificationStatus.toLowerCase().trim() ==
                            'verified')
                        .length,
                    flagged: allSpots
                        .where((s) =>
                            s.verificationStatus.toLowerCase().trim() ==
                            'flagged')
                        .length,
                    averageRating: avgRating,
                  ),
                  const SizedBox(height: 20),
                  _ToolbarClean(
                    searchController: _searchCtrl,
                    cities: cities,
                    cityFilter: _cityFilter,
                    spotStatusFilter: _spotStatusFilter,
                    verificationFilter: _verificationFilter,
                    allSpots: allSpots,
                    onCityChanged: (value) {
                      setState(() => _cityFilter = value);
                    },
                    onSpotStatusChanged: (value) {
                      setState(() => _spotStatusFilter = value);
                    },
                    onVerificationChanged: (value) {
                      setState(() => _verificationFilter = value);
                    },
                  ),
                  const SizedBox(height: 20),
                  if (spots.isEmpty)
                    const AdminEmptyState(
                      icon: Icons.travel_explore_outlined,
                      title: 'No tourist spots found',
                      message:
                          'Tourist spots created by city tenants will appear here for verification.',
                    )
                  else if (mobile)
                    ...spots.map(
                      (spot) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SpotCard(
                          spot: spot,
                          onVerify: () => _verify(spot),
                          onFlag: () => _flag(spot),
                          onArchive: () => _archive(spot),
                        ),
                      ),
                    )
                  else
                    _SpotGrid(
                      spots: spots,
                      onVerify: _verify,
                      onFlag: _flag,
                      onArchive: _archive,
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

class _TourismHero extends StatelessWidget {
  const _TourismHero({
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
                  verified: verified,
                  flagged: flagged,
                  averageRating: averageRating,
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
                  verified: verified,
                  flagged: flagged,
                  averageRating: averageRating,
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
        Icons.travel_explore_rounded,
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
          'Province-wide Tourism Data Review',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .86),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tourist Spot Verification',
          style: TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Review LGU-submitted tourist spots, verify accurate data, and flag records that need correction.',
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
    final desktop = Responsive.isDesktop(context);

    final items = [
      _HeroStatData('Total', total.toString(), Icons.place_rounded),
      _HeroStatData('Active', active.toString(), Icons.public_rounded),
      _HeroStatData('Verified', verified.toString(), Icons.verified_rounded),
      _HeroStatData('Flagged', flagged.toString(), Icons.flag_rounded),
      _HeroStatData(
        'Avg Rating',
        averageRating.toStringAsFixed(1),
        Icons.star_rounded,
      ),
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

/// Clean, unified toolbar with search and filters dropdown
class _ToolbarClean extends StatefulWidget {
  const _ToolbarClean({
    required this.searchController,
    required this.cities,
    required this.cityFilter,
    required this.spotStatusFilter,
    required this.verificationFilter,
    required this.allSpots,
    required this.onCityChanged,
    required this.onSpotStatusChanged,
    required this.onVerificationChanged,
  });

  final TextEditingController searchController;
  final List<String> cities;
  final String cityFilter;
  final String spotStatusFilter;
  final String verificationFilter;
  final List<ProvinceSpot> allSpots;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<String> onSpotStatusChanged;
  final ValueChanged<String> onVerificationChanged;

  @override
  State<_ToolbarClean> createState() => _ToolbarCleanState();
}

class _ToolbarCleanState extends State<_ToolbarClean> {
  final GlobalKey<_FilterDropdownState> _filterKey =
      GlobalKey<_FilterDropdownState>();

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      child: mobile
          ? Column(
              children: [
                _SearchField(controller: widget.searchController),
                const SizedBox(height: 12),
                _FilterDropdown(
                  key: _filterKey,
                  cities: widget.cities,
                  cityFilter: widget.cityFilter,
                  spotStatusFilter: widget.spotStatusFilter,
                  verificationFilter: widget.verificationFilter,
                  allSpots: widget.allSpots,
                  onCityChanged: widget.onCityChanged,
                  onSpotStatusChanged: widget.onSpotStatusChanged,
                  onVerificationChanged: widget.onVerificationChanged,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  flex: 1,
                  child: _SearchField(controller: widget.searchController),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 240,
                  child: _FilterDropdown(
                    key: _filterKey,
                    cities: widget.cities,
                    cityFilter: widget.cityFilter,
                    spotStatusFilter: widget.spotStatusFilter,
                    verificationFilter: widget.verificationFilter,
                    allSpots: widget.allSpots,
                    onCityChanged: widget.onCityChanged,
                    onSpotStatusChanged: widget.onSpotStatusChanged,
                    onVerificationChanged: widget.onVerificationChanged,
                  ),
                ),
              ],
            ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Search tourist spot, city, barangay...',
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
  }
}

/// Unified filters dropdown widget
class _FilterDropdown extends StatefulWidget {
  const _FilterDropdown({
    super.key,
    required this.cities,
    required this.cityFilter,
    required this.spotStatusFilter,
    required this.verificationFilter,
    required this.allSpots,
    required this.onCityChanged,
    required this.onSpotStatusChanged,
    required this.onVerificationChanged,
  });

  final List<String> cities;
  final String cityFilter;
  final String spotStatusFilter;
  final String verificationFilter;
  final List<ProvinceSpot> allSpots;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<String> onSpotStatusChanged;
  final ValueChanged<String> onVerificationChanged;

  @override
  State<_FilterDropdown> createState() => _FilterDropdownState();
}

class _FilterDropdownState extends State<_FilterDropdown> {
  late OverlayEntry _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  bool _isOpen = false;

  @override
  void dispose() {
    if (_isOpen) {
      _overlayEntry.remove();
    }
    super.dispose();
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _overlayEntry.remove();
      setState(() => _isOpen = false);
    } else {
      _overlayEntry = _buildOverlayEntry();
      Overlay.of(context).insert(_overlayEntry);
      setState(() => _isOpen = true);
    }
  }

  OverlayEntry _buildOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 8),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: ProvincialAdminColors.line),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // City filter section
                      _FilterSection(
                        title: 'City',
                        children: [
                          _FilterOption(
                            label: 'All Cities',
                            value: 'all',
                            selected: widget.cityFilter == 'all',
                            onTap: () {
                              widget.onCityChanged('all');
                              _toggleDropdown();
                            },
                          ),
                          ...widget.cities.map((city) {
                            return _FilterOption(
                              label: city,
                              value: city,
                              selected: widget.cityFilter == city,
                              onTap: () {
                                widget.onCityChanged(city);
                                _toggleDropdown();
                              },
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(
                        height: 1,
                        color: ProvincialAdminColors.line,
                      ),
                      const SizedBox(height: 12),
                      // Spot status filter section
                      _FilterSection(
                        title: 'Spot Status',
                        children: [
                          _FilterOption(
                            label: 'All',
                            value: 'all',
                            selected: widget.spotStatusFilter == 'all',
                            onTap: () {
                              widget.onSpotStatusChanged('all');
                              _toggleDropdown();
                            },
                          ),
                          _FilterOption(
                            label: 'Active',
                            value: 'active',
                            selected: widget.spotStatusFilter == 'active',
                            onTap: () {
                              widget.onSpotStatusChanged('active');
                              _toggleDropdown();
                            },
                          ),
                          _FilterOption(
                            label: 'Maintenance',
                            value: 'maintenance',
                            selected: widget.spotStatusFilter == 'maintenance',
                            onTap: () {
                              widget.onSpotStatusChanged('maintenance');
                              _toggleDropdown();
                            },
                          ),
                          _FilterOption(
                            label: 'Archived',
                            value: 'archived',
                            selected: widget.spotStatusFilter == 'archived',
                            onTap: () {
                              widget.onSpotStatusChanged('archived');
                              _toggleDropdown();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(
                        height: 1,
                        color: ProvincialAdminColors.line,
                      ),
                      const SizedBox(height: 12),
                      // Verification filter section
                      _FilterSection(
                        title: 'Verification',
                        children: [
                          _FilterOption(
                            label: 'All Verification',
                            value: 'all',
                            selected: widget.verificationFilter == 'all',
                            onTap: () {
                              widget.onVerificationChanged('all');
                              _toggleDropdown();
                            },
                          ),
                          _FilterOption(
                            label: 'Verified',
                            value: 'verified',
                            selected: widget.verificationFilter == 'verified',
                            onTap: () {
                              widget.onVerificationChanged('verified');
                              _toggleDropdown();
                            },
                          ),
                          _FilterOption(
                            label: 'Unverified',
                            value: 'unverified',
                            selected: widget.verificationFilter == 'unverified',
                            onTap: () {
                              widget.onVerificationChanged('unverified');
                              _toggleDropdown();
                            },
                          ),
                          _FilterOption(
                            label: 'Flagged',
                            value: 'flagged',
                            selected: widget.verificationFilter == 'flagged',
                            onTap: () {
                              widget.onVerificationChanged('flagged');
                              _toggleDropdown();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getFilterSummary() {
    final parts = <String>[];

    if (widget.cityFilter != 'all') {
      parts.add(widget.cityFilter);
    }
    if (widget.spotStatusFilter != 'all') {
      parts.add(widget.spotStatusFilter);
    }
    if (widget.verificationFilter != 'all') {
      parts.add(widget.verificationFilter);
    }

    if (parts.isEmpty) {
      return 'Filters';
    }
    if (parts.length == 1) {
      return parts.first;
    }
    return '${parts.length} active';
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        height: 48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: _toggleDropdown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _isOpen ? const Color(0xFFF1F6FF) : const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: _isOpen
                      ? ProvincialAdminColors.blue
                      : ProvincialAdminColors.line,
                  width: _isOpen ? 1.3 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list_rounded,
                    color: ProvincialAdminColors.lightMuted,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getFilterSummary(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _isOpen
                            ? ProvincialAdminColors.blue
                            : ProvincialAdminColors.muted,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    _isOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: ProvincialAdminColors.lightMuted,
                    size: 18,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: ProvincialAdminColors.text,
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _FilterOption extends StatelessWidget {
  const _FilterOption({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: selected ? ProvincialAdminColors.blue : Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: selected
                      ? ProvincialAdminColors.blue
                      : ProvincialAdminColors.line,
                  width: selected ? 0 : 1.5,
                ),
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 12,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? ProvincialAdminColors.text
                      : ProvincialAdminColors.muted,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotGrid extends StatelessWidget {
  const _SpotGrid({
    required this.spots,
    required this.onVerify,
    required this.onFlag,
    required this.onArchive,
  });

  final List<ProvinceSpot> spots;
  final ValueChanged<ProvinceSpot> onVerify;
  final ValueChanged<ProvinceSpot> onFlag;
  final ValueChanged<ProvinceSpot> onArchive;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1250 ? 3 : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: spots.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 2.05,
          ),
          itemBuilder: (context, index) {
            final spot = spots[index];

            return _SpotCard(
              spot: spot,
              onVerify: () => onVerify(spot),
              onFlag: () => onFlag(spot),
              onArchive: () => onArchive(spot),
            );
          },
        );
      },
    );
  }
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({
    required this.spot,
    required this.onVerify,
    required this.onFlag,
    required this.onArchive,
  });

  final ProvinceSpot spot;
  final VoidCallback onVerify;
  final VoidCallback onFlag;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final verified = spot.verificationStatus.toLowerCase().trim() == 'verified';

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
                  _SpotImage(url: spot.imageUrl),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spot.title,
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
                          spot.city,
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
                  AdminStatusPill(status: spot.status),
                  PopupMenuButton<String>(
                    tooltip: 'Spot actions',
                    onSelected: (value) {
                      switch (value) {
                        case 'verify':
                          onVerify();
                          break;
                        case 'flag':
                          onFlag();
                          break;
                        case 'archive':
                          onArchive();
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'verify', child: Text('Verify Spot')),
                      PopupMenuItem(value: 'flag', child: Text('Flag Issue')),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text('Archive Spot'),
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
                    child: _SpotInfo(
                      icon: Icons.location_on_rounded,
                      label: 'Barangay',
                      value: spot.barangay.isEmpty ? 'N/A' : spot.barangay,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SpotInfo(
                      icon: Icons.star_rounded,
                      label: 'Rating',
                      value: spot.rating <= 0
                          ? 'No rating'
                          : spot.rating.toStringAsFixed(1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _VerificationBox(
                      verified: verified,
                      status: spot.verificationStatus,
                      onVerify: onVerify,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SpotActionBox(
                      label: 'Flag',
                      subtitle: 'Mark inaccurate',
                      icon: Icons.flag_rounded,
                      color: ProvincialAdminColors.amber,
                      onTap: onFlag,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SpotActionBox(
                      label: 'Archive',
                      subtitle: 'Hide record',
                      icon: Icons.archive_rounded,
                      color: ProvincialAdminColors.red,
                      onTap: onArchive,
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

class _SpotImage extends StatelessWidget {
  const _SpotImage({required this.url});

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
              Icons.travel_explore_rounded,
              color: ProvincialAdminColors.blue,
              size: 28,
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.travel_explore_rounded,
                color: ProvincialAdminColors.blue,
                size: 28,
              ),
            ),
    );
  }
}

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

class _VerificationBox extends StatelessWidget {
  const _VerificationBox({
    required this.verified,
    required this.status,
    required this.onVerify,
  });

  final bool verified;
  final String status;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final color = verified ? ProvincialAdminColors.green : ProvincialAdminColors.amber;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: verified ? null : onVerify,
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
              verified ? Icons.verified_rounded : Icons.pending_actions_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: verified ? 'Verified\n' : 'Pending\n',
                      style: TextStyle(
                        color: color,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    TextSpan(
                      text: verified ? 'Approved data' : 'Tap to verify',
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
      ),
    );
  }
}

class _SpotActionBox extends StatelessWidget {
  const _SpotActionBox({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
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
                      text: '$label\n',
                      style: TextStyle(
                        color: color,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    TextSpan(
                      text: subtitle,
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
      ),
    );
  }
}