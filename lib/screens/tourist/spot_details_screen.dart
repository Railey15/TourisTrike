import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/places/google_places_gateway.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/tourist/tourist_saved_places_state.dart';

class TouristSpotDetailsData {
  const TouristSpotDetailsData({
    required this.id,
    required this.title,
    required this.address,
    required this.distance,
    required this.distanceKm,
    required this.tag,
    required this.rating,
    required this.userRatingsTotal,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.openNow,
    required this.municipality,
    this.imageUrls = const [],
    this.googlePlaceId = '',
  });

  final String id;
  final String title;
  final String address;
  final String distance;
  final double distanceKm;
  final String tag;
  final double rating;
  final int userRatingsTotal;
  final String imageUrl;
  final double latitude;
  final double longitude;
  final bool? openNow;
  final String municipality;
  final List<String> imageUrls;
  final String googlePlaceId;
}

class TouristSpotDetailsScreen extends StatefulWidget {
  const TouristSpotDetailsScreen({
    super.key,
    required this.spot,
    required this.googleMapsApiKey,
  });

  final TouristSpotDetailsData spot;
  final String googleMapsApiKey;

  @override
  State<TouristSpotDetailsScreen> createState() =>
      _TouristSpotDetailsScreenState();
}

class _TouristSpotDetailsScreenState extends State<TouristSpotDetailsScreen> {
  final TourisTrikeRepository _repo = TourisTrikeRepository();

  double? _liveRating;
  int? _liveReviewCount;
  bool? _liveOpenNow;
  String? _googleMapsUrl;
  bool _loadingGoogleDetails = false;
  String? _proxyMapImageUrl;

  TouristSpotDetailsData get spot => widget.spot;
  String get googleMapsApiKey => widget.googleMapsApiKey;

  String get _effectivePlaceId {
    if (spot.googlePlaceId.trim().isNotEmpty) return spot.googlePlaceId.trim();
    return spot.id.trim();
  }

  double get _displayRating => _liveRating ?? spot.rating;
  int get _displayReviewCount => _liveReviewCount ?? spot.userRatingsTotal;

  String get _fallbackMapsUrl {
    final query = Uri.encodeComponent('${spot.latitude},${spot.longitude}');
    final placeId = Uri.encodeComponent(_effectivePlaceId);

    if (_effectivePlaceId.isNotEmpty &&
        !_effectivePlaceId.contains('sample') &&
        !_isNumericOnly(_effectivePlaceId)) {
      return 'https://www.google.com/maps/search/?api=1&query=$query&query_place_id=$placeId';
    }

    return 'https://www.google.com/maps/search/?api=1&query=$query';
  }

  String get _mapsUrl => _googleMapsUrl ?? _fallbackMapsUrl;

  String get _mapImage =>
      _proxyMapImageUrl ??
      CitySpotSuggestionService.buildStaticMapUrl(
        latitude: spot.latitude,
        longitude: spot.longitude,
        apiKey: googleMapsApiKey,
      );

  String get _aboutText {
    final category = spot.tag.toLowerCase();
    return '${spot.title} is a recommended $category destination in ${spot.municipality}, Bulacan. '
        'View its rating, reviews, location, and distance before planning your visit.';
  }

  TouristSavedPlace get _savedPlace {
    return TouristSavedPlace(
      id: 'google-${spot.id}',
      label: spot.title,
      address: spot.address.isEmpty
          ? '${spot.municipality}, Bulacan'
          : spot.address,
      tag: spot.tag,
      latitude: spot.latitude,
      longitude: spot.longitude,
      imageUrl: spot.imageUrl,
      rating: _displayRating,
    );
  }

  bool get _isSaved => touristSavedPlacesStore.isSaved(_savedPlace.id);

  String get _openText {
    final value = _liveOpenNow ?? spot.openNow;
    if (value == null) return 'Listed';
    return value ? 'Open' : 'Closed';
  }

  Color get _openColor {
    final value = _liveOpenNow ?? spot.openNow;
    if (value == null) return const Color(0xFF2A86FF);
    return value ? const Color(0xFF10B981) : const Color(0xFFEF4444);
  }

  @override
  void initState() {
    super.initState();
    _loadGooglePlaceDetails();
  }

  bool _isNumericOnly(String value) => RegExp(r'^\d+$').hasMatch(value);

  Future<void> _loadGooglePlaceDetails() async {
    if (_effectivePlaceId.isEmpty) return;
    if (_effectivePlaceId.contains('sample')) return;
    if (_isNumericOnly(_effectivePlaceId)) return;

    setState(() => _loadingGoogleDetails = true);

    try {
      final data = await GooglePlacesGateway(apiKey: googleMapsApiKey)
          .request('details', {
            'place_id': _effectivePlaceId,
            'fields': 'rating,user_ratings_total,opening_hours,url,geometry',
          });
      final result = data['result'] as Map<String, dynamic>?;

      if (result == null) return;

      final openingHours = result['opening_hours'] as Map<String, dynamic>?;

      if (!mounted) return;
      setState(() {
        _liveRating = (result['rating'] as num?)?.toDouble() ?? _liveRating;
        _liveReviewCount =
            (result['user_ratings_total'] as num?)?.toInt() ?? _liveReviewCount;
        _liveOpenNow = openingHours?['open_now'] as bool?;
        _googleMapsUrl = result['url'] as String?;
        _proxyMapImageUrl = result['_proxy_static_map_url'] as String?;
      });
    } catch (_) {
      // Keep fallback data from Explore screen.
    } finally {
      if (mounted) setState(() => _loadingGoogleDetails = false);
    }
  }

  Future<void> _toggleSaved() async {
    final wasSaved = _isSaved;

    try {
      if (wasSaved) {
        final rows = await _repo.fetchSavedPlaces();

        for (final row in rows.where(
          (item) =>
              item.label == _savedPlace.label &&
              item.address == _savedPlace.address,
        )) {
          await _repo.deleteSavedPlace(row.id);
        }

        touristSavedPlacesStore.remove(_savedPlace.id);
      } else {
        await _repo.savePlace(
          label: _savedPlace.label,
          address: _savedPlace.address,
          latitude: _savedPlace.latitude,
          longitude: _savedPlace.longitude,
          kind: 'normal',
          tag: _savedPlace.tag,
        );

        touristSavedPlacesStore.addOrUpdate(_savedPlace);
      }

      if (!mounted) return;
      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasSaved ? 'Removed from Saved Places' : 'Saved to Saved Places',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update saved place: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _copyMapsLink() async {
    await Clipboard.setData(ClipboardData(text: _mapsUrl));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Maps link copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openMaps() async {
    final uri = Uri.parse(_mapsUrl);

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) await _copyMapsLink();
    } catch (_) {
      await _copyMapsLink();
    }
  }

  Future<void> _sharePlace() async {
    final text =
        '${spot.title}\n'
        '${spot.address.isEmpty ? '${spot.municipality}, Bulacan' : spot.address}\n\n'
        'Google Maps: $_mapsUrl';

    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share link copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = spot.imageUrls.isEmpty ? [spot.imageUrl] : spot.imageUrls;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _SpotHeroImage(imageUrls: images),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 355,
                      child: _SpotHeaderCard(
                        spot: spot,
                        rating: _displayRating,
                        reviewCount: _displayReviewCount,
                        loading: _loadingGoogleDetails,
                      ),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 34),
                  child: _SpotDetailsBody(
                    spot: spot,
                    aboutText: _aboutText,
                    mapImage: _mapImage,
                    rating: _displayRating,
                    reviewCount: _displayReviewCount,
                    openText: _openText,
                    openColor: _openColor,
                    onMapTap: _openMaps,
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
                    onTap: _toggleSaved,
                  ),
                  const SizedBox(width: 12),
                  _FloatingActionButton(
                    icon: Icons.ios_share_rounded,
                    onTap: _sharePlace,
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

class SpotDetailsScreen extends StatelessWidget {
  const SpotDetailsScreen({super.key});

  static const _fallbackSpot = TouristSpotDetailsData(
    id: 'sample-tourist-spot',
    title: 'Tourist Spot',
    address: 'Bulacan, Philippines',
    distance: 'Nearby',
    distanceKm: 0,
    tag: 'Popular',
    rating: 4.8,
    userRatingsTotal: 0,
    imageUrl:
        'https://images.unsplash.com/photo-1500375592092-40eb2168fd21?auto=format&fit=crop&w=1200&q=80',
    latitude: 14.8434,
    longitude: 120.8114,
    openNow: null,
    municipality: 'Bulacan',
  );

  @override
  Widget build(BuildContext context) {
    return const TouristSpotDetailsScreen(
      spot: _fallbackSpot,
      googleMapsApiKey: '',
    );
  }
}

class _SpotHeroImage extends StatelessWidget {
  const _SpotHeroImage({required this.imageUrls});

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 470,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            itemCount: imageUrls.isEmpty ? 1 : imageUrls.length,
            itemBuilder: (context, index) {
              final imageUrl = imageUrls.isEmpty ? '' : imageUrls[index];

              if (imageUrl.isEmpty) return const _ImageFallback();

              return Image.network(
                imageUrl,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, _, _) => const _ImageFallback(),
              );
            },
          ),
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
          if (imageUrls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 92,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  imageUrls.length > 5 ? 5 : imageUrls.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: index == 0 ? 22 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: index == 0 ? 1 : .55,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SpotHeaderCard extends StatelessWidget {
  const _SpotHeaderCard({
    required this.spot,
    required this.rating,
    required this.reviewCount,
    required this.loading,
  });

  final TouristSpotDetailsData spot;
  final double rating;
  final int reviewCount;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final address = spot.address.isEmpty
        ? '${spot.municipality}, Bulacan'
        : spot.address;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(30, 28, 30, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.title,
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
                        address,
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
              ],
            ),
          ),
          const SizedBox(width: 10),
          _HeaderRatingBadge(
            rating: rating,
            reviewCount: reviewCount,
            loading: loading,
          ),
        ],
      ),
    );
  }
}

class _HeaderRatingBadge extends StatelessWidget {
  const _HeaderRatingBadge({
    required this.rating,
    required this.reviewCount,
    required this.loading,
  });

  final double rating;
  final int reviewCount;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final reviewsText = reviewCount > 0 ? '$reviewCount reviews' : 'No reviews';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFDDFBEA),
            borderRadius: BorderRadius.circular(8),
          ),
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF16A34A),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_border_rounded,
                      color: Color(0xFF00C86B),
                      size: 22,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Color(0xFF00A95A),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 7),
        Text(
          reviewsText,
          style: const TextStyle(
            color: Color(0xFF4A77A6),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1,
            decoration: TextDecoration.underline,
          ),
        ),
      ],
    );
  }
}

class _SpotDetailsBody extends StatelessWidget {
  const _SpotDetailsBody({
    required this.spot,
    required this.aboutText,
    required this.mapImage,
    required this.rating,
    required this.reviewCount,
    required this.openText,
    required this.openColor,
    required this.onMapTap,
  });

  final TouristSpotDetailsData spot;
  final String aboutText;
  final String mapImage;
  final double rating;
  final int reviewCount;
  final String openText;
  final Color openColor;
  final VoidCallback onMapTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpotStatsRow(
          rating: rating,
          distance: spot.distance,
          openText: openText,
          openColor: openColor,
        ),
        const SizedBox(height: 24),
        const _SoftDivider(),
        const SizedBox(height: 24),
        const _DetailsSectionTitle('About Destination'),
        const SizedBox(height: 12),
        Text(
          aboutText,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 15.8,
            height: 1.58,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            const _DetailsSectionTitle('Location'),
            const Spacer(),
            TextButton(
              onPressed: onMapTap,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2A86FF),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              child: const Text('Open in Maps'),
            ),
          ],
        ),
        if (spot.address.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            spot.address,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _MapPreview(imageUrl: mapImage, onTap: onMapTap),
        const SizedBox(height: 28),
        _ReviewsSummary(
          reviewCount: reviewCount,
          rating: rating,
          onOpenReviews: onMapTap,
        ),
      ],
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
          Icons.image_not_supported_rounded,
          color: Color(0xFF94A3B8),
          size: 46,
        ),
      ),
    );
  }
}

class _SpotStatsRow extends StatelessWidget {
  const _SpotStatsRow({
    required this.rating,
    required this.distance,
    required this.openText,
    required this.openColor,
  });

  final double rating;
  final String distance;
  final String openText;
  final Color openColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DetailStat(
            value: rating.toStringAsFixed(1),
            suffixIcon: Icons.star_rounded,
            suffixColor: const Color(0xFFF59E0B),
            label: 'Ratings',
          ),
        ),
        const _StatDivider(),
        Expanded(
          child: _DetailStat(
            value: distance.replaceAll(' away', ''),
            label: 'Distance',
          ),
        ),
        const _StatDivider(),
        Expanded(
          child: _DetailStat(
            value: openText,
            valueColor: openColor,
            label: openText == 'Listed' ? 'Google' : 'Today',
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
    this.suffixIcon,
    this.suffixColor,
  });

  final String value;
  final String label;
  final Color? valueColor;
  final IconData? suffixIcon;
  final Color? suffixColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueColor ?? const Color(0xFF0F172A),
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (suffixIcon != null) ...[
              const SizedBox(width: 5),
              Icon(suffixIcon, color: suffixColor, size: 17),
            ],
          ],
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

class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.imageUrl, required this.onTap});

  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 178,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl.isNotEmpty)
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: const Color(0xFFEAF2FF),
                      child: const Center(
                        child: Icon(
                          Icons.map_rounded,
                          color: Color(0xFF2A86FF),
                          size: 42,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    color: const Color(0xFFEAF2FF),
                    child: const Center(
                      child: Icon(
                        Icons.map_rounded,
                        color: Color(0xFF2A86FF),
                        size: 42,
                      ),
                    ),
                  ),
                Container(color: Colors.black.withValues(alpha: 0.04)),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined, color: Color(0xFF2A86FF)),
                        SizedBox(width: 10),
                        Text(
                          'View Map',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
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

class _ReviewsSummary extends StatelessWidget {
  const _ReviewsSummary({
    required this.reviewCount,
    required this.rating,
    required this.onOpenReviews,
  });

  final int reviewCount;
  final double rating;
  final VoidCallback onOpenReviews;

  @override
  Widget build(BuildContext context) {
    final countText = reviewCount > 0
        ? _compactCount(reviewCount)
        : 'No reviews yet';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8EEF6)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7ED),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.star_rounded,
              color: Color(0xFFF59E0B),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                Text(
                  countText,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onOpenReviews,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2A86FF),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
            child: const Text('See in Maps'),
          ),
        ],
      ),
    );
  }

  String _compactCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k Google reviews';
    }
    return '$count Google reviews';
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
