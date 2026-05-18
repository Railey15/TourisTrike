import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  TouristSpotDetailsData get spot => widget.spot;
  String get googleMapsApiKey => widget.googleMapsApiKey;

  String get _mapImage {
    final marker = Uri.encodeComponent('${spot.latitude},${spot.longitude}');
    return 'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$marker'
        '&zoom=16'
        '&size=900x520'
        '&scale=2'
        '&maptype=roadmap'
        '&markers=color:red%7C$marker'
        '&key=$googleMapsApiKey';
  }

  String get _aboutText {
    final category = spot.tag.toLowerCase();
    return '${spot.title} is a recommended $category place in ${spot.municipality}, Bulacan. '
        'It was selected from live Google Places results for the current city, so you can review its rating, address, and map location before visiting.';
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
      rating: spot.rating,
    );
  }

  bool get _isSaved => touristSavedPlacesStore.isSaved(_savedPlace.id);

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
          kind: 'tourist_spot',
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
    final url =
        'https://www.google.com/maps/search/?api=1&query=${spot.latitude},${spot.longitude}&query_place_id=${Uri.encodeComponent(spot.id)}';
    await Clipboard.setData(ClipboardData(text: url));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Maps link copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String get _openText {
    if (spot.openNow == null) return 'Listed';
    return spot.openNow! ? 'Open' : 'Closed';
  }

  Color get _openColor {
    if (spot.openNow == null) return const Color(0xFF2A86FF);
    return spot.openNow! ? const Color(0xFF10B981) : const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _SpotHeroImage(
                  imageUrls: spot.imageUrls.isEmpty
                      ? [spot.imageUrl]
                      : spot.imageUrls,
                ),
              ),
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -15),
                  child: _SpotDetailsSheet(
                    spot: spot,
                    aboutText: _aboutText,
                    mapImage: _mapImage,
                    openText: _openText,
                    openColor: _openColor,
                    onMapTap: _copyMapsLink,
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
                    onTap: _copyMapsLink,
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
      height: 390,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            itemCount: imageUrls.isEmpty ? 1 : imageUrls.length,
            itemBuilder: (context, index) {
              final imageUrl = imageUrls.isEmpty ? '' : imageUrls[index];
              if (imageUrl.isEmpty) {
                return Container(
                  color: const Color(0xFFEAF2FF),
                  child: const Icon(
                    Icons.image_not_supported_rounded,
                    color: Color(0xFF94A3B8),
                    size: 42,
                  ),
                );
              }
              return Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: const Color(0xFFEAF2FF),
                  child: const Icon(
                    Icons.image_not_supported_rounded,
                    color: Color(0xFF94A3B8),
                    size: 42,
                  ),
                ),
              );
            },
          ),
          if (imageUrls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  imageUrls.length > 6 ? 6 : imageUrls.length,
                  (index) => Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.20),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.10),
                  ],
                  stops: const [0.0, 0.42, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotDetailsSheet extends StatelessWidget {
  const _SpotDetailsSheet({
    required this.spot,
    required this.aboutText,
    required this.mapImage,
    required this.openText,
    required this.openColor,
    required this.onMapTap,
  });

  final TouristSpotDetailsData spot;
  final String aboutText;
  final String mapImage;
  final String openText;
  final Color openColor;
  final VoidCallback onMapTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(22, 24, 22, bottom + 112),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SpotTitleBlock(spot: spot),
          const SizedBox(height: 25),
          _SpotStatsRow(
            rating: spot.rating,
            distance: spot.distance,
            openText: openText,
            openColor: openColor,
          ),
          const SizedBox(height: 22),
          const _SoftDivider(),
          const SizedBox(height: 22),
          const _DetailsSectionTitle('About Destination'),
          const SizedBox(height: 12),
          Text(
            aboutText,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 15.5,
              height: 1.55,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 26),
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
          const SizedBox(height: 24),
          _ReviewsPreview(reviewCount: spot.userRatingsTotal),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoPill(icon: Icons.category_rounded, text: spot.tag),
              _InfoPill(
                icon: Icons.pin_drop_rounded,
                text:
                    '${spot.latitude.toStringAsFixed(4)}, ${spot.longitude.toStringAsFixed(4)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotTitleBlock extends StatelessWidget {
  const _SpotTitleBlock({required this.spot});

  final TouristSpotDetailsData spot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                spot.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 30,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFBBD7FF)),
              ),
              child: Text(
                spot.tag,
                style: const TextStyle(
                  color: Color(0xFF2A86FF),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(
              Icons.location_on_outlined,
              size: 19,
              color: Color(0xFF2A86FF),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                spot.address.isEmpty
                    ? '${spot.municipality}, Bulacan'
                    : spot.address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                ),
              ),
            ),
          ],
        ),
      ],
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
        fontSize: 20,
        letterSpacing: -0.2,
      ),
    );
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.imageUrl, required this.onTap});

  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 170,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: const Color(0xFFEAF2FF),
                  child: const Center(
                    child: Icon(
                      Icons.map_rounded,
                      color: Color(0xFF2A86FF),
                      size: 40,
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 18,
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
    );
  }
}

class _ReviewsPreview extends StatelessWidget {
  const _ReviewsPreview({required this.reviewCount});

  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final countText = reviewCount > 0 ? _compactCount(reviewCount) : 'Google';

    return Column(
      children: [
        Row(
          children: [
            Text(
              'Reviews ($countText)',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2A86FF),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
              child: const Text('See All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const _ReviewCard(
          name: 'Local Guide',
          timeAgo: 'Recent review',
          rating: '5.0',
          quote:
              'A recommended stop in Bulacan with helpful location details from Google Maps.',
          color: Color(0xFFB7795E),
        ),
      ],
    );
  }

  String _compactCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.name,
    required this.timeAgo,
    required this.rating,
    required this.quote,
    required this.color,
  });

  final String name;
  final String timeAgo;
  final String rating;
  final String quote;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EEF6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 22, backgroundColor: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      timeAgo,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      rating,
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFF59E0B),
                      size: 15,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            '"$quote"',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              height: 1.45,
              fontSize: 14.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF2A86FF)),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
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
          color: Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
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
