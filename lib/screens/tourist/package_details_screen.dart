import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _isSaved = false;

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
      if (spot.isOriginal) _removedOriginalKeys.add(spot.key);
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

  Future<void> _sharePackage(TourPackage package) async {
    final text = '${package.title}\n${package.city}, Bulacan\n${package.priceText}';
    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Package details copied for sharing'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
        'opening_time': originalSpot.openingTime.isEmpty
            ? null
            : originalSpot.openingTime,
        'closing_time': originalSpot.closingTime.isEmpty
            ? null
            : originalSpot.closingTime,
        'estimated_arrival_time': originalSpot.estimatedArrivalTime.isEmpty
            ? null
            : originalSpot.estimatedArrivalTime,
        'estimated_duration_minutes': originalSpot.estimatedDurationMinutes > 0
            ? originalSpot.estimatedDurationMinutes
            : null,
        'recommended_visit_duration_minutes':
            originalSpot.recommendedVisitDurationMinutes > 0
                ? originalSpot.recommendedVisitDurationMinutes
                : null,
      });
    }

    return rows;
  }

  Future<void> _book(_PackageDetailsData data) async {
    final validationError = _selectedSpotValidationMessage(
      _selectedSpots.length,
    );

    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationError),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final hasActiveTour = await _repo.hasActiveTour();
      if (hasActiveTour) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(TourisTrikeRepository.activeTourErrorMessage),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to verify your current tour status right now. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final originalCount = data.originalSpots.length;
    if (!mounted) return;

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
      backgroundColor: Colors.white,
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
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _PackageHeroImage(imageUrl: data.package.displayImageUrl),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 355,
                          child: _PackageHeaderCard(
                            package: data.package,
                            currentUnitPrice: currentUnitPrice,
                            spotCount: _selectedSpots.length,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 30, 24, 142),
                      child: _PackageDetailsBody(
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
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Row(
                    children: [
                      _FloatingActionButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      _FloatingActionButton(
                        icon: _isSaved
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        iconColor: _isSaved
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF0F172A),
                        onTap: () => setState(() => _isSaved = !_isSaved),
                      ),
                      const SizedBox(width: 12),
                      _FloatingActionButton(
                        icon: Icons.ios_share_rounded,
                        onTap: () => _sharePackage(data.package),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _BottomBookBar(
                  package: data.package,
                  currentUnitPrice: currentUnitPrice,
                  validationMessage: _selectedSpotValidationMessage(
                    _selectedSpots.length,
                  ),
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
      openingTime: spot.openingTime,
      closingTime: spot.closingTime,
      estimatedArrivalTime: spot.estimatedArrivalTime,
      estimatedDurationMinutes: spot.estimatedDurationMinutes,
      recommendedVisitDurationMinutes: spot.recommendedVisitDurationMinutes,
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
      openingTime: '',
      closingTime: '',
      estimatedArrivalTime: '',
      estimatedDurationMinutes: 0,
      recommendedVisitDurationMinutes: 0,
    );
  }
}

class _PackageHeroImage extends StatelessWidget {
  const _PackageHeroImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 470,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              alignment: Alignment.center,
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
                    Colors.black.withValues(alpha: 0.30),
                    Colors.black.withValues(alpha: 0.02),
                    Colors.black.withValues(alpha: 0.04),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageHeaderCard extends StatelessWidget {
  const _PackageHeaderCard({
    required this.package,
    required this.currentUnitPrice,
    required this.spotCount,
  });

  final TourPackage package;
  final double currentUnitPrice;
  final int spotCount;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);
    final priceText = currentUnitPrice > 0
        ? money.format(currentUnitPrice)
        : package.priceText.isNotEmpty
            ? package.priceText
            : 'Ask office';
    final duration = package.durationText.isEmpty ? 'Flexible' : package.durationText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(30, 28, 30, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  package.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF182433),
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _HeaderStatusBadge(text: package.status),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: Color(0xFF4A77A6),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${package.city}, Bulacan',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4A77A6),
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          _PackageStatsRow(
            priceText: priceText,
            durationText: duration,
            spotCount: spotCount,
          ),
        ],
      ),
    );
  }
}

class _HeaderStatusBadge extends StatelessWidget {
  const _HeaderStatusBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFDDFBEA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text.isEmpty ? 'LISTED' : text.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF00A95A),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PackageStatsRow extends StatelessWidget {
  const _PackageStatsRow({
    required this.priceText,
    required this.durationText,
    required this.spotCount,
  });

  final String priceText;
  final String durationText;
  final int spotCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DetailStat(
            value: priceText.replaceAll('PHP ', '₱'),
            label: 'Price',
          ),
        ),
        const _StatDivider(),
        Expanded(
          child: _DetailStat(
            value: durationText,
            label: 'Duration',
          ),
        ),
        const _StatDivider(),
        Expanded(
          child: _DetailStat(
            value: '$spotCount',
            label: spotCount == 1 ? 'Spot' : 'Spots',
            valueColor: const Color(0xFF2A86FF),
          ),
        ),
      ],
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: valueColor ?? const Color(0xFF0F172A),
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _PackageDetailsBody extends StatefulWidget {
  const _PackageDetailsBody({
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
  State<_PackageDetailsBody> createState() => _PackageDetailsBodyState();
}

class _PackageDetailsBodyState extends State<_PackageDetailsBody> {
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
    final filteredSuggestions = _filteredSuggestions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SoftDivider(),
        const SizedBox(height: 24),
        const _DetailsSectionTitle('About the Tour'),
        const SizedBox(height: 12),
        Text(
          package.description.isEmpty
              ? (package.subtitle.isEmpty
                  ? 'No description has been added yet.'
                  : package.subtitle)
              : package.description,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 15.8,
            height: 1.58,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 28),
        const _DetailsSectionTitle('Spots Preview'),
        const SizedBox(height: 12),
        _InfoBlock(
          icon: Icons.map_outlined,
          message:
              'The itinerary is now handled in the booking screen. Review the package spots here, then tap Book Now to continue to itinerary selection.',
        ),
        const SizedBox(height: 28),
        const _DetailsSectionTitle('Original Package'),
        const SizedBox(height: 6),
        const Text(
          'These are the package spots included by the tour operator.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
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
            return _OriginalSpotTile(spot: item, removed: false);
          }),
        const SizedBox(height: 24),
        const _DetailsSectionTitle('Your Selected Spots'),
        const SizedBox(height: 12),
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
        const SizedBox(height: 24),
        const _DetailsSectionTitle('Google Places Suggestions'),
        const SizedBox(height: 12),
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
        const SizedBox(height: 24),
        _OperatorBlock(package: package),
      ],
    );
  }
}

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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                      color:
                          isSelected ? Colors.white : const Color(0xFF64748B),
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
    required this.validationMessage,
    required this.onBook,
  });

  final TourPackage package;
  final double currentUnitPrice;
  final String? validationMessage;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final price = currentUnitPrice > 0
        ? 'PHP ${currentUnitPrice.toStringAsFixed(0)}'
        : package.priceText.isNotEmpty
            ? package.priceText
            : 'Ask office';

    final blocked = validationMessage != null;

    return Container(
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
      child: Column(
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
                      validationMessage!,
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
          Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, bottom + 12),
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
                    onPressed: package.status == 'published' && !blocked
                        ? onBook
                        : null,
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

class _DetailsSectionTitle extends StatelessWidget {
  const _DetailsSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontWeight: FontWeight.w900,
        fontSize: 21,
        letterSpacing: -0.3,
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

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 58, color: const Color(0xFFE7EEF7));
  }
}

class _SoftDivider extends StatelessWidget {
  const _SoftDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: const Color(0xFFE7EEF7));
  }
}

class _FloatingActionButton extends StatelessWidget {
  const _FloatingActionButton({
    required this.icon,
    required this.onTap,
    this.iconColor = const Color(0xFF0F172A),
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.13),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: iconColor, size: 25),
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
        child: Icon(
          Icons.map_rounded,
          color: Color(0xFF2A86FF),
          size: 42,
        ),
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

bool _sameMunicipality(String a, String b) {
  return _normalizeText(a) == _normalizeText(b);
}

String? _selectedSpotValidationMessage(int count) {
  if (count < 3) {
    return 'Please select at least 3 spots for your tour package.';
  }
  if (count > 6) {
    return 'You can only select up to 6 spots per package.';
  }
  return null;
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
