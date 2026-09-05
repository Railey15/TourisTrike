import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/places/google_places_errors.dart';
import 'package:touristrike/core/responsive/responsive.dart';

import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/subtenant_spot_form_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_workspace_search.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

const _pageBackground = Color(0xFFF4F7FB);

const _softBlue = Color(0xFFF2F7FF);
const _softGreen = Color(0xFFF0FDF4);
const _softAmber = Color(0xFFFFFBEB);
const _softRed = Color(0xFFFEF2F2);

const _green = Color(0xFF16A34A);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFDC2626);

class SubTenantSpotsScreen extends StatefulWidget {
  const SubTenantSpotsScreen({super.key});

  @override
  State<SubTenantSpotsScreen> createState() => _SubTenantSpotsScreenState();
}

class _SubTenantSpotsScreenState extends State<SubTenantSpotsScreen> {
  final SubTenantService _service = SubTenantService();
  final CitySpotSuggestionService _suggestionService =
      CitySpotSuggestionService();

  final TextEditingController _searchCtrl = TextEditingController();
  final SubTenantWorkspaceSearchController _workspaceSearch =
      SubTenantWorkspaceSearchController.instance;

  late Future<_SpotListLoad> _future;

  Future<List<CitySpotSuggestion>>? _suggestionsFuture;

  String _status = 'all';
  int _tabIndex = 0;
  String? _suggestionCity;
  int _suggestionRefreshKey = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchCtrl.addListener(_onSearchChanged);
    _workspaceSearch.addListener(_handleWorkspaceSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _workspaceSearch.removeListener(_handleWorkspaceSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleWorkspaceSearchChanged() {
    if (!mounted || _workspaceSearch.activeScope != 1) return;
    setState(() {});
  }

  Future<_SpotListLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final spots = await _service.fetchSpots(profile);

    return _SpotListLoad(
      profile: profile,
      spots: spots,
    );
  }

  Future<void> _reload() async {
    late Future<_SpotListLoad> newFuture;

    setState(() {
      newFuture = _load();
      _future = newFuture;
      _suggestionsFuture = null;
      _suggestionCity = null;
      _suggestionRefreshKey++;
    });

    await newFuture;
  }

  Future<void> _openForm({
    SubTenantSpot? spot,
    CitySpotSuggestion? suggestion,
  }) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubTenantSpotFormScreen(
          spot: spot,
          initialSuggestion: suggestion,
        ),
      ),
    );

    if (!mounted) return;

    if (changed == true) {
      await _reload();
    }
  }

  void _ensureSuggestions(
    SubTenantProfile profile,
    List<SubTenantSpot> spots,
  ) {
    final city = profile.assignedCity.trim();
    final cacheKey = '$city-$_suggestionRefreshKey';

    if (_suggestionsFuture != null && _suggestionCity == cacheKey) {
      return;
    }

    _suggestionCity = cacheKey;
    _suggestionsFuture = _loadCitySuggestions(profile, spots);
  }

  void _refreshSuggestions(
    SubTenantProfile profile,
    List<SubTenantSpot> spots,
  ) {
    setState(() {
      _suggestionRefreshKey++;
      _suggestionCity = '${profile.assignedCity.trim()}-$_suggestionRefreshKey';
      _suggestionsFuture = _loadCitySuggestions(profile, spots);
    });
  }

  Future<List<CitySpotSuggestion>> _loadCitySuggestions(
    SubTenantProfile profile,
    List<SubTenantSpot> existingSpots,
  ) async {
    final city = profile.assignedCity.trim();
    final province =
        profile.province.trim().isEmpty ? 'Bulacan' : profile.province.trim();

    final center = _suggestionService.centerForCity(city) ??
        CitySpotSuggestionService.defaultBulacanCenter;

    final googleSuggestions = await _suggestionService
        .fetchSuggestions(
          city: city,
          province: province,
          center: center,
          limit: 18,
        )
        .timeout(const Duration(seconds: 35));

    final filteredGoogle = _removeAlreadySavedSuggestions(
      googleSuggestions,
      existingSpots,
      city,
      center,
    );

    return filteredGoogle.take(8).toList(growable: false);
  }

  List<CitySpotSuggestion> _removeAlreadySavedSuggestions(
    List<CitySpotSuggestion> suggestions,
    List<SubTenantSpot> existingSpots,
    String city,
    LatLng center,
  ) {
    return suggestions.where((suggestion) {
      final belongsToSelectedCity =
          _isSuggestionInSelectedCity(suggestion, city, center);

      if (!belongsToSelectedCity) return false;
      if (_hasExactSavedTitle(suggestion, existingSpots)) return false;
      if (_hasNearbySavedLocation(suggestion, existingSpots)) return false;

      return true;
    }).toList(growable: false);
  }

  bool _isSuggestionInSelectedCity(
    CitySpotSuggestion suggestion,
    String city,
    LatLng center,
  ) {
    if (suggestion.latitude != 0 && suggestion.longitude != 0) {
      final distance = _distanceKm(
        center.latitude,
        center.longitude,
        suggestion.latitude,
        suggestion.longitude,
      );

      if (distance <= 20) {
        return true;
      }
    }

    final aliases = CitySpotSuggestionService.cityAliases(city);
    if (aliases.isEmpty) return false;

    final normalizedAddress =
        CitySpotSuggestionService.normalizeText(suggestion.address);

    final normalizedSuggestionCity =
        CitySpotSuggestionService.normalizeText(suggestion.city);

    return aliases.any(
      (alias) =>
          normalizedAddress.contains(alias) || normalizedSuggestionCity == alias,
    );
  }

  bool _hasExactSavedTitle(
    CitySpotSuggestion suggestion,
    List<SubTenantSpot> existingSpots,
  ) {
    final suggestedTitle = _normalText(suggestion.title);

    return existingSpots.any(
      (spot) => _normalText(spot.title) == suggestedTitle,
    );
  }

  bool _hasNearbySavedLocation(
    CitySpotSuggestion suggestion,
    List<SubTenantSpot> existingSpots,
  ) {
    return existingSpots.any((spot) {
      if (spot.latitude == 0 || spot.longitude == 0) return false;
      if (suggestion.latitude == 0 || suggestion.longitude == 0) return false;

      final distance = _distanceKm(
        spot.latitude,
        spot.longitude,
        suggestion.latitude,
        suggestion.longitude,
      );

      return distance <= 0.12;
    });
  }

  String _normalText(String value) {
    return value
        .toLowerCase()
        .replaceAll('ñ', 'n')
        .replaceAll('-', '')
        .replaceAll('_', '')
        .replaceAll(' ', '')
        .replaceAll(',', '')
        .replaceAll('.', '')
        .replaceAll('city', '')
        .replaceAll('municipality', '')
        .trim();
  }

  double _distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;

    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degToRad(double degree) {
    return degree * (math.pi / 180);
  }

  Future<void> _archive(
    SubTenantProfile profile,
    SubTenantSpot spot,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Archive Tourist Spot?',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Archive "${spot.title}" for ${profile.assignedCity}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.archive_outlined, size: 16),
              label: const Text('Archive'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _service.archiveSpot(profile, spot);

      if (!mounted) return;

      showSubTenantSnack(
        context,
        'Tourist spot archived.',
        error: false,
      );

      await _reload();
    } catch (error) {
      if (!mounted) return;

      showSubTenantSnack(
        context,
        'Failed to archive spot: $error',
      );
    }
  }

  List<SubTenantSpot> _filtered(List<SubTenantSpot> spots) {
    final query = [
      _searchCtrl.text.trim(),
      _workspaceSearch.queryFor(1),
    ].where((value) => value.isNotEmpty).join(' ').toLowerCase();

    return spots.where((spot) {
      final status = spot.status.trim().toLowerCase();

      final matchesStatus = _status == 'all' || status == _status;

      final matchesSearch = query.isEmpty ||
          spot.title.toLowerCase().contains(query) ||
          spot.barangay.toLowerCase().contains(query) ||
          spot.city.toLowerCase().contains(query);

      return matchesStatus && matchesSearch;
    }).toList(growable: false);
  }

  int _countByStatus(List<SubTenantSpot> spots, String status) {
    return spots
        .where((spot) => spot.status.trim().toLowerCase() == status)
        .length;
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'active':
        return 'Active';
      case 'maintenance':
        return 'Maintenance';
      case 'archived':
        return 'Archived';
      default:
        return 'All';
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return SubTenantAdminShell(
      currentIndex: 1,
      title: 'Tourist Spots',
      subtitle: 'Manage city-scoped destinations and spot visibility.',
      actions: [
        if (!mobile)
          FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_location_alt_rounded, size: 18),
            label: const Text('Add Spot'),
          ),
      ],
      floatingActionButton: mobile
          ? FloatingActionButton(
              heroTag: 'subtenant_spot_add_fab',
              backgroundColor: SubTenantColors.blue,
              foregroundColor: Colors.white,
              onPressed: () => _openForm(),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      child: FutureBuilder<_SpotListLoad>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SubTenantLoadingView();
          }

          if (snapshot.hasError) {
            return SubTenantErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final load = snapshot.data!;
          final filteredSpots = _filtered(load.spots);

          final totalCount = load.spots.length;
          final activeCount = _countByStatus(load.spots, 'active');
          final maintenanceCount = _countByStatus(load.spots, 'maintenance');
          final archivedCount = _countByStatus(load.spots, 'archived');

          if (_tabIndex == 1) {
            _ensureSuggestions(load.profile, load.spots);
          }

          return ColoredBox(
            color: _pageBackground,
            child: RefreshIndicator(
              onRefresh: _reload,
              child: ResponsivePageContainer(
                children: [
                  _SpotModeSwitcher(
                    selectedIndex: _tabIndex,
                    onChanged: (index) {
                      setState(() {
                        _tabIndex = index;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  if (_tabIndex == 0) ...[
                    _SpotToolbar(
                      controller: _searchCtrl,
                      status: _status,
                      onStatusChanged: (value) {
                        setState(() {
                          _status = value;
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    _SpotDirectoryHeader(
                      count: filteredSpots.length,
                      city: load.profile.assignedCity,
                      statusLabel: _statusLabel(_status),
                    ),
                    const SizedBox(height: 12),
                    if (filteredSpots.isEmpty)
                      _SavedSpotsEmptyState(
                        city: load.profile.assignedCity,
                        onAddManual: () => _openForm(),
                      )
                    else
                      _SpotGrid(
                        spots: filteredSpots,
                        onEdit: (spot) => _openForm(spot: spot),
                        onArchive: (spot) => _archive(load.profile, spot),
                      ),
                  ],
                  if (_tabIndex == 1)
                    _GoogleSuggestionsSection(
                      city: load.profile.assignedCity,
                      future: _suggestionsFuture!,
                      onRefresh: () =>
                          _refreshSuggestions(load.profile, load.spots),
                      onAddSuggestion: (suggestion) =>
                          _openForm(suggestion: suggestion),
                      onAddManual: () => _openForm(),
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


class _SummaryMetricData {
  const _SummaryMetricData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;
}

class _SummaryMetricCard extends StatelessWidget {
  const _SummaryMetricCard({
    required this.data,
  });

  final _SummaryMetricData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: data.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: data.color.withOpacity(.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              data.icon,
              size: 18,
              color: data.color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SubTenantColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.value,
                  style: TextStyle(
                    color: data.color,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
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

class _SpotModeSwitcher extends StatelessWidget {
  const _SpotModeSwitcher({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (label: 'Saved Tourist Spots', icon: Icons.place_outlined),
      (label: 'Google Suggestions', icon: Icons.travel_explore_rounded),
    ];

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 580;

          Widget buildTab(int index) {
            final selected = selectedIndex == index;
            final tab = tabs[index];

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onChanged(index),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color:
                        selected ? SubTenantColors.blue : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        tab.icon,
                        size: 16,
                        color: selected
                            ? Colors.white
                            : SubTenantColors.muted,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : SubTenantColors.text,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (compact) {
            return Column(
              children: [
                buildTab(0),
                const SizedBox(height: 6),
                buildTab(1),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: buildTab(0)),
              const SizedBox(width: 6),
              Expanded(child: buildTab(1)),
            ],
          );
        },
      ),
    );
  }
}

class _SpotToolbar extends StatelessWidget {
  const _SpotToolbar({
    required this.controller,
    required this.status,
    required this.onStatusChanged,
  });

  final TextEditingController controller;
  final String status;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 820;

          final search = SizedBox(
            height: 46,
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search tourist spot, barangay or city...',
                hintStyle: const TextStyle(
                  color: SubTenantColors.lightMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: SubTenantColors.lightMuted,
                ),
                suffixIcon: controller.text.trim().isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear search',
                        onPressed: controller.clear,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 16,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: SubTenantColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: SubTenantColors.blue,
                    width: 1.2,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          );

          final filters = _SpotStatusFilters(
            selected: status,
            onSelected: onStatusChanged,
          );

          if (!horizontal) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 10),
                filters,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              filters,
            ],
          );
        },
      ),
    );
  }
}

class _SpotStatusFilters extends StatelessWidget {
  const _SpotStatusFilters({
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (value: 'all', label: 'All', icon: Icons.apps_rounded),
      (
        value: 'active',
        label: 'Active',
        icon: Icons.check_circle_outline_rounded,
      ),
      (
        value: 'maintenance',
        label: 'Maintenance',
        icon: Icons.build_outlined,
      ),
      (
        value: 'archived',
        label: 'Archived',
        icon: Icons.archive_outlined,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.map((item) {
          final active = selected == item.value;

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => onSelected(item.value),
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color:
                      active ? SubTenantColors.blue : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color:
                        active ? SubTenantColors.blue : SubTenantColors.line,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 13,
                      color:
                          active ? Colors.white : SubTenantColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.label,
                      style: TextStyle(
                        color:
                            active ? Colors.white : SubTenantColors.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
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

class _SpotDirectoryHeader extends StatelessWidget {
  const _SpotDirectoryHeader({
    required this.count,
    required this.city,
    required this.statusLabel,
  });

  final int count;
  final String city;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tourist Spot Directory',
                style: TextStyle(
                  color: SubTenantColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count result${count == 1 ? '' : 's'} • $statusLabel • $city',
                style: const TextStyle(
                  color: SubTenantColors.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpotGrid extends StatelessWidget {
  const _SpotGrid({
    required this.spots,
    required this.onEdit,
    required this.onArchive,
  });

  final List<SubTenantSpot> spots;
  final ValueChanged<SubTenantSpot> onEdit;
  final ValueChanged<SubTenantSpot> onArchive;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final columns = width >= 1180
            ? 3
            : width >= 740
                ? 2
                : 1;

        final cardHeight = columns == 1
            ? 318.0
            : 328.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: spots.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: cardHeight,
          ),
          itemBuilder: (context, index) {
            final spot = spots[index];

            return _SpotImageCard(
              spot: spot,
              onEdit: () => onEdit(spot),
              onArchive: spot.status.trim().toLowerCase() == 'archived'
                  ? null
                  : () => onArchive(spot),
            );
          },
        );
      },
    );
  }
}

class _SpotImageCard extends StatelessWidget {
  const _SpotImageCard({
    required this.spot,
    required this.onEdit,
    this.onArchive,
  });

  final SubTenantSpot spot;
  final VoidCallback onEdit;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final location = [
      if (spot.barangay.trim().isNotEmpty) spot.barangay.trim(),
      if (spot.city.trim().isNotEmpty) spot.city.trim(),
    ].join(', ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: SubTenantColors.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.03),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 160,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _SpotImage(url: spot.imageUrl),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(.06),
                              Colors.transparent,
                              Colors.black.withOpacity(.28),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: SubTenantStatusPill(status: spot.status),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _SpotCardMenu(
                        onEdit: onEdit,
                        onArchive: onArchive,
                      ),
                    ),
                    if (spot.rating > 0)
                      Positioned(
                        right: 48,
                        top: 10,
                        child: _SpotRatingBadge(rating: spot.rating),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 42,
                        child: Text(
                          spot.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SubTenantColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: SubTenantColors.line,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.place_outlined,
                                size: 15,
                                color: SubTenantColors.blue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                location.isEmpty
                                    ? 'Location not specified'
                                    : location,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: SubTenantColors.muted,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Edit Spot Details'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SubTenantColors.blue,
                            side: const BorderSide(
                              color: SubTenantColors.line,
                            ),
                            backgroundColor: _softBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
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

class _SpotImage extends StatelessWidget {
  const _SpotImage({
    required this.url,
  });

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return const _SpotImageFallback();
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _SpotImageFallback(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;

        return Container(
          color: _softBlue,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        );
      },
    );
  }
}

class _SpotImageFallback extends StatelessWidget {
  const _SpotImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F6FB),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.95),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.photo_outlined,
              color: SubTenantColors.lightMuted,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'No spot photo available',
            style: TextStyle(
              color: SubTenantColors.muted,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotRatingBadge extends StatelessWidget {
  const _SpotRatingBadge({
    required this.rating,
  });

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.star_rounded,
            color: _amber,
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotCardMenu extends StatelessWidget {
  const _SpotCardMenu({
    required this.onEdit,
    this.onArchive,
  });

  final VoidCallback onEdit;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Spot actions',
      padding: EdgeInsets.zero,
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
            break;
          case 'archive':
            onArchive?.call();
            break;
        }
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: _SpotMenuItem(
            icon: Icons.edit_outlined,
            label: 'Edit Spot',
          ),
        ),
        if (onArchive != null)
          const PopupMenuItem(
            value: 'archive',
            child: _SpotMenuItem(
              icon: Icons.archive_outlined,
              label: 'Archive Spot',
              color: _red,
            ),
          ),
      ],
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.52),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          color: Colors.white,
          size: 17,
        ),
      ),
    );
  }
}

class _SpotMenuItem extends StatelessWidget {
  const _SpotMenuItem({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final actualColor = color ?? SubTenantColors.muted;

    return Row(
      children: [
        Icon(icon, size: 17, color: actualColor),
        const SizedBox(width: 9),
        Text(
          label,
          style: TextStyle(
            color: color ?? SubTenantColors.text,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _GoogleSuggestionsSection extends StatelessWidget {
  const _GoogleSuggestionsSection({
    required this.city,
    required this.future,
    required this.onRefresh,
    required this.onAddSuggestion,
    required this.onAddManual,
  });

  final String city;
  final Future<List<CitySpotSuggestion>> future;
  final VoidCallback onRefresh;
  final ValueChanged<CitySpotSuggestion> onAddSuggestion;
  final VoidCallback onAddManual;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SubTenantColors.blue.withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.travel_explore_rounded,
                color: SubTenantColors.blue,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Google Places Suggestions',
                    style: TextStyle(
                      color: SubTenantColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Suggested places near $city that are not yet saved.',
                    style: const TextStyle(
                      color: SubTenantColors.muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FutureBuilder<List<CitySpotSuggestion>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _SuggestionLoadingState(city: city);
            }

            if (snapshot.hasError) {
              final error = snapshot.error;

              return _SuggestionMessageCard(
                icon: Icons.cloud_off_rounded,
                title: 'Google Places is unavailable',
                message: _suggestionErrorMessage(error, city),
                primaryLabel: 'Retry',
                onPrimary: onRefresh,
                secondaryLabel: 'Add Manually',
                onSecondary: onAddManual,
              );
            }

            final suggestions = snapshot.data ?? const <CitySpotSuggestion>[];

            if (suggestions.isEmpty) {
              return _SuggestionMessageCard(
                icon: Icons.travel_explore_rounded,
                title: 'No new suggestions for $city',
                message:
                    'Nearby places may already be saved, or Google Places did not return any new results.',
                primaryLabel: 'Refresh',
                onPrimary: onRefresh,
                secondaryLabel: 'Add Manually',
                onSecondary: onAddManual,
              );
            }

            return _SuggestionGrid(
              suggestions: suggestions,
              onAdd: onAddSuggestion,
            );
          },
        ),
      ],
    );
  }

  String _suggestionErrorMessage(Object? error, String city) {
    if (error is GooglePlacesException) {
      return switch (error.kind) {
        GooglePlacesFailureKind.unauthorized ||
        GooglePlacesFailureKind.notConfigured =>
          '${error.message} Ask an administrator to check the server configuration, then retry.',
        GooglePlacesFailureKind.rateLimited => error.message,
        GooglePlacesFailureKind.network => error.message,
        _ => '${error.message} Please retry.',
      };
    }

    return 'Could not fetch suggestions for $city. Check your connection and try again.';
  }
}

class _SuggestionGrid extends StatelessWidget {
  const _SuggestionGrid({
    required this.suggestions,
    required this.onAdd,
  });

  final List<CitySpotSuggestion> suggestions;
  final ValueChanged<CitySpotSuggestion> onAdd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final columns = width >= 1050
            ? 3
            : width >= 640
                ? 2
                : 1;

        final cardHeight = columns == 1 ? 430.0 : 400.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: suggestions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: cardHeight,
          ),
          itemBuilder: (context, index) {
            final suggestion = suggestions[index];

            return _GoogleSuggestionCard(
              suggestion: suggestion,
              onAdd: () => onAdd(suggestion),
            );
          },
        );
      },
    );
  }
}

class _GoogleSuggestionCard extends StatelessWidget {
  const _GoogleSuggestionCard({
    required this.suggestion,
    required this.onAdd,
  });

  final CitySpotSuggestion suggestion;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final location = suggestion.address.trim().isEmpty
        ? [
            suggestion.city,
            suggestion.province,
          ].where((item) => item.trim().isNotEmpty).join(', ')
        : suggestion.address;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubTenantColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 140,
            child: _SuggestionImage(
              url: suggestion.imageForCard,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      if (suggestion.category.trim().isNotEmpty)
                        _SuggestionChip(
                          icon: Icons.category_outlined,
                          label: suggestion.category,
                        ),
                      if (suggestion.rating > 0)
                        _SuggestionChip(
                          icon: Icons.star_rounded,
                          label: suggestion.rating.toStringAsFixed(1),
                          accent: _amber,
                        ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  SizedBox(
                    height: 38,
                    child: Text(
                      suggestion.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SubTenantColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 34,
                    child: Text(
                      suggestion.description.trim().isEmpty
                          ? 'Suggested tourist destination from Google Places.'
                          : suggestion.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  _SuggestionLine(
                    icon: Icons.place_outlined,
                    text:
                        location.isEmpty ? 'Location unavailable' : location,
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    height: 18,
                    child: suggestion.distanceText.trim().isEmpty
                        ? const SizedBox.shrink()
                        : _SuggestionLine(
                            icon: Icons.near_me_outlined,
                            text: suggestion.distanceText,
                          ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(
                        Icons.add_location_alt_outlined,
                        size: 16,
                      ),
                      label: const Text('Add as Tourist Spot'),
                      style: FilledButton.styleFrom(
                        backgroundColor: SubTenantColors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
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

class _SuggestionImage extends StatelessWidget {
  const _SuggestionImage({
    required this.url,
  });

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return Container(
        color: _softBlue,
        alignment: Alignment.center,
        child: const Icon(
          Icons.travel_explore_rounded,
          color: SubTenantColors.blue,
          size: 36,
        ),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return Container(
          color: _softBlue,
          alignment: Alignment.center,
          child: const Icon(
            Icons.image_not_supported_outlined,
            color: SubTenantColors.lightMuted,
            size: 30,
          ),
        );
      },
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.icon,
    required this.label,
    this.accent = SubTenantColors.blue,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: accent),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionLine extends StatelessWidget {
  const _SuggestionLine({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            icon,
            size: 13,
            color: SubTenantColors.blue,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SubTenantColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggestionLoadingState extends StatelessWidget {
  const _SuggestionLoadingState({
    required this.city,
  });

  final String city;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Searching Google Places for tourist destinations in $city...',
              style: const TextStyle(
                color: SubTenantColors.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionMessageCard extends StatelessWidget {
  const _SuggestionMessageCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SubTenantColors.blue.withOpacity(.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: SubTenantColors.blue,
                  size: 19,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: SubTenantColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onPrimary,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(primaryLabel),
              ),
              OutlinedButton.icon(
                onPressed: onSecondary,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(secondaryLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavedSpotsEmptyState extends StatelessWidget {
  const _SavedSpotsEmptyState({
    required this.city,
    required this.onAddManual,
  });

  final String city;
  final VoidCallback onAddManual;

  @override
  Widget build(BuildContext context) {
    return EmptyStateCard(
      icon: Icons.place_outlined,
      title: 'No tourist spots found',
      message:
          'Tourist spots assigned to $city will appear here. Add one manually or browse Google Places Suggestions.',
      actionLabel: 'Add Tourist Spot',
      onAction: onAddManual,
    );
  }
}

class _SpotListLoad {
  const _SpotListLoad({
    required this.profile,
    required this.spots,
  });

  final SubTenantProfile profile;
  final List<SubTenantSpot> spots;
}