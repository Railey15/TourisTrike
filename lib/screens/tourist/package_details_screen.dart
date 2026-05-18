import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/tourist/package_booking_screen.dart';

class PackageDetailsScreen extends StatefulWidget {
  const PackageDetailsScreen({super.key, this.packageId});

  final dynamic packageId;

  @override
  State<PackageDetailsScreen> createState() => _PackageDetailsScreenState();
}

class _PackageDetailsScreenState extends State<PackageDetailsScreen> {
  static const double additionalSpotFee = 250;

  final TourisTrikeRepository _repo = TourisTrikeRepository();
  late Future<_PackageDetailsData> _future;

  final List<_EditablePackageSpot> _selectedSpots = [];
  final Set<String> _removedOriginalKeys = <String>{};
  dynamic _initializedPackageId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PackageDetailsData> _load() async {
    if (widget.packageId == null) {
      throw StateError('No package was selected.');
    }

    await _repo.trackTourPackageView(widget.packageId);
    final package = await _repo.fetchTourPackage(widget.packageId);
    if (package == null) throw StateError('Package not found.');

    final originalSpotsFuture = _repo.fetchPackageSpots(widget.packageId);
    final googleSuggestionsFuture = const CitySpotSuggestionService()
        .fetchSuggestions(
          city: package.city,
          province: package.city.isEmpty ? 'Bulacan' : package.provinceFallback,
          limit: 16,
        );

    final originalSpots = await originalSpotsFuture;
    final googleSuggestions = await googleSuggestionsFuture;

    return _PackageDetailsData(
      package: package,
      originalSpots: originalSpots,
      googleSuggestions: googleSuggestions
          .where((spot) => _sameMunicipality(spot.city, package.city))
          .toList(growable: false),
    );
  }

  void _reload() {
    setState(() {
      _initializedPackageId = null;
      _selectedSpots.clear();
      _removedOriginalKeys.clear();
      _future = _load();
    });
  }

  void _initializeSelection(_PackageDetailsData data) {
    if (_initializedPackageId == data.package.id) return;
    _initializedPackageId = data.package.id;
    _selectedSpots
      ..clear()
      ..addAll(
        data.originalSpots.map(
          (spot) =>
              _EditablePackageSpot.fromTouristSpot(spot, isOriginal: true),
        ),
      );
    _removedOriginalKeys.clear();
  }

  double _unitPrice(TourPackage package, int originalCount) {
    final basePrice = package.numericPrice;
    final extraSpots = math.max(0, _selectedSpots.length - originalCount);
    return basePrice + (extraSpots * additionalSpotFee);
  }

  void _addGoogleSuggestion(CitySpotSuggestion suggestion) {
    final candidate = _EditablePackageSpot.fromSuggestion(suggestion);
    if (_containsSpot(candidate)) return;
    setState(() => _selectedSpots.add(candidate));
  }

  void _removeSelectedSpot(_EditablePackageSpot spot) {
    setState(() {
      _selectedSpots.removeWhere((item) => item.key == spot.key);
      if (spot.isOriginal) {
        _removedOriginalKeys.add(spot.key);
      }
    });
  }

  void _moveSpot(int index, int delta) {
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= _selectedSpots.length) return;
    setState(() {
      final item = _selectedSpots.removeAt(index);
      _selectedSpots.insert(nextIndex, item);
    });
  }

  bool _containsSpot(_EditablePackageSpot spot) {
    return _selectedSpots.any((item) => item.key == spot.key);
  }

  List<Map<String, dynamic>> _buildCustomizationRows(
    TourPackage package,
    int originalCount,
    List<TouristSpot> originalSpots,
  ) {
    final rows = <Map<String, dynamic>>[];
    final selectedKeys = _selectedSpots.map((spot) => spot.key).toSet();

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
        'additional_fee': i >= originalCount ? additionalSpotFee : 0,
        'sort_order': i,
      });
    }

    for (final original in originalSpots) {
      final originalSpot = _EditablePackageSpot.fromTouristSpot(
        original,
        isOriginal: true,
      );
      if (selectedKeys.contains(originalSpot.key)) continue;
      rows.add({
        'spot_id': originalSpot.spotId,
        'action_type': 'removed',
        'source_type': originalSpot.sourceType,
        'google_place_id': originalSpot.googlePlaceId,
        'spot_title': originalSpot.title,
        'spot_address': originalSpot.address,
        'municipality': package.city,
        'barangay': originalSpot.barangay,
        'latitude': originalSpot.latitude,
        'longitude': originalSpot.longitude,
        'image_url': originalSpot.imageUrl,
        'additional_fee': 0,
      });
    }

    return rows;
  }

  void _book(_PackageDetailsData data) {
    final originalCount = data.originalSpots.length;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PackageBookingScreen(
          packageId: data.package.id,
          initialPackage: data.package,
          customizedUnitPrice: _unitPrice(data.package, originalCount),
          customizedSpots: _buildCustomizationRows(
            data.package,
            originalCount,
            data.originalSpots,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: FutureBuilder<_PackageDetailsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _LoadingView();
          }
          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final data = snapshot.data!;
          _initializeSelection(data);

          final originalCount = data.originalSpots.length;
          final currentUnitPrice = _unitPrice(data.package, originalCount);

          return Stack(
            children: [
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _HeroHeader(
                      imageUrl: data.package.displayImageUrl,
                      onBack: () => Navigator.pop(context),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Transform.translate(
                      offset: const Offset(0, -24),
                      child: _DetailsSheet(
                        data: data,
                        selectedSpots: _selectedSpots,
                        removedOriginalKeys: _removedOriginalKeys,
                        currentUnitPrice: currentUnitPrice,
                        additionalSpotFee: additionalSpotFee,
                        googleSuggestions: data.googleSuggestions,
                        onRemoveSpot: _removeSelectedSpot,
                        onMoveUp: (index) => _moveSpot(index, -1),
                        onMoveDown: (index) => _moveSpot(index, 1),
                        onAddGoogleSpot: _addGoogleSuggestion,
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _BottomBookBar(
                  package: data.package,
                  currentUnitPrice: currentUnitPrice,
                  onBook: () => _book(data),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _PackageDetailsData {
  const _PackageDetailsData({
    required this.package,
    required this.originalSpots,
    required this.googleSuggestions,
  });

  final TourPackage package;
  final List<TouristSpot> originalSpots;
  final List<CitySpotSuggestion> googleSuggestions;
}

class _EditablePackageSpot {
  const _EditablePackageSpot({
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

  factory _EditablePackageSpot.fromTouristSpot(
    TouristSpot spot, {
    required bool isOriginal,
  }) {
    final sourceType = spot.sourceType.isEmpty ? 'manual' : spot.sourceType;
    final googlePlaceId = spot.googlePlaceId;
    final baseKey = googlePlaceId.isNotEmpty
        ? 'google:$googlePlaceId'
        : spot.id != null
        ? 'db:${spot.id}'
        : 'title:${_normalizeText(spot.title)}';

    return _EditablePackageSpot(
      key: baseKey,
      spotId: spot.id,
      title: spot.title,
      address: spot.address,
      barangay: spot.barangay,
      municipality: spot.municipality,
      imageUrl: spot.imageUrl,
      latitude: spot.latitude,
      longitude: spot.longitude,
      sourceType: sourceType,
      googlePlaceId: googlePlaceId,
      isOriginal: isOriginal,
      category: _inferCategoryFromTitle(spot.title),
    );
  }

  factory _EditablePackageSpot.fromSuggestion(CitySpotSuggestion suggestion) {
    return _EditablePackageSpot(
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
    );
  }
}

// ---------------------------------------------------------------------------
// AI Itinerary helpers
// ---------------------------------------------------------------------------

class _ItineraryEntry {
  const _ItineraryEntry({
    required this.order,
    required this.spotName,
    required this.time,
    required this.durationMinutes,
    required this.activity,
  });

  final int order;
  final String spotName;
  final String time;
  final int durationMinutes;
  final String activity;

  String get durationText {
    if (durationMinutes < 60) return '$durationMinutes minutes';
    final hours = durationMinutes ~/ 60;
    final mins = durationMinutes % 60;
    if (mins == 0) return '$hours hour${hours > 1 ? "s" : ""}';
    return '$hours hr $mins min';
  }
}

List<_ItineraryEntry> _generateAiItinerary(
  List<_EditablePackageSpot> spots,
) {
  final entries = <_ItineraryEntry>[];
  var currentMinutes = 8 * 60; // 8:00 AM

  for (var i = 0; i < spots.length; i++) {
    final spot = spots[i];
    final duration = _spotDuration(spot.category);
    entries.add(
      _ItineraryEntry(
        order: i + 1,
        spotName: spot.title,
        time: _formatTime(currentMinutes),
        durationMinutes: duration,
        activity: _spotActivity(spot.category),
      ),
    );
    currentMinutes += duration;
    if (i < spots.length - 1) currentMinutes += 15;
  }

  return entries;
}

int _spotDuration(String category) {
  switch (category) {
    case 'Religious':
      return 30;
    case 'Nature':
      return 60;
    case 'Adventure':
      return 90;
    case 'Cafe':
      return 45;
    case 'Food':
      return 60;
    case 'Cultural':
      return 45;
    default:
      return 45;
  }
}

String _spotActivity(String category) {
  switch (category) {
    case 'Religious':
      return 'Visit the site, appreciate the architecture, and take a moment for quiet reflection.';
    case 'Nature':
      return 'Take a leisurely stroll, soak in the natural scenery, and capture some amazing photos.';
    case 'Adventure':
      return 'Get your adrenaline pumping and enjoy thrilling outdoor activities!';
    case 'Cafe':
      return 'Relax with a refreshing drink and enjoy the cozy, welcoming atmosphere.';
    case 'Food':
      return 'Taste delicious local delicacies and enjoy a well-deserved meal break.';
    case 'Cultural':
      return 'Immerse yourself in the local arts, traditions, and cultural heritage of the area.';
    default:
      return 'Explore the landmark, discover its rich history, and take memorable photos.';
  }
}

String _formatTime(int totalMinutes) {
  final hours = totalMinutes ~/ 60;
  final mins = totalMinutes % 60;
  final period = hours < 12 ? 'AM' : 'PM';
  final h = hours > 12 ? hours - 12 : (hours == 0 ? 12 : hours);
  final m = mins.toString().padLeft(2, '0');
  return '$h:$m $period';
}

int _totalTourMinutes(List<_EditablePackageSpot> spots) {
  if (spots.isEmpty) return 0;
  final stay = spots.map((s) => _spotDuration(s.category)).reduce((a, b) => a + b);
  final travel = (spots.length - 1) * 15;
  return stay + travel;
}

// ---------------------------------------------------------------------------
// Hero header
// ---------------------------------------------------------------------------

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.imageUrl, required this.onBack});

  final String imageUrl;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _ImageFallback(),
            )
          else
            const _ImageFallback(),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.12),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _CircleButton(icon: Icons.arrow_back_rounded, onTap: onBack),
                  const Spacer(),
                  _CircleButton(icon: Icons.ios_share_rounded, onTap: () {}),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Details sheet (stateful for category filter)
// ---------------------------------------------------------------------------

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({
    required this.data,
    required this.selectedSpots,
    required this.removedOriginalKeys,
    required this.currentUnitPrice,
    required this.additionalSpotFee,
    required this.googleSuggestions,
    required this.onRemoveSpot,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onAddGoogleSpot,
  });

  final _PackageDetailsData data;
  final List<_EditablePackageSpot> selectedSpots;
  final Set<String> removedOriginalKeys;
  final double currentUnitPrice;
  final double additionalSpotFee;
  final List<CitySpotSuggestion> googleSuggestions;
  final void Function(_EditablePackageSpot spot) onRemoveSpot;
  final void Function(int index) onMoveUp;
  final void Function(int index) onMoveDown;
  final void Function(CitySpotSuggestion spot) onAddGoogleSpot;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  static const _allCategories = [
    'All',
    'Cafe',
    'Historical',
    'Nature',
    'Religious',
    'Food',
    'Adventure',
    'Cultural',
  ];

  String _selectedCategory = 'All';

  List<CitySpotSuggestion> get _filteredSuggestions {
    final selectedKeys = widget.selectedSpots.map((s) => s.key).toSet();
    final selectedTitles = widget.selectedSpots
        .map((s) => _normalizeText(s.title))
        .toSet();

    return widget.googleSuggestions.where((s) {
      if (selectedKeys.contains('google:${s.id}')) return false;
      if (selectedTitles.contains(_normalizeText(s.title))) return false;
      if (_selectedCategory != 'All' && s.category != _selectedCategory) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final package = widget.data.package;
    final bottom = MediaQuery.of(context).padding.bottom;
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);
    final extraSpots = math.max(
      0,
      widget.selectedSpots.length - widget.data.originalSpots.length,
    );
    final filteredSuggestions = _filteredSuggestions;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18, 22, 18, bottom + 116),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title & status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  package.title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 28,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _StatusChip(text: package.status),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: Color(0xFF2A86FF),
                size: 19,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${package.city}, Bulacan',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetaPill(
                icon: Icons.payments_rounded,
                text: widget.currentUnitPrice > 0
                    ? money.format(widget.currentUnitPrice)
                    : _priceLabel(package),
              ),
              _MetaPill(
                icon: Icons.schedule_rounded,
                text: package.durationText.isEmpty
                    ? 'Flexible'
                    : package.durationText,
              ),
              _MetaPill(
                icon: Icons.edit_location_alt_rounded,
                text:
                    '${widget.selectedSpots.length} spot${widget.selectedSpots.length == 1 ? '' : 's'}',
              ),
              if (extraSpots > 0)
                _MetaPill(
                  icon: Icons.add_circle_outline_rounded,
                  text:
                      '+${money.format(extraSpots * widget.additionalSpotFee)} extras',
                ),
            ],
          ),
          const SizedBox(height: 18),

          // About
          const _SectionTitle('About the Tour'),
          const SizedBox(height: 8),
          Text(
            package.description.isEmpty
                ? (package.subtitle.isEmpty
                      ? 'No description has been added yet.'
                      : package.subtitle)
                : package.description,
            style: const TextStyle(
              color: Color(0xFF64748B),
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 22),

          // Customize info
          const _SectionTitle('Customize This Package'),
          const SizedBox(height: 10),
          _InfoBlock(
            icon: Icons.tune_rounded,
            message:
                'The "Original Package" below shows what the tour operator included. '
                'Feel free to remove spots you don\'t want, add new ones from Google Places, '
                'and reorder them to match your preferred route. '
                'Each spot beyond the original ${widget.data.originalSpots.length} '
                'adds ${money.format(widget.additionalSpotFee)} to the price.',
          ),
          const SizedBox(height: 22),

          // ─── SECTION 1: Original Package ────────────────────────────────
          const _SectionTitle('Original Package'),
          const SizedBox(height: 6),
          const Text(
            'These are the spots included by the tour operator. You can remove any that don\'t interest you.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          if (widget.data.originalSpots.isEmpty)
            const _EmptyBlock(
              message: 'No tourist spots have been linked to this package yet.',
            )
          else
            ...widget.data.originalSpots.map((spot) {
              final item = _EditablePackageSpot.fromTouristSpot(
                spot,
                isOriginal: true,
              );
              final removed = widget.removedOriginalKeys.contains(item.key);
              return _OriginalSpotTile(spot: item, removed: removed);
            }),
          const SizedBox(height: 22),

          // ─── SECTION 2: Your Selected Spots ─────────────────────────────
          const _SectionTitle('Your Selected Spots'),
          const SizedBox(height: 10),
          if (widget.selectedSpots.isEmpty)
            const _EmptyBlock(
              message:
                  'You removed all spots. Add new ones from Google Places below before booking.',
            )
          else
            ...widget.selectedSpots.asMap().entries.map(
              (entry) => _SelectedSpotTile(
                spot: entry.value,
                index: entry.key,
                total: widget.selectedSpots.length,
                onMoveUp: entry.key == 0
                    ? null
                    : () => widget.onMoveUp(entry.key),
                onMoveDown: entry.key == widget.selectedSpots.length - 1
                    ? null
                    : () => widget.onMoveDown(entry.key),
                onRemove: () => widget.onRemoveSpot(entry.value),
              ),
            ),
          const SizedBox(height: 22),

          // ─── SECTION 3: Google Places Suggestions ───────────────────────
          const _SectionTitle('Google Places Suggestions'),
          const SizedBox(height: 10),
          _CategoryFilterBar(
            categories: _allCategories,
            selected: _selectedCategory,
            onSelect: (cat) => setState(() => _selectedCategory = cat),
          ),
          const SizedBox(height: 12),
          if (filteredSuggestions.isEmpty)
            _EmptyBlock(
              message: _selectedCategory == 'All'
                  ? 'No additional Google Places suggestions are available for this area right now.'
                  : 'No $_selectedCategory spots found nearby. Try a different category.',
            )
          else
            ...filteredSuggestions.map(
              (spot) => _GoogleSuggestionTile(
                spot: spot,
                onAdd: () => widget.onAddGoogleSpot(spot),
              ),
            ),
          const SizedBox(height: 22),

          // ─── SECTION 4: AI Suggested Itinerary ──────────────────────────
          const _SectionTitle('Itinerary'),
          const SizedBox(height: 10),
          _AiItinerarySection(selectedSpots: widget.selectedSpots),
          const SizedBox(height: 20),

          _OperatorBlock(package: package),
        ],
      ),
    );
  }

  String _priceLabel(TourPackage package) {
    if (package.priceText.isNotEmpty) return package.priceText;
    if (package.estimatedBudget > 0) {
      return 'PHP ${package.estimatedBudget.toStringAsFixed(0)}';
    }
    return 'Ask office';
  }
}

// ---------------------------------------------------------------------------
// Category filter bar
// ---------------------------------------------------------------------------

class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<String> categories;
  final String selected;
  final void Function(String) onSelect;

  static const _icons = <String, IconData>{
    'All': Icons.apps_rounded,
    'Cafe': Icons.coffee_rounded,
    'Historical': Icons.account_balance_rounded,
    'Nature': Icons.park_rounded,
    'Religious': Icons.church_rounded,
    'Food': Icons.restaurant_rounded,
    'Adventure': Icons.terrain_rounded,
    'Cultural': Icons.museum_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((cat) {
          final isSelected = cat == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF2A86FF)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF2A86FF)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _icons[cat] ?? Icons.place_rounded,
                      size: 15,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cat,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF334155),
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
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

// ---------------------------------------------------------------------------
// AI Itinerary section
// ---------------------------------------------------------------------------

class _AiItinerarySection extends StatelessWidget {
  const _AiItinerarySection({required this.selectedSpots});

  final List<_EditablePackageSpot> selectedSpots;

  @override
  Widget build(BuildContext context) {
    if (selectedSpots.isEmpty) {
      return const _EmptyBlock(
        message:
            'Add spots above to generate your personalized AI itinerary.',
      );
    }

    final entries = _generateAiItinerary(selectedSpots);
    final totalMinutes = _totalTourMinutes(selectedSpots);
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    final totalText = mins == 0
        ? '$hours hour${hours != 1 ? "s" : ""}'
        : '$hours hour${hours != 1 ? "s" : ""} $mins min${mins != 1 ? "s" : ""}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2A86FF), Color(0xFF7C3AED)],
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 14,
              ),
              SizedBox(width: 6),
              Text(
                'AI Suggested Itinerary',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...entries.map((entry) => _ItineraryEntryCard(entry: entry)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBBD7FF)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.timer_rounded,
                color: Color(0xFF2A86FF),
                size: 22,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Estimated Tour Duration',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    totalText,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ItineraryEntryCard extends StatelessWidget {
  const _ItineraryEntryCard({required this.entry});

  final _ItineraryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFF2A86FF),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${entry.order}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.time,
                  style: const TextStyle(
                    color: Color(0xFF2A86FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.spotName,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                _ItineraryDetailRow(
                  icon: Icons.schedule_rounded,
                  text: 'Estimated stay: ${entry.durationText}',
                ),
                const SizedBox(height: 4),
                _ItineraryDetailRow(
                  icon: Icons.lightbulb_outline_rounded,
                  text: 'Suggested activity: ${entry.activity}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItineraryDetailRow extends StatelessWidget {
  const _ItineraryDetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              height: 1.4,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Spot tiles
// ---------------------------------------------------------------------------

class _OriginalSpotTile extends StatelessWidget {
  const _OriginalSpotTile({required this.spot, required this.removed});

  final _EditablePackageSpot spot;
  final bool removed;

  @override
  Widget build(BuildContext context) {
    return _BaseSpotTile(
      title: spot.title,
      subtitle: _spotSubtitle(spot),
      imageUrl: spot.imageUrl,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: removed ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          removed ? 'Removed' : 'Included',
          style: TextStyle(
            color: removed ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _SelectedSpotTile extends StatelessWidget {
  const _SelectedSpotTile({
    required this.spot,
    required this.index,
    required this.total,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final _EditablePackageSpot spot;
  final int index;
  final int total;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return _BaseSpotTile(
      title: '${index + 1}. ${spot.title}',
      subtitle: _spotSubtitle(spot),
      imageUrl: spot.imageUrl,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconActionButton(
            icon: Icons.keyboard_arrow_up_rounded,
            enabled: onMoveUp != null,
            onTap: onMoveUp,
          ),
          const SizedBox(width: 4),
          _IconActionButton(
            icon: Icons.keyboard_arrow_down_rounded,
            enabled: onMoveDown != null,
            onTap: onMoveDown,
          ),
          const SizedBox(width: 4),
          _IconActionButton(
            icon: Icons.remove_circle_outline_rounded,
            enabled: true,
            accent: const Color(0xFFDC2626),
            onTap: onRemove,
          ),
        ],
      ),
      footer: total > 1
          ? const Text(
              'Use the arrows to customize the package route order.',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            )
          : null,
    );
  }
}

class _GoogleSuggestionTile extends StatelessWidget {
  const _GoogleSuggestionTile({required this.spot, required this.onAdd});

  final CitySpotSuggestion spot;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return _BaseSpotTile(
      title: spot.title,
      subtitle: [
        spot.barangayHint,
        spot.address,
      ].where((value) => value.trim().isNotEmpty).join(' • '),
      imageUrl: spot.imageForCard,
      footer: Text(
        'Google Places • ${spot.category}',
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
      trailing: _AddButton(onTap: onAdd),
    );
  }
}

class _BaseSpotTile extends StatelessWidget {
  const _BaseSpotTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.trailing,
    this.footer,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final Widget trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: imageUrl.isEmpty
                      ? const _ImageFallback()
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const _ImageFallback(),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle.isEmpty ? 'Municipality spot' : subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: footer!),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add_rounded, size: 16),
      label: const Text('Add'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2A86FF),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBBD7FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2A86FF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OperatorBlock extends StatelessWidget {
  const _OperatorBlock({required this.package});

  final TourPackage package;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBBD7FF)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(Icons.verified_rounded, color: Color(0xFF2A86FF)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OPERATED BY',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  package.submittedByName.isEmpty
                      ? '${package.city} Tourism Office'
                      : package.submittedByName,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
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

class _BottomBookBar extends StatelessWidget {
  const _BottomBookBar({
    required this.package,
    required this.currentUnitPrice,
    required this.onBook,
  });

  final TourPackage package;
  final double currentUnitPrice;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final price = currentUnitPrice > 0
        ? 'PHP ${currentUnitPrice.toStringAsFixed(0)}'
        : package.priceText.isNotEmpty
        ? package.priceText
        : 'Ask office';

    return Container(
      padding: EdgeInsets.fromLTRB(18, 12, 18, bottom + 12),
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
                const Text(
                  'Customized Price',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  price,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            height: 54,
            width: 170,
            child: ElevatedButton.icon(
              onPressed: package.status == 'published' ? onBook : null,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Book Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A86FF),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFBBD7FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  const _IconActionButton({
    required this.icon,
    required this.enabled,
    this.accent = const Color(0xFF2A86FF),
    this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled
              ? accent.withValues(alpha: 0.10)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? accent : const Color(0xFFCBD5E1),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF2A86FF), size: 17),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF2A86FF),
          fontWeight: FontWeight.w900,
          fontSize: 11,
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
        fontWeight: FontWeight.w900,
        fontSize: 18,
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w800,
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
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF0F172A)),
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
      child: const Center(
        child: Icon(Icons.map_rounded, color: Color(0xFF2A86FF), size: 42),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF2A86FF)),
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

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

bool _sameMunicipality(String a, String b) {
  return _normalizeText(a) == _normalizeText(b);
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

String _spotSubtitle(_EditablePackageSpot spot) {
  final parts = [
    spot.barangay,
    spot.municipality,
    if (spot.address.isNotEmpty) spot.address,
  ].where((value) => value.trim().isNotEmpty).toList(growable: false);
  return parts.join(' • ');
}

String _inferCategoryFromTitle(String title) {
  final t = title.toLowerCase();
  if (t.contains('church') ||
      t.contains('chapel') ||
      t.contains('cathedral') ||
      t.contains('basilica') ||
      t.contains('shrine') ||
      t.contains('mosque') ||
      t.contains('temple') ||
      t.contains('parish')) {
    return 'Religious';
  }
  if (t.contains('museum') ||
      t.contains('gallery') ||
      t.contains('cultural') ||
      t.contains('heritage') ||
      t.contains('arts center')) {
    return 'Cultural';
  }
  if (t.contains('cafe') ||
      t.contains('café') ||
      t.contains('coffee') ||
      t.contains('bakery') ||
      t.contains('pastry')) {
    return 'Cafe';
  }
  if (t.contains('restaurant') ||
      t.contains('eatery') ||
      t.contains('food') ||
      t.contains('carinderia') ||
      t.contains('diner') ||
      t.contains('grill')) {
    return 'Food';
  }
  if (t.contains('park') ||
      t.contains('garden') ||
      t.contains('falls') ||
      t.contains('lake') ||
      t.contains('mountain') ||
      t.contains('forest') ||
      t.contains('river') ||
      t.contains('nature')) {
    return 'Nature';
  }
  if (t.contains('resort') ||
      t.contains('adventure') ||
      t.contains('zipline') ||
      t.contains('hiking') ||
      t.contains('trail') ||
      t.contains('camp') ||
      t.contains('sports')) {
    return 'Adventure';
  }
  return 'Historical';
}

extension on TourPackage {
  String get provinceFallback => 'Bulacan';
}
