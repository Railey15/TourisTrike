import 'dart:convert' show jsonDecode;
import 'dart:math' show atan2, cos, sin, sqrt;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class _BuilderData {
  const _BuilderData({
    required this.profile,
    required this.spots,
    required this.categories,
    required this.popularIds,
    required this.googleSuggestions,
    required this.fareSettings,
  });

  final SubTenantProfile profile;
  final List<SubTenantSpot> spots;
  final List<SubTenantCategory> categories;
  final Set<dynamic> popularIds;
  final Map<String, List<_GPlaceSuggestion>> googleSuggestions;
  final SubTenantFareSettings fareSettings;
}

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

const _kGoogleApiKey = 'AIzaSyDwbxBRuIRTbYWA3i5PtX7V6dYQ3fAqE1k';

// ignore: unused_element
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
    if (results[i].isNotEmpty) {
      map[specs[i].tag] = results[i];
    }
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
  } catch (error) {
    debugPrint('Google Places [$tag]: $error');
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
      .replaceAll('ÃƒÂ±', 'n')
      .replaceAll('Ã±', 'n')
      .replaceAll('-', '')
      .replaceAll(' ', '')
      .replaceAll(',', '')
      .replaceAll('.', '');
}

_GPlaceSuggestion _toGoogleSuggestion(
  CitySpotSuggestion suggestion, {
  String? fallbackTag,
}) {
  return _GPlaceSuggestion(
    placeId: suggestion.id,
    title: suggestion.title,
    address: suggestion.address,
    tag: fallbackTag ?? suggestion.category,
    rating: suggestion.rating,
    imageUrl: suggestion.imageForCard,
    latitude: suggestion.latitude,
    longitude: suggestion.longitude,
  );
}

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

  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  final _coverCtrl = TextEditingController();
  final _spotSearchCtrl = TextEditingController();

  String _status = 'draft';
  String _visibility = 'visible';
  dynamic _packageCategoryId;
  int _currentStep = 0;
  bool _saving = false;
  bool _uploadingImage = false;
  bool _uploadingCover = false;
  bool _spotsInitialized = false;
  bool _itineraryLoading = false;

  String _spotCategoryFilter = 'all';
  final List<SelectedPackageSpot> _selectedSpots = [];
  final Set<String> _addingPlaceIds = {};
  List<PackageItineraryDay> _itineraryDays = const [];
  dynamic _workingPackageId;
  bool _routeMetricsLoading = false;
  String _distanceHint = 'Select at least 2 destinations';
  String _durationHint = 'Generated from itinerary schedule';

  late Future<_BuilderData> _dataFuture;

  bool get _editing => widget.package != null;
  bool get _isFinalStep => _currentStep == 3;
  bool get _wizardBusy =>
      _saving || _uploadingImage || _uploadingCover || _itineraryLoading;

  @override
  void initState() {
    super.initState();
    _workingPackageId = widget.package?.id;
    _prefillFromPackage();
    _dataFuture = _loadData();
    _spotSearchCtrl.addListener(() => setState(() {}));
    _distanceCtrl.addListener(() => setState(() {}));
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
    _distanceCtrl.dispose();
    _imageCtrl.dispose();
    _coverCtrl.dispose();
    _spotSearchCtrl.dispose();
    super.dispose();
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
    if (!mounted) throw StateError('Screen was disposed.');

    if (!_editing) {
      setState(() => _cityCtrl.text = profile.assignedCity);
    }

    final spotsFuture = _service.loadCityTouristSpots(profile);
    final categoriesFuture = _service.loadTourismCategories();
    final popularIdsFuture = _service.loadPopularSpotIdsByCity(
      profile.assignedCity,
    );
    final googleFuture = _service.loadPackageSmartSuggestions(
      profile: profile,
      keyword: _titleCtrl.text.trim(),
      selectedSpots: _selectedSpots,
    );
    final fareFuture = _service.loadFareSettings(profile);

    final spots = await spotsFuture;
    final categories = await categoriesFuture;
    final popularIds = await popularIdsFuture;
    final googleSuggestions = await googleFuture;
    final fareSettings = await fareFuture;

    if (_editing && !_spotsInitialized) {
      final existing = await _service.loadPackageSelectedSpots(
        profile,
        widget.package!.id,
      );
      if (mounted && !_spotsInitialized) {
        setState(() {
          _selectedSpots
            ..clear()
            ..addAll(existing);
          _spotsInitialized = true;
        });
        await _recalcDistance();
      }
    }

    final normalizedSuggestions = <String, List<_GPlaceSuggestion>>{};
    for (final entry in googleSuggestions.entries) {
      normalizedSuggestions[entry.key] = entry.value
          .map(
            (suggestion) =>
                _toGoogleSuggestion(suggestion, fallbackTag: entry.key),
          )
          .toList(growable: false);
    }

    return _BuilderData(
      profile: profile,
      spots: spots,
      categories: categories,
      popularIds: popularIds,
      googleSuggestions: normalizedSuggestions,
      fareSettings: fareSettings,
    );
  }

  void _reloadData() {
    setState(() => _dataFuture = _loadData());
  }

  void _addSpot(SubTenantSpot spot) {
    if (_selectedSpots.any((item) => stId(item.spot.id) == stId(spot.id))) {
      return;
    }
    setState(() {
      _selectedSpots.add(
        SelectedPackageSpot(spot: spot, sortOrder: _selectedSpots.length),
      );
    });
    _recalcDistance();
  }

  void _removeSpot(int index) {
    setState(() {
      _selectedSpots.removeAt(index);
      _normalizeSelectedSpots();
    });
    _recalcDistance();
  }

  void _moveSpotUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = _selectedSpots.removeAt(index);
      _selectedSpots.insert(index - 1, item);
      _normalizeSelectedSpots();
    });
    _recalcDistance();
  }

  void _moveSpotDown(int index) {
    if (index >= _selectedSpots.length - 1) return;
    setState(() {
      final item = _selectedSpots.removeAt(index);
      _selectedSpots.insert(index + 1, item);
      _normalizeSelectedSpots();
    });
    _recalcDistance();
  }

  void _normalizeSelectedSpots() {
    for (var i = 0; i < _selectedSpots.length; i++) {
      _selectedSpots[i].sortOrder = i;
    }
  }

  Future<void> _editSpotSchedule(int index) async {
    final current = _selectedSpots[index];
    final updated = await showModalBottomSheet<SelectedPackageSpot>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SpotScheduleSheet(spot: current),
    );
    if (updated == null || !mounted) return;
    setState(() => _selectedSpots[index] = updated);
    _recalcDistance();
  }

  Future<void> _recalcDistance() async {
    if (!mounted) return;
    if (_selectedSpots.isEmpty) {
      setState(() {
        _distanceCtrl.clear();
        _durationCtrl.clear();
        _distanceHint = 'Select at least 2 destinations';
        _durationHint = 'Generated from itinerary schedule';
        _routeMetricsLoading = false;
      });
      return;
    }

    setState(() {
      _routeMetricsLoading = true;
      _distanceHint = 'Calculating...';
      _durationHint = 'Calculating...';
    });

    try {
      final metrics = await _service.computePackageRouteMetrics(_selectedSpots);
      if (!mounted) return;
      setState(() {
        _distanceCtrl.text = metrics.available
            ? metrics.distanceKm.toStringAsFixed(1)
            : '';
        _distanceHint = metrics.available
            ? (metrics.usedDirectionsApi
                  ? 'Calculated from Google Maps route'
                  : 'Calculated with route fallback')
            : 'Not available';
        _durationCtrl.text = _buildDurationText(metrics.travelDurationMinutes);
        _durationHint = _durationCtrl.text.isEmpty
            ? 'Not available'
            : 'Auto-generated for a day tour';
        _routeMetricsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _distanceCtrl.clear();
        _distanceHint = 'Not available';
        _durationCtrl.text = _buildDurationText(0);
        _durationHint = _durationCtrl.text.isEmpty
            ? 'Not available'
            : 'Auto-generated for a day tour';
        _routeMetricsLoading = false;
      });
    }
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

  String _buildDurationText(int travelDurationMinutes) {
    final totalMinutes = _estimateTourDurationMinutes(
      travelDurationMinutes: travelDurationMinutes,
    );
    if (totalMinutes <= 0) return '';
    if (totalMinutes >= 8 * 60) return 'Whole Day Tour';

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '$minutes Minutes';
    if (minutes == 0) return '$hours Hours';
    return '$hours Hours $minutes Minutes';
  }

  int _estimateTourDurationMinutes({required int travelDurationMinutes}) {
    if (_selectedSpots.isEmpty) return 0;

    final explicitSchedule = _buildExplicitDaySchedule();
    if (explicitSchedule != null) {
      return explicitSchedule;
    }

    final stayMinutes = _selectedSpots.fold<int>(
      0,
      (sum, selectedSpot) => sum + _preferredStayMinutes(selectedSpot),
    );
    final computedTravel = travelDurationMinutes > 0
        ? travelDurationMinutes
        : _fallbackTravelMinutes();
    return stayMinutes + computedTravel;
  }

  int? _buildExplicitDaySchedule() {
    var earliest = 24 * 60;
    var latest = 0;
    var sawExplicit = false;

    for (final selectedSpot in _selectedSpots) {
      final arrival = _parseClockMinutes(selectedSpot.estimatedArrivalTime);
      if (arrival == null) continue;
      sawExplicit = true;
      final departure = arrival + _preferredStayMinutes(selectedSpot);
      if (arrival < earliest) earliest = arrival;
      if (departure > latest) latest = departure;
    }

    if (!sawExplicit || latest <= earliest) return null;
    return latest - earliest;
  }

  int _preferredStayMinutes(SelectedPackageSpot selectedSpot) {
    if (selectedSpot.estimatedDurationMinutes > 0) {
      return selectedSpot.estimatedDurationMinutes;
    }
    if (selectedSpot.recommendedVisitDurationMinutes > 0) {
      return selectedSpot.recommendedVisitDurationMinutes;
    }
    return 60;
  }

  int _fallbackTravelMinutes() {
    if (_selectedSpots.length < 2) return 0;
    var totalKm = 0.0;
    for (var i = 0; i < _selectedSpots.length - 1; i++) {
      final a = _selectedSpots[i].spot;
      final b = _selectedSpots[i + 1].spot;
      if (a.latitude == 0 ||
          a.longitude == 0 ||
          b.latitude == 0 ||
          b.longitude == 0) {
        continue;
      }
      totalKm += _haversine(a.latitude, a.longitude, b.latitude, b.longitude);
    }
    return ((totalKm / 28) * 60).round();
  }

  int? _parseClockMinutes(String raw) {
    final value = raw.trim().toUpperCase();
    if (value.isEmpty) return null;

    final twelveHour = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
    ).firstMatch(value);
    if (twelveHour != null) {
      var hour = int.tryParse(twelveHour.group(1)!) ?? -1;
      final minute = int.tryParse(twelveHour.group(2)!) ?? -1;
      final meridiem = twelveHour.group(3)!;
      if (hour < 1 || hour > 12 || minute < 0 || minute > 59) return null;
      if (meridiem == 'AM') {
        if (hour == 12) hour = 0;
      } else if (hour != 12) {
        hour += 12;
      }
      return (hour * 60) + minute;
    }

    final twentyFourHour = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
    if (twentyFourHour != null) {
      final hour = int.tryParse(twentyFourHour.group(1)!) ?? -1;
      final minute = int.tryParse(twentyFourHour.group(2)!) ?? -1;
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
      return (hour * 60) + minute;
    }

    return null;
  }

  FareCalculation _fareCalculation(SubTenantFareSettings settings) {
    final distance =
        double.tryParse(_distanceCtrl.text.trim().replaceAll(',', '')) ?? 0;
    return settings.calculate(
      routeDistanceKm: distance,
      groupSize: 1,
      waitingHours: _totalWaitingHours(),
    );
  }

  int _totalWaitingMinutes() {
    if (_selectedSpots.isEmpty) return 0;
    return _selectedSpots.fold<int>(
      0,
      (sum, selectedSpot) => sum + _preferredStayMinutes(selectedSpot),
    );
  }

  double _totalWaitingHours() => _totalWaitingMinutes() / 60.0;

  String _totalWaitingLabel() {
    final totalMinutes = _totalWaitingMinutes();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h';
    return '${minutes}m';
  }

  void _useSuggestedPrice(SubTenantFareSettings settings) {
    final calculation = _fareCalculation(settings);
    setState(() {
      _budgetCtrl.text = calculation.total.toStringAsFixed(0);
      _priceCtrl.text = 'From PHP ${calculation.total.toStringAsFixed(0)}';
    });
  }

  bool _isSupportedImage(XFile file) {
    final name = file.name.toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp');
  }

  String _contentTypeFor(XFile file) {
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _pickAndUploadImage({
    required SubTenantProfile profile,
    required TextEditingController target,
    required bool cover,
  }) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 88,
    );
    if (file == null) return;

    if (!_isSupportedImage(file)) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Use JPG, PNG, or WebP images only.');
      return;
    }

    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Image must be 5 MB or smaller.');
      return;
    }

    setState(() {
      if (cover) {
        _uploadingCover = true;
      } else {
        _uploadingImage = true;
      }
    });

    try {
      final url = await _service.uploadPublicAsset(
        profile: profile,
        bucket: 'public-assets',
        folder: 'tour-packages',
        fileName: file.name,
        bytes: bytes,
        contentType: _contentTypeFor(file),
      );

      if (!mounted) return;
      setState(() => target.text = url);
      showSubTenantSnack(context, 'Image uploaded.', error: false);
    } catch (error) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Image upload failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          if (cover) {
            _uploadingCover = false;
          } else {
            _uploadingImage = false;
          }
        });
      }
    }
  }

  List<SubTenantSpot> _filteredSpots(
    List<SubTenantSpot> all,
    Set<dynamic> popularIds,
  ) {
    final selectedIds = _selectedSpots
        .map((item) => stId(item.spot.id))
        .toSet();
    final query = _spotSearchCtrl.text.toLowerCase().trim();
    final filtered = all.where((spot) {
      if (selectedIds.contains(stId(spot.id))) return false;
      if (query.isNotEmpty &&
          !spot.title.toLowerCase().contains(query) &&
          !spot.barangay.toLowerCase().contains(query) &&
          !spot.description.toLowerCase().contains(query)) {
        return false;
      }
      if (_spotCategoryFilter != 'all' && spot.categoryId != null) {
        if (stId(spot.categoryId) != _spotCategoryFilter) return false;
      }
      return spot.status != 'archived';
    }).toList();

    filtered.sort((a, b) {
      final aPopular = popularIds.contains(a.id) ? 1 : 0;
      final bPopular = popularIds.contains(b.id) ? 1 : 0;
      if (aPopular != bPopular) return bPopular.compareTo(aPopular);
      return b.rating.compareTo(a.rating);
    });

    return filtered;
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
      if (mounted) {
        _addSpot(spot);
      }
    } catch (error) {
      if (mounted) {
        showSubTenantSnack(context, 'Could not add spot: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _addingPlaceIds.remove(suggestion.placeId));
      }
    }
  }

  bool _isValidPackageName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return false;
    if (!RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿÑñ]").hasMatch(trimmed)) return false;
    return RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿÑñ' -]+$").hasMatch(trimmed);
  }

  String? _validateWizard({bool requirePrice = true}) {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return 'Package title is required.';
    if (!_isValidPackageName(title)) {
      return 'Package name must contain valid words only.';
    }
    if (_descriptionCtrl.text.trim().isEmpty) {
      return 'Package description is required.';
    }
    if (requirePrice && _priceCtrl.text.trim().isEmpty) {
      return 'Price text is required.';
    }
    if (_selectedSpots.isEmpty) {
      return 'Add at least one destination to this package.';
    }
    return null;
  }

  String? _validateDayTourRules() {
    const earliestMinutes = 7 * 60;
    const latestMinutes = 17 * 60;

    var cursor = earliestMinutes;
    for (final selectedSpot in _selectedSpots) {
      final explicitArrival = _parseClockMinutes(
        selectedSpot.estimatedArrivalTime,
      );
      final arrival = explicitArrival ?? cursor;
      final stayMinutes = _preferredStayMinutes(selectedSpot);
      final departure = arrival + stayMinutes;

      if (arrival < earliestMinutes) {
        return '${selectedSpot.spot.title} cannot arrive before 7:00 AM.';
      }
      if (departure <= arrival) {
        return '${selectedSpot.spot.title} must depart after it arrives.';
      }
      if (departure > latestMinutes) {
        return 'The itinerary exceeds 5:00 PM. Adjust the destination timing.';
      }

      cursor = departure + 20;
    }

    if (_itineraryDays.length > 1) {
      return 'Tour packages are limited to a single day itinerary only.';
    }

    for (final day in _itineraryDays) {
      for (final item in day.items) {
        final time = _parseClockMinutes(item.timeLabel);
        if (time == null) {
          return 'Use a clear time like 9:00 AM for itinerary stops.';
        }
        if (time < earliestMinutes || time > latestMinutes) {
          return 'Itinerary stops must stay within 7:00 AM to 5:00 PM.';
        }
      }
    }

    return null;
  }

  Future<String?> _validateBeforeSave(SubTenantProfile profile) async {
    final basicMessage = _validateWizard();
    if (basicMessage != null) return basicMessage;

    final dayTourMessage = _validateDayTourRules();
    if (dayTourMessage != null) return dayTourMessage;

    final duplicate = await _service.checkDuplicatePackageComposition(
      profile: profile,
      selectedSpots: _selectedSpots,
      excludePackageId: _workingPackageId,
    );
    if (duplicate.isDuplicate) {
      return 'This package is too similar to an existing package.';
    }

    return null;
  }

  Future<String?> _validateBeforeItinerary(SubTenantProfile profile) async {
    final basicMessage = _validateWizard(requirePrice: false);
    if (basicMessage != null) return basicMessage;

    final duplicate = await _service.checkDuplicatePackageComposition(
      profile: profile,
      selectedSpots: _selectedSpots,
      excludePackageId: _workingPackageId,
    );
    if (duplicate.isDuplicate) {
      return 'This package is too similar to an existing package.';
    }

    return null;
  }

  Future<dynamic> _savePackageDraft(
    SubTenantProfile profile, {
    bool showSuccess = false,
  }) async {
    final budget = double.tryParse(_budgetCtrl.text.trim().replaceAll(',', ''));
    final distance = double.tryParse(
      _distanceCtrl.text.trim().replaceAll(',', ''),
    );

    final published = _status == 'published' && _visibility == 'visible';

    final id = await _service.savePackage(
      profile: profile,
      packageId: _workingPackageId,
      values: {
        'title': _titleCtrl.text.trim(),
        'subtitle': _subtitleCtrl.text.trim(),
        'description': _descriptionCtrl.text.trim(),
        'price_text': _priceCtrl.text.trim(),
        'duration_text': _durationCtrl.text.trim(),
        'estimated_budget': budget ?? 0,
        'route_distance_km': distance ?? 0,
        'image_url': _imageCtrl.text.trim(),
        'cover_image_url': _coverCtrl.text.trim().isEmpty
            ? _imageCtrl.text.trim()
            : _coverCtrl.text.trim(),
        'status': published ? 'published' : 'draft',
        'visibility_status': published ? 'visible' : 'hidden',
        if (_packageCategoryId != null) 'category_id': _packageCategoryId,
      },
    );

    await _service.savePackageSelectedSpots(
      packageId: id,
      selectedSpots: _selectedSpots,
    );

    if (mounted) {
      setState(() => _workingPackageId = id);
      if (showSuccess) {
        showSubTenantSnack(
          context,
          widget.package == null ? 'Package saved.' : 'Package updated.',
          error: false,
        );
      }
    }
    return id;
  }

  Future<void> _ensurePackageAndLoadItinerary(SubTenantProfile profile) async {
    if (_wizardBusy) return;

    final validationMessage = await _validateBeforeItinerary(profile);
    if (!mounted) return;
    if (validationMessage != null) {
      showSubTenantSnack(context, validationMessage);
      return;
    }

    setState(() {
      _saving = true;
      _itineraryLoading = true;
    });

    try {
      await _savePackageDraft(profile);
      await _service.syncPackageItineraryFromSelectedSpots(
        profile: profile,
        packageId: _workingPackageId,
        selectedSpots: _selectedSpots,
      );
      final days = await _service.fetchItinerary(profile, _workingPackageId);
      if (!mounted) return;
      setState(() {
        _itineraryDays = days;
        _currentStep = 2;
      });
    } catch (error) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to prepare itinerary editor: $error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _itineraryLoading = false;
        });
      }
    }
  }

  Future<void> _saveAndClose(SubTenantProfile profile) async {
    if (_wizardBusy) return;

    final validationMessage = await _validateBeforeSave(profile);
    if (!mounted) return;
    if (validationMessage != null) {
      showSubTenantSnack(context, validationMessage);
      return;
    }

    setState(() => _saving = true);
    try {
      await _savePackageDraft(profile, showSuccess: true);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to save package: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _handleNext(_BuilderData data) async {
    if (_wizardBusy) return;

    // Validate basic info only when on the first step
    if (_currentStep == 0) {
      if (!_formKey.currentState!.validate()) return;
    }

    // When on the Spots step, prepare package and load itinerary (jump to itinerary)
    if (_currentStep == 1) {
      await _ensurePackageAndLoadItinerary(data.profile);
      return;
    }

    if (_currentStep < 3) {
      setState(() => _currentStep += 1);
    }
  }

  void _handleBack() {
    if (_wizardBusy || _currentStep == 0) return;
    setState(() => _currentStep -= 1);
  }

  Future<void> _reloadItinerary(SubTenantProfile profile) async {
    if (_workingPackageId == null) return;

    setState(() => _itineraryLoading = true);
    try {
      final days = await _service.fetchItinerary(profile, _workingPackageId);
      if (!mounted) return;
      setState(() => _itineraryDays = days);
    } catch (error) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to load itinerary: $error');
    } finally {
      if (mounted) {
        setState(() => _itineraryLoading = false);
      }
    }
  }

  Future<void> _addDay(SubTenantProfile profile) async {
    if (_workingPackageId == null || _itineraryLoading) return;
    setState(() => _itineraryLoading = true);
    try {
      await _syncGeneratedItinerary(profile);
      if (!mounted) return;
      showSubTenantSnack(
        context,
        'Day tour itinerary generated.',
        error: false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _itineraryLoading = false);
      showSubTenantSnack(context, 'Failed to add day: $error');
    }
  }

  Future<void> _syncGeneratedItinerary(SubTenantProfile profile) async {
    if (_workingPackageId == null) return;

    await _service.savePackageSelectedSpots(
      packageId: _workingPackageId,
      selectedSpots: _selectedSpots,
    );
    await _service.syncPackageItineraryFromSelectedSpots(
      profile: profile,
      packageId: _workingPackageId,
      selectedSpots: _selectedSpots,
    );
    await _reloadItinerary(profile);
  }

  Future<void> _openItemForm(
    _BuilderData data,
    PackageItineraryItem item,
  ) async {
    final index = _selectedSpots.indexWhere(
      (selectedSpot) => stId(selectedSpot.spot.id) == stId(item.spotId),
    );
    if (index < 0) {
      showSubTenantSnack(
        context,
        'This itinerary stop is no longer linked to the selected package spots.',
      );
      return;
    }

    final updated = await showModalBottomSheet<SelectedPackageSpot>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _SpotScheduleSheet(spot: _selectedSpots[index], forItinerary: true),
    );

    if (updated == null || !mounted) return;
    setState(() => _selectedSpots[index] = updated);
    await _syncGeneratedItinerary(data.profile);
  }

  Future<void> _moveItem(
    SubTenantProfile profile,
    PackageItineraryDay day,
    int oldIndex,
    int newIndex,
  ) async {
    if (_workingPackageId == null ||
        newIndex < 0 ||
        newIndex >= day.items.length) {
      return;
    }

    final movedSpotId = stId(day.items[oldIndex].spotId);
    final sourceIndex = _selectedSpots.indexWhere(
      (selectedSpot) => stId(selectedSpot.spot.id) == movedSpotId,
    );
    if (sourceIndex < 0) return;

    setState(() {
      final moved = _selectedSpots.removeAt(sourceIndex);
      _selectedSpots.insert(newIndex, moved);
      _normalizeSelectedSpots();
    });

    try {
      await _syncGeneratedItinerary(profile);
    } catch (error) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to reorder item: $error');
    }
  }

  String get _stepSubtitle => switch (_currentStep) {
    0 => 'Set the package title, description, city, and category.',
    1 => 'Pick the tourist spots to include and arrange their visit order.',
    2 => 'Build the single-day itinerary from 7:00 AM to 5:00 PM.',
    _ => 'Configure pricing, route details, images, and publish settings.',
  };

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
              onRetry: _reloadData,
            );
          }

          final data = snapshot.data!;
          return Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 960;
                final padding = isWide
                    ? const EdgeInsets.fromLTRB(24, 16, 24, 30)
                    : const EdgeInsets.fromLTRB(14, 12, 14, 24);

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WizardProgressCard(
                        currentStep: _currentStep,
                        subtitle: _stepSubtitle,
                      ),
                      const SizedBox(height: 14),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KeyedSubtree(
                          key: ValueKey<int>(_currentStep),
                          child: _buildStepContent(data, isWide),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildNavigationBar(data),
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

  Widget _buildStepContent(_BuilderData data, bool isWide) {
    switch (_currentStep) {
      case 0:
        return isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 58, child: _basicInfoCard(data)),
                  const SizedBox(width: 18),
                  Expanded(flex: 42, child: _previewCard()),
                ],
              )
            : Column(
                children: [
                  _basicInfoCard(data),
                  const SizedBox(height: 14),
                  _previewCard(),
                ],
              );
      case 1:
        // Spots selection step (previously case 2)
        return isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 54,
                    child: Column(
                      children: [
                        _smartRecsCard(data),
                        const SizedBox(height: 14),
                        _suggestedSpotsCard(data),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 46,
                    child: Column(
                      children: [
                        _selectedSpotsCard(),
                        const SizedBox(height: 14),
                        _previewCard(),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  _smartRecsCard(data),
                  const SizedBox(height: 14),
                  _suggestedSpotsCard(data),
                  const SizedBox(height: 14),
                  _selectedSpotsCard(),
                  const SizedBox(height: 14),
                  _previewCard(),
                ],
              );
      case 2:
        // Itinerary editor step (previously default)
        return isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 58, child: _itineraryEditorCard(data)),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 42,
                    child: Column(
                      children: [
                        _PackageReviewCard(
                          title: _titleCtrl.text.trim(),
                          subtitle: _subtitleCtrl.text.trim(),
                          city: _cityCtrl.text.trim(),
                          priceText: _priceCtrl.text.trim(),
                          durationText: _durationCtrl.text.trim(),
                          status: _status,
                          visibility: _visibility,
                          selectedSpotCount: _selectedSpots.length,
                          itineraryDayCount: _itineraryDays.length,
                          itineraryStopCount: _itineraryDays.fold<int>(
                            0,
                            (sum, day) => sum + day.items.length,
                          ),
                          packageId: _workingPackageId,
                        ),
                        const SizedBox(height: 14),
                        _previewCard(),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  _itineraryEditorCard(data),
                  const SizedBox(height: 14),
                  _PackageReviewCard(
                    title: _titleCtrl.text.trim(),
                    subtitle: _subtitleCtrl.text.trim(),
                    city: _cityCtrl.text.trim(),
                    priceText: _priceCtrl.text.trim(),
                    durationText: _durationCtrl.text.trim(),
                    status: _status,
                    visibility: _visibility,
                    selectedSpotCount: _selectedSpots.length,
                    itineraryDayCount: _itineraryDays.length,
                    itineraryStopCount: _itineraryDays.fold<int>(
                      0,
                      (sum, day) => sum + day.items.length,
                    ),
                    packageId: _workingPackageId,
                  ),
                  const SizedBox(height: 14),
                  _previewCard(),
                ],
              );
      default:
        // Details step moved to last (previously case 1)
        return isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 58,
                    child: Column(
                      children: [
                        _detailsCard(data),
                        const SizedBox(height: 14),
                        _imagesCard(data),
                        const SizedBox(height: 14),
                        _publishingCard(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 42,
                    child: Column(
                      children: [
                        _previewCard(),
                        const SizedBox(height: 14),
                        _fareBreakdownCard(data),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  _detailsCard(data),
                  const SizedBox(height: 14),
                  _imagesCard(data),
                  const SizedBox(height: 14),
                  _publishingCard(),
                  const SizedBox(height: 14),
                  _fareBreakdownCard(data),
                  const SizedBox(height: 14),
                  _previewCard(),
                ],
              );
    }
  }

  Widget _buildNavigationBar(_BuilderData data) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SubTenantColors.line),
        boxShadow: const [
          BoxShadow(
            color: SubTenantColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _wizardBusy ? null : _handleBack,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: SubTenantColors.blue,
                  side: const BorderSide(color: SubTenantColors.blue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: _isFinalStep
                ? SubTenantGradientButton(
                    label: widget.package == null
                        ? 'Save Package'
                        : 'Update Package',
                    icon: Icons.save_rounded,
                    loading: _saving,
                    onPressed: () => _saveAndClose(data.profile),
                  )
                : SubTenantGradientButton(
                    label: _currentStep == 1
                        ? 'Continue to Itinerary'
                        : 'Next Step',
                    icon: Icons.arrow_forward_rounded,
                    loading: _saving || _itineraryLoading,
                    onPressed: () => _handleNext(data),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _basicInfoCard(_BuilderData data) {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Step 1: Package Basic Info',
            subtitle: 'Name, description, city, and category.',
          ),
          const SizedBox(height: 14),
          SubTenantTextField(
            controller: _titleCtrl,
            label: 'Title',
            hint: 'e.g. Heritage Walking Tour',
            validator: (value) {
              final trimmed = (value ?? '').trim();
              if (trimmed.isEmpty) return 'Required';
              if (!_isValidPackageName(trimmed)) {
                return 'Package name must contain valid words only.';
              }
              return null;
            },
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
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Required' : null,
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
          decoration: _dropdownDecoration(),
          isExpanded: true,
          items: [
            const DropdownMenuItem<dynamic>(value: null, child: Text('None')),
            ...categories.map(
              (category) => DropdownMenuItem<dynamic>(
                value: category.id,
                child: Text(category.name),
              ),
            ),
          ],
          onChanged: (value) => setState(() => _packageCategoryId = value),
        ),
      ],
    );
  }

  Widget _detailsCard(_BuilderData data) {
    final calculation = _fareCalculation(data.fareSettings);
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Step 4: Package Details',
            subtitle: 'Pricing, route details, and suggested fare.',
          ),
          const SizedBox(height: 14),
          SubTenantTextField(
            controller: _priceCtrl,
            label: 'Price',
            hint: 'From PHP 1,200',
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _durationCtrl,
            label: 'Estimated Tour Duration',
            hint: 'Auto-generated from stops and travel time',
            readOnly: true,
            helperText: _durationHint,
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _budgetCtrl,
            label: 'Estimated Budget (PHP)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _distanceCtrl,
            label: 'Route Distance (km)',
            hint: _routeMetricsLoading ? 'Calculating...' : 'Auto-calculated',
            readOnly: true,
            helperText: _distanceHint,
            suffix: _routeMetricsLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          _PackageFareSuggestion(
            calculation: calculation,
            waitingLabel: _totalWaitingLabel(),
            onUse: () => _useSuggestedPrice(data.fareSettings),
          ),
        ],
      ),
    );
  }

  Widget _imagesCard(_BuilderData data) {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Images',
            subtitle: 'Package photo and cover banner.',
          ),
          const SizedBox(height: 14),
          SubTenantTextField(
            controller: _imageCtrl,
            label: 'Image URL',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _uploadingImage
                ? null
                : () => _pickAndUploadImage(
                    profile: data.profile,
                    target: _imageCtrl,
                    cover: false,
                  ),
            icon: _uploadingImage
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_rounded),
            label: Text(_uploadingImage ? 'Uploading...' : 'Upload Image'),
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _coverCtrl,
            label: 'Cover Image URL',
            hint: 'Defaults to the package image if left empty',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _uploadingCover
                ? null
                : () => _pickAndUploadImage(
                    profile: data.profile,
                    target: _coverCtrl,
                    cover: true,
                  ),
            icon: _uploadingCover
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_rounded),
            label: Text(_uploadingCover ? 'Uploading...' : 'Upload Cover'),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _coverCtrl,
            builder: (_, coverValue, _) =>
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _imageCtrl,
                  builder: (_, imageValue, _) {
                    final url = coverValue.text.trim().isNotEmpty
                        ? coverValue.text.trim()
                        : imageValue.text.trim();
                    if (url.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        url,
                        height: 150,
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
            subtitle: 'Control whether this package is visible to tourists.',
          ),
          const SizedBox(height: 14),
          _dropdownLabel('Availability'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _status == 'published' && _visibility == 'visible'
                ? 'published'
                : 'draft',
            decoration: _dropdownDecoration(),
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'published', child: Text('Published')),
              DropdownMenuItem(value: 'draft', child: Text('Unpublished')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _status = value;
                  _visibility = value == 'published' ? 'visible' : 'hidden';
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _fareBreakdownCard(_BuilderData data) {
    final calculation = _fareCalculation(data.fareSettings);
    final waitingLabel = _totalWaitingLabel();
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Fare Snapshot',
            subtitle: 'Live estimate based on the current inputs.',
          ),
          const SizedBox(height: 12),
          _ReviewMetric(
            icon: Icons.payments_rounded,
            label: 'Suggested Price',
            value: 'PHP ${calculation.total.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 10),
          _ReviewMetric(
            icon: Icons.route_rounded,
            label: 'Route Distance',
            value: _distanceCtrl.text.trim().isEmpty
                ? '0 km'
                : '${_distanceCtrl.text.trim()} km',
          ),
          const SizedBox(height: 10),
          _ReviewMetric(
            icon: Icons.hourglass_bottom_rounded,
            label: 'Total Waiting Time',
            value: waitingLabel,
          ),
          const SizedBox(height: 10),
          _ReviewMetric(
            icon: Icons.schedule_rounded,
            label: 'Waiting Fee',
            value: 'PHP ${calculation.waitingFee.toStringAsFixed(0)}',
          ),
        ],
      ),
    );
  }

  Widget _smartRecsCard(_BuilderData data) {
    final selectedTitles = _selectedSpots
        .map((item) => item.spot.title.toLowerCase())
        .toSet();
    final filtered = <String, List<_GPlaceSuggestion>>{};

    for (final entry in data.googleSuggestions.entries) {
      final spots = entry.value
          .where((suggestion) {
            return !selectedTitles.contains(suggestion.title.toLowerCase());
          })
          .toList(growable: false);
      if (spots.isNotEmpty) {
        filtered[entry.key] = spots;
      }
    }

    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SubTenantSectionHeader(
                  title: 'Step 2: Smart Suggestions',
                  subtitle: 'Google Places recommendations by category.',
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
          if (filtered.isEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
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
                      'No suggestions found. Try another keyword or check Google Places API.',
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _tagColor(tag).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _tagIcon(tag),
                              color: _tagColor(tag),
                              size: 13,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              tag,
                              style: TextStyle(
                                color: _tagColor(tag),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...filtered[tag]!.map(
                        (suggestion) => _GSpotCard(
                          suggestion: suggestion,
                          adding: _addingPlaceIds.contains(suggestion.placeId),
                          onAdd: () => _addGoogleSpot(data.profile, suggestion),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _suggestedSpotsCard(_BuilderData data) {
    final filtered = _filteredSpots(data.spots, data.popularIds);

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
            hintText: 'Search by name, barangay, or description...',
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
                      : 'All suggested spots have already been added.',
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
                  (spot) => _SpotCard(
                    spot: spot,
                    onAdd: () => _addSpot(spot),
                    popular: data.popularIds.contains(spot.id),
                  ),
                ),
            if (filtered.length > 12)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${filtered.length - 12} more available. Use search to narrow down.',
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
    final filters = ['all', ...categories.map((item) => stId(item.id))];
    final labels = <String, String>{
      'all': 'All',
      for (final category in categories) stId(category.id): category.name,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters
            .map((value) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _FilterChip(
                  label: labels[value] ?? value,
                  selected: _spotCategoryFilter == value,
                  onTap: () => setState(() => _spotCategoryFilter = value),
                ),
              );
            })
            .toList(growable: false),
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
                '${_selectedSpots.length} spot${_selectedSpots.length == 1 ? '' : 's'} included in this package',
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
                  border: Border.all(color: SubTenantColors.line),
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
                      'Add spots from the smart suggestions or city list, then arrange them in order.',
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
              'Use the arrows to reorder package stops. Edit each stop to set arrival and visit timing.',
              style: TextStyle(color: SubTenantColors.lightMuted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _itineraryEditorCard(_BuilderData data) {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SubTenantSectionHeader(
                  title: 'Step 3: Day Tour Itinerary',
                  subtitle: _workingPackageId == null
                      ? 'The package will be saved first before itinerary editing becomes available.'
                      : 'Manage the single-day itinerary from 7:00 AM to 5:00 PM.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_workingPackageId == null)
            const SubTenantEmptyState(
              icon: Icons.route_outlined,
              title: 'Itinerary not ready yet',
              message:
                  'Continue from the previous step so the package can be saved in the background and assigned an ID.',
            )
          else if (_itineraryLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_itineraryDays.isEmpty)
            SubTenantEmptyState(
              icon: Icons.map_outlined,
              title: 'No day tour itinerary yet',
              message:
                  'Create the 7:00 AM to 5:00 PM day tour using the selected tourist spots.',
              actionLabel: 'Start Itinerary',
              onAction: () => _addDay(data.profile),
            )
          else
            ..._itineraryDays.map(
              (day) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _WizardDayCard(
                  day: day,
                  onEditItem: (item) => _openItemForm(data, item),
                  onMoveItem: (oldIndex, newIndex) =>
                      _moveItem(data.profile, day, oldIndex, newIndex),
                ),
              ),
            ),
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

  Widget _dropdownLabel(String label) => Text(
    label,
    style: const TextStyle(
      color: SubTenantColors.text,
      fontSize: 13,
      fontWeight: FontWeight.w900,
    ),
  );

  InputDecoration _dropdownDecoration({String? hint}) => InputDecoration(
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

class _WizardProgressCard extends StatelessWidget {
  const _WizardProgressCard({
    required this.currentStep,
    required this.subtitle,
  });

  final int currentStep;
  final String subtitle;

  static const _steps = ['Basic Info', 'Spots', 'Itinerary', 'Details'];

  @override
  Widget build(BuildContext context) {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${currentStep + 1} of ${_steps.length}',
            style: const TextStyle(
              color: SubTenantColors.blue,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _steps[currentStep],
            style: const TextStyle(
              color: SubTenantColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: SubTenantColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(_steps.length, (index) {
              final isDone = index < currentStep;
              final isActive = index == currentStep;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == _steps.length - 1 ? 0 : 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 8,
                        decoration: BoxDecoration(
                          color: isDone || isActive
                              ? SubTenantColors.blue
                              : SubTenantColors.line,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _steps[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDone || isActive
                              ? SubTenantColors.text
                              : SubTenantColors.lightMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _PackageFareSuggestion extends StatelessWidget {
  const _PackageFareSuggestion({
    required this.calculation,
    required this.waitingLabel,
    required this.onUse,
  });

  final FareCalculation calculation;
  final String waitingLabel;
  final VoidCallback onUse;

  String _money(double value) => 'PHP ${value.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Base fare', calculation.baseFare),
      ('Distance fee', calculation.distanceFee),
      ('Waiting fee ($waitingLabel)', calculation.waitingFee),
      if (calculation.minimumFareAdjustment > 0)
        ('Minimum fare adjustment', calculation.minimumFareAdjustment),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: SubTenantColors.blue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubTenantColors.blue.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Suggested Price',
                  style: TextStyle(
                    color: SubTenantColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _money(calculation.total),
                style: const TextStyle(
                  color: SubTenantColors.blue,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _money(row.$2),
                    style: const TextStyle(
                      color: SubTenantColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onUse,
              icon: const Icon(Icons.price_check_rounded, size: 18),
              label: const Text('Use Suggested Price'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({
    required this.spot,
    required this.onAdd,
    required this.popular,
  });

  final SubTenantSpot spot;
  final VoidCallback onAdd;
  final bool popular;

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
                        if (popular) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFF59E0B,
                              ).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Popular',
                              style: TextStyle(
                                color: Color(0xFFF59E0B),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
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
          _arrowButton(Icons.keyboard_arrow_up_rounded, onMoveUp),
          _arrowButton(Icons.keyboard_arrow_down_rounded, onMoveDown),
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

  Widget _arrowButton(IconData icon, VoidCallback? onTap) {
    return InkWell(
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
  }

  String get _scheduleSummary {
    final parts = <String>[];
    if (selectedSpot.estimatedArrivalTime.trim().isNotEmpty) {
      parts.add('Arrive ${selectedSpot.estimatedArrivalTime}');
    }
    if (selectedSpot.estimatedDurationMinutes > 0) {
      final departure = _scheduleDepartureLabel(
        selectedSpot.estimatedArrivalTime,
        selectedSpot.estimatedDurationMinutes,
      );
      parts.add(
        departure == null
            ? 'Stay ${selectedSpot.estimatedDurationMinutes}m'
            : 'Stay ${selectedSpot.estimatedDurationMinutes}m, leave $departure',
      );
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
    return parts.join(' / ');
  }
}

String? _scheduleDepartureLabel(String arrivalTime, int durationMinutes) {
  if (durationMinutes <= 0) return null;
  final arrival = _parseScheduleTime(arrivalTime);
  if (arrival == null) return null;
  return _formatScheduleTime(arrival + durationMinutes);
}

int? _parseScheduleTime(String raw) {
  final value = raw.trim().toUpperCase();
  if (value.isEmpty) return null;

  final twelveHour = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$').firstMatch(value);
  if (twelveHour != null) {
    var hour = int.tryParse(twelveHour.group(1)!) ?? -1;
    final minute = int.tryParse(twelveHour.group(2)!) ?? -1;
    final meridiem = twelveHour.group(3)!;
    if (hour < 1 || hour > 12 || minute < 0 || minute > 59) return null;
    if (meridiem == 'AM') {
      if (hour == 12) hour = 0;
    } else if (hour != 12) {
      hour += 12;
    }
    return (hour * 60) + minute;
  }

  final twentyFourHour = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
  if (twentyFourHour != null) {
    final hour = int.tryParse(twentyFourHour.group(1)!) ?? -1;
    final minute = int.tryParse(twentyFourHour.group(2)!) ?? -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour * 60) + minute;
  }

  return null;
}

String _formatScheduleTime(int rawMinutes) {
  var minutes = rawMinutes;
  if (minutes < 0) minutes = 0;
  final hour24 = (minutes ~/ 60) % 24;
  final minute = minutes % 60;
  final meridiem = hour24 >= 12 ? 'PM' : 'AM';
  var hour12 = hour24 % 12;
  if (hour12 == 0) hour12 = 12;
  final minuteText = minute.toString().padLeft(2, '0');
  return '$hour12:$minuteText $meridiem';
}

class _ScheduleDropdown<T> extends StatelessWidget {
  const _ScheduleDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T value) itemLabel;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
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
      ),
      items: items
          .map(
            (item) =>
                DropdownMenuItem<T>(value: item, child: Text(itemLabel(item))),
          )
          .toList(growable: false),
      onChanged: onChanged,
    );
  }
}

class _SpotScheduleSheet extends StatefulWidget {
  const _SpotScheduleSheet({required this.spot, this.forItinerary = false});

  final SelectedPackageSpot spot;
  final bool forItinerary;

  @override
  State<_SpotScheduleSheet> createState() => _SpotScheduleSheetState();
}

class _SpotScheduleSheetState extends State<_SpotScheduleSheet> {
  late String? _openingTime;
  late String? _closingTime;
  late String? _arrivalTime;
  late int? _stayDurationMinutes;
  late int? _recommendedDurationMinutes;

  static final List<String> _timeOptions = [
    for (var minutes = 7 * 60; minutes <= 17 * 60; minutes += 15)
      _formatScheduleTime(minutes),
  ];

  static final List<int> _durationOptions = [
    for (var minutes = 15; minutes <= 240; minutes += 15) minutes,
  ];

  @override
  void initState() {
    super.initState();
    _openingTime = _normalizeTimeValue(widget.spot.openingTime);
    _closingTime = _normalizeTimeValue(widget.spot.closingTime);
    _arrivalTime = _normalizeTimeValue(widget.spot.estimatedArrivalTime);
    _stayDurationMinutes = _normalizeDurationValue(
      widget.spot.estimatedDurationMinutes,
    );
    _recommendedDurationMinutes = _normalizeDurationValue(
      widget.spot.recommendedVisitDurationMinutes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final departureLabel = _departurePreview();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
              Text(
                widget.forItinerary
                    ? 'Adjust the auto-generated day tour schedule for this stop.'
                    : 'Set visit hours and package-specific schedule timing for this tourist spot.',
                style: const TextStyle(
                  color: SubTenantColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ScheduleDropdown<String>(
                      label: 'Opening Time',
                      value: _openingTime,
                      items: _timeOptions,
                      itemLabel: (value) => value,
                      onChanged: (value) =>
                          setState(() => _openingTime = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ScheduleDropdown<String>(
                      label: 'Closing Time',
                      value: _closingTime,
                      items: _timeOptions,
                      itemLabel: (value) => value,
                      onChanged: (value) =>
                          setState(() => _closingTime = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ScheduleDropdown<String>(
                      label: 'Arrival Time',
                      value: _arrivalTime,
                      items: _timeOptions,
                      itemLabel: (value) => value,
                      onChanged: (value) =>
                          setState(() => _arrivalTime = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ScheduleDropdown<int>(
                      label: 'Stay Duration (min)',
                      value: _stayDurationMinutes,
                      items: _durationOptions,
                      itemLabel: (value) => '$value mins',
                      onChanged: (value) =>
                          setState(() => _stayDurationMinutes = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ScheduleDropdown<int>(
                label: 'Recommended Visit Duration (min)',
                value: _recommendedDurationMinutes,
                items: _durationOptions,
                itemLabel: (value) => '$value mins',
                onChanged: (value) =>
                    setState(() => _recommendedDurationMinutes = value),
              ),
              if (departureLabel != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: SubTenantColors.line),
                  ),
                  child: Text(
                    'Departure preview: $departureLabel',
                    style: const TextStyle(
                      color: SubTenantColors.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
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
                      openingTime: _openingTime ?? '',
                      closingTime: _closingTime ?? '',
                      estimatedArrivalTime: _arrivalTime ?? '',
                      estimatedDurationMinutes: _stayDurationMinutes ?? 0,
                      recommendedVisitDurationMinutes:
                          _recommendedDurationMinutes ?? 0,
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

  String? _departurePreview() {
    final arrival = _arrivalTime;
    final stay = _stayDurationMinutes;
    if (arrival == null || stay == null || stay <= 0) return null;
    final arrivalMinutes = _parseScheduleTime(arrival);
    if (arrivalMinutes == null) return null;
    return _formatScheduleTime(arrivalMinutes + stay);
  }

  static String? _normalizeTimeValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final minutes = _parseScheduleTime(trimmed);
    if (minutes == null) return null;
    final formatted = _formatScheduleTime(minutes);
    return _timeOptions.contains(formatted) ? formatted : null;
  }

  static int? _normalizeDurationValue(int raw) {
    if (raw <= 0) return null;
    return _durationOptions.contains(raw) ? raw : null;
  }
}

class _WizardDayCard extends StatelessWidget {
  const _WizardDayCard({
    required this.day,
    required this.onEditItem,
    required this.onMoveItem,
  });

  final PackageItineraryDay day;
  final ValueChanged<PackageItineraryItem> onEditItem;
  final void Function(int oldIndex, int newIndex) onMoveItem;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SubTenantColors.backgroundAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: const SubTenantSectionHeader(
                  title: 'Day Tour',
                  subtitle: '7:00 AM to 5:00 PM',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (day.items.isEmpty)
            const SubTenantEmptyState(
              icon: Icons.route_outlined,
              title: 'No stops for this day tour',
              message:
                  'Return to the Spots step to configure destinations, then generate the itinerary again.',
            )
          else
            ...day.items.asMap().entries.map(
              (entry) => _WizardItineraryTile(
                item: entry.value,
                index: entry.key,
                total: day.items.length,
                onEdit: () => onEditItem(entry.value),
                onMoveUp: () => onMoveItem(entry.key, entry.key - 1),
                onMoveDown: () => onMoveItem(entry.key, entry.key + 1),
              ),
            ),
        ],
      ),
    );
  }
}

class _WizardItineraryTile extends StatelessWidget {
  const _WizardItineraryTile({
    required this.item,
    required this.index,
    required this.total,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final PackageItineraryItem item;
  final int index;
  final int total;
  final VoidCallback onEdit;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (item.timeLabel.isNotEmpty) item.timeLabel,
      if (item.note.isNotEmpty) item.note,
    ].join(' / ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EEF7),
              borderRadius: BorderRadius.circular(15),
              image: item.spotImageUrl.isEmpty
                  ? null
                  : DecorationImage(
                      image: NetworkImage(item.spotImageUrl),
                      fit: BoxFit.cover,
                    ),
            ),
            child: item.spotImageUrl.isEmpty
                ? const Icon(
                    Icons.place_rounded,
                    color: SubTenantColors.lightMuted,
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.spotTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle.isEmpty ? 'No schedule note yet' : subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SubTenantColors.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Move up',
                    visualDensity: VisualDensity.compact,
                    onPressed: index == 0 ? null : onMoveUp,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    visualDensity: VisualDensity.compact,
                    onPressed: index == total - 1 ? null : onMoveDown,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded),
                    color: SubTenantColors.blue,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItineraryItemSheet extends StatefulWidget {
  const _ItineraryItemSheet({
    required this.service,
    required this.profile,
    required this.packageId,
    required this.day,
    required this.spots,
    required this.item,
  });

  final SubTenantService service;
  final SubTenantProfile profile;
  final dynamic packageId;
  final PackageItineraryDay day;
  final List<SubTenantSpot> spots;
  final PackageItineraryItem? item;

  @override
  State<_ItineraryItemSheet> createState() => _ItineraryItemSheetState();
}

class _ItineraryItemSheetState extends State<_ItineraryItemSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _timeCtrl;
  late final TextEditingController _noteCtrl;
  dynamic _spotId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _timeCtrl = TextEditingController(text: widget.item?.timeLabel ?? '');
    _noteCtrl = TextEditingController(text: widget.item?.note ?? '');
    _spotId = widget.item?.spotId ?? widget.spots.first.id;
  }

  @override
  void dispose() {
    _timeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await widget.service.saveItineraryItem(
        profile: widget.profile,
        packageId: widget.packageId,
        dayId: widget.day.id,
        itemId: widget.item?.id,
        spotId: _spotId,
        timeLabel: _timeCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        sortOrder: widget.item?.sortOrder ?? widget.day.items.length,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to save itinerary item: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      decoration: const BoxDecoration(
        color: SubTenantColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Form(
        key: _formKey,
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
                widget.item == null ? 'Add Itinerary Stop' : 'Edit Stop',
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<dynamic>(
                initialValue: _spotId,
                decoration: InputDecoration(
                  labelText: 'Tourist Spot',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: SubTenantColors.line),
                  ),
                ),
                items: widget.spots
                    .map(
                      (spot) => DropdownMenuItem<dynamic>(
                        value: spot.id,
                        child: Text(
                          spot.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _spotId = value),
              ),
              const SizedBox(height: 14),
              SubTenantTextField(
                controller: _timeCtrl,
                label: 'Time Label',
                hint: '09:00 AM',
                helperText: 'Use a stop time between 7:00 AM and 5:00 PM.',
              ),
              const SizedBox(height: 14),
              SubTenantTextField(
                controller: _noteCtrl,
                label: 'Note',
                maxLines: 3,
              ),
              const SizedBox(height: 18),
              SubTenantGradientButton(
                label: 'Save Stop',
                icon: Icons.save_rounded,
                loading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackageReviewCard extends StatelessWidget {
  const _PackageReviewCard({
    required this.title,
    required this.subtitle,
    required this.city,
    required this.priceText,
    required this.durationText,
    required this.status,
    required this.visibility,
    required this.selectedSpotCount,
    required this.itineraryDayCount,
    required this.itineraryStopCount,
    required this.packageId,
  });

  final String title;
  final String subtitle;
  final String city;
  final String priceText;
  final String durationText;
  final String status;
  final String visibility;
  final int selectedSpotCount;
  final int itineraryDayCount;
  final int itineraryStopCount;
  final dynamic packageId;

  @override
  Widget build(BuildContext context) {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Review Summary',
            subtitle: 'Check the package details before saving.',
          ),
          const SizedBox(height: 12),
          _ReviewMetric(
            icon: Icons.inventory_2_rounded,
            label: 'Package',
            value: title.isEmpty ? 'Untitled package' : title,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ReviewMetric(
              icon: Icons.short_text_rounded,
              label: 'Subtitle',
              value: subtitle,
            ),
          ],
          const SizedBox(height: 10),
          _ReviewMetric(
            icon: Icons.location_on_rounded,
            label: 'City',
            value: city.isEmpty ? 'Not set' : city,
          ),
          const SizedBox(height: 10),
          _ReviewMetric(
            icon: Icons.payments_rounded,
            label: 'Price',
            value: priceText.isEmpty ? 'Not set' : priceText,
          ),
          const SizedBox(height: 10),
          _ReviewMetric(
            icon: Icons.schedule_rounded,
            label: 'Duration',
            value: durationText.isEmpty ? 'Not set' : durationText,
          ),
          const SizedBox(height: 10),
          _ReviewMetric(
            icon: Icons.place_rounded,
            label: 'Selected Spots',
            value: '$selectedSpotCount',
          ),
          const SizedBox(height: 10),
          _ReviewMetric(
            icon: Icons.calendar_view_day_rounded,
            label: 'Itinerary Days',
            value: itineraryDayCount <= 0 ? '0' : '1',
          ),
          const SizedBox(height: 10),
          _ReviewMetric(
            icon: Icons.route_rounded,
            label: 'Itinerary Stops',
            value: '$itineraryStopCount',
          ),
          const SizedBox(height: 10),
          _ReviewMetric(
            icon: Icons.circle_rounded,
            label: 'Status / Visibility',
            value: '${stTitleCase(status)} / ${stTitleCase(visibility)}',
          ),
          const SizedBox(height: 10),
          _ReviewMetric(
            icon: Icons.tag_rounded,
            label: 'Package ID',
            value: packageId == null
                ? 'Will be created on save'
                : stId(packageId),
          ),
        ],
      ),
    );
  }
}

class _ReviewMetric extends StatelessWidget {
  const _ReviewMetric({
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: SubTenantColors.blue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: SubTenantColors.blue, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: SubTenantColors.lightMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
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
            subtitle: 'Updates live as you edit the package',
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
