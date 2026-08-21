import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/tourist/payment_checkout_screen.dart';
import 'package:touristrike/screens/tourist/tourist_activity_screen.dart';
import 'package:touristrike/screens/tourist/tourist_activity_tracking_screen.dart';

// ── Autocomplete result model ────────────────────────────────────────────────
class _AutocompleteResult {
  final String placeId;
  final String description;
  const _AutocompleteResult({required this.placeId, required this.description});
}

// ============================================================================
// Main booking screen pogi si bench
// ============================================================================

class PackageBookingScreen extends StatefulWidget {
  const PackageBookingScreen({
    super.key,
    required this.packageId,
    this.initialPackage,
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
  static const int _tourStartMinutes = 7 * 60;
  static const int _tourEndMinutes = 17 * 60;
  static const String _tourHoursErrorMessage =
      'Your itinerary exceeds the allowed tour hours. Tours are only available from 7:00 AM to 5:00 PM.';

  final TourisTrikeRepository _repo = TourisTrikeRepository();
  final _notesCtrl = TextEditingController();
  late Future<_BookingScreenData> _future;

  DateTime? _selectedDate;
  int _adults = 1;
  int _children = 0;
  _PaymentMethod _payment = _PaymentMethod.cashPickup;
  bool _saving = false;

  // Pickup / drop-off
  _SelectedLocation? _selectedPickup;
  _SelectedLocation? _selectedDropoff;
  String? _pickupLocationError;
  String? _dropoffLocationError;

  List<_EditableItineraryStop> _aiSuggestedItinerary = const [];
  List<_EditableItineraryStop> _customizedDraftItinerary = const [];
  List<_EditableItineraryStop> _availableCustomizedStops = const [];
  dynamic _initializedItineraryForPackageId;
  _ItineraryViewMode _itineraryMode = _ItineraryViewMode.aiSuggested;
  bool _customizedItineraryDirty = false;

  // ── Spot validation ──────────────────────────────────────────────────────
  String? get _spotError {
    if (widget.customizedSpots.isEmpty) return null;
    final active = widget.customizedSpots
        .where((s) => s['action_type'] == 'kept' || s['action_type'] == 'added')
        .length;
    if (active < 3) {
      return 'Please select at least 3 spots for your tour package.';
    }
    if (active > 6) {
      return 'You can only select up to 6 spots per package.';
    }
    return null;
  }

  // ── Participant helpers ──────────────────────────────────────────────────
  int get _totalParticipants => _adults + _children;
  static const int _tricycleCapacity = 3;
  int get _requiredTricycles =>
      (_totalParticipants / _tricycleCapacity).ceil().clamp(1, 99);

  // ── Booking type detection ───────────────────────────────────────────────
  bool get _isSameDay {
    if (_selectedDate == null) return false;
    final now = DateTime.now();
    return _selectedDate!.year == now.year &&
        _selectedDate!.month == now.month &&
        _selectedDate!.day == now.day;
  }

  String get _bookingType => _isSameDay ? 'same_day' : 'advanced';

  // ── Price helpers ────────────────────────────────────────────────────────
  double _totalPrice(TourPackage package) {
    final base = widget.customizedUnitPrice ?? package.numericPrice;
    return base <= 0 ? 0 : base * _totalParticipants;
  }

  double _downpaymentAmount(TourPackage package) =>
      _isSameDay ? 0 : _totalPrice(package) * 0.50;

  double _remainingBalance(TourPackage package) =>
      _isSameDay ? 0 : _totalPrice(package) * 0.50;

  double _amountToPayNow(TourPackage package) =>
      _isSameDay ? _totalPrice(package) : _totalPrice(package) * 0.50;

  // ── Location callbacks ───────────────────────────────────────────────────
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
  }

  String _packageProvince(TourPackage package) =>
      dbString(package.row['province'], fallback: 'Bulacan');


  String? _locationBlockingMessage(TourPackage package) {
    if (_pickupLocationError != null) return _pickupLocationError;
    if (_dropoffLocationError != null) return _dropoffLocationError;
    final pickupValid =
        _selectedPickup != null && _selectedPickup!.isValidWithinMunicipality;
    final dropoffValid =
        _selectedDropoff != null && _selectedDropoff!.isValidWithinMunicipality;
    if (!pickupValid) {
      return 'Select a pickup point within ${package.city}, ${_packageProvince(package)}.';
    }
    if (!dropoffValid) {
      return 'Select a drop-off point within ${package.city}, ${_packageProvince(package)}.';
    }
    return null;
  }

  String? _passengerValidationMessage() {
    if (_adults < 1) {
      return 'Please include at least 1 adult passenger.';
    }
    if (_totalParticipants <= 0) {
      return 'Please include at least 1 passenger before confirming your booking.';
    }
    return null;
  }

  String? _itineraryValidationMessage() {
    final itinerary = _selectedItinerary;
    if (itinerary.isEmpty) {
      return 'Unable to prepare the itinerary for this booking.';
    }
    if (itinerary.length < 3) {
      return 'Please keep at least 3 destinations in your itinerary.';
    }
    if (itinerary.length > 6) {
      return 'You can only include up to 6 destinations.';
    }

    int? firstArrivalMinutes;
    int? previousDepartureMinutes;
    int? finalDepartureMinutes;

    for (final item in itinerary) {
      final arrivalMinutes = _storageTimeToMinutes(item.arrivalTime);
      final departureMinutes = _storageTimeToMinutes(item.departureTime);

      if (arrivalMinutes == null || departureMinutes == null) {
        return 'Please complete the itinerary times before confirming your booking.';
      }
      if (item.stayMinutes <= 0) {
        return 'Please enter a valid estimated stay for ${item.destinationName}.';
      }
      if (departureMinutes <= arrivalMinutes) {
        return 'Please make sure departure time is after arrival time for ${item.destinationName}.';
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

    if (finalDepartureMinutes == null) {
      return 'Unable to prepare the itinerary for this booking.';
    }
    if (finalDepartureMinutes > _tourEndMinutes) {
      return _tourHoursErrorMessage;
    }
    if (_selectedDate == null) {
      return 'Please select a travel date.';
    }
    if (_isSameDay) {
      final now = DateTime.now();
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

  String? _dateAndTimeValidationMessage() {
    if (_selectedDate == null) {
      return 'Please select a travel date.';
    }
    return _itineraryValidationMessage();
  }

  String? _confirmationBlockingMessage(TourPackage package) {
    return _spotError ??
        _passengerValidationMessage() ??
        _locationBlockingMessage(package) ??
        _dateAndTimeValidationMessage();
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

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _future = _loadPackage();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final item in _aiSuggestedItinerary) {
      item.dispose();
    }
    for (final item in _customizedDraftItinerary) {
      item.dispose();
    }
    for (final item in _availableCustomizedStops) {
      item.dispose();
    }
    super.dispose();
  }

  Future<_BookingScreenData> _loadPackage() async {
    TourPackage? package;
    if (widget.initialPackage != null &&
        widget.initialPackage!.id == widget.packageId) {
      package = widget.initialPackage!;
    } else {
      package = await _repo.fetchTourPackage(widget.packageId);
    }
    if (package == null) throw StateError('Package not found.');
    final packageSpots = await _repo.fetchPackageSpots(package.id);
    return _BookingScreenData(package: package, packageSpots: packageSpots);
  }

  void _initializeItinerary(_BookingScreenData data) {
    if (_initializedItineraryForPackageId == data.package.id) return;
    _disposeItineraryCollections();
    _initializedItineraryForPackageId = data.package.id;

    final selectedRows = widget.customizedSpots.isNotEmpty
        ? widget.customizedSpots
        : data.packageSpots
              .indexed
              .map(
                (entry) => <String, dynamic>{
                  'spot_id': entry.$2.id,
                  'action_type': 'kept',
                  'google_place_id': entry.$2.googlePlaceId,
                  'spot_title': entry.$2.title,
                  'spot_address': entry.$2.address,
                  'municipality': entry.$2.municipality,
                  'barangay': entry.$2.barangay,
                  'latitude': entry.$2.latitude,
                  'longitude': entry.$2.longitude,
                  'image_url': entry.$2.imageUrl,
                  'sort_order': entry.$1,
                  'estimated_arrival_time': entry.$2.estimatedArrivalTime,
                  'estimated_duration_minutes': entry.$2.estimatedDurationMinutes,
                  'recommended_visit_duration_minutes':
                      entry.$2.recommendedVisitDurationMinutes,
                },
              )
              .toList(growable: false);

    final activeRows = selectedRows
        .where(
          (row) => row['action_type'] == 'kept' || row['action_type'] == 'added',
        )
        .toList(growable: false)
      ..sort(
        (a, b) => dbInt(a['sort_order']).compareTo(dbInt(b['sort_order'])),
      );
    final removedRows = selectedRows
        .where((row) => row['action_type'] == 'removed')
        .toList(growable: false);

    _aiSuggestedItinerary = _buildAiSuggestedItinerary(activeRows);
    _customizedDraftItinerary = _aiSuggestedItinerary
        .map(_EditableItineraryStop.cloneFrom)
        .toList(growable: true);
    _availableCustomizedStops = removedRows
        .map(
          (row) => _EditableItineraryStop.fromSourceRow(
            row,
            arrivalTime: '',
            stayMinutes: resolveItineraryStayMinutes(
              estimatedMinutes: dbInt(row['estimated_duration_minutes']),
              recommendedMinutes: dbInt(
                row['recommended_visit_duration_minutes'],
              ),
            ),
            departureTime: '',
            activityNote: _suggestActivityForDestination(
              dbString(row['spot_title']),
            ),
          ),
        )
        .toList(growable: true);
    _customizedItineraryDirty = false;
  }

  void _disposeItineraryCollections() {
    for (final item in _aiSuggestedItinerary) {
      item.dispose();
    }
    for (final item in _customizedDraftItinerary) {
      item.dispose();
    }
    for (final item in _availableCustomizedStops) {
      item.dispose();
    }
  }

  List<_EditableItineraryStop> _buildAiSuggestedItinerary(
    List<Map<String, dynamic>> rows,
  ) {
    var nextArrival = '09:00:00';
    return rows.indexed.map((entry) {
      final row = entry.$2;
      final arrival = dbTimeText(row['estimated_arrival_time']).isNotEmpty
          ? dbTimeText(row['estimated_arrival_time'])
          : nextArrival;
      final stayMinutes = resolveItineraryStayMinutes(
        estimatedMinutes: dbInt(row['estimated_duration_minutes']),
        recommendedMinutes: dbInt(row['recommended_visit_duration_minutes']),
      );
      final departure = addMinutesToScheduleTime(arrival, stayMinutes);
      nextArrival = addMinutesToScheduleTime(departure, 20);
      return _EditableItineraryStop.fromSourceRow(
        row,
        arrivalTime: arrival,
        stayMinutes: stayMinutes,
        departureTime: departure,
        activityNote: _suggestActivityForDestination(
          dbString(row['spot_title']),
        ),
      );
    }).toList(growable: false);
  }

  String _suggestActivityForDestination(String destinationName) {
    final name = destinationName.trim();
    final lower = name.toLowerCase();
    if (lower.contains('falls') ||
        lower.contains('spring') ||
        lower.contains('lake') ||
        lower.contains('river') ||
        lower.contains('dam')) {
      return 'Sightseeing, photo stop, and enjoy the natural scenery.';
    }
    if (lower.contains('church') ||
        lower.contains('museum') ||
        lower.contains('heritage') ||
        lower.contains('shrine')) {
      return 'Cultural visit, quiet exploration, and photo time.';
    }
    if (lower.contains('park') ||
        lower.contains('garden') ||
        lower.contains('farm') ||
        lower.contains('resort')) {
      return 'Walk around, take photos, and enjoy the surroundings.';
    }
    return 'Explore $name, take photos, and enjoy the suggested stop.';
  }

  List<_EditableItineraryStop> get _selectedItinerary {
    if (_itineraryMode == _ItineraryViewMode.customize) {
      return _customizedDraftItinerary;
    }
    return _aiSuggestedItinerary;
  }

  String get _selectedItineraryLabel =>
      _itineraryMode == _ItineraryViewMode.customize ? 'Customized' : 'AI Suggested';

  int get _selectedItineraryDurationMinutes {
    final itinerary = _selectedItinerary;
    if (itinerary.isEmpty) return 0;
    final start = itinerary.first.arrivalTime;
    final end = itinerary.last.departureTime;
    if (start.isNotEmpty && end.isNotEmpty) {
      return scheduleMinutesBetween(start, end);
    }
    return itinerary.fold<int>(
      0,
      (sum, item) => sum + item.stayMinutes,
    );
  }

  static List<String> _tourTimeOptions() {
    final result = <String>[];
    for (var m = _tourStartMinutes; m <= _tourEndMinutes; m += 15) {
      final h = m ~/ 60;
      final min = m % 60;
      result.add(
        '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}:00',
      );
    }
    return result;
  }

  Future<void> _pickItineraryTime(
    _EditableItineraryStop item, {
    required bool pickingArrival,
  }) async {
    final options = _tourTimeOptions();
    final current = pickingArrival ? item.arrivalTime : item.departureTime;

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _TimePickerSheet(
        title: pickingArrival ? 'Select Arrival Time' : 'Select Departure Time',
        options: options,
        selected: current,
      ),
    );

    if (picked == null) return;
    setState(() {
      if (pickingArrival) {
        item.arrivalTime = picked;
        item.departureTime = addMinutesToScheduleTime(
          item.arrivalTime,
          item.stayMinutes,
        );
      } else {
        item.departureTime = picked;
        if (item.arrivalTime.isNotEmpty) {
          final stay = scheduleMinutesBetween(
            item.arrivalTime,
            item.departureTime,
          );
          item.stayMinutes = stay > 0 ? stay : item.stayMinutes;
        }
      }
      _customizedItineraryDirty = true;
    });
  }

  int? _storageTimeToMinutes(String value) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})(?::\d{2})?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    return (int.parse(match.group(1)!) * 60) + int.parse(match.group(2)!);
  }

  void _moveCustomizedItineraryStop(int index, int delta) {
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= _customizedDraftItinerary.length) return;
    setState(() {
      final item = _customizedDraftItinerary.removeAt(index);
      _customizedDraftItinerary.insert(nextIndex, item);
      _customizedItineraryDirty = true;
    });
  }

  void _removeCustomizedItineraryStop(int index) {
    if (_customizedDraftItinerary.length <= 3) {
      _snack('At least 3 destinations are required in the itinerary.');
      return;
    }
    setState(() {
      final item = _customizedDraftItinerary.removeAt(index);
      _availableCustomizedStops = [..._availableCustomizedStops, item];
      _customizedItineraryDirty = true;
    });
  }

  Future<void> _showAddDestinationSheet() async {
    if (_availableCustomizedStops.isEmpty) {
      _snack('No more package destinations are available to add.');
      return;
    }
    if (_customizedDraftItinerary.length >= 6) {
      _snack('You can only include up to 6 destinations.');
      return;
    }

    final selected = await showModalBottomSheet<_EditableItineraryStop>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Destination',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'These destinations are allowed by the package customization setup.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              ..._availableCustomizedStops.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    item.destinationName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    item.destinationAddress.isEmpty
                        ? 'No address available'
                        : item.destinationAddress,
                  ),
                  trailing: const Icon(Icons.add_circle_rounded),
                  onTap: () => Navigator.pop(context, item),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected == null) return;
    setState(() {
      _availableCustomizedStops = _availableCustomizedStops
          .where((item) => item.localKey != selected.localKey)
          .toList(growable: false);
      if (selected.arrivalTime.isEmpty) {
        final lastDeparture = _customizedDraftItinerary.isEmpty
            ? '09:00:00'
            : _customizedDraftItinerary.last.departureTime;
        selected.arrivalTime = addMinutesToScheduleTime(lastDeparture, 20);
      }
      if (selected.departureTime.isEmpty) {
        selected.departureTime = addMinutesToScheduleTime(
          selected.arrivalTime,
          selected.stayMinutes,
        );
      }
      _customizedDraftItinerary = [..._customizedDraftItinerary, selected];
      _customizedItineraryDirty = true;
    });
  }

  bool _commitCustomizedItinerary() {
    if (_customizedDraftItinerary.length < 3) {
      _snack('Please keep at least 3 destinations in your customized itinerary.');
      return false;
    }
    if (_customizedDraftItinerary.length > 6) {
      _snack('You can only include up to 6 destinations.');
      return false;
    }
    for (final item in _customizedDraftItinerary) {
      if (item.arrivalTime.isEmpty || item.departureTime.isEmpty) {
        _snack(
          'Please set the arrival and departure time for ${item.destinationName}.',
        );
        return false;
      }
      if (item.stayMinutes <= 0) {
        _snack(
          'Please enter a valid estimated stay for ${item.destinationName}.',
        );
        return false;
      }
    }

    setState(() {
      _customizedItineraryDirty = false;
    });
    return true;
  }

  List<Json> _buildFinalItineraryPayload() {
    return _selectedItinerary.indexed
        .map(
          (entry) => entry.$2.toBookingPayload(
            order: entry.$1 + 1,
            sourceType: _itineraryMode == _ItineraryViewMode.customize
                ? 'customized'
                : 'ai_suggested',
          ),
        )
        .toList(growable: false);
  }

  // ── Notes builder ────────────────────────────────────────────────────────
  String _buildNotesSummary() {
    final parts = <String>[];

    final typedNotes = _notesCtrl.text.trim();
    if (typedNotes.isNotEmpty) parts.add(typedNotes);

    final type = _isSameDay ? 'Same-day Booking' : 'Advanced Booking (50% DP)';
    parts.add('Booking type: $type');
    parts.add(
      'Participants — Adults: $_adults, Children: $_children. '
      'Required tricycles: $_requiredTricycles.',
    );

    if (widget.customizedSpots.isNotEmpty) {
      final keptOrAdded = widget.customizedSpots
          .where(
            (r) => r['action_type'] == 'kept' || r['action_type'] == 'added',
          )
          .map((r) => r['spot_title']?.toString() ?? '')
          .where((v) => v.trim().isNotEmpty)
          .toList(growable: false);

      final removed = widget.customizedSpots
          .where((r) => r['action_type'] == 'removed')
          .map((r) => r['spot_title']?.toString() ?? '')
          .where((v) => v.trim().isNotEmpty)
          .toList(growable: false);

      if (keptOrAdded.isNotEmpty) {
        parts.add('Customized spots: ${keptOrAdded.join(', ')}');
      }
      if (removed.isNotEmpty) {
        parts.add('Removed spots: ${removed.join(', ')}');
      }
    }

    final finalItinerary = _selectedItinerary;
    if (finalItinerary.isNotEmpty) {
      parts.add('Final itinerary source: $_selectedItineraryLabel');
      parts.add(
        'Estimated tour duration: ${_formatDurationLabel(_selectedItineraryDurationMinutes)}',
      );
      parts.add(
        'Destination order: ${finalItinerary.map((item) => item.destinationName).join(' -> ')}',
      );
    }

    return parts.join('\n');
  }

  // ── Date picker ──────────────────────────────────────────────────────────
  String get _dateLabel {
    if (_selectedDate == null) return 'Select travel date';
    return DateFormat('EEEE, MMM d, yyyy').format(_selectedDate!);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final initialDate = _selectedDate ?? firstDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 2),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;

        final pickedIsToday =
            picked.year == now.year &&
            picked.month == now.month &&
            picked.day == now.day;

        if (!pickedIsToday && _payment == _PaymentMethod.cashPickup) {
          _payment = _PaymentMethod.gcash;
        }
      });
    }
  }

  // ── Confirm ──────────────────────────────────────────────────────────────
  Future<void> _confirm(TourPackage package) async {
    try {
      final hasActiveTour = await _repo.hasActiveTour();
      if (hasActiveTour) {
        _snack(TourisTrikeRepository.activeTourErrorMessage);
        return;
      }
    } catch (_) {
      _snack(
        'Unable to verify your current tour status right now. Please try again.',
      );
      return;
    }

    if (_selectedDate == null) {
      _snack('Please select a travel date.');
      return;
    }

    final passengerMessage = _passengerValidationMessage();
    if (passengerMessage != null) {
      _snack(passengerMessage);
      return;
    }

    final pickupValid = _selectedPickup != null &&
        _selectedPickup!.isValidWithinMunicipality;
    final dropoffValid = _selectedDropoff != null &&
        _selectedDropoff!.isValidWithinMunicipality;

    if (!pickupValid || !dropoffValid) {
      _snack(
        'Please select valid pickup and drop-off points before confirming your booking.',
      );
      return;
    }

    if (_itineraryMode == _ItineraryViewMode.customize &&
        !_commitCustomizedItinerary()) {
      return;
    }

    final dateAndTimeMessage = _dateAndTimeValidationMessage();
    if (dateAndTimeMessage != null) {
      _snack(dateAndTimeMessage);
      return;
    }

    final finalItinerary = _buildFinalItineraryPayload();
    if (finalItinerary.isEmpty) {
      _snack('Unable to prepare the itinerary for this booking.');
      return;
    }

    // Spot count validation for customized packages
    if (widget.customizedSpots.isNotEmpty) {
      final activeSpots = widget.customizedSpots
          .where(
            (s) => s['action_type'] == 'kept' || s['action_type'] == 'added',
          )
          .toList();
      if (activeSpots.length < 3) {
        _snack('Please select at least 3 spots for your tour package.');
        return;
      }
      if (activeSpots.length > 6) {
        _snack('You can only select up to 6 spots per package.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final total = _totalPrice(package);
      final downpayment = _downpaymentAmount(package);
      final remaining = _remainingBalance(package);
      final method = _payment == _PaymentMethod.cashPickup ? 'cash' : 'gcash';

      // Advanced + GCash bookings pay the down payment via PayMongo
      // Checkout before a driver is ever matched — the booking is created
      // hidden ('pending_payment') and only becomes visible to drivers
      // once that checkout resolves. Same-day bookings (cash or GCash,
      // full amount at pickup) are unaffected — see
      // docs/payment-architecture.md Phase C3 for why cash can't follow
      // this path (no digital trail until the driver is physically there).
      final needsUpfrontCheckout = method == 'gcash' && downpayment > 0;

      final booking = await _repo.createPackageBooking(
        packageId: package.id,
        travelDate: _selectedDate!,
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
        customizedSpots: widget.customizedSpots,
        itineraryItems: finalItinerary,
        requiredDrivers: _requiredTricycles,
        municipality: package.city,
        province: _packageProvince(package),
        totalPassengers: _totalParticipants,
        initialBookingStatus: needsUpfrontCheckout ? 'pending_payment' : 'waiting_for_drivers',
      );

      if (!mounted) return;

      if (needsUpfrontCheckout) {
        final paid = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => PaymentCheckoutScreen(
              bookingId: booking.id,
              paymentStage: 'down_payment',
              amount: downpayment,
              description: 'Down payment for package booking #${booking.id}',
              allowCancelBooking: true,
            ),
          ),
        );
        if (!mounted) return;
        if (paid == true) {
          _navigateToActivityTracking(booking.id.toString());
        }
        // paid != true: tourist cancelled or backed out — stay on this
        // screen so they can adjust and retry. The booking itself was
        // already cancelled by PaymentCheckoutScreen if they chose to.
        return;
      }

      _navigateToActivityTracking(booking.id.toString());
    } catch (e) {
      if (!mounted) return;
      _snack('Unable to create booking: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? const Color(0xFFDC2626) : null,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: FutureBuilder<_BookingScreenData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF2A86FF)),
            );
          }
          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _future = _loadPackage()),
            );
          }

          final data = snapshot.data!;
          final package = data.package;
          _initializeItinerary(data);
          final totalPrice = _totalPrice(package);
          final downpayment = _downpaymentAmount(package);
          final remaining = _remainingBalance(package);
          final amountToPayNow = _amountToPayNow(package);
          final bottom = MediaQuery.of(context).padding.bottom;

          return SafeArea(
            bottom: false,
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(18, 12, 18, 120 + bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          _CircleButton(
                            icon: Icons.arrow_back_rounded,
                            onTap: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Confirm Booking',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 56),
                        ],
                      ),
                      const SizedBox(height: 18),

                      _PackageSummary(package: package),
                      const SizedBox(height: 22),

                      // ── Date ──────────────────────────────────────────
                      const _SectionTitle('Select Date'),
                      const SizedBox(height: 10),
                      _FieldButton(
                        icon: Icons.calendar_month_rounded,
                        text: _dateLabel,
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: 22),

                      // ── Participants ───────────────────────────────────
                      const _SectionTitle('Participants'),
                      const SizedBox(height: 10),
                      _ParticipantsCard(
                        adults: _adults,
                        children: _children,
                        onAdultsMinus: _adults <= 1
                            ? null
                            : () => setState(() => _adults--),
                        onAdultsPlus: () => setState(() => _adults++),
                        onChildrenMinus: _children <= 0
                            ? null
                            : () => setState(() => _children--),
                        onChildrenPlus: () => setState(() => _children++),
                      ),
                      const SizedBox(height: 22),

                      // ── Pickup and Drop-off (combined) ─────────────────
                      const _SectionTitle(
                        'Select Pickup Point and Drop-off Point',
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFDCE8F8)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF16A34A),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Pickup Point',
                                        style: TextStyle(
                                          color: Color(0xFF0F172A),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Where should the driver pick you up?',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  _LocationPickerCard(
                                    label: 'Pickup',
                                    showUseCurrentLocation: true,
                                    showMapPreview: false,
                                    requiredMunicipality: package.city,
                                    requiredProvince:
                                        _packageProvince(package),
                                    errorText: _pickupLocationError,
                                    onValidationMessageChanged: (message) {
                                      if (!mounted) return;
                                      setState(
                                        () =>
                                            _pickupLocationError = message,
                                      );
                                    },
                                    onLocationSelected: _onPickupSelected,
                                  ),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Divider(
                                height: 1,
                                color: Color(0xFFE7EEF7),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFDC2626),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Drop-off Point',
                                        style: TextStyle(
                                          color: Color(0xFF0F172A),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Where should the driver drop you off after the tour?',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  _LocationPickerCard(
                                    label: 'Drop-off',
                                    showUseCurrentLocation: true,
                                    showMapPreview: false,
                                    requiredMunicipality: package.city,
                                    requiredProvince:
                                        _packageProvince(package),
                                    errorText: _dropoffLocationError,
                                    onValidationMessageChanged: (message) {
                                      if (!mounted) return;
                                      setState(
                                        () =>
                                            _dropoffLocationError = message,
                                      );
                                    },
                                    onLocationSelected: _onDropoffSelected,
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: _SharedRouteMapPreview(
                                pickupAddress: _selectedPickup?.address,
                                pickupLat: _selectedPickup?.latitude,
                                pickupLng: _selectedPickup?.longitude,
                                dropoffAddress: _selectedDropoff?.address,
                                dropoffLat: _selectedDropoff?.latitude,
                                dropoffLng: _selectedDropoff?.longitude,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // ── Booking Summary (live) ─────────────────────────
                      const _SectionTitle('Itinerary'),
                      const SizedBox(height: 10),
                      _ItineraryModeToggle(
                        selected: _itineraryMode,
                        onChanged: (mode) =>
                            setState(() => _itineraryMode = mode),
                      ),
                      const SizedBox(height: 12),
                      if (_itineraryMode == _ItineraryViewMode.aiSuggested)
                        _ReadOnlyItineraryCard(
                          label: 'AI Suggested Itinerary',
                          description:
                              'TourisTrike automatically generated this route from your selected package spots.',
                          items: _aiSuggestedItinerary,
                          sourceType: 'ai_suggested',
                          totalDurationLabel: _formatDurationLabel(
                            _calculateDurationMinutes(_aiSuggestedItinerary),
                          ),
                        )
                      else
                        _EditableItineraryCard(
                          items: _customizedDraftItinerary,
                          availableStopsCount: _availableCustomizedStops.length,
                          hasUnsavedChanges: _customizedItineraryDirty,
                          currentDurationLabel: _formatDurationLabel(
                            _calculateDurationMinutes(_customizedDraftItinerary),
                          ),
                          onPickArrival: (item) =>
                              _pickItineraryTime(item, pickingArrival: true),
                          onPickDeparture: (item) =>
                              _pickItineraryTime(item, pickingArrival: false),
                          onStayChanged: (item, minutes) {
                            setState(() {
                              item.stayMinutes = minutes;
                              if (item.arrivalTime.isNotEmpty) {
                                item.departureTime = addMinutesToScheduleTime(
                                  item.arrivalTime,
                                  item.stayMinutes,
                                );
                              }
                              _customizedItineraryDirty = true;
                            });
                          },
                          onMoveUp: (index) =>
                              _moveCustomizedItineraryStop(index, -1),
                          onMoveDown: (index) =>
                              _moveCustomizedItineraryStop(index, 1),
                          onRemove: _removeCustomizedItineraryStop,
                          onAddDestination: _showAddDestinationSheet,
                        ),
                      const SizedBox(height: 22),

                      const _SectionTitle('Booking Summary'),
                      const SizedBox(height: 10),
                      _BookingSummaryCard(
                        hasDate: _selectedDate != null,
                        isSameDay: _isSameDay,
                        selectedDate: _selectedDate,
                        adults: _adults,
                        children: _children,
                        totalParticipants: _totalParticipants,
                        requiredTricycles: _requiredTricycles,
                        totalPrice: totalPrice,
                        downpaymentAmount: downpayment,
                        remainingBalance: remaining,
                        amountToPayNow: amountToPayNow,
                        isCustomizedPrice: widget.customizedUnitPrice != null,
                        itinerarySourceLabel: _selectedItineraryLabel,
                        estimatedTourDurationLabel: _formatDurationLabel(
                          _selectedItineraryDurationMinutes,
                        ),
                        itineraryItems: _selectedItinerary,
                      ),
                      const SizedBox(height: 22),

                      // ── Payment method ─────────────────────────────────
                      const _SectionTitle('Payment Method'),
                      const SizedBox(height: 10),

                      _PaymentCard(
                        selected: _payment == _PaymentMethod.cashPickup,
                        enabled: _selectedDate != null && _isSameDay,
                        icon: Icons.payments_outlined,
                        title: 'Cash on Pick-up',
                        subtitle: _selectedDate == null
                            ? 'Select a date first.'
                            : _isSameDay
                            ? 'Pay your driver when they arrive for the tour.'
                            : 'Only available for same-day bookings.',
                        onTap: () {
                          if (_selectedDate != null && _isSameDay) {
                            setState(
                              () => _payment = _PaymentMethod.cashPickup,
                            );
                          }
                        },
                      ),

                      const SizedBox(height: 10),

                      _PaymentCard(
                        selected: _payment == _PaymentMethod.gcash,
                        enabled: _selectedDate != null,
                        icon: Icons.qr_code_2_rounded,
                        title: 'GCash',
                        subtitle: _selectedDate == null
                            ? 'Select a date first.'
                            : _isSameDay
                            ? 'Scan the driver\'s GCash QR and pay the full amount.'
                            : 'Pay the driver\'s GCash QR: down payment once a driver accepts, remaining balance at the end of the tour.',
                        onTap: () {
                          if (_selectedDate != null) {
                            setState(() => _payment = _PaymentMethod.gcash);
                          }
                        },
                      ),

                      const SizedBox(height: 10),

                      Text(
                        _selectedDate == null
                            ? 'Note: Select a travel date to see available payment options.'
                            : _isSameDay
                            ? 'Note: Same-day bookings pay the full amount, in cash or GCash, directly to the driver.'
                            : 'Note: Advanced bookings pay a 50% down payment once a driver accepts, and the remaining balance at the end of the tour — in cash or GCash, directly to the driver. TourisTrike never holds this money.',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 22),

                      // ── Notes ──────────────────────────────────────────
                      const _SectionTitle('Notes'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notesCtrl,
                        minLines: 4,
                        maxLines: 7,
                        decoration: InputDecoration(
                          hintText:
                              'Optional requests for the city tourism office',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                              color: Color(0xFFE7EEF7),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                              color: Color(0xFFE7EEF7),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom bar
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _BottomBar(
                    hasDate: _selectedDate != null,
                    isSameDay: _isSameDay,
                    amountToPayNow: amountToPayNow,
                    saving: _saving,
                    onConfirm: () => _confirm(package),
                    blockingMessage: _confirmationBlockingMessage(package),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
// This is only a payment-method preference recorded on the booking; no funds
// are captured here. The actual GCash-to-driver payment happens once a driver
// is assigned (down payment) and again at tour completion (remaining balance).
enum _PaymentMethod { cashPickup, gcash }

enum _ItineraryViewMode { aiSuggested, customize }

class _BookingScreenData {
  const _BookingScreenData({
    required this.package,
    required this.packageSpots,
  });

  final TourPackage package;
  final List<TouristSpot> packageSpots;
}

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
    required String activityNote,
  }) : activityController = TextEditingController(text: activityNote);

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
  final TextEditingController activityController;

  factory _EditableItineraryStop.fromSourceRow(
    Map<String, dynamic> row, {
    required String arrivalTime,
    required int stayMinutes,
    required String departureTime,
    required String activityNote,
  }) {
    final googlePlaceId = dbString(row['google_place_id']);
    final spotId = row['spot_id'];
    final name = dbString(row['spot_title']);
    return _EditableItineraryStop(
      localKey: googlePlaceId.isNotEmpty
          ? 'google:$googlePlaceId'
          : spotId != null
          ? 'spot:$spotId'
          : 'title:${name.toLowerCase()}',
      spotId: spotId,
      googlePlaceId: googlePlaceId,
      destinationName: name,
      destinationAddress: dbString(row['spot_address']),
      municipality: dbString(row['municipality']),
      barangay: dbString(row['barangay']),
      latitude: dbDouble(row['latitude']),
      longitude: dbDouble(row['longitude']),
      imageUrl: dbString(row['image_url']),
      arrivalTime: arrivalTime,
      stayMinutes: stayMinutes,
      departureTime: departureTime,
      activityNote: activityNote,
    );
  }

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
      activityNote: other.activityController.text.trim(),
    );
  }

  Json toBookingPayload({
    required int order,
    required String sourceType,
  }) {
    return {
      'spot_id': spotId,
      'destination_name': destinationName,
      'destination_address': destinationAddress,
      'order_number': order,
      'destination_order': order,
      'arrival_time': arrivalTime,
      'estimated_stay_duration_minutes': stayMinutes,
      'departure_time': departureTime,
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

  void dispose() {
    activityController.dispose();
  }
}

int _calculateDurationMinutes(List<_EditableItineraryStop> items) {
  if (items.isEmpty) return 0;
  final start = items.first.arrivalTime;
  final end = items.last.departureTime;
  if (start.isNotEmpty && end.isNotEmpty) {
    return scheduleMinutesBetween(start, end);
  }
  return items.fold<int>(0, (sum, item) => sum + item.stayMinutes);
}

String _formatDurationLabel(int minutes) {
  if (minutes <= 0) return 'Not available yet';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours <= 0) return '${remainder}m';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}

String _normalizeLocationName(String value) {
  var normalized = value.toLowerCase().trim();
  normalized = normalized.replaceAll(
    RegExp(r'\b(city|municipality|province)\s+of\b'),
    '',
  );
  normalized = normalized.replaceAll(
    RegExp(r'\b(city|municipality|province)\b'),
    '',
  );
  normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized;
}

bool _locationNamesMatch(String actual, String expected) {
  final normalizedActual = _normalizeLocationName(actual);
  final normalizedExpected = _normalizeLocationName(expected);
  if (normalizedActual.isEmpty || normalizedExpected.isEmpty) {
    return false;
  }
  return normalizedActual == normalizedExpected ||
      normalizedActual.contains(normalizedExpected) ||
      normalizedExpected.contains(normalizedActual);
}

bool _addressContainsLocation(String address, String expected) {
  final normalizedAddress = _normalizeLocationName(address);
  final normalizedExpected = _normalizeLocationName(expected);
  if (normalizedAddress.isEmpty || normalizedExpected.isEmpty) {
    return false;
  }
  return normalizedAddress.contains(normalizedExpected);
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
    if (types.contains('country') && countryCode.isEmpty) {
      countryCode = shortName;
    }
    if (types.contains('administrative_area_level_1') && province.isEmpty) {
      province = longName;
    }
    if ((types.contains('locality') ||
            types.contains('administrative_area_level_2') ||
            types.contains('administrative_area_level_3')) &&
        locality.isEmpty) {
      locality = longName;
    }
  }

  return _ParsedAddressComponents(
    countryCode: countryCode,
    province: province,
    locality: locality,
  );
}

String _itineraryTimingSummary({
  required String arrivalTime,
  required int stayMinutes,
  required String departureTime,
}) {
  final parts = <String>[];
  if (arrivalTime.isNotEmpty) {
    parts.add('Arrival ${formatScheduleTimeLabel(arrivalTime)}');
  }
  if (stayMinutes > 0) {
    parts.add('Stay ${_formatDurationLabel(stayMinutes)}');
  }
  if (departureTime.isNotEmpty) {
    parts.add('Departure ${formatScheduleTimeLabel(departureTime)}');
  }
  return parts.join(' • ');
}

class _ItineraryModeToggle extends StatelessWidget {
  const _ItineraryModeToggle({
    required this.selected,
    required this.onChanged,
  });

  final _ItineraryViewMode selected;
  final ValueChanged<_ItineraryViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ItineraryModeChip(
              label: 'AI Suggested',
              selected: selected == _ItineraryViewMode.aiSuggested,
              onTap: () => onChanged(_ItineraryViewMode.aiSuggested),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ItineraryModeChip(
              label: 'Customize',
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
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected
                ? const Color(0xFF0F172A)
                : const Color(0xFF47617E),
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyItineraryCard extends StatelessWidget {
  const _ReadOnlyItineraryCard({
    required this.label,
    required this.description,
    required this.items,
    required this.sourceType,
    required this.totalDurationLabel,
  });

  final String label;
  final String description;
  final List<_EditableItineraryStop> items;
  final String sourceType;
  final String totalDurationLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE8F8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF2A86FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                totalDurationLabel,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          ...items.indexed.map(
            (entry) => Padding(
              padding: EdgeInsets.only(bottom: entry.$1 == items.length - 1 ? 0 : 12),
              child: _ItineraryPreviewTile(
                index: entry.$1 + 1,
                item: entry.$2,
                sourceType: sourceType,
              ),
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
    required this.availableStopsCount,
    required this.hasUnsavedChanges,
    required this.currentDurationLabel,
    required this.onPickArrival,
    required this.onPickDeparture,
    required this.onStayChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
    required this.onAddDestination,
  });

  final List<_EditableItineraryStop> items;
  final int availableStopsCount;
  final bool hasUnsavedChanges;
  final String currentDurationLabel;
  final ValueChanged<_EditableItineraryStop> onPickArrival;
  final ValueChanged<_EditableItineraryStop> onPickDeparture;
  final void Function(_EditableItineraryStop item, int minutes) onStayChanged;
  final ValueChanged<int> onMoveUp;
  final ValueChanged<int> onMoveDown;
  final ValueChanged<int> onRemove;
  final VoidCallback onAddDestination;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE8F8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Customized Itinerary',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAddDestination,
                icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                label: Text(
                  availableStopsCount > 0
                      ? 'Add ($availableStopsCount)'
                      : 'Add',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasUnsavedChanges
                ? 'Your latest changes will be saved when you tap Confirm Booking.'
                : 'Edit the order, time, and estimated stay for your preferred route.',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Current estimated duration: $currentDurationLabel',
            style: const TextStyle(
              color: Color(0xFF2A86FF),
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 16),
          ...items.indexed.map(
            (entry) => Padding(
              padding: EdgeInsets.only(bottom: entry.$1 == items.length - 1 ? 0 : 14),
              child: _EditableItineraryTile(
                index: entry.$1,
                item: entry.$2,
                totalItems: items.length,
                onPickArrival: () => onPickArrival(entry.$2),
                onPickDeparture: () => onPickDeparture(entry.$2),
                onStayChanged: (minutes) => onStayChanged(entry.$2, minutes),
                onMoveUp: () => onMoveUp(entry.$1),
                onMoveDown: () => onMoveDown(entry.$1),
                onRemove: () => onRemove(entry.$1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItineraryPreviewTile extends StatelessWidget {
  const _ItineraryPreviewTile({
    required this.index,
    required this.item,
    required this.sourceType,
  });

  final int index;
  final _EditableItineraryStop item;
  final String sourceType;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2ECFA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: const TextStyle(
                    color: Color(0xFF2A86FF),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.destinationName,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: sourceType == 'customized'
                      ? const Color(0xFFFFF7ED)
                      : const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  sourceType == 'customized' ? 'Customized' : 'AI',
                  style: TextStyle(
                    color: sourceType == 'customized'
                        ? const Color(0xFFEA580C)
                        : const Color(0xFF2A86FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _itineraryTimingSummary(
              arrivalTime: item.arrivalTime,
              stayMinutes: item.stayMinutes,
              departureTime: item.departureTime,
            ),
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
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
    required this.item,
    required this.totalItems,
    required this.onPickArrival,
    required this.onPickDeparture,
    required this.onStayChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final int index;
  final _EditableItineraryStop item;
  final int totalItems;
  final VoidCallback onPickArrival;
  final VoidCallback onPickDeparture;
  final ValueChanged<int> onStayChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2ECFA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF2A86FF),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.destinationName,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Move up',
                onPressed: index == 0 ? null : onMoveUp,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              IconButton(
                tooltip: 'Move down',
                onPressed: index == totalItems - 1 ? null : onMoveDown,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              IconButton(
                tooltip: 'Remove destination',
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: const Color(0xFFDC2626),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _EditableTimeButton(
                  label: 'Arrival',
                  value: item.arrivalTime.isEmpty
                      ? 'Set time'
                      : formatScheduleTimeLabel(item.arrivalTime),
                  onTap: onPickArrival,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EditableTimeButton(
                  label: 'Departure',
                  value: item.departureTime.isEmpty
                      ? 'Set time'
                      : formatScheduleTimeLabel(item.departureTime),
                  onTap: onPickDeparture,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: '${item.stayMinutes}',
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final minutes = int.tryParse(value.trim());
              if (minutes != null && minutes > 0) {
                onStayChanged(minutes);
              }
            },
            decoration: InputDecoration(
              labelText: 'Estimated Stay (minutes)',
              hintText: 'Enter estimated stay in minutes',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7EEF7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Location picker card
// ============================================================================

class _LocationPickerCard extends StatefulWidget {
  const _LocationPickerCard({
    required this.label,
    required this.onLocationSelected,
    required this.requiredMunicipality,
    required this.requiredProvince,
    this.showUseCurrentLocation = true,
    this.showMapPreview = true,
    this.errorText,
    this.onValidationMessageChanged,
  });

  final String label;
  final String requiredMunicipality;
  final String requiredProvince;
  final bool showUseCurrentLocation;
  final bool showMapPreview;
  final String? errorText;
  final ValueChanged<String?>? onValidationMessageChanged;
  final void Function(String? address, double? lat, double? lng)
  onLocationSelected;

  @override
  State<_LocationPickerCard> createState() => _LocationPickerCardState();
}

class _LocationPickerCardState extends State<_LocationPickerCard> {
  static final _apiKey = CitySpotSuggestionService.resolveApiKey();

  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  List<_AutocompleteResult> _suggestions = [];
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

  // ── Autocomplete search ──────────────────────────────────────────────────
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _fetchSuggestions(query.trim()),
    );
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    setState(() => _loadingSuggestions = true);
    try {
      final scopedQuery =
          '$query, ${widget.requiredMunicipality}, ${widget.requiredProvince}, Philippines';
      final encoded = Uri.encodeQueryComponent(scopedQuery);
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=$encoded'
        '&key=$_apiKey'
        '&components=country:ph'
        '&language=en',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final preds = (body['predictions'] as List?) ?? const [];
        setState(() {
          _suggestions = preds
              .map(
                (p) => _AutocompleteResult(
                  placeId: p['place_id'] as String? ?? '',
                  description: p['description'] as String? ?? '',
                ),
              )
              .where((r) => r.placeId.isNotEmpty)
              .take(5)
              .toList();
        });
      }
    } catch (_) {
      // ignore network errors silently
    } finally {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  Future<void> _selectSuggestion(_AutocompleteResult suggestion) async {
    _focusNode.unfocus();
    setState(() {
      _suggestions = [];
      _loadingDetails = true;
    });
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${suggestion.placeId}'
        '&fields=geometry,formatted_address,address_components,name'
        '&key=$_apiKey',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
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
          final validationMessage = _locationValidationMessage(
            address: address,
            countryCode: components.countryCode,
            province: components.province,
            locality: components.locality,
          );
          if (validationMessage != null) {
            _invalidateSelection(validationMessage);
            return;
          }
          _setLocation(address, lat, lng);
          return;
        }
      }
      _invalidateSelection(
        'Unable to verify this location. Please choose another pickup/drop-off point.',
      );
    } catch (_) {
      _invalidateSelection(
        'Unable to verify this location. Please choose another pickup/drop-off point.',
      );
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  // ── Use current location ─────────────────────────────────────────────────
  Future<void> _useCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showError(
          'Location services are disabled. Please enable them in device settings.',
        );
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
      if (!mounted) return;
      final address = await _reverseGeocode(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      final validationMessage = _locationValidationMessage(
        address: address,
        countryCode:
            _addressContainsLocation(address, 'Philippines') ? 'PH' : '',
      );
      if (validationMessage != null) {
        _invalidateSelection(validationMessage);
        return;
      }
      _searchCtrl.text = address;
      _setLocation(address, position.latitude, position.longitude);
    } catch (_) {
      if (mounted) {
        _showError('Could not get current location. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
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
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final results = (body['results'] as List?) ?? const [];
        if (results.isNotEmpty) {
          return results.first['formatted_address'] as String? ??
              '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
        }
      }
    } catch (_) {}
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  // ── Set location ─────────────────────────────────────────────────────────
  void _setLocation(String address, double lat, double lng) {
    _searchCtrl.text = address;
    setState(() {
      _selectedAddress = address;
      _selectedLat = lat;
      _selectedLng = lng;
      _suggestions = [];
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
      _suggestions = [];
    });
    widget.onValidationMessageChanged?.call(null);
    widget.onLocationSelected(null, null, null);
  }

  void _invalidateSelection(String message) {
    _searchCtrl.clear();
    setState(() {
      _selectedAddress = null;
      _selectedLat = null;
      _selectedLng = null;
      _suggestions = [];
    });
    widget.onValidationMessageChanged?.call(message);
    widget.onLocationSelected(null, null, null);
    _showError(message);
  }

  String? _locationValidationMessage({
    required String address,
    String countryCode = '',
    String province = '',
    String locality = '',
  }) {
    final normalizedCountry = countryCode.trim().toUpperCase();
    final isPhilippines = normalizedCountry == 'PH' ||
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

    final fallbackAddressMatches =
        _addressContainsLocation(address, widget.requiredMunicipality) &&
        _addressContainsLocation(address, widget.requiredProvince) &&
        _addressContainsLocation(address, 'Philippines');
    if (fallbackAddressMatches) {
      return null;
    }

    final provinceMatches = structuredProvinceMatches ||
        _addressContainsLocation(address, widget.requiredProvince);
    final localityMatches = structuredLocalityMatches ||
        _addressContainsLocation(address, widget.requiredMunicipality);

    if (!provinceMatches || !localityMatches) {
      return 'Please select a pickup/drop-off point within ${widget.requiredMunicipality}, ${widget.requiredProvince}.';
    }

    return null;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _staticMapUrl(double lat, double lng) {
    final marker = '$lat,$lng';
    final encodedMarker = Uri.encodeComponent(marker);
    return 'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$encodedMarker'
        '&zoom=15'
        '&size=640x320'
        '&scale=2'
        '&maptype=roadmap'
        '&markers=color:red%7C$encodedMarker'
        '&key=$_apiKey';
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = _selectedLat != null;
    final isBusy = _loadingDetails || _loadingLocation;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasLocation
              ? const Color(0xFF86EFAC)
              : const Color(0xFFE7EEF7),
          width: hasLocation ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Search field ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _focusNode,
              onChanged: _onSearchChanged,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Search ${widget.label.toLowerCase()} location...',
                hintStyle: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF2A86FF),
                ),
                suffixIcon: isBusy
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF2A86FF),
                          ),
                        ),
                      )
                    : _loadingSuggestions
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      )
                    : _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear_rounded,
                          color: Color(0xFF94A3B8),
                        ),
                        onPressed: _clearLocation,
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF8FAFF),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF2A86FF),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // ── Suggestion list ────────────────────────────────────────────
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE7EEF7)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: _suggestions.asMap().entries.map((entry) {
                  final i = entry.key;
                  final s = entry.value;
                  return InkWell(
                    onTap: () => _selectSuggestion(s),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        border: i < _suggestions.length - 1
                            ? const Border(
                                bottom: BorderSide(color: Color(0xFFEEF2F7)),
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF2FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.place_rounded,
                              color: Color(0xFF2A86FF),
                              size: 17,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.description,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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

          // ── Use current location ───────────────────────────────────────
          if (widget.showUseCurrentLocation) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: InkWell(
                onTap: _loadingLocation ? null : _useCurrentLocation,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loadingLocation)
                        const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF2A86FF),
                          ),
                        )
                      else
                        const Icon(
                          Icons.my_location_rounded,
                          color: Color(0xFF2A86FF),
                          size: 17,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        _loadingLocation
                            ? 'Getting location...'
                            : 'Use Current Location',
                        style: const TextStyle(
                          color: Color(0xFF2A86FF),
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // ── Map preview (static) ───────────────────────────────────────
          if (hasLocation && widget.showMapPreview) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  _staticMapUrl(_selectedLat!, _selectedLng!),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 200,
                      color: const Color(0xFFF1F5F9),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF2A86FF),
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],

          // ── Selected address chip ──────────────────────────────────────
          if (_selectedAddress != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF16A34A),
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _selectedAddress!,
                      style: const TextStyle(
                        color: Color(0xFF15803D),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (widget.errorText != null && widget.errorText!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                widget.errorText!,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

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

class _SharedRouteMapPreview extends StatelessWidget {
  const _SharedRouteMapPreview({
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffAddress,
    required this.dropoffLat,
    required this.dropoffLng,
  });

  static final _apiKey = CitySpotSuggestionService.resolveApiKey();

  final String? pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final String? dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;

  String _staticMapUrl() {
    final params = StringBuffer(
      'https://maps.googleapis.com/maps/api/staticmap'
      '?size=800x360&scale=2&maptype=roadmap&key=$_apiKey',
    );
    if (pickupLat != null && pickupLng != null) {
      params.write(
        '&markers=color:green%7Clabel:P%7C$pickupLat,$pickupLng',
      );
    }
    if (dropoffLat != null && dropoffLng != null) {
      params.write(
        '&markers=color:red%7Clabel:D%7C$dropoffLat,$dropoffLng',
      );
    }
    return params.toString();
  }

  @override
  Widget build(BuildContext context) {
    final hasBoth = pickupLat != null &&
        pickupLng != null &&
        dropoffLat != null &&
        dropoffLng != null;

    if (!hasBoth) {
      final hasPickup = pickupLat != null && pickupLng != null;
      final hasDropoff = dropoffLat != null && dropoffLng != null;
      final msg = !hasPickup && !hasDropoff
          ? 'Select both locations above to see the map preview.'
          : !hasPickup
          ? 'Select your pickup point to show the map preview.'
          : 'Select your drop-off point to show the map preview.';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7EEF7)),
        ),
        child: Row(
          children: [
            const Icon(Icons.map_outlined, color: Color(0xFF94A3B8), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(
            _staticMapUrl(),
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Container(
                height: 200,
                color: const Color(0xFFF1F5F9),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF2A86FF),
                    strokeWidth: 2,
                  ),
                ),
              );
            },
            errorBuilder: (_, _, _) => Container(
              height: 200,
              color: const Color(0xFFF1F5F9),
              alignment: Alignment.center,
              child: const Text(
                'Map preview unavailable',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (pickupAddress != null && pickupAddress!.isNotEmpty)
          _MapLegendRow(
            color: const Color(0xFF16A34A),
            label: 'Pickup',
            value: pickupAddress!,
          ),
        if (dropoffAddress != null && dropoffAddress!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _MapLegendRow(
              color: const Color(0xFFDC2626),
              label: 'Drop-off',
              value: dropoffAddress!,
            ),
          ),
      ],
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
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label: $value',
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Booking Summary Card
// ============================================================================

class _BookingSummaryCard extends StatelessWidget {
  const _BookingSummaryCard({
    required this.hasDate,
    required this.isSameDay,
    required this.selectedDate,
    required this.adults,
    required this.children,
    required this.totalParticipants,
    required this.requiredTricycles,
    required this.totalPrice,
    required this.downpaymentAmount,
    required this.remainingBalance,
    required this.amountToPayNow,
    required this.isCustomizedPrice,
    required this.itinerarySourceLabel,
    required this.estimatedTourDurationLabel,
    required this.itineraryItems,
  });

  final bool hasDate;
  final bool isSameDay;
  final DateTime? selectedDate;
  final int adults;
  final int children;
  final int totalParticipants;
  final int requiredTricycles;
  final double totalPrice;
  final double downpaymentAmount;
  final double remainingBalance;
  final double amountToPayNow;
  final bool isCustomizedPrice;
  final String itinerarySourceLabel;
  final String estimatedTourDurationLabel;
  final List<_EditableItineraryStop> itineraryItems;

  @override
  Widget build(BuildContext context) {
    if (!hasDate) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7EEF7)),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: Color(0xFF2A86FF),
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Select a travel date above to see your complete booking summary.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);
    final accent = isSameDay
        ? const Color(0xFF16A34A)
        : const Color(0xFF2A86FF);
    final accentLight = isSameDay
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFEAF2FF);
    final accentBorder = isSameDay
        ? const Color(0xFF86EFAC)
        : const Color(0xFFBBD7FF);
    final cardBorder = isSameDay
        ? const Color(0xFF86EFAC)
        : const Color(0xFFBBD7FF);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: accentLight,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: accentBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSameDay
                                ? Icons.bolt_rounded
                                : Icons.calendar_today_rounded,
                            size: 14,
                            color: accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isSameDay ? 'Same-day Booking' : 'Advanced Booking',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(selectedDate!),
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                if (!isSameDay) ...[
                  const SizedBox(height: 4),
                  const Text(
                    '50% down payment is required for advanced bookings.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Full payment is required for same-day bookings.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const _Divider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _GroupLabel('ITINERARY'),
                const SizedBox(height: 10),
                _DetailRow(
                  label: 'Selected Itinerary',
                  value: itinerarySourceLabel,
                  bold: true,
                ),
                const SizedBox(height: 6),
                _DetailRow(
                  label: 'Estimated Tour Duration',
                  value: estimatedTourDurationLabel,
                ),
                if (itineraryItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...itineraryItems.indexed.map(
                    (entry) => Padding(
                      padding: EdgeInsets.only(
                        bottom: entry.$1 == itineraryItems.length - 1 ? 0 : 8,
                      ),
                      child: _SummaryItineraryRow(
                        index: entry.$1 + 1,
                        item: entry.$2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const _Divider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _GroupLabel('PARTICIPANTS'),
                const SizedBox(height: 10),
                _DetailRow(label: 'Adults', value: '$adults'),
                const SizedBox(height: 6),
                _DetailRow(label: 'Children', value: '$children'),
                const SizedBox(height: 8),
                _DetailRow(
                  label: 'Total Participants',
                  value: '$totalParticipants',
                  bold: true,
                ),
                const SizedBox(height: 6),
                _DetailRow(
                  label: 'Required Tricycles',
                  value:
                      '$requiredTricycles tricycle${requiredTricycles == 1 ? '' : 's'}',
                  bold: true,
                  valueColor: const Color(0xFF2A86FF),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1 tricycle = maximum of 2 persons',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),

          const _Divider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _GroupLabel('PRICE BREAKDOWN'),
                const SizedBox(height: 10),
                _DetailRow(
                  label: isCustomizedPrice
                      ? 'Customized Package Price'
                      : 'Total Package Price',
                  value: money.format(totalPrice),
                  bold: true,
                ),
                if (!isSameDay) ...[
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: 'Down Payment (50%)',
                    value: money.format(downpaymentAmount),
                    valueColor: const Color(0xFF2A86FF),
                  ),
                  const SizedBox(height: 6),
                  _DetailRow(
                    label: 'Remaining Balance',
                    value: money.format(remainingBalance),
                    valueColor: const Color(0xFFDC2626),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: const Text(
                      'The remaining balance is paid on the day of the tour when the driver arrives.',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: accentLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accentBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Amount to Pay Now',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isSameDay
                              ? 'Full payment — no remaining balance'
                              : '50% down payment',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    money.format(amountToPayNow),
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
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

class _SummaryItineraryRow extends StatelessWidget {
  const _SummaryItineraryRow({
    required this.index,
    required this.item,
  });

  final int index;
  final _EditableItineraryStop item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2ECFA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$index. ${item.destinationName}',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _itineraryTimingSummary(
              arrivalTime: item.arrivalTime,
              stayMinutes: item.stayMinutes,
              departureTime: item.departureTime,
            ),
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Participants card (Adults + Children counters)
// ============================================================================

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
    return _Card(
      child: Column(
        children: [
          _CounterRow(
            icon: Icons.person_rounded,
            label: 'Adults',
            sublabel: 'Ages 13 and above',
            value: adults,
            onMinus: onAdultsMinus,
            onPlus: onAdultsPlus,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFE7EEF7)),
          ),
          _CounterRow(
            icon: Icons.child_care_rounded,
            label: 'Children',
            sublabel: 'Ages 12 and below',
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF2A86FF), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                sublabel,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _RoundButton(icon: Icons.remove_rounded, onTap: onMinus),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            '$value',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        _RoundButton(icon: Icons.add_rounded, onTap: onPlus, filled: true),
      ],
    );
  }
}

// ============================================================================
// Small detail helpers inside summary card
// ============================================================================

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontWeight: FontWeight.w900,
        fontSize: 11,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: bold ? const Color(0xFF0F172A) : const Color(0xFF64748B),
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            fontSize: bold ? 14 : 13.5,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? const Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: bold ? 15 : 14,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, color: Color(0xFFE7EEF7));
  }
}

// ============================================================================
// Package summary card
// ============================================================================

class _PackageSummary extends StatelessWidget {
  const _PackageSummary({required this.package});

  final TourPackage package;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 88,
              height: 88,
              child: package.displayImageUrl.isEmpty
                  ? const _ImageFallback()
                  : Image.network(
                      package.displayImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _ImageFallback(),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _MiniChip(text: 'Tour Package'),
                const SizedBox(height: 8),
                Text(
                  package.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 17,
                      color: Color(0xFF2A86FF),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        package.city,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w800,
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
    );
  }
}

// ============================================================================
// Payment method card
// ============================================================================

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
    final activeSelected = selected && enabled;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: _Card(
          selected: activeSelected,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF2A86FF)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                activeSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: activeSelected
                    ? const Color(0xFF2A86FF)
                    : const Color(0xFFCBD5E1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Bottom bar
// ============================================================================

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.hasDate,
    required this.isSameDay,
    required this.amountToPayNow,
    required this.saving,
    required this.onConfirm,
    this.blockingMessage,
  });

  final bool hasDate;
  final bool isSameDay;
  final double amountToPayNow;
  final bool saving;
  final VoidCallback onConfirm;
  final String? blockingMessage;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);
    final label = !hasDate
        ? 'Amount to Pay'
        : isSameDay
        ? 'Full Payment'
        : 'Down Payment (50%)';
    final blocked = blockingMessage != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (blocked)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            color: const Color(0xFFFFF3CD),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFFB45309),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                    blockingMessage!,
                    style: const TextStyle(
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 12 + bottom),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 22,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      money.format(amountToPayNow),
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 180,
                height: 54,
                child: ElevatedButton(
                  onPressed: (saving || blocked) ? null : onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A86FF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFBBD7FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Confirm Booking'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Shared small widgets
// ============================================================================

class _FieldButton extends StatelessWidget {
  const _FieldButton({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: _Card(
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF2A86FF)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Icon(Icons.edit_calendar_rounded),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.selected = false});

  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? const Color(0xFF2A86FF) : const Color(0xFFE7EEF7),
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

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
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFF2A86FF) : const Color(0xFFF1F5F9),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: onTap == null
              ? const Color(0xFFCBD5E1)
              : filled
              ? Colors.white
              : const Color(0xFF0F172A),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: const Color(0xFF0F172A)),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF2A86FF),
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF2FF),
      child: const Icon(Icons.map_rounded, color: Color(0xFF2A86FF)),
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
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Time picker bottom sheet (dropdown-style, 7 AM – 5 PM, 15-min steps)
// ============================================================================

class _TimePickerSheet extends StatefulWidget {
  const _TimePickerSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final String selected;

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    final idx = widget.options.indexOf(widget.selected);
    final offset = idx > 3 ? (idx - 3) * 54.0 : 0.0;
    _scrollCtrl = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: const Color(0xFF64748B),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE7EEF7)),
          Flexible(
            child: ListView.builder(
              controller: _scrollCtrl,
              itemCount: widget.options.length,
              itemExtent: 54,
              itemBuilder: (_, i) {
                final option = widget.options[i];
                final isSelected = option == widget.selected;
                return InkWell(
                  onTap: () => Navigator.pop(context, option),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    color: isSelected
                        ? const Color(0xFFEAF2FF)
                        : Colors.transparent,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatScheduleTimeLabel(option),
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF2A86FF)
                                  : const Color(0xFF0F172A),
                              fontWeight: isSelected
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.check_rounded,
                            color: Color(0xFF2A86FF),
                            size: 20,
                          ),
                      ],
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
}
