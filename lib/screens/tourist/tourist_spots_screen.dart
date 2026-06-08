// FILE 1: lib/screens/tourist/tourist_spots_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/tourist/spot_details_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_tourist.dart';

class TouristSpotsScreen extends StatefulWidget {
  const TouristSpotsScreen({super.key});

  @override
  State<TouristSpotsScreen> createState() => _TouristSpotsScreenState();
}

class _TouristSpotsScreenState extends State<TouristSpotsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
 
  late Future<List<_PublicTouristSpot>> _future;

  int _navIndex = 1;
  int _selectedChip = 0;

  @override
  void initState() {
    super.initState();
    _future = _fetchTouristSpots();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = _fetchTouristSpots());
  }

  Future<List<_PublicTouristSpot>> _fetchTouristSpots() async {
    try {
      final rows = await _supabase
          .from('tourist_spots')
          .select(
            'id, title, description, barangay, city, province, latitude, longitude, rating, image_url, status, verification_status, address, opening_hours, entrance_fee, contact_number, website_url, best_time_to_visit, travel_tips, created_at',
          )
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(150)
          .timeout(const Duration(seconds: 15));

      final spots = (rows as List)
          .map((row) => _PublicTouristSpot.fromMap(row as Map<String, dynamic>))
          .where((spot) => spot.title.trim().isNotEmpty)
          .toList(growable: false);

      return _dedupeSpots(spots);
    } catch (e) {
      debugPrint('TOURIST spots fetch failed: $e');
      rethrow;
    }
  }

  List<_PublicTouristSpot> _dedupeSpots(List<_PublicTouristSpot> spots) {
    final seen = <String>{};
    final result = <_PublicTouristSpot>[];

    for (final spot in spots) {
      final key = [
        spot.title,
        spot.barangay,
        spot.city,
        spot.latitude.toStringAsFixed(5),
        spot.longitude.toStringAsFixed(5),
      ].join('|').toLowerCase();

      if (seen.add(key)) result.add(spot);
    }

    return result;
  }

  List<String> _chipsFor(List<_PublicTouristSpot> spots) {
    final cities = spots
        .map((spot) => spot.city)
        .where((city) => city.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All', ...cities];
  }

  List<_PublicTouristSpot> _filtered(
    List<_PublicTouristSpot> spots,
    List<String> chips,
  ) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final selected = chips[_selectedChip < chips.length ? _selectedChip : 0];

    return spots.where((spot) {
      final cityOk = selected == 'All' || spot.city == selected;
      final searchOk = query.isEmpty ||
          spot.title.toLowerCase().contains(query) ||
          spot.description.toLowerCase().contains(query) ||
          spot.city.toLowerCase().contains(query) ||
          spot.barangay.toLowerCase().contains(query) ||
          spot.address.toLowerCase().contains(query);

      return cityOk && searchOk;
    }).toList(growable: false);
  }

  Future<void> _trackTouristSpotView(dynamic id) async {
    try {
      await _supabase.from('tourist_spot_views').insert({
        'spot_id': id,
        'viewed_at': DateTime.now().toIso8601String(),
      }).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('TOURIST spot view tracking skipped: $e');
    }
  }

  Future<void> _openSpotDetails(_PublicTouristSpot spot) async {
    await _trackTouristSpotView(spot.id);
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TouristSpotDetailsScreen(
          spot: TouristSpotDetailsData(
            id: spot.id.toString(),
            title: spot.title,
            address: spot.fullAddress,
            distance: spot.verificationStatus == 'verified'
                ? 'Verified listing'
                : 'Community listing',
            distanceKm: 0,
            tag: spot.verificationStatus == 'verified' ? 'Verified' : 'Spot',
            rating: spot.rating,
            userRatingsTotal: 0,
            imageUrl: spot.imageForCard,
            imageUrls: [spot.imageForCard],
            latitude: spot.latitude,
            longitude: spot.longitude,
            openNow: null,
            municipality: spot.city,
          ),
          googleMapsApiKey: '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    const navBarBodyHeight = 92.0;
    final navTotalH = navBarBodyHeight + bottomInset;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: FutureBuilder<List<_PublicTouristSpot>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _LoadingState();
                  }

                  if (snapshot.hasError) {
                    return _ErrorState(
                      message: snapshot.error.toString(),
                      onRetry: _reload,
                    );
                  }

                  final spots = snapshot.data ?? const <_PublicTouristSpot>[];
                  final chips = _chipsFor(spots);
                  if (_selectedChip >= chips.length) _selectedChip = 0;
                  final filtered = _filtered(spots, chips);

                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    color: const Color(0xFF2A86FF),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16, 10, 16, navTotalH + 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _BackButtonCircle(
                                onTap: () => Navigator.pop(context),
                              ),
                              const Spacer(),
                              const Text(
                                'Tourist Spots',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: _reload,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  color: Color(0xFF2A86FF),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _SearchBar(controller: _searchCtrl),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 42,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: chips.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (_, i) => _CategoryChip(
                                label: chips[i],
                                selected: i == _selectedChip,
                                onTap: () => setState(() => _selectedChip = i),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (filtered.isEmpty)
                            const _EmptyState(
                              message:
                                  'No tourist spots available yet. Subtenant-created active spots will appear here once saved in the database.',
                            )
                          else
                            ...filtered.map(
                              (spot) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _PopularSpotCard(
                                  spot: spot,
                                  onTap: () => _openSpotDetails(spot),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AppBottomNav(
                selectedIndex: _navIndex,
                onSelect: (i) => setState(() => _navIndex = i),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicTouristSpot {
  const _PublicTouristSpot({
    required this.id,
    required this.title,
    required this.description,
    required this.barangay,
    required this.city,
    required this.province,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.imageUrl,
    required this.status,
    required this.verificationStatus,
    required this.address,
    required this.openingHours,
    required this.entranceFee,
    required this.contactNumber,
    required this.websiteUrl,
    required this.bestTimeToVisit,
    required this.travelTips,
  });

  final dynamic id;
  final String title;
  final String description;
  final String barangay;
  final String city;
  final String province;
  final double latitude;
  final double longitude;
  final double rating;
  final String imageUrl;
  final String status;
  final String verificationStatus;
  final String address;
  final String openingHours;
  final String entranceFee;
  final String contactNumber;
  final String websiteUrl;
  final String bestTimeToVisit;
  final String travelTips;

  factory _PublicTouristSpot.fromMap(Map<String, dynamic> map) {
    return _PublicTouristSpot(
      id: map['id'],
      title: _readString(map['title'], fallback: 'Untitled Spot'),
      description: _readString(map['description']),
      barangay: _readString(map['barangay']),
      city: _readString(map['city']),
      province: _readString(map['province'], fallback: 'Bulacan'),
      latitude: _readDouble(map['latitude']),
      longitude: _readDouble(map['longitude']),
      rating: _readDouble(map['rating']).clamp(0.0, 5.0),
      imageUrl: _readString(map['image_url']),
      status: _readString(map['status'], fallback: 'active'),
      verificationStatus:
          _readString(map['verification_status'], fallback: 'pending'),
      address: _readString(map['address']),
      openingHours: _readString(map['opening_hours']),
      entranceFee: _readString(map['entrance_fee']),
      contactNumber: _readString(map['contact_number']),
      websiteUrl: _readString(map['website_url']),
      bestTimeToVisit: _readString(map['best_time_to_visit']),
      travelTips: _readString(map['travel_tips']),
    );
  }

  static String _readString(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String get fullAddress {
    final parts = [
      if (address.isNotEmpty) address,
      if (barangay.isNotEmpty && !address.toLowerCase().contains(barangay.toLowerCase())) barangay,
      if (city.isNotEmpty) city,
      if (province.isNotEmpty) province,
    ];
    return parts.join(', ');
  }

  String get imageForCard {
    if (imageUrl.isNotEmpty) return imageUrl;
    if (latitude != 0 && longitude != 0) {
      return 'https://maps.googleapis.com/maps/api/staticmap?center=$latitude,$longitude&zoom=15&size=640x420&scale=2&maptype=roadmap&markers=color:red%7C$latitude,$longitude';
    }
    return '';
  }
}

class _PopularSpotCard extends StatelessWidget {
  const _PopularSpotCard({required this.spot, required this.onTap});

  final _PublicTouristSpot spot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE8EEF6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            children: [
              SizedBox(
                height: 190,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (spot.imageForCard.isNotEmpty)
                      Image.network(
                        spot.imageForCard,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _ImageFallback(),
                      )
                    else
                      const _ImageFallback(),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _ImageChip(
                        icon: Icons.star_rounded,
                        text: spot.rating.toStringAsFixed(1),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _ImageChip(
                        icon: spot.verificationStatus == 'verified'
                            ? Icons.verified_rounded
                            : Icons.pending_actions_rounded,
                        text: spot.verificationStatus,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            spot.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF2A86FF),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            [spot.barangay, spot.city]
                                .where((part) => part.isNotEmpty)
                                .join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (spot.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        spot.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (spot.openingHours.isNotEmpty)
                          _DetailPill(
                            icon: Icons.schedule_rounded,
                            text: spot.openingHours,
                          ),
                        if (spot.entranceFee.isNotEmpty)
                          _DetailPill(
                            icon: Icons.payments_rounded,
                            text: spot.entranceFee,
                          ),
                        if (spot.bestTimeToVisit.isNotEmpty)
                          _DetailPill(
                            icon: Icons.wb_sunny_rounded,
                            text: spot.bestTimeToVisit,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF2A86FF), size: 14),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF2A86FF),
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageChip extends StatelessWidget {
  const _ImageChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2A86FF), size: 16),
          const SizedBox(width: 5),
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search_rounded, color: Color(0xFF94A3B8)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Search spots, barangays, cities...',
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
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
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2A86FF) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}

class _BackButtonCircle extends StatelessWidget {
  const _BackButtonCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
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
        child: Icon(Icons.image_rounded, color: Color(0xFF2A86FF), size: 34),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w800,
          height: 1.4,
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF2A86FF)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
    );
  }
}
