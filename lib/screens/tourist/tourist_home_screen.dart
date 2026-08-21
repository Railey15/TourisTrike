import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/recommendations/tourist_ai_recommendation_service.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';

import 'package:touristrike/screens/tourist/profile/tourist_profile_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_tourist.dart';
import 'package:touristrike/components/tourist/ai_chatbot_floating_widget.dart';
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

  final TouristAiRecommendationService _recommendationService =
      const TouristAiRecommendationService();

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

  Set<String> _activeMunicipalities = {};

  // AI Preferences
  String _prefLocation = '';
  List<String> _prefCategories = [];
  bool _prefLoaded = false;

  @override
  void initState() {
    super.initState();

    if (!touristLocationStore.usePhoneLocationForFirstHomeOpen()) {
      _syncManualLocationFromStore();
    }

    _homeFuture = _loadHome();
    _startLocationWatch();
    _loadPreferences();
    _loadActiveMunicipalities();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<_HomeData> _loadHome() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      debugPrint(
        'HOME preview: no authenticated user present '
        '(running web preview).',
      );
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

    final profile = (user != null)
        ? await supabase
              .from('profiles')
              .select('full_name, profile_image_url')
              .eq('id', user.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 15))
        : null;

    final fullName =
        (profile?['full_name'] as String?)?.trim().isNotEmpty == true
        ? profile!['full_name'] as String
        : 'Tourist';

    final avatarUrl = (profile?['profile_image_url'] as String?) ?? '';

    final allSpots = municipality == null
        ? <_NearbySpot>[]
        : (await _recommendationService.loadMunicipalitySpots(
            municipality: municipality,
            center: currentCenter,
            googleLimit: 20,
          )).map(_NearbySpot.fromRecommendationSpot).toList(growable: false);

    final famousSpots = _buildFamousSpots(allSpots);

    final packages = await _loadAdminPackages(municipality);

    return _HomeData(
      fullName: fullName,
      avatarUrl: avatarUrl,
      cityText: cityText,
      center: currentCenter,
      municipality: municipality,
      isInsideBulacan: insideBulacan,
      allSpots: allSpots,
      famousSpots: famousSpots,
      suggestionPackages: packages,
    );
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
            'id, title, subtitle, city, price_text, duration_text, '
            'image_url, cover_image_url, status, visibility_status',
          )
          .eq('status', 'published')
          .eq('visibility_status', 'visible')
          .order('created_at', ascending: false)
          .limit(80)
          .timeout(const Duration(seconds: 15));

      final selectedCity = _normalText(municipality);

      final packages = (rows as List)
          .map(
            (e) => _SuggestionPackage.fromMap(
              e as Map<String, dynamic>,
            ),
          )
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

  List<_NearbySpot> _buildFamousSpots(List<_NearbySpot> spots) {
    final ranked = List<_NearbySpot>.from(spots)
      ..sort((a, b) {
        final scoreA = (a.rating * 100) - (a.distanceKm * 8);
        final scoreB = (b.rating * 100) - (b.distanceKm * 8);

        return scoreB.compareTo(scoreA);
      });

    return ranked.take(10).toList(growable: false);
  }

  Future<LatLng> _resolveCurrentCenter() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();

      if (!enabled) {
        return _lastKnownCenter ?? _defaultCenter;
      }

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

      final center = LatLng(
        position.latitude,
        position.longitude,
      );

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
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 11),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCE5F0),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      20,
                      20,
                      14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF4FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.location_city_rounded,
                            color: Color(0xFF2185F5),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Choose your location',
                                style: TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Cities and municipalities in Bulacan',
                                style: TextStyle(
                                  color: Color(0xFF8A98AB),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFF0F4F8),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        14,
                        12,
                        14,
                        24,
                      ),
                      itemCount: _bulacanMunicipalities.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 7),
                      itemBuilder: (_, i) {
                        final m = _bulacanMunicipalities[i];

                        final selectedNow =
                            _selectedArea?.name == m.name;

                        final isActive =
                            _activeMunicipalities.contains(m.name);

                        return Material(
                          color: selectedNow
                              ? const Color(0xFFEDF6FF)
                              : const Color(0xFFF8FAFD),
                          borderRadius: BorderRadius.circular(17),
                          child: InkWell(
                            onTap: () =>
                                Navigator.pop(context, m),
                            borderRadius: BorderRadius.circular(17),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: selectedNow
                                          ? const Color(0xFF2185F5)
                                          : isActive
                                          ? const Color(0xFFE5F9EC)
                                          : const Color(0xFFEDF1F5),
                                      borderRadius:
                                          BorderRadius.circular(13),
                                    ),
                                    child: Icon(
                                      selectedNow
                                          ? Icons.check_rounded
                                          : isActive
                                          ? Icons
                                                .local_activity_rounded
                                          : Icons.place_outlined,
                                      color: selectedNow
                                          ? Colors.white
                                          : isActive
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFF8A98AB),
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m.name,
                                          style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w700,
                                            color: Color(0xFF182235),
                                            fontSize: 14.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          isActive
                                              ? 'Packages & destinations available'
                                              : 'No listings yet',
                                          style: TextStyle(
                                            color: isActive
                                                ? const Color(
                                                    0xFF16A34A,
                                                  )
                                                : const Color(
                                                    0xFF9AA7B8,
                                                  ),
                                            fontSize: 11.5,
                                            fontWeight:
                                                FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFFB7C2CF),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
      TouristMunicipalityArea(
        name: selected.name,
        center: selected.center,
      ),
    );

    if (_mapController.isCompleted) {
      final controller = await _mapController.future;

      controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          selected.center,
          14.5,
        ),
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

      _positionSub =
          Geolocator.getPositionStream(
            locationSettings: settings,
          ).listen((position) async {
            if (_usingManualLocation) return;

            final center = LatLng(
              position.latitude,
              position.longitude,
            );

            final municipality =
                _detectBulacanMunicipality(center);

            final movedKm = _lastKnownCenter == null
                ? 999.0
                : _haversineKm(
                    _lastKnownCenter!.latitude,
                    _lastKnownCenter!.longitude,
                    center.latitude,
                    center.longitude,
                  );

            if (municipality != _lastMunicipality ||
                movedKm >= 1.0) {
              _lastKnownCenter = center;
              _lastMunicipality = municipality;

              if (_mapController.isCompleted) {
                final controller =
                    await _mapController.future;

                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    center,
                    14.5,
                  ),
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
      debugPrint(
        'HOME location watch unavailable: $e',
      );
    }
  }

  Future<void> _loadActiveMunicipalities() async {
    try {
      final rows = await supabase
          .from('tour_packages')
          .select('city')
          .eq('status', 'published')
          .eq('visibility_status', 'visible');

      if (!mounted) return;

      setState(() {
        _activeMunicipalities = {
          for (final row in rows as List)
            if (row['city'] is String &&
                (row['city'] as String).trim().isNotEmpty)
              (row['city'] as String).trim(),
        };
      });
    } catch (_) {}
  }

  Future<void> _loadPreferences() async {
    final user = supabase.auth.currentUser;

    if (user == null) return;

    try {
      final row = await supabase
          .from('tourist_preferences')
          .select(
            'preferred_location, preferred_categories',
          )
          .eq('tourist_id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _prefLocation =
            (row?['preferred_location'] as String?) ?? '';

        final cats = row?['preferred_categories'];

        _prefCategories = cats is List
            ? cats.map((e) => e.toString()).toList()
            : <String>[];

        _prefLoaded = true;
      });

      _showFirstTimePreferencePopupIfNeeded();
    } catch (_) {
      if (!mounted) return;

      setState(() => _prefLoaded = true);

      _showFirstTimePreferencePopupIfNeeded();
    }
  }

  void _showFirstTimePreferencePopupIfNeeded() {
    final hasPreferences =
        _prefLocation.trim().isNotEmpty ||
        _prefCategories.isNotEmpty;

    if (hasPreferences || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _showPreferencesSheet(
        forceSetup: true,
      );
    });
  }

  Future<void> _showPreferencesSheet({
    bool forceSetup = false,
  }) async {
    final result =
        await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          isDismissible: !forceSetup,
          enableDrag: !forceSetup,
          builder: (_) => _PreferencesSheet(
            initialLocation: _prefLocation,
            initialCategories: _prefCategories,
            forceSetup: forceSetup,
          ),
        );

    if (result == null) {
      if (forceSetup) {
        _showFirstTimePreferencePopupIfNeeded();
      }

      return;
    }

    final location = result['location'] as String;
    final categories =
        result['categories'] as List<String>;

    setState(() {
      _prefLocation = location;
      _prefCategories = categories;
    });

    final user = supabase.auth.currentUser;

    if (user == null) return;

    try {
      await supabase.from('tourist_preferences').upsert({
        'tourist_id': user.id,
        'preferred_location': location,
        'preferred_categories': categories,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'tourist_id');
    } catch (e) {
      debugPrint(
        'Preferences save failed: $e',
      );
    }
  }

  bool _isInsideBulacan(LatLng point) {
    return point.latitude >=
            _bulacanBounds.southwest.latitude &&
        point.latitude <=
            _bulacanBounds.northeast.latitude &&
        point.longitude >=
            _bulacanBounds.southwest.longitude &&
        point.longitude <=
            _bulacanBounds.northeast.longitude;
  }

  String? _detectBulacanMunicipality(
    LatLng point,
  ) {
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
        .replaceAll('.', '');
  }

  double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371.0;

    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 *
        math.atan2(
          math.sqrt(a),
          math.sqrt(1 - a),
        );

    return r * c;
  }

  double _deg2rad(double deg) =>
      deg * (math.pi / 180);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final bottomInset = media.padding.bottom;

    const navBarBodyHeight = 92.0;
    final navTotalH =
        navBarBodyHeight + bottomInset;

    // UI improvement:
    // Keeps the map useful without allowing it to dominate the
    // screen on tall mobile devices.
    final mapH =
        (size.height * 0.43).clamp(345.0, 420.0);

    final sheetTop = mapH - 35;

    return TouristAiChatbotWrapper(
      child: Scaffold(
        backgroundColor:
            const Color(0xFFF7F9FC),
        body: FutureBuilder<_HomeData>(
          future: _homeFuture,
          builder: (context, snap) {
            if (snap.connectionState !=
                ConnectionState.done) {
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

            final packages =
                data.suggestionPackages
                    .take(3)
                    .toList();

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
                    mapController:
                        _mapController,
                    bounds:
                        _bulacanBounds,
                    usingManualLocation:
                        _usingManualLocation,
                    onUsePhoneLocation:
                        _usePhoneLocation,
                    onPickLocation:
                        _selectMunicipality,
                    onProfileTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const ProfileScreen(),
                        ),
                      );
                    },
                  ),
                ),

                Positioned(
                  left: 0,
                  right: 0,
                  top: sheetTop,
                  bottom: navTotalH,
                  child: _HomeSheet(
                    data: data,
                    packages: packages,
                    prefLocation:
                        _prefLocation,
                    prefCategories:
                        _prefCategories,
                    prefLoaded:
                        _prefLoaded,
                    onSetPreferences:
                        _showPreferencesSheet,
                  ),
                ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AppBottomNav(
                    selectedIndex:
                        _navIndex,
                    onSelect: (i) {
                      setState(() {
                        _navIndex = i;
                      });
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// MAP HERO
// ============================================================================

class _MapHero extends StatelessWidget {
  const _MapHero({
    required this.data,
    required this.mapController,
    required this.bounds,
    required this.usingManualLocation,
    required this.onUsePhoneLocation,
    required this.onPickLocation,
    required this.onProfileTap,
  });

  final _HomeData data;
  final Completer<GoogleMapController>
  mapController;
  final LatLngBounds bounds;
  final bool usingManualLocation;
  final VoidCallback onUsePhoneLocation;
  final VoidCallback onPickLocation;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            key: ValueKey(
              '${data.center.latitude}-'
              '${data.center.longitude}-'
              '${data.cityText}',
            ),
            initialCameraPosition:
                CameraPosition(
                  target: data.center,
                  zoom: 14.5,
                ),
            onMapCreated: (controller) {
              if (!mapController.isCompleted) {
                mapController.complete(
                  controller,
                );
              }
            },
            cameraTargetBounds:
                CameraTargetBounds(bounds),
            minMaxZoomPreference:
                const MinMaxZoomPreference(
                  10.5,
                  19.0,
                ),
            zoomControlsEnabled: false,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            buildingsEnabled: true,
            markers: {
              Marker(
                markerId:
                    const MarkerId(
                      'selected-location',
                    ),
                position: data.center,
                infoWindow: InfoWindow(
                  title: data.cityText,
                  snippet:
                      usingManualLocation
                      ? 'Selected location'
                      : 'Phone location',
                ),
                icon:
                    BitmapDescriptor
                        .defaultMarkerWithHue(
                          BitmapDescriptor
                              .hueAzure,
                        ),
              ),
              ...data.famousSpots.map(
                (s) => Marker(
                  markerId: MarkerId(
                    'spot-${s.id}',
                  ),
                  position: LatLng(
                    s.latitude,
                    s.longitude,
                  ),
                  infoWindow: InfoWindow(
                    title: s.title,
                    snippet:
                        s.distanceText,
                  ),
                ),
              ),
            },
          ),
        ),

        // Softer map overlay for improved readability.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin:
                      Alignment.topCenter,
                  end:
                      Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(
                      alpha: 0.33,
                    ),
                    Colors.black.withValues(
                      alpha: 0.06,
                    ),
                    Colors.black.withValues(
                      alpha: 0.02,
                    ),
                    const Color(
                      0xFFF7F9FC,
                    ).withValues(
                      alpha: 0.62,
                    ),
                  ],
                  stops: const [
                    0.0,
                    0.35,
                    0.72,
                    1.0,
                  ],
                ),
              ),
            ),
          ),
        ),

        SafeArea(
          bottom: false,
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(
                  18,
                  10,
                  18,
                  0,
                ),
            child: Column(
              children: [
                Row(
                  children: [
                    _AvatarWithDot(
                      imageUrl:
                          data.avatarUrl,
                    ),
                    const SizedBox(
                      width: 11,
                    ),
                    Expanded(
                      child: _GreetingBlock(
                        fullName:
                            data.fullName,
                      ),
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    _WhiteCircleButton(
                      icon: Icons
                          .person_outline_rounded,
                      onTap:
                          onProfileTap,
                    ),
                  ],
                ),

                const Spacer(),

                Align(
                  alignment:
                      Alignment.centerLeft,
                  child: Padding(
                    padding:
                        const EdgeInsets.only(
                          left: 2,
                          bottom: 9,
                        ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        const Text(
                          'Where do you want to go?',
                          style: TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight.w800,
                            fontSize: 19,
                            letterSpacing:
                                -0.35,
                            shadows: [
                              Shadow(
                                blurRadius: 9,
                                color:
                                    Colors.black26,
                                offset:
                                    Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          'Discover places, packages and experiences nearby',
                          style: TextStyle(
                            color: Colors.white
                                .withValues(
                                  alpha:
                                      0.88,
                                ),
                            fontWeight:
                                FontWeight.w500,
                            fontSize: 11.5,
                            shadows: const [
                              Shadow(
                                blurRadius: 8,
                                color:
                                    Colors.black26,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Row(
                  children: [
                    Expanded(
                      child:
                          _LocationChip(
                            text:
                                data.cityText,
                            onTap:
                                onPickLocation,
                          ),
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    _MapActionButton(
                      icon:
                          usingManualLocation
                          ? Icons
                                .gps_fixed_rounded
                          : Icons
                                .my_location_rounded,
                      onTap: () async {
                        onUsePhoneLocation();

                        if (mapController
                            .isCompleted) {
                          final controller =
                              await mapController
                                  .future;

                          controller
                              .animateCamera(
                            CameraUpdate
                                .newLatLngZoom(
                                  data.center,
                                  14.5,
                                ),
                          );
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(
                  height: 58,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// HOME CONTENT
// ============================================================================

class _HomeSheet extends StatelessWidget {
  const _HomeSheet({
    required this.data,
    required this.packages,
    required this.prefLocation,
    required this.prefCategories,
    required this.prefLoaded,
    required this.onSetPreferences,
  });

  final _HomeData data;
  final List<_SuggestionPackage> packages;
  final String prefLocation;
  final List<String> prefCategories;
  final bool prefLoaded;
  final VoidCallback onSetPreferences;

  static const TouristAiRecommendationService
  _recommendationService =
      TouristAiRecommendationService();

  bool _spotMatchesPreferredCategory(
    _NearbySpot spot,
  ) {
    return _recommendationService
        .matchesPreferredCategory(
          spot.toRecommendationSpot(),
          prefCategories,
        );
  }

  List<_NearbySpot>
  _rankedPreferredSpots() {
    final locationKey =
        prefLocation.trim().toLowerCase();

    final matched =
        data.allSpots
            .where(
              _spotMatchesPreferredCategory,
            )
            .map((spot) {
              var score = 0.0;

              final spotText =
                  '${spot.title} '
                          '${spot.description} '
                          '${spot.city} '
                          '${spot.barangay} '
                          '${spot.tag}'
                      .toLowerCase();

              score += 25;
              score += spot.rating * 6;
              score += math.max(
                0,
                12 - spot.distanceKm,
              );

              if (locationKey.isNotEmpty &&
                  spotText.contains(
                    locationKey,
                  )) {
                score += 8;
              }

              return MapEntry(
                spot,
                score,
              );
            })
            .toList()
          ..sort(
            (a, b) => b.value
                .compareTo(a.value),
          );

    return matched
        .map((entry) => entry.key)
        .take(6)
        .toList(growable: false);
  }

  List<_NearbySpot>
  _exploreBeyondPreferences(
    List<_NearbySpot> preferred,
  ) {
    final preferredIds =
        preferred.map((spot) => spot.id).toSet();

    final outside =
        data.allSpots.where((spot) {
          return !preferredIds.contains(
                spot.id,
              ) &&
              !_spotMatchesPreferredCategory(
                spot,
              );
        }).toList()
          ..sort((a, b) {
            final scoreA =
                (a.rating * 100) -
                (a.distanceKm * 8);

            final scoreB =
                (b.rating * 100) -
                (b.distanceKm * 8);

            return scoreB.compareTo(
              scoreA,
            );
          });

    return outside
        .take(6)
        .toList(growable: false);
  }

  List<_NearbySpot>
  _famousSpotsExcluding(
    List<_NearbySpot> excluded,
  ) {
    final excludedIds =
        excluded.map((spot) => spot.id).toSet();

    final ranked = data.famousSpots
        .where(
          (spot) =>
              !excludedIds.contains(
                spot.id,
              ),
        )
        .toList(growable: false);

    if (ranked.isNotEmpty) {
      return ranked
          .take(6)
          .toList(growable: false);
    }

    return data.famousSpots
        .take(6)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final selectedText =
        data.municipality == null
        ? 'Select a city or municipality in Bulacan'
        : '${data.municipality}, Bulacan';

    final preferredSpots =
        _rankedPreferredSpots();

    final beyondPreferenceSpots =
        _exploreBeyondPreferences(
          preferredSpots,
        );

    final famousSpots =
        _famousSpotsExcluding([
          ...preferredSpots,
          ...beyondPreferenceSpots,
        ]);

    final hasPreferences =
        prefCategories.isNotEmpty ||
        prefLocation.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius:
            const BorderRadius.vertical(
              top: Radius.circular(30),
            ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF25334A,
            ).withValues(
              alpha: 0.13,
            ),
            blurRadius: 28,
            offset: const Offset(
              0,
              -10,
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),

          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(
                0xFFD8E1EC,
              ),
              borderRadius:
                  BorderRadius.circular(
                    100,
                  ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              physics:
                  const BouncingScrollPhysics(),
              padding:
                  const EdgeInsets.fromLTRB(
                    18,
                    13,
                    18,
                    30,
                  ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  if (hasPreferences)
                    _HomePreferenceEditRow(
                      hasPreferences:
                          hasPreferences,
                      prefLocation:
                          prefLocation,
                      prefCategories:
                          prefCategories,
                      onEdit:
                          onSetPreferences,
                    )
                  else
                    _PreferenceEmptyState(
                      onSetPreferences:
                          onSetPreferences,
                    ),

                  if (hasPreferences) ...[
                    const SizedBox(
                      height: 24,
                    ),
                    _RecommendedSection(
                      title:
                          'Recommended For You',
                      subtitle:
                          prefCategories
                              .isEmpty
                          ? 'Places matching your selected destination'
                          : 'Picked from your ${prefCategories.take(3).join(', ')} interests',
                      icon: Icons
                          .auto_awesome_rounded,
                      iconColor:
                          const Color(
                            0xFF2185F5,
                          ),
                      emptyTitle:
                          'No exact matches yet',
                      emptySubtitle:
                          'Try choosing more interests or another Bulacan city to improve your suggestions.',
                      spots:
                          preferredSpots,
                    ),
                    const SizedBox(
                      height: 27,
                    ),
                    _RecommendedSection(
                      title:
                          'Explore Something New',
                      subtitle:
                          'Discover places beyond your usual interests',
                      icon: Icons
                          .explore_outlined,
                      iconColor:
                          const Color(
                            0xFF64748B,
                          ),
                      emptyTitle:
                          'No extra suggestions yet',
                      emptySubtitle:
                          'More places will appear once nearby destinations become available.',
                      spots:
                          beyondPreferenceSpots,
                    ),
                  ],

                  const SizedBox(
                    height: 28,
                  ),

                  _SectionHeader(
                    title:
                        data.municipality ==
                            null
                        ? 'Famous Spots'
                        : 'Famous Spots in ${data.municipality}',
                    subtitle:
                        data.municipality ==
                            null
                        ? 'Choose a Bulacan location to discover destinations'
                        : 'Popular destinations around $selectedText',
                    onSeeAll: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const TouristExploreScreen(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(
                    height: 13,
                  ),

                  if (famousSpots.isEmpty)
                    const _EmptyCard(
                      icon: Icons
                          .travel_explore_rounded,
                      title:
                          'No famous spots found',
                      subtitle:
                          'Choose another Bulacan city or refresh your phone location to discover places.',
                    )
                  else
                    SizedBox(
                      height: 215,
                      child:
                          ListView.separated(
                            physics:
                                const BouncingScrollPhysics(),
                            clipBehavior:
                                Clip.none,
                            scrollDirection:
                                Axis.horizontal,
                            itemCount:
                                famousSpots.length,
                            separatorBuilder:
                                (_, _) =>
                                    const SizedBox(
                                      width:
                                          12,
                                    ),
                            itemBuilder:
                                (_, i) =>
                                    _NearbySpotCard(
                                      spot:
                                          famousSpots[i],
                                    ),
                          ),
                    ),

                  const SizedBox(
                    height: 29,
                  ),

                  _SectionHeader(
                    title:
                        data.municipality ==
                            null
                        ? 'Tour Packages'
                        : '${data.municipality} Packages',
                    subtitle:
                        data.municipality ==
                            null
                        ? 'Choose a location to view available packages'
                        : 'Curated experiences available in $selectedText',
                    onSeeAll: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const TouristExploreScreen(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(
                    height: 13,
                  ),

                  if (packages.isEmpty)
                    const _EmptyCard(
                      icon:
                          Icons.map_rounded,
                      title:
                          'No packages available yet',
                      subtitle:
                          'Admin-created tour packages for this location will appear here.',
                    )
                  else
                    ...packages.map(
                      (pkg) => Padding(
                        padding:
                            const EdgeInsets.only(
                              bottom: 11,
                            ),
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(
                                19,
                              ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PackageDetailsScreen(
                                      packageId:
                                          pkg.id,
                                    ),
                              ),
                            );
                          },
                          child:
                              _SuggestionPackageTile(
                                pkg: pkg,
                              ),
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

// ============================================================================
// LOADING / ERROR
// ============================================================================

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F9FC),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.symmetric(
            horizontal: 30,
            vertical: 25,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFEDF1F6),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF25334A,
                ).withValues(
                  alpha: 0.07,
                ),
                blurRadius: 25,
                offset: const Offset(
                  0,
                  12,
                ),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child:
                    CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(
                        0xFF2185F5,
                      ),
                    ),
              ),
              SizedBox(height: 15),
              Text(
                'Loading your travel guide...',
                style: TextStyle(
                  color: Color(
                    0xFF64748B,
                  ),
                  fontWeight:
                      FontWeight.w600,
                  fontSize: 13,
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
  const _ErrorState({
    required this.error,
    required this.onRetry,
  });

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F9FC),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(24),
            border: Border.all(
              color:
                  const Color(0xFFEDF1F6),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF25334A,
                ).withValues(
                  alpha: 0.08,
                ),
                blurRadius: 25,
                offset: const Offset(
                  0,
                  12,
                ),
              ),
            ],
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration:
                    const BoxDecoration(
                      color: Color(
                        0xFFFFECEC,
                      ),
                      shape:
                          BoxShape.circle,
                    ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: Color(
                    0xFFDC2626,
                  ),
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Unable to load home',
                style: TextStyle(
                  color: Color(
                    0xFF172033,
                  ),
                  fontSize: 19,
                  fontWeight:
                      FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                error,
                textAlign:
                    TextAlign.center,
                style: const TextStyle(
                  color: Color(
                    0xFF728096,
                  ),
                  fontWeight:
                      FontWeight.w500,
                  height: 1.4,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 19),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: _GradientButton(
                  text: 'Try Again',
                  onPressed: onRetry,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// MAP HEADER WIDGETS
// ============================================================================

class _GreetingBlock extends StatelessWidget {
  const _GreetingBlock({
    required this.fullName,
  });

  final String fullName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          'WELCOME BACK',
          style: TextStyle(
            color: Colors.white.withValues(
              alpha: 0.82,
            ),
            fontWeight: FontWeight.w700,
            letterSpacing: 1.05,
            fontSize: 10.5,
            shadows: const [
              Shadow(
                color: Colors.black26,
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          fullName,
          maxLines: 1,
          overflow:
              TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight:
                FontWeight.w800,
            fontSize: 20,
            height: 1.08,
            letterSpacing: -0.35,
            shadows: [
              Shadow(
                color: Colors.black26,
                blurRadius: 7,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvatarWithDot extends StatelessWidget {
  const _AvatarWithDot({
    required this.imageUrl,
  });

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color:
                      Colors.white.withValues(
                        alpha: 0.96,
                      ),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(
                          alpha: 0.13,
                        ),
                    blurRadius: 14,
                    offset:
                        const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipOval(
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, _, _) =>
                                const _AvatarFallback(),
                      )
                    : const _AvatarFallback(),
              ),
            ),
          ),
          Positioned(
            right: 1,
            bottom: 2,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: const Color(
                  0xFF22C55E,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(
                          alpha: 0.15,
                        ),
                    blurRadius: 4,
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

class _AvatarFallback
    extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE8EDF4),
      child: const Icon(
        Icons.person_rounded,
        size: 29,
        color: Color(0xFF8B9AAD),
      ),
    );
  }
}

class _WhiteCircleButton
    extends StatelessWidget {
  const _WhiteCircleButton({
    required this.icon,
    required this.onTap,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(
        alpha: 0.96,
      ),
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        customBorder:
            const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color:
                  Colors.white.withValues(
                    alpha: 0.9,
                  ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(
                      alpha: 0.12,
                    ),
                blurRadius: 15,
                offset:
                    const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: const Color(
              0xFF2185F5,
            ),
            size: 21,
          ),
        ),
      ),
    );
  }
}

class _MapActionButton
    extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _WhiteCircleButton(
      icon: icon,
      onTap: onTap,
      size: 48,
    );
  }
}

class _LocationChip
    extends StatelessWidget {
  const _LocationChip({
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(
        alpha: 0.97,
      ),
      borderRadius:
          BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(16),
        child: Container(
          height: 50,
          padding:
              const EdgeInsets.symmetric(
                horizontal: 13,
              ),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(
                  16,
                ),
            border: Border.all(
              color: Colors.white
                  .withValues(
                    alpha: 0.85,
                  ),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF24334B,
                ).withValues(
                  alpha: 0.10,
                ),
                blurRadius: 16,
                offset: const Offset(
                  0,
                  6,
                ),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 29,
                height: 29,
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFEAF4FF,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                        9,
                      ),
                ),
                child: const Icon(
                  Icons
                      .location_on_rounded,
                  color: Color(
                    0xFF2185F5,
                  ),
                  size: 18,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                        color: Color(
                          0xFF172033,
                        ),
                        fontWeight:
                            FontWeight.w700,
                        fontSize: 13.5,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons
                    .keyboard_arrow_down_rounded,
                color:
                    Color(0xFF7B899C),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SECTION HEADER
// ============================================================================

class _SectionHeader
    extends StatelessWidget {
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
      crossAxisAlignment:
          CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight:
                      FontWeight.w800,
                  color:
                      Color(0xFF172033),
                  letterSpacing: -0.35,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  color:
                      Color(0xFF8A98AB),
                  fontWeight:
                      FontWeight.w500,
                  fontSize: 11.5,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onSeeAll,
          style: TextButton.styleFrom(
            foregroundColor:
                const Color(
                  0xFF2185F5,
                ),
            minimumSize:
                const Size(0, 38),
            padding:
                const EdgeInsets.symmetric(
                  horizontal: 8,
                ),
            tapTargetSize:
                MaterialTapTargetSize
                    .shrinkWrap,
            textStyle:
                const TextStyle(
                  fontWeight:
                      FontWeight.w700,
                  fontSize: 12,
                ),
          ),
          child: const Row(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Text('See All'),
              SizedBox(width: 2),
              Icon(
                Icons
                    .arrow_forward_ios_rounded,
                size: 11,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// FAMOUS SPOT CARD
// ============================================================================

class _NearbySpotCard
    extends StatelessWidget {
  const _NearbySpotCard({
    required this.spot,
  });

  final _NearbySpot spot;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: const Color(
            0xFFE8EDF4,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF24334B,
            ).withValues(
              alpha: 0.09,
            ),
            blurRadius: 18,
            offset:
                const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              spot.imageForCard,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Container(
                    color:
                        const Color(
                          0xFFE8EEF5,
                        ),
                    child: const Center(
                      child: Icon(
                        Icons
                            .image_outlined,
                        size: 30,
                        color: Color(
                          0xFF93A2B6,
                        ),
                      ),
                    ),
                  ),
            ),

            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient:
                      LinearGradient(
                        begin: Alignment
                            .topCenter,
                        end: Alignment
                            .bottomCenter,
                        colors: [
                          Colors.black
                              .withValues(
                                alpha:
                                    0.04,
                              ),
                          Colors.black
                              .withValues(
                                alpha:
                                    0.05,
                              ),
                          Colors.black
                              .withValues(
                                alpha:
                                    0.78,
                              ),
                        ],
                        stops: const [
                          0.0,
                          0.42,
                          1.0,
                        ],
                      ),
                ),
              ),
            ),

            Positioned(
              top: 10,
              left: 10,
              child: _CategoryBadge(
                tag: spot.tag,
              ),
            ),

            Positioned(
              top: 10,
              right: 10,
              child: _RatingBadge(
                rating: spot.rating,
              ),
            ),

            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    spot.title,
                    maxLines: 2,
                    overflow:
                        TextOverflow
                            .ellipsis,
                    style:
                        const TextStyle(
                          color:
                              Colors.white,
                          fontWeight:
                              FontWeight
                                  .w800,
                          fontSize: 15,
                          height: 1.12,
                          letterSpacing:
                              -0.15,
                        ),
                  ),
                  const SizedBox(
                    height: 6,
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons
                            .near_me_rounded,
                        color: Color(
                          0xFF9CCAFF,
                        ),
                        size: 13,
                      ),
                      const SizedBox(
                        width: 4,
                      ),
                      Text(
                        spot.distanceText,
                        style:
                            const TextStyle(
                              color: Color(
                                0xFFB9DAFF,
                              ),
                              fontWeight:
                                  FontWeight
                                      .w700,
                              fontSize:
                                  11,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 4,
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons
                            .place_outlined,
                        color:
                            Colors.white70,
                        size: 12,
                      ),
                      const SizedBox(
                        width: 4,
                      ),
                      Expanded(
                        child: Text(
                          spot.barangay
                                  .isEmpty
                              ? spot.city
                              : spot.barangay,
                          maxLines: 1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              const TextStyle(
                                color: Colors
                                    .white70,
                                fontWeight:
                                    FontWeight
                                        .w500,
                                fontSize:
                                    10.5,
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

class _CategoryBadge
    extends StatelessWidget {
  const _CategoryBadge({
    required this.tag,
  });

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          const BoxConstraints(
            maxWidth: 88,
          ),
      padding:
          const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 5,
          ),
      decoration: BoxDecoration(
        color: Colors.white
            .withValues(alpha: 0.94),
        borderRadius:
            BorderRadius.circular(100),
      ),
      child: Text(
        tag,
        maxLines: 1,
        overflow:
            TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF28364A),
          fontWeight:
              FontWeight.w700,
          fontSize: 9.5,
        ),
      ),
    );
  }
}

class _RatingBadge
    extends StatelessWidget {
  const _RatingBadge({
    required this.rating,
  });

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 5,
          ),
      decoration: BoxDecoration(
        color: Colors.black
            .withValues(alpha: 0.42),
        borderRadius:
            BorderRadius.circular(100),
        border: Border.all(
          color: Colors.white
              .withValues(alpha: 0.13),
        ),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          const Icon(
            Icons.star_rounded,
            color:
                Color(0xFFFFD166),
            size: 13,
          ),
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(1),
            style:
                const TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight.w700,
                  fontSize: 10.5,
                ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PACKAGE CARD
// ============================================================================

class _SuggestionPackageTile
    extends StatelessWidget {
  const _SuggestionPackageTile({
    required this.pkg,
  });

  final _SuggestionPackage pkg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(19),
        border: Border.all(
          color:
              const Color(0xFFE8EDF4),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF24334B,
            ).withValues(
              alpha: 0.055,
            ),
            blurRadius: 15,
            offset:
                const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius:
                BorderRadius.circular(15),
            child: SizedBox(
              width: 84,
              height: 84,
              child:
                  pkg.imageUrl.isNotEmpty
                  ? Image.network(
                      pkg.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (_, _, _) =>
                              const _PackageImageFallback(),
                    )
                  : const _PackageImageFallback(),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  pkg.title,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                        color: Color(
                          0xFF172033,
                        ),
                        fontWeight:
                            FontWeight.w800,
                        fontSize: 14.5,
                        letterSpacing:
                            -0.15,
                      ),
                ),

                const SizedBox(height: 4),

                Text(
                  pkg.subtitle.isEmpty
                      ? pkg.city
                      : pkg.subtitle,
                  maxLines: 2,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                        color: Color(
                          0xFF77869A,
                        ),
                        fontWeight:
                            FontWeight.w500,
                        height: 1.25,
                        fontSize: 11.5,
                      ),
                ),

                const SizedBox(height: 9),

                Row(
                  children: [
                    Flexible(
                      child: _MiniInfoPill(
                        icon: Icons
                            .payments_outlined,
                        text:
                            pkg.priceText,
                        color:
                            const Color(
                              0xFF2185F5,
                            ),
                      ),
                    ),
                    const SizedBox(
                      width: 7,
                    ),
                    Flexible(
                      child: _MiniInfoPill(
                        icon: Icons
                            .schedule_rounded,
                        text: pkg
                            .durationText,
                        color:
                            const Color(
                              0xFF64748B,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(
                0xFFF3F7FB,
              ),
              borderRadius:
                  BorderRadius.circular(
                    10,
                  ),
            ),
            child: const Icon(
              Icons
                  .arrow_forward_ios_rounded,
              size: 12,
              color:
                  Color(0xFF718197),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniInfoPill
    extends StatelessWidget {
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
      constraints:
          const BoxConstraints(
            minWidth: 0,
          ),
      padding:
          const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 5,
          ),
      decoration: BoxDecoration(
        color: const Color(
          0xFFF4F7FA,
        ),
        borderRadius:
            BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight:
                    FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EMPTY CARD
// ============================================================================

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
      padding:
          const EdgeInsets.fromLTRB(
            14,
            14,
            15,
            14,
          ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color:
              const Color(0xFFE7EDF4),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.center,
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: const Color(
                0xFFEDF6FF,
              ),
              borderRadius:
                  BorderRadius.circular(
                    13,
                  ),
            ),
            child: Icon(
              icon,
              color:
                  const Color(
                    0xFF2185F5,
                  ),
              size: 22,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(
                        color: Color(
                          0xFF172033,
                        ),
                        fontWeight:
                            FontWeight.w700,
                        fontSize: 13.5,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style:
                      const TextStyle(
                        color: Color(
                          0xFF8391A4,
                        ),
                        fontWeight:
                            FontWeight.w500,
                        height: 1.3,
                        fontSize: 11,
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

class _PackageImageFallback
    extends StatelessWidget {
  const _PackageImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(
        0xFFEAF4FF,
      ),
      child: const Icon(
        Icons
            .map_outlined,
        color:
            Color(0xFF2185F5),
        size: 28,
      ),
    );
  }
}

// ============================================================================
// BUTTON
// ============================================================================

class _GradientButton
    extends StatelessWidget {
  const _GradientButton({
    required this.text,
    required this.onPressed,
  });

  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(
              begin:
                  Alignment.centerLeft,
              end:
                  Alignment.centerRight,
              colors: [
                Color(0xFF45A4FF),
                Color(0xFF2185F5),
                Color(0xFF2563EB),
              ],
            ),
        borderRadius:
            BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF2185F5,
            ).withValues(
              alpha: 0.20,
            ),
            blurRadius: 15,
            offset:
                const Offset(0, 7),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style:
            ElevatedButton.styleFrom(
              elevation: 0,
              shadowColor:
                  Colors.transparent,
              backgroundColor:
                  Colors.transparent,
              foregroundColor:
                  Colors.white,
              shape:
                  RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                          15,
                        ),
                  ),
            ),
        child: Text(
          text,
          style:
              const TextStyle(
                color: Colors.white,
                fontWeight:
                    FontWeight.w700,
                fontSize: 14,
              ),
        ),
      ),
    );
  }
}

// ============================================================================
// AI PREFERENCE CARD
// ============================================================================

class _HomePreferenceEditRow
    extends StatelessWidget {
  const _HomePreferenceEditRow({
    required this.hasPreferences,
    required this.prefLocation,
    required this.prefCategories,
    required this.onEdit,
  });

  final bool hasPreferences;
  final String prefLocation;
  final List<String> prefCategories;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    if (!hasPreferences) {
      return const SizedBox.shrink();
    }

    final label = [
      if (prefLocation.trim().isNotEmpty)
        prefLocation.trim(),
      if (prefCategories.isNotEmpty)
        prefCategories
            .take(3)
            .join(' • '),
    ].join(' • ');

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
            13,
            11,
            9,
            11,
          ),
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(
              begin:
                  Alignment.centerLeft,
              end:
                  Alignment.centerRight,
              colors: [
                Color(0xFFF0F7FF),
                Color(0xFFF7FAFE),
              ],
            ),
        borderRadius:
            BorderRadius.circular(17),
        border: Border.all(
          color:
              const Color(0xFFDCEBFB),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: const Color(
                0xFF2185F5,
              ).withValues(
                alpha: 0.10,
              ),
              borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
            ),
            child: const Icon(
              Icons
                  .auto_awesome_rounded,
              color:
                  Color(0xFF2185F5),
              size: 19,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your travel preferences',
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      TextStyle(
                        color: Color(
                          0xFF26364B,
                        ),
                        fontWeight:
                            FontWeight.w700,
                        fontSize: 12.5,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                        color: Color(
                          0xFF8190A3,
                        ),
                        fontWeight:
                            FontWeight.w500,
                        fontSize: 10.5,
                      ),
                ),
              ],
            ),
          ),

          TextButton(
            onPressed: onEdit,
            style:
                TextButton.styleFrom(
                  foregroundColor:
                      const Color(
                        0xFF2185F5,
                      ),
                  padding:
                      const EdgeInsets
                          .symmetric(
                            horizontal: 8,
                          ),
                  minimumSize:
                      const Size(
                        0,
                        34,
                      ),
                  tapTargetSize:
                      MaterialTapTargetSize
                          .shrinkWrap,
                ),
            child:
                const Text(
                  'Edit',
                  style: TextStyle(
                    fontWeight:
                        FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceEmptyState
    extends StatelessWidget {
  const _PreferenceEmptyState({
    required this.onSetPreferences,
  });

  final VoidCallback onSetPreferences;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
            16,
            15,
            16,
            15,
          ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(19),
        border: Border.all(
          color:
              const Color(0xFFE5ECF4),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF24334B,
            ).withValues(
              alpha: 0.05,
            ),
            blurRadius: 14,
            offset:
                const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient:
                      const LinearGradient(
                        begin: Alignment
                            .topLeft,
                        end: Alignment
                            .bottomRight,
                        colors: [
                          Color(
                            0xFFEAF5FF,
                          ),
                          Color(
                            0xFFDDEEFF,
                          ),
                        ],
                      ),
                  borderRadius:
                      BorderRadius.circular(
                        14,
                      ),
                ),
                child: const Icon(
                  Icons
                      .auto_awesome_rounded,
                  color: Color(
                    0xFF2185F5,
                  ),
                  size: 22,
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              const Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      'Make TourisTrike yours',
                      style:
                          TextStyle(
                            color: Color(
                              0xFF172033,
                            ),
                            fontWeight:
                                FontWeight
                                    .w800,
                            fontSize:
                                15,
                            letterSpacing:
                                -0.15,
                          ),
                    ),
                    SizedBox(
                      height: 4,
                    ),
                    Text(
                      'Choose the places you enjoy and we\'ll personalize your travel suggestions.',
                      style:
                          TextStyle(
                            color: Color(
                              0xFF79889B,
                            ),
                            fontWeight:
                                FontWeight
                                    .w500,
                            height:
                                1.32,
                            fontSize:
                                11.5,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          SizedBox(
            width: double.infinity,
            height: 43,
            child: _GradientButton(
              text:
                  'Set My Preferences',
              onPressed:
                  onSetPreferences,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// RECOMMENDATION SECTION
// ============================================================================

class _RecommendedSection
    extends StatelessWidget {
  const _RecommendedSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.spots,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final String emptyTitle;
  final String emptySubtitle;
  final List<_NearbySpot> spots;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment:
              CrossAxisAlignment.center,
          children: [
            Container(
              width: 37,
              height: 37,
              decoration: BoxDecoration(
                color: iconColor
                    .withValues(
                      alpha: 0.10,
                    ),
                borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 19,
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow:
                        TextOverflow
                            .ellipsis,
                    style:
                        const TextStyle(
                          color: Color(
                            0xFF172033,
                          ),
                          fontWeight:
                              FontWeight
                                  .w800,
                          fontSize: 18,
                          letterSpacing:
                              -0.3,
                          height: 1.1,
                        ),
                  ),
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow:
                        TextOverflow
                            .ellipsis,
                    style:
                        const TextStyle(
                          color: Color(
                            0xFF8A98AB,
                          ),
                          fontWeight:
                              FontWeight
                                  .w500,
                          fontSize:
                              11.5,
                          height:
                              1.25,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        if (spots.isEmpty)
          _EmptyCard(
            icon: icon,
            title: emptyTitle,
            subtitle: emptySubtitle,
          )
        else
          SizedBox(
            height: 160,
            child:
                ListView.separated(
                  physics:
                      const BouncingScrollPhysics(),
                  clipBehavior:
                      Clip.none,
                  scrollDirection:
                      Axis.horizontal,
                  itemCount:
                      spots.length,
                  separatorBuilder:
                      (_, _) =>
                          const SizedBox(
                            width: 11,
                          ),
                  itemBuilder: (_, i) =>
                      _AiSpotMiniCard(
                        spot: spots[i],
                        matchLabel:
                            title ==
                                'Recommended For You'
                            ? 'For you'
                            : 'Discover',
                      ),
                ),
          ),
      ],
    );
  }
}

class _AiSpotMiniCard
    extends StatelessWidget {
  const _AiSpotMiniCard({
    required this.spot,
    required this.matchLabel,
  });

  final _NearbySpot spot;
  final String matchLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 245,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color:
              const Color(0xFFE5ECF4),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF24334B,
            ).withValues(
              alpha: 0.055,
            ),
            blurRadius: 15,
            offset:
                const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(18),
        child: Row(
          children: [
            SizedBox(
              width: 94,
              height: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    spot.imageForCard,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, _, _) =>
                            Container(
                              color:
                                  const Color(
                                    0xFFEAF4FF,
                                  ),
                              child: const Icon(
                                Icons
                                    .image_outlined,
                                color: Color(
                                  0xFF2185F5,
                                ),
                              ),
                            ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration:
                          BoxDecoration(
                            gradient:
                                LinearGradient(
                                  begin:
                                      Alignment
                                          .centerLeft,
                                  end:
                                      Alignment
                                          .centerRight,
                                  colors: [
                                    Colors
                                        .transparent,
                                    Colors
                                        .black
                                        .withValues(
                                          alpha:
                                              0.04,
                                        ),
                                  ],
                                ),
                          ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets
                        .fromLTRB(
                          11,
                          10,
                          11,
                          10,
                        ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                                horizontal:
                                    7,
                                vertical:
                                    4,
                              ),
                      decoration:
                          BoxDecoration(
                            color:
                                const Color(
                                  0xFF2185F5,
                                ).withValues(
                                  alpha:
                                      0.09,
                                ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                                      100,
                                    ),
                          ),
                      child: Row(
                        mainAxisSize:
                            MainAxisSize
                                .min,
                        children: [
                          const Icon(
                            Icons
                                .auto_awesome_rounded,
                            color: Color(
                              0xFF2185F5,
                            ),
                            size: 11,
                          ),
                          const SizedBox(
                            width: 3,
                          ),
                          Text(
                            matchLabel,
                            style:
                                const TextStyle(
                                  color:
                                      Color(
                                        0xFF2185F5,
                                      ),
                                  fontWeight:
                                      FontWeight
                                          .w700,
                                  fontSize:
                                      9,
                                ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(
                      height: 7,
                    ),

                    Text(
                      spot.title,
                      maxLines: 2,
                      overflow:
                          TextOverflow
                              .ellipsis,
                      style:
                          const TextStyle(
                            color: Color(
                              0xFF172033,
                            ),
                            fontWeight:
                                FontWeight
                                    .w800,
                            fontSize:
                                13.5,
                            height: 1.15,
                            letterSpacing:
                                -0.1,
                          ),
                    ),

                    const SizedBox(
                      height: 5,
                    ),

                    Text(
                      spot.tag.isEmpty
                          ? spot.city
                          : spot.tag,
                      maxLines: 1,
                      overflow:
                          TextOverflow
                              .ellipsis,
                      style:
                          const TextStyle(
                            color: Color(
                              0xFF7F8EA1,
                            ),
                            fontWeight:
                                FontWeight
                                    .w500,
                            fontSize:
                                10.5,
                          ),
                    ),

                    const Spacer(),

                    Row(
                      children: [
                        const Icon(
                          Icons
                              .star_rounded,
                          color: Color(
                            0xFFFFC857,
                          ),
                          size: 14,
                        ),
                        const SizedBox(
                          width: 3,
                        ),
                        Text(
                          spot.rating
                              .toStringAsFixed(
                                1,
                              ),
                          style:
                              const TextStyle(
                                color: Color(
                                  0xFF26364B,
                                ),
                                fontWeight:
                                    FontWeight
                                        .w700,
                                fontSize:
                                    10.5,
                              ),
                        ),
                        const SizedBox(
                          width: 7,
                        ),
                        Expanded(
                          child: Text(
                            spot.distanceText,
                            maxLines: 1,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                const TextStyle(
                                  color:
                                      Color(
                                        0xFF95A2B3,
                                      ),
                                  fontWeight:
                                      FontWeight
                                          .w500,
                                  fontSize:
                                      9.5,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PREFERENCES SHEET
// ============================================================================

class _PreferencesSheet
    extends StatefulWidget {
  const _PreferencesSheet({
    required this.initialLocation,
    required this.initialCategories,
    required this.forceSetup,
  });

  final String initialLocation;
  final List<String>
  initialCategories;
  final bool forceSetup;

  @override
  State<_PreferencesSheet>
  createState() =>
      _PreferencesSheetState();
}

class _PreferencesSheetState
    extends State<_PreferencesSheet> {
  late TextEditingController
  _locationCtrl;

  late List<String>
  _selectedCategories;

  static const _allCategories = [
    'Nature',
    'Historical',
    'Food',
    'Religious',
    'Resort',
    'Shopping',
    'Adventure',
    'Cultural',
    'Family-friendly',
    'Instagram-worthy',
    'Hidden gems',
  ];

  @override
  void initState() {
    super.initState();

    _locationCtrl =
        TextEditingController(
          text:
              widget.initialLocation,
        );

    _selectedCategories =
        List.from(
          widget.initialCategories,
        );
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset =
        MediaQuery.of(
          context,
        ).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + bottomInset,
      ),
      decoration:
          const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(
                  top:
                      Radius.circular(
                        28,
                      ),
                ),
          ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration:
                    BoxDecoration(
                      color:
                          const Color(
                            0xFFDCE4ED,
                          ),
                      borderRadius:
                          BorderRadius
                              .circular(
                                100,
                              ),
                    ),
              ),
            ),

            const SizedBox(height: 18),

            Row(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .center,
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration:
                      BoxDecoration(
                        gradient:
                            const LinearGradient(
                              begin:
                                  Alignment
                                      .topLeft,
                              end:
                                  Alignment
                                      .bottomRight,
                              colors: [
                                Color(
                                  0xFF4BA8FF,
                                ),
                                Color(
                                  0xFF2185F5,
                                ),
                              ],
                            ),
                        borderRadius:
                            BorderRadius
                                .circular(
                                  14,
                                ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(
                                  0xFF2185F5,
                                ).withValues(
                                  alpha:
                                      0.18,
                                ),
                            blurRadius:
                                12,
                            offset:
                                const Offset(
                                  0,
                                  5,
                                ),
                          ),
                        ],
                      ),
                  child: const Icon(
                    Icons
                        .auto_awesome_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        widget.forceSetup
                            ? 'Personalize Your Trip'
                            : 'Travel Preferences',
                        style:
                            const TextStyle(
                              fontSize: 18,
                              fontWeight:
                                  FontWeight
                                      .w800,
                              color: Color(
                                0xFF172033,
                              ),
                              letterSpacing:
                                  -0.3,
                            ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      const Text(
                        'Choose what you enjoy so TourisTrike can recommend better places.',
                        style:
                            TextStyle(
                              fontSize:
                                  11.5,
                              color: Color(
                                0xFF7B899C,
                              ),
                              fontWeight:
                                  FontWeight
                                      .w500,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 23),

            const Text(
              'What do you love exploring?',
              style: TextStyle(
                fontWeight:
                    FontWeight.w800,
                color:
                    Color(0xFF172033),
                fontSize: 14.5,
                letterSpacing: -0.1,
              ),
            ),

            const SizedBox(height: 5),

            const Text(
              'Select one or more interests.',
              style: TextStyle(
                color:
                    Color(0xFF8A98AB),
                fontSize: 11.5,
                fontWeight:
                    FontWeight.w500,
              ),
            ),

            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _allCategories.map((
                    cat,
                  ) {
                    final selected =
                        _selectedCategories
                            .contains(cat);

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (selected) {
                            _selectedCategories
                                .remove(
                                  cat,
                                );
                          } else {
                            _selectedCategories
                                .add(
                                  cat,
                                );
                          }
                        });
                      },
                      child:
                          AnimatedContainer(
                            duration:
                                const Duration(
                                  milliseconds:
                                      160,
                                ),
                            curve: Curves
                                .easeOut,
                            padding:
                                const EdgeInsets
                                    .symmetric(
                                      horizontal:
                                          12,
                                      vertical:
                                          8,
                                    ),
                            decoration:
                                BoxDecoration(
                                  color:
                                      selected
                                      ? const Color(
                                          0xFF2185F5,
                                        )
                                      : const Color(
                                          0xFFF5F7FA,
                                        ),
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                            100,
                                          ),
                                  border:
                                      Border.all(
                                        color:
                                            selected
                                            ? const Color(
                                                0xFF2185F5,
                                              )
                                            : const Color(
                                                0xFFE2E8F0,
                                              ),
                                      ),
                                  boxShadow:
                                      selected
                                      ? [
                                          BoxShadow(
                                            color:
                                                const Color(
                                                  0xFF2185F5,
                                                ).withValues(
                                                  alpha:
                                                      0.14,
                                                ),
                                            blurRadius:
                                                8,
                                            offset:
                                                const Offset(
                                                  0,
                                                  3,
                                                ),
                                          ),
                                        ]
                                      : null,
                                ),
                            child: Row(
                              mainAxisSize:
                                  MainAxisSize
                                      .min,
                              children: [
                                if (selected) ...[
                                  const Icon(
                                    Icons
                                        .check_rounded,
                                    color:
                                        Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(
                                    width: 4,
                                  ),
                                ],
                                Text(
                                  cat,
                                  style:
                                      TextStyle(
                                        fontWeight:
                                            FontWeight
                                                .w600,
                                        fontSize:
                                            12,
                                        color:
                                            selected
                                            ? Colors
                                                  .white
                                            : const Color(
                                                0xFF627186,
                                              ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                    );
                  }).toList(),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: DecoratedBox(
                decoration:
                    BoxDecoration(
                      gradient:
                          const LinearGradient(
                            begin: Alignment
                                .centerLeft,
                            end: Alignment
                                .centerRight,
                            colors: [
                              Color(
                                0xFF45A4FF,
                              ),
                              Color(
                                0xFF2185F5,
                              ),
                              Color(
                                0xFF2563EB,
                              ),
                            ],
                          ),
                      borderRadius:
                          BorderRadius
                              .circular(
                                15,
                              ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(
                                0xFF2185F5,
                              ).withValues(
                                alpha:
                                    0.20,
                              ),
                          blurRadius:
                              15,
                          offset:
                              const Offset(
                                0,
                                7,
                              ),
                        ),
                      ],
                    ),
                child: ElevatedButton(
                  onPressed: () {
                    if (widget
                            .forceSetup &&
                        _selectedCategories
                            .isEmpty) {
                      ScaffoldMessenger
                          .of(context)
                          .showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please choose at least one preferred kind of place.',
                              ),
                            ),
                          );

                      return;
                    }

                    Navigator.pop(
                      context,
                      {
                        'location': '',
                        'categories':
                            _selectedCategories,
                      },
                    );
                  },
                  style:
                      ElevatedButton
                          .styleFrom(
                            elevation: 0,
                            backgroundColor:
                                Colors
                                    .transparent,
                            shadowColor:
                                Colors
                                    .transparent,
                            foregroundColor:
                                Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                    15,
                                  ),
                            ),
                          ),
                  child: Text(
                    widget.forceSetup
                        ? 'Show My Suggestions'
                        : 'Save Preferences',
                    style:
                        const TextStyle(
                          color:
                              Colors.white,
                          fontWeight:
                              FontWeight
                                  .w700,
                          fontSize: 14.5,
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// MODELS
// ============================================================================

class _HomeData {
  final String fullName;
  final String avatarUrl;
  final String cityText;
  final LatLng center;
  final String? municipality;
  final bool isInsideBulacan;
  final List<_NearbySpot> allSpots;
  final List<_NearbySpot> famousSpots;
  final List<_SuggestionPackage>
  suggestionPackages;

  _HomeData({
    required this.fullName,
    required this.avatarUrl,
    required this.cityText,
    required this.center,
    required this.municipality,
    required this.isInsideBulacan,
    required this.allSpots,
    required this.famousSpots,
    required this.suggestionPackages,
  });
}

class _MunicipalityArea {
  final String name;
  final LatLng center;

  const _MunicipalityArea({
    required this.name,
    required this.center,
  });
}

const _bulacanMunicipalities = [
  _MunicipalityArea(
    name: 'Bustos',
    center:
        LatLng(14.9597, 120.9206),
  ),
  _MunicipalityArea(
    name: 'Baliwag',
    center:
        LatLng(14.9547, 120.8969),
  ),
  _MunicipalityArea(
    name: 'Malolos',
    center:
        LatLng(14.8434, 120.8114),
  ),
  _MunicipalityArea(
    name: 'Pulilan',
    center:
        LatLng(14.9017, 120.8492),
  ),
  _MunicipalityArea(
    name: 'Plaridel',
    center:
        LatLng(14.8873, 120.8572),
  ),
  _MunicipalityArea(
    name: 'San Rafael',
    center:
        LatLng(15.0265, 120.9283),
  ),
  _MunicipalityArea(
    name: 'San Ildefonso',
    center:
        LatLng(15.0809, 120.9410),
  ),
  _MunicipalityArea(
    name: 'San Miguel',
    center:
        LatLng(15.1458, 120.9783),
  ),
  _MunicipalityArea(
    name: 'Calumpit',
    center:
        LatLng(14.9164, 120.7658),
  ),
  _MunicipalityArea(
    name: 'Hagonoy',
    center:
        LatLng(14.8340, 120.7328),
  ),
  _MunicipalityArea(
    name: 'Paombong',
    center:
        LatLng(14.8319, 120.7897),
  ),
  _MunicipalityArea(
    name: 'Guiguinto',
    center:
        LatLng(14.8333, 120.8833),
  ),
  _MunicipalityArea(
    name: 'Balagtas',
    center:
        LatLng(14.8167, 120.8667),
  ),
  _MunicipalityArea(
    name: 'Bocaue',
    center:
        LatLng(14.7983, 120.9261),
  ),
  _MunicipalityArea(
    name: 'Marilao',
    center:
        LatLng(14.7581, 120.9481),
  ),
  _MunicipalityArea(
    name: 'Meycauayan',
    center:
        LatLng(14.7369, 120.9608),
  ),
  _MunicipalityArea(
    name: 'Norzagaray',
    center:
        LatLng(14.9109, 121.0493),
  ),
  _MunicipalityArea(
    name: 'Santa Maria',
    center:
        LatLng(14.8208, 120.9636),
  ),
  _MunicipalityArea(
    name: 'Angat',
    center:
        LatLng(14.9285, 121.0292),
  ),
  _MunicipalityArea(
    name: 'Pandi',
    center:
        LatLng(14.8650, 120.9572),
  ),
  _MunicipalityArea(
    name: 'Obando',
    center:
        LatLng(14.7098, 120.9362),
  ),
  _MunicipalityArea(
    name: 'Bulakan',
    center:
        LatLng(14.7928, 120.8789),
  ),
  _MunicipalityArea(
    name: 'Dona Remedios Trinidad',
    center:
        LatLng(15.0005, 121.0838),
  ),
  _MunicipalityArea(
    name: 'San Jose del Monte',
    center:
        LatLng(14.8139, 121.0453),
  ),
];

class _NearbySpot {
  final String id;
  final String title;
  final String city;
  final String barangay;
  final String description;
  final double latitude;
  final double longitude;
  final double rating;
  final String imageUrl;
  final String tag;
  final double distanceKm;

  const _NearbySpot({
    required this.id,
    required this.title,
    required this.city,
    required this.barangay,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.imageUrl,
    required this.tag,
    required this.distanceKm,
  });

  factory _NearbySpot.fromRecommendationSpot(
    TouristAiRecommendationSpot spot,
  ) {
    return _NearbySpot(
      id: spot.id,
      title: spot.title,
      city: spot.municipality,
      barangay: spot.address,
      description: spot.description,
      latitude: spot.latitude,
      longitude: spot.longitude,
      rating: spot.rating,
      imageUrl: spot.imageUrl,
      tag: spot.category,
      distanceKm: spot.distanceKm,
    );
  }

  TouristAiRecommendationSpot
  toRecommendationSpot() {
    return TouristAiRecommendationSpot(
      id: id,
      title: title,
      address: barangay,
      distanceText: distanceText,
      distanceKm: distanceKm,
      category: tag,
      rating: rating,
      imageUrl: imageUrl,
      latitude: latitude,
      longitude: longitude,
      municipality: city,
      googlePlaceId: id,
      description: description,
    );
  }

  String get distanceText {
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()}m away';
    }

    return '${distanceKm.toStringAsFixed(1)}km away';
  }

  String get imageForCard {
    if (imageUrl.isNotEmpty) {
      return imageUrl;
    }

    return CitySpotSuggestionService
        .buildStaticMapUrl(
          latitude: latitude,
          longitude: longitude,
        );
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

  factory _SuggestionPackage.fromMap(
    Map<String, dynamic> m,
  ) {
    final cover =
        (m['cover_image_url']
            as String?) ??
        '';

    final image = cover.isNotEmpty
        ? cover
        : ((m['image_url']
                  as String?) ??
              '');

    return _SuggestionPackage(
      id: m['id'],
      title:
          (m['title'] as String?) ??
          'Untitled Package',
      subtitle:
          (m['subtitle'] as String?) ??
          '',
      city:
          (m['city'] as String?) ?? '',
      priceText:
          (m['price_text']
              as String?) ??
          'Ask admin',
      durationText:
          (m['duration_text']
              as String?) ??
          'Flexible',
      imageUrl: image,
    );
  }
}