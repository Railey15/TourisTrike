import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../core/places/booking_location_service.dart';

const _primary = Color(0xFF2A86FF);
const _ink = Color(0xFF0F172A);
const _border = Color(0xFFE4EBF4);

class BookingLocationPicker extends StatefulWidget {
  const BookingLocationPicker({
    super.key,
    required this.label,
    required this.onLocationSelected,
    this.errorText,
    this.onValidationMessageChanged,
    this.service,
    this.positionLoader,
  });
  final String label;
  final ValueChanged<BookingLocation?> onLocationSelected;
  final String? errorText;
  final ValueChanged<String?>? onValidationMessageChanged;
  final BookingLocationService? service;
  final Future<Position> Function()? positionLoader;
  @override
  State<BookingLocationPicker> createState() => _BookingLocationPickerState();
}

class _BookingLocationPickerState extends State<BookingLocationPicker> {
  late final _service = widget.service ?? BookingLocationService();
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  int _revision = 0;
  List<BookingPlaceSuggestion> _suggestions = const [];
  bool _loadingSuggestions = false;
  bool _loadingDetails = false;
  bool _loadingLocation = false;
  String? _selectedAddress;
  double? _selectedLat;
  String? _searchMessage;
  bool _searchFailed = false;

  @override
  void dispose() {
    _revision++;
    _debounce?.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  int _resetSelection() {
    _debounce?.cancel();
    final revision = ++_revision;
    setState(() {
      _selectedAddress = null;
      _selectedLat = null;
      _suggestions = const [];
      _loadingDetails = _loadingLocation = _loadingSuggestions = false;
      _searchMessage = null;
      _searchFailed = false;
    });
    widget.onValidationMessageChanged?.call(null);
    widget.onLocationSelected(null);
    return revision;
  }

  bool _isCurrent(int revision) => mounted && revision == _revision;

  void _onSearchChanged(String query) {
    final revision = _resetSelection();
    if (query.trim().isEmpty) return;
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _fetchSuggestions(query.trim(), revision),
    );
  }

  Future<void> _fetchSuggestions(String query, int revision) async {
    if (!_isCurrent(revision)) return;
    setState(() {
      _loadingSuggestions = true;
      _searchMessage = null;
    });
    try {
      final suggestions = await _service.search(query);
      if (!_isCurrent(revision)) return;
      setState(() {
        _suggestions = suggestions;
        _searchFailed = false;
        _searchMessage = suggestions.isEmpty
            ? 'No matching locations. Try a more specific search.'
            : null;
      });
    } on BookingLocationException catch (e) {
      if (!_isCurrent(revision)) return;
      setState(() {
        _searchMessage = e.message;
        _searchFailed = true;
      });
    } finally {
      if (_isCurrent(revision)) setState(() => _loadingSuggestions = false);
    }
  }

  Future<void> _selectSuggestion(BookingPlaceSuggestion suggestion) async {
    final revision = _resetSelection();
    _focusNode.unfocus();
    _searchCtrl.text = suggestion.description;
    setState(() => _loadingDetails = true);
    try {
      final location = await _service.select(suggestion);
      if (_isCurrent(revision)) _setLocation(location);
    } on BookingLocationException catch (e) {
      if (_isCurrent(revision)) _invalidateSelection(e.message);
    } finally {
      if (_isCurrent(revision)) setState(() => _loadingDetails = false);
    }
  }

  Future<Position> _getPosition() async {
    if (widget.positionLoader != null) return widget.positionLoader!();
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const BookingLocationException(
        'Location services are disabled. Please enable them first.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const BookingLocationException('Location permission was denied.');
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    ).timeout(const Duration(seconds: 20));
  }

  Future<void> _useCurrentLocation() async {
    final revision = _resetSelection();
    setState(() => _loadingLocation = true);
    try {
      final position = await _getPosition();
      if (!_isCurrent(revision)) return;
      final location = await _service.currentLocation(
        position.latitude,
        position.longitude,
      );
      if (_isCurrent(revision)) _setLocation(location);
    } on BookingLocationException catch (e) {
      if (_isCurrent(revision)) _invalidateSelection(e.message);
    } catch (_) {
      if (_isCurrent(revision)) {
        _invalidateSelection(
          'Could not get your current location. Please retry.',
        );
      }
    } finally {
      if (_isCurrent(revision)) setState(() => _loadingLocation = false);
    }
  }

  void _setLocation(BookingLocation location) {
    _searchCtrl.text = location.address;
    setState(() {
      _selectedAddress = location.address;
      _selectedLat = location.latitude;
      _suggestions = const [];
    });
    widget.onValidationMessageChanged?.call(null);
    widget.onLocationSelected(location);
  }

  void _clearLocation() {
    _searchCtrl.clear();
    _resetSelection();
  }

  void _invalidateSelection(String message) {
    widget.onValidationMessageChanged?.call(message);
    _showError(message);
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

        if (_searchMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _searchMessage!,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ),
        if (_searchFailed && !_loadingSuggestions)
          TextButton(
            onPressed: () => _onSearchChanged(_searchCtrl.text),
            child: const Text('Retry search'),
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
