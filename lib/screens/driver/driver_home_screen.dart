import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/screens/driver/incoming_ride_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_profile.dart';
import 'package:touristrike/widgets/app_bottom_nav_driver.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final supabase = Supabase.instance.client;
  static final LatLngBounds _bulacanBounds = LatLngBounds(
    southwest: const LatLng(14.35, 120.35),
    northeast: const LatLng(15.55, 121.55),
  );

  Map<String, dynamic>? _profile;
  bool _isOnline = false;
  bool _settingOnline = false;

  Map<String, dynamic>? _activeRide;

  num _todayEarnings = 0;
  int _todayTrips = 0;
  int _totalCompletedTours = 0;

  StreamSubscription<List<Map<String, dynamic>>>? _profileSub;
  StreamSubscription<List<Map<String, dynamic>>>? _activeRideSub;
  StreamSubscription<Position>? _positionSub;

  RealtimeChannel? _searchingChannel;

  bool _accepting = false;
  LatLng? _currentDriverLocation;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _activeRideSub?.cancel();
    _positionSub?.cancel();
    _stopSearchingRideListener();
    super.dispose();
  }

  User get _user {
    final u = supabase.auth.currentUser;
    if (u == null) throw Exception('No logged-in user.');
    return u;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _bootstrap() async {
    await _loadProfile();
    _subscribeProfileRealtime();

    await _loadActiveRideOnce();
    _subscribeMyActiveRideRealtime();

    await _refreshEarnings();

    if (_isOnline) {
      final ok = await _prepareLocationAndStartTracking();
      if (!ok) {
        await _setOnlineInternal(false, fromProfileRealtime: false);
        return;
      }

      if (_activeRide == null) {
        _startSearchingRideListener();
        await _scanAndAutoAcceptLatest();
      } else {
        await _pushDriverLocationToActiveRide();
      }
    }
  }

  Future<void> _refreshAll() async {
    await _loadProfile();
    await _loadActiveRideOnce();
    await _refreshEarnings();

    if (_isOnline) {
      final ok = await _prepareLocationAndStartTracking();
      if (ok && _activeRide == null) {
        _startSearchingRideListener();
        await _scanAndAutoAcceptLatest();
      }
    } else {
      _stopSearchingRideListener();
    }
  }

  Future<void> _loadProfile() async {
    final res = await supabase
        .from('profiles')
        .select(
          'id, full_name, first_name, last_name, profile_image_url, is_online, role',
        )
        .eq('id', _user.id)
        .maybeSingle();

    if (!mounted) return;

    setState(() {
      _profile = res;
      _isOnline = (res?['is_online'] as bool?) ?? false;
    });
  }

  void _subscribeProfileRealtime() {
    _profileSub?.cancel();

    _profileSub = supabase
        .from('profiles')
        .stream(primaryKey: const ['id'])
        .eq('id', _user.id)
        .listen((rows) async {
          if (!mounted || rows.isEmpty) return;

          final p = rows.first;
          final newOnline = (p['is_online'] as bool?) ?? false;

          setState(() {
            _profile = p;
            _isOnline = newOnline;
          });

          if (newOnline) {
            final ok = await _prepareLocationAndStartTracking();
            if (!ok) {
              await _setOnlineInternal(false, fromProfileRealtime: true);
              return;
            }

            if (_activeRide == null) {
              _startSearchingRideListener();
              await _scanAndAutoAcceptLatest();
            } else {
              await _pushDriverLocationToActiveRide();
            }
          } else {
            _stopSearchingRideListener();
            await _stopLocationTracking();
          }
        });
  }

  Future<void> _setOnline(bool value) async {
    if (_settingOnline) return;
    _settingOnline = true;

    try {
      await _setOnlineInternal(value, fromProfileRealtime: false);
    } finally {
      _settingOnline = false;
    }
  }

  Future<void> _setOnlineInternal(
    bool value, {
    required bool fromProfileRealtime,
  }) async {
    if (value) {
      final ok = await _prepareLocationAndStartTracking();
      if (!ok) {
        if (mounted) {
          setState(() => _isOnline = false);
        }
        if (!fromProfileRealtime) {
          _showSnack('Location permission is required to go online.');
        }
        return;
      }

      if (mounted) {
        setState(() => _isOnline = true);
      }

      if (!fromProfileRealtime) {
        await supabase
            .from('profiles')
            .update({'is_online': true})
            .eq('id', _user.id);
      }

      if (_activeRide == null) {
        _startSearchingRideListener();
        await _scanAndAutoAcceptLatest();
      } else {
        await _pushDriverLocationToActiveRide();
      }
    } else {
      _stopSearchingRideListener();
      await _stopLocationTracking();

      if (mounted) {
        setState(() => _isOnline = false);
      }

      if (!fromProfileRealtime) {
        await supabase
            .from('profiles')
            .update({'is_online': false})
            .eq('id', _user.id);
      }
    }
  }

  Future<bool> _prepareLocationAndStartTracking() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('Please enable device location.');
      return false;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _currentDriverLocation = LatLng(pos.latitude, pos.longitude);

      if (_activeRide != null) {
        await _pushDriverLocationToActiveRide();
      }

      await _startLocationTracking();
      return true;
    } catch (_) {
      _showSnack('Unable to get current location.');
      return false;
    }
  }

  Future<void> _startLocationTracking() async {
    await _positionSub?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((Position pos) async {
          _currentDriverLocation = LatLng(pos.latitude, pos.longitude);

          if (mounted) {
            setState(() {});
          }

          if (_activeRide != null) {
            await _pushDriverLocationToActiveRide();
          }
        });
  }

  Future<void> _stopLocationTracking() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  Future<void> _pushDriverLocationToActiveRide() async {
    if (_activeRide == null || _currentDriverLocation == null) return;

    final rideId = _activeRide!['id']?.toString();
    if (rideId == null || rideId.isEmpty) return;

    try {
      await supabase
          .from('rides')
          .update({
            'driver_lat': _currentDriverLocation!.latitude,
            'driver_lng': _currentDriverLocation!.longitude,
            'driver_last_seen': DateTime.now().toIso8601String(),
          })
          .eq('id', rideId);
    } catch (_) {}
  }

  Future<void> _loadActiveRideOnce() async {
    final rows = await supabase
        .from('rides')
        .select('*')
        .eq('driver_id', _user.id)
        .not('status', 'in', '(completed,cancelled)')
        .order('created_at', ascending: false)
        .limit(1);

    if (!mounted) return;

    setState(() {
      _activeRide = rows.isNotEmpty
          ? Map<String, dynamic>.from(rows.first)
          : null;
    });
  }

  void _subscribeMyActiveRideRealtime() {
    _activeRideSub?.cancel();

    _activeRideSub = supabase
        .from('rides')
        .stream(primaryKey: const ['id'])
        .eq('driver_id', _user.id)
        .order('created_at', ascending: false)
        .listen((rows) async {
          if (!mounted) return;

          Map<String, dynamic>? active;
          for (final r in rows) {
            final s = (r['status'] ?? '').toString();
            if (s != 'completed' && s != 'cancelled') {
              active = r;
              break;
            }
          }

          setState(() => _activeRide = active);
          await _refreshEarnings();

          if (_activeRide != null && _isOnline) {
            await _pushDriverLocationToActiveRide();
          }

          if (_activeRide == null && _isOnline) {
            _startSearchingRideListener();
            await _scanAndAutoAcceptLatest();
          }
        });
  }

  void _startSearchingRideListener() {
    if (_searchingChannel != null) return;
    if (_activeRide != null) return;
    if (!_isOnline) return;

    _searchingChannel = supabase.channel('driver-searching-rides-${_user.id}');

    _searchingChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'rides',
          callback: (payload) async {
            if (!_isOnline || _activeRide != null || _accepting) return;

            final newRow = payload.newRecord;
            final status = (newRow['status'] ?? '').toString();
            final driverId = newRow['driver_id'];

            if (status == 'searching' && driverId == null) {
              final rideId = newRow['id']?.toString();
              if (rideId != null) {
                await _tryAutoAcceptRide(rideId);
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          callback: (payload) async {
            if (!_isOnline || _activeRide != null || _accepting) return;

            final newRow = payload.newRecord;
            final status = (newRow['status'] ?? '').toString();
            final driverId = newRow['driver_id'];

            if (status == 'searching' && driverId == null) {
              final rideId = newRow['id']?.toString();
              if (rideId != null) {
                await _tryAutoAcceptRide(rideId);
              }
            }
          },
        );

    _searchingChannel!.subscribe();
  }

  void _stopSearchingRideListener() {
    final ch = _searchingChannel;
    _searchingChannel = null;
    if (ch != null) {
      supabase.removeChannel(ch);
    }
  }

  Future<void> _scanAndAutoAcceptLatest() async {
    if (!_isOnline) return;
    if (_activeRide != null) return;
    if (_accepting) return;

    try {
      final rows = await supabase
          .from('rides')
          .select('id, driver_id, status, created_at')
          .eq('status', 'searching')
          .isFilter('driver_id', null)
          .order('created_at', ascending: false)
          .limit(1);

      if (rows.isNotEmpty) {
        final rideId = rows.first['id']?.toString();
        if (rideId != null) {
          await _tryAutoAcceptRide(rideId);
        }
      }
    } catch (_) {}
  }

  Future<void> _tryAutoAcceptRide(String rideId) async {
    if (!_isOnline) return;
    if (_activeRide != null) return;
    if (_currentDriverLocation == null) return;

    _accepting = true;

    try {
      final accepted = await supabase
          .from('rides')
          .update({
            'driver_id': _user.id,
            'status': 'accepted',
            'driver_lat': _currentDriverLocation!.latitude,
            'driver_lng': _currentDriverLocation!.longitude,
            'driver_last_seen': DateTime.now().toIso8601String(),
          })
          .eq('id', rideId)
          .eq('status', 'searching')
          .isFilter('driver_id', null)
          .select()
          .maybeSingle();

      if (accepted == null) return;
      if (!mounted) return;

      setState(() {
        _activeRide = Map<String, dynamic>.from(accepted);
      });

      _stopSearchingRideListener();
      _showSnack('New tour assignment accepted');
    } catch (_) {
      _showSnack('Failed to accept tour assignment.');
    } finally {
      _accepting = false;
    }
  }

  Future<void> _refreshEarnings() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    num sum = 0;
    var trips = 0;
    var completedTotal = 0;

    try {
      // Today's earnings from wallet_transactions (type: driver_earning)
      final txRows = await supabase
          .from('wallet_transactions')
          .select('amount, created_at')
          .eq('user_id', _user.id)
          .eq('type', 'driver_earning')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());

      for (final r in txRows) {
        final amount = r['amount'];
        if (amount is num) sum += amount;
        trips++;
      }
    } catch (_) {
      // Fallback: use package_activities price sum
      try {
        final actRows = await supabase
            .from('package_activities')
            .select('price, updated_at')
            .eq('driver_id', _user.id)
            .eq('status', 'completed')
            .gte('updated_at', start.toIso8601String())
            .lt('updated_at', end.toIso8601String());

        for (final r in actRows) {
          final price = r['price'];
          if (price is num) sum += price;
          trips++;
        }
      } catch (_) {}
    }

    try {
      final totalRows = await supabase
          .from('package_activities')
          .select('id')
          .eq('driver_id', _user.id)
          .eq('status', 'completed')
          .limit(1000);
      completedTotal = totalRows.length;
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _todayEarnings = sum;
      _todayTrips = trips;
      _totalCompletedTours = completedTotal;
    });
  }

  void _handleCenterAction() {
    final rideId = _activeRide?['id']?.toString();
    if (rideId == null || rideId.isEmpty) {
      _showSnack('No active tour assignment.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => IncomingRideScreen(rideId: rideId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.of(context).padding.top + 12,
            16,
            18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTourHeader(),
              const SizedBox(height: 14),
              _buildAvailabilityCard(),
              const SizedBox(height: 14),
              _buildUpcomingTourSchedule(),
              const SizedBox(height: 14),
              _buildActiveTourAssignment(),
              const SizedBox(height: 14),
              _buildTodayTourEarnings(),
              const SizedBox(height: 14),
              _buildGuideStats(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNavDriver(currentIndex: 0),
    );
  }

  Widget _buildTourHeader() {
    final img = (_profile?['profile_image_url'] ?? '').toString().trim();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F6FFF), Color(0xFF42B8FF)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F6FFF).withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
                backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
                child: img.isEmpty
                    ? const Icon(Icons.person_rounded, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tour Operations',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _displayName(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    onPressed: () => _showSnack('No new tour notifications.'),
                    icon: const Icon(Icons.notifications_none_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DriverProfileScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_outline_rounded),
                    tooltip: 'Profile',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  icon: Icons.route_rounded,
                  label: 'Active',
                  value: _activeRide == null ? 'None' : 'Assigned',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStat(
                  icon: Icons.payments_rounded,
                  label: 'Today',
                  value: _money(_todayEarnings),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityCard() {
    return _DashboardCard(
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: _isOnline
                  ? const Color(0xFFE8FFF3)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              _isOnline ? Icons.travel_explore_rounded : Icons.tour_outlined,
              color: _isOnline
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Driver Availability',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isOnline
                      ? (_activeRide == null
                            ? 'Waiting for tour assignments'
                            : 'Guiding an assigned tour package')
                      : 'Unavailable for scheduled tours',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: _isOnline, onChanged: (v) => _setOnline(v)),
        ],
      ),
    );
  }

  Widget _buildUpcomingTourSchedule() {
    final tour = _activeRide;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Upcoming Tour Schedule'),
        const SizedBox(height: 10),
        _DashboardCard(
          child: tour == null
              ? const _EmptyPanel(
                  icon: Icons.event_available_rounded,
                  title: 'No scheduled tour package yet',
                  subtitle:
                      'New tour assignments will appear here when assigned by operations.',
                )
              : Column(
                  children: [
                    _tourInfoRow(
                      icon: Icons.card_travel_rounded,
                      label: 'Package name',
                      value: _tourPackageName(tour),
                    ),
                    const SizedBox(height: 10),
                    _tourInfoRow(
                      icon: Icons.schedule_rounded,
                      label: 'Tour date/time',
                      value: _tourTime(tour),
                    ),
                    const SizedBox(height: 10),
                    _tourInfoRow(
                      icon: Icons.groups_rounded,
                      label: 'Number of tourists',
                      value: '${_touristCount(tour)} tourists',
                    ),
                    const SizedBox(height: 10),
                    _tourInfoRow(
                      icon: Icons.location_on_rounded,
                      label: 'Pickup location',
                      value: _pickupName(tour),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildActiveTourAssignment() {
    final tour = _activeRide;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Active Tour Assignment'),
        const SizedBox(height: 10),
        _DashboardCard(
          child: tour == null
              ? const _EmptyPanel(
                  icon: Icons.map_outlined,
                  title: 'No active tour assignment',
                  subtitle:
                      'Set yourself available to receive scheduled tour package assignments.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _tourPackageName(tour),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              height: 1.1,
                            ),
                          ),
                        ),
                        _statusPill(_tourStatus(tour)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTourMap(tour),
                    const SizedBox(height: 12),
                    _tourInfoRow(
                      icon: Icons.flag_rounded,
                      label: 'Destinations/stops',
                      value: _tourStops(tour).join(' -> '),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniMetric(
                            icon: Icons.groups_rounded,
                            label: 'Tourists',
                            value: '${_touristCount(tour)}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniMetric(
                            icon: Icons.play_circle_outline_rounded,
                            label: 'Start time',
                            value: _tourTime(tour),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        _TourActionButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Start Tour',
                          primary: true,
                          onTap: () => _startTour(tour),
                        ),
                        _TourActionButton(
                          icon: Icons.alt_route_rounded,
                          label: 'View Itinerary',
                          onTap: _handleCenterAction,
                        ),
                        _TourActionButton(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Contact Tourist',
                          onTap: _handleCenterAction,
                        ),
                        _TourActionButton(
                          icon: Icons.map_rounded,
                          label: 'Open Map',
                          onTap: _handleCenterAction,
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildTourProgressTracker(Map<String, dynamic>? tour) {
    final stops = tour == null ? <String>[] : _tourStops(tour);
    final status = tour == null ? '' : _tourStatus(tour);
    final activeIndex = status == 'completed'
        ? stops.length
        : status == 'ongoing'
        ? 1
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Tour Progress Tracker'),
        const SizedBox(height: 10),
        _DashboardCard(
          child: stops.isEmpty
              ? const _EmptyPanel(
                  icon: Icons.timeline_rounded,
                  title: 'Itinerary pending',
                  subtitle:
                      'Assigned package stops will appear as a guided progress tracker.',
                )
              : Column(
                  children: List.generate(stops.length, (index) {
                    return _ProgressStep(
                      title: stops[index],
                      subtitle: index == 0
                          ? 'Pickup and orientation'
                          : 'Destination stop',
                      isDone: index < activeIndex,
                      isActive: index == activeIndex,
                      isLast: index == stops.length - 1,
                    );
                  }),
                ),
        ),
      ],
    );
  }

  Widget _buildTodayTourEarnings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle("Today's Tour Earnings"),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEAF2FF), Color(0xFFF0FDF4)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFD6E8FF)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _EarningMetric(
                  label: 'Earnings today',
                  value: _money(_todayEarnings),
                  icon: Icons.payments_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EarningMetric(
                  label: 'Completed tours',
                  value: '$_todayTrips',
                  icon: Icons.task_alt_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EarningMetric(
                  label: 'Tourists assisted',
                  value: '${_todayTrips == 0 ? 0 : _todayTrips}',
                  icon: Icons.diversity_3_rounded,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGuideStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Driver/Tour Guide Stats'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _GuideStatCard(
                icon: Icons.star_rounded,
                label: 'Rating',
                value: _ratingLabel(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GuideStatCard(
                icon: Icons.emoji_events_rounded,
                label: 'Tours completed',
                value: '$_totalCompletedTours',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GuideStatCard(
                icon: Icons.verified_rounded,
                label: 'Badge',
                value: _guideBadge(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Quick Actions'),
        const SizedBox(height: 10),
        GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.85,
          children: [
            _QuickActionTile(
              icon: Icons.navigation_rounded,
              title: 'Navigate',
              onTap: _handleCenterAction,
            ),
            _QuickActionTile(
              icon: Icons.chat_rounded,
              title: 'Chat Tourist',
              onTap: _handleCenterAction,
            ),
            _QuickActionTile(
              icon: Icons.health_and_safety_rounded,
              title: 'Emergency Assistance',
              onTap: () => _showSnack('Emergency assistance panel ready.'),
            ),
            _QuickActionTile(
              icon: Icons.calendar_month_rounded,
              title: 'View Schedule',
              onTap: () =>
                  _showSnack('Schedule opens from the bottom navigation.'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTourMap(Map<String, dynamic> tour) {
    final pickupLat = _toDouble(tour['pickup_lat']);
    final pickupLng = _toDouble(tour['pickup_lng']);
    final dropLat = _toDouble(tour['dropoff_lat']);
    final dropLng = _toDouble(tour['dropoff_lng']);
    final driverLat = _toDouble(tour['driver_lat'], fallback: pickupLat);
    final driverLng = _toDouble(tour['driver_lng'], fallback: pickupLng);

    final center = LatLng(
      (pickupLat + dropLat + driverLat) / 3,
      (pickupLng + dropLng + driverLng) / 3,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 180,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: center, zoom: 13.8),
          cameraTargetBounds: CameraTargetBounds(_bulacanBounds),
          minMaxZoomPreference: const MinMaxZoomPreference(11.5, 18.5),
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          markers: {
            Marker(
              markerId: const MarkerId('guide'),
              position: LatLng(driverLat, driverLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure,
              ),
              infoWindow: const InfoWindow(title: 'Tour driver'),
            ),
            Marker(
              markerId: const MarkerId('pickup'),
              position: LatLng(pickupLat, pickupLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
              infoWindow: InfoWindow(title: _pickupName(tour)),
            ),
            Marker(
              markerId: const MarkerId('destination'),
              position: LatLng(dropLat, dropLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
              infoWindow: InfoWindow(title: _destinationName(tour)),
            ),
          },
          polylines: {
            Polyline(
              polylineId: const PolylineId('tour-route'),
              points: [
                LatLng(driverLat, driverLng),
                LatLng(pickupLat, pickupLng),
                LatLng(dropLat, dropLng),
              ],
              width: 5,
              color: const Color(0xFF2F6FFF),
            ),
          },
        ),
      ),
    );
  }

  Future<void> _startTour(Map<String, dynamic> tour) async {
    final id = tour['id']?.toString();
    if (id == null || id.isEmpty) return;

    try {
      await supabase
          .from('rides')
          .update({
            'status': 'ongoing',
            'driver_lat': _currentDriverLocation?.latitude,
            'driver_lng': _currentDriverLocation?.longitude,
            'driver_last_seen': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
      _showSnack('Tour progress started.');
    } catch (_) {
      _showSnack('Unable to start tour progress.');
    }
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontWeight: FontWeight.w900,
        fontSize: 18,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _tourInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF2F6FFF)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusPill(String status) {
    final label = status.trim().isEmpty ? 'Assigned' : status;
    final active =
        label == 'ongoing' || label == 'accepted' || label == 'enroute_pickup';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFECFDF5) : const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _titleCase(label.replaceAll('_', ' ')),
        style: TextStyle(
          color: active ? const Color(0xFF16A34A) : const Color(0xFF2F6FFF),
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }

  String _tourPackageName(Map<String, dynamic> tour) {
    final packageName = (tour['package_name'] ?? tour['package_title'] ?? '')
        .toString()
        .trim();
    if (packageName.isNotEmpty) return packageName;

    final destination = _destinationName(tour);
    return destination.isEmpty
        ? 'Assigned Tour Package'
        : '$destination Tour Package';
  }

  String _pickupName(Map<String, dynamic> tour) {
    final value = (tour['pickup_name'] ?? tour['pickup_address'] ?? '')
        .toString()
        .trim();
    return value.isEmpty ? 'Pickup location pending' : value;
  }

  String _destinationName(Map<String, dynamic> tour) {
    final value =
        (tour['dropoff_name'] ??
                tour['destination_name'] ??
                tour['dropoff_address'] ??
                '')
            .toString()
            .trim();
    return value.isEmpty ? 'Destination pending' : value;
  }

  String _tourTime(Map<String, dynamic> tour) {
    final raw =
        (tour['scheduled_at'] ?? tour['start_time'] ?? tour['created_at'] ?? '')
            .toString();
    final dt = DateTime.tryParse(raw);
    if (dt == null) return 'Schedule pending';

    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.month}/${dt.day}/${dt.year} $hour:$minute $ampm';
  }

  int _touristCount(Map<String, dynamic> tour) {
    final raw =
        tour['tourist_count'] ?? tour['passenger_count'] ?? tour['group_size'];
    if (raw is num && raw > 0) return raw.toInt();
    return 1;
  }

  List<String> _tourStops(Map<String, dynamic> tour) {
    final pickup = _pickupName(tour);
    final destination = _destinationName(tour);
    return [
      pickup,
      destination,
    ].where((value) => value.trim().isNotEmpty).toList();
  }

  String _tourStatus(Map<String, dynamic> tour) {
    final status = (tour['status'] ?? '').toString().trim();
    return status.isEmpty ? 'assigned' : status;
  }

  String _ratingLabel() {
    final raw = _profile?['rating'] ?? _profile?['driver_rating'];
    if (raw is num && raw > 0) return raw.toStringAsFixed(1);
    return 'New';
  }

  String _guideBadge() {
    final role = (_profile?['role'] ?? '').toString().trim();
    if (role.isEmpty) return 'Guide';
    return _titleCase(role.replaceAll('_', ' '));
  }

  double _toDouble(dynamic raw, {double fallback = 0}) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  String _money(num value) => 'PHP ${value.toStringAsFixed(2)}';

  String _titleCase(String value) {
    return value
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _displayName() {
    final full = (_profile?['full_name'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;

    final first = (_profile?['first_name'] ?? '').toString().trim();
    final last = (_profile?['last_name'] ?? '').toString().trim();
    final joined = ('$first $last').trim();
    return joined.isNotEmpty ? joined : 'Tour Driver';
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
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

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: const Color(0xFF2F6FFF)),
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
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2F6FFF), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
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

class _TourActionButton extends StatelessWidget {
  const _TourActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: primary ? const Color(0xFF2F6FFF) : const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: primary ? Colors.white : const Color(0xFF2F6FFF),
              size: 18,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: primary ? Colors.white : const Color(0xFF2F6FFF),
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.title,
    required this.subtitle,
    required this.isDone,
    required this.isActive,
    required this.isLast,
  });

  final String title;
  final String subtitle;
  final bool isDone;
  final bool isActive;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = isDone || isActive
        ? const Color(0xFF2F6FFF)
        : const Color(0xFFCBD5E1);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isDone
                    ? const Color(0xFF2F6FFF)
                    : isActive
                    ? const Color(0xFFEAF2FF)
                    : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(
                isDone ? Icons.check_rounded : Icons.place_rounded,
                color: isDone ? Colors.white : color,
                size: 16,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 42,
                color: color.withValues(alpha: 0.35),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 3, bottom: isLast ? 0 : 18),
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
                  ),
                ),
                const SizedBox(height: 3),
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
        ),
      ],
    );
  }
}

class _EarningMetric extends StatelessWidget {
  const _EarningMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF2F6FFF), size: 22),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _GuideStatCard extends StatelessWidget {
  const _GuideStatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF2F6FFF), size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7EEF7)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF2F6FFF)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
