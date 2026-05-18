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


// FILE 2: lib/screens/tourist/tourist_home_screen.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';

import 'package:touristrike/widgets/app_bottom_nav_tourist.dart';
import 'tourist_location_state.dart';
import 'tourist_explore_screen.dart';
import 'package_details_screen.dart';

class TouristHomeScreen extends StatefulWidget {
  const TouristHomeScreen({super.key});

  @override
  State<TouristHomeScreen> createState() => _TouristHomeScreenState();
}

class _TouristHomeScreenState extends State<TouristHomeScreen> {
  final supabase = Supabase.instance.client;

  static const LatLng _defaultCenter = LatLng(14.9597, 120.9206);

  static final LatLngBounds _bulacanBounds = LatLngBounds(
    southwest: const LatLng(14.35, 120.35),
    northeast: const LatLng(15.55, 121.55),
  );

  final Completer<GoogleMapController> _mapController = Completer();

  int _navIndex = 0;
  late Future<_HomeData> _homeFuture;

  StreamSubscription<Position>? _positionSub;
  LatLng? _lastKnownCenter;
  String? _lastMunicipality;

  _MunicipalityArea? _selectedArea;
  bool _usingManualLocation = false;

  @override
  void initState() {
    super.initState();
    if (!touristLocationStore.usePhoneLocationForFirstHomeOpen()) {
      _syncManualLocationFromStore();
    }
    _homeFuture = _loadHome();
    _startLocationWatch();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<_HomeData> _loadHome() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Not logged in.');
    }

    final currentCenter = _usingManualLocation && _selectedArea != null
        ? _selectedArea!.center
        : await _resolveCurrentCenter();

    final municipality = _usingManualLocation && _selectedArea != null
        ? _selectedArea!.name
        : _detectBulacanMunicipality(currentCenter);

    final insideBulacan = municipality != null;

    final cityText = municipality == null
        ? 'Select a Bulacan city'
        : '$municipality, Bulacan';

    final profile = await supabase
        .from('profiles')
        .select('full_name, profile_image_url')
        .eq('id', user.id)
        .maybeSingle()
        .timeout(const Duration(seconds: 15));

    final fullName =
        (profile?['full_name'] as String?)?.trim().isNotEmpty == true
            ? profile!['full_name'] as String
            : 'Tourist';

    final avatarUrl = (profile?['profile_image_url'] as String?) ?? '';

    final dbSpots = municipality == null
        ? <_NearbySpot>[]
        : await _loadDatabaseSpots(
            municipality: municipality,
            center: currentCenter,
          );

    final googleSpots = municipality == null
        ? <_NearbySpot>[]
        : await _loadGoogleFamousSpots(
            municipality: municipality,
            center: currentCenter,
            existingDbSpots: dbSpots,
          );

    final famousSpots = _dedupeNearbySpots([
      ...dbSpots,
      ...googleSpots,
    ]);

    final packages = await _loadAdminPackages(municipality);

    return _HomeData(
      fullName: fullName,
      avatarUrl: avatarUrl,
      cityText: cityText,
      center: currentCenter,
      municipality: municipality,
      isInsideBulacan: insideBulacan,
      famousSpots: famousSpots,
      suggestionPackages: packages,
    );
  }

  Future<List<_NearbySpot>> _loadDatabaseSpots({
    required String municipality,
    required LatLng center,
  }) async {
    try {
      final rows = await supabase
          .from('tourist_spots')
          .select(
            'id, title, description, barangay, city, province, latitude, longitude, rating, image_url, status, verification_status, address, opening_hours, entrance_fee, best_time_to_visit, travel_tips, created_at',
          )
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(120)
          .timeout(const Duration(seconds: 15));

      final selectedCity = _normalText(municipality);

      return (rows as List)
          .map((row) => _NearbySpot.fromDatabase(
                row as Map<String, dynamic>,
                selectedCenter: center,
              ))
          .where((spot) {
            final city = _normalText(spot.rawCity);
            return city == selectedCity ||
                city.contains(selectedCity) ||
                selectedCity.contains(city);
          })
          .where((spot) => spot.title.trim().isNotEmpty)
          .take(10)
          .toList(growable: false);
    } catch (e) {
      debugPrint('HOME database spots unavailable: $e');
      return [];
    }
  }

  List<_NearbySpot> _dedupeNearbySpots(List<_NearbySpot> spots) {
    final seen = <String>{};
    final result = <_NearbySpot>[];

    for (final spot in spots) {
      final key = [
        _normalText(spot.title),
        _normalText(spot.rawCity),
        spot.latitude.toStringAsFixed(4),
        spot.longitude.toStringAsFixed(4),
      ].join('|');

      if (seen.add(key)) result.add(spot);
    }

    return result;
  }

  void _syncManualLocationFromStore() {
    final area = touristLocationStore.value.manualArea;
    if (area == null) return;

    for (final municipality in _bulacanMunicipalities) {
      if (municipality.name == area.name) {
        _selectedArea = municipality;
        _usingManualLocation = true;
        _lastKnownCenter = municipality.center;
        _lastMunicipality = municipality.name;
        return;
      }
    }
  }

  Future<List<_SuggestionPackage>> _loadAdminPackages(
    String? municipality,
  ) async {
    if (municipality == null) return [];

    try {
      final rows = await supabase
          .from('tour_packages')
          .select(
            'id, title, subtitle, city, price_text, duration_text, image_url, cover_image_url, status, visibility_status',
          )
          .eq('status', 'published')
          .eq('visibility_status', 'visible')
          .order('created_at', ascending: false)
          .limit(80)
          .timeout(const Duration(seconds: 15));

      final selectedCity = _normalText(municipality);

      final packages = (rows as List)
          .map((e) => _SuggestionPackage.fromMap(e as Map<String, dynamic>))
          .where((p) {
            final packageCity = _normalText(p.city);

            return packageCity == selectedCity ||
                packageCity == _normalText('$municipality Bulacan') ||
                packageCity.contains(selectedCity);
          })
          .toList();

      return packages.take(6).toList();
    } catch (e) {
      debugPrint('HOME packages unavailable: $e');
      return [];
    }
  }

  Future<List<_NearbySpot>> _loadGoogleFamousSpots({
    required String municipality,
    required LatLng center,
    required List<_NearbySpot> existingDbSpots,
  }) async {
    try {
      final suggestions = await const CitySpotSuggestionService()
          .fetchSuggestions(
            city: municipality,
            province: 'Bulacan',
            center: center,
            limit: 8,
          );

      return suggestions
          .where((suggestion) => !_matchesDatabaseSpot(suggestion, existingDbSpots))
          .map((suggestion) => _NearbySpot.fromSuggestion(suggestion))
          .toList(growable: false);
    } catch (e) {
      debugPrint('Google famous spots unavailable: $e');
      return [];
    }
  }

  bool _matchesDatabaseSpot(
    CitySpotSuggestion suggestion,
    List<_NearbySpot> dbSpots,
  ) {
    final title = _normalText(suggestion.title);
    return dbSpots.any((spot) {
      final sameTitle = _normalText(spot.title) == title;
      final nearby = (spot.latitude - suggestion.latitude).abs() <= 0.001 &&
          (spot.longitude - suggestion.longitude).abs() <= 0.001;
      return sameTitle || nearby;
    });
  }

  Future<LatLng> _resolveCurrentCenter() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return _lastKnownCenter ?? _defaultCenter;

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _lastKnownCenter ?? _defaultCenter;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12));

      final center = LatLng(position.latitude, position.longitude);
      _lastKnownCenter = center;
      _lastMunicipality = _detectBulacanMunicipality(center);

      return center;
    } catch (e) {
      debugPrint('HOME location fallback: $e');
      return _lastKnownCenter ?? _defaultCenter;
    }
  }

  Future<void> _selectMunicipality() async {
    final selected = await showModalBottomSheet<_MunicipalityArea>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Color(0xFFD8E3F1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 18, 18, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_city_rounded,
                          color: Color(0xFF2A86FF),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Choose location in Bulacan',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                      itemCount: _bulacanMunicipalities.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final m = _bulacanMunicipalities[i];
                        final selectedNow = _selectedArea?.name == m.name;

                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          tileColor: selectedNow
                              ? const Color(0xFFEFF6FF)
                              : const Color(0xFFF8FAFC),
                          leading: CircleAvatar(
                            backgroundColor: selectedNow
                                ? const Color(0xFF2A86FF)
                                : const Color(0xFFE2E8F0),
                            child: Icon(
                              selectedNow
                                  ? Icons.check_rounded
                                  : Icons.place_rounded,
                              color: selectedNow
                                  ? Colors.white
                                  : const Color(0xFF64748B),
                            ),
                          ),
                          title: Text(
                            m.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          subtitle: const Text(
                            'Show famous spots and packages here',
                          ),
                          onTap: () => Navigator.pop(context, m),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (selected == null) return;

    setState(() {
      _selectedArea = selected;
      _usingManualLocation = true;
      _lastKnownCenter = selected.center;
      _lastMunicipality = selected.name;
      _homeFuture = _loadHome();
    });

    touristLocationStore.useManualLocation(
      TouristMunicipalityArea(name: selected.name, center: selected.center),
    );

    if (_mapController.isCompleted) {
      final controller = await _mapController.future;
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(selected.center, 14.5),
      );
    }
  }

  Future<void> _usePhoneLocation() async {
    touristLocationStore.usePhoneLocation();

    setState(() {
      _usingManualLocation = false;
      _selectedArea = null;
      _homeFuture = _loadHome();
    });
  }

  Future<void> _startLocationWatch() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 250,
      );

      _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen((position) async {
        if (_usingManualLocation) return;

        final center = LatLng(position.latitude, position.longitude);
        final municipality = _detectBulacanMunicipality(center);

        final movedKm = _lastKnownCenter == null
            ? 999.0
            : _haversineKm(
                _lastKnownCenter!.latitude,
                _lastKnownCenter!.longitude,
                center.latitude,
                center.longitude,
              );

        if (municipality != _lastMunicipality || movedKm >= 1.0) {
          _lastKnownCenter = center;
          _lastMunicipality = municipality;

          if (_mapController.isCompleted) {
            final controller = await _mapController.future;
            controller.animateCamera(
              CameraUpdate.newLatLngZoom(center, 14.5),
            );
          }

          if (mounted) {
            setState(() {
              _homeFuture = _loadHome();
            });
          }
        }
      });
    } catch (e) {
      debugPrint('HOME location watch unavailable: $e');
    }
  }

  bool _isInsideBulacan(LatLng point) {
    return point.latitude >= _bulacanBounds.southwest.latitude &&
        point.latitude <= _bulacanBounds.northeast.latitude &&
        point.longitude >= _bulacanBounds.southwest.longitude &&
        point.longitude <= _bulacanBounds.northeast.longitude;
  }

  String? _detectBulacanMunicipality(LatLng point) {
    if (!_isInsideBulacan(point)) return null;

    _MunicipalityArea? nearest;
    var nearestKm = double.infinity;

    for (final area in _bulacanMunicipalities) {
      final km = _haversineKm(
        point.latitude,
        point.longitude,
        area.center.latitude,
        area.center.longitude,
      );

      if (km < nearestKm) {
        nearestKm = km;
        nearest = area;
      }
    }

    return nearest?.name;
  }

  String _normalText(String value) {
    return value
        .toLowerCase()
        .replaceAll('ñ', 'n')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .replaceAll(',', '')
        .replaceAll('.', '')
        .replaceAll('city', '')
        .replaceAll('municipality', '')
        .trim();
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;

    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return r * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final bottomInset = media.padding.bottom;

    const navBarBodyHeight = 92.0;
    final navTotalH = navBarBodyHeight + bottomInset;

    final mapH = (size.height * 0.50).clamp(320.0, 480.0);
    final sheetTop = mapH - 56;

    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
      body: FutureBuilder<_HomeData>(
        future: _homeFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _LoadingState();
          }

          if (snap.hasError) {
            return _ErrorState(
              error: snap.error.toString(),
              onRetry: () {
                setState(() {
                  _homeFuture = _loadHome();
                });
              },
            );
          }

          final data = snap.data!;
          final famousSpots = data.famousSpots.take(6).toList();
          final packages = data.suggestionPackages.take(3).toList();

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: mapH,
                child: _MapHero(
                  data: data,
                  mapController: _mapController,
                  bounds: _bulacanBounds,
                  usingManualLocation: _usingManualLocation,
                  onUsePhoneLocation: _usePhoneLocation,
                  onPickLocation: _selectMunicipality,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: sheetTop,
                bottom: navTotalH,
                child: _HomeSheet(
                  data: data,
                  famousSpots: famousSpots,
                  packages: packages,
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
          );
        },
      ),
    );
  }
}

class _MapHero extends StatelessWidget {
  const _MapHero({
    required this.data,
    required this.mapController,
    required this.bounds,
    required this.usingManualLocation,
    required this.onUsePhoneLocation,
    required this.onPickLocation,
  });

  final _HomeData data;
  final Completer<GoogleMapController> mapController;
  final LatLngBounds bounds;
  final bool usingManualLocation;
  final VoidCallback onUsePhoneLocation;
  final VoidCallback onPickLocation;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            key: ValueKey(
              '${data.center.latitude}-${data.center.longitude}-${data.cityText}',
            ),
            initialCameraPosition: CameraPosition(
              target: data.center,
              zoom: 14.5,
            ),
            onMapCreated: (controller) {
              if (!mapController.isCompleted) {
                mapController.complete(controller);
              }
            },
            cameraTargetBounds: CameraTargetBounds(bounds),
            minMaxZoomPreference: const MinMaxZoomPreference(10.5, 19.0),
            zoomControlsEnabled: false,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            buildingsEnabled: true,
            markers: {
              Marker(
                markerId: const MarkerId('selected-location'),
                position: data.center,
                infoWindow: InfoWindow(
                  title: data.cityText,
                  snippet: usingManualLocation
                      ? 'Selected location'
                      : 'Phone location',
                ),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
              ),
              ...data.famousSpots.where((s) => s.latitude != 0 && s.longitude != 0).map(
                    (s) => Marker(
                      markerId: MarkerId('spot-${s.id}'),
                      position: LatLng(s.latitude, s.longitude),
                      infoWindow: InfoWindow(
                        title: s.title,
                        snippet: s.source == _SpotSource.database
                            ? 'Saved tourist spot'
                            : s.distanceText,
                      ),
                    ),
                  ),
            },
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.38),
                    Colors.black.withValues(alpha: 0.06),
                    const Color(0xFFF6FAFF).withValues(alpha: 0.95),
                  ],
                  stops: const [0.0, 0.56, 1.0],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    _AvatarWithDot(imageUrl: data.avatarUrl),
                    const SizedBox(width: 12),
                    Expanded(child: _GreetingBlock(fullName: data.fullName)),
                    _WhiteCircleButton(
                      icon: Icons.notifications_none_rounded,
                      onTap: () {},
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _LocationChip(
                        text: data.cityText,
                        onTap: onPickLocation,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _MapActionButton(
                      icon: usingManualLocation
                          ? Icons.gps_fixed_rounded
                          : Icons.my_location_rounded,
                      onTap: () async {
                        onUsePhoneLocation();

                        if (mapController.isCompleted) {
                          final controller = await mapController.future;
                          controller.animateCamera(
                            CameraUpdate.newLatLngZoom(data.center, 14.5),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 70),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeSheet extends StatelessWidget {
  const _HomeSheet({
    required this.data,
    required this.famousSpots,
    required this.packages,
  });

  final _HomeData data;
  final List<_NearbySpot> famousSpots;
  final List<_SuggestionPackage> packages;

  @override
  Widget build(BuildContext context) {
    final selectedText = data.municipality == null
        ? 'Select a city or municipality in Bulacan'
        : '${data.municipality}, Bulacan';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFF),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 34,
            offset: const Offset(0, -14),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFD8E3F1),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _QuickStatsRow(
                    spotCount: data.famousSpots.length,
                    packageCount: data.suggestionPackages.length,
                    cityText: selectedText,
                  ),
                  const SizedBox(height: 16),
                  _MunicipalityStatus(
                    municipality: data.municipality,
                    insideBulacan: data.isInsideBulacan,
                  ),
                  const SizedBox(height: 22),
                  _SectionHeader(
                    title: data.municipality == null
                        ? 'Famous Spots'
                        : 'Famous Spots in ${data.municipality}',
                    subtitle: data.municipality == null
                        ? 'Choose a Bulacan location to see recommendations'
                        : 'Saved tourist spots and recommendations in $selectedText',
                    onSeeAll: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TouristExploreScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (famousSpots.isEmpty)
                    const _EmptyCard(
                      icon: Icons.travel_explore_rounded,
                      title: 'No famous spots found',
                      subtitle:
                          'Subtenant-created spots and Google suggestions for the selected city will appear here.',
                    )
                  else
                    SizedBox(
                      height: 224,
                      child: ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        scrollDirection: Axis.horizontal,
                        itemCount: famousSpots.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, i) =>
                            _NearbySpotCard(spot: famousSpots[i]),
                      ),
                    ),
                  const SizedBox(height: 24),
                  _SectionHeader(
                    title: data.municipality == null
                        ? 'Tour Packages'
                        : '${data.municipality} Packages',
                    subtitle: data.municipality == null
                        ? 'Choose a location to view packages'
                        : 'Only showing packages in $selectedText',
                    onSeeAll: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TouristExploreScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (packages.isEmpty)
                    const _EmptyCard(
                      icon: Icons.map_rounded,
                      title: 'No packages available yet',
                      subtitle:
                          'Admin-created tour packages for the selected city will appear here.',
                    )
                  else
                    ...packages.map(
                      (pkg) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PackageDetailsScreen(packageId: pkg.id),
                              ),
                            );
                          },
                          child: _SuggestionPackageTile(pkg: pkg),
                        ),
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

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6FAFF),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF2A86FF)),
              SizedBox(height: 16),
              Text(
                'Loading your travel guide...',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6FAFF),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: Color(0xFFDC2626),
                size: 42,
              ),
              const SizedBox(height: 14),
              const Text(
                'Unable to load home',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: _GradientButton(text: 'Retry', onPressed: onRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GreetingBlock extends StatelessWidget {
  const _GreetingBlock({required this.fullName});

  final String fullName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WELCOME BACK',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.86),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 22,
            height: 1.05,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _QuickStatsRow extends StatelessWidget {
  const _QuickStatsRow({
    required this.spotCount,
    required this.packageCount,
    required this.cityText,
  });

  final int spotCount;
  final int packageCount;
  final String cityText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatPill(
            icon: Icons.travel_explore_rounded,
            label: 'Spots',
            value: '$spotCount',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatPill(
            icon: Icons.map_rounded,
            label: 'Packages',
            value: '$packageCount',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatPill(
            icon: Icons.location_on_rounded,
            label: 'Selected',
            value: cityText.split(',').first,
          ),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF8)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2A86FF), size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _HomeData {
  final String fullName;
  final String avatarUrl;
  final String cityText;
  final LatLng center;
  final String? municipality;
  final bool isInsideBulacan;
  final List<_NearbySpot> famousSpots;
  final List<_SuggestionPackage> suggestionPackages;

  _HomeData({
    required this.fullName,
    required this.avatarUrl,
    required this.cityText,
    required this.center,
    required this.municipality,
    required this.isInsideBulacan,
    required this.famousSpots,
    required this.suggestionPackages,
  });
}

class _MunicipalityArea {
  final String name;
  final LatLng center;

  const _MunicipalityArea({required this.name, required this.center});
}

const _bulacanMunicipalities = [
  _MunicipalityArea(name: 'Bustos', center: LatLng(14.9597, 120.9206)),
  _MunicipalityArea(name: 'Baliwag', center: LatLng(14.9547, 120.8969)),
  _MunicipalityArea(name: 'Malolos', center: LatLng(14.8434, 120.8114)),
  _MunicipalityArea(name: 'Pulilan', center: LatLng(14.9017, 120.8492)),
  _MunicipalityArea(name: 'Plaridel', center: LatLng(14.8873, 120.8572)),
  _MunicipalityArea(name: 'San Rafael', center: LatLng(15.0265, 120.9283)),
  _MunicipalityArea(name: 'San Ildefonso', center: LatLng(15.0809, 120.9410)),
  _MunicipalityArea(name: 'San Miguel', center: LatLng(15.1458, 120.9783)),
  _MunicipalityArea(name: 'Calumpit', center: LatLng(14.9164, 120.7658)),
  _MunicipalityArea(name: 'Hagonoy', center: LatLng(14.8340, 120.7328)),
  _MunicipalityArea(name: 'Paombong', center: LatLng(14.8319, 120.7897)),
  _MunicipalityArea(name: 'Guiguinto', center: LatLng(14.8333, 120.8833)),
  _MunicipalityArea(name: 'Balagtas', center: LatLng(14.8167, 120.8667)),
  _MunicipalityArea(name: 'Bocaue', center: LatLng(14.7983, 120.9261)),
  _MunicipalityArea(name: 'Marilao', center: LatLng(14.7581, 120.9481)),
  _MunicipalityArea(name: 'Meycauayan', center: LatLng(14.7369, 120.9608)),
  _MunicipalityArea(name: 'Norzagaray', center: LatLng(14.9109, 121.0493)),
  _MunicipalityArea(name: 'Santa Maria', center: LatLng(14.8208, 120.9636)),
  _MunicipalityArea(name: 'Angat', center: LatLng(14.9285, 121.0292)),
  _MunicipalityArea(name: 'Pandi', center: LatLng(14.8650, 120.9572)),
  _MunicipalityArea(name: 'Obando', center: LatLng(14.7098, 120.9362)),
  _MunicipalityArea(name: 'Bulakan', center: LatLng(14.7928, 120.8789)),
  _MunicipalityArea(
    name: 'Dona Remedios Trinidad',
    center: LatLng(15.0005, 121.0838),
  ),
  _MunicipalityArea(
    name: 'San Jose del Monte',
    center: LatLng(14.8139, 121.0453),
  ),
];

enum _SpotSource { database, google }

class _NearbySpot {
  final String id;
  final String title;
  final String city;
  final String rawCity;
  final String barangay;
  final String description;
  final double latitude;
  final double longitude;
  final double rating;
  final String imageUrl;
  final String tag;
  final double distanceKm;
  final _SpotSource source;

  const _NearbySpot({
    required this.id,
    required this.title,
    required this.city,
    required this.rawCity,
    required this.barangay,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.imageUrl,
    required this.tag,
    required this.distanceKm,
    required this.source,
  });

  factory _NearbySpot.fromSuggestion(CitySpotSuggestion suggestion) {
    return _NearbySpot(
      id: suggestion.id,
      title: suggestion.title,
      city: '${suggestion.city}, ${suggestion.province}',
      rawCity: suggestion.city,
      barangay: suggestion.address,
      description: suggestion.description,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude,
      rating: suggestion.rating,
      imageUrl: suggestion.imageUrl,
      tag: suggestion.category,
      distanceKm: suggestion.distanceKm,
      source: _SpotSource.google,
    );
  }

  factory _NearbySpot.fromDatabase(
    Map<String, dynamic> map, {
    required LatLng selectedCenter,
  }) {
    final latitude = _readDouble(map['latitude']);
    final longitude = _readDouble(map['longitude']);
    final city = _readString(map['city']);
    final province = _readString(map['province'], fallback: 'Bulacan');
    final distanceKm = latitude == 0 || longitude == 0
        ? 0.0
        : _distanceKm(
            selectedCenter.latitude,
            selectedCenter.longitude,
            latitude,
            longitude,
          );

    final verification = _readString(
      map['verification_status'],
      fallback: 'pending',
    );

    return _NearbySpot(
      id: map['id']?.toString() ?? '',
      title: _readString(map['title'], fallback: 'Untitled Spot'),
      city: '$city, $province',
      rawCity: city,
      barangay: _readString(map['barangay']).isNotEmpty
          ? _readString(map['barangay'])
          : _readString(map['address']),
      description: _readString(map['description']),
      latitude: latitude,
      longitude: longitude,
      rating: _readDouble(map['rating']).clamp(0.0, 5.0),
      imageUrl: _readString(map['image_url']),
      tag: verification == 'verified' ? 'Verified Spot' : 'Saved Spot',
      distanceKm: distanceKm,
      source: _SpotSource.database,
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

  static double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2radStatic(lat2 - lat1);
    final dLon = _deg2radStatic(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2radStatic(lat1)) *
            math.cos(_deg2radStatic(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _deg2radStatic(double deg) => deg * (math.pi / 180);

  String get distanceText {
    if (source == _SpotSource.database && distanceKm == 0) return 'Saved spot';
    if (distanceKm < 1) return '${(distanceKm * 1000).round()}m away';
    return '${distanceKm.toStringAsFixed(1)}km away';
  }

  String get imageForCard {
    if (imageUrl.isNotEmpty) return imageUrl;
    if (latitude != 0 && longitude != 0) {
      return CitySpotSuggestionService.buildStaticMapUrl(
        latitude: latitude,
        longitude: longitude,
      );
    }
    return '';
  }
}

class _SuggestionPackage {
  final dynamic id;
  final String title;
  final String subtitle;
  final String city;
  final String priceText;
  final String durationText;
  final String imageUrl;

  const _SuggestionPackage({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.city,
    required this.priceText,
    required this.durationText,
    required this.imageUrl,
  });

  factory _SuggestionPackage.fromMap(Map<String, dynamic> m) {
    final cover = (m['cover_image_url'] as String?) ?? '';
    final image = cover.isNotEmpty
        ? cover
        : ((m['image_url'] as String?) ?? '');

    return _SuggestionPackage(
      id: m['id'],
      title: (m['title'] as String?) ?? 'Untitled Package',
      subtitle: (m['subtitle'] as String?) ?? '',
      city: (m['city'] as String?) ?? '',
      priceText: (m['price_text'] as String?) ?? 'Ask admin',
      durationText: (m['duration_text'] as String?) ?? 'Flexible',
      imageUrl: image,
    );
  }
}

class _AvatarWithDot extends StatelessWidget {
  const _AvatarWithDot({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 66,
      height: 66,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 2.5,
                ),
              ),
              child: ClipOval(
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        width: 66,
                        height: 66,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _AvatarFallback(),
                      )
                    : const _AvatarFallback(),
              ),
            ),
          ),
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE2E8F0),
      child: const Icon(
        Icons.person_rounded,
        size: 34,
        color: Color(0xFF94A3B8),
      ),
    );
  }
}

class _WhiteCircleButton extends StatelessWidget {
  const _WhiteCircleButton({
    required this.icon,
    required this.onTap,
    this.size = 48,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF2A86FF)),
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _WhiteCircleButton(icon: icon, onTap: onTap, size: 46);
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              const Icon(Icons.location_on_rounded, color: Color(0xFF2A86FF)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _MunicipalityStatus extends StatelessWidget {
  const _MunicipalityStatus({
    required this.municipality,
    required this.insideBulacan,
  });

  final String? municipality;
  final bool insideBulacan;

  @override
  Widget build(BuildContext context) {
    final title = municipality == null
        ? 'Choose your Bulacan location'
        : '$municipality Suggestions';

    final subtitle = municipality == null
        ? 'Tap the location field above and select a city or municipality in Bulacan.'
        : 'Saved tourist spots, famous places, and packages are filtered for $municipality only.';

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFF6FF), Color(0xFFF0FDF4)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD6E8FF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              municipality == null
                  ? Icons.location_searching_rounded
                  : Icons.auto_awesome_rounded,
              color: municipality == null
                  ? const Color(0xFF64748B)
                  : const Color(0xFF2A86FF),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    height: 1.28,
                    fontSize: 12.5,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.onSeeAll,
  });

  final String title;
  final String subtitle;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onSeeAll,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF2A86FF),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
          child: const Text('See All'),
        ),
      ],
    );
  }
}

class _NearbySpotCard extends StatelessWidget {
  const _NearbySpotCard({required this.spot});

  final _NearbySpot spot;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 178,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.11),
            blurRadius: 22,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (spot.imageForCard.isNotEmpty)
              Image.network(
                spot.imageForCard,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFFE2E8F0),
                  child: const Center(
                    child: Icon(
                      Icons.image_not_supported_rounded,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              )
            else
              Container(
                color: const Color(0xFFE2E8F0),
                child: const Center(
                  child: Icon(
                    Icons.place_rounded,
                    color: Color(0xFF94A3B8),
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
                      Colors.black.withValues(alpha: 0.06),
                      Colors.black.withValues(alpha: 0.76),
                    ],
                    stops: const [0.42, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 11,
              right: 11,
              child: _RatingBadge(rating: spot.rating),
            ),
            Positioned(top: 11, left: 11, child: _CategoryBadge(tag: spot.tag)),
            Positioned(
              left: 13,
              right: 13,
              bottom: 13,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    spot.distanceText,
                    style: const TextStyle(
                      color: Color(0xFF93C5FD),
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        color: Colors.white70,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          spot.barangay.isEmpty ? spot.city : spot.barangay,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
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
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tag,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: Color(0xFFFFD166), size: 16),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionPackageTile extends StatelessWidget {
  const _SuggestionPackageTile({required this.pkg});

  final _SuggestionPackage pkg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF8)),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: SizedBox(
              width: 78,
              height: 78,
              child: pkg.imageUrl.isNotEmpty
                  ? Image.network(
                      pkg.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _PackageImageFallback(),
                    )
                  : const _PackageImageFallback(),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pkg.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  pkg.subtitle.isEmpty ? pkg.city : pkg.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MiniInfoPill(
                        icon: Icons.payments_rounded,
                        text: pkg.priceText,
                        color: const Color(0xFF2A86FF),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniInfoPill(
                        icon: Icons.schedule_rounded,
                        text: pkg.durationText,
                        color: const Color(0xFF64748B),
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

class _MiniInfoPill extends StatelessWidget {
  const _MiniInfoPill({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF8)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF2A86FF)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    fontSize: 12.5,
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

class _PackageImageFallback extends StatelessWidget {
  const _PackageImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF2FF),
      child: const Icon(Icons.map_rounded, color: Color(0xFF2A86FF)),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.text, required this.onPressed});

  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF), Color(0xFF1D4ED8)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A86FF).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
