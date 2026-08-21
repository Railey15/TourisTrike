import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/screens/driver/incoming_ride_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_profile.dart';
import 'package:touristrike/widgets/app_bottom_nav_driver.dart';
import 'package:touristrike/widgets/driver_page_header.dart';

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
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged-in user.');
    }

    return user;
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
  }

  Future<void> _bootstrap() async {
    await _loadProfile();

    _subscribeProfileRealtime();

    await _loadActiveRideOnce();

    _subscribeMyActiveRideRealtime();

    await _refreshEarnings();

    if (_isOnline) {
      final ready = await _prepareLocationAndStartTracking();

      if (!ready) {
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
      final ready = await _prepareLocationAndStartTracking();

      if (ready && _activeRide == null) {
        _startSearchingRideListener();

        await _scanAndAutoAcceptLatest();
      }
    } else {
      _stopSearchingRideListener();
    }
  }

  // =========================================================================
  // PROFILE
  // =========================================================================

  Future<void> _loadProfile() async {
    final result = await supabase
        .from('profiles')
        .select(
          'id, full_name, first_name, last_name, '
          'profile_image_url, is_online, role',
        )
        .eq('id', _user.id)
        .maybeSingle();

    if (!mounted) return;

    setState(() {
      _profile = result;

      _isOnline = (result?['is_online'] as bool?) ?? false;
    });
  }

  void _subscribeProfileRealtime() {
    _profileSub?.cancel();

    _profileSub = supabase
        .from('profiles')
        .stream(primaryKey: const ['id'])
        .eq('id', _user.id)
        .listen((rows) async {
          if (!mounted || rows.isEmpty) {
            return;
          }

          final profile = rows.first;

          final newOnline = (profile['is_online'] as bool?) ?? false;

          setState(() {
            _profile = profile;
            _isOnline = newOnline;
          });

          if (newOnline) {
            final ready = await _prepareLocationAndStartTracking();

            if (!ready) {
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

  // =========================================================================
  // AVAILABILITY
  // =========================================================================

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
      final ready = await _prepareLocationAndStartTracking();

      if (!ready) {
        if (mounted) {
          setState(() {
            _isOnline = false;
          });
        }

        if (!fromProfileRealtime) {
          _showSnack('Location permission is required to go online.');
        }

        return;
      }

      if (mounted) {
        setState(() {
          _isOnline = true;
        });
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
        setState(() {
          _isOnline = false;
        });
      }

      if (!fromProfileRealtime) {
        await supabase
            .from('profiles')
            .update({'is_online': false})
            .eq('id', _user.id);
      }
    }
  }

  // =========================================================================
  // LOCATION
  // =========================================================================

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
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _currentDriverLocation = LatLng(position.latitude, position.longitude);

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
        .listen((Position position) async {
          _currentDriverLocation = LatLng(
            position.latitude,
            position.longitude,
          );

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
    if (_activeRide == null || _currentDriverLocation == null) {
      return;
    }

    final rideId = _activeRide!['id']?.toString();

    if (rideId == null || rideId.isEmpty) {
      return;
    }

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

  // =========================================================================
  // ACTIVE TOUR
  // =========================================================================

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

          for (final row in rows) {
            final status = (row['status'] ?? '').toString();

            if (status != 'completed' && status != 'cancelled') {
              active = row;
              break;
            }
          }

          setState(() {
            _activeRide = active;
          });

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

  // =========================================================================
  // SEARCHING / AUTO ACCEPT
  // =========================================================================

  void _startSearchingRideListener() {
    if (_searchingChannel != null) {
      return;
    }

    if (_activeRide != null) {
      return;
    }

    if (!_isOnline) {
      return;
    }

    _searchingChannel = supabase.channel('driver-searching-rides-${_user.id}');

    _searchingChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'rides',
          callback: (payload) async {
            if (!_isOnline || _activeRide != null || _accepting) {
              return;
            }

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
            if (!_isOnline || _activeRide != null || _accepting) {
              return;
            }

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
    final channel = _searchingChannel;

    _searchingChannel = null;

    if (channel != null) {
      supabase.removeChannel(channel);
    }
  }

  Future<void> _scanAndAutoAcceptLatest() async {
    if (!_isOnline || _activeRide != null || _accepting) {
      return;
    }

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
    if (!_isOnline || _activeRide != null || _currentDriverLocation == null) {
      return;
    }

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

      if (accepted == null || !mounted) {
        return;
      }

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

  // =========================================================================
  // EARNINGS
  // =========================================================================

  Future<void> _refreshEarnings() async {
    final now = DateTime.now();

    final start = DateTime(now.year, now.month, now.day);

    final end = start.add(const Duration(days: 1));

    num sum = 0;

    var trips = 0;
    var completedTotal = 0;

    try {
      final transactionRows = await supabase
          .from('payment_records')
          .select('amount, created_at')
          .eq('payee_id', _user.id)
          .eq('status', 'confirmed')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());

      for (final row in transactionRows) {
        final amount = row['amount'];

        if (amount is num) {
          sum += amount;
        }

        trips++;
      }
    } catch (_) {
      try {
        final activityRows = await supabase
            .from('package_activities')
            .select('price, updated_at')
            .eq('driver_id', _user.id)
            .eq('status', 'completed')
            .gte('updated_at', start.toIso8601String())
            .lt('updated_at', end.toIso8601String());

        for (final row in activityRows) {
          final price = row['price'];

          if (price is num) {
            sum += price;
          }

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

  // =========================================================================
  // NAVIGATION
  // =========================================================================

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

  // =========================================================================
  // UI
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),

      bottomNavigationBar: const AppBottomNavDriver(currentIndex: 0),

      body: RefreshIndicator(
        color: const Color(0xFF2F7EFF),
        backgroundColor: Colors.white,
        onRefresh: _refreshAll,

        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.only(bottom: 30),

          child: Align(
            alignment: Alignment.topCenter,

            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  _buildSharedTourHeader(),

                  const SizedBox(height: 18),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAvailabilityCard(),

                        const SizedBox(height: 24),

                        _sectionHeader(
                          title: 'Upcoming Schedule',
                          subtitle: 'Your next assigned tour',
                          icon: Icons.calendar_month_outlined,
                        ),

                        const SizedBox(height: 11),

                        _buildUpcomingTourSchedule(),

                        const SizedBox(height: 24),

                        _sectionHeader(
                          title: 'Active Assignment',
                          subtitle: 'Current tour operations',
                          icon: Icons.route_outlined,
                        ),

                        const SizedBox(height: 11),

                        _buildActiveTourAssignment(),

                        const SizedBox(height: 24),

                        _sectionHeader(
                          title: "Today's Performance",
                          subtitle: 'Your earnings and activity today',
                          icon: Icons.insights_outlined,
                        ),

                        const SizedBox(height: 11),

                        _buildTodayTourEarnings(),

                        const SizedBox(height: 24),

                        _sectionHeader(
                          title: 'Driver Overview',
                          subtitle: 'Your tour guide performance',
                          icon: Icons.workspace_premium_outlined,
                        ),

                        const SizedBox(height: 11),

                        _buildGuideStats(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // HEADER
  // =========================================================================

  Widget _buildSharedTourHeader() {
    final imageUrl = (_profile?['profile_image_url'] ?? '').toString().trim();

    return DriverPageHeader.custom(
      headerContent: Row(
        children: [
          _DriverAvatar(imageUrl: imageUrl, name: _displayName()),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _displayName(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.35,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _isOnline
                            ? const Color(0xFF86EFAC)
                            : Colors.white.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _isOnline ? 'Available for tours' : 'Currently offline',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.86),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DriverHeaderActionButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Notifications',
            onPressed: () {
              _showSnack('No new tour notifications.');
            },
          ),
          const SizedBox(width: 7),
          DriverHeaderActionButton(
            icon: Icons.person_outline_rounded,
            tooltip: 'Profile',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DriverProfileScreen()),
              );
            },
          ),
        ],
      ),
      stats: [
        DriverHeaderStat(
          icon: Icons.route_rounded,
          value: _activeRide == null ? 'None' : 'Assigned',
          label: 'Active Tour',
        ),
        DriverHeaderStat(
          icon: Icons.payments_outlined,
          value: _money(_todayEarnings),
          label: "Today's Earnings",
        ),
      ],
    );
  }

  // =========================================================================
  // AVAILABILITY
  // =========================================================================

  Widget _buildAvailabilityCard() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.fromLTRB(14, 14, 13, 14),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: const Color(0xFFE5ECF5)),

        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),

      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),

            width: 48,
            height: 48,

            decoration: BoxDecoration(
              color: _isOnline
                  ? const Color(0xFFECFDF3)
                  : const Color(0xFFF1F5F9),

              borderRadius: BorderRadius.circular(15),
            ),

            child: Icon(
              _isOnline
                  ? Icons.location_searching_rounded
                  : Icons.location_disabled_outlined,

              color: _isOnline
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF7C8BA1),

              size: 22,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Row(
                  children: [
                    const Text(
                      'Availability',
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(width: 7),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),

                      decoration: BoxDecoration(
                        color: _isOnline
                            ? const Color(0xFFECFDF3)
                            : const Color(0xFFF1F5F9),

                        borderRadius: BorderRadius.circular(999),
                      ),

                      child: Text(
                        _isOnline ? 'ONLINE' : 'OFFLINE',

                        style: TextStyle(
                          color: _isOnline
                              ? const Color(0xFF15803D)
                              : const Color(0xFF64748B),
                          fontWeight: FontWeight.w900,
                          fontSize: 8.5,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                Text(
                  _isOnline
                      ? _activeRide == null
                            ? 'Ready and waiting for tour assignments'
                            : 'You currently have an assigned tour'
                      : 'Go online when you are ready to accept tours',

                  style: const TextStyle(
                    color: Color(0xFF78869A),
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Switch(
            value: _isOnline,

            onChanged: _settingOnline ? null : _setOnline,

            activeThumbColor: Colors.white,

            activeTrackColor: const Color(0xFF16A34A),

            inactiveThumbColor: Colors.white,

            inactiveTrackColor: const Color(0xFF94A3B8),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // UPCOMING TOUR
  // =========================================================================

  Widget _buildUpcomingTourSchedule() {
    final tour = _activeRide;

    if (tour == null) {
      return const _DashboardEmptyState(
        icon: Icons.calendar_month_outlined,
        title: 'No upcoming tour yet',
        subtitle: 'Your next assigned package will appear here automatically.',
      );
    }

    return _DashboardSurface(
      child: Column(
        children: [
          _TourInfoRow(
            icon: Icons.card_travel_outlined,
            label: 'Tour package',
            value: _tourPackageName(tour),
          ),

          const _InnerDivider(),

          _TourInfoRow(
            icon: Icons.schedule_outlined,
            label: 'Schedule',
            value: _tourTime(tour),
          ),

          const _InnerDivider(),

          _TourInfoRow(
            icon: Icons.group_outlined,
            label: 'Tourists',
            value:
                '${_touristCount(tour)} ${_touristCount(tour) == 1 ? 'tourist' : 'tourists'}',
          ),

          const _InnerDivider(),

          _TourInfoRow(
            icon: Icons.location_on_outlined,
            label: 'Pickup point',
            value: _pickupName(tour),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // ACTIVE ASSIGNMENT
  // =========================================================================

  Widget _buildActiveTourAssignment() {
    final tour = _activeRide;

    if (tour == null) {
      return _DashboardEmptyState(
        icon: Icons.route_outlined,
        title: 'No active assignment',
        subtitle: _isOnline
            ? 'You are online. New tour assignments will appear here when available.'
            : 'Turn on your availability to start receiving tour assignments.',
      );
    }

    return _DashboardSurface(
      padding: const EdgeInsets.all(14),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      _tourPackageName(tour),

                      maxLines: 2,

                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        height: 1.18,
                        letterSpacing: -0.25,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: Color(0xFF718096),
                        ),

                        const SizedBox(width: 4),

                        Expanded(
                          child: Text(
                            _pickupName(tour),

                            maxLines: 1,

                            overflow: TextOverflow.ellipsis,

                            style: const TextStyle(
                              color: Color(0xFF718096),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              _statusPill(_tourStatus(tour)),
            ],
          ),

          const SizedBox(height: 14),

          _buildTourMap(tour),

          const SizedBox(height: 13),

          Row(
            children: [
              Expanded(
                child: _TourSummaryBox(
                  icon: Icons.group_outlined,
                  value: '${_touristCount(tour)}',
                  label: 'Tourists',
                ),
              ),

              const SizedBox(width: 9),

              Expanded(
                child: _TourSummaryBox(
                  icon: Icons.schedule_outlined,
                  value: _tourTimeShort(tour),
                  label: 'Start Time',
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          _TourInfoRow(
            icon: Icons.alt_route_rounded,
            label: 'Route',
            value: _tourStops(tour).join(' → '),
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                flex: 2,
                child: _PrimaryTourButton(
                  icon: Icons.navigation_rounded,
                  label: 'Open Tour',
                  onTap: _handleCenterAction,
                ),
              ),

              const SizedBox(width: 9),

              Expanded(
                child: _SecondaryTourButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Start',
                  onTap: () {
                    _startTour(tour);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // EARNINGS
  // =========================================================================

  Widget _buildTodayTourEarnings() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.fromLTRB(15, 16, 15, 15),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEDF5FF), Color(0xFFF6FBFF), Color(0xFFF0FDF6)],
        ),

        borderRadius: BorderRadius.circular(24),

        border: Border.all(color: const Color(0xFFDCE9F8)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(13),

                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.08),

                      blurRadius: 12,
                    ),
                  ],
                ),

                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Text(
                      'Earnings today',
                      style: TextStyle(
                        color: Color(0xFF718096),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      _money(_todayEarnings),

                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(999),
                ),

                child: const Text(
                  'TODAY',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),

            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.76),

              borderRadius: BorderRadius.circular(17),
            ),

            child: Row(
              children: [
                Expanded(
                  child: _PerformanceMetric(
                    icon: Icons.task_alt_rounded,
                    value: '$_todayTrips',
                    label: 'Completed',
                  ),
                ),

                Container(width: 1, height: 34, color: const Color(0xFFE4EBF3)),

                Expanded(
                  child: _PerformanceMetric(
                    icon: Icons.groups_2_outlined,
                    value: '${_todayTrips == 0 ? 0 : _todayTrips}',
                    label: 'Assisted',
                  ),
                ),

                Container(width: 1, height: 34, color: const Color(0xFFE4EBF3)),

                Expanded(
                  child: _PerformanceMetric(
                    icon: Icons.local_taxi_outlined,
                    value: _activeRide == null ? '0' : '1',
                    label: 'Active',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // DRIVER STATS
  // =========================================================================

  Widget _buildGuideStats() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: const Color(0xFFE5ECF5)),
      ),

      child: Row(
        children: [
          Expanded(
            child: _DriverStatItem(
              icon: Icons.star_outline_rounded,
              value: _ratingLabel(),
              label: 'Rating',
            ),
          ),

          const _StatDivider(),

          Expanded(
            child: _DriverStatItem(
              icon: Icons.emoji_events_outlined,
              value: '$_totalCompletedTours',
              label: 'Tours',
            ),
          ),

          const _StatDivider(),

          Expanded(
            child: _DriverStatItem(
              icon: Icons.verified_outlined,
              value: _guideBadge(),
              label: 'Role',
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // SECTION HEADER
  // =========================================================================

  Widget _sectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,

          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),

            borderRadius: BorderRadius.circular(12),
          ),

          child: Icon(icon, color: const Color(0xFF2F7EFF), size: 18),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF8A98AB),
                  fontSize: 10.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // MAP
  // =========================================================================

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
      borderRadius: BorderRadius.circular(18),

      child: SizedBox(
        height: 165,

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

              color: const Color(0xFF2F7EFF),
            ),
          },
        ),
      ),
    );
  }

  // =========================================================================
  // START TOUR
  // =========================================================================

  Future<void> _startTour(Map<String, dynamic> tour) async {
    final id = tour['id']?.toString();

    if (id == null || id.isEmpty) {
      return;
    }

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

  // =========================================================================
  // STATUS
  // =========================================================================

  Widget _statusPill(String status) {
    final normalized = status.trim().toLowerCase();

    final label = normalized.isEmpty ? 'assigned' : normalized;

    final isActive = label == 'ongoing';

    final isAccepted = label == 'accepted' || label == 'enroute_pickup';

    Color foreground;
    Color background;

    if (isActive) {
      foreground = const Color(0xFF15803D);

      background = const Color(0xFFECFDF3);
    } else if (isAccepted) {
      foreground = const Color(0xFF2563EB);

      background = const Color(0xFFEEF5FF);
    } else {
      foreground = const Color(0xFF64748B);

      background = const Color(0xFFF1F5F9);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),

      decoration: BoxDecoration(
        color: background,

        borderRadius: BorderRadius.circular(999),
      ),

      child: Text(
        _titleCase(label.replaceAll('_', ' ')),

        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w900,
          fontSize: 9.5,
        ),
      ),
    );
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  String _tourPackageName(Map<String, dynamic> tour) {
    final packageName = (tour['package_name'] ?? tour['package_title'] ?? '')
        .toString()
        .trim();

    if (packageName.isNotEmpty) {
      return packageName;
    }

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

    final date = DateTime.tryParse(raw)?.toLocal();

    if (date == null) {
      return 'Schedule pending';
    }

    final hour = date.hour > 12
        ? date.hour - 12
        : date.hour == 0
        ? 12
        : date.hour;

    final minute = date.minute.toString().padLeft(2, '0');

    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '${_monthShort(date.month)} ${date.day}, ${date.year} • $hour:$minute $period';
  }

  String _tourTimeShort(Map<String, dynamic> tour) {
    final raw =
        (tour['scheduled_at'] ?? tour['start_time'] ?? tour['created_at'] ?? '')
            .toString();

    final date = DateTime.tryParse(raw)?.toLocal();

    if (date == null) {
      return 'Pending';
    }

    final hour = date.hour > 12
        ? date.hour - 12
        : date.hour == 0
        ? 12
        : date.hour;

    final minute = date.minute.toString().padLeft(2, '0');

    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  int _touristCount(Map<String, dynamic> tour) {
    final raw =
        tour['tourist_count'] ?? tour['passenger_count'] ?? tour['group_size'];

    if (raw is num && raw > 0) {
      return raw.toInt();
    }

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

    if (raw is num && raw > 0) {
      return raw.toStringAsFixed(1);
    }

    return 'New';
  }

  String _guideBadge() {
    final role = (_profile?['role'] ?? '').toString().trim();

    if (role.isEmpty) {
      return 'Driver';
    }

    return _titleCase(role.replaceAll('_', ' '));
  }

  double _toDouble(dynamic raw, {double fallback = 0}) {
    if (raw is num) {
      return raw.toDouble();
    }

    return double.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  String _money(num value) {
    return 'PHP ${value.toStringAsFixed(2)}';
  }

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

    if (full.isNotEmpty) {
      return full;
    }

    final first = (_profile?['first_name'] ?? '').toString().trim();

    final last = (_profile?['last_name'] ?? '').toString().trim();

    final combined = '$first $last'.trim();

    return combined.isNotEmpty ? combined : 'Tour Driver';
  }

  String _greeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'Good morning';
    }

    if (hour < 18) {
      return 'Good afternoon';
    }

    return 'Good evening';
  }

  String _monthShort(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    if (month < 1 || month > 12) {
      return '';
    }

    return months[month - 1];
  }
}

// =============================================================================
// DRIVER AVATAR
// =============================================================================

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar({required this.imageUrl, required this.name});

  final String imageUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Container(
      width: DriverPageHeader.profileAvatarSize,
      height: DriverPageHeader.profileAvatarSize,

      decoration: BoxDecoration(
        shape: BoxShape.circle,

        color: Colors.white.withValues(alpha: 0.22),

        border: Border.all(
          color: Colors.white.withValues(alpha: 0.72),
          width: 2,
        ),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],

        image: imageUrl.isEmpty
            ? null
            : DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
      ),

      child: imageUrl.isNotEmpty
          ? null
          : Center(
              child: Text(
                initials.isEmpty ? 'D' : initials,

                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
    );
  }
}

// =============================================================================
// SURFACE
// =============================================================================

class _DashboardSurface extends StatelessWidget {
  const _DashboardSurface({
    required this.child,
    this.padding = const EdgeInsets.all(15),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: padding,

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: const Color(0xFFE5ECF5)),

        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),

            blurRadius: 18,

            offset: const Offset(0, 8),
          ),
        ],
      ),

      child: child,
    );
  }
}

// =============================================================================
// EMPTY STATE
// =============================================================================

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({
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

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: const Color(0xFFE5ECF5)),

        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),

            blurRadius: 16,

            offset: const Offset(0, 7),
          ),
        ],
      ),

      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,

            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),

              borderRadius: BorderRadius.circular(16),
            ),

            child: Icon(icon, color: const Color(0xFF2F7EFF), size: 23),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,

                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  subtitle,

                  style: const TextStyle(
                    color: Color(0xFF718096),
                    fontSize: 11.2,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
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

// =============================================================================
// TOUR INFO
// =============================================================================

class _TourInfoRow extends StatelessWidget {
  const _TourInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,

      children: [
        Container(
          width: 34,
          height: 34,

          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),

            borderRadius: BorderRadius.circular(11),
          ),

          child: Icon(icon, color: const Color(0xFF2F7EFF), size: 17),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Text(
                label,

                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                value,

                maxLines: 2,

                overflow: TextOverflow.ellipsis,

                style: const TextStyle(
                  color: Color(0xFF253047),
                  fontSize: 12.2,
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
}

// =============================================================================
// DIVIDER
// =============================================================================

class _InnerDivider extends StatelessWidget {
  const _InnerDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 11),

      child: Divider(height: 1, color: Color(0xFFEDF1F6)),
    );
  }
}

// =============================================================================
// ACTIVE TOUR SUMMARY
// =============================================================================

class _TourSummaryBox extends StatelessWidget {
  const _TourSummaryBox({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),

      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),

        borderRadius: BorderRadius.circular(15),

        border: Border.all(color: const Color(0xFFE9EEF5)),
      ),

      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2F7EFF), size: 17),

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
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 1),

                Text(
                  label,

                  style: const TextStyle(
                    color: Color(0xFF8A98AB),
                    fontWeight: FontWeight.w600,
                    fontSize: 9.5,
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

// =============================================================================
// PRIMARY BUTTON
// =============================================================================

class _PrimaryTourButton extends StatelessWidget {
  const _PrimaryTourButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,

      child: ElevatedButton.icon(
        onPressed: onTap,

        icon: Icon(icon, size: 18),

        label: Text(label),

        style: ElevatedButton.styleFrom(
          elevation: 0,

          foregroundColor: Colors.white,

          backgroundColor: const Color(0xFF2F7EFF),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),

          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SECONDARY BUTTON
// =============================================================================

class _SecondaryTourButton extends StatelessWidget {
  const _SecondaryTourButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,

      child: OutlinedButton.icon(
        onPressed: onTap,

        icon: Icon(icon, size: 17),

        label: Text(label),

        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF2F7EFF),

          side: const BorderSide(color: Color(0xFFCFE0FA)),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),

          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PERFORMANCE METRIC
// =============================================================================

class _PerformanceMetric extends StatelessWidget {
  const _PerformanceMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF2F7EFF), size: 18),

        const SizedBox(height: 6),

        Text(
          value,

          maxLines: 1,

          overflow: TextOverflow.ellipsis,

          style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),

        const SizedBox(height: 2),

        Text(
          label,

          style: const TextStyle(
            color: Color(0xFF8A98AB),
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// DRIVER STAT
// =============================================================================

class _DriverStatItem extends StatelessWidget {
  const _DriverStatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,

          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),

            borderRadius: BorderRadius.circular(12),
          ),

          child: Icon(icon, color: const Color(0xFF2F7EFF), size: 18),
        ),

        const SizedBox(height: 8),

        Text(
          value,

          maxLines: 1,

          overflow: TextOverflow.ellipsis,

          textAlign: TextAlign.center,

          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 2),

        Text(
          label,

          style: const TextStyle(
            color: Color(0xFF8795A8),
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// STAT DIVIDER
// =============================================================================

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 50, color: const Color(0xFFE9EEF5));
  }
}
