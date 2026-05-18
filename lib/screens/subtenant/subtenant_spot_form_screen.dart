import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

LatLng _municipalityCenter(String city) {
  return const CitySpotSuggestionService().centerForCity(city) ??
      CitySpotSuggestionService.defaultBulacanCenter;
}

LatLngBounds _municipalityBounds(LatLng center) {
  const delta = 0.045;
  return LatLngBounds(
    southwest: LatLng(center.latitude - delta, center.longitude - delta),
    northeast: LatLng(center.latitude + delta, center.longitude + delta),
  );
}

class SubTenantSpotFormScreen extends StatefulWidget {
  const SubTenantSpotFormScreen({super.key, this.spot, this.initialSuggestion});

  final SubTenantSpot? spot;
  final CitySpotSuggestion? initialSuggestion;

  @override
  State<SubTenantSpotFormScreen> createState() =>
      _SubTenantSpotFormScreenState();
}

class _SubTenantSpotFormScreenState extends State<SubTenantSpotFormScreen> {
  final SubTenantService _service = SubTenantService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();

  late Future<_SpotFormData> _dataFuture;

  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _ratingCtrl = TextEditingController(text: '0.0');
  final _imageCtrl = TextEditingController();
  final _openingHoursCtrl = TextEditingController();
  final _entranceFeeCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _bestTimeCtrl = TextEditingController();
  final _tipsCtrl = TextEditingController();
  final _suggestedSpotCtrl = TextEditingController();

  String _status = 'active';
  String _verificationStatus = 'pending';
  dynamic _categoryId;

  bool _saving = false;
  bool _autoFilling = false;

  String? _selectedSuggestionId;
  String? _selectedBarangay;
  String? _selectedGooglePlaceId;
  String? _selectedGooglePhotoReference;
  String _sourceType = 'manual';

  GoogleMapController? _mapController;
  LatLng? _pickedLocation;

  bool get _editing => widget.spot != null;

  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _prefill();
    _dataFuture = _loadData();

    for (final ctrl in [
      _titleCtrl,
      _descriptionCtrl,
      _barangayCtrl,
      _addressCtrl,
      _imageCtrl,
      _openingHoursCtrl,
      _entranceFeeCtrl,
      _bestTimeCtrl,
      _tipsCtrl,
      _ratingCtrl,
    ]) {
      ctrl.addListener(_refreshPreview);
    }
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  void _prefill() {
    final spot = widget.spot;

    if (spot == null) {
      final suggestion = widget.initialSuggestion;
      if (suggestion == null) return;

      _selectedSuggestionId = suggestion.id;
      _applyRawSuggestionValues(suggestion);
      return;
    }

    _titleCtrl.text = spot.title;
    _descriptionCtrl.text = spot.description;
    _addressCtrl.text = spot.address;
    _barangayCtrl.text = spot.barangay;
    _selectedBarangay = spot.barangay.trim().isEmpty ? null : spot.barangay;
    _cityCtrl.text = spot.city;
    _provinceCtrl.text = spot.province;
    _latCtrl.text = spot.latitude == 0 ? '' : spot.latitude.toString();
    _lngCtrl.text = spot.longitude == 0 ? '' : spot.longitude.toString();
    _ratingCtrl.text = spot.rating.toStringAsFixed(1);
    _imageCtrl.text = spot.imageUrl;
    _status = spot.status.trim().isEmpty ? 'active' : spot.status;
    _verificationStatus = spot.verificationStatus.trim().isEmpty
        ? 'pending'
        : spot.verificationStatus;
    _categoryId = spot.categoryId;
    _sourceType = spot.sourceType.trim().isEmpty ? 'manual' : spot.sourceType;
    _selectedGooglePlaceId = spot.googlePlaceId.trim().isEmpty
        ? null
        : spot.googlePlaceId;

    if (spot.latitude != 0 && spot.longitude != 0) {
      _pickedLocation = LatLng(spot.latitude, spot.longitude);
    }
  }

  Future<_SpotFormData> _loadData() async {
    final profile = await _service.loadCurrentProfile();
    final categories = await _service.loadTourismCategories();
    final existingSpots = await _service.fetchSpots(profile);
    final city = profile.assignedCity.trim();
    final province = profile.province.trim().isEmpty
        ? 'Bulacan'
        : profile.province.trim();
    final center =
        const CitySpotSuggestionService().centerForCity(city) ??
        CitySpotSuggestionService.defaultBulacanCenter;

    var suggestions = await const CitySpotSuggestionService().fetchSuggestions(
      city: city,
      province: province,
      center: center,
      limit: 6,
    );

    suggestions = _filterDuplicateSuggestions(
      suggestions,
      existingSpots: existingSpots,
      municipality: city,
    );

    if (!_editing && widget.initialSuggestion != null) {
      final initial = widget.initialSuggestion!;
      final scopedInitial = _belongsToMunicipality(initial, city)
          ? initial
          : null;
      final exists =
          scopedInitial != null &&
          suggestions.any((item) => item.id == scopedInitial.id);
      if (scopedInitial != null && !exists) {
        suggestions = [scopedInitial, ...suggestions];
      }
    }

    final barangays = CitySpotSuggestionService.barangaysForCity(
      profile.assignedCity,
    );

    _cityCtrl.text = profile.assignedCity.trim();
    _provinceCtrl.text = province;

    if (_editing) {
      _selectedBarangay = _matchBarangay(_barangayCtrl.text, barangays);
      if (_selectedBarangay != null) _barangayCtrl.text = _selectedBarangay!;
    } else if (widget.initialSuggestion != null) {
      final selected = _findSuggestionById(
        suggestions,
        widget.initialSuggestion!.id,
      );

      if (selected != null) {
        await _applySuggestion(
          selected,
          categories,
          barangays,
          animateMap: false,
          showLoading: false,
        );
      }
    }

    return _SpotFormData(
      profile: profile,
      categories: categories,
      suggestions: suggestions,
      barangays: barangays,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _mapController?.dispose();

    for (final ctrl in [
      _titleCtrl,
      _descriptionCtrl,
      _barangayCtrl,
      _cityCtrl,
      _provinceCtrl,
      _addressCtrl,
      _latCtrl,
      _lngCtrl,
      _ratingCtrl,
      _imageCtrl,
      _openingHoursCtrl,
      _entranceFeeCtrl,
      _contactCtrl,
      _websiteCtrl,
      _bestTimeCtrl,
      _tipsCtrl,
      _suggestedSpotCtrl,
    ]) {
      ctrl.dispose();
    }

    super.dispose();
  }

  void _applyRawSuggestionValues(CitySpotSuggestion suggestion) {
    _selectedSuggestionId = suggestion.id;
    _selectedGooglePlaceId = suggestion.id;
    _selectedGooglePhotoReference = suggestion.photoReference.trim().isEmpty
        ? null
        : suggestion.photoReference.trim();
    _sourceType = 'google_places';
    _titleCtrl.text = suggestion.title.trim();
    _descriptionCtrl.text = _enhancedDescription(
      suggestion.title,
      suggestion.description,
    );
    _barangayCtrl.text = suggestion.barangayHint.trim();
    _addressCtrl.text = suggestion.address.trim();
    _latCtrl.text = suggestion.latitude.toStringAsFixed(7);
    _lngCtrl.text = suggestion.longitude.toStringAsFixed(7);
    _ratingCtrl.text = _safeRatingText(suggestion.rating);
    _imageCtrl.text = _safeImageUrl(suggestion.imageForCard);
    _suggestedSpotCtrl.text = suggestion.title.trim();
    _pickedLocation = LatLng(suggestion.latitude, suggestion.longitude);
  }

  Future<void> _applySuggestion(
    CitySpotSuggestion suggestion,
    List<SubTenantCategory> categories,
    List<String> barangays, {
    bool animateMap = true,
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() => _autoFilling = true);
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }

    final defaults = _defaultsForCategory(suggestion.category);

    _selectedSuggestionId = suggestion.id;
    _selectedGooglePlaceId = suggestion.id;
    _selectedGooglePhotoReference = suggestion.photoReference.trim().isEmpty
        ? null
        : suggestion.photoReference.trim();
    _sourceType = 'google_places';
    _suggestedSpotCtrl.text = suggestion.title.trim();

    _titleCtrl.text = suggestion.title.trim();
    _descriptionCtrl.text = _enhancedDescription(
      suggestion.title,
      suggestion.description,
    );
    _addressCtrl.text = _smartAddress(suggestion, barangays);
    _latCtrl.text = suggestion.latitude.toStringAsFixed(7);
    _lngCtrl.text = suggestion.longitude.toStringAsFixed(7);
    _ratingCtrl.text = _safeRatingText(suggestion.rating);
    _imageCtrl.text = _safeImageUrl(suggestion.imageForCard);

    _openingHoursCtrl.text = defaults.openingHours;
    _entranceFeeCtrl.text = defaults.entranceFee;
    _bestTimeCtrl.text = defaults.bestTime;
    _tipsCtrl.text = defaults.travelTips;

    _categoryId = _matchCategoryId(suggestion.category, categories);

    final matchedBarangay = _matchBarangay(suggestion.barangayHint, barangays);
    _selectedBarangay = matchedBarangay;
    _barangayCtrl.text = matchedBarangay ?? '';

    _pickedLocation = LatLng(suggestion.latitude, suggestion.longitude);

    if (mounted) {
      setState(() => _autoFilling = false);
    }

    if (animateMap) {
      _animateToLocation(_pickedLocation!, zoom: 16.5);
    }
  }

  void _switchToManualEntry() {
    setState(() {
      _selectedSuggestionId = null;
      _selectedGooglePlaceId = null;
      _selectedGooglePhotoReference = null;
      _sourceType = 'manual';
      _suggestedSpotCtrl.clear();
      _titleCtrl.clear();
      _descriptionCtrl.clear();
      _addressCtrl.clear();
      _barangayCtrl.clear();
      _selectedBarangay = null;
      _latCtrl.clear();
      _lngCtrl.clear();
      _ratingCtrl.text = '0.0';
      _imageCtrl.clear();
      _openingHoursCtrl.clear();
      _entranceFeeCtrl.clear();
      _bestTimeCtrl.clear();
      _tipsCtrl.clear();
      _pickedLocation = null;
      _categoryId = null;
    });
  }

  void _setPickedLocation(LatLng position) {
    setState(() {
      _pickedLocation = position;
      _latCtrl.text = position.latitude.toStringAsFixed(7);
      _lngCtrl.text = position.longitude.toStringAsFixed(7);
    });

    _animateToLocation(position, zoom: 16);
  }

  void _animateToLocation(LatLng position, {double zoom = 15.5}) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: position, zoom: zoom),
      ),
    );
  }

  void _onBarangayChanged(String? barangay, SubTenantProfile profile) {
    if (barangay == null) return;

    setState(() {
      _selectedBarangay = barangay;
      _barangayCtrl.text = barangay;
    });

    if (_pickedLocation == null) {
      final center = _municipalityCenter(profile.assignedCity);
      _setPickedLocation(center);
    }
  }

  CitySpotSuggestion? _findSuggestionById(
    List<CitySpotSuggestion> suggestions,
    String id,
  ) {
    for (final suggestion in suggestions) {
      if (suggestion.id == id) return suggestion;
    }
    return null;
  }

  List<CitySpotSuggestion> _filterDuplicateSuggestions(
    List<CitySpotSuggestion> suggestions, {
    required List<SubTenantSpot> existingSpots,
    required String municipality,
  }) {
    final targetMunicipality = _normalizeText(municipality);
    final existingPlaceIds = existingSpots
        .map((spot) => spot.googlePlaceId.trim().toLowerCase())
        .where((id) => id.isNotEmpty)
        .toSet();
    final existingTitlesByMunicipality = existingSpots
        .where(
          (spot) =>
              _normalizeText(
                spot.municipality.isEmpty ? spot.city : spot.municipality,
              ) ==
              targetMunicipality,
        )
        .map((spot) => _normalizeText(spot.title))
        .where((title) => title.isNotEmpty)
        .toSet();

    final filtered = <CitySpotSuggestion>[];
    final seenIds = <String>{};
    final seenTitles = <String>{};

    for (final suggestion in suggestions) {
      if (!_belongsToMunicipality(suggestion, municipality)) continue;

      final placeId = suggestion.id.trim().toLowerCase();
      final normalizedTitle = _normalizeText(suggestion.title);
      if (placeId.isNotEmpty && existingPlaceIds.contains(placeId)) continue;
      if (normalizedTitle.isEmpty) continue;
      if (_isSimilarSavedTitle(normalizedTitle, existingTitlesByMunicipality)) {
        continue;
      }
      if (placeId.isNotEmpty && !seenIds.add(placeId)) continue;
      if (!seenTitles.add(normalizedTitle)) continue;

      filtered.add(suggestion);
    }

    return filtered;
  }

  bool _belongsToMunicipality(
    CitySpotSuggestion suggestion,
    String municipality,
  ) {
    final target = _normalizeText(municipality);
    final suggestionCity = _normalizeText(suggestion.city);
    final suggestionAddress = _normalizeText(suggestion.address);

    return suggestionCity == target ||
        (suggestionCity.isNotEmpty && target.contains(suggestionCity)) ||
        suggestionAddress.contains(target);
  }

  bool _isSimilarSavedTitle(String title, Set<String> savedTitles) {
    for (final saved in savedTitles) {
      if (saved == title || saved.contains(title) || title.contains(saved)) {
        return true;
      }
    }
    return false;
  }

  dynamic _matchCategoryId(
    String suggestionCategory,
    List<SubTenantCategory> categories,
  ) {
    final target = _normalizeText(suggestionCategory);

    for (final category in categories) {
      final current = _normalizeText(category.name);
      if (current == target ||
          current.contains(target) ||
          target.contains(current)) {
        return category.id;
      }
    }

    return categories.isNotEmpty ? categories.first.id : null;
  }

  String? _matchBarangay(String value, List<String> barangays) {
    final target = _normalizeText(value);
    if (target.isEmpty || barangays.isEmpty) return null;

    for (final barangay in barangays) {
      if (_normalizeText(barangay) == target) return barangay;
    }

    for (final barangay in barangays) {
      final normalized = _normalizeText(barangay);
      if (normalized.contains(target) || target.contains(normalized)) {
        return barangay;
      }
    }

    return null;
  }

  Future<void> _save(SubTenantProfile profile, List<String> barangays) async {
    FocusScope.of(context).unfocus();

    final authUserId = _currentUserId;
    if (authUserId == null) {
      showSubTenantSnack(
        context,
        'Your session has expired. Please sign in again before saving.',
      );
      return;
    }

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      _scrollToTop();
      return;
    }

    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());

    if (lat == null || lng == null) {
      _scrollToTop();
      showSubTenantSnack(
        context,
        'Please pin the tourist spot location on the map.',
      );
      return;
    }

    final barangay = _selectedBarangay?.trim() ?? _barangayCtrl.text.trim();

    if (barangays.isNotEmpty && !barangays.contains(barangay)) {
      _scrollToTop();
      showSubTenantSnack(
        context,
        'Please select a valid barangay under ${profile.assignedCity}.',
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final payload = _buildSavePayload(
        profile: profile,
        barangay: barangay,
        latitude: lat,
        longitude: lng,
        authUserId: authUserId,
      );

      await _service.saveSpot(
        profile: profile,
        spotId: widget.spot?.id,
        values: payload,
      );

      if (!mounted) return;

      showSubTenantSnack(
        context,
        _editing ? 'Tourist spot updated.' : 'Tourist spot created.',
        error: false,
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to save tourist spot: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _buildSavePayload({
    required SubTenantProfile profile,
    required String barangay,
    required double latitude,
    required double longitude,
    required String authUserId,
  }) {
    final rating = double.tryParse(_ratingCtrl.text.trim()) ?? 0.0;
    final title = _titleCtrl.text.trim();
    final isCreate = !_editing;

    final payload = <String, dynamic>{
      'title': title,
      'description': _enhancedDescription(title, _descriptionCtrl.text),
      'address': _nonEmpty(_addressCtrl.text, fallback: 'Brgy. $barangay'),
      'barangay': barangay,
      'city': profile.assignedCity.trim(),
      'municipality': profile.assignedCity.trim(),
      'province': profile.province.trim().isEmpty
          ? 'Bulacan'
          : profile.province.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'rating': rating.clamp(0.0, 5.0),
      'image_url': _safeImageUrl(_imageCtrl.text),
      'status': _status.trim().isEmpty ? 'active' : _status.trim(),
      'source_type': _sourceType,
      if (_selectedGooglePlaceId != null)
        'google_place_id': _selectedGooglePlaceId,
      if (_selectedGooglePhotoReference != null)
        'google_photo_reference': _selectedGooglePhotoReference,

      // Important for Supabase RLS. Most policies allow subtenants to insert
      // only rows where submitted_by = auth.uid().
      if (isCreate) 'submitted_by': authUserId,

      // Keep create requests pending. Do not allow a subtenant create flow to
      // insert directly as verified because many RLS policies block that.
      'verification_status': isCreate
          ? 'pending'
          : (_verificationStatus.trim().isEmpty
                ? 'pending'
                : _verificationStatus.trim()),

      if (_categoryId != null) 'category_id': _categoryId,
      'opening_hours': _nonEmpty(
        _openingHoursCtrl.text,
        fallback: _defaultsForCategory(_selectedCategoryName()).openingHours,
      ),
      'entrance_fee': _nonEmpty(_entranceFeeCtrl.text, fallback: 'Free'),
      'contact_number': _contactCtrl.text.trim(),
      'website_url': _websiteCtrl.text.trim(),
      'best_time_to_visit': _nonEmpty(
        _bestTimeCtrl.text,
        fallback: 'Morning, weekends, and sunset hours',
      ),
      'travel_tips': _nonEmpty(
        _tipsCtrl.text,
        fallback:
            'Bring water and wear comfortable clothing. Best visited during daylight hours.',
      ),
    };

    payload.removeWhere((_, value) {
      if (value == null) return true;
      if (value is String && value.trim().isEmpty) return true;
      return false;
    });

    return payload;
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  String _selectedCategoryName() {
    return _suggestedSpotCtrl.text.trim().isEmpty
        ? 'tourist spot'
        : _suggestedSpotCtrl.text.trim();
  }

  _SpotDefaults _defaultsForCategory(String category) {
    final normalized = _normalizeText(category);

    if (normalized.contains('park') ||
        normalized.contains('nature') ||
        normalized.contains('garden')) {
      return const _SpotDefaults(
        openingHours: '6:00 AM - 6:00 PM',
        entranceFee: 'Free',
        bestTime: 'Morning and sunset',
        travelTips:
            'Bring water, wear comfortable clothing, and visit during daylight hours.',
      );
    }

    if (normalized.contains('museum') ||
        normalized.contains('heritage') ||
        normalized.contains('historical')) {
      return const _SpotDefaults(
        openingHours: '8:00 AM - 5:00 PM',
        entranceFee: 'Free or minimal entrance fee',
        bestTime: 'Weekday mornings',
        travelTips:
            'Check operating days before visiting and bring a camera for heritage displays.',
      );
    }

    if (normalized.contains('resort') ||
        normalized.contains('hotel') ||
        normalized.contains('pool')) {
      return const _SpotDefaults(
        openingHours: 'Open 24 Hours',
        entranceFee: 'Contact management for rates',
        bestTime: 'Weekends and summer season',
        travelTips:
            'Bring swimwear, extra clothes, and confirm cottage or room availability in advance.',
      );
    }

    if (normalized.contains('church') ||
        normalized.contains('chapel') ||
        normalized.contains('religious')) {
      return const _SpotDefaults(
        openingHours: '6:00 AM - 6:00 PM',
        entranceFee: 'Free',
        bestTime: 'Morning and late afternoon',
        travelTips:
            'Observe proper attire and respect ongoing religious activities.',
      );
    }

    if (normalized.contains('food') ||
        normalized.contains('restaurant') ||
        normalized.contains('cafe')) {
      return const _SpotDefaults(
        openingHours: '10:00 AM - 9:00 PM',
        entranceFee: 'Depends on order',
        bestTime: 'Lunch, dinner, and weekends',
        travelTips:
            'Check peak hours and prepare digital or cash payment options.',
      );
    }

    return const _SpotDefaults(
      openingHours: '8:00 AM - 5:00 PM',
      entranceFee: 'Free',
      bestTime: 'Morning, weekends, and sunset hours',
      travelTips:
          'Bring water and wear comfortable clothing. Best visited during daylight hours.',
    );
  }

  String _enhancedDescription(String title, String description) {
    final cleanTitle = title.trim();
    final cleanDescription = description.trim();

    if (cleanDescription.length >= 90) return cleanDescription;

    if (cleanDescription.isEmpty) {
      return '$cleanTitle is a recommended tourist destination where visitors can enjoy local attractions, take photos, and explore the surrounding community.';
    }

    return '$cleanDescription Visitors can enjoy the area, take memorable photos, and experience one of the local highlights of the municipality.';
  }

  String _smartAddress(CitySpotSuggestion suggestion, List<String> barangays) {
    final address = suggestion.address.trim();
    if (address.isNotEmpty) return address;

    final barangay = _matchBarangay(suggestion.barangayHint, barangays);
    if (barangay != null) return 'Brgy. $barangay';

    return suggestion.title.trim();
  }

  String _safeRatingText(double rating) {
    if (rating <= 0) return '0.0';
    return rating.clamp(0.0, 5.0).toStringAsFixed(1);
  }

  String _safeImageUrl(String value) {
    final url = value.trim();
    if (url.isEmpty) {
      return 'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80';
    }
    return url;
  }

  String _nonEmpty(String value, {required String fallback}) {
    return value.trim().isEmpty ? fallback : value.trim();
  }

  String _normalizeText(String value) {
    return value
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll('barangay', '')
        .replaceAll('brgy.', '')
        .replaceAll('brgy', '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SubTenantColors.background,
      appBar: subTenantAppBar(
        context,
        title: _editing ? 'Edit Tourist Spot' : 'Create Tourist Spot',
        showBack: true,
      ),
      body: FutureBuilder<_SpotFormData>(
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

          return Stack(
            children: [
              Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 980;

                    return SingleChildScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 24 : 14,
                        14,
                        isWide ? 24 : 14,
                        30,
                      ),
                      child: isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 55,
                                  child: Column(
                                    children: [
                                      _basicInfoCard(data),
                                      const SizedBox(height: 14),
                                      _detailsCard(data),
                                      const SizedBox(height: 14),
                                      _statusCard(),
                                      const SizedBox(height: 18),
                                      _saveButton(data),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  flex: 45,
                                  child: Column(
                                    children: [
                                      _mapCard(data.profile),
                                      const SizedBox(height: 14),
                                      _mediaCard(),
                                      const SizedBox(height: 14),
                                      _previewCard(),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                _basicInfoCard(data),
                                const SizedBox(height: 14),
                                _mapCard(data.profile),
                                const SizedBox(height: 14),
                                _detailsCard(data),
                                const SizedBox(height: 14),
                                _mediaCard(),
                                const SizedBox(height: 14),
                                _statusCard(),
                                const SizedBox(height: 14),
                                _previewCard(),
                                const SizedBox(height: 18),
                                _saveButton(data),
                              ],
                            ),
                    );
                  },
                ),
              ),
              if (_autoFilling)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.white.withValues(alpha: .18),
                      child: const Center(child: _AutofillBadge()),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _basicInfoCard(_SpotFormData data) {
    final useAiSelection = !_editing;

    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubTenantSectionHeader(
            title: 'Spot Information',
            subtitle: useAiSelection
                ? 'Google Places suggestions are optional. You can create a tourist spot manually anytime.'
                : 'Update the tourist spot details without changing its city assignment',
          ),
          const SizedBox(height: 14),
          if (useAiSelection) ...[
            _smartHelper(
              icon: Icons.auto_awesome_rounded,
              text:
                  'Google Places suggestions use the same municipality-based search logic as the tourist Explore screen for ${data.profile.assignedCity}. You can still edit every field before saving.',
            ),
            const SizedBox(height: 12),
            _label('Google Place Suggestion'),
            const SizedBox(height: 8),
            if (data.suggestions.isEmpty)
              _smartHelper(
                icon: Icons.info_rounded,
                text: 'No Google Places suggestions found',
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  return DropdownMenu<String>(
                    controller: _suggestedSpotCtrl,
                    width: constraints.maxWidth,
                    initialSelection: _selectedSuggestionId,
                    enableFilter: true,
                    enableSearch: true,
                    requestFocusOnTap: true,
                    hintText: 'Search Google-suggested places',
                    inputDecorationTheme: _inputDecorationTheme(),
                    dropdownMenuEntries: data.suggestions
                        .map(
                          (suggestion) => DropdownMenuEntry<String>(
                            value: suggestion.id,
                            label: suggestion.title,
                            leadingIcon: const Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                              color: SubTenantColors.blue,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onSelected: (value) async {
                      if (value == null) return;

                      final selected = _findSuggestionById(
                        data.suggestions,
                        value,
                      );
                      if (selected == null) return;

                      await _applySuggestion(
                        selected,
                        data.categories,
                        data.barangays,
                      );
                    },
                  );
                },
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _dataFuture = _loadData()),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh Suggestions'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: SubTenantColors.blue,
                      side: const BorderSide(color: SubTenantColors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _switchToManualEntry,
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('Add Manually'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: SubTenantColors.text,
                      side: const BorderSide(color: SubTenantColors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          SubTenantTextField(
            controller: _titleCtrl,
            label: 'Spot Name',
            hint: 'e.g. Heritage Park, Riverside Cafe, City Museum',
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Spot name is required.' : null,
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _descriptionCtrl,
            label: 'Description',
            hint: 'Describe what tourists can see or do here.',
            maxLines: 5,
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Description is required.'
                : null,
          ),
          const SizedBox(height: 12),
          if (data.categories.isNotEmpty) ...[
            _label('Category'),
            const SizedBox(height: 8),
            DropdownButtonFormField<dynamic>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: _inputDecoration(),
              validator: (value) =>
                  value == null ? 'Please select a category.' : null,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Select category'),
                ),
                ...data.categories.map(
                  (category) => DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: 12),
          ],
          _label('Barangay'),
          const SizedBox(height: 8),
          if (data.barangays.isNotEmpty)
            FormField<String>(
              initialValue: _selectedBarangay,
              validator: (_) {
                final selected = _selectedBarangay ?? _barangayCtrl.text.trim();

                if (selected.isEmpty) return 'Please select a barangay.';

                if (!data.barangays.contains(selected)) {
                  return 'Select a valid barangay under ${data.profile.assignedCity}.';
                }

                return null;
              },
              builder: (field) {
                return _dropdownWithError(
                  errorText: field.errorText,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return DropdownMenu<String>(
                        key: ValueKey(_selectedBarangay ?? 'barangay'),
                        controller: _barangayCtrl,
                        width: constraints.maxWidth,
                        initialSelection: _selectedBarangay,
                        enableFilter: true,
                        enableSearch: true,
                        requestFocusOnTap: true,
                        hintText:
                            'Search barangay in ${data.profile.assignedCity}',
                        inputDecorationTheme: _inputDecorationTheme(),
                        dropdownMenuEntries: data.barangays
                            .map(
                              (barangay) => DropdownMenuEntry<String>(
                                value: barangay,
                                label: barangay,
                                leadingIcon: const Icon(
                                  Icons.location_city_rounded,
                                  size: 18,
                                  color: SubTenantColors.blue,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onSelected: (value) {
                          field.didChange(value);
                          _onBarangayChanged(value, data.profile);
                        },
                      );
                    },
                  ),
                );
              },
            )
          else
            SubTenantTextField(
              controller: _barangayCtrl,
              label: 'Barangay',
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Barangay is required.' : null,
            ),
          const SizedBox(height: 8),
          _smartHelper(
            icon: Icons.verified_rounded,
            text: data.barangays.isNotEmpty
                ? 'Only barangays under ${data.profile.assignedCity} can be selected.'
                : 'Barangay list is unavailable, so manual entry is temporarily enabled.',
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _addressCtrl,
            label: 'Complete Address / Landmark',
            hint: 'Street, landmark, or nearby reference',
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SubTenantTextField(
                  controller: _cityCtrl,
                  label: 'City / Municipality',
                  enabled: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SubTenantTextField(
                  controller: _provinceCtrl,
                  label: 'Province',
                  enabled: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mapCard(SubTenantProfile profile) {
    final cityCenter = _municipalityCenter(profile.assignedCity);
    final initial = _pickedLocation ?? cityCenter;
    final bounds = _municipalityBounds(cityCenter);

    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubTenantSectionHeader(
            title: 'Pin Location',
            subtitle:
                'Tap within ${profile.assignedCity} to place or adjust the tourist spot pin.',
          ),
          const SizedBox(height: 12),
          Container(
            height: 310,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SubTenantColors.line),
            ),
            clipBehavior: Clip.hardEdge,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initial,
                zoom: _pickedLocation == null ? 13.5 : 16,
              ),
              mapType: MapType.normal,
              zoomControlsEnabled: true,
              myLocationButtonEnabled: false,
              minMaxZoomPreference: const MinMaxZoomPreference(11, 19),
              cameraTargetBounds: CameraTargetBounds(bounds),
              onMapCreated: (controller) {
                _mapController = controller;
                if (_pickedLocation != null) {
                  Future.delayed(const Duration(milliseconds: 350), () {
                    if (mounted && _pickedLocation != null) {
                      _animateToLocation(_pickedLocation!, zoom: 16);
                    }
                  });
                }
              },
              onTap: _setPickedLocation,
              markers: {
                if (_pickedLocation != null)
                  Marker(
                    markerId: const MarkerId('spot_location'),
                    position: _pickedLocation!,
                    draggable: true,
                    onDragEnd: _setPickedLocation,
                    infoWindow: InfoWindow(
                      title: _titleCtrl.text.trim().isEmpty
                          ? 'Tourist Spot'
                          : _titleCtrl.text.trim(),
                      snippet: _selectedBarangay ?? profile.assignedCity,
                    ),
                  ),
              },
            ),
          ),
          const SizedBox(height: 12),
          _smartHelper(
            icon: Icons.touch_app_rounded,
            text: _pickedLocation == null
                ? 'Tap the map to pin this tourist spot. Coordinates will be filled automatically.'
                : 'Pinned at ${_latCtrl.text}, ${_lngCtrl.text}',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SubTenantTextField(
                  controller: _latCtrl,
                  label: 'Latitude',
                  enabled: false,
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Pin required.' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SubTenantTextField(
                  controller: _lngCtrl,
                  label: 'Longitude',
                  enabled: false,
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Pin required.' : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailsCard(_SpotFormData data) {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Visitor Details',
            subtitle: 'Use smart presets to minimize manual typing',
          ),
          const SizedBox(height: 14),
          _presetWrap(
            title: 'Opening Hours Presets',
            controller: _openingHoursCtrl,
            values: const [
              '6:00 AM - 6:00 PM',
              '8:00 AM - 5:00 PM',
              '10:00 AM - 9:00 PM',
              'Open 24 Hours',
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SubTenantTextField(
                  controller: _openingHoursCtrl,
                  label: 'Opening Hours',
                  hint: 'e.g. 8:00 AM - 5:00 PM',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SubTenantTextField(
                  controller: _entranceFeeCtrl,
                  label: 'Entrance Fee',
                  hint: 'Free / PHP 50',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _presetWrap(
            title: 'Entrance Fee Presets',
            controller: _entranceFeeCtrl,
            values: const [
              'Free',
              'PHP 20',
              'PHP 50',
              'Contact management for rates',
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SubTenantTextField(
                  controller: _contactCtrl,
                  label: 'Contact Number',
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SubTenantTextField(
                  controller: _ratingCtrl,
                  label: 'Initial Rating',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    final rating = double.tryParse((value ?? '').trim());
                    if (rating == null) return 'Invalid rating.';
                    if (rating < 0 || rating > 5) return 'Use 0 to 5.';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _websiteCtrl,
            label: 'Website / Social Link',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _bestTimeCtrl,
            label: 'Best Time to Visit',
            hint: 'e.g. Morning, sunset, weekends',
          ),
          const SizedBox(height: 10),
          _presetWrap(
            title: 'Best Time Presets',
            controller: _bestTimeCtrl,
            values: const [
              'Morning and sunset',
              'Weekday mornings',
              'Weekends and sunset hours',
              'Summer season',
            ],
          ),
          const SizedBox(height: 12),
          SubTenantTextField(
            controller: _tipsCtrl,
            label: 'Tourist Tips',
            hint: 'Parking, dress code, reminders, accessibility, etc.',
            maxLines: 3,
          ),
          const SizedBox(height: 10),
          _presetWrap(
            title: 'Travel Tips Presets',
            controller: _tipsCtrl,
            values: const [
              'Bring water and wear comfortable clothing.',
              'Best visited during daylight hours.',
              'Check availability before visiting.',
              'Respect local rules and keep the area clean.',
            ],
          ),
        ],
      ),
    );
  }

  Widget _mediaCard() {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Media',
            subtitle: 'Main image used in tourist screens',
          ),
          const SizedBox(height: 14),
          SubTenantTextField(
            controller: _imageCtrl,
            label: 'Image URL',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          _imagePreview(),
        ],
      ),
    );
  }

  Widget _statusCard() {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Publishing',
            subtitle: 'Spot availability and verification state',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: _inputDecoration(hint: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                      value: 'maintenance',
                      child: Text('Maintenance'),
                    ),
                    DropdownMenuItem(
                      value: 'archived',
                      child: Text('Archived'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _editing ? _verificationStatus : 'pending',
                  isExpanded: true,
                  decoration: _inputDecoration(hint: 'Verification'),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                      value: 'verified',
                      child: Text('Verified'),
                    ),
                  ],
                  onChanged: _editing
                      ? (value) {
                          if (value != null) {
                            setState(() => _verificationStatus = value);
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
          if (!_editing) ...[
            const SizedBox(height: 10),
            _smartHelper(
              icon: Icons.lock_clock_rounded,
              text:
                  'New tourist spots are submitted as Pending first. This avoids RLS errors and keeps verification controlled by the review flow.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewCard() {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubTenantSectionHeader(
            title: 'Tourist Spot Preview',
            subtitle: 'Live preview of how tourists may see this spot',
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: SubTenantColors.backgroundAlt,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SubTenantColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _imagePreview(height: 150, compact: true),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleCtrl.text.trim().isEmpty
                            ? 'Tourist Spot Name'
                            : _titleCtrl.text.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SubTenantColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _descriptionCtrl.text.trim().isEmpty
                            ? 'Short description preview for tourists.'
                            : _descriptionCtrl.text.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SubTenantColors.muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 7,
                        children: [
                          _InfoChip(
                            icon: Icons.location_on_rounded,
                            text: (_selectedBarangay?.isEmpty ?? true)
                                ? _cityCtrl.text
                                : 'Brgy. $_selectedBarangay',
                          ),
                          _InfoChip(
                            icon: Icons.schedule_rounded,
                            text: _openingHoursCtrl.text.trim().isEmpty
                                ? 'Hours not set'
                                : _openingHoursCtrl.text.trim(),
                          ),
                          _InfoChip(
                            icon: Icons.payments_rounded,
                            text: _entranceFeeCtrl.text.trim().isEmpty
                                ? 'Fee not set'
                                : _entranceFeeCtrl.text.trim(),
                          ),
                          _InfoChip(
                            icon: Icons.star_rounded,
                            text: _ratingCtrl.text.trim().isEmpty
                                ? '0.0'
                                : _ratingCtrl.text.trim(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetWrap({
    required String title,
    required TextEditingController controller,
    required List<String> values,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: SubTenantColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map((value) {
                return ActionChip(
                  label: Text(value),
                  onPressed: () => setState(() => controller.text = value),
                  backgroundColor: SubTenantColors.blue.withValues(alpha: .08),
                  side: BorderSide(
                    color: SubTenantColors.blue.withValues(alpha: .16),
                  ),
                  labelStyle: const TextStyle(
                    color: SubTenantColors.blue,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _smartHelper({required IconData icon, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SubTenantColors.blue.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubTenantColors.blue.withValues(alpha: .14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: SubTenantColors.blue, size: 20),
          const SizedBox(width: 10),
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
      ),
    );
  }

  Widget _dropdownWithError({
    required Widget child,
    required String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        child,
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            errorText,
            style: const TextStyle(
              color: Color(0xFFB42318),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _imagePreview({double height = 130, bool compact = false}) {
    final url = _imageCtrl.text.trim();

    if (url.isEmpty) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFE4ECF7),
          borderRadius: compact ? BorderRadius.zero : BorderRadius.circular(16),
        ),
        child: const Center(
          child: Icon(
            Icons.image_rounded,
            color: SubTenantColors.lightMuted,
            size: 32,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: compact ? BorderRadius.zero : BorderRadius.circular(16),
      child: Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          height: height,
          width: double.infinity,
          color: const Color(0xFFE4ECF7),
          child: const Center(
            child: Icon(
              Icons.broken_image_rounded,
              color: SubTenantColors.lightMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _saveButton(_SpotFormData data) {
    return SubTenantGradientButton(
      label: _editing ? 'Save Tourist Spot' : 'Create Tourist Spot',
      icon: Icons.save_rounded,
      loading: _saving,
      onPressed: () => _save(data.profile, data.barangays),
    );
  }

  Widget _label(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: SubTenantColors.text,
        fontSize: 13,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFB42318)),
      ),
    );
  }

  InputDecorationTheme _inputDecorationTheme() {
    return InputDecorationTheme(
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
}

class _SpotFormData {
  const _SpotFormData({
    required this.profile,
    required this.categories,
    required this.suggestions,
    required this.barangays,
  });

  final SubTenantProfile profile;
  final List<SubTenantCategory> categories;
  final List<CitySpotSuggestion> suggestions;
  final List<String> barangays;
}

class _SpotDefaults {
  const _SpotDefaults({
    required this.openingHours,
    required this.entranceFee,
    required this.bestTime,
    required this.travelTips,
  });

  final String openingHours;
  final String entranceFee;
  final String bestTime;
  final String travelTips;
}

class _AutofillBadge extends StatelessWidget {
  const _AutofillBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          SizedBox(width: 12),
          Text(
            'Google Places is filling spot details...',
            style: TextStyle(
              color: SubTenantColors.text,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: SubTenantColors.blue.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: SubTenantColors.blue, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: SubTenantColors.blue,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
