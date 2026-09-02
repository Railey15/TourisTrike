import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/services/itinerary_schedule_service.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/tourist/tourist_activity_screen.dart';
import 'package:touristrike/screens/tourist/tourist_activity_tracking_screen.dart';

// ============================================================================
// SHARED TOURISTRlKE BOOKING UI COLORS
// ============================================================================

const Color _primary = Color(0xFF2A86FF);
const Color _background = Color(0xFFF5F7FB);
const Color _ink = Color(0xFF0F172A);
const Color _secondaryText = Color(0xFF64748B);
const Color _border = Color(0xFFE4EBF4);
const Color _softBlue = Color(0xFFEAF3FF);

// =============================================================================
// AUTOCOMPLETE
// =============================================================================

class _AutocompleteResult {
  const _AutocompleteResult({required this.placeId, required this.description});

  final String placeId;
  final String description;
}

// =============================================================================
// BOOKING SCREEN
// =============================================================================

class PackageBookingScreen extends StatefulWidget {
  const PackageBookingScreen({
    super.key,
    required this.packageId,
    this.initialPackage,

    // Kept only for backward compatibility with other callers.
    this.customizedSpots = const [],
    this.customizedUnitPrice,
  });

  final dynamic packageId;
  final TourPackage? initialPackage;

  final List<Map<String, dynamic>> customizedSpots;
  final double? customizedUnitPrice;

  @override
  State<PackageBookingScreen> createState() => _PackageBookingScreenState();
}

class _PackageBookingScreenState extends State<PackageBookingScreen> {
  static const double _additionalSpotFee = 250;

  static const int _tourStartMinutes = 7 * 60;
  static const int _tourEndMinutes = 17 * 60;

  static const int _minimumSpots = 3;
  static const int _maximumSpots = 6;

  static const int _tricycleCapacity = 3;

  static const String _tourHoursErrorMessage =
      'Your itinerary exceeds the allowed tour hours. Tours are only available from 7:00 AM to 5:00 PM.';

  final TourisTrikeRepository _repo = TourisTrikeRepository();
  late final ItineraryScheduleService _scheduleService =
      ItineraryScheduleService(
        apiKey: CitySpotSuggestionService.resolveApiKey(),
      );

  final PageController _pageController = PageController();
  final TextEditingController _notesCtrl = TextEditingController();

  late Future<_BookingScreenData> _future;

  int _currentStep = 0;

  DateTime? _selectedDate;
  TimeOfDay? _selectedPickupTime;

  int _adults = 1;
  int _children = 0;
  int _selectedTricycles = 1;

  _PaymentMethod _payment = _PaymentMethod.gcash;

  bool _saving = false;

  // ---------------------------------------------------------------------------
  // LOCATION
  // ---------------------------------------------------------------------------

  _SelectedLocation? _selectedPickup;
  _SelectedLocation? _selectedDropoff;

  String? _pickupLocationError;
  String? _dropoffLocationError;

  // ---------------------------------------------------------------------------
  // SPOTS
  // ---------------------------------------------------------------------------

  final List<_EditableBookingSpot> _selectedSpots = [];
  final List<_EditableBookingSpot> _originalSpots = [];

  List<CitySpotSuggestion> _googleSuggestions = const [];

  dynamic _initializedSpotPackageId;

  String _spotCategory = 'All';

  bool _spotSelectionDirtyForSchedule = true;

  // ---------------------------------------------------------------------------
  // SCHEDULE
  // ---------------------------------------------------------------------------

  List<_EditableItineraryStop> _suggestedItinerary = const [];
  List<_EditableItineraryStop> _customizedItinerary = const [];

  _ItineraryViewMode _itineraryMode = _ItineraryViewMode.suggested;

  bool _customizedItineraryDirty = false;
  bool _scheduleLoading = false;
  int _scheduleRevision = 0;
  int _finalTravelDurationMinutes = 0;

  // =============================================================================
  // LIFECYCLE
  // =============================================================================

  @override
  void initState() {
    super.initState();
    _future = _loadPackage();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _pageController.dispose();

    _disposeItineraries();

    super.dispose();
  }

  // =============================================================================
  // LOAD
  // =============================================================================

  Future<_BookingScreenData> _loadPackage() async {
    TourPackage? package;

    if (widget.initialPackage != null &&
        widget.initialPackage!.id == widget.packageId) {
      package = widget.initialPackage!;
    } else {
      package = await _repo.fetchTourPackage(widget.packageId);
    }

    if (package == null) {
      throw StateError('Package not found.');
    }

    final province = dbString(package.row['province'], fallback: 'Bulacan');

    final packageSpotsFuture = _repo.fetchPackageSpots(package.id);

    final suggestionFuture = CitySpotSuggestionService().fetchSuggestions(
      city: package.city,
      province: province,
      limit: 20,
    );

    final packageSpots = await packageSpotsFuture;

    List<CitySpotSuggestion> suggestions;

    try {
      suggestions = await suggestionFuture;
    } catch (_) {
      suggestions = const [];
    }

    suggestions = suggestions
        .where((spot) => _sameMunicipality(spot.city, package!.city))
        .toList(growable: false);

    return _BookingScreenData(
      package: package,
      packageSpots: packageSpots,
      googleSuggestions: suggestions,
    );
  }

  void _initializeSpotSelection(_BookingScreenData data) {
    if (_initializedSpotPackageId == data.package.id) {
      return;
    }

    _initializedSpotPackageId = data.package.id;

    _originalSpots
      ..clear()
      ..addAll(
        data.packageSpots.map(
          (spot) =>
              _EditableBookingSpot.fromTouristSpot(spot, isOriginal: true),
        ),
      );

    _selectedSpots.clear();

    // Backward compatibility if another page still passes customizedSpots.
    if (widget.customizedSpots.isNotEmpty) {
      final activeRows =
          widget.customizedSpots
              .where(
                (row) =>
                    row['action_type'] == 'kept' ||
                    row['action_type'] == 'added',
              )
              .toList()
            ..sort(
              (a, b) =>
                  dbInt(a['sort_order']).compareTo(dbInt(b['sort_order'])),
            );

      _selectedSpots.addAll(
        activeRows.map(_EditableBookingSpot.fromCustomizationRow),
      );
    } else {
      _selectedSpots.addAll(_originalSpots.map(_EditableBookingSpot.copy));
    }

    _googleSuggestions = data.googleSuggestions;

    _spotSelectionDirtyForSchedule = true;

    _rebuildScheduleFromSelectedSpots();
  }

  // =============================================================================
  // PARTICIPANTS
  // =============================================================================

  int get _totalParticipants => _adults + _children;

  int get _minimumRequiredTricycles =>
      (_totalParticipants / _tricycleCapacity).ceil().clamp(1, 99);

  int get _requiredTricycles =>
      math.max(_selectedTricycles, _minimumRequiredTricycles);

  void _keepSelectedTricyclesAboveMinimum() {
    _selectedTricycles = math.max(
      _selectedTricycles,
      _minimumRequiredTricycles,
    );
  }

  // =============================================================================
  // BOOKING TYPE
  // =============================================================================

  bool get _isSameDay {
    if (_selectedDate == null) {
      return false;
    }

    final now = DateTime.now();

    return _selectedDate!.year == now.year &&
        _selectedDate!.month == now.month &&
        _selectedDate!.day == now.day;
  }

  String get _bookingType {
    return _isSameDay ? 'same_day' : 'advanced';
  }

  // =============================================================================
  // SPOT PRICING
  // =============================================================================

  int get _addedGoogleSpotCount {
    return _selectedSpots.where((spot) => !spot.isOriginal).length;
  }

  double _unitPrice(TourPackage package) {
    if (widget.customizedUnitPrice != null &&
        widget.customizedSpots.isNotEmpty &&
        _initializedSpotPackageId == null) {
      return widget.customizedUnitPrice!;
    }

    return package.numericPrice + (_addedGoogleSpotCount * _additionalSpotFee);
  }

  double _totalPrice(TourPackage package) {
    final price = _unitPrice(package);

    if (price <= 0) {
      return 0;
    }

    return price * _totalParticipants;
  }

  double _downpaymentAmount(TourPackage package) {
    return (_totalPrice(package) * 50).roundToDouble() / 100;
  }

  double _remainingBalance(TourPackage package) {
    return _totalPrice(package) - _downpaymentAmount(package);
  }

  double _amountToPayNow(TourPackage package) {
    return _downpaymentAmount(package);
  }

  // =============================================================================
  // LOCATION
  // =============================================================================

  void _onPickupSelected(String? address, double? lat, double? lng) {
    setState(() {
      if (address != null && lat != null && lng != null) {
        _selectedPickup = _SelectedLocation(
          address: address,
          latitude: lat,
          longitude: lng,
          isValidWithinMunicipality: true,
        );

        _pickupLocationError = null;
      } else {
        _selectedPickup = null;
      }
    });
    unawaited(_recalculateSelectedItinerary());
  }

  void _onDropoffSelected(String? address, double? lat, double? lng) {
    setState(() {
      if (address != null && lat != null && lng != null) {
        _selectedDropoff = _SelectedLocation(
          address: address,
          latitude: lat,
          longitude: lng,
          isValidWithinMunicipality: true,
        );

        _dropoffLocationError = null;
      } else {
        _selectedDropoff = null;
      }
    });
    unawaited(_recalculateSelectedItinerary());
  }

  String _packageProvince(TourPackage package) {
    return dbString(package.row['province'], fallback: 'Bulacan');
  }

  String? _locationBlockingMessage(TourPackage package) {
    if (_pickupLocationError != null) {
      return _pickupLocationError;
    }

    if (_dropoffLocationError != null) {
      return _dropoffLocationError;
    }

    if (_selectedPickup == null ||
        !_selectedPickup!.isValidWithinMunicipality) {
      return 'Select a pickup point within ${package.city}, ${_packageProvince(package)}.';
    }

    if (_selectedDropoff == null ||
        !_selectedDropoff!.isValidWithinMunicipality) {
      return 'Select a drop-off point within ${package.city}, ${_packageProvince(package)}.';
    }

    return null;
  }

  // =============================================================================
  // SPOT MANAGEMENT
  // =============================================================================

  String? _spotValidationMessage() {
    if (_selectedSpots.length < _minimumSpots) {
      return 'Please select at least $_minimumSpots destinations for your tour.';
    }

    if (_selectedSpots.length > _maximumSpots) {
      return 'You can only select up to $_maximumSpots destinations.';
    }

    return null;
  }

  bool _containsSpot(_EditableBookingSpot spot) {
    return _selectedSpots.any((item) => item.key == spot.key);
  }

  void _addGoogleSuggestion(CitySpotSuggestion suggestion) {
    if (_selectedSpots.length >= _maximumSpots) {
      _snack('You can only select up to $_maximumSpots destinations.');
      return;
    }

    final candidate = _EditableBookingSpot.fromSuggestion(suggestion);

    if (_containsSpot(candidate)) {
      _snack('This destination is already selected.');
      return;
    }

    setState(() {
      _selectedSpots.add(candidate);
      _spotSelectionDirtyForSchedule = true;
    });
  }

  void _removeSelectedSpot(_EditableBookingSpot spot) {
    if (_selectedSpots.length <= _minimumSpots) {
      _snack('At least $_minimumSpots destinations are required.');
      return;
    }

    setState(() {
      _selectedSpots.removeWhere((item) => item.key == spot.key);

      _spotSelectionDirtyForSchedule = true;
    });
  }

  void _restoreOriginalSpot(_EditableBookingSpot original) {
    if (_selectedSpots.length >= _maximumSpots) {
      _snack('You can only select up to $_maximumSpots destinations.');
      return;
    }

    if (_containsSpot(original)) {
      return;
    }

    setState(() {
      _selectedSpots.add(_EditableBookingSpot.copy(original));

      _spotSelectionDirtyForSchedule = true;
    });
  }

  void _moveSelectedSpot(int index, int delta) {
    final nextIndex = index + delta;

    if (nextIndex < 0 || nextIndex >= _selectedSpots.length) {
      return;
    }

    setState(() {
      final item = _selectedSpots.removeAt(index);

      _selectedSpots.insert(nextIndex, item);

      _spotSelectionDirtyForSchedule = true;
    });
  }

  List<_EditableBookingSpot> get _removedOriginalSpots {
    final selectedKeys = _selectedSpots.map((spot) => spot.key).toSet();

    return _originalSpots
        .where((spot) => !selectedKeys.contains(spot.key))
        .toList(growable: false);
  }

  List<CitySpotSuggestion> get _filteredGoogleSuggestions {
    final selectedKeys = _selectedSpots.map((spot) => spot.key).toSet();

    final selectedTitles = _selectedSpots
        .map((spot) => _normalizeText(spot.title))
        .toSet();

    return _googleSuggestions
        .where((suggestion) {
          if (selectedKeys.contains('google:${suggestion.id}')) {
            return false;
          }

          if (selectedTitles.contains(_normalizeText(suggestion.title))) {
            return false;
          }

          if (_spotCategory != 'All' && suggestion.category != _spotCategory) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _buildCustomizationRows(TourPackage package) {
    final selectedKeys = _selectedSpots.map((spot) => spot.key).toSet();

    final rows = <Map<String, dynamic>>[];

    for (var i = 0; i < _selectedSpots.length; i++) {
      final spot = _selectedSpots[i];

      rows.add({
        'spot_id': spot.spotId,
        'action_type': spot.isOriginal ? 'kept' : 'added',
        'source_type': spot.sourceType,
        'google_place_id': spot.googlePlaceId,
        'spot_title': spot.title,
        'spot_address': spot.address,
        'municipality': package.city,
        'barangay': spot.barangay,
        'latitude': spot.latitude,
        'longitude': spot.longitude,
        'image_url': spot.imageUrl,
        'additional_fee': spot.isOriginal ? 0 : _additionalSpotFee,
        'sort_order': i,
        'opening_time': spot.openingTime.isEmpty ? null : spot.openingTime,
        'closing_time': spot.closingTime.isEmpty ? null : spot.closingTime,
        'estimated_arrival_time': spot.estimatedArrivalTime.isEmpty
            ? null
            : spot.estimatedArrivalTime,
        'estimated_duration_minutes': spot.estimatedDurationMinutes > 0
            ? spot.estimatedDurationMinutes
            : null,
        'recommended_visit_duration_minutes':
            spot.recommendedVisitDurationMinutes > 0
            ? spot.recommendedVisitDurationMinutes
            : null,
      });
    }

    for (final original in _originalSpots) {
      if (selectedKeys.contains(original.key)) {
        continue;
      }

      rows.add({
        'spot_id': original.spotId,
        'action_type': 'removed',
        'source_type': original.sourceType,
        'google_place_id': original.googlePlaceId,
        'spot_title': original.title,
        'spot_address': original.address,
        'municipality': package.city,
        'barangay': original.barangay,
        'latitude': original.latitude,
        'longitude': original.longitude,
        'image_url': original.imageUrl,
        'additional_fee': 0,
        'sort_order': null,
        'opening_time': original.openingTime.isEmpty
            ? null
            : original.openingTime,
        'closing_time': original.closingTime.isEmpty
            ? null
            : original.closingTime,
        'estimated_arrival_time': original.estimatedArrivalTime.isEmpty
            ? null
            : original.estimatedArrivalTime,
        'estimated_duration_minutes': original.estimatedDurationMinutes > 0
            ? original.estimatedDurationMinutes
            : null,
        'recommended_visit_duration_minutes':
            original.recommendedVisitDurationMinutes > 0
            ? original.recommendedVisitDurationMinutes
            : null,
      });
    }

    return rows;
  }

  // =============================================================================
  // SCHEDULE
  // =============================================================================

  void _disposeItineraries() {
    for (final item in _suggestedItinerary) {
      item.dispose();
    }

    for (final item in _customizedItinerary) {
      item.dispose();
    }

    _suggestedItinerary = const [];
    _customizedItinerary = const [];
  }

  void _rebuildScheduleFromSelectedSpots() {
    _disposeItineraries();

    var cursorMinutes = _pickupMinutes;

    final suggested = <_EditableItineraryStop>[];

    for (final spot in _selectedSpots) {
      final stayMinutes = resolveItineraryStayMinutes(
        estimatedMinutes: spot.estimatedDurationMinutes,
        recommendedMinutes: spot.recommendedVisitDurationMinutes,
      );

      const initialTravelMinutes = 20;
      final arrivalMinutes = cursorMinutes + initialTravelMinutes;
      final departureMinutes = arrivalMinutes + stayMinutes;
      final arrival = _storageTimeFromMinutes(arrivalMinutes);
      final departure = _storageTimeFromMinutes(departureMinutes);
      cursorMinutes = departureMinutes;

      suggested.add(
        _EditableItineraryStop(
          localKey: spot.key,
          spotId: spot.spotId,
          googlePlaceId: spot.googlePlaceId,
          destinationName: spot.title,
          destinationAddress: spot.address,
          municipality: spot.municipality,
          barangay: spot.barangay,
          latitude: spot.latitude,
          longitude: spot.longitude,
          imageUrl: spot.imageUrl,
          arrivalTime: arrival,
          stayMinutes: stayMinutes,
          departureTime: departure,
          travelDurationMinutes: initialTravelMinutes,
          routeDistanceMeters: 0,
        ),
      );
    }

    _suggestedItinerary = suggested;

    _customizedItinerary = suggested
        .map(_EditableItineraryStop.cloneFrom)
        .toList(growable: true);

    _spotSelectionDirtyForSchedule = false;
    _customizedItineraryDirty = false;
    unawaited(_recalculateSelectedItinerary());
  }

  int get _pickupMinutes {
    final time = _selectedPickupTime;
    return time == null ? _tourStartMinutes : time.hour * 60 + time.minute;
  }

  DateTime? get _scheduledPickupAt {
    final date = _selectedDate;
    final time = _selectedPickupTime;
    if (date == null || time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  DateTime? get _estimatedBookingEndAt {
    final date = _selectedDate;
    final itinerary = _selectedItinerary;
    if (date == null || itinerary.isEmpty) return null;
    final departure = _storageTimeToMinutes(itinerary.last.departureTime);
    if (departure == null) return null;
    final endMinutes = departure + _finalTravelDurationMinutes;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).add(Duration(minutes: endMinutes));
  }

  Future<void> _recalculateSelectedItinerary() async {
    final pickup = _selectedPickup;
    final itinerary = _selectedItinerary;
    if (pickup == null || itinerary.isEmpty) return;

    final revision = ++_scheduleRevision;
    if (mounted) setState(() => _scheduleLoading = true);

    final points = <LatLng>[
      LatLng(pickup.latitude, pickup.longitude),
      ...itinerary.map((item) => LatLng(item.latitude, item.longitude)),
      if (_selectedDropoff case final dropoff?)
        LatLng(dropoff.latitude, dropoff.longitude),
    ];
    final legs = await _scheduleService.fetchTravelLegs(points);
    if (!mounted || revision != _scheduleRevision) return;

    final inboundLegs = legs.take(itinerary.length).toList(growable: false);
    final timings = calculateItineraryTimings(
      pickupMinutes: _pickupMinutes,
      stayDurationMinutes: itinerary.map((item) => item.stayMinutes).toList(),
      travelDurationMinutes: List<int>.generate(
        itinerary.length,
        (i) => i < inboundLegs.length ? inboundLegs[i].durationMinutes : 20,
      ),
    );

    setState(() {
      for (var i = 0; i < itinerary.length; i++) {
        itinerary[i]
          ..arrivalTime = _storageTimeFromMinutes(timings[i].arrivalMinutes)
          ..departureTime = _storageTimeFromMinutes(timings[i].departureMinutes)
          ..travelDurationMinutes = timings[i].travelDurationMinutes
          ..routeDistanceMeters = i < inboundLegs.length
              ? inboundLegs[i].distanceMeters
              : 0;
      }
      _finalTravelDurationMinutes = legs.length > itinerary.length
          ? legs[itinerary.length].durationMinutes
          : 0;
      _scheduleLoading = false;
      _customizedItineraryDirty =
          _itineraryMode == _ItineraryViewMode.customize;
    });
  }

  List<_EditableItineraryStop> get _selectedItinerary {
    if (_itineraryMode == _ItineraryViewMode.customize) {
      return _customizedItinerary;
    }

    return _suggestedItinerary;
  }

  String get _selectedItineraryLabel {
    return _itineraryMode == _ItineraryViewMode.customize
        ? 'Customized Schedule'
        : 'Suggested Schedule';
  }

  int get _selectedItineraryDurationMinutes {
    return _calculateDurationMinutes(_selectedItinerary);
  }

  String? _itineraryValidationMessage() {
    final itinerary = _selectedItinerary;

    if (itinerary.length < _minimumSpots) {
      return 'Please keep at least $_minimumSpots destinations.';
    }

    if (itinerary.length > _maximumSpots) {
      return 'You can only include up to $_maximumSpots destinations.';
    }

    int? firstArrivalMinutes;
    int? previousDepartureMinutes;
    int? finalDepartureMinutes;

    for (final item in itinerary) {
      final arrivalMinutes = _storageTimeToMinutes(item.arrivalTime);

      final departureMinutes = _storageTimeToMinutes(item.departureTime);

      if (arrivalMinutes == null || departureMinutes == null) {
        return 'Please complete all itinerary times.';
      }

      if (item.stayMinutes <= 0) {
        return 'Please enter a valid estimated stay for ${item.destinationName}.';
      }

      if (departureMinutes <= arrivalMinutes) {
        return 'Departure must be after arrival for ${item.destinationName}.';
      }

      if (arrivalMinutes < _tourStartMinutes ||
          arrivalMinutes > _tourEndMinutes ||
          departureMinutes < _tourStartMinutes ||
          departureMinutes > _tourEndMinutes) {
        return _tourHoursErrorMessage;
      }

      if (previousDepartureMinutes != null &&
          arrivalMinutes < previousDepartureMinutes) {
        return 'Please keep your itinerary times in chronological order.';
      }

      firstArrivalMinutes ??= arrivalMinutes;
      previousDepartureMinutes = departureMinutes;
      finalDepartureMinutes = departureMinutes;
    }

    if (_selectedDate == null) {
      return 'Please select a travel date.';
    }

    if (_selectedPickupTime == null) {
      return 'Please select an exact pickup time.';
    }

    if (_pickupMinutes < _tourStartMinutes ||
        _pickupMinutes >= _tourEndMinutes) {
      return 'Pickup time must be between 7:00 AM and 4:59 PM.';
    }

    if (finalDepartureMinutes != null &&
        finalDepartureMinutes > _tourEndMinutes) {
      return _tourHoursErrorMessage;
    }

    if (_isSameDay) {
      final now = DateTime.now();

      final scheduled = _scheduledPickupAt;
      if (scheduled != null && scheduled.isBefore(now)) {
        return 'For same-day bookings, pickup time must be later than the current time.';
      }

      final currentMinutes = now.hour * 60 + now.minute;

      if (currentMinutes > _tourEndMinutes) {
        return 'Tours are no longer available today. Tours are only available from 7:00 AM to 5:00 PM.';
      }

      if (firstArrivalMinutes != null && firstArrivalMinutes < currentMinutes) {
        if (currentMinutes + _selectedItineraryDurationMinutes >
            _tourEndMinutes) {
          return _tourHoursErrorMessage;
        }

        return 'For same-day bookings, your tour must start no earlier than the current time.';
      }
    }

    return null;
  }

  int? _storageTimeToMinutes(String value) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})(?::\d{2})?$',
    ).firstMatch(value.trim());

    if (match == null) {
      return null;
    }

    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  void _moveCustomizedItineraryStop(int index, int delta) {
    final target = index + delta;

    if (target < 0 || target >= _customizedItinerary.length) {
      return;
    }

    setState(() {
      final item = _customizedItinerary.removeAt(index);

      _customizedItinerary.insert(target, item);

      _customizedItineraryDirty = true;
    });
    unawaited(_recalculateSelectedItinerary());
  }

  bool _commitCustomizedItinerary({bool showSnack = true}) {
    final error = _itineraryValidationMessage();

    if (error != null) {
      if (showSnack) {
        _snack(error);
      }

      return false;
    }

    setState(() {
      _customizedItineraryDirty = false;
    });

    return true;
  }

  List<Json> _buildFinalItineraryPayload() {
    return _selectedItinerary.indexed
        .map((entry) {
          return entry.$2.toBookingPayload(
            order: entry.$1 + 1,
            sourceType: _itineraryMode == _ItineraryViewMode.customize
                ? 'customized'
                : 'ai_suggested',
          );
        })
        .toList(growable: false);
  }

  // =============================================================================
  // DATE
  // =============================================================================

  String get _dateLabel {
    if (_selectedDate == null) {
      return 'Choose your travel date';
    }

    return DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate!);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final firstDate = DateTime(now.year, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? firstDate,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 2),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = picked;
      _payment = _PaymentMethod.gcash;
    });
    unawaited(_recalculateSelectedItinerary());
  }

  String get _pickupTimeLabel => _selectedPickupTime == null
      ? 'Choose exact pickup time'
      : _selectedPickupTime!.format(context);

  Future<void> _pickPickupTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedPickupTime ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked == null) return;
    setState(() => _selectedPickupTime = picked);
    await _recalculateSelectedItinerary();
  }

  // =============================================================================
  // VALIDATION
  // =============================================================================

  String? _passengerValidationMessage() {
    if (_adults < 1) {
      return 'Please include at least 1 adult passenger.';
    }

    if (_totalParticipants <= 0) {
      return 'Please include at least 1 passenger.';
    }

    return null;
  }

  String? _stepValidationMessage(int step, TourPackage package) {
    switch (step) {
      case 0:
        if (_selectedDate == null) {
          return 'Please select your travel date first.';
        }
        if (_selectedPickupTime == null) {
          return 'Please select your pickup time.';
        }

        return _passengerValidationMessage();

      case 1:
        return _locationBlockingMessage(package);

      case 2:
        return _spotValidationMessage();

      case 3:
        if (_itineraryMode == _ItineraryViewMode.customize &&
            !_commitCustomizedItinerary(showSnack: false)) {
          return _itineraryValidationMessage();
        }

        return _itineraryValidationMessage();

      case 4:
        return null;

      default:
        return null;
    }
  }

  String? _confirmationBlockingMessage(TourPackage package) {
    return _passengerValidationMessage() ??
        _locationBlockingMessage(package) ??
        _spotValidationMessage() ??
        _itineraryValidationMessage();
  }

  // =============================================================================
  // STEPS
  // =============================================================================

  Future<void> _nextStep(TourPackage package) async {
    final error = _stepValidationMessage(_currentStep, package);

    if (error != null) {
      _snack(error);
      return;
    }

    // Leaving Choose Spots.
    if (_currentStep == 2 && _spotSelectionDirtyForSchedule) {
      setState(() {
        _rebuildScheduleFromSelectedSpots();
      });
    }

    if (_currentStep == 1 || _currentStep == 2) {
      await _recalculateSelectedItinerary();
    }

    if (_currentStep >= 5) {
      return;
    }

    final next = _currentStep + 1;

    setState(() {
      _currentStep = next;
    });

    await _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 270),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _previousStep() async {
    if (_currentStep <= 0) {
      Navigator.pop(context);
      return;
    }

    final previous = _currentStep - 1;

    setState(() {
      _currentStep = previous;
    });

    await _pageController.animateToPage(
      previous,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goToStep(int step) async {
    if (step < 0 || step > 5) {
      return;
    }

    if (step > _currentStep) {
      return;
    }

    setState(() {
      _currentStep = step;
    });

    await _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  // =============================================================================
  // NOTES
  // =============================================================================

  String _buildNotesSummary() {
    final parts = <String>[];

    final notes = _notesCtrl.text.trim();

    if (notes.isNotEmpty) {
      parts.add(notes);
    }

    parts.add(
      'Booking type: ${_isSameDay ? 'Same-day Booking' : 'Advanced Booking (50% DP)'}',
    );

    parts.add(
      'Participants — Adults: $_adults, Children: $_children. '
      'Required tricycles: $_requiredTricycles.',
    );

    parts.add(
      'Selected destinations: ${_selectedSpots.map((spot) => spot.title).join(', ')}',
    );

    final removed = _removedOriginalSpots;

    if (removed.isNotEmpty) {
      parts.add(
        'Removed package destinations: ${removed.map((spot) => spot.title).join(', ')}',
      );
    }

    if (_addedGoogleSpotCount > 0) {
      parts.add(
        'Added Google Places destinations: ${_selectedSpots.where((spot) => !spot.isOriginal).map((spot) => spot.title).join(', ')}',
      );
    }

    parts.add('Final itinerary source: $_selectedItineraryLabel');

    parts.add(
      'Estimated tour duration: ${_formatDurationLabel(_selectedItineraryDurationMinutes)}',
    );

    return parts.join('\n');
  }

  // =============================================================================
  // CONFIRM
  // =============================================================================

  Future<void> _confirm(TourPackage package) async {
    try {
      final active = await _repo.hasActiveTour();

      if (active) {
        _snack(TourisTrikeRepository.activeTourErrorMessage);
        return;
      }
    } catch (_) {
      _snack(
        'Unable to verify your current tour status right now. Please try again.',
      );
      return;
    }

    final blocking = _confirmationBlockingMessage(package);

    if (blocking != null) {
      _snack(blocking);
      return;
    }

    if (_spotSelectionDirtyForSchedule) {
      setState(() {
        _rebuildScheduleFromSelectedSpots();
      });
    }

    if (_itineraryMode == _ItineraryViewMode.customize &&
        !_commitCustomizedItinerary()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _recalculateSelectedItinerary();
      if (!mounted) return;

      final recalculatedError = _itineraryValidationMessage();
      if (recalculatedError != null) {
        _snack(recalculatedError);
        return;
      }

      final itinerary = _buildFinalItineraryPayload();
      if (itinerary.isEmpty) {
        _snack('Unable to prepare the itinerary for this booking.');
        return;
      }

      final total = _totalPrice(package);

      final downpayment = _downpaymentAmount(package);

      final remaining = _remainingBalance(package);

      const method = 'gcash';

      final booking = await _repo.createPackageBooking(
        packageId: package.id,
        travelDate: _selectedDate!,
        scheduledStartAt: _scheduledPickupAt!,
        estimatedEndAt: _estimatedBookingEndAt!,
        adults: _adults,
        children: _children,
        paymentMethod: method,
        totalAmount: total,
        downpaymentAmount: downpayment,
        remainingBalance: remaining,
        bookingType: _bookingType,

        pickupAddress: _selectedPickup!.address,
        pickupLatitude: _selectedPickup!.latitude,
        pickupLongitude: _selectedPickup!.longitude,
        pickupProvince: _packageProvince(package),
        pickupLocality: package.city,
        pickupCountryCode: 'PH',

        dropoffAddress: _selectedDropoff!.address,
        dropoffLatitude: _selectedDropoff!.latitude,
        dropoffLongitude: _selectedDropoff!.longitude,
        dropoffProvince: _packageProvince(package),
        dropoffLocality: package.city,
        dropoffCountryCode: 'PH',

        notes: _buildNotesSummary(),

        customizedSpots: _buildCustomizationRows(package),

        itineraryItems: itinerary,

        requiredDrivers: _requiredTricycles,

        municipality: package.city,
        province: _packageProvince(package),

        totalPassengers: _totalParticipants,
      );

      if (!mounted) {
        return;
      }

      _navigateToActivityTracking(booking.id.toString());
    } catch (error) {
      if (!mounted) {
        return;
      }

      _snack('Unable to create booking: $error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _navigateToActivityTracking(String bookingId) {
    final navigator = Navigator.of(context);

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ActivityScreen()),
      (route) => false,
    );

    navigator.push(
      MaterialPageRoute(
        builder: (_) => ActivityTrackingScreen(bookingId: bookingId),
      ),
    );
  }

  void _snack(String message, {bool error = true}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: error
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  // =============================================================================
  // BUILD
  // =============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: FutureBuilder<_BookingScreenData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _BookingLoadingView();
          }

          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _future = _loadPackage();
                });
              },
            );
          }

          final data = snapshot.data!;
          final package = data.package;

          _initializeSpotSelection(data);

          final total = _totalPrice(package);

          final amountNow = _amountToPayNow(package);

          final remaining = _remainingBalance(package);

          return SafeArea(
            bottom: false,
            child: Column(
              children: [
                _BookingTopBar(
                  currentStep: _currentStep,
                  totalSteps: 6,
                  onBack: _previousStep,
                ),

                _BookingStepIndicator(
                  currentStep: _currentStep,
                  onTap: _goToStep,
                ),

                const SizedBox(height: 6),

                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      // ======================================================
                      // STEP 1 - TRIP DETAILS
                      // ======================================================
                      _StepScrollView(
                        children: [
                          const _StepIntro(
                            icon: Icons.calendar_month_outlined,
                            step: 'Step 1 of 6',
                            title: 'Trip Details',
                            description:
                                'Choose your travel date and tell us who is joining the tour.',
                          ),

                          const SizedBox(height: 18),

                          _PackageSummary(
                            package: package,
                            unitPrice: _unitPrice(package),
                          ),

                          const SizedBox(height: 20),

                          const _StepSectionTitle(
                            title: 'Travel Date',
                            subtitle: 'When would you like to take this tour?',
                          ),

                          const SizedBox(height: 10),

                          _DateSelectionCard(
                            selectedDate: _selectedDate,
                            isSameDay: _isSameDay,
                            dateLabel: _dateLabel,
                            onTap: _pickDate,
                          ),

                          const SizedBox(height: 10),

                          _PickupTimeSelectionCard(
                            selected: _selectedPickupTime != null,
                            value: _pickupTimeLabel,
                            onTap: _pickPickupTime,
                          ),

                          const SizedBox(height: 22),

                          const _StepSectionTitle(
                            title: 'Participants',
                            subtitle:
                                'Add the number of people joining the booking.',
                          ),

                          const SizedBox(height: 10),

                          _ParticipantsCard(
                            adults: _adults,
                            children: _children,
                            onAdultsMinus: _adults <= 1
                                ? null
                                : () {
                                    setState(() {
                                      _adults--;
                                      _keepSelectedTricyclesAboveMinimum();
                                    });
                                  },
                            onAdultsPlus: () {
                              setState(() {
                                _adults++;
                                _keepSelectedTricyclesAboveMinimum();
                              });
                            },
                            onChildrenMinus: _children <= 0
                                ? null
                                : () {
                                    setState(() {
                                      _children--;
                                      _keepSelectedTricyclesAboveMinimum();
                                    });
                                  },
                            onChildrenPlus: () {
                              setState(() {
                                _children++;
                                _keepSelectedTricyclesAboveMinimum();
                              });
                            },
                          ),

                          const SizedBox(height: 12),

                          _TransportRequirementCard(
                            participants: _totalParticipants,
                            minimumTricycles: _minimumRequiredTricycles,
                            selectedTricycles: _requiredTricycles,
                            onMinus:
                                _requiredTricycles <= _minimumRequiredTricycles
                                ? null
                                : () => setState(() => _selectedTricycles--),
                            onPlus: () => setState(() => _selectedTricycles++),
                          ),
                        ],
                      ),

                      // ======================================================
                      // STEP 2 - PICKUP / DROP-OFF
                      // ======================================================
                      _StepScrollView(
                        children: [
                          const _StepIntro(
                            icon: Icons.route_outlined,
                            step: 'Step 2 of 6',
                            title: 'Pickup & Drop-off',
                            description:
                                'Set where your assigned driver should meet you and where the tour should end.',
                          ),

                          const SizedBox(height: 18),

                          _LocationStepCard(
                            number: '1',
                            icon: Icons.trip_origin_rounded,
                            iconColor: const Color(0xFF16A34A),
                            title: 'Pickup Point',
                            subtitle: 'Where should the driver meet you?',
                            child: _LocationPickerCard(
                              label: 'Pickup',
                              requiredMunicipality: package.city,
                              requiredProvince: _packageProvince(package),
                              errorText: _pickupLocationError,
                              onValidationMessageChanged: (message) {
                                if (!mounted) return;

                                setState(() {
                                  _pickupLocationError = message;
                                });
                              },
                              onLocationSelected: _onPickupSelected,
                            ),
                          ),

                          const SizedBox(height: 14),

                          _LocationStepCard(
                            number: '2',
                            icon: Icons.location_on_rounded,
                            iconColor: const Color(0xFFDC2626),
                            title: 'Drop-off Point',
                            subtitle: 'Where should the tour end?',
                            child: _LocationPickerCard(
                              label: 'Drop-off',
                              requiredMunicipality: package.city,
                              requiredProvince: _packageProvince(package),
                              errorText: _dropoffLocationError,
                              onValidationMessageChanged: (message) {
                                if (!mounted) return;

                                setState(() {
                                  _dropoffLocationError = message;
                                });
                              },
                              onLocationSelected: _onDropoffSelected,
                            ),
                          ),

                          const SizedBox(height: 20),

                          const _StepSectionTitle(
                            title: 'Route Preview',
                            subtitle:
                                'Your selected pickup and drop-off points.',
                          ),

                          const SizedBox(height: 10),

                          _SharedRouteMapPreview(
                            pickupAddress: _selectedPickup?.address,
                            pickupLat: _selectedPickup?.latitude,
                            pickupLng: _selectedPickup?.longitude,
                            dropoffAddress: _selectedDropoff?.address,
                            dropoffLat: _selectedDropoff?.latitude,
                            dropoffLng: _selectedDropoff?.longitude,
                          ),
                        ],
                      ),

                      // ======================================================
                      // STEP 3 - CHOOSE SPOTS
                      // ======================================================
                      _StepScrollView(
                        children: [
                          const _StepIntro(
                            icon: Icons.place_outlined,
                            step: 'Step 3 of 6',
                            title: 'Choose Your Stops',
                            description:
                                'Keep the included package destinations or personalize the trip using nearby Google Places suggestions.',
                          ),

                          const SizedBox(height: 18),

                          _SelectedSpotSummaryCard(
                            selectedCount: _selectedSpots.length,
                            addedCount: _addedGoogleSpotCount,
                            removedCount: _removedOriginalSpots.length,
                            unitPrice: _unitPrice(package),
                            basePrice: package.numericPrice,
                          ),

                          const SizedBox(height: 20),

                          _StepSectionTitle(
                            title: 'Selected Destinations',
                            subtitle:
                                '${_selectedSpots.length} of $_maximumSpots destinations selected. Minimum $_minimumSpots required.',
                          ),

                          const SizedBox(height: 10),

                          ..._selectedSpots.asMap().entries.map(
                            (entry) => _SelectedBookingSpotCard(
                              index: entry.key,
                              spot: entry.value,
                              total: _selectedSpots.length,
                              onMoveUp: entry.key == 0
                                  ? null
                                  : () => _moveSelectedSpot(entry.key, -1),
                              onMoveDown: entry.key == _selectedSpots.length - 1
                                  ? null
                                  : () => _moveSelectedSpot(entry.key, 1),
                              onRemove: () => _removeSelectedSpot(entry.value),
                            ),
                          ),

                          if (_removedOriginalSpots.isNotEmpty) ...[
                            const SizedBox(height: 20),

                            const _StepSectionTitle(
                              title: 'Removed Package Spots',
                              subtitle:
                                  'You can restore any original destination.',
                            ),

                            const SizedBox(height: 10),

                            ..._removedOriginalSpots.map(
                              (spot) => _RemovedOriginalSpotCard(
                                spot: spot,
                                onRestore: () => _restoreOriginalSpot(spot),
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),

                          const _StepSectionTitle(
                            title: 'Explore Nearby Places',
                            subtitle:
                                'Add Google Places suggestions from the same municipality.',
                          ),

                          const SizedBox(height: 10),

                          _SpotCategoryFilter(
                            selected: _spotCategory,
                            onSelected: (value) {
                              setState(() {
                                _spotCategory = value;
                              });
                            },
                          ),

                          const SizedBox(height: 12),

                          if (_filteredGoogleSuggestions.isEmpty)
                            const _SimpleEmptyCard(
                              icon: Icons.travel_explore_outlined,
                              title: 'No more suggestions',
                              subtitle:
                                  'Try another category or continue with your selected destinations.',
                            )
                          else
                            ..._filteredGoogleSuggestions.map(
                              (spot) => _GoogleSuggestionCard(
                                spot: spot,
                                additionalFee: _additionalSpotFee,
                                onAdd: () => _addGoogleSuggestion(spot),
                              ),
                            ),

                          const SizedBox(height: 14),

                          const _SpotFeeNotice(),
                        ],
                      ),

                      // ======================================================
                      // STEP 4 - SCHEDULE
                      // ======================================================
                      _StepScrollView(
                        children: [
                          const _StepIntro(
                            icon: Icons.schedule_outlined,
                            step: 'Step 4 of 6',
                            title: 'Plan Your Itinerary',
                            description:
                                'Your destinations are already selected. Now choose a suggested schedule or customize their order and timing.',
                          ),

                          const SizedBox(height: 18),

                          _FinalSpotStrip(spots: _selectedSpots),

                          const SizedBox(height: 18),

                          _ItineraryModeToggle(
                            selected: _itineraryMode,
                            onChanged: (mode) {
                              setState(() {
                                _itineraryMode = mode;
                              });
                            },
                          ),

                          const SizedBox(height: 12),

                          if (_itineraryMode == _ItineraryViewMode.suggested)
                            _ReadOnlyItineraryCard(
                              items: _suggestedItinerary,
                              totalDurationLabel: _formatDurationLabel(
                                _calculateDurationMinutes(_suggestedItinerary),
                              ),
                            )
                          else
                            _EditableItineraryCard(
                              items: _customizedItinerary,
                              currentDurationLabel: _formatDurationLabel(
                                _calculateDurationMinutes(_customizedItinerary),
                              ),
                              hasUnsavedChanges: _customizedItineraryDirty,
                              onStayChanged: (item, minutes) {
                                setState(() {
                                  item.stayMinutes = minutes;
                                  _customizedItineraryDirty = true;
                                });
                                unawaited(_recalculateSelectedItinerary());
                              },
                              onMoveUp: (index) =>
                                  _moveCustomizedItineraryStop(index, -1),
                              onMoveDown: (index) =>
                                  _moveCustomizedItineraryStop(index, 1),
                            ),

                          if (_scheduleLoading) ...[
                            const SizedBox(height: 10),
                            const LinearProgressIndicator(minHeight: 2),
                          ],

                          const SizedBox(height: 12),

                          _ItineraryGuideCard(
                            duration: _formatDurationLabel(
                              _selectedItineraryDurationMinutes,
                            ),
                            stops: _selectedItinerary.length,
                          ),
                        ],
                      ),

                      // ======================================================
                      // STEP 5 - PAYMENT
                      // ======================================================
                      _StepScrollView(
                        children: [
                          const _StepIntro(
                            icon: Icons.payments_outlined,
                            step: 'Step 5 of 6',
                            title: 'Payment',
                            description:
                                'Review the price and choose how you will pay the assigned driver.',
                          ),

                          const SizedBox(height: 18),

                          _PaymentAmountHero(
                            total: total,
                            amountNow: amountNow,
                            remaining: remaining,
                          ),

                          const SizedBox(height: 20),

                          _PricingBreakdownCard(
                            baseUnitPrice: package.numericPrice,
                            addedSpotCount: _addedGoogleSpotCount,
                            addedSpotFee: _additionalSpotFee,
                            finalUnitPrice: _unitPrice(package),
                            passengers: _totalParticipants,
                          ),

                          const SizedBox(height: 22),

                          const _StepSectionTitle(
                            title: 'Payment Method',
                            subtitle:
                                'Payments go directly to your assigned driver.',
                          ),

                          const SizedBox(height: 10),

                          _PaymentCard(
                            selected: _payment == _PaymentMethod.gcash,
                            enabled: _selectedDate != null,
                            icon: Icons.qr_code_2_rounded,
                            title: 'GCash',
                            subtitle: _selectedDate == null
                                ? 'Choose your travel date first.'
                                : 'Pay the 50% down payment after the driver roster is filled, then pay the remaining balance after the tour.',
                            onTap: () {
                              if (_selectedDate != null) {
                                setState(() {
                                  _payment = _PaymentMethod.gcash;
                                });
                              }
                            },
                          ),

                          const SizedBox(height: 14),

                          const _DirectPaymentNotice(),

                          const SizedBox(height: 22),

                          const _StepSectionTitle(
                            title: 'Special Requests',
                            subtitle:
                                'Optional notes for the tourism office or assigned driver.',
                          ),

                          const SizedBox(height: 10),

                          _NotesField(controller: _notesCtrl),
                        ],
                      ),

                      // ======================================================
                      // STEP 6 - REVIEW
                      // ======================================================
                      _StepScrollView(
                        children: [
                          const _StepIntro(
                            icon: Icons.task_alt_rounded,
                            step: 'Step 6 of 6',
                            title: 'Review Booking',
                            description:
                                'Check all details before sending your booking request.',
                          ),

                          const SizedBox(height: 18),

                          _ReviewPackageCard(package: package),

                          const SizedBox(height: 12),

                          _ReviewSection(
                            icon: Icons.calendar_month_outlined,
                            title: 'Trip Details',
                            onEdit: () => _goToStep(0),
                            children: [
                              _ReviewRow(
                                label: 'Travel Date',
                                value: _selectedDate == null
                                    ? 'Not selected'
                                    : DateFormat(
                                        'MMM d, yyyy',
                                      ).format(_selectedDate!),
                              ),
                              _ReviewRow(
                                label: 'Pickup Time',
                                value: _pickupTimeLabel,
                              ),
                              _ReviewRow(
                                label: 'Booking Type',
                                value: _isSameDay ? 'Same-day' : 'Advanced',
                              ),
                              _ReviewRow(
                                label: 'Participants',
                                value: '$_totalParticipants',
                              ),
                              _ReviewRow(
                                label: 'Tricycles',
                                value: '$_requiredTricycles',
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          _ReviewSection(
                            icon: Icons.route_outlined,
                            title: 'Pickup & Drop-off',
                            onEdit: () => _goToStep(1),
                            children: [
                              _ReviewAddressRow(
                                label: 'Pickup',
                                value:
                                    _selectedPickup?.address ?? 'Not selected',
                                color: const Color(0xFF16A34A),
                              ),

                              const SizedBox(height: 10),

                              _ReviewAddressRow(
                                label: 'Drop-off',
                                value:
                                    _selectedDropoff?.address ?? 'Not selected',
                                color: const Color(0xFFDC2626),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          _ReviewSection(
                            icon: Icons.place_outlined,
                            title: 'Destinations',
                            onEdit: () => _goToStep(2),
                            children: [
                              _ReviewRow(
                                label: 'Selected',
                                value: '${_selectedSpots.length}',
                              ),
                              _ReviewRow(
                                label: 'Original Kept',
                                value:
                                    '${_selectedSpots.where((spot) => spot.isOriginal).length}',
                              ),
                              _ReviewRow(
                                label: 'Google Added',
                                value: '$_addedGoogleSpotCount',
                              ),

                              const SizedBox(height: 8),

                              ..._selectedSpots.asMap().entries.map(
                                (entry) => _ReviewDestinationRow(
                                  index: entry.key + 1,
                                  name: entry.value.title,
                                  added: !entry.value.isOriginal,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          _ReviewSection(
                            icon: Icons.schedule_outlined,
                            title: 'Schedule',
                            onEdit: () => _goToStep(3),
                            children: [
                              _ReviewRow(
                                label: 'Schedule Type',
                                value: _selectedItineraryLabel,
                              ),
                              _ReviewRow(
                                label: 'Duration',
                                value: _formatDurationLabel(
                                  _selectedItineraryDurationMinutes,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          _ReviewSection(
                            icon: Icons.payments_outlined,
                            title: 'Payment',
                            onEdit: () => _goToStep(4),
                            children: [
                              _ReviewRow(label: 'Method', value: 'GCash'),
                              _ReviewRow(
                                label: 'Unit Price',
                                value: _money(_unitPrice(package)),
                              ),
                              _ReviewRow(label: 'Total', value: _money(total)),
                              _ReviewRow(
                                label: 'Pay Now',
                                value: _money(amountNow),
                                emphasized: true,
                              ),
                              _ReviewRow(
                                label: 'Remaining',
                                value: _money(remaining),
                              ),
                            ],
                          ),

                          if (_notesCtrl.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),

                            _ReviewSection(
                              icon: Icons.notes_outlined,
                              title: 'Special Request',
                              onEdit: () => _goToStep(4),
                              children: [
                                Text(
                                  _notesCtrl.text.trim(),
                                  style: const TextStyle(
                                    color: _secondaryText,
                                    fontSize: 11.5,
                                    height: 1.45,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 14),

                          const _FinalAgreementNotice(),
                        ],
                      ),
                    ],
                  ),
                ),

                _BookingNavigationBar(
                  currentStep: _currentStep,
                  totalSteps: 6,
                  saving: _saving,
                  onBack: _previousStep,
                  onNext: () => _nextStep(package),
                  onConfirm: () => _confirm(package),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _money(double amount) {
    return NumberFormat.currency(
      symbol: 'PHP ',
      decimalDigits: 0,
    ).format(amount);
  }
}

// =============================================================================
// ENUMS / DATA
// =============================================================================

enum _PaymentMethod { gcash }

enum _ItineraryViewMode { suggested, customize }

class _BookingScreenData {
  const _BookingScreenData({
    required this.package,
    required this.packageSpots,
    required this.googleSuggestions,
  });

  final TourPackage package;
  final List<TouristSpot> packageSpots;
  final List<CitySpotSuggestion> googleSuggestions;
}

// =============================================================================
// EDITABLE BOOKING SPOT
// =============================================================================

class _EditableBookingSpot {
  const _EditableBookingSpot({
    required this.key,
    required this.spotId,
    required this.title,
    required this.address,
    required this.barangay,
    required this.municipality,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.sourceType,
    required this.googlePlaceId,
    required this.isOriginal,
    required this.category,
    required this.openingTime,
    required this.closingTime,
    required this.estimatedArrivalTime,
    required this.estimatedDurationMinutes,
    required this.recommendedVisitDurationMinutes,
  });

  final String key;

  final dynamic spotId;

  final String title;
  final String address;
  final String barangay;
  final String municipality;

  final String imageUrl;

  final double latitude;
  final double longitude;

  final String sourceType;
  final String googlePlaceId;

  final bool isOriginal;

  final String category;

  final String openingTime;
  final String closingTime;

  final String estimatedArrivalTime;
  final int estimatedDurationMinutes;
  final int recommendedVisitDurationMinutes;

  factory _EditableBookingSpot.fromTouristSpot(
    TouristSpot spot, {
    required bool isOriginal,
  }) {
    final googlePlaceId = spot.googlePlaceId;

    final key = googlePlaceId.isNotEmpty
        ? 'google:$googlePlaceId'
        : spot.id != null
        ? 'db:${spot.id}'
        : 'title:${_normalizeText(spot.title)}';

    return _EditableBookingSpot(
      key: key,
      spotId: spot.id,
      title: spot.title,
      address: spot.address,
      barangay: spot.barangay,
      municipality: spot.municipality,
      imageUrl: spot.imageUrl,
      latitude: spot.latitude,
      longitude: spot.longitude,
      sourceType: spot.sourceType.isEmpty ? 'manual' : spot.sourceType,
      googlePlaceId: googlePlaceId,
      isOriginal: isOriginal,
      category: _inferCategoryFromTitle(spot.title),
      openingTime: spot.openingTime,
      closingTime: spot.closingTime,
      estimatedArrivalTime: spot.estimatedArrivalTime,
      estimatedDurationMinutes: spot.estimatedDurationMinutes,
      recommendedVisitDurationMinutes: spot.recommendedVisitDurationMinutes,
    );
  }

  factory _EditableBookingSpot.fromSuggestion(CitySpotSuggestion suggestion) {
    return _EditableBookingSpot(
      key: 'google:${suggestion.id}',
      spotId: null,
      title: suggestion.title,
      address: suggestion.address,
      barangay: suggestion.barangayHint,
      municipality: suggestion.city,
      imageUrl: suggestion.imageForCard,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude,
      sourceType: 'google_places',
      googlePlaceId: suggestion.id,
      isOriginal: false,
      category: suggestion.category,
      openingTime: '',
      closingTime: '',
      estimatedArrivalTime: '',
      estimatedDurationMinutes: 0,
      recommendedVisitDurationMinutes: 0,
    );
  }

  factory _EditableBookingSpot.fromCustomizationRow(Map<String, dynamic> row) {
    final googlePlaceId = dbString(row['google_place_id']);

    final spotId = row['spot_id'];

    final title = dbString(row['spot_title']);

    final sourceType = dbString(row['source_type'], fallback: 'manual');

    final added = row['action_type'] == 'added';

    return _EditableBookingSpot(
      key: googlePlaceId.isNotEmpty
          ? 'google:$googlePlaceId'
          : spotId != null
          ? 'db:$spotId'
          : 'title:${_normalizeText(title)}',
      spotId: spotId,
      title: title,
      address: dbString(row['spot_address']),
      barangay: dbString(row['barangay']),
      municipality: dbString(row['municipality']),
      imageUrl: dbString(row['image_url']),
      latitude: dbDouble(row['latitude']),
      longitude: dbDouble(row['longitude']),
      sourceType: sourceType,
      googlePlaceId: googlePlaceId,
      isOriginal: !added,
      category: _inferCategoryFromTitle(title),
      openingTime: dbTimeText(row['opening_time']),
      closingTime: dbTimeText(row['closing_time']),
      estimatedArrivalTime: dbTimeText(row['estimated_arrival_time']),
      estimatedDurationMinutes: dbInt(row['estimated_duration_minutes']),
      recommendedVisitDurationMinutes: dbInt(
        row['recommended_visit_duration_minutes'],
      ),
    );
  }

  factory _EditableBookingSpot.copy(_EditableBookingSpot other) {
    return _EditableBookingSpot(
      key: other.key,
      spotId: other.spotId,
      title: other.title,
      address: other.address,
      barangay: other.barangay,
      municipality: other.municipality,
      imageUrl: other.imageUrl,
      latitude: other.latitude,
      longitude: other.longitude,
      sourceType: other.sourceType,
      googlePlaceId: other.googlePlaceId,
      isOriginal: other.isOriginal,
      category: other.category,
      openingTime: other.openingTime,
      closingTime: other.closingTime,
      estimatedArrivalTime: other.estimatedArrivalTime,
      estimatedDurationMinutes: other.estimatedDurationMinutes,
      recommendedVisitDurationMinutes: other.recommendedVisitDurationMinutes,
    );
  }
}

// =============================================================================
// TOP BAR
// =============================================================================

class _BookingTopBar extends StatelessWidget {
  const _BookingTopBar({
    required this.currentStep,
    required this.totalSteps,
    required this.onBack,
  });

  final int currentStep;
  final int totalSteps;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 9, 18, 7),
      child: Row(
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(13),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: _border),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Color(0xFF344054),
                  size: 16,
                ),
              ),
            ),
          ),

          const SizedBox(width: 11),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Book Tour Package',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),

                SizedBox(height: 2),

                Text(
                  'Personalize and confirm your tour',
                  style: TextStyle(
                    color: Color(0xFF8492A6),
                    fontSize: 10.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: _softBlue,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${currentStep + 1}/$totalSteps',
              style: const TextStyle(
                color: _primary,
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// STEP INDICATOR
// =============================================================================

class _BookingStepIndicator extends StatelessWidget {
  const _BookingStepIndicator({required this.currentStep, required this.onTap});

  final int currentStep;
  final ValueChanged<int> onTap;

  static const _steps = [
    (Icons.tune_rounded, 'Details'),
    (Icons.route_outlined, 'Route'),
    (Icons.place_outlined, 'Stops'),
    (Icons.schedule_outlined, 'Plan'),
    (Icons.payments_outlined, 'Pay'),
    (Icons.task_alt_outlined, 'Review'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: List.generate(_steps.length, (index) {
            final active = index == currentStep;
            final complete = index < currentStep;

            return Expanded(
              child: InkWell(
                onTap: index <= currentStep ? () => onTap(index) : null,
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 170),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: active
                            ? _primary
                            : complete
                            ? _softBlue
                            : const Color(0xFFF3F5F8),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        complete ? Icons.check_rounded : _steps[index].$1,
                        color: active
                            ? Colors.white
                            : complete
                            ? _primary
                            : const Color(0xFFA6B0BE),
                        size: 14,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      _steps[index].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? _primary : const Color(0xFF667085),
                        fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                        fontSize: 8.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// =============================================================================
// STEP LAYOUT
// =============================================================================

class _StepScrollView extends StatelessWidget {
  const _StepScrollView({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _StepIntro extends StatelessWidget {
  const _StepIntro({
    required this.icon,
    required this.step,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String step;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _softBlue,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: _primary, size: 21),
        ),

        const SizedBox(width: 11),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.toUpperCase(),
                style: const TextStyle(
                  color: _primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 9,
                  letterSpacing: 0.65,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 21,
                  letterSpacing: -0.45,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                description,
                style: const TextStyle(
                  color: _secondaryText,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepSectionTitle extends StatelessWidget {
  const _StepSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),

        const SizedBox(height: 3),

        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF8593A6),
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// PACKAGE SUMMARY
// =============================================================================

class _PackageSummary extends StatelessWidget {
  const _PackageSummary({required this.package, required this.unitPrice});

  final TourPackage package;
  final double unitPrice;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 70,
              height: 70,
              child: package.displayImageUrl.isEmpty
                  ? const _ImageFallback()
                  : Image.network(
                      package.displayImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _ImageFallback(),
                    ),
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _MiniChip(text: 'TOUR PACKAGE'),

                const SizedBox(height: 6),

                Text(
                  package.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    height: 1.15,
                  ),
                ),

                const SizedBox(height: 6),

                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: _primary,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        package.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF718096),
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 5),

                Text(
                  '${money.format(unitPrice)} / person',
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
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

// =============================================================================
// DATE
// =============================================================================

class _DateSelectionCard extends StatelessWidget {
  const _DateSelectionCard({
    required this.selectedDate,
    required this.isSameDay,
    required this.dateLabel,
    required this.onTap,
  });

  final DateTime? selectedDate;
  final bool isSameDay;
  final String dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = selectedDate != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? const Color(0xFFBBD7FF) : _border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.calendar_today_outlined,
                  color: _primary,
                  size: 19,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected ? 'Travel Date' : 'Select Travel Date',
                      style: const TextStyle(
                        color: Color(0xFF8491A3),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      dateLabel,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),

                    if (selected) ...[
                      const SizedBox(height: 4),

                      Text(
                        isSameDay ? 'Same-day booking' : 'Advanced booking',
                        style: TextStyle(
                          color: isSameDay ? const Color(0xFF16A34A) : _primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA6B6)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickupTimeSelectionCard extends StatelessWidget {
  const _PickupTimeSelectionCard({
    required this.selected,
    required this.value,
    required this.onTap,
  });

  final bool selected;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? const Color(0xFFBBD7FF) : _border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: _primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pickup Time',
                      style: TextStyle(
                        color: Color(0xFF8491A3),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA6B6)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PARTICIPANTS
// =============================================================================

class _ParticipantsCard extends StatelessWidget {
  const _ParticipantsCard({
    required this.adults,
    required this.children,
    required this.onAdultsMinus,
    required this.onAdultsPlus,
    required this.onChildrenMinus,
    required this.onChildrenPlus,
  });

  final int adults;
  final int children;

  final VoidCallback? onAdultsMinus;
  final VoidCallback onAdultsPlus;

  final VoidCallback? onChildrenMinus;
  final VoidCallback onChildrenPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          _CounterRow(
            icon: Icons.person_outline_rounded,
            label: 'Adults',
            sublabel: 'Age 13 and above',
            value: adults,
            onMinus: onAdultsMinus,
            onPlus: onAdultsPlus,
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 13),
            child: Divider(height: 1, color: Color(0xFFEDF1F6)),
          ),

          _CounterRow(
            icon: Icons.child_care_outlined,
            label: 'Children',
            sublabel: 'Age 12 and below',
            value: children,
            onMinus: onChildrenMinus,
            onPlus: onChildrenPlus,
          ),
        ],
      ),
    );
  }
}

class _CounterRow extends StatelessWidget {
  const _CounterRow({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final int value;

  final VoidCallback? onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: _softBlue,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _primary, size: 18),
        ),

        const SizedBox(width: 11),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                sublabel,
                style: const TextStyle(
                  color: Color(0xFF8A98AB),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        _RoundButton(icon: Icons.remove_rounded, onTap: onMinus),

        SizedBox(
          width: 42,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),

        _RoundButton(icon: Icons.add_rounded, onTap: onPlus, filled: true),
      ],
    );
  }
}

class _TransportRequirementCard extends StatelessWidget {
  const _TransportRequirementCard({
    required this.participants,
    required this.minimumTricycles,
    required this.selectedTricycles,
    required this.onMinus,
    required this.onPlus,
  });

  final int participants;
  final int minimumTricycles;
  final int selectedTricycles;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.commute_outlined, color: _primary, size: 18),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              '$participants passenger${participants == 1 ? '' : 's'} • '
              'minimum $minimumTricycles tricycle${minimumTricycles == 1 ? '' : 's'} | selected $selectedTricycles',
              style: const TextStyle(
                color: Color(0xFF4D6686),
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
              ),
            ),
          ),
          _RoundButton(icon: Icons.remove_rounded, onTap: onMinus),
          SizedBox(
            width: 38,
            child: Text(
              '$selectedTricycles',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          _RoundButton(icon: Icons.add_rounded, onTap: onPlus, filled: true),
        ],
      ),
    );
  }
}

// =============================================================================
// SPOT SELECTION
// =============================================================================

class _SelectedSpotSummaryCard extends StatelessWidget {
  const _SelectedSpotSummaryCard({
    required this.selectedCount,
    required this.addedCount,
    required this.removedCount,
    required this.unitPrice,
    required this.basePrice,
  });

  final int selectedCount;
  final int addedCount;
  final int removedCount;

  final double unitPrice;
  final double basePrice;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF3FAAF8)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'YOUR CUSTOMIZED TOUR',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            money.format(unitPrice),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),

          Text(
            'per person',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w600,
              fontSize: 9.5,
            ),
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _WhiteMetric(
                    value: '$selectedCount',
                    label: 'Selected',
                  ),
                ),
                _WhiteDivider(),
                Expanded(
                  child: _WhiteMetric(value: '$addedCount', label: 'Added'),
                ),
                _WhiteDivider(),
                Expanded(
                  child: _WhiteMetric(value: '$removedCount', label: 'Removed'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WhiteMetric extends StatelessWidget {
  const _WhiteMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),

        const SizedBox(height: 2),

        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class _WhiteDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      color: Colors.white.withValues(alpha: 0.18),
    );
  }
}

class _SelectedBookingSpotCard extends StatelessWidget {
  const _SelectedBookingSpotCard({
    required this.index,
    required this.spot,
    required this.total,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final int index;
  final _EditableBookingSpot spot;
  final int total;

  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: spot.imageUrl.isEmpty
                      ? const _ImageFallback()
                      : Image.network(
                          spot.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const _ImageFallback(),
                        ),
                ),
              ),

              Positioned(
                left: 4,
                top: 4,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  _spotSubtitle(spot),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _secondaryText,
                    fontWeight: FontWeight.w600,
                    fontSize: 9.8,
                    height: 1.3,
                  ),
                ),

                const SizedBox(height: 6),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: spot.isOriginal
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFEAF3FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    spot.isOriginal ? 'Package spot' : '+ ₱250 Google Place',
                    style: TextStyle(
                      color: spot.isOriginal
                          ? const Color(0xFF15803D)
                          : _primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 8.8,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          Column(
            children: [
              _TinyActionButton(
                icon: Icons.keyboard_arrow_up_rounded,
                onTap: onMoveUp,
              ),

              const SizedBox(height: 3),

              _TinyActionButton(
                icon: Icons.keyboard_arrow_down_rounded,
                onTap: onMoveDown,
              ),

              const SizedBox(height: 3),

              _TinyActionButton(
                icon: Icons.close_rounded,
                onTap: onRemove,
                danger: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RemovedOriginalSpotCard extends StatelessWidget {
  const _RemovedOriginalSpotCard({required this.spot, required this.onRestore});

  final _EditableBookingSpot spot;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFD),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.place_outlined,
              color: Color(0xFF8492A6),
              size: 18,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              spot.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ),

          const SizedBox(width: 8),

          TextButton.icon(
            onPressed: onRestore,
            icon: const Icon(Icons.undo_rounded, size: 15),
            label: const Text('Restore'),
            style: TextButton.styleFrom(
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotCategoryFilter extends StatelessWidget {
  const _SpotCategoryFilter({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  static const categories = [
    'All',
    'Cafe',
    'Historical',
    'Nature',
    'Religious',
    'Food',
    'Adventure',
    'Cultural',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: categories.map((category) {
          final active = selected == category;

          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: InkWell(
              onTap: () => onSelected(category),
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: active ? _primary : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: active ? _primary : _border),
                ),
                child: Text(
                  category,
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF526173),
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _GoogleSuggestionCard extends StatelessWidget {
  const _GoogleSuggestionCard({
    required this.spot,
    required this.additionalFee,
    required this.onAdd,
  });

  final CitySpotSuggestion spot;
  final double additionalFee;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: SizedBox(
              width: 60,
              height: 60,
              child: Image.network(
                spot.imageForCard,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _ImageFallback(),
              ),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  [
                    spot.category,
                    spot.barangayHint,
                  ].where((value) => value.trim().isNotEmpty).join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _secondaryText,
                    fontWeight: FontWeight.w600,
                    fontSize: 9.8,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  '+ ₱${additionalFee.toStringAsFixed(0)} / person',
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          SizedBox(
            height: 38,
            child: ElevatedButton(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Add',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotFeeNotice extends StatelessWidget {
  const _SpotFeeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFFDE3A7)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 17),

          SizedBox(width: 8),

          Expanded(
            child: Text(
              'Every additional Google Places destination adds ₱250 per person to the package price. Removing an original destination does not add a fee.',
              style: TextStyle(
                color: Color(0xFF8A5A16),
                fontWeight: FontWeight.w600,
                fontSize: 10.2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinalSpotStrip extends StatelessWidget {
  const _FinalSpotStrip({required this.spots});

  final List<_EditableBookingSpot> spots;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Final selected destinations',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: spots.asMap().entries.map((entry) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${entry.key + 1}. ${entry.value.title}',
                  style: const TextStyle(
                    color: Color(0xFF315B8A),
                    fontWeight: FontWeight.w700,
                    fontSize: 9.5,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SCHEDULE
// =============================================================================

class _ItineraryModeToggle extends StatelessWidget {
  const _ItineraryModeToggle({required this.selected, required this.onChanged});

  final _ItineraryViewMode selected;
  final ValueChanged<_ItineraryViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF5),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ItineraryModeChip(
              icon: Icons.auto_awesome_rounded,
              label: 'Suggested Schedule',
              selected: selected == _ItineraryViewMode.suggested,
              onTap: () => onChanged(_ItineraryViewMode.suggested),
            ),
          ),

          const SizedBox(width: 5),

          Expanded(
            child: _ItineraryModeChip(
              icon: Icons.tune_rounded,
              label: 'Customize Schedule',
              selected: selected == _ItineraryViewMode.customize,
              onTap: () => onChanged(_ItineraryViewMode.customize),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItineraryModeChip extends StatelessWidget {
  const _ItineraryModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? _primary : const Color(0xFF667085),
            ),

            const SizedBox(width: 5),

            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? _ink : const Color(0xFF667085),
                  fontWeight: FontWeight.w800,
                  fontSize: 9.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyItineraryCard extends StatelessWidget {
  const _ReadOnlyItineraryCard({
    required this.items,
    required this.totalDurationLabel,
  });

  final List<_EditableItineraryStop> items;
  final String totalDurationLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'TOURISTRlKE SUGGESTED',
                  style: TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 8.5,
                  ),
                ),
              ),

              const Spacer(),

              Text(
                totalDurationLabel,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: 9),

          const Text(
            'A recommended timing for the destinations you selected.',
            style: TextStyle(
              color: _secondaryText,
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
            ),
          ),

          const SizedBox(height: 13),

          ...items.asMap().entries.map(
            (entry) => Padding(
              padding: EdgeInsets.only(
                bottom: entry.key == items.length - 1 ? 0 : 8,
              ),
              child: _ItineraryPreviewTile(
                index: entry.key + 1,
                item: entry.value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItineraryPreviewTile extends StatelessWidget {
  const _ItineraryPreviewTile({required this.index, required this.item});

  final int index;
  final _EditableItineraryStop item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 29,
            height: 29,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _softBlue,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                color: _primary,
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ),
            ),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.destinationName,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  _itineraryTimingSummary(
                    arrivalTime: item.arrivalTime,
                    stayMinutes: item.stayMinutes,
                    departureTime: item.departureTime,
                    travelDurationMinutes: item.travelDurationMinutes,
                  ),
                  style: const TextStyle(
                    color: _secondaryText,
                    fontWeight: FontWeight.w600,
                    fontSize: 9.5,
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

class _EditableItineraryCard extends StatelessWidget {
  const _EditableItineraryCard({
    required this.items,
    required this.currentDurationLabel,
    required this.hasUnsavedChanges,
    required this.onStayChanged,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final List<_EditableItineraryStop> items;

  final String currentDurationLabel;

  final bool hasUnsavedChanges;

  final void Function(_EditableItineraryStop item, int minutes) onStayChanged;

  final ValueChanged<int> onMoveUp;
  final ValueChanged<int> onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Customized Schedule',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            'Reorder destinations and adjust their timing. Destination selection is managed in the previous step.',
            style: const TextStyle(
              color: _secondaryText,
              fontWeight: FontWeight.w600,
              fontSize: 10.2,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Estimated duration: $currentDurationLabel',
            style: const TextStyle(
              color: _primary,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),

          const SizedBox(height: 13),

          ...items.asMap().entries.map(
            (entry) => Padding(
              padding: EdgeInsets.only(
                bottom: entry.key == items.length - 1 ? 0 : 10,
              ),
              child: _EditableItineraryTile(
                index: entry.key,
                total: items.length,
                item: entry.value,
                onMoveUp: entry.key == 0 ? null : () => onMoveUp(entry.key),
                onMoveDown: entry.key == items.length - 1
                    ? null
                    : () => onMoveDown(entry.key),
                onStayChanged: (minutes) => onStayChanged(entry.value, minutes),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableItineraryTile extends StatelessWidget {
  const _EditableItineraryTile({
    required this.index,
    required this.total,
    required this.item,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onStayChanged,
  });

  final int index;
  final int total;

  final _EditableItineraryStop item;

  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  final ValueChanged<int> onStayChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 29,
                height: 29,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  item.destinationName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),

              _TinyActionButton(
                icon: Icons.keyboard_arrow_up_rounded,
                onTap: onMoveUp,
              ),

              _TinyActionButton(
                icon: Icons.keyboard_arrow_down_rounded,
                onTap: onMoveDown,
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _EditableTimeButton(
                  label: 'Arrival',
                  value: item.arrivalTime.isEmpty
                      ? 'Calculating'
                      : formatScheduleTimeLabel(item.arrivalTime),
                  onTap: null,
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _EditableTimeButton(
                  label: 'Departure',
                  value: item.departureTime.isEmpty
                      ? 'Calculating'
                      : formatScheduleTimeLabel(item.departureTime),
                  onTap: null,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          TextFormField(
            initialValue: '${item.stayMinutes}',
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final minutes = int.tryParse(value.trim());

              if (minutes != null && minutes > 0) {
                onStayChanged(minutes);
              }
            },
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
            decoration: InputDecoration(
              labelText: 'Estimated stay',
              suffixText: 'min',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: _border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableTimeButton extends StatelessWidget {
  const _EditableTimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8795A8),
                fontWeight: FontWeight.w600,
                fontSize: 8.5,
              ),
            ),

            const SizedBox(height: 3),

            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w800,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItineraryGuideCard extends StatelessWidget {
  const _ItineraryGuideCard({required this.duration, required this.stops});

  final String duration;
  final int stops;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_outlined, color: _primary, size: 16),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              '$stops destination${stops == 1 ? '' : 's'} • $duration total estimated tour time',
              style: const TextStyle(
                color: Color(0xFF4F6785),
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PAYMENT
// =============================================================================

class _PaymentAmountHero extends StatelessWidget {
  const _PaymentAmountHero({
    required this.total,
    required this.amountNow,
    required this.remaining,
  });

  final double total;
  final double amountNow;
  final double remaining;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF3FAAF8)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '50% DOWN PAYMENT',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w900,
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            money.format(amountNow),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _PaymentMetric(
                    label: 'Total',
                    value: money.format(total),
                  ),
                ),

                _WhiteDivider(),

                Expanded(
                  child: _PaymentMetric(
                    label: 'Remaining',
                    value: money.format(remaining),
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

class _PaymentMetric extends StatelessWidget {
  const _PaymentMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 11.5,
          ),
        ),

        const SizedBox(height: 2),

        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 8.5,
          ),
        ),
      ],
    );
  }
}

class _PricingBreakdownCard extends StatelessWidget {
  const _PricingBreakdownCard({
    required this.baseUnitPrice,
    required this.addedSpotCount,
    required this.addedSpotFee,
    required this.finalUnitPrice,
    required this.passengers,
  });

  final double baseUnitPrice;

  final int addedSpotCount;

  final double addedSpotFee;
  final double finalUnitPrice;

  final int passengers;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          _PriceBreakdownRow(
            label: 'Base package',
            value: money.format(baseUnitPrice),
          ),

          if (addedSpotCount > 0) ...[
            const SizedBox(height: 8),

            _PriceBreakdownRow(
              label:
                  '$addedSpotCount added destination${addedSpotCount == 1 ? '' : 's'}',
              value: '+ ${money.format(addedSpotCount * addedSpotFee)}',
            ),
          ],

          const Divider(height: 20, color: Color(0xFFEDF1F6)),

          _PriceBreakdownRow(
            label: 'Price per person',
            value: money.format(finalUnitPrice),
            strong: true,
          ),

          const SizedBox(height: 6),

          _PriceBreakdownRow(
            label: '$passengers passenger${passengers == 1 ? '' : 's'}',
            value: money.format(finalUnitPrice * passengers),
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _PriceBreakdownRow extends StatelessWidget {
  const _PriceBreakdownRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: strong ? _ink : _secondaryText,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              fontSize: 10.5,
            ),
          ),
        ),

        Text(
          value,
          style: TextStyle(
            color: strong ? _primary : _ink,
            fontWeight: FontWeight.w900,
            fontSize: strong ? 12 : 10.5,
          ),
        ),
      ],
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.selected,
    required this.enabled,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final bool enabled;

  final IconData icon;

  final String title;
  final String subtitle;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = selected && enabled;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active ? _primary : _border,
                width: active ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 41,
                  height: 41,
                  decoration: BoxDecoration(
                    color: _softBlue,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: _primary, size: 18),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _secondaryText,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 7),

                Icon(
                  active
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: active ? _primary : const Color(0xFFC3CDDA),
                  size: 21,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectPaymentNotice extends StatelessWidget {
  const _DirectPaymentNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _primary, size: 17),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              'Every package booking requires a confirmed 50% GCash down payment before the driver can start. The remaining balance is paid after the tour.',
              style: const TextStyle(
                color: Color(0xFF57708F),
                fontWeight: FontWeight.w600,
                fontSize: 10,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesField extends StatelessWidget {
  const _NotesField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 4,
      maxLines: 6,
      style: const TextStyle(
        color: _ink,
        fontWeight: FontWeight.w600,
        fontSize: 11.5,
      ),
      decoration: InputDecoration(
        hintText: 'Example: Please assist an elderly passenger...',
        hintStyle: const TextStyle(
          color: Color(0xFFA0AABA),
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: _primary),
        ),
      ),
    );
  }
}

// =============================================================================
// REVIEW
// =============================================================================

class _ReviewPackageCard extends StatelessWidget {
  const _ReviewPackageCard({required this.package});

  final TourPackage package;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: SizedBox(
              width: 60,
              height: 60,
              child: package.displayImageUrl.isEmpty
                  ? const _ImageFallback()
                  : Image.network(
                      package.displayImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _ImageFallback(),
                    ),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOU ARE BOOKING',
                  style: TextStyle(
                    color: Color(0xFF8A98AB),
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                    letterSpacing: 0.5,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  package.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  package.city,
                  style: const TextStyle(
                    color: _secondaryText,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
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

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.icon,
    required this.title,
    required this.onEdit,
    required this.children,
  });

  final IconData icon;
  final String title;

  final VoidCallback onEdit;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 33,
                height: 33,
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 15, color: _primary),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
              ),

              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text(
                  'Edit',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10),
                ),
              ),
            ],
          ),

          const Divider(height: 19, color: Color(0xFFEDF1F6)),

          ...children,
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;

  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF7D8A9D),
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ),

          const SizedBox(width: 10),

          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: emphasized ? _primary : _ink,
                fontWeight: FontWeight.w800,
                fontSize: emphasized ? 12 : 10.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewDestinationRow extends StatelessWidget {
  const _ReviewDestinationRow({
    required this.index,
    required this.name,
    required this.added,
  });

  final int index;
  final String name;
  final bool added;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 23,
            height: 23,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _softBlue,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                color: _primary,
                fontWeight: FontWeight.w900,
                fontSize: 8.5,
              ),
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
              ),
            ),
          ),

          if (added)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: _softBlue,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Added',
                style: TextStyle(
                  color: _primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 8,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewAddressRow extends StatelessWidget {
  const _ReviewAddressRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),

        const SizedBox(width: 7),

        SizedBox(
          width: 51,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7D8A9D),
              fontWeight: FontWeight.w600,
              fontSize: 9.5,
            ),
          ),
        ),

        const SizedBox(width: 5),

        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _FinalAgreementNotice extends StatelessWidget {
  const _FinalAgreementNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, color: _primary, size: 17),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              'By confirming, you are requesting this tour. The 50% GCash down payment becomes due after the driver roster is filled.',
              style: const TextStyle(
                color: Color(0xFF57708F),
                fontWeight: FontWeight.w600,
                fontSize: 10,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BOTTOM NAV
// =============================================================================

class _BookingNavigationBar extends StatelessWidget {
  const _BookingNavigationBar({
    required this.currentStep,
    required this.totalSteps,
    required this.saving,
    required this.onBack,
    required this.onNext,
    required this.onConfirm,
  });

  final int currentStep;
  final int totalSteps;

  final bool saving;

  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    final finalStep = currentStep == totalSteps - 1;

    return Container(
      padding: EdgeInsets.fromLTRB(18, 10, 18, 10 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE8EDF4))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          if (currentStep > 0) ...[
            SizedBox(
              height: 48,
              width: 88,
              child: OutlinedButton(
                onPressed: saving ? null : onBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4D5D73),
                  side: const BorderSide(color: Color(0xFFDCE4EE)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),

            const SizedBox(width: 9),
          ],

          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: saving
                    ? null
                    : finalStep
                    ? onConfirm
                    : onNext,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFB9D5FA),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: saving
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            finalStep ? 'Confirm Booking' : 'Continue',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),

                          const SizedBox(width: 6),

                          Icon(
                            finalStep
                                ? Icons.check_rounded
                                : Icons.arrow_forward_rounded,
                            size: 17,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// LOCATION STEP CARD
// =============================================================================

class _LocationStepCard extends StatelessWidget {
  const _LocationStepCard({
    required this.number,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String number;
  final IconData icon;
  final Color iconColor;

  final String title;
  final String subtitle;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 37,
                height: 37,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 17),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF8492A6),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),

              Text(
                number,
                style: const TextStyle(
                  color: Color(0xFFC3CDDA),
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          child,
        ],
      ),
    );
  }
}

// =============================================================================
// LOCATION PICKER
// =============================================================================

class _LocationPickerCard extends StatefulWidget {
  const _LocationPickerCard({
    required this.label,
    required this.onLocationSelected,
    required this.requiredMunicipality,
    required this.requiredProvince,
    this.errorText,
    this.onValidationMessageChanged,
  });

  final String label;

  final String requiredMunicipality;
  final String requiredProvince;

  final String? errorText;

  final ValueChanged<String?>? onValidationMessageChanged;

  final void Function(String? address, double? lat, double? lng)
  onLocationSelected;

  @override
  State<_LocationPickerCard> createState() => _LocationPickerCardState();
}

class _LocationPickerCardState extends State<_LocationPickerCard> {
  static final String _apiKey = CitySpotSuggestionService.resolveApiKey();

  final TextEditingController _searchCtrl = TextEditingController();

  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;

  List<_AutocompleteResult> _suggestions = const [];

  bool _loadingSuggestions = false;
  bool _loadingDetails = false;
  bool _loadingLocation = false;

  String? _selectedAddress;

  double? _selectedLat;
  double? _selectedLng;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = const [];
      });

      return;
    }

    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _fetchSuggestions(query.trim()),
    );
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;

    setState(() {
      _loadingSuggestions = true;
    });

    try {
      final scoped =
          '$query, ${widget.requiredMunicipality}, ${widget.requiredProvince}, Philippines';

      final encoded = Uri.encodeQueryComponent(scoped);

      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=$encoded'
        '&key=$_apiKey'
        '&components=country:ph'
        '&language=en',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;

        final predictions = (body['predictions'] as List?) ?? const [];

        setState(() {
          _suggestions = predictions
              .map(
                (prediction) => _AutocompleteResult(
                  placeId: prediction['place_id'] as String? ?? '',
                  description: prediction['description'] as String? ?? '',
                ),
              )
              .where((result) => result.placeId.isNotEmpty)
              .take(5)
              .toList(growable: false);
        });
      }
    } catch (_) {
      // Intentionally unobtrusive.
    } finally {
      if (mounted) {
        setState(() {
          _loadingSuggestions = false;
        });
      }
    }
  }

  Future<void> _selectSuggestion(_AutocompleteResult suggestion) async {
    _focusNode.unfocus();

    setState(() {
      _suggestions = const [];
      _loadingDetails = true;
    });

    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${suggestion.placeId}'
        '&fields=geometry,formatted_address,address_components,name'
        '&key=$_apiKey',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;

        final result = body['result'] as Map<String, dynamic>?;

        final geometry = result?['geometry'] as Map?;

        final location = geometry == null
            ? null
            : Map<String, dynamic>.from(geometry)['location'] as Map?;

        final lat = (location?['lat'] as num?)?.toDouble();

        final lng = (location?['lng'] as num?)?.toDouble();

        final address =
            result?['formatted_address'] as String? ?? suggestion.description;

        final components = _parseAddressComponents(
          (result?['address_components'] as List?) ?? const [],
        );

        if (lat != null && lng != null) {
          final validation = _locationValidationMessage(
            address: address,
            countryCode: components.countryCode,
            province: components.province,
            locality: components.locality,
          );

          if (validation != null) {
            _invalidateSelection(validation);
            return;
          }

          _setLocation(address, lat, lng);

          return;
        }
      }

      _invalidateSelection(
        'Unable to verify this location. Please choose another location.',
      );
    } catch (_) {
      _invalidateSelection(
        'Unable to verify this location. Please choose another location.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingDetails = false;
        });
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _loadingLocation = true;
    });

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();

      if (!enabled) {
        _showError('Location services are disabled. Please enable them first.');
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showError('Location permission was denied.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final address = await _reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;

      final validation = _locationValidationMessage(
        address: address,
        countryCode: _addressContainsLocation(address, 'Philippines')
            ? 'PH'
            : '',
      );

      if (validation != null) {
        _invalidateSelection(validation);
        return;
      }

      _setLocation(address, position.latitude, position.longitude);
    } catch (_) {
      _showError('Could not get your current location. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _loadingLocation = false;
        });
      }
    }
  }

  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=$lat,$lng'
        '&key=$_apiKey'
        '&language=en',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;

        final results = (body['results'] as List?) ?? const [];

        if (results.isNotEmpty) {
          return results.first['formatted_address'] as String? ??
              '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
        }
      }
    } catch (_) {}

    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  void _setLocation(String address, double lat, double lng) {
    _searchCtrl.text = address;

    setState(() {
      _selectedAddress = address;
      _selectedLat = lat;
      _selectedLng = lng;
      _suggestions = const [];
    });

    widget.onValidationMessageChanged?.call(null);

    widget.onLocationSelected(address, lat, lng);
  }

  void _clearLocation() {
    _searchCtrl.clear();

    setState(() {
      _selectedAddress = null;
      _selectedLat = null;
      _selectedLng = null;
      _suggestions = const [];
    });

    widget.onValidationMessageChanged?.call(null);

    widget.onLocationSelected(null, null, null);
  }

  void _invalidateSelection(String message) {
    _clearLocation();

    widget.onValidationMessageChanged?.call(message);

    _showError(message);
  }

  String? _locationValidationMessage({
    required String address,
    String countryCode = '',
    String province = '',
    String locality = '',
  }) {
    final isPhilippines =
        countryCode.trim().toUpperCase() == 'PH' ||
        _addressContainsLocation(address, 'Philippines');

    if (!isPhilippines) {
      return 'Please select a valid location within the Philippines.';
    }

    final structuredProvinceMatches =
        province.isNotEmpty &&
        _locationNamesMatch(province, widget.requiredProvince);

    final structuredLocalityMatches =
        locality.isNotEmpty &&
        _locationNamesMatch(locality, widget.requiredMunicipality);

    if (structuredProvinceMatches && structuredLocalityMatches) {
      return null;
    }

    final fallbackMatches =
        _addressContainsLocation(address, widget.requiredMunicipality) &&
        _addressContainsLocation(address, widget.requiredProvince);

    if (fallbackMatches) {
      return null;
    }

    return 'Please select a pickup/drop-off point within ${widget.requiredMunicipality}, ${widget.requiredProvince}.';
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loadingDetails || _loadingLocation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          focusNode: _focusNode,
          onChanged: _onSearchChanged,
          style: const TextStyle(
            color: _ink,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          ),
          decoration: InputDecoration(
            hintText: 'Search ${widget.label.toLowerCase()} location...',
            hintStyle: const TextStyle(
              color: Color(0xFF9AA6B6),
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: _primary,
              size: 19,
            ),
            suffixIcon: busy
                ? const Padding(
                    padding: EdgeInsets.all(13),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _primary,
                      ),
                    ),
                  )
                : _searchCtrl.text.isNotEmpty
                ? IconButton(
                    onPressed: _clearLocation,
                    icon: const Icon(Icons.close_rounded),
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF8FAFD),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: _selectedLat != null ? const Color(0xFF86EFAC) : _border,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: _primary),
            ),
          ),
        ),

        if (_loadingSuggestions)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(color: _primary, minHeight: 2),
          ),

        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 7),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: _suggestions.map((suggestion) {
                return InkWell(
                  onTap: () => _selectSuggestion(suggestion),
                  child: Padding(
                    padding: const EdgeInsets.all(11),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          color: _primary,
                          size: 16,
                        ),

                        const SizedBox(width: 8),

                        Expanded(
                          child: Text(
                            suggestion.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF344054),
                              fontWeight: FontWeight.w600,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        const SizedBox(height: 6),

        TextButton.icon(
          onPressed: _loadingLocation ? null : _useCurrentLocation,
          icon: _loadingLocation
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location_rounded, size: 15),
          label: Text(
            _loadingLocation ? 'Getting location...' : 'Use Current Location',
          ),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
            ),
          ),
        ),

        if (_selectedAddress != null) ...[
          const SizedBox(height: 4),

          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF16A34A),
                  size: 15,
                ),

                const SizedBox(width: 7),

                Expanded(
                  child: Text(
                    _selectedAddress!,
                    style: const TextStyle(
                      color: Color(0xFF15803D),
                      fontWeight: FontWeight.w600,
                      fontSize: 9.8,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (widget.errorText != null &&
            widget.errorText!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),

          Text(
            widget.errorText!,
            style: const TextStyle(
              color: Color(0xFFDC2626),
              fontWeight: FontWeight.w600,
              fontSize: 9.8,
            ),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// ROUTE MAP
// =============================================================================

class _SharedRouteMapPreview extends StatelessWidget {
  const _SharedRouteMapPreview({
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffAddress,
    required this.dropoffLat,
    required this.dropoffLng,
  });

  static final String _apiKey = CitySpotSuggestionService.resolveApiKey();

  final String? pickupAddress;

  final double? pickupLat;
  final double? pickupLng;

  final String? dropoffAddress;

  final double? dropoffLat;
  final double? dropoffLng;

  String _mapUrl() {
    final buffer = StringBuffer(
      'https://maps.googleapis.com/maps/api/staticmap'
      '?size=800x360&scale=2&maptype=roadmap&key=$_apiKey',
    );

    if (pickupLat != null && pickupLng != null) {
      buffer.write('&markers=color:green%7Clabel:P%7C$pickupLat,$pickupLng');
    }

    if (dropoffLat != null && dropoffLng != null) {
      buffer.write('&markers=color:red%7Clabel:D%7C$dropoffLat,$dropoffLng');
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final complete =
        pickupLat != null &&
        pickupLng != null &&
        dropoffLat != null &&
        dropoffLng != null;

    if (!complete) {
      return const _SimpleEmptyCard(
        icon: Icons.map_outlined,
        title: 'Route preview waiting',
        subtitle:
            'Select both pickup and drop-off points to preview them on the map.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              _mapUrl(),
              width: double.infinity,
              height: 160,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 160,
                color: const Color(0xFFF1F5F9),
                alignment: Alignment.center,
                child: const Text('Map preview unavailable'),
              ),
            ),
          ),

          const SizedBox(height: 9),

          _MapLegendRow(
            color: const Color(0xFF16A34A),
            label: 'Pickup',
            value: pickupAddress ?? '',
          ),

          const SizedBox(height: 6),

          _MapLegendRow(
            color: const Color(0xFFDC2626),
            label: 'Drop-off',
            value: dropoffAddress ?? '',
          ),
        ],
      ),
    );
  }
}

class _MapLegendRow extends StatelessWidget {
  const _MapLegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),

        const SizedBox(width: 7),

        SizedBox(
          width: 46,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7D8A9D),
              fontWeight: FontWeight.w600,
              fontSize: 9,
            ),
          ),
        ),

        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF344054),
              fontWeight: FontWeight.w600,
              fontSize: 9.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// LOCATION MODELS / HELPERS
// =============================================================================

class _SelectedLocation {
  const _SelectedLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
    this.isValidWithinMunicipality = true,
  });

  final String address;

  final double latitude;
  final double longitude;

  final bool isValidWithinMunicipality;
}

class _ParsedAddressComponents {
  const _ParsedAddressComponents({
    required this.countryCode,
    required this.province,
    required this.locality,
  });

  final String countryCode;
  final String province;
  final String locality;
}

String _normalizeLocationName(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'\b(city|municipality|province)\s+of\b'), '')
      .replaceAll(RegExp(r'\b(city|municipality|province)\b'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _locationNamesMatch(String actual, String expected) {
  final a = _normalizeLocationName(actual);
  final b = _normalizeLocationName(expected);

  if (a.isEmpty || b.isEmpty) {
    return false;
  }

  return a == b || a.contains(b) || b.contains(a);
}

bool _addressContainsLocation(String address, String expected) {
  return _normalizeLocationName(
    address,
  ).contains(_normalizeLocationName(expected));
}

_ParsedAddressComponents _parseAddressComponents(List<dynamic> rawComponents) {
  String countryCode = '';
  String province = '';
  String locality = '';

  for (final raw in rawComponents.whereType<Map>()) {
    final component = Map<String, dynamic>.from(raw);

    final types = (component['types'] as List?)?.cast<String>() ?? const [];

    final longName = dbString(component['long_name']);

    final shortName = dbString(component['short_name']);

    if (types.contains('country')) {
      countryCode = shortName;
    }

    if (types.contains('administrative_area_level_1')) {
      province = longName;
    }

    if (types.contains('locality') ||
        types.contains('administrative_area_level_2') ||
        types.contains('administrative_area_level_3')) {
      if (locality.isEmpty) {
        locality = longName;
      }
    }
  }

  return _ParsedAddressComponents(
    countryCode: countryCode,
    province: province,
    locality: locality,
  );
}

// =============================================================================
// ITINERARY MODEL
// =============================================================================

class _EditableItineraryStop {
  _EditableItineraryStop({
    required this.localKey,
    required this.spotId,
    required this.googlePlaceId,
    required this.destinationName,
    required this.destinationAddress,
    required this.municipality,
    required this.barangay,
    required this.latitude,
    required this.longitude,
    required this.imageUrl,
    required this.arrivalTime,
    required this.stayMinutes,
    required this.departureTime,
    required this.travelDurationMinutes,
    required this.routeDistanceMeters,
  });

  final String localKey;

  final dynamic spotId;
  final String googlePlaceId;

  final String destinationName;
  final String destinationAddress;

  final String municipality;
  final String barangay;

  final double latitude;
  final double longitude;

  final String imageUrl;

  String arrivalTime;
  int stayMinutes;
  String departureTime;
  int travelDurationMinutes;
  int routeDistanceMeters;

  factory _EditableItineraryStop.cloneFrom(_EditableItineraryStop other) {
    return _EditableItineraryStop(
      localKey: other.localKey,
      spotId: other.spotId,
      googlePlaceId: other.googlePlaceId,
      destinationName: other.destinationName,
      destinationAddress: other.destinationAddress,
      municipality: other.municipality,
      barangay: other.barangay,
      latitude: other.latitude,
      longitude: other.longitude,
      imageUrl: other.imageUrl,
      arrivalTime: other.arrivalTime,
      stayMinutes: other.stayMinutes,
      departureTime: other.departureTime,
      travelDurationMinutes: other.travelDurationMinutes,
      routeDistanceMeters: other.routeDistanceMeters,
    );
  }

  Json toBookingPayload({required int order, required String sourceType}) {
    return {
      'spot_id': spotId,
      'destination_name': destinationName,
      'destination_address': destinationAddress,
      'order_number': order,
      'destination_order': order,
      'arrival_time': arrivalTime,
      'estimated_stay_duration_minutes': stayMinutes,
      'departure_time': departureTime,
      'travel_duration_minutes': travelDurationMinutes,
      'route_distance_meters': routeDistanceMeters,
      'activity_note': '',
      'itinerary_source': sourceType,
      'source_type': sourceType,
      'google_place_id': googlePlaceId,
      'municipality': municipality,
      'barangay': barangay,
      'latitude': latitude,
      'longitude': longitude,
      'image_url': imageUrl,
    };
  }

  void dispose() {}
}

// =============================================================================
// GENERAL HELPERS
// =============================================================================

int _calculateDurationMinutes(List<_EditableItineraryStop> items) {
  if (items.isEmpty) {
    return 0;
  }

  final first = items.first.arrivalTime;
  final last = items.last.departureTime;

  if (first.isNotEmpty && last.isNotEmpty) {
    return scheduleMinutesBetween(first, last);
  }

  return items.fold(0, (total, item) => total + item.stayMinutes);
}

String _formatDurationLabel(int minutes) {
  if (minutes <= 0) {
    return 'Not available';
  }

  final hours = minutes ~/ 60;
  final remainder = minutes % 60;

  if (hours == 0) {
    return '${remainder}m';
  }

  if (remainder == 0) {
    return '${hours}h';
  }

  return '${hours}h ${remainder}m';
}

String _itineraryTimingSummary({
  required String arrivalTime,
  required int stayMinutes,
  required String departureTime,
  int travelDurationMinutes = 0,
}) {
  final parts = <String>[];

  if (travelDurationMinutes > 0) {
    parts.add('Travel ${_formatDurationLabel(travelDurationMinutes)}');
  }

  if (arrivalTime.isNotEmpty) {
    parts.add('Arrival ${formatScheduleTimeLabel(arrivalTime)}');
  }

  if (stayMinutes > 0) {
    parts.add('Stay ${_formatDurationLabel(stayMinutes)}');
  }

  if (departureTime.isNotEmpty) {
    parts.add('Leave ${formatScheduleTimeLabel(departureTime)}');
  }

  return parts.join(' • ');
}

String _storageTimeFromMinutes(int totalMinutes) {
  final normalized = totalMinutes % (24 * 60);
  final hour = normalized ~/ 60;
  final minute = normalized % 60;
  return '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}:00';
}

bool _sameMunicipality(String a, String b) {
  return _normalizeText(a) == _normalizeText(b);
}

String _normalizeText(String value) {
  return value
      .toLowerCase()
      .replaceAll('ñ', 'n')
      .replaceAll('Ã±', 'n')
      .replaceAll('-', '')
      .replaceAll(' ', '')
      .replaceAll(',', '')
      .replaceAll('.', '');
}

String _spotSubtitle(_EditableBookingSpot spot) {
  return [
    spot.barangay,
    spot.municipality,
    if (spot.address.isNotEmpty) spot.address,
  ].where((text) => text.trim().isNotEmpty).join(' • ');
}

String _inferCategoryFromTitle(String title) {
  final value = title.toLowerCase();

  if (value.contains('church') ||
      value.contains('chapel') ||
      value.contains('cathedral') ||
      value.contains('basilica') ||
      value.contains('shrine') ||
      value.contains('mosque') ||
      value.contains('temple') ||
      value.contains('parish')) {
    return 'Religious';
  }

  if (value.contains('museum') ||
      value.contains('gallery') ||
      value.contains('cultural') ||
      value.contains('heritage') ||
      value.contains('arts center')) {
    return 'Cultural';
  }

  if (value.contains('cafe') ||
      value.contains('café') ||
      value.contains('coffee') ||
      value.contains('bakery') ||
      value.contains('pastry')) {
    return 'Cafe';
  }

  if (value.contains('restaurant') ||
      value.contains('eatery') ||
      value.contains('food') ||
      value.contains('carinderia') ||
      value.contains('diner') ||
      value.contains('grill')) {
    return 'Food';
  }

  if (value.contains('park') ||
      value.contains('garden') ||
      value.contains('falls') ||
      value.contains('lake') ||
      value.contains('mountain') ||
      value.contains('forest') ||
      value.contains('river') ||
      value.contains('nature')) {
    return 'Nature';
  }

  if (value.contains('resort') ||
      value.contains('adventure') ||
      value.contains('zipline') ||
      value.contains('hiking') ||
      value.contains('trail') ||
      value.contains('camp')) {
    return 'Adventure';
  }

  return 'Historical';
}

// =============================================================================
// SMALL WIDGETS
// =============================================================================

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: filled ? _primary : const Color(0xFFF1F4F8),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 17,
          color: onTap == null
              ? const Color(0xFFC8D0DB)
              : filled
              ? Colors.white
              : const Color(0xFF526173),
        ),
      ),
    );
  }
}

class _TinyActionButton extends StatelessWidget {
  const _TinyActionButton({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback? onTap;

  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 29,
        height: 29,
        child: Icon(
          icon,
          size: 17,
          color: onTap == null
              ? const Color(0xFFC8D0DB)
              : danger
              ? const Color(0xFFDC2626)
              : const Color(0xFF64748B),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: _softBlue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _primary,
          fontWeight: FontWeight.w900,
          fontSize: 8,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SimpleEmptyCard extends StatelessWidget {
  const _SimpleEmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _softBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _primary, size: 18),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _secondaryText,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    height: 1.35,
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

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _softBlue,
      alignment: Alignment.center,
      child: const Icon(Icons.map_outlined, color: _primary),
    );
  }
}

// =============================================================================
// TIME PICKER
// =============================================================================

class _TimePickerSheet extends StatelessWidget {
  const _TimePickerSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final String selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.68,
        child: Column(
          children: [
            const SizedBox(height: 10),

            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFDCE3EC),
                borderRadius: BorderRadius.circular(999),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 13, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),

                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (_, index) {
                  final option = options[index];

                  final active = option == selected;

                  return ListTile(
                    onTap: () => Navigator.pop(context, option),
                    tileColor: active ? _softBlue : null,
                    title: Text(
                      formatScheduleTimeLabel(option),
                      style: TextStyle(
                        color: active ? _primary : _ink,
                        fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    trailing: active
                        ? const Icon(Icons.check_rounded, color: _primary)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// LOADING / ERROR
// =============================================================================

class _BookingLoadingView extends StatelessWidget {
  const _BookingLoadingView();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 29,
              height: 29,
              child: CircularProgressIndicator(color: _primary, strokeWidth: 3),
            ),

            SizedBox(height: 13),

            Text(
              'Preparing your booking...',
              style: TextStyle(
                color: _secondaryText,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Container(
            padding: const EdgeInsets.all(21),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: _border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFDC2626),
                  size: 35,
                ),

                const SizedBox(height: 12),

                const Text(
                  'Unable to load booking',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _secondaryText,
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
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
