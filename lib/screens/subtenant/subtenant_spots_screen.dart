import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/subtenant_spot_form_screen.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantSpotsScreen extends StatefulWidget {
  const SubTenantSpotsScreen({super.key});

  @override
  State<SubTenantSpotsScreen> createState() => _SubTenantSpotsScreenState();
}

class _SubTenantSpotsScreenState extends State<SubTenantSpotsScreen> {
  final SubTenantService _service = SubTenantService();
  final CitySpotSuggestionService _suggestionService =
      const CitySpotSuggestionService();
  final TextEditingController _searchCtrl = TextEditingController();

  late Future<_SpotListLoad> _future;
  Future<List<CitySpotSuggestion>>? _suggestionsFuture;

  String _status = 'all';
  int _tabIndex = 0;
  String? _suggestionCity;
  int _suggestionRefreshKey = 0;
  bool _usingAiFallbackSuggestions = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<_SpotListLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final spots = await _service.fetchSpots(profile);
    return _SpotListLoad(profile: profile, spots: spots);
  }

  void _reload() {
    setState(() {
      _future = _load();
      _suggestionsFuture = null;
      _suggestionCity = null;
      _suggestionRefreshKey++;
      _usingAiFallbackSuggestions = false;
    });
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
    if (changed == true) _reload();
  }

  void _ensureSuggestions(SubTenantProfile profile, List<SubTenantSpot> spots) {
    final city = profile.assignedCity.trim();
    final cacheKey = '$city-$_suggestionRefreshKey';

    if (_suggestionsFuture != null && _suggestionCity == cacheKey) return;

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
      _usingAiFallbackSuggestions = false;
      _suggestionsFuture = _loadCitySuggestions(profile, spots);
    });
  }

  Future<List<CitySpotSuggestion>> _loadCitySuggestions(
    SubTenantProfile profile,
    List<SubTenantSpot> existingSpots,
  ) async {
    final city = profile.assignedCity.trim();
    final province = profile.province.trim().isEmpty
        ? 'Bulacan'
        : profile.province.trim();
    final center = _suggestionService.centerForCity(city) ??
        CitySpotSuggestionService.defaultBulacanCenter;

    try {
      final googleSuggestions = await _suggestionService
          .fetchSuggestions(
            city: city,
            province: province,
            center: center,
            limit: 18,
          )
          .timeout(const Duration(seconds: 20));

      final filteredGoogle = _removeAlreadySavedSuggestions(
        googleSuggestions,
        existingSpots,
        city,
        center,
      );

      if (filteredGoogle.isNotEmpty) {
        if (mounted) {
          setState(() => _usingAiFallbackSuggestions = false);
        }
        return filteredGoogle.take(8).toList(growable: false);
      }

      debugPrint(
        'SUBTENANT Google Places returned no usable suggestions for $city. Using AI fallback suggestions.',
      );

      final fallback = _buildAiFallbackSuggestions(
        profile: profile,
        existingSpots: existingSpots,
        center: center,
      );

      if (mounted) {
        setState(() => _usingAiFallbackSuggestions = fallback.isNotEmpty);
      }

      return fallback;
    } catch (e) {
      debugPrint('SUBTENANT Google suggestions unavailable for $city: $e');

      final fallback = _buildAiFallbackSuggestions(
        profile: profile,
        existingSpots: existingSpots,
        center: center,
      );

      if (mounted) {
        setState(() => _usingAiFallbackSuggestions = fallback.isNotEmpty);
      }

      return fallback;
    }
  }

  List<CitySpotSuggestion> _removeAlreadySavedSuggestions(
    List<CitySpotSuggestion> suggestions,
    List<SubTenantSpot> existingSpots,
    String city,
    LatLng center,
  ) {
    return suggestions.where((suggestion) {
      final belongsToSelectedCity = _isSuggestionInSelectedCity(
        suggestion,
        city,
        center,
      );

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
    final selectedCity = _normalText(city);
    final suggestionCity = _normalText(suggestion.city);
    final address = _normalText(suggestion.address);

    final cityMatches = suggestionCity == selectedCity ||
        suggestionCity.contains(selectedCity) ||
        selectedCity.contains(suggestionCity) ||
        address.contains(selectedCity);

    if (cityMatches) return true;

    if (suggestion.latitude == 0 || suggestion.longitude == 0) return false;

    final distance = _distanceKm(
      center.latitude,
      center.longitude,
      suggestion.latitude,
      suggestion.longitude,
    );

    return distance <= 15;
  }

  List<CitySpotSuggestion> _buildAiFallbackSuggestions({
    required SubTenantProfile profile,
    required List<SubTenantSpot> existingSpots,
    required LatLng center,
  }) {
    final city = profile.assignedCity.trim();
    final province = profile.province.trim().isEmpty
        ? 'Bulacan'
        : profile.province.trim();

    final barangays = CitySpotSuggestionService.barangaysForCity(city);
    final safeBarangays = barangays.isEmpty
        ? <String>['Poblacion', 'San Jose', 'San Pedro', 'Malambig']
        : barangays;

    final templates = <_AiSpotTemplate>[
      _AiSpotTemplate(
        suffix: 'Heritage Walk',
        category: 'Historical',
        description:
            'A suggested cultural and heritage destination where tourists can explore local history, landmarks, and community stories.',
        reason: 'AI-generated heritage spot idea for $city.',
        latOffset: -0.010,
        lngOffset: -0.008,
      ),
      _AiSpotTemplate(
        suffix: 'Nature Park',
        category: 'Nature',
        description:
            'A suggested nature-friendly tourist spot ideal for relaxation, photos, fresh air, and family visits.',
        reason: 'AI-generated nature spot idea for $city.',
        latOffset: -0.005,
        lngOffset: 0.007,
      ),
      _AiSpotTemplate(
        suffix: 'Food Stop',
        category: 'Food',
        description:
            'A suggested food destination where visitors can try local dishes, snacks, and community favorites.',
        reason: 'AI-generated food tourism idea for $city.',
        latOffset: 0.004,
        lngOffset: -0.006,
      ),
      _AiSpotTemplate(
        suffix: 'Resort and Leisure Area',
        category: 'Resort',
        description:
            'A suggested leisure destination for swimming, family bonding, and weekend relaxation.',
        reason: 'AI-generated resort idea for $city.',
        latOffset: 0.008,
        lngOffset: 0.006,
      ),
      _AiSpotTemplate(
        suffix: 'Faith and Cultural Site',
        category: 'Religious',
        description:
            'A suggested religious or cultural stop suitable for quiet visits, reflection, and local sightseeing.',
        reason: 'AI-generated religious tourism idea for $city.',
        latOffset: 0.012,
        lngOffset: -0.003,
      ),
      _AiSpotTemplate(
        suffix: 'Community Museum',
        category: 'Museum',
        description:
            'A suggested museum or cultural learning spot where visitors can learn about the municipality and its people.',
        reason: 'AI-generated cultural learning idea for $city.',
        latOffset: -0.013,
        lngOffset: 0.004,
      ),
      _AiSpotTemplate(
        suffix: 'Photo View Deck',
        category: 'Scenic',
        description:
            'A suggested scenic area where tourists can take photos and enjoy a relaxing local view.',
        reason: 'AI-generated scenic tourism idea for $city.',
        latOffset: 0.002,
        lngOffset: 0.012,
      ),
      _AiSpotTemplate(
        suffix: 'Local Market Experience',
        category: 'Market',
        description:
            'A suggested local market experience where tourists can discover local products, snacks, and community businesses.',
        reason: 'AI-generated local market idea for $city.',
        latOffset: -0.002,
        lngOffset: -0.012,
      ),
    ];

    final suggestions = <CitySpotSuggestion>[];

    for (var i = 0; i < templates.length; i++) {
      final template = templates[i];
      final barangay = safeBarangays[i % safeBarangays.length];
      final latitude = center.latitude + template.latOffset;
      final longitude = center.longitude + template.lngOffset;

      final suggestion = CitySpotSuggestion(
        id: 'ai-${_normalText(city)}-${_normalText(template.category)}-$i',
        title: '$city ${template.suffix}',
        city: city,
        province: province,
        barangayHint: barangay,
        address: 'Brgy. $barangay, $city, $province',
        description: template.description,
        category: template.category,
        latitude: latitude,
        longitude: longitude,
        rating: 0,
        imageUrl: CitySpotSuggestionService.buildStaticMapUrl(
          latitude: latitude,
          longitude: longitude,
        ),
        reason: template.reason,
        distanceKm: 0,
      );

      if (_hasExactSavedTitle(suggestion, existingSpots)) continue;
      if (_hasNearbySavedLocation(suggestion, existingSpots)) continue;

      suggestions.add(suggestion);
    }

    return suggestions.take(8).toList(growable: false);
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

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
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

  double _degToRad(double degree) => degree * (math.pi / 180);

  Future<void> _archive(SubTenantProfile profile, SubTenantSpot spot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive spot?'),
        content: Text('Archive "${spot.title}" for ${profile.assignedCity}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.archiveSpot(profile, spot);
      if (!mounted) return;
      showSubTenantSnack(context, 'Tourist spot archived.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to archive spot: $e');
    }
  }

  List<SubTenantSpot> _filtered(List<SubTenantSpot> spots) {
    final query = _searchCtrl.text.trim().toLowerCase();

    return spots.where((spot) {
      final matchesStatus = _status == 'all' || spot.status == _status;
      final matchesSearch = query.isEmpty ||
          spot.title.toLowerCase().contains(query) ||
          spot.barangay.toLowerCase().contains(query) ||
          spot.city.toLowerCase().contains(query);

      return matchesStatus && matchesSearch;
    }).toList(growable: false);
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
            icon: const Icon(Icons.add_location_alt_rounded),
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
          _ensureSuggestions(load.profile, load.spots);
          final spots = _filtered(load.spots);

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ResponsivePageContainer(
              children: [
                _SpotTabs(
                  selectedIndex: _tabIndex,
                  onChanged: (index) => setState(() => _tabIndex = index),
                ),
                const SizedBox(height: 16),
                if (_tabIndex == 0) ...[
                  _SpotToolbar(
                    controller: _searchCtrl,
                    status: _status,
                    onStatusChanged: (value) =>
                        setState(() => _status = value),
                  ),
                  const SizedBox(height: 16),
                  if (spots.isEmpty)
                    _SavedSpotsEmptyState(
                      city: load.profile.assignedCity,
                      onAddManual: () => _openForm(),
                    )
                  else
                    _SpotGrid(
                      spots: spots,
                      onEdit: (spot) => _openForm(spot: spot),
                      onArchive: (spot) => _archive(load.profile, spot),
                    ),
                ] else
                  _AiSuggestionsSection(
                    city: load.profile.assignedCity,
                    future: _suggestionsFuture!,
                    usingFallback: _usingAiFallbackSuggestions,
                    onRefresh: () =>
                        _refreshSuggestions(load.profile, load.spots),
                    onAddSuggestion: (suggestion) =>
                        _openForm(suggestion: suggestion),
                    onAddManual: () => _openForm(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SpotTabs extends StatelessWidget {
  const _SpotTabs({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = const [
      (label: 'Active Spots', icon: Icons.place_rounded),
      (label: 'AI Suggested Spots', icon: Icons.auto_awesome_rounded),
    ];

    return DashboardSectionCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          Widget buildTab(int index) {
            final selected = selectedIndex == index;
            final tab = tabs[index];
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color:
                      selected ? SubTenantColors.blue : const Color(0xFFF8FBFF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        selected ? SubTenantColors.blue : SubTenantColors.line,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tab.icon,
                      size: 18,
                      color: selected ? Colors.white : SubTenantColors.muted,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        tab.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              selected ? Colors.white : SubTenantColors.text,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildTab(0),
                const SizedBox(height: 10),
                buildTab(1),
              ],
            );
          }

          return Flex(
            direction: Axis.horizontal,
            children: List.generate(tabs.length, (index) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == tabs.length - 1 ? 0 : 10,
                  ),
                  child: buildTab(index),
                ),
              );
            }),
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
    final desktop = Responsive.isDesktop(context);

    return DashboardSectionCard(
      child: Flex(
        direction: desktop ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment:
            desktop ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
        children: [
          if (desktop)
            Expanded(
              child: SubTenantSearchBar(
                controller: controller,
                hintText: 'Search tourist spots...',
                onChanged: (_) {},
              ),
            )
          else
            SubTenantSearchBar(
              controller: controller,
              hintText: 'Search tourist spots...',
              onChanged: (_) {},
            ),
          SizedBox(width: desktop ? 14 : 0, height: desktop ? 0 : 12),
          SubTenantFilterChips(
            values: const ['all', 'active', 'maintenance', 'archived'],
            selected: status,
            onSelected: onStatusChanged,
          ),
        ],
      ),
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
        final columns = width >= 900 ? 3 : width >= 520 ? 2 : 1;
        const spacing = 14.0;
        final cardWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: spots
              .map(
                (spot) => SizedBox(
                  width: cardWidth,
                  child: _SpotImageCard(
                    spot: spot,
                    onEdit: () => onEdit(spot),
                    onArchive:
                        spot.status == 'archived' ? null : () => onArchive(spot),
                  ),
                ),
              )
              .toList(growable: false),
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
    return GestureDetector(
      onTap: onEdit,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE8EEF6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .07),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
              child: SizedBox(
                height: 178,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    spot.imageUrl.isEmpty
                        ? Container(
                            color: const Color(0xFFEAF2FF),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.place_rounded,
                              color: SubTenantColors.blue,
                              size: 42,
                            ),
                          )
                        : Image.network(
                            spot.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: const Color(0xFFEAF2FF),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.image_not_supported_rounded,
                                color: SubTenantColors.lightMuted,
                                size: 32,
                              ),
                            ),
                          ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: .58),
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
                    if (spot.rating > 0)
                      Positioned(
                        top: 10,
                        right: 48,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .52),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFF59E0B),
                                size: 13,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                spot.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _SpotCardMenu(
                        onEdit: onEdit,
                        onArchive: onArchive,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SubTenantColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        size: 13,
                        color: SubTenantColors.blue,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            if (spot.barangay.isNotEmpty) spot.barangay,
                            spot.city,
                          ].join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SubTenantColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
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

class _SpotCardMenu extends StatelessWidget {
  const _SpotCardMenu({required this.onEdit, this.onArchive});

  final VoidCallback onEdit;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Spot actions',
      onSelected: (value) {
        if (value == 'edit') onEdit();
        if (value == 'archive') onArchive?.call();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit Spot')),
        if (onArchive != null)
          const PopupMenuItem(value: 'archive', child: Text('Archive Spot')),
      ],
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}

class _AiSuggestionsSection extends StatelessWidget {
  const _AiSuggestionsSection({
    required this.city,
    required this.future,
    required this.usingFallback,
    required this.onRefresh,
    required this.onAddSuggestion,
    required this.onAddManual,
  });

  final String city;
  final Future<List<CitySpotSuggestion>> future;
  final bool usingFallback;
  final VoidCallback onRefresh;
  final ValueChanged<CitySpotSuggestion> onAddSuggestion;
  final VoidCallback onAddManual;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: SubTenantColors.gradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Suggestions',
                      style: TextStyle(
                        color: SubTenantColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      usingFallback
                          ? 'No Google Places results yet. Showing AI-generated spot ideas for $city.'
                          : 'Uses Google Places city logic first, then hides saved duplicates in $city.',
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRefresh,
                tooltip: 'Refresh AI suggestions',
                icon: const Icon(Icons.refresh_rounded),
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
                return _SuggestionMessageCard(
                  icon: Icons.cloud_off_rounded,
                  title: 'Suggestions are unavailable right now',
                  message:
                      'We could not generate suggestions for $city yet. Try again or add a tourist spot manually.',
                  primaryLabel: 'Regenerate',
                  onPrimary: onRefresh,
                  secondaryLabel: 'Add Manually',
                  onSecondary: onAddManual,
                );
              }

              final suggestions = snapshot.data ?? const <CitySpotSuggestion>[];
              if (suggestions.isEmpty) {
                return _SuggestionMessageCard(
                  icon: Icons.travel_explore_rounded,
                  title: 'No suggestions available yet',
                  message:
                      'No Google Places or AI fallback suggestions are available for $city right now. You can still add a tourist spot manually.',
                  primaryLabel: 'Refresh Suggestions',
                  onPrimary: onRefresh,
                  secondaryLabel: 'Add Manually',
                  onSecondary: onAddManual,
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final desktop = Responsive.isDesktop(context);
                  final cardWidth =
                      desktop ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: suggestions
                        .map(
                          (suggestion) => SizedBox(
                            width: cardWidth,
                            child: _AiSuggestionCard(
                              suggestion: suggestion,
                              onAdd: () => onAddSuggestion(suggestion),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AiSuggestionCard extends StatelessWidget {
  const _AiSuggestionCard({required this.suggestion, required this.onAdd});

  final CitySpotSuggestion suggestion;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SubTenantDashboardCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: suggestion.imageForCard.isEmpty
                  ? Container(
                      color: const Color(0xFFE4ECF7),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.travel_explore_rounded,
                        color: SubTenantColors.lightMuted,
                        size: 28,
                      ),
                    )
                  : Image.network(
                      suggestion.imageForCard,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: const Color(0xFFE4ECF7),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_not_supported_rounded,
                          color: SubTenantColors.lightMuted,
                          size: 28,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SuggestionChip(
                icon: Icons.category_rounded,
                label: suggestion.category,
              ),
              if (suggestion.rating > 0)
                _SuggestionChip(
                  icon: Icons.star_rounded,
                  label: suggestion.rating.toStringAsFixed(1),
                  accent: const Color(0xFFF59E0B),
                ),
              _SuggestionChip(
                icon: Icons.auto_awesome_rounded,
                label: suggestion.id.startsWith('ai-') ? 'AI Idea' : 'Google',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            suggestion.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SubTenantColors.text,
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            suggestion.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SubTenantColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.32,
            ),
          ),
          const SizedBox(height: 10),
          _SuggestionLine(
            icon: Icons.place_outlined,
            text: suggestion.address.isEmpty
                ? '${suggestion.city}, ${suggestion.province}'
                : suggestion.address,
          ),
          const SizedBox(height: 8),
          _SuggestionLine(
            icon: Icons.lightbulb_outline_rounded,
            text: suggestion.reason,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: SubTenantGradientButton(
              label: 'Add as Tourist Spot',
              icon: Icons.add_location_alt_rounded,
              onPressed: onAdd,
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionLine extends StatelessWidget {
  const _SuggestionLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: SubTenantColors.blue),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: SubTenantColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggestionLoadingState extends StatelessWidget {
  const _SuggestionLoadingState({required this.city});

  final String city;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SubTenantColors.backgroundAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Loading AI suggestions for $city...',
              style: const TextStyle(
                color: SubTenantColors.muted,
                fontWeight: FontWeight.w800,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: SubTenantColors.blue.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: SubTenantColors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: SubTenantColors.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onPrimary,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(primaryLabel),
              ),
              OutlinedButton.icon(
                onPressed: onSecondary,
                icon: const Icon(Icons.add_rounded),
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
  const _SavedSpotsEmptyState({required this.city, required this.onAddManual});

  final String city;
  final VoidCallback onAddManual;

  @override
  Widget build(BuildContext context) {
    return EmptyStateCard(
      icon: Icons.place_outlined,
      title: 'No saved tourist spots yet',
      message:
          'Only tourist spots assigned to $city appear here. You can add one manually or start with an AI suggestion above.',
      actionLabel: 'Add Tourist Spot',
      onAction: onAddManual,
    );
  }
}

class _SpotListLoad {
  const _SpotListLoad({required this.profile, required this.spots});

  final SubTenantProfile profile;
  final List<SubTenantSpot> spots;
}

class _AiSpotTemplate {
  const _AiSpotTemplate({
    required this.suffix,
    required this.category,
    required this.description,
    required this.reason,
    required this.latOffset,
    required this.lngOffset,
  });

  final String suffix;
  final String category;
  final String description;
  final String reason;
  final double latOffset;
  final double lngOffset;
}
