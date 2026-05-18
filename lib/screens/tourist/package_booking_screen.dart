import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/tourist/tourist_activity_tracking_screen.dart';

// ── Autocomplete result model ────────────────────────────────────────────────
class _AutocompleteResult {
  final String placeId;
  final String description;
  const _AutocompleteResult({required this.placeId, required this.description});
}

// ============================================================================
// Main booking screen
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
  final TourisTrikeRepository _repo = TourisTrikeRepository();
  final _notesCtrl = TextEditingController();
  late Future<TourPackage> _future;

  DateTime? _selectedDate;
  int _adults = 1;
  int _children = 0;
  _PaymentMethod _payment = _PaymentMethod.cashPickup;
  bool _saving = false;
  double? _walletBalance;
  bool _walletLoading = true;

  // Pickup / drop-off
  String? _pickupAddress;
  double? _pickupLat;
  double? _pickupLng;
  String? _dropoffAddress;
  double? _dropoffLat;
  double? _dropoffLng;

  // ── Participant helpers ──────────────────────────────────────────────────
  int get _totalParticipants => _adults + _children;
  int get _requiredTricycles => (_totalParticipants / 2).ceil();

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
      _pickupAddress = address;
      _pickupLat = lat;
      _pickupLng = lng;
    });
  }

  void _onDropoffSelected(String? address, double? lat, double? lng) {
    setState(() {
      _dropoffAddress = address;
      _dropoffLat = lat;
      _dropoffLng = lng;
    });
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _future = _loadPackage();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    try {
      final wallet = await _repo.fetchOrCreateWallet(role: 'tourist');
      if (mounted) setState(() => _walletBalance = wallet.balance);
    } catch (_) {
      // wallet unavailable
    } finally {
      if (mounted) setState(() => _walletLoading = false);
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<TourPackage> _loadPackage() async {
    if (widget.initialPackage != null &&
        widget.initialPackage!.id == widget.packageId) {
      return widget.initialPackage!;
    }
    final package = await _repo.fetchTourPackage(widget.packageId);
    if (package == null) throw StateError('Package not found.');
    return package;
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

        final pickedIsToday = picked.year == now.year &&
            picked.month == now.month &&
            picked.day == now.day;

        if (!pickedIsToday && _payment == _PaymentMethod.cashPickup) {
          _payment = _PaymentMethod.wallet;
        }
      });
    }
  }

  // ── Confirm ──────────────────────────────────────────────────────────────
  Future<void> _confirm(TourPackage package) async {
    if (_selectedDate == null) {
      _snack('Please select a travel date.');
      return;
    }

    if (_pickupLat == null ||
        _pickupLng == null ||
        _dropoffLat == null ||
        _dropoffLng == null) {
      _snack(
        'Please select your pickup and drop-off points before confirming your booking.',
      );
      return;
    }

    // Wallet sufficiency check
    final amountToPayNow = _amountToPayNow(package);
    if (_payment == _PaymentMethod.wallet) {
      if (_walletBalance == null || _walletBalance! < amountToPayNow) {
        _snack(
          'Insufficient wallet balance. Please top up your wallet.',
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final total = _totalPrice(package);
      final downpayment = _downpaymentAmount(package);
      final remaining = _remainingBalance(package);
      final method = _payment == _PaymentMethod.cashPickup ? 'cash' : 'wallet';

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
        pickupAddress: _pickupAddress ?? '',
        pickupLatitude: _pickupLat,
        pickupLongitude: _pickupLng,
        dropoffAddress: _dropoffAddress ?? '',
        dropoffLatitude: _dropoffLat,
        dropoffLongitude: _dropoffLng,
        notes: _buildNotesSummary(),
        customizedSpots: widget.customizedSpots,
      );

      await _repo.createPayment(
        bookingId: booking.id,
        amount: amountToPayNow,
        paymentMethod: method,
        paymentStatus: _isSameDay ? 'fully_paid' : 'dp_paid',
        paymentType: _isSameDay ? 'full_payment' : 'down_payment',
      );

      // Deduct wallet balance if wallet was used
      if (_payment == _PaymentMethod.wallet) {
        await _repo.deductWalletForBooking(
          bookingId: booking.id.toString(),
          amount: amountToPayNow,
          transactionType:
              _isSameDay ? 'package_payment' : 'package_payment',
          description: 'Payment for ${package.title}',
          referenceKey: 'initial_wallet_payment',
        );
      }

      if (!mounted) return;

      if (_isSameDay) {
        // Go directly to the live tracking screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ActivityTrackingScreen(
              bookingId: booking.id.toString(),
            ),
          ),
        );
      } else {
        _snack('Booking submitted successfully!', error: false);
        Navigator.pop(context);
      }
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
      body: FutureBuilder<TourPackage>(
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

          final package = snapshot.data!;
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

                      // ── Pickup Point ───────────────────────────────────
                      const _SectionTitle('Pickup Point'),
                      const SizedBox(height: 6),
                      const Text(
                        'Where should the driver pick you up?',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _LocationPickerCard(
                        label: 'Pickup',
                        showUseCurrentLocation: true,
                        onLocationSelected: _onPickupSelected,
                      ),
                      const SizedBox(height: 22),

                      // ── Drop-off Point ─────────────────────────────────
                      const _SectionTitle('Drop-off Point'),
                      const SizedBox(height: 6),
                      const Text(
                        'Where should the driver drop you off after the tour?',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _LocationPickerCard(
                        label: 'Drop-off',
                        showUseCurrentLocation: true,
                        onLocationSelected: _onDropoffSelected,
                      ),
                      const SizedBox(height: 22),

                      // ── Booking Summary (live) ─────────────────────────
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
                            setState(() => _payment = _PaymentMethod.cashPickup);
                          }
                        },
                      ),

                      const SizedBox(height: 10),

                      _WalletPaymentCard(
                        selected: _payment == _PaymentMethod.wallet,
                        walletBalance: _walletBalance,
                        walletLoading: _walletLoading,
                        amountToPayNow: amountToPayNow,
                        isSameDay: _isSameDay,
                        onTap: () =>
                            setState(() => _payment = _PaymentMethod.wallet),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        _selectedDate == null
                            ? 'Note: Select a travel date to see available payment options.'
                            : _isSameDay
                                ? 'Note: Same-day bookings can use Cash on Pick-up or E-Wallet. Full payment is required.'
                                : 'Note: Advanced bookings require a 50% down payment via E-Wallet. Cash on Pick-up is disabled for advanced bookings.',
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

enum _PaymentMethod { cashPickup, wallet }

// ============================================================================
// Location picker card
// ============================================================================

class _LocationPickerCard extends StatefulWidget {
  const _LocationPickerCard({
    required this.label,
    required this.onLocationSelected,
    this.showUseCurrentLocation = true,
  });

  final String label;
  final bool showUseCurrentLocation;
  final void Function(String? address, double? lat, double? lng)
      onLocationSelected;

  @override
  State<_LocationPickerCard> createState() => _LocationPickerCardState();
}

class _LocationPickerCardState extends State<_LocationPickerCard> {
  static const _apiKey = CitySpotSuggestionService.defaultGoogleMapsApiKey;

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
      final encoded = Uri.encodeQueryComponent(query);
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
    _searchCtrl.text = suggestion.description;
    setState(() {
      _suggestions = [];
      _loadingDetails = true;
    });
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${suggestion.placeId}'
        '&fields=geometry,formatted_address'
        '&key=$_apiKey',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final result = body['result'] as Map<String, dynamic>?;
        final location =
            (result?['geometry'] as Map?)?.cast<String, dynamic>()['location']
                as Map?;
        final lat = (location?['lat'] as num?)?.toDouble();
        final lng = (location?['lng'] as num?)?.toDouble();
        final address =
            result?['formatted_address'] as String? ?? suggestion.description;
        if (lat != null && lng != null) {
          _setLocation(address, lat, lng);
        }
      }
    } catch (_) {
      // ignore
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
      final address =
          await _reverseGeocode(position.latitude, position.longitude);
      if (!mounted) return;
      _searchCtrl.text = address;
      _setLocation(address, position.latitude, position.longitude);
    } catch (_) {
      if (mounted) _showError('Could not get current location. Please try again.');
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
    setState(() {
      _selectedAddress = address;
      _selectedLat = lat;
      _selectedLng = lng;
      _suggestions = [];
    });
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
    widget.onLocationSelected(null, null, null);
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
                                bottom: BorderSide(
                                  color: Color(0xFFEEF2F7),
                                ),
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
          if (hasLocation) ...[
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

          const SizedBox(height: 14),
        ],
      ),
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
    final accent =
        isSameDay ? const Color(0xFF16A34A) : const Color(0xFF2A86FF);
    final accentLight =
        isSameDay ? const Color(0xFFDCFCE7) : const Color(0xFFEAF2FF);
    final accentBorder =
        isSameDay ? const Color(0xFF86EFAC) : const Color(0xFFBBD7FF);
    final cardBorder =
        isSameDay ? const Color(0xFF86EFAC) : const Color(0xFFBBD7FF);

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
                            isSameDay
                                ? 'Same-day Booking'
                                : 'Advanced Booking',
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
                  Column(
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
// Wallet payment card
// ============================================================================

class _WalletPaymentCard extends StatelessWidget {
  const _WalletPaymentCard({
    required this.selected,
    required this.walletBalance,
    required this.walletLoading,
    required this.amountToPayNow,
    required this.isSameDay,
    required this.onTap,
  });

  final bool selected;
  final double? walletBalance;
  final bool walletLoading;
  final double amountToPayNow;
  final bool isSameDay;
  final VoidCallback onTap;

  bool get _sufficient =>
      walletBalance != null && walletBalance! >= amountToPayNow;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);
    final enabled = _sufficient;
    final activeSelected = selected && enabled;

    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: _Card(
          selected: activeSelected,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Color(0xFF2A86FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'E-Wallet (In-App Balance)',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isSameDay
                              ? 'Pay full amount from wallet.'
                              : 'Pay 50% down payment from wallet.',
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
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: _sufficient
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _sufficient
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFFFCA5A5),
                  ),
                ),
                child: walletLoading
                    ? const SizedBox(
                        height: 16,
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF2A86FF),
                            ),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Wallet Balance',
                            style: TextStyle(
                              color: _sufficient
                                  ? const Color(0xFF15803D)
                                  : const Color(0xFFDC2626),
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          Text(
                            walletBalance != null
                                ? money.format(walletBalance)
                                : '—',
                            style: TextStyle(
                              color: _sufficient
                                  ? const Color(0xFF15803D)
                                  : const Color(0xFFDC2626),
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
              ),
              if (!_sufficient && !walletLoading) ...[
                const SizedBox(height: 8),
                const Text(
                  'Insufficient wallet balance. Please top up your wallet.',
                  style: TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
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
  });

  final bool hasDate;
  final bool isSameDay;
  final double amountToPayNow;
  final bool saving;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);
    final label = !hasDate
        ? 'Amount to Pay'
        : isSameDay
            ? 'Full Payment'
            : 'Down Payment (50%)';

    return Container(
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
              onPressed: saving ? null : onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A86FF),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFBBD7FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
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
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFDC2626),
              ),
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
