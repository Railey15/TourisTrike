import 'dart:convert' show jsonDecode;
import 'dart:math' show sqrt, sin, cos, atan2;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_package_itinerary_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

// ─── Internal data holder ────────────────────────────────────────────────────

class _BuilderData {
  const _BuilderData({
    required this.profile,
    required this.spots,
    required this.categories,
    required this.popularIds,
    required this.googleSuggestions,
  });

  final SubTenantProfile profile;
  final List<SubTenantSpot> spots;
  final List<SubTenantCategory> categories;
  final Set<dynamic> popularIds;
  final Map<String, List<_GPlaceSuggestion>> googleSuggestions;
}

// ─── Google Place suggestion model ───────────────────────────────────────────

class _GPlaceSuggestion {
  const _GPlaceSuggestion({
    required this.placeId,
    required this.title,
    required this.address,
    required this.tag,
    required this.rating,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
  });

  final String placeId;
  final String title;
  final String address;
  final String tag;
  final double rating;
  final String imageUrl;
  final double latitude;
  final double longitude;
}

// ─── Google Places fetch helpers ─────────────────────────────────────────────

const _kGoogleApiKey = 'AIzaSyDwbxBRuIRTbYWA3i5PtX7V6dYQ3fAqE1k';

Future<Map<String, List<_GPlaceSuggestion>>> _fetchGoogleSuggestions(
  String city,
  String province,
) async {
  final where = [
    city,
    if (province.isNotEmpty) province,
    'Philippines',
  ].join(' ');

  const specs = [
    (
      tag: 'Historical',
      hint: 'famous historical landmarks heritage sites monuments',
    ),
    (tag: 'Nature', hint: 'nature parks gardens scenic tourist attractions'),
    (tag: 'Church', hint: 'famous churches cathedrals pilgrimage sites'),
    (tag: 'Museum', hint: 'museums cultural centers galleries'),
    (tag: 'Sports', hint: 'sports complex stadium recreation center courts'),
    (tag: 'Food', hint: 'popular local restaurants cafes delicacies'),
  ];

  final futures = specs.map(
    (s) => _fetchGoogleSpotsForTag(
      tag: s.tag,
      query: '${s.hint} in $where',
      city: city,
    ),
  );

  final results = await Future.wait(futures);
  final map = <String, List<_GPlaceSuggestion>>{};
  for (var i = 0; i < specs.length; i++) {
    if (results[i].isNotEmpty) map[specs[i].tag] = results[i];
  }
  return map;
}

Future<List<_GPlaceSuggestion>> _fetchGoogleSpotsForTag({
  required String tag,
  required String query,
  required String city,
}) async {
  try {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/textsearch/json'
      '?query=${Uri.encodeQueryComponent(query)}'
      '&region=ph'
      '&key=$_kGoogleApiKey',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return const [];

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final status = body['status']?.toString() ?? '';
    if (status != 'OK' && status != 'ZERO_RESULTS') return const [];

    final results = (body['results'] as List?) ?? const [];
    final spots = <_GPlaceSuggestion>[];

    for (final raw in results) {
      final item = raw as Map<String, dynamic>;
      final loc = ((item['geometry'] as Map?)?['location'] as Map?) ?? const {};
      final lat = ((loc['lat'] as num?) ?? 0).toDouble();
      final lng = ((loc['lng'] as num?) ?? 0).toDouble();
      if (lat == 0 && lng == 0) continue;

      final title = (item['name'] as String?)?.trim() ?? '';
      if (title.isEmpty) continue;

      final address = (item['formatted_address'] as String?) ?? '';
      if (!_isPlaceInSelectedCity(address: address, city: city)) {
        continue;
      }
      final rating = ((item['rating'] as num?) ?? 4.0).toDouble();
      final placeId = (item['place_id'] as String?) ?? title;

      final photos = (item['photos'] as List?) ?? const [];
      final photoRef =
          ((photos.firstOrNull as Map?)?['photo_reference'] as String?) ?? '';
      final imageUrl = photoRef.isEmpty
          ? ''
          : 'https://maps.googleapis.com/maps/api/place/photo'
                '?maxwidth=800'
                '&photo_reference=${Uri.encodeComponent(photoRef)}'
                '&key=$_kGoogleApiKey';

      spots.add(
        _GPlaceSuggestion(
          placeId: placeId,
          title: title,
          address: address,
          tag: tag,
          rating: rating,
          imageUrl: imageUrl,
          latitude: lat,
          longitude: lng,
        ),
      );
    }

    spots.sort((a, b) => b.rating.compareTo(a.rating));
    return spots.take(3).toList();
  } catch (e) {
    debugPrint('Google Places [$tag]: $e');
    return const [];
  }
}

bool _isPlaceInSelectedCity({required String address, required String city}) {
  final normalizedAddress = _normalizeText(address);
  final normalizedCity = _normalizeText(city);

  if (normalizedAddress.isEmpty || normalizedCity.isEmpty) return false;
  if (!normalizedAddress.contains('bulacan')) return false;
  return normalizedAddress.contains(normalizedCity);
}

String _normalizeText(String value) {
  return value
      .toLowerCase()
      .replaceAll('Ã±', 'n')
      .replaceAll('ñ', 'n')
      .replaceAll('-', '')
      .replaceAll(' ', '')
      .replaceAll(',', '')
      .replaceAll('.', '');
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class SubTenantPackageFormScreen extends StatefulWidget {
  const SubTenantPackageFormScreen({super.key, this.package});

  final SubTenantPackage? package;

  @override
  State<SubTenantPackageFormScreen> createState() =>
      _SubTenantPackageFormScreenState();
}

class _SubTenantPackageFormScreenState
    extends State<SubTenantPackageFormScreen> {
  final SubTenantService _service = SubTenantService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Form controllers
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _groupSizeCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  final _coverCtrl = TextEditingController();
  final _spotSearchCtrl = TextEditingController();

  // Form state
  String _status = 'draft';
  String _visibility = 'visible';
  dynamic _packageCategoryId;
  bool _saving = false;
  bool _spotsInitialized = false;

  // Spot builder state
  String _spotCategoryFilter = 'all';
  final List<SelectedPackageSpot> _selectedSpots = [];
  final Set<String> _addingPlaceIds = {};

  late Future<_BuilderData> _dataFuture;

  bool get _editing => widget.package != null;

  @override
  void initState() {
    super.initState();
    _prefillFromPackage();
    _dataFuture = _loadData();
    _spotSearchCtrl.addListener(() => setState(() {}));
  }

  void _prefillFromPackage() {
    final pkg = widget.package;
    if (pkg == null) return;
    _titleCtrl.text = pkg.title;
    _subtitleCtrl.text = pkg.subtitle;
    _descriptionCtrl.text = pkg.description;
    _cityCtrl.text = pkg.city;
    _priceCtrl.text = pkg.priceText;
    _durationCtrl.text = pkg.durationText;
    _budgetCtrl.text = pkg.estimatedBudget == 0
        ? ''
        : pkg.estimatedBudget.toStringAsFixed(0);
    _groupSizeCtrl.text = pkg.groupSize == 0 ? '' : pkg.groupSize.toString();
    _distanceCtrl.text = pkg.routeDistanceKm == 0
        ? ''
        : pkg.routeDistanceKm.toStringAsFixed(1);
    _imageCtrl.text = pkg.imageUrl;
    _coverCtrl.text = pkg.coverImageUrl;
    _status = pkg.status;
    _visibility = pkg.visibilityStatus;
  }

  Future<_BuilderData> _loadData() async {
    final profile = await _service.loadCurrentProfile();
    if (!mounted) throw StateError('disposed');
    if (!_editing) setState(() => _cityCtrl.text = profile.assignedCity);

    // Fire all fetches in parallel
    final spotsF = _service.loadCityTouristSpots(profile);
    final categoriesF = _service.loadTourismCategories();
    final popularIdsF = _service.loadPopularSpotIdsByCity(profile.assignedCity);
    final googleF = _fetchGoogleSuggestions(
      profile.assignedCity,
      profile.province,
    );

    final spots = await spotsF;
    final categories = await categoriesF;
    final popularIds = await popularIdsF;
    final googleSuggestions = await googleF;

    if (_editing && !_spotsInitialized) {
      final existing = await _service.loadPackageSelectedSpots(
        profile,
        widget.package!.id,
      );
      if (mounted && !_spotsInitialized) {
        setState(() {
          _selectedSpots.clear();
          _selectedSpots.addAll(existing);
          _spotsInitialized = true;
        });
      }
    }

    return _BuilderData(
      profile: profile,
      spots: spots,
      categories: categories,
      popularIds: popularIds,
      googleSuggestions: googleSuggestions,
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _descriptionCtrl.dispose();
    _cityCtrl.dispose();
    _priceCtrl.dispose();
    _durationCtrl.dispose();
    _budgetCtrl.dispose();
    _groupSizeCtrl.dispose();
    _distanceCtrl.dispose();
    _imageCtrl.dispose();
    _coverCtrl.dispose();
    _spotSearchCtrl.dispose();
    super.dispose();
  }

  // ─── Spot management ─────────────────────────────────────────────────────

  void _addSpot(SubTenantSpot spot) {
    if (_selectedSpots.any((s) => stId(s.spot.id) == stId(spot.id))) return;
    setState(() {
      _selectedSpots.add(
        SelectedPackageSpot(spot: spot, sortOrder: _selectedSpots.length),
      );
      _recalcDistance();
    });
  }

  void _removeSpot(int index) {
    setState(() {
      _selectedSpots.removeAt(index);
      for (var i = 0; i < _selectedSpots.length; i++) {
        _selectedSpots[i].sortOrder = i;
      }
      _recalcDistance();
    });
  }

  void _moveSpotUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = _selectedSpots.removeAt(index);
      _selectedSpots.insert(index - 1, item);
      for (var i = 0; i < _selectedSpots.length; i++) {
        _selectedSpots[i].sortOrder = i;
      }
      _recalcDistance();
    });
  }

  void _moveSpotDown(int index) {
    if (index >= _selectedSpots.length - 1) return;
    setState(() {
      final item = _selectedSpots.removeAt(index);
      _selectedSpots.insert(index + 1, item);
      for (var i = 0; i < _selectedSpots.length; i++) {
        _selectedSpots[i].sortOrder = i;
      }
      _recalcDistance();
    });
  }

  Future<void> _editSpotSchedule(int index) async {
    final current = _selectedSpots[index];
    final updated = await showModalBottomSheet<SelectedPackageSpot>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SpotScheduleSheet(spot: current),
    );
    if (updated == null) return;
    setState(() => _selectedSpots[index] = updated);
  }

  void _recalcDistance() {
    if (_selectedSpots.length < 2) return;
    double total = 0;
    for (var i = 0; i < _selectedSpots.length - 1; i++) {
      final a = _selectedSpots[i].spot;
      final b = _selectedSpots[i + 1].spot;
      if (a.latitude != 0 &&
          a.longitude != 0 &&
          b.latitude != 0 &&
          b.longitude != 0) {
        total += _haversine(a.latitude, a.longitude, b.latitude, b.longitude);
      }
    }
    if (total > 0) _distanceCtrl.text = total.toStringAsFixed(1);
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRad(double deg) => deg * (3.141592653589793 / 180);

  // ─── Filtering / recommendations ─────────────────────────────────────────

  List<SubTenantSpot> _filteredSpots(List<SubTenantSpot> all) {
    final selectedIds = _selectedSpots.map((s) => stId(s.spot.id)).toSet();
    final q = _spotSearchCtrl.text.toLowerCase().trim();
    return all.where((spot) {
      if (selectedIds.contains(stId(spot.id))) return false;
      if (q.isNotEmpty) {
        if (!spot.title.toLowerCase().contains(q) &&
            !spot.barangay.toLowerCase().contains(q) &&
            !spot.description.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (_spotCategoryFilter != 'all' && spot.categoryId != null) {
        if (stId(spot.categoryId) != _spotCategoryFilter) return false;
      }
      return true;
    }).toList();
  }

  static const _tagOrder = [
    'Historical',
    'Nature',
    'Church',
    'Museum',
    'Sports',
    'Food',
  ];

  static IconData _tagIcon(String tag) => switch (tag) {
    'Nature' => Icons.terrain_outlined,
    'Church' => Icons.church_outlined,
    'Museum' => Icons.museum_outlined,
    'Sports' => Icons.sports_basketball_outlined,
    'Food' => Icons.restaurant_outlined,
    _ => Icons.account_balance_outlined,
  };

  static Color _tagColor(String tag) => switch (tag) {
    'Nature' => const Color(0xFF16A34A),
    'Church' => const Color(0xFF7C3AED),
    'Museum' => const Color(0xFF0284C7),
    'Sports' => const Color(0xFFEA580C),
    'Food' => const Color(0xFFDC2626),
    _ => const Color(0xFF78716C),
  };

  Future<void> _addGoogleSpot(
    SubTenantProfile profile,
    _GPlaceSuggestion suggestion,
  ) async {
    if (_addingPlaceIds.contains(suggestion.placeId)) return;
    setState(() => _addingPlaceIds.add(suggestion.placeId));
    try {
      final spot = await _service.upsertSpotFromGoogle(
        profile: profile,
        title: suggestion.title,
        description: suggestion.address,
        address: suggestion.address,
        latitude: suggestion.latitude,
        longitude: suggestion.longitude,
        imageUrl: suggestion.imageUrl,
        rating: suggestion.rating,
        tag: suggestion.tag,
        googlePlaceId: suggestion.placeId,
      );
      if (mounted) _addSpot(spot);
    } catch (e) {
      if (mounted) showSubTenantSnack(context, 'Could not add spot: $e');
    } finally {
      if (mounted) setState(() => _addingPlaceIds.remove(suggestion.placeId));
    }
  }

  // ─── Save ────────────────────────────────────────────────────────────────

  Future<void> _save(
    SubTenantProfile profile, {
    bool openItinerary = false,
  }) async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final budget = double.tryParse(_budgetCtrl.text.trim().replaceAll(',', ''));
    final groupSize = int.tryParse(_groupSizeCtrl.text.trim());
    final distance = double.tryParse(
      _distanceCtrl.text.trim().replaceAll(',', ''),
    );

    setState(() => _saving = true);
    try {
      final id = await _service.savePackage(
        profile: profile,
        packageId: widget.package?.id,
        values: {
          'title': _titleCtrl.text.trim(),
          'subtitle': _subtitleCtrl.text.trim(),
          'description': _descriptionCtrl.text.trim(),
          'price_text': _priceCtrl.text.trim(),
          'duration_text': _durationCtrl.text.trim(),
          'estimated_budget': budget ?? 0,
          'group_size': groupSize ?? 0,
          'route_distance_km': distance ?? 0,
          'image_url': _imageCtrl.text.trim(),
          'cover_image_url': _coverCtrl.text.trim().isEmpty
              ? _imageCtrl.text.trim()
              : _coverCtrl.text.trim(),
          'status': _status,
          'visibility_status': _visibility,
          if (_packageCategoryId != null) 'category_id': _packageCategoryId,
        },
      );

      if (_selectedSpots.isNotEmpty) {
        await _service.savePackageSelectedSpots(
          packageId: id,
          selectedSpots: _selectedSpots,
        );
      }

      if (!mounted) return;
      showSubTenantSnack(
        context,
        _editing ? 'Package updated.' : 'Package created.',
        error: false,
      );

      if (openItinerary) {
        final pkg = await _service.fetchPackageById(profile, id);
        if (!mounted || pkg == null) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SubTenantPackageItineraryScreen(package: pkg),
          ),
        );
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to save package: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SubTenantColors.background,
      appBar: subTenantAppBar(
        context,
        title: _editing ? 'Edit Package' : 'Build Tour Package',
        showBack: true,
      ),
      body: FutureBuilder<_BuilderData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SubTenantLoadingView();
          }
          if (snapshot.hasError) {
            return SubTenantErrorView(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _dataFuture = _loadData()),
            );
          }

          final data = snapshot.data!;
          return Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 860;
                final h = isWide
                    ? const EdgeInsets.fromLTRB(24, 16, 24, 36)
                    : const EdgeInsets.fromLTRB(14, 12, 14, 28);
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: h,
                  child: isWide ? _buildWide(data) : _buildNarrow(data),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildWide(_BuilderData data) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 60, child: Column(children: _leftChildren(data))),
        const SizedBox(width: 20),
        Expanded(flex: 40, child: Column(children: _rightChildren(data))),
      ],
    );
  }

  Widget _buildNarrow(_BuilderData data) {
    return Column(children: [..._leftChildren(data), ..._rightChildren(data)]);
  }

  List<Widget> _leftChildren(_BuilderData data) => [
    _basicInfoCard(data),
    const SizedBox(height: 14),
    _detailsCard(),
    const SizedBox(height: 14),
    _imagesCard(),
    const SizedBox(height: 14),
    _publishingCard(),
    const SizedBox(height: 18),
    _saveButtons(data.profile),
    const SizedBox(height: 14),
  ];

  List<Widget> _rightChildren(_BuilderData data) => [
    _smartRecsCard(data),
    const SizedBox(height: 14),
    _suggestedSpotsCard(data),
    const SizedBox(height: 14),
    _selectedSpotsCard(),
    const SizedBox(height: 14),
    _previewCard(),
    const SizedBox(height: 14),
  ];

  // ─── Left column sections ─────────────────────────────────────────────────

  Widget _basicInfoCard(_BuilderData data) {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Package Basic Info',
            subtitle: 'Name, description, and category',
          ),
          const SizedBox(height: 14),
          SubTenantTextField(
            controller: _titleCtrl,
            label: 'Title',
            hint: 'e.g. Heritage Walking Tour',
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _subtitleCtrl,
            label: 'Subtitle',
            hint: 'Short tagline for tourists',
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _descriptionCtrl,
            label: 'Description',
            hint: 'What tourists can expect...',
            maxLines: 4,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _cityCtrl,
            label: 'City / Municipality',
            enabled: false,
          ),
          if (data.categories.isNotEmpty) ...[
            const SizedBox(height: 12),
            _categoryDropdown(data.categories),
          ],
        ],
      ),
    );
  }

  Widget _categoryDropdown(List<SubTenantCategory> categories) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Category',
          style: TextStyle(
            color: SubTenantColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<dynamic>(
          initialValue: _packageCategoryId,
          decoration: _dd(),
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: null, child: Text('None')),
            ...categories.map(
              (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
            ),
          ],
          onChanged: (v) => setState(() => _packageCategoryId = v),
        ),
      ],
    );
  }

  Widget _detailsCard() {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Package Details',
            subtitle: 'Pricing, duration, and logistics',
          ),
          const SizedBox(height: 14),
          SubTenantTextField(
            controller: _priceCtrl,
            label: 'Price Text',
            hint: 'From PHP 1,200',
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _durationCtrl,
            label: 'Duration Text',
            hint: '1 day',
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SubTenantTextField(
                  controller: _budgetCtrl,
                  label: 'Est. Budget (PHP)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SubTenantTextField(
                  controller: _groupSizeCtrl,
                  label: 'Group Size',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _distanceCtrl,
            label: 'Route Distance (km)',
            hint: 'Auto-filled when spots have coordinates',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
    );
  }

  Widget _imagesCard() {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Images',
            subtitle: 'Package photo and cover banner',
          ),
          const SizedBox(height: 14),
          SubTenantTextField(
            controller: _imageCtrl,
            label: 'Image URL',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _coverCtrl,
            label: 'Cover Image URL',
            hint: 'Defaults to Image URL if empty',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _coverCtrl,
            builder: (_, cv, _) => ValueListenableBuilder<TextEditingValue>(
              valueListenable: _imageCtrl,
              builder: (_, iv, _) {
                final url = cv.text.trim().isNotEmpty
                    ? cv.text.trim()
                    : iv.text.trim();
                if (url.isEmpty) return const SizedBox.shrink();
                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    url,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: SubTenantColors.line,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text(
                          'Invalid image URL',
                          style: TextStyle(
                            color: SubTenantColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _publishingCard() {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Publishing',
            subtitle: 'Status and visibility settings',
          ),
          const SizedBox(height: 14),
          _ddLabel('Status'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: _dd(),
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'draft', child: Text('Draft')),
              DropdownMenuItem(value: 'pending', child: Text('Pending Review')),
              DropdownMenuItem(value: 'published', child: Text('Published')),
              DropdownMenuItem(value: 'returned', child: Text('Returned')),
              DropdownMenuItem(value: 'sold_out', child: Text('Sold Out')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _status = v);
            },
          ),
          const SizedBox(height: 12),
          _ddLabel('Visibility'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _visibility,
            decoration: _dd(),
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'visible', child: Text('Visible')),
              DropdownMenuItem(value: 'hidden', child: Text('Hidden')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _visibility = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _saveButtons(SubTenantProfile profile) {
    return Column(
      children: [
        SubTenantGradientButton(
          label: 'Save Package',
          icon: Icons.save_rounded,
          loading: _saving,
          onPressed: () => _save(profile),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _saving ? null : () => _save(profile, openItinerary: true),
          icon: const Icon(Icons.map_rounded),
          label: const Text('Save & Manage Itinerary'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: SubTenantColors.blue,
            side: const BorderSide(color: SubTenantColors.blue),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Right column sections ─────────────────────────────────────────────────

  Widget _suggestedSpotsCard(_BuilderData data) {
    final filtered = _filteredSpots(data.spots);

    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubTenantSectionHeader(
            title: 'Suggested Tourist Spots',
            subtitle:
                '${data.spots.length} active spot${data.spots.length == 1 ? '' : 's'} in ${data.profile.assignedCity}',
          ),
          const SizedBox(height: 12),
          SubTenantSearchBar(
            controller: _spotSearchCtrl,
            hintText: 'Search by name, barangay...',
          ),
          if (data.categories.isNotEmpty) ...[
            const SizedBox(height: 10),
            _categoryFilterRow(data.categories),
          ],
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  _spotSearchCtrl.text.isNotEmpty
                      ? 'No spots match your search.'
                      : data.spots.isEmpty
                      ? 'No active tourist spots found in ${data.profile.assignedCity} yet.'
                      : 'All spots have been added to your package.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: SubTenantColors.muted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            )
          else ...[
            ...filtered
                .take(12)
                .map(
                  (spot) => _SpotCard(spot: spot, onAdd: () => _addSpot(spot)),
                ),
            if (filtered.length > 12)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${filtered.length - 12} more — use search to narrow down.',
                  style: const TextStyle(
                    color: SubTenantColors.lightMuted,
                    fontSize: 11.5,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _categoryFilterRow(List<SubTenantCategory> categories) {
    final filters = ['all', ...categories.map((c) => stId(c.id))];
    final labels = <String, String>{
      'all': 'All',
      for (final c in categories) stId(c.id): c.name,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters
            .map(
              (f) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _FilterChip(
                  label: labels[f] ?? f,
                  selected: _spotCategoryFilter == f,
                  onTap: () => setState(() => _spotCategoryFilter = f),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _smartRecsCard(_BuilderData data) {
    // Filter out already-selected spots (match by title)
    final selectedTitles = _selectedSpots
        .map((s) => s.spot.title.toLowerCase())
        .toSet();
    final filtered = <String, List<_GPlaceSuggestion>>{};
    for (final entry in data.googleSuggestions.entries) {
      final spots = entry.value
          .where((s) => !selectedTitles.contains(s.title.toLowerCase()))
          .toList();
      if (spots.isNotEmpty) filtered[entry.key] = spots;
    }
    final hasData = filtered.isNotEmpty;

    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SubTenantSectionHeader(
                  title: 'Smart Suggestions',
                  subtitle: 'Google Places picks by category',
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  gradient: SubTenantColors.gradient,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 12,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in _tagOrder)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: filtered.containsKey(tag)
                        ? _tagColor(tag).withValues(alpha: 0.12)
                        : SubTenantColors.backgroundAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: filtered.containsKey(tag)
                          ? _tagColor(tag).withValues(alpha: 0.3)
                          : SubTenantColors.line,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _tagIcon(tag),
                        color: filtered.containsKey(tag)
                            ? _tagColor(tag)
                            : SubTenantColors.lightMuted,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tag,
                        style: TextStyle(
                          color: filtered.containsKey(tag)
                              ? _tagColor(tag)
                              : SubTenantColors.lightMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (!hasData) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: SubTenantColors.backgroundAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SubTenantColors.line),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: SubTenantColors.lightMuted,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No Google Places results found for this city. Check your internet connection.',
                      style: TextStyle(
                        color: SubTenantColors.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            for (final tag in _tagOrder)
              if (filtered.containsKey(tag))
                _tagSection(tag, filtered[tag]!, data.profile),
          ],
        ],
      ),
    );
  }

  Widget _tagSection(
    String tag,
    List<_GPlaceSuggestion> spots,
    SubTenantProfile profile,
  ) {
    final color = _tagColor(tag);
    final icon = _tagIcon(tag);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 13),
                const SizedBox(width: 5),
                Text(
                  tag,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...spots.map(
            (s) => _GSpotCard(
              suggestion: s,
              adding: _addingPlaceIds.contains(s.placeId),
              onAdd: () => _addGoogleSpot(profile, s),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectedSpotsCard() {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubTenantSectionHeader(
            title: 'Selected Spots',
            subtitle:
                '${_selectedSpots.length} spot${_selectedSpots.length == 1 ? '' : 's'} in this package',
          ),
          const SizedBox(height: 12),
          if (_selectedSpots.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: SubTenantColors.backgroundAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: SubTenantColors.line,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.add_location_alt_outlined,
                      color: SubTenantColors.lightMuted,
                      size: 28,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'No spots added yet',
                      style: TextStyle(
                        color: SubTenantColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Tap Add on spots from the lists above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SubTenantColors.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            for (var i = 0; i < _selectedSpots.length; i++)
              _SelectedSpotTile(
                key: ValueKey(stId(_selectedSpots[i].spot.id)),
                selectedSpot: _selectedSpots[i],
                index: i,
                total: _selectedSpots.length,
                onRemove: () => _removeSpot(i),
                onEditSchedule: () => _editSpotSchedule(i),
                onMoveUp: i > 0 ? () => _moveSpotUp(i) : null,
                onMoveDown: i < _selectedSpots.length - 1
                    ? () => _moveSpotDown(i)
                    : null,
              ),
            const SizedBox(height: 6),
            const Text(
              'Use arrows to reorder. Use the edit button to set opening, closing, arrival, and stay times.',
              style: TextStyle(color: SubTenantColors.lightMuted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewCard() {
    return _PackagePreviewCard(
      titleCtrl: _titleCtrl,
      subtitleCtrl: _subtitleCtrl,
      cityCtrl: _cityCtrl,
      priceCtrl: _priceCtrl,
      durationCtrl: _durationCtrl,
      coverCtrl: _coverCtrl,
      imageCtrl: _imageCtrl,
      status: _status,
      visibility: _visibility,
      selectedSpotCount: _selectedSpots.length,
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Widget _ddLabel(String label) => Text(
    label,
    style: const TextStyle(
      color: SubTenantColors.text,
      fontSize: 13,
      fontWeight: FontWeight.w900,
    ),
  );

  InputDecoration _dd({String? hint}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      color: SubTenantColors.lightMuted,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    ),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: SubTenantColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: SubTenantColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: SubTenantColors.blue, width: 1.3),
    ),
  );
}

// ─── Spot card ────────────────────────────────────────────────────────────────

class _SpotCard extends StatelessWidget {
  const _SpotCard({required this.spot, required this.onAdd});

  final SubTenantSpot spot;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: SubTenantColors.backgroundAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SubTenantColors.line),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(13),
                bottomLeft: Radius.circular(13),
              ),
              child: spot.imageUrl.isNotEmpty
                  ? Image.network(
                      spot.imageUrl,
                      width: 64,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            spot.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SubTenantColors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      spot.barangay.isNotEmpty
                          ? 'Brgy. ${spot.barangay}'
                          : spot.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (spot.rating > 0) ...[
                      const SizedBox(height: 3),
                      Row(
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
                              color: SubTenantColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: SubTenantColors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: SubTenantColors.blue.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_rounded,
                        color: SubTenantColors.blue,
                        size: 14,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Add',
                        style: TextStyle(
                          color: SubTenantColors.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    width: 64,
    height: 72,
    color: SubTenantColors.line,
    child: const Icon(
      Icons.image_rounded,
      color: SubTenantColors.lightMuted,
      size: 24,
    ),
  );
}

// ─── Selected spot tile ───────────────────────────────────────────────────────

class _SelectedSpotTile extends StatelessWidget {
  const _SelectedSpotTile({
    super.key,
    required this.selectedSpot,
    required this.index,
    required this.total,
    required this.onRemove,
    required this.onEditSchedule,
    this.onMoveUp,
    this.onMoveDown,
  });

  final SelectedPackageSpot selectedSpot;
  final int index;
  final int total;
  final VoidCallback onRemove;
  final VoidCallback onEditSchedule;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: SubTenantColors.gradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedSpot.spot.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (selectedSpot.spot.barangay.isNotEmpty)
                  Text(
                    'Brgy. ${selectedSpot.spot.barangay}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SubTenantColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (_scheduleSummary.isNotEmpty)
                  Text(
                    _scheduleSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SubTenantColors.lightMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          InkWell(
            onTap: onEditSchedule,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.schedule_rounded,
                color: SubTenantColors.blue,
                size: 16,
              ),
            ),
          ),
          _arrowBtn(Icons.keyboard_arrow_up_rounded, onMoveUp),
          _arrowBtn(Icons.keyboard_arrow_down_rounded, onMoveDown),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                color: Color(0xFFDC2626),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _arrowBtn(IconData icon, VoidCallback? onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Icon(
        icon,
        size: 18,
        color: onTap == null
            ? SubTenantColors.line
            : SubTenantColors.lightMuted,
      ),
    ),
  );

  String get _scheduleSummary {
    final parts = <String>[];
    if (selectedSpot.estimatedArrivalTime.trim().isNotEmpty) {
      parts.add('Arrive ${selectedSpot.estimatedArrivalTime}');
    }
    if (selectedSpot.estimatedDurationMinutes > 0) {
      parts.add('Stay ${selectedSpot.estimatedDurationMinutes}m');
    } else if (selectedSpot.recommendedVisitDurationMinutes > 0) {
      parts.add('Recommended ${selectedSpot.recommendedVisitDurationMinutes}m');
    }
    if (selectedSpot.openingTime.trim().isNotEmpty ||
        selectedSpot.closingTime.trim().isNotEmpty) {
      parts.add(
        'Open ${selectedSpot.openingTime.isEmpty ? '--' : selectedSpot.openingTime} - '
        '${selectedSpot.closingTime.isEmpty ? '--' : selectedSpot.closingTime}',
      );
    }
    return parts.join(' • ');
  }
}

// ─── Package preview card ─────────────────────────────────────────────────────

class _SpotScheduleSheet extends StatefulWidget {
  const _SpotScheduleSheet({required this.spot});

  final SelectedPackageSpot spot;

  @override
  State<_SpotScheduleSheet> createState() => _SpotScheduleSheetState();
}

class _SpotScheduleSheetState extends State<_SpotScheduleSheet> {
  late final TextEditingController _openingCtrl;
  late final TextEditingController _closingCtrl;
  late final TextEditingController _arrivalCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _recommendedCtrl;

  @override
  void initState() {
    super.initState();
    _openingCtrl = TextEditingController(text: widget.spot.openingTime);
    _closingCtrl = TextEditingController(text: widget.spot.closingTime);
    _arrivalCtrl = TextEditingController(text: widget.spot.estimatedArrivalTime);
    _durationCtrl = TextEditingController(
      text: widget.spot.estimatedDurationMinutes <= 0
          ? ''
          : widget.spot.estimatedDurationMinutes.toString(),
    );
    _recommendedCtrl = TextEditingController(
      text: widget.spot.recommendedVisitDurationMinutes <= 0
          ? ''
          : widget.spot.recommendedVisitDurationMinutes.toString(),
    );
  }

  @override
  void dispose() {
    _openingCtrl.dispose();
    _closingCtrl.dispose();
    _arrivalCtrl.dispose();
    _durationCtrl.dispose();
    _recommendedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
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
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.spot.spot.title,
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Set manual visit hours and itinerary timing for this package stop.',
                style: TextStyle(
                  color: SubTenantColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SubTenantTextField(
                      controller: _openingCtrl,
                      label: 'Opening Time',
                      hint: '08:00',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SubTenantTextField(
                      controller: _closingCtrl,
                      label: 'Closing Time',
                      hint: '17:00',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SubTenantTextField(
                      controller: _arrivalCtrl,
                      label: 'Estimated Arrival',
                      hint: '09:00',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SubTenantTextField(
                      controller: _durationCtrl,
                      label: 'Stay Duration (min)',
                      hint: '45',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SubTenantTextField(
                controller: _recommendedCtrl,
                label: 'Recommended Visit Duration (min)',
                hint: '60',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              SubTenantGradientButton(
                label: 'Save Spot Schedule',
                icon: Icons.save_rounded,
                onPressed: () {
                  Navigator.pop(
                    context,
                    SelectedPackageSpot(
                      spot: widget.spot.spot,
                      sortOrder: widget.spot.sortOrder,
                      openingTime: _openingCtrl.text.trim(),
                      closingTime: _closingCtrl.text.trim(),
                      estimatedArrivalTime: _arrivalCtrl.text.trim(),
                      estimatedDurationMinutes:
                          int.tryParse(_durationCtrl.text.trim()) ?? 0,
                      recommendedVisitDurationMinutes:
                          int.tryParse(_recommendedCtrl.text.trim()) ?? 0,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackagePreviewCard extends StatelessWidget {
  const _PackagePreviewCard({
    required this.titleCtrl,
    required this.subtitleCtrl,
    required this.cityCtrl,
    required this.priceCtrl,
    required this.durationCtrl,
    required this.coverCtrl,
    required this.imageCtrl,
    required this.status,
    required this.visibility,
    required this.selectedSpotCount,
  });

  final TextEditingController titleCtrl;
  final TextEditingController subtitleCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController durationCtrl;
  final TextEditingController coverCtrl;
  final TextEditingController imageCtrl;
  final String status;
  final String visibility;
  final int selectedSpotCount;

  @override
  Widget build(BuildContext context) {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Tourist-Facing Preview',
            subtitle: 'Updates live as you type',
          ),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: Listenable.merge([
              titleCtrl,
              subtitleCtrl,
              cityCtrl,
              priceCtrl,
              durationCtrl,
              coverCtrl,
              imageCtrl,
            ]),
            builder: (_, _) {
              final coverUrl = coverCtrl.text.trim().isNotEmpty
                  ? coverCtrl.text.trim()
                  : imageCtrl.text.trim();
              final title = titleCtrl.text.trim();
              final subtitle = subtitleCtrl.text.trim();
              final city = cityCtrl.text.trim();
              final price = priceCtrl.text.trim();
              final duration = durationCtrl.text.trim();

              return Container(
                decoration: BoxDecoration(
                  color: SubTenantColors.backgroundAlt,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SubTenantColors.line),
                ),
                clipBehavior: Clip.hardEdge,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cover
                    coverUrl.isNotEmpty
                        ? Image.network(
                            coverUrl,
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _coverPlaceholder(),
                          )
                        : _coverPlaceholder(),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title.isEmpty ? 'Package Title' : title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: title.isEmpty
                                        ? SubTenantColors.lightMuted
                                        : SubTenantColors.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SubTenantStatusPill(status: status),
                            ],
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: SubTenantColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 5,
                            children: [
                              if (city.isNotEmpty)
                                _Chip(
                                  icon: Icons.location_on_rounded,
                                  label: city,
                                ),
                              if (price.isNotEmpty)
                                _Chip(
                                  icon: Icons.payments_rounded,
                                  label: price,
                                ),
                              if (duration.isNotEmpty)
                                _Chip(
                                  icon: Icons.schedule_rounded,
                                  label: duration,
                                ),
                              if (selectedSpotCount > 0)
                                _Chip(
                                  icon: Icons.place_rounded,
                                  label:
                                      '$selectedSpotCount stop${selectedSpotCount == 1 ? '' : 's'}',
                                ),
                              if (visibility == 'hidden')
                                const _Chip(
                                  icon: Icons.visibility_off_rounded,
                                  label: 'Hidden',
                                  color: Color(0xFFDC2626),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _coverPlaceholder() => Container(
    height: 120,
    width: double.infinity,
    color: const Color(0xFFE4ECF7),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_rounded, color: SubTenantColors.lightMuted, size: 28),
        SizedBox(height: 4),
        Text(
          'Cover image preview',
          style: TextStyle(color: SubTenantColors.lightMuted, fontSize: 12),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    this.color = SubTenantColors.muted,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ─── Google suggestion card ───────────────────────────────────────────────────

class _GSpotCard extends StatelessWidget {
  const _GSpotCard({
    required this.suggestion,
    required this.onAdd,
    required this.adding,
  });

  final _GPlaceSuggestion suggestion;
  final VoidCallback onAdd;
  final bool adding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: SubTenantColors.backgroundAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SubTenantColors.line),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(13),
                bottomLeft: Radius.circular(13),
              ),
              child: suggestion.imageUrl.isNotEmpty
                  ? Image.network(
                      suggestion.imageUrl,
                      width: 64,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SubTenantColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      suggestion.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (suggestion.rating > 0) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFF59E0B),
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            suggestion.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: SubTenantColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'via Google',
                            style: TextStyle(
                              color: SubTenantColors.lightMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: adding
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SubTenantColors.blue,
                          ),
                        ),
                      ),
                    )
                  : InkWell(
                      onTap: onAdd,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: SubTenantColors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: SubTenantColors.blue.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              color: SubTenantColors.blue,
                              size: 14,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Add',
                              style: TextStyle(
                                color: SubTenantColors.blue,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    width: 64,
    height: 72,
    color: SubTenantColors.line,
    child: const Icon(
      Icons.place_rounded,
      color: SubTenantColors.lightMuted,
      size: 24,
    ),
  );
}

// ─── Filter chip ─────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? SubTenantColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? SubTenantColors.blue : SubTenantColors.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : SubTenantColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
