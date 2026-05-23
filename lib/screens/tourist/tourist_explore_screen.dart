import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/widgets/app_bottom_nav_tourist.dart';
import 'package:touristrike/components/tourist/ai_chatbot_floating_widget.dart';
import 'package:touristrike/screens/tourist/package_details_screen.dart';
import 'spot_details_screen.dart';
import 'tourist_location_state.dart';

enum ExploreContentType { spots, packages }

class TouristExploreScreen extends StatefulWidget {
  const TouristExploreScreen({super.key});

  @override
  State<TouristExploreScreen> createState() => _TouristExploreScreenState();
}

class _TouristExploreScreenState extends State<TouristExploreScreen> {
  final supabase = Supabase.instance.client;
  final CitySpotSuggestionService _spotSuggestionService =
      CitySpotSuggestionService();

  static const LatLng _defaultCenter = LatLng(14.9597, 120.9206);

  static final LatLngBounds _bulacanBounds = LatLngBounds(
    southwest: const LatLng(14.35, 120.35),
    northeast: const LatLng(15.55, 121.55),
  );

  int _navIndex = 1;
  ExploreContentType _selectedType = ExploreContentType.spots;
  String? _selectedSpotCategory;
  String? _selectedPackageCategory;

  final _searchCtrl = TextEditingController();
  final List<_SpotModel> _googleSearchSpots = [];
  bool _isSearchingGoogle = false;
  Timer? _searchDebounce;
  late Future<_ExploreData> _future;

  LatLng? _lastKnownCenter;
  Set<String> _activeMunicipalities = {};

  static const List<_CategoryChipModel> _spotCategories = [
    _CategoryChipModel('Historical', icon: Icons.account_balance_outlined),
    _CategoryChipModel('Nature', icon: Icons.terrain_outlined),
    _CategoryChipModel('Resort', icon: Icons.pool_rounded),
    _CategoryChipModel('Food', icon: Icons.restaurant_outlined),
    _CategoryChipModel('Religious', icon: Icons.church_outlined),
    _CategoryChipModel('Museum', icon: Icons.museum_outlined),
    _CategoryChipModel('Park', icon: Icons.park_outlined),
  ];

  static const List<_CategoryChipModel> _packageCategoryOptions = [
    _CategoryChipModel('Adventure', icon: Icons.hiking_rounded),
    _CategoryChipModel('Family', icon: Icons.family_restroom_rounded),
    _CategoryChipModel('Nature', icon: Icons.forest_rounded),
    _CategoryChipModel('Historical', icon: Icons.account_balance_outlined),
    _CategoryChipModel('Budget', icon: Icons.savings_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _future = _loadExploreData();
    touristLocationStore.addListener(_onLocationSelectionChanged);
    _loadActiveMunicipalities();
  }

  @override
  void dispose() {
    touristLocationStore.removeListener(_onLocationSelectionChanged);
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<_ExploreData> _loadExploreData() async {
    final manualArea = touristLocationStore.value.manualArea;
    final usingManualLocation = manualArea != null;

    late final LatLng center;
    late final String? municipality;

    if (manualArea != null) {
      center = manualArea.center;
      municipality = manualArea.name;
    } else {
      center = await _resolveCurrentCenter();
      municipality = _detectBulacanMunicipality(center);
    }

    final insideBulacan = municipality != null;

    final spots = municipality == null
        ? <_SpotModel>[]
        : await _loadMunicipalitySpots(
            municipality: municipality,
            center: center,
          );

    final packages = await _loadAdminPackages(municipality);

    return _ExploreData(
      center: center,
      municipality: municipality,
      insideBulacan: insideBulacan,
      usingManualLocation: usingManualLocation,
      spots: spots,
      packages: packages,
    );
  }

  void _onLocationSelectionChanged() {
    if (!mounted) return;
    setState(() => _future = _loadExploreData());
  }

  Future<void> _loadActiveMunicipalities() async {
    try {
      final rows = await supabase
          .from('subtenant_details')
          .select('city')
          .eq('is_active', true);
      if (!mounted) return;
      setState(() {
        _activeMunicipalities = {
          for (final row in rows as List)
            if (row['city'] is String &&
                (row['city'] as String).trim().isNotEmpty)
              (row['city'] as String).trim(),
        };
      });
    } catch (_) {}
  }

  Future<LatLng> _resolveCurrentCenter() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return _lastKnownCenter ?? _defaultCenter;

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _lastKnownCenter ?? _defaultCenter;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12));

      final center = LatLng(position.latitude, position.longitude);
      _lastKnownCenter = center;

      return center;
    } catch (e) {
      debugPrint('EXPLORE location fallback: $e');
      return _lastKnownCenter ?? _defaultCenter;
    }
  }

  Future<List<_SpotModel>> _loadMunicipalitySpots({
    required String municipality,
    required LatLng center,
  }) async {
    final results = await Future.wait([
      _loadSavedTouristSpots(municipality: municipality, center: center),
      _loadGoogleFamousSpots(municipality: municipality, center: center),
    ]);

    final merged = <_SpotModel>[];
    final seen = <String>{};

    for (final spot in [...results[0], ...results[1]]) {
      final googleKey = spot.googlePlaceId.trim().toLowerCase();
      final fallbackKey =
          '${_normalText(spot.title)}|${_normalText(spot.municipality)}';
      final key = googleKey.isNotEmpty ? 'g:$googleKey' : 't:$fallbackKey';

      if (seen.add(key)) {
        merged.add(spot);
      }
    }

    merged.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return merged;
  }

  Future<List<_SpotModel>> _loadGoogleFamousSpots({
    required String municipality,
    required LatLng center,
  }) async {
    final suggestions = await _spotSuggestionService.fetchSuggestions(
      city: municipality,
      province: 'Bulacan',
      center: center,
      limit: 20,
    );

    return suggestions.map((suggestion) {
      final category = _normalizeSpotCategory(
        suggestion.category,
        placeTypes: suggestion.placeTypes,
      );

      return _SpotModel(
        id: suggestion.id,
        title: suggestion.title,
        address: suggestion.address,
        distance: _distanceText(suggestion.distanceKm),
        distanceKm: suggestion.distanceKm,
        tag: category,
        category: category,
        rating: suggestion.rating,
        userRatingsTotal: 0,
        imageUrl: suggestion.imageForCard,
        latitude: suggestion.latitude,
        longitude: suggestion.longitude,
        openNow: null,
        types: suggestion.placeTypes,
        municipality: municipality,
        googlePlaceId: suggestion.id,
      );
    }).toList(growable: false);
  }

  Future<List<_SpotModel>> _loadSavedTouristSpots({
    required String municipality,
    required LatLng center,
  }) async {
    try {
      final responses = await Future.wait([
        supabase
            .from('tourist_spots')
            .select(
              'id, title, city, municipality, latitude, longitude, rating, image_url, description, address, barangay, source_type, google_place_id, category_id, tourist_spot_images(image_url, sort_order, is_cover)',
            )
            .neq('status', 'archived')
            .order('title', ascending: true)
            .limit(200)
            .timeout(const Duration(seconds: 15)),
        supabase
            .from('tourism_categories')
            .select('id, name')
            .limit(200)
            .timeout(const Duration(seconds: 15)),
      ]);

      final spotRows = (responses[0] as List).whereType<Map>().toList();
      final categoryRows = (responses[1] as List).whereType<Map>().toList();

      final categoryNames = <String, String>{
        for (final row in categoryRows)
          '${row['id']}': ((row['name'] as String?) ?? '').trim(),
      };

      final selectedCity = _normalText(municipality);

      return spotRows
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) {
            final city = _normalText(
              ((row['municipality'] as String?) ??
                  (row['city'] as String?) ??
                  ''),
            );
            final fallbackCity = _normalText((row['city'] as String?) ?? '');

            return city == selectedCity ||
                fallbackCity == selectedCity ||
                fallbackCity == _normalText('$municipality Bulacan') ||
                fallbackCity.contains(selectedCity);
          })
          .map((row) {
            final lat = (row['latitude'] as num?)?.toDouble() ?? 0;
            final lng = (row['longitude'] as num?)?.toDouble() ?? 0;

            final distanceKm = _haversineKm(
              center.latitude,
              center.longitude,
              lat,
              lng,
            );

            final categoryName =
                categoryNames['${row['category_id']}'] ??
                ((row['category'] as String?) ?? '');

            final resolvedMunicipality =
                ((row['municipality'] as String?)?.trim().isNotEmpty ?? false)
                    ? (row['municipality'] as String).trim()
                    : ((row['city'] as String?) ?? municipality).trim();

            final category = _normalizeSpotCategory(
              categoryName,
              title: (row['title'] as String?) ?? '',
              description: (row['description'] as String?) ?? '',
            );

            final imageUrl = _resolveSpotImageUrl(
              primaryImage: (row['image_url'] as String?) ?? '',
              imageRows: row['tourist_spot_images'] as List?,
            );

            return _SpotModel(
              id: '${row['id']}',
              title: ((row['title'] as String?) ?? 'Untitled Spot').trim(),
              address: ((row['address'] as String?) ?? '').trim(),
              distance: _distanceText(distanceKm),
              distanceKm: distanceKm,
              tag: category,
              category: category,
              rating: (row['rating'] as num?)?.toDouble() ?? 4.5,
              userRatingsTotal: 0,
              imageUrl: imageUrl,
              latitude: lat,
              longitude: lng,
              openNow: null,
              types: const [],
              municipality: resolvedMunicipality,
              googlePlaceId: ((row['google_place_id'] as String?) ?? '').trim(),
            );
          })
          .toList(growable: false);
    } catch (e) {
      debugPrint('EXPLORE saved spots unavailable: $e');
      return [];
    }
  }

  Future<List<_PackageModel>> _loadAdminPackages(String? municipality) async {
    if (municipality == null) return [];

    try {
      final rows = await supabase
          .from('tour_packages')
          .select(
            'id, title, subtitle, city, price_text, duration_text, image_url, cover_image_url, description, estimated_budget, group_size, route_distance_km, status, visibility_status',
          )
          .eq('status', 'published')
          .eq('visibility_status', 'visible')
          .order('created_at', ascending: false)
          .limit(80)
          .timeout(const Duration(seconds: 15));

      final selectedCity = _normalText(municipality);

      return (rows as List)
          .map((e) => _PackageModel.fromMap(e as Map<String, dynamic>))
          .where((p) {
        final packageCity = _normalText(p.city);

        return packageCity == selectedCity ||
            packageCity == _normalText('$municipality Bulacan') ||
            packageCity.contains(selectedCity);
      }).toList();
    } catch (e) {
      debugPrint('EXPLORE packages unavailable: $e');
      return [];
    }
  }

  String _distanceText(double km) {
    if (km < 1) return '${(km * 1000).round()} m away';
    return '${km.toStringAsFixed(1)} km away';
  }

  bool _isInsideBulacan(LatLng point) {
    return point.latitude >= _bulacanBounds.southwest.latitude &&
        point.latitude <= _bulacanBounds.northeast.latitude &&
        point.longitude >= _bulacanBounds.southwest.longitude &&
        point.longitude <= _bulacanBounds.northeast.longitude;
  }

  String? _detectBulacanMunicipality(LatLng point) {
    if (!_isInsideBulacan(point)) return null;

    TouristMunicipalityArea? nearest;
    var nearestKm = double.infinity;

    for (final area in touristBulacanMunicipalities) {
      final km = _haversineKm(
        point.latitude,
        point.longitude,
        area.center.latitude,
        area.center.longitude,
      );

      if (km < nearestKm) {
        nearestKm = km;
        nearest = area;
      }
    }

    return nearest?.name;
  }

  String _normalText(String value) {
    return value
        .toLowerCase()
        .replaceAll('Ã±', 'n')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .replaceAll(',', '')
        .replaceAll('.', '');
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180);

  bool _matchesSearch(String text) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return text.toLowerCase().contains(q);
  }

  String _normalizeSpotCategory(
    String rawCategory, {
    List<String> placeTypes = const [],
    String title = '',
    String description = '',
  }) {
    final source = [
      rawCategory,
      title,
      description,
      placeTypes.join(' '),
    ].join(' ').toLowerCase();

    if (source.contains('museum')) return 'Museum';
    if (source.contains('park') ||
        source.contains('garden') ||
        source.contains('playground')) {
      return 'Park';
    }
    if (source.contains('resort') ||
        source.contains('pool') ||
        source.contains('beach')) {
      return 'Resort';
    }
    if (source.contains('food') ||
        source.contains('restaurant') ||
        source.contains('cafe') ||
        source.contains('eat')) {
      return 'Food';
    }
    if (source.contains('religious') ||
        source.contains('church') ||
        source.contains('cathedral') ||
        source.contains('worship') ||
        source.contains('temple')) {
      return 'Religious';
    }
    if (source.contains('historic') ||
        source.contains('historical') ||
        source.contains('heritage') ||
        source.contains('monument')) {
      return 'Historical';
    }
    if (source.contains('nature') ||
        source.contains('mountain') ||
        source.contains('river') ||
        source.contains('falls') ||
        source.contains('lake') ||
        source.contains('forest')) {
      return 'Nature';
    }
    return 'Nature';
  }

  List<_SpotModel> _filteredSpots(List<_SpotModel> spots) {
    return spots.where((s) {
      final category = _selectedSpotCategory;
      final matchesCategory = category == null || s.category == category;

      return (_matchesSearch(s.title) ||
              _matchesSearch(s.address) ||
              _matchesSearch(s.municipality)) &&
          matchesCategory;
    }).toList();
  }

  List<_PackageModel> _filteredPackages(List<_PackageModel> packages) {
    final availableCategories = packages
        .expand((package) => package.filterCategories)
        .toSet();

    return packages.where((p) {
      final category = _selectedPackageCategory;
      final matchesCategory = category == null ||
          !availableCategories.contains(category) ||
          p.filterCategories.contains(category);

      return (_matchesSearch(p.title) ||
              _matchesSearch(p.description) ||
              _matchesSearch(p.city) ||
              _matchesSearch(p.price)) &&
          matchesCategory;
    }).toList();
  }

  List<_CategoryChipModel> _availablePackageCategories(
    List<_PackageModel> packages,
  ) {
    final available = packages
        .expand((package) => package.filterCategories)
        .toSet();

    return _packageCategoryOptions
        .where((chip) => available.contains(chip.label))
        .toList(growable: false);
  }

  String _resolveSpotImageUrl({
    required String primaryImage,
    required List? imageRows,
  }) {
    if (primaryImage.trim().isNotEmpty) return primaryImage.trim();
    if (imageRows == null) return '';

    final images = imageRows.whereType<Map>().map(Map<String, dynamic>.from);
    Map<String, dynamic>? preferred;

    for (final image in images) {
      if (image['is_cover'] == true) {
        preferred = image;
        break;
      }
      preferred ??= image;
    }

    return ((preferred?['image_url'] as String?) ?? '').trim();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadExploreData();
      _googleSearchSpots.clear();
      _isSearchingGoogle = false;
    });
    await _future;
  }

  void _onSearchTextChanged(String query, _ExploreData data) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();

    if (trimmed.length < 3) {
      if (_googleSearchSpots.isNotEmpty || _isSearchingGoogle) {
        setState(() {
          _googleSearchSpots.clear();
          _isSearchingGoogle = false;
        });
      }
      return;
    }

    setState(() {
      _isSearchingGoogle = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      _performGoogleSearch(trimmed, data);
    });
  }

  Future<void> _performGoogleSearch(String query, _ExploreData data) async {
    if (!mounted || data.municipality == null) return;

    try {
      final suggestions = await _spotSuggestionService.searchPlaces(
        query: query,
        city: data.municipality!,
        province: 'Bulacan',
        center: data.center,
      );

      if (!mounted || _searchCtrl.text.trim() != query) return;

      setState(() {
        _googleSearchSpots
          ..clear()
          ..addAll(suggestions.map((suggestion) {
            final category = _normalizeSpotCategory(
              suggestion.category,
              placeTypes: suggestion.placeTypes,
            );
            return _SpotModel(
              id: suggestion.id,
              title: suggestion.title,
              address: suggestion.address,
              distance: suggestion.distanceText,
              distanceKm: suggestion.distanceKm,
              tag: category,
              category: category,
              rating: suggestion.rating,
              userRatingsTotal: 0,
              imageUrl: suggestion.imageUrl,
              latitude: suggestion.latitude,
              longitude: suggestion.longitude,
              openNow: null,
              types: suggestion.placeTypes,
              municipality: data.municipality!,
              googlePlaceId: suggestion.id,
            );
          }));
        _isSearchingGoogle = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _googleSearchSpots.clear();
        _isSearchingGoogle = false;
      });
    }
  }

  Future<void> _selectMunicipality() async {
    final selected = await showModalBottomSheet<TouristMunicipalityArea>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            final selectedArea = touristLocationStore.value.manualArea;

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8E3F1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 18, 18, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_city_rounded,
                          color: Color(0xFF2A86FF),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Choose location in Bulacan',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                      itemCount: touristBulacanMunicipalities.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final m = touristBulacanMunicipalities[i];
                        final selectedNow = selectedArea?.name == m.name;
                        final isActive = _activeMunicipalities.contains(m.name);

                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          tileColor: selectedNow
                              ? const Color(0xFFEFF6FF)
                              : const Color(0xFFF8FAFC),
                          leading: CircleAvatar(
                            backgroundColor: selectedNow
                                ? const Color(0xFF2A86FF)
                                : isActive
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFE2E8F0),
                            child: Icon(
                              selectedNow
                                  ? Icons.check_rounded
                                  : isActive
                                      ? Icons.store_rounded
                                      : Icons.place_rounded,
                              color: selectedNow
                                  ? Colors.white
                                  : isActive
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFF64748B),
                            ),
                          ),
                          title: Text(
                            m.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          subtitle: Text(
                            isActive
                                ? 'Has packages & spots'
                                : 'No listings yet',
                            style: TextStyle(
                              color: isActive
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                          onTap: () => Navigator.pop(context, m),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (selected == null) return;

    _lastKnownCenter = selected.center;
    touristLocationStore.useManualLocation(selected);
  }

  void _usePhoneLocation() {
    final wasManual = touristLocationStore.value.isManual;
    touristLocationStore.usePhoneLocation();

    if (!wasManual) {
      setState(() => _future = _loadExploreData());
    }
  }

  void _openSpotDetails(_SpotModel spot) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TouristSpotDetailsScreen(
          spot: TouristSpotDetailsData(
            id: spot.id,
            title: spot.title,
            address: spot.address,
            distance: spot.distance,
            distanceKm: spot.distanceKm,
            tag: spot.tag,
            rating: spot.rating,
            userRatingsTotal: spot.userRatingsTotal,
            imageUrl: spot.imageUrl,
            latitude: spot.latitude,
            longitude: spot.longitude,
            openNow: spot.openNow,
            municipality: spot.municipality,
          ),
          googleMapsApiKey: CitySpotSuggestionService.defaultGoogleMapsApiKey,
        ),
      ),
    );
  }

  void _selectContentType(ExploreContentType type) {
    if (_selectedType == type) return;
    setState(() => _selectedType = type);
  }

  void _openFilterSheet(List<_PackageModel> packages) {
    final packageCategories = _availablePackageCategories(packages);
    final categories = _selectedType == ExploreContentType.spots
        ? _spotCategories
        : packageCategories;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            final selectedCategory = _selectedType == ExploreContentType.spots
                ? _selectedSpotCategory
                : _selectedPackageCategory;

            return Container(
              padding: EdgeInsets.fromLTRB(
                18,
                12,
                18,
                MediaQuery.of(context).padding.bottom + 22,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD8E3F1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.tune_rounded,
                          color: Color(0xFF2A86FF),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedType == ExploreContentType.spots
                              ? 'Filter spots'
                              : 'Filter packages',
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_selectedType == ExploreContentType.spots) {
                              _selectedSpotCategory = null;
                            } else {
                              _selectedPackageCategory = null;
                            }
                          });
                          modalSetState(() {});
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (categories.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Text(
                        'No filters available for this section yet.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: categories.map((chip) {
                        final selected = selectedCategory == chip.label;

                        return _CategoryChip(
                          label: chip.label,
                          icon: chip.icon,
                          selected: selected,
                          onTap: () {
                            setState(() {
                              if (_selectedType == ExploreContentType.spots) {
                                _selectedSpotCategory =
                                    selected ? null : chip.label;
                              } else {
                                _selectedPackageCategory =
                                    selected ? null : chip.label;
                              }
                            });
                            modalSetState(() {});
                          },
                        );
                      }).toList(growable: false),
                    ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: _GradientButton(
                      text: 'Apply Filter',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool get _hasActiveFilter {
    return _selectedType == ExploreContentType.spots
        ? _selectedSpotCategory != null
        : _selectedPackageCategory != null;
  }

  String? get _activeFilterLabel {
    return _selectedType == ExploreContentType.spots
        ? _selectedSpotCategory
        : _selectedPackageCategory;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom;

    const navBodyH = 92.0;
    final navTotalH = navBodyH + bottomInset;

    return TouristAiChatbotWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFF6FAFF),
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Positioned.fill(
                child: FutureBuilder<_ExploreData>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const _LoadingState();
                    }

                    if (snap.hasError) {
                      return _ErrorState(
                        error: snap.error.toString(),
                        onRetry: _refresh,
                      );
                    }

                    final data = snap.data!;
                    final query = _searchCtrl.text.trim();
                    final isGoogleSearch = query.length >= 3 && data.municipality != null;
                    final spots = isGoogleSearch
                        ? List<_SpotModel>.unmodifiable(_googleSearchSpots)
                        : _filteredSpots(data.spots);
                    final packages = _filteredPackages(data.packages);

                    final showSpots =
                        _selectedType == ExploreContentType.spots;
                    final showPackages =
                        _selectedType == ExploreContentType.packages;

                    return RefreshIndicator(
                      color: const Color(0xFF2A86FF),
                      onRefresh: _refresh,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          16,
                          10,
                          16,
                          navTotalH + 18,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ExploreHeader(onRefresh: _refresh),
                            const SizedBox(height: 12),
                            _LocationBanner(
                              municipality: data.municipality,
                              insideBulacan: data.insideBulacan,
                              usingManualLocation: data.usingManualLocation,
                              onPickLocation: _selectMunicipality,
                              onUsePhoneLocation: _usePhoneLocation,
                            ),
                            const SizedBox(height: 16),
                            _SearchFilterRow(
                              controller: _searchCtrl,
                              onChanged: (query) => _onSearchTextChanged(query, data),
                              hasActiveFilter: _hasActiveFilter,
                              onFilterTap: () => _openFilterSheet(data.packages),
                            ),
                            const SizedBox(height: 12),
                            _ExploreTabBar(
                              selectedType: _selectedType,
                              onSelected: _selectContentType,
                              spotsCount: spots.length,
                              packagesCount:
                                  _filteredPackages(data.packages).length,
                            ),
                            if (_activeFilterLabel != null) ...[
                              const SizedBox(height: 12),
                              _ActiveFilterPill(
                                label: _activeFilterLabel!,
                                onClear: () {
                                  setState(() {
                                    if (_selectedType ==
                                        ExploreContentType.spots) {
                                      _selectedSpotCategory = null;
                                    } else {
                                      _selectedPackageCategory = null;
                                    }
                                  });
                                },
                              ),
                            ],
                            const SizedBox(height: 18),
                            if (showSpots) ...[
                              _SectionRow(
                                title: data.municipality == null
                                    ? 'Famous Spots'
                                    : 'Famous Spots in ${data.municipality}',
                                subtitle:
                                    '${spots.length} result${spots.length == 1 ? '' : 's'}',
                              ),
                              const SizedBox(height: 12),
                              if (spots.isEmpty)
                                if (isGoogleSearch && _isSearchingGoogle)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 24),
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF2A86FF),
                                      ),
                                    ),
                                  )
                                else
                                  const _EmptyState(
                                    icon: Icons.travel_explore_rounded,
                                    title: 'No spots found',
                                    message:
                                        'Try another keyword, filter, or make sure your location is inside Bulacan.',
                                  )
                              else
                                ...spots.map(
                                  (s) => Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: _PopularSpotCard(
                                      model: s,
                                      onTap: () => _openSpotDetails(s),
                                    ),
                                  ),
                                ),
                            ],
                            if (showPackages) ...[
                              _SectionRow(
                                title: data.municipality == null
                                    ? 'Packages'
                                    : 'Packages in ${data.municipality}',
                                subtitle:
                                    '${packages.length} result${packages.length == 1 ? '' : 's'}',
                              ),
                              const SizedBox(height: 12),
                              if (packages.isEmpty)
                                const _EmptyState(
                                  icon: Icons.card_travel_rounded,
                                  title: 'No packages available',
                                  message:
                                      'Admin-created packages for this municipality will appear here.',
                                )
                              else
                                ...packages.map(
                                  (p) => Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: _PackageCard(
                                      model: p,
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                PackageDetailsScreen(
                                              packageId: p.id,
                                            ),
                                          ),
                                        );
                                      },
                                      onBook: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                PackageDetailsScreen(
                                              packageId: p.id,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AppBottomNav(
                  selectedIndex: _navIndex,
                  onSelect: (i) => setState(() => _navIndex = i),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExploreHeader extends StatelessWidget {
  const _ExploreHeader({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 48),
        const Expanded(
          child: Text(
            'Explore',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: -0.4,
            ),
          ),
        ),
        IconButton(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF2A86FF)),
        ),
      ],
    );
  }
}

class _ExploreData {
  final LatLng center;
  final String? municipality;
  final bool insideBulacan;
  final bool usingManualLocation;
  final List<_SpotModel> spots;
  final List<_PackageModel> packages;

  const _ExploreData({
    required this.center,
    required this.municipality,
    required this.insideBulacan,
    required this.usingManualLocation,
    required this.spots,
    required this.packages,
  });
}

class _CategoryChipModel {
  final String label;
  final IconData? icon;

  const _CategoryChipModel(this.label, {required this.icon});
}

class _SpotModel {
  final String id;
  final String title;
  final String address;
  final String distance;
  final double distanceKm;
  final String tag;
  final String category;
  final double rating;
  final int userRatingsTotal;
  final String imageUrl;
  final double latitude;
  final double longitude;
  final bool? openNow;
  final List<String> types;
  final String municipality;
  final String googlePlaceId;

  const _SpotModel({
    required this.id,
    required this.title,
    required this.address,
    required this.distance,
    required this.distanceKm,
    required this.tag,
    required this.category,
    required this.rating,
    required this.userRatingsTotal,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.openNow,
    required this.types,
    required this.municipality,
    required this.googlePlaceId,
  });
}

class _PackageModel {
  final dynamic id;
  final String title;
  final double rating;
  final String description;
  final String city;
  final String hoursText;
  final String stopsText;
  final String price;
  final String imageUrl;
  final String badgeText;
  final IconData? badgeIcon;
  final Color? badgeBg;
  final Color? badgeFg;
  final List<String> filterCategories;

  const _PackageModel({
    required this.id,
    required this.title,
    required this.rating,
    required this.description,
    required this.city,
    required this.hoursText,
    required this.stopsText,
    required this.price,
    required this.imageUrl,
    required this.badgeText,
    required this.badgeIcon,
    required this.badgeBg,
    required this.badgeFg,
    required this.filterCategories,
  });

  factory _PackageModel.fromMap(Map<String, dynamic> m) {
    final cover = (m['cover_image_url'] as String?) ?? '';
    final img = cover.isNotEmpty ? cover : ((m['image_url'] as String?) ?? '');

    final distance = (m['route_distance_km'] as num?)?.toDouble();
    final groupSize = (m['group_size'] as num?)?.toInt();

    final categories = _derivePackageCategories(m);

    return _PackageModel(
      id: m['id'],
      title: (m['title'] as String?) ?? 'Untitled Package',
      rating: 4.8,
      description: (m['description'] as String?) ??
          (m['subtitle'] as String?) ??
          'Admin-created tour package.',
      city: (m['city'] as String?) ?? 'Bulacan',
      hoursText: (m['duration_text'] as String?) ?? 'Flexible',
      stopsText: distance == null
          ? (groupSize == null ? 'Multiple stops' : '$groupSize pax')
          : '${distance.toStringAsFixed(1)} km route',
      price: (m['price_text'] as String?) ?? 'Ask admin',
      imageUrl: img,
      badgeText: 'Admin',
      badgeIcon: Icons.verified_rounded,
      badgeBg: const Color(0xFFEAF2FF),
      badgeFg: const Color(0xFF2A86FF),
      filterCategories: categories,
    );
  }

  static List<String> _derivePackageCategories(Map<String, dynamic> m) {
    final title = ((m['title'] as String?) ?? '').toLowerCase();
    final subtitle = ((m['subtitle'] as String?) ?? '').toLowerCase();
    final description = ((m['description'] as String?) ?? '').toLowerCase();
    final city = ((m['city'] as String?) ?? '').toLowerCase();
    final priceText = ((m['price_text'] as String?) ?? '').toLowerCase();
    final source = '$title $subtitle $description $city $priceText';
    final tags = <String>{};

    if (source.contains('adventure') ||
        source.contains('hike') ||
        source.contains('river') ||
        source.contains('trail') ||
        source.contains('outdoor')) {
      tags.add('Adventure');
    }
    if (source.contains('family') ||
        source.contains('kids') ||
        source.contains('group') ||
        source.contains('pax')) {
      tags.add('Family');
    }
    if (source.contains('nature') ||
        source.contains('falls') ||
        source.contains('mountain') ||
        source.contains('park') ||
        source.contains('garden')) {
      tags.add('Nature');
    }
    if (source.contains('historical') ||
        source.contains('historic') ||
        source.contains('heritage') ||
        source.contains('museum') ||
        source.contains('church')) {
      tags.add('Historical');
    }

    final budget = (m['estimated_budget'] as num?)?.toDouble();
    if (source.contains('budget') ||
        source.contains('affordable') ||
        source.contains('cheap') ||
        (budget != null && budget > 0 && budget <= 1500)) {
      tags.add('Budget');
    }

    return tags.toList(growable: false);
  }
}

class _LocationBanner extends StatelessWidget {
  const _LocationBanner({
    required this.municipality,
    required this.insideBulacan,
    required this.usingManualLocation,
    required this.onPickLocation,
    required this.onUsePhoneLocation,
  });

  final String? municipality;
  final bool insideBulacan;
  final bool usingManualLocation;
  final VoidCallback onPickLocation;
  final VoidCallback onUsePhoneLocation;

  @override
  Widget build(BuildContext context) {
    final title = municipality == null
        ? 'Choose your Bulacan location'
        : '$municipality, Bulacan';

    final subtitle = municipality == null
        ? 'Tap to select a Bulacan city or use GPS inside Bulacan.'
        : usingManualLocation
            ? 'Manual selection is synced with Home. Tap GPS to use your phone location.'
            : 'Using phone GPS. Famous spots and packages are filtered for this city.';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onPickLocation,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFEAF2FF)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A86FF),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  insideBulacan
                      ? Icons.auto_awesome_rounded
                      : Icons.location_searching_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _LocationActionButton(
                icon: usingManualLocation
                    ? Icons.gps_fixed_rounded
                    : Icons.my_location_rounded,
                onTap: onUsePhoneLocation,
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF64748B),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationActionButton extends StatelessWidget {
  const _LocationActionButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: const BoxDecoration(
          color: Color(0xFFEAF2FF),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: const Color(0xFF2A86FF), size: 21),
      ),
    );
  }
}

class _SearchFilterRow extends StatelessWidget {
  const _SearchFilterRow({
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
    required this.hasActiveFilter,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;
  final bool hasActiveFilter;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.045),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 15),
                const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Search places or packages...',
                      hintStyle: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF94A3B8),
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (controller.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: onFilterTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: hasActiveFilter
                  ? const Color(0xFF2A86FF)
                  : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: hasActiveFilter
                    ? const Color(0xFF2A86FF)
                    : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.045),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.tune_rounded,
                  color: hasActiveFilter
                      ? Colors.white
                      : const Color(0xFF2A86FF),
                ),
                if (hasActiveFilter)
                  Positioned(
                    top: 13,
                    right: 13,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ExploreTabBar extends StatelessWidget {
  const _ExploreTabBar({
    required this.selectedType,
    required this.onSelected,
    required this.spotsCount,
    required this.packagesCount,
  });

  final ExploreContentType selectedType;
  final ValueChanged<ExploreContentType> onSelected;
  final int spotsCount;
  final int packagesCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCEBFF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ExploreTabButton(
              label: 'Spots',
              count: spotsCount,
              icon: Icons.place_rounded,
              selected: selectedType == ExploreContentType.spots,
              onTap: () => onSelected(ExploreContentType.spots),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ExploreTabButton(
              label: 'Packages',
              count: packagesCount,
              icon: Icons.card_travel_rounded,
              selected: selectedType == ExploreContentType.packages,
              onTap: () => onSelected(ExploreContentType.packages),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreTabButton extends StatelessWidget {
  const _ExploreTabButton({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : const Color(0xFF2A86FF);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2A86FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2A86FF).withValues(alpha: 0.22),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.20)
                    : Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: fg,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveFilterPill extends StatelessWidget {
  const _ActiveFilterPill({
    required this.label,
    required this.onClear,
  });

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 9, 8, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDCEBFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.filter_alt_rounded, size: 16, color: Color(0xFF2A86FF)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF2A86FF),
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: Color(0xFF2A86FF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFF2A86FF) : const Color(0xFFF8FAFC);
    final fg = selected ? Colors.white : const Color(0xFF334155);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
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
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2A86FF),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8EEF6)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF2FF),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF2A86FF)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                    height: 1.3,
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

class _PopularSpotCard extends StatelessWidget {
  const _PopularSpotCard({
    required this.model,
    required this.onTap,
  });

  final _SpotModel model;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE8EEF6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 22,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Column(
              children: [
                SizedBox(
                  height: 205,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        model.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: const Color(0xFFE2E8F0),
                          child: const Center(
                            child: Icon(
                              Icons.image_not_supported_rounded,
                              color: Color(0xFF94A3B8),
                            ),
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
                                Colors.black.withValues(alpha: 0.05),
                                Colors.black.withValues(alpha: 0.62),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _ImageChip(
                          icon: Icons.category_rounded,
                          text: model.tag,
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _ImageChip(
                          icon: Icons.star_rounded,
                          text: model.rating.toStringAsFixed(1),
                        ),
                      ),
                      Positioned(
                        left: 15,
                        right: 15,
                        bottom: 15,
                        child: Text(
                          model.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.near_me_rounded,
                            size: 18,
                            color: Color(0xFF2A86FF),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            model.distance,
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'View details',
                            style: TextStyle(
                              color: Color(0xFF2A86FF),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Color(0xFF2A86FF),
                            size: 14,
                          ),
                        ],
                      ),
                      if (model.address.isNotEmpty) ...[
                        const SizedBox(height: 11),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                model.address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
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

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.model,
    required this.onBook,
    required this.onTap,
  });

  final _PackageModel model;
  final VoidCallback onBook;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE8EEF6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 22,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 190,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (model.imageUrl.isNotEmpty)
                      Image.network(
                        model.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _PackageImageFallback(),
                      )
                    else
                      _PackageImageFallback(),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.04),
                              Colors.black.withValues(alpha: 0.38),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (model.badgeText.isNotEmpty)
                      Positioned(
                        top: 13,
                        left: 13,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: model.badgeBg ?? const Color(0xFFEAF2FF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                model.badgeIcon ?? Icons.verified_rounded,
                                size: 16,
                                color: model.badgeFg ?? const Color(0xFF2A86FF),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                model.badgeText,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                  color:
                                      model.badgeFg ?? const Color(0xFF2A86FF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.title,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      model.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.2,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MiniInfoPill(
                          icon: Icons.schedule_rounded,
                          text: model.hoursText,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MiniInfoPill(
                            icon: Icons.location_on_outlined,
                            text: model.stopsText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(height: 1, color: const Color(0xFFE7EEF7)),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Price',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                model.price,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF2A86FF),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 46,
                          width: 122,
                          child: _GradientButton(
                            text: 'Book Now',
                            onPressed: onBook,
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
      ),
    );
  }
}

class _MiniInfoPill extends StatelessWidget {
  const _MiniInfoPill({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageChip extends StatelessWidget {
  const _ImageChip({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2A86FF), size: 16),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageImageFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF2FF),
      child: const Center(
        child: Icon(
          Icons.map_rounded,
          color: Color(0xFF2A86FF),
          size: 34,
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6FAFF),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF2A86FF)),
              SizedBox(height: 16),
              Text(
                'Loading explore guide...',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.error,
    required this.onRetry,
  });

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6FAFF),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: Color(0xFFDC2626),
                size: 42,
              ),
              const SizedBox(height: 14),
              const Text(
                'Unable to load explore',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: _GradientButton(
                  text: 'Retry',
                  onPressed: onRetry,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.text,
    required this.onPressed,
  });

  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF), Color(0xFF1D4ED8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A86FF).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14.5,
          ),
        ),
      ),
    );
  }
}