import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/driver/driver_package_booking_details_screen.dart';
import 'package:touristrike/screens/driver/driver_package_tracking_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_driver.dart';
import 'package:touristrike/widgets/driver_page_header.dart';

bool isDriverApproved({
  required Map<String, dynamic> profile,
  Map<String, dynamic>? driverDetails,
  Map<String, dynamic>? driverApplication,
}) {
  final verificationStatus = profile['verification_status']
      ?.toString()
      .toLowerCase()
      .trim();

  final status = profile['status']?.toString().toLowerCase().trim();

  final driverStatus = profile['driver_status']
      ?.toString()
      .toLowerCase()
      .trim();

  final detailsStatus = driverDetails?['status']
      ?.toString()
      .toLowerCase()
      .trim();

  final applicationStatus = driverApplication?['status']
      ?.toString()
      .toLowerCase()
      .trim();

  return profile['is_verified'] == true ||
      profile['is_approved'] == true ||
      verificationStatus == 'approved' ||
      status == 'approved' ||
      driverStatus == 'approved' ||
      detailsStatus == 'approved' ||
      applicationStatus == 'approved';
}

class DriverPackageJobsScreen extends StatefulWidget {
  const DriverPackageJobsScreen({super.key});

  @override
  State<DriverPackageJobsScreen> createState() =>
      _DriverPackageJobsScreenState();
}

class _DriverPackageJobsScreenState extends State<DriverPackageJobsScreen> {
  final TourisTrikeRepository _repo = TourisTrikeRepository();
  final SupabaseClient _supabase = Supabase.instance.client;

  List<PackageActivity> _jobs = [];

  bool _loading = true;
  bool _accepting = false;
  bool _hasActiveTour = false;

  String? _error;

  Set<String> _acceptedBookingIds = {};

  Map<String, int> _itineraryCounts = {};
  Map<String, List<BookingItineraryItem>> _itineraryItemsMap = {};

  Profile? _driverProfile;
  DriverDetails? _driverDetails;
  DriverApplication? _driverApplication;

  String _driverMunicipality = '';
  String _driverProvince = '';

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();

    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // =========================================================================
  // LOAD
  // =========================================================================

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final userId = _repo.requireUserId();

      final results = await Future.wait([
        _repo.fetchPendingPackageActivities(),
        _repo.driverHasActivePackageTour(),
        _repo.fetchDriverAcceptedBookingIds(),
        _repo.currentProfile(),
        _repo.fetchDriverDetails(userId),
        _repo.fetchCurrentDriverApplication(),
      ]);

      final allJobs = results[0] as List<PackageActivity>;

      final hasActiveTour = results[1] as bool;

      final acceptedIds = results[2] as Set<String>;

      final profile = results[3] as Profile;

      final driverDetails = results[4] as DriverDetails?;

      final driverApplication = results[5] as DriverApplication?;

      final driverMunicipality = _normalizedLocationText(
        profile.municipality.isNotEmpty ? profile.municipality : profile.city,
      );

      final driverProvince = _normalizedLocationText(profile.province);

      final jobs = allJobs
          .where(
            (job) =>
                !acceptedIds.contains(job.bookingId) &&
                _isMatchingDriverArea(
                  job: job,
                  driverMunicipality: driverMunicipality,
                  driverProvince: driverProvince,
                ),
          )
          .toList();

      final bookingIds = jobs.map((job) => job.bookingId).toSet().toList();

      var itineraryCounts = await _repo.fetchBookingItineraryCounts(bookingIds);

      final missingItineraryIds = itineraryCounts.entries
          .where((entry) => entry.value == 0)
          .map((entry) => entry.key)
          .toList(growable: false);

      if (missingItineraryIds.isNotEmpty) {
        await Future.wait(
          missingItineraryIds.map((bookingId) async {
            try {
              await _repo.ensureBookingItinerary(bookingId);
            } catch (_) {}
          }),
        );

        itineraryCounts = await _repo.fetchBookingItineraryCounts(bookingIds);
      }

      Map<String, List<BookingItineraryItem>> itineraryItemsMap = {};

      if (bookingIds.isNotEmpty) {
        try {
          final rows = await _supabase
              .from('booking_itinerary_items')
              .select(
                'id, booking_id, destination_name, '
                'destination_address, arrival_time, departure_time, '
                'actual_arrival_time, actual_departure_time, '
                'source_type, spot_status, order_number, destination_order',
              )
              .inFilter('booking_id', bookingIds)
              .order('order_number', ascending: true)
              .order('destination_order', ascending: true);

          for (final row in rows as List<dynamic>) {
            final map = Map<String, dynamic>.from(row as Map);

            final bookingId = map['booking_id']?.toString() ?? '';

            if (bookingId.isEmpty) {
              continue;
            }

            itineraryItemsMap.putIfAbsent(bookingId, () => []);

            itineraryItemsMap[bookingId]!.add(BookingItineraryItem(map));
          }
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _jobs = jobs;

        _hasActiveTour = hasActiveTour;

        _acceptedBookingIds = acceptedIds;

        _itineraryCounts = itineraryCounts;

        _itineraryItemsMap = itineraryItemsMap;

        _driverProfile = profile;

        _driverDetails = driverDetails;

        _driverApplication = driverApplication;

        _driverMunicipality = driverMunicipality;

        _driverProvince = driverProvince;

        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  // =========================================================================
  // REALTIME
  // =========================================================================

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('driver-jobs-${_repo.currentUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'package_activities',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'package_activities',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'package_bookings',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'booking_itinerary_items',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'booking_itinerary_items',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'booking_itinerary_items',
          callback: (_) => _load(),
        );

    _channel!.subscribe();
  }

  // =========================================================================
  // ACCEPT JOB
  // =========================================================================

  Future<void> _accept(PackageActivity job) async {
    if (_accepting) return;

    final disabledReason = _acceptDisabledReason(job);

    if (disabledReason != null) {
      _showSnack(disabledReason);

      return;
    }

    setState(() {
      _accepting = true;
    });

    try {
      final result = await _repo.acceptPackageBooking(bookingId: job.bookingId);

      if (!mounted) return;

      final accepted = (result['accepted_count'] as num?)?.toInt() ?? 1;

      final required = (result['required_count'] as num?)?.toInt() ?? 1;

      final allFilled = result['all_filled'] as bool? ?? true;

      final remaining = required - accepted;

      final message = allFilled
          ? 'All drivers confirmed! Head to tracking.'
          : 'Slot accepted! Waiting for $remaining more '
                'driver${remaining == 1 ? '' : 's'}.';

      _showSnack(message);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              DriverPackageTrackingScreen(activityId: job.id.toString()),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      debugPrint(
        'DriverPackageJobsScreen accept failed '
        'bookingId=${job.bookingId} '
        'driverId=${_repo.currentUserId ?? 'unknown'} '
        'error=$error',
      );

      final message = _humanizeError(error.toString());

      _showSnack(message);
    } finally {
      if (mounted) {
        setState(() {
          _accepting = false;
        });
      }
    }
  }

  // =========================================================================
  // SNACKBAR
  // =========================================================================

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

  // =========================================================================
  // ERROR MESSAGES
  // =========================================================================

  String _humanizeError(String raw) {
    if (raw.contains('MUNICIPALITY_MISMATCH')) {
      final match = RegExp(r'Booking is for (.+?) only').firstMatch(raw);

      final area = match?.group(1) ?? 'your area';

      return 'This booking is only available to drivers in $area.';
    }

    if (raw.contains('PROVINCE_MISMATCH')) {
      return 'This booking is outside your assigned municipality.';
    }

    if (raw.contains('BOOKING_ALREADY_FULL')) {
      return 'This booking already has enough drivers.';
    }

    if (raw.contains('ALREADY_ACCEPTED')) {
      return 'You already accepted this booking.';
    }

    if (raw.contains('DRIVER_NOT_AVAILABLE')) {
      return 'You must be online/available to accept bookings.';
    }

    if (raw.contains('DRIVER_NOT_VERIFIED')) {
      return 'Only verified drivers can accept bookings.';
    }

    if (raw.contains('DRIVER_ROLE_REQUIRED')) {
      return 'Only driver accounts can accept package bookings.';
    }

    if (raw.contains('DRIVER_NOT_FOUND')) {
      return 'Driver profile not found. Please sign in again.';
    }

    if (raw.contains('ACTIVE_TOUR_EXISTS')) {
      return 'Complete your current tour before accepting another.';
    }

    if (raw.contains('BOOKING_NOT_AVAILABLE')) {
      return 'This booking is no longer accepting drivers.';
    }

    return 'Failed to accept booking. Please try again.';
  }

  // =========================================================================
  // LOCATION
  // =========================================================================

  String _normalizedLocationText(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _bookingMunicipality(PackageActivity job) {
    final bookingMunicipality = (job.bookingRow?['municipality'] ?? '')
        .toString()
        .trim();

    if (bookingMunicipality.isNotEmpty) {
      return _normalizedLocationText(bookingMunicipality);
    }

    return _normalizedLocationText((job.packageRow?['city'] ?? '').toString());
  }

  String _bookingProvince(PackageActivity job) {
    final bookingProvince = (job.bookingRow?['province'] ?? '')
        .toString()
        .trim();

    return _normalizedLocationText(
      bookingProvince.isEmpty ? 'Bulacan' : bookingProvince,
    );
  }

  bool _isMatchingDriverArea({
    required PackageActivity job,
    required String driverMunicipality,
    required String driverProvince,
  }) {
    final bookingMunicipality = _bookingMunicipality(job);

    final bookingProvince = _bookingProvince(job);

    return bookingMunicipality.isNotEmpty &&
        driverMunicipality.isNotEmpty &&
        bookingMunicipality == driverMunicipality &&
        bookingProvince == driverProvince;
  }

  // =========================================================================
  // DISABLED REASON
  // =========================================================================

  String? _acceptDisabledReason(PackageActivity job) {
    final driver = _driverProfile;

    final booking = job.bookingRow;

    final profileMap = driver?.row ?? const {};

    final detailsMap = _driverDetails?.row;

    final applicationMap = _driverApplication?.row;

    final approved = isDriverApproved(
      profile: profileMap,
      driverDetails: detailsMap,
      driverApplication: applicationMap,
    );

    debugPrint(
      '[PackageJobs] '
      'driverId=${_repo.currentUserId} '
      'city=$_driverMunicipality '
      'province=$_driverProvince '
      'is_verified=${profileMap['is_verified']} '
      'is_approved=${profileMap['is_approved']} '
      'verification_status=${profileMap['verification_status']} '
      'driver_status=${profileMap['driver_status']} '
      'details.status=${detailsMap?['status']} '
      'application.status=${applicationMap?['status']} '
      'computedApproved=$approved '
      'bookingMunicipality=${booking?['municipality']} '
      'bookingProvince=${booking?['province']} '
      'accepted=${booking?['accepted_drivers_count']} '
      'required=${booking?['required_drivers']}',
    );

    if (_repo.currentUserId == null) {
      return 'Please log in again to accept bookings.';
    }

    if (driver == null) {
      return 'Driver profile not found.';
    }

    if (!driver.isDriver) {
      return 'Only driver accounts can accept package bookings.';
    }

    if (!approved) {
      return 'Only verified drivers can accept bookings.';
    }

    if (!_isMatchingDriverArea(
      job: job,
      driverMunicipality: _driverMunicipality,
      driverProvince: _driverProvince,
    )) {
      return 'This booking is outside your assigned municipality.';
    }

    if (!(driver.isAvailable || driver.isOnline)) {
      return 'You must be online/available to accept bookings.';
    }

    if (_hasActiveTour) {
      return 'Complete your current tour before accepting another.';
    }

    if (_acceptedBookingIds.contains(job.bookingId)) {
      return 'You already accepted this booking.';
    }

    final bookingStatus =
        (booking?['booking_status'] ?? booking?['status'] ?? job.status)
            .toString()
            .trim()
            .toLowerCase();

    if (bookingStatus != 'pending' && bookingStatus != 'waiting_for_drivers') {
      return 'This booking is no longer accepting drivers.';
    }

    final requiredDrivers =
        (booking?['required_drivers'] as num?)?.toInt() ?? 1;

    final acceptedDrivers =
        (booking?['accepted_drivers_count'] as num?)?.toInt() ?? 0;

    if (acceptedDrivers >= requiredDrivers) {
      return 'This booking already has enough drivers.';
    }

    return null;
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final rating = _driverProfile?.averageRating ?? 0.0;
    final reviews = _driverProfile?.totalReviews ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),

      bottomNavigationBar: const AppBottomNavDriver(currentIndex: 1),

      body: Align(
        alignment: Alignment.topCenter,

        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),

          child: Column(
            children: [
              _buildSharedHeader(),

              if (reviews > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF59E0B),
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${rating.toStringAsFixed(1)} '
                        '• $reviews review${reviews == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),

              if (_hasActiveTour)
                _ActiveTourBanner(
                  onTap: () {
                    _showSnack(
                      'Complete your current tour before accepting another.',
                    );
                  },
                ),

              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // HEADER
  // =========================================================================

  Widget _buildSharedHeader() {
    final municipality = _driverMunicipality.isEmpty
        ? 'Not set'
        : _titleCase(_driverMunicipality);

    return DriverPageHeader(
      icon: Icons.work_outline_rounded,
      title: 'Package Jobs',
      subtitle: 'New tour assignments available to you',
      onRefresh: _load,
      stats: [
        DriverHeaderStat(
          icon: Icons.assignment_outlined,
          value: _loading ? '...' : '${_jobs.length}',
          label: 'Available',
        ),
        DriverHeaderStat(
          icon: Icons.check_circle_outline_rounded,
          value: '${_acceptedBookingIds.length}',
          label: 'Accepted',
        ),
        DriverHeaderStat(
          icon: Icons.location_on_outlined,
          value: municipality,
          label: 'Area',
        ),
      ],
    );
  }

  // =========================================================================
  // BODY
  // =========================================================================

  Widget _buildBody() {
    if (_loading) {
      return const _JobsLoadingState();
    }

    if (_error != null) {
      return _JobsErrorState(error: _error!, onRetry: _load);
    }

    if (_jobs.isEmpty) {
      return _EmptyJobsState(
        municipality: _driverMunicipality,
        hasActiveTour: _hasActiveTour,
        acceptedCount: _acceptedBookingIds.length,
        onRefresh: _load,
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF2F7EFF),

      backgroundColor: Colors.white,

      onRefresh: _load,

      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),

        padding: const EdgeInsets.fromLTRB(16, 18, 16, 26),

        children: [
          _JobsSectionHeader(
            count: _jobs.length,
            municipality: _driverMunicipality,
          ),

          const SizedBox(height: 14),

          ..._jobs.map(
            (job) => Padding(
              padding: const EdgeInsets.only(bottom: 14),

              child: _JobCard(
                job: job,

                itineraryCount: _itineraryCounts[job.bookingId] ?? 0,

                itineraryItems: _itineraryItemsMap[job.bookingId] ?? [],

                accepting: _accepting,

                disabledReason: _acceptDisabledReason(job),

                onAccept: () => _accept(job),

                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DriverPackageBookingDetailsScreen(
                        activityId: job.id.toString(),

                        initialJob: job,

                        initialItineraryCount:
                            _itineraryCounts[job.bookingId] ?? 0,

                        disabledReason: _acceptDisabledReason(job),
                      ),
                    ),
                  );

                  if (mounted) {
                    _load();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _titleCase(String text) {
    return text
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

// =============================================================================
// JOBS SECTION HEADER
// =============================================================================

class _ActiveTourBanner extends StatelessWidget {
  const _ActiveTourBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Material(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF8D99B)),
            ),
            child: const Row(
              children: [
                Icon(Icons.route_rounded, color: Color(0xFFB45309), size: 19),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Complete your active tour before accepting another.',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 10.8,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFB45309),
                  size: 19,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JobsSectionHeader extends StatelessWidget {
  const _JobsSectionHeader({required this.count, required this.municipality});

  final int count;
  final String municipality;

  @override
  Widget build(BuildContext context) {
    final area = municipality
        .trim()
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');

    return Row(
      children: [
        Container(
          width: 37,
          height: 37,

          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),

            borderRadius: BorderRadius.circular(12),
          ),

          child: const Icon(
            Icons.assignment_outlined,
            color: Color(0xFF2F7EFF),
            size: 18,
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              const Text(
                'Available Assignments',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: -0.2,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                area.isEmpty
                    ? 'Tour packages available for you'
                    : 'Tour packages available around $area',

                style: const TextStyle(
                  color: Color(0xFF8A98AB),
                  fontWeight: FontWeight.w600,
                  fontSize: 10.8,
                ),
              ),
            ],
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),

          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),

            borderRadius: BorderRadius.circular(999),
          ),

          child: Text(
            '$count',

            style: const TextStyle(
              color: Color(0xFF2F7EFF),
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// EMPTY JOBS
// =============================================================================

class _EmptyJobsState extends StatelessWidget {
  const _EmptyJobsState({
    required this.municipality,
    required this.hasActiveTour,
    required this.acceptedCount,
    required this.onRefresh,
  });

  final String municipality;
  final bool hasActiveTour;
  final int acceptedCount;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final area = municipality
        .trim()
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');

    return RefreshIndicator(
      color: const Color(0xFF2F7EFF),

      onRefresh: onRefresh,

      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),

        padding: const EdgeInsets.fromLTRB(18, 24, 18, 30),

        children: [
          Container(
            width: double.infinity,

            padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),

            decoration: BoxDecoration(
              color: Colors.white,

              borderRadius: BorderRadius.circular(24),

              border: Border.all(color: const Color(0xFFE5ECF5)),

              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.035),

                  blurRadius: 22,

                  offset: const Offset(0, 10),
                ),
              ],
            ),

            child: Column(
              children: [
                Container(
                  width: 74,
                  height: 74,

                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3FF),

                    borderRadius: BorderRadius.circular(24),
                  ),

                  child: const Icon(
                    Icons.work_outline_rounded,
                    color: Color(0xFF2F7EFF),
                    size: 31,
                  ),
                ),

                const SizedBox(height: 18),

                const Text(
                  'No package jobs right now',
                  textAlign: TextAlign.center,

                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    letterSpacing: -0.2,
                  ),
                ),

                const SizedBox(height: 7),

                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 310),

                  child: Text(
                    hasActiveTour
                        ? 'You already have an active tour. New jobs can be accepted after your current assignment is completed.'
                        : area.isNotEmpty
                        ? 'New tour bookings in $area will appear here automatically when they need drivers.'
                        : 'New tour bookings in your assigned area will appear here automatically.',

                    textAlign: TextAlign.center,

                    style: const TextStyle(
                      color: Color(0xFF718096),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),

                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F8FF),

                    borderRadius: BorderRadius.circular(999),
                  ),

                  child: const Row(
                    mainAxisSize: MainAxisSize.min,

                    children: [
                      Icon(
                        Icons.sync_rounded,
                        color: Color(0xFF2F7EFF),
                        size: 14,
                      ),

                      SizedBox(width: 6),

                      Text(
                        'Jobs update automatically',
                        style: TextStyle(
                          color: Color(0xFF57739A),
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: _EmptySummaryTile(
                  icon: Icons.check_circle_outline_rounded,
                  value: '$acceptedCount',
                  label: 'Accepted',
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: _EmptySummaryTile(
                  icon: Icons.location_on_outlined,
                  value: area.isEmpty ? 'Assigned' : area,
                  label: 'Service Area',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptySummaryTile extends StatelessWidget {
  const _EmptySummaryTile({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: const Color(0xFFE5ECF5)),
      ),

      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF2F7EFF), size: 20),

          const SizedBox(height: 7),

          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,

            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 2),

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
    );
  }
}

// =============================================================================
// LOADING
// =============================================================================

class _JobsLoadingState extends StatelessWidget {
  const _JobsLoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),

      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),

      children: [
        const Row(
          children: [
            Text(
              'Available Assignments',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        ...List.generate(
          2,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 13),

            child: _JobSkeleton(),
          ),
        ),
      ],
    );
  }
}

class _JobSkeleton extends StatelessWidget {
  const _JobSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: const Color(0xFFE5ECF5)),
      ),

      child: Column(
        children: [
          Container(
            height: 56,

            decoration: const BoxDecoration(
              color: Color(0xFFF0F5FA),

              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
          ),

          const Expanded(
            child: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF2F7EFF),
                strokeWidth: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ERROR STATE
// =============================================================================

class _JobsErrorState extends StatelessWidget {
  const _JobsErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),

        child: Container(
          width: double.infinity,

          constraints: const BoxConstraints(maxWidth: 420),

          padding: const EdgeInsets.all(24),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(24),

            border: Border.all(color: const Color(0xFFE5ECF5)),
          ),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              Container(
                width: 62,
                height: 62,

                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),

                  borderRadius: BorderRadius.circular(20),
                ),

                child: const Icon(
                  Icons.error_outline_rounded,
                  size: 29,
                  color: Color(0xFFDC2626),
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Unable to load jobs',
                textAlign: TextAlign.center,

                style: TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),

              const SizedBox(height: 7),

              Text(
                error,

                textAlign: TextAlign.center,

                style: const TextStyle(
                  color: Color(0xFF718096),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 47,

                child: ElevatedButton.icon(
                  onPressed: onRetry,

                  icon: const Icon(Icons.refresh_rounded, size: 18),

                  label: const Text('Try Again'),

                  style: ElevatedButton.styleFrom(
                    elevation: 0,

                    backgroundColor: const Color(0xFF2F7EFF),

                    foregroundColor: Colors.white,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),

                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
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

// =============================================================================
// JOB CARD
// =============================================================================

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.itineraryCount,
    required this.itineraryItems,
    required this.accepting,
    required this.disabledReason,
    required this.onAccept,
    required this.onTap,
  });

  final PackageActivity job;

  final int itineraryCount;

  final List<BookingItineraryItem> itineraryItems;

  final bool accepting;

  final String? disabledReason;

  final VoidCallback onAccept;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final booking = job.bookingRow;

    final package = job.packageRow;

    final packageTitle = _str(package?['title']) ?? 'Package Tour';

    final travelDate = _parseDate(booking?['travel_date']);

    final adults = booking?['adults'] is num
        ? (booking!['adults'] as num).toInt()
        : 1;

    final children = booking?['children'] is num
        ? (booking!['children'] as num).toInt()
        : 0;

    final passengerText = _str(booking?['total_passengers']);

    final bookingType = _str(booking?['booking_type']) ?? 'same_day';

    final pickupAddress = _str(booking?['pickup_address']) ?? 'Pickup pending';

    final dropoffAddress =
        _str(booking?['dropoff_address']) ?? 'Drop-off pending';

    final isAdvanced = bookingType == 'advanced';

    final requiredDrivers =
        (booking?['required_drivers'] as num?)?.toInt() ?? 1;

    final acceptedDrivers =
        (booking?['accepted_drivers_count'] as num?)?.toInt() ?? 0;

    final isGroup = requiredDrivers > 1;

    final bookingMunicipality = _str(booking?['municipality']);

    final packageCity = _str(package?['city']);

    final municipality = bookingMunicipality ?? packageCity ?? '';

    final province = _str(booking?['province']) ?? 'Bulacan';

    final areaLabel = municipality.isNotEmpty
        ? '$municipality, $province'
        : province;

    final totalAmount =
        (booking?['total_amount'] as num?)?.toDouble() ?? job.price;

    final isDisabled = disabledReason != null;

    final isOutOfArea =
        disabledReason == 'This booking is outside your assigned municipality.';

    final isFull = disabledReason == 'This booking already has enough drivers.';

    final alreadyAccepted =
        disabledReason == 'You already accepted this booking.';

    final itineraryStopCount = itineraryItems.isNotEmpty
        ? itineraryItems.length
        : itineraryCount;

    return Material(
      color: Colors.transparent,

      child: InkWell(
        onTap: onTap,

        borderRadius: BorderRadius.circular(24),

        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(24),

            border: Border.all(color: const Color(0xFFE5ECF5)),

            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.045),

                blurRadius: 20,

                offset: const Offset(0, 9),
              ),
            ],
          ),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // -------------------------------------------------------------
              // TOP
              // -------------------------------------------------------------
              Container(
                padding: const EdgeInsets.fromLTRB(15, 14, 13, 13),

                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,

                    colors: [Color(0xFFF0F6FF), Color(0xFFF8FBFF)],
                  ),

                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),

                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Container(
                      width: 42,
                      height: 42,

                      decoration: BoxDecoration(
                        color: const Color(0xFFE1EDFF),

                        borderRadius: BorderRadius.circular(13),
                      ),

                      child: const Icon(
                        Icons.tour_outlined,
                        color: Color(0xFF2F7EFF),
                        size: 21,
                      ),
                    ),

                    const SizedBox(width: 11),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            packageTitle,

                            maxLines: 2,

                            overflow: TextOverflow.ellipsis,

                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5,
                              height: 1.17,
                              letterSpacing: -0.2,
                            ),
                          ),

                          const SizedBox(height: 6),

                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                color: Color(0xFF718096),
                                size: 13,
                              ),

                              const SizedBox(width: 4),

                              Expanded(
                                child: Text(
                                  areaLabel,

                                  maxLines: 1,

                                  overflow: TextOverflow.ellipsis,

                                  style: const TextStyle(
                                    color: Color(0xFF718096),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,

                      children: [
                        _TypePill(isAdvanced: isAdvanced),

                        if (isGroup) ...[
                          const SizedBox(height: 6),

                          _GroupPill(
                            accepted: acceptedDrivers,
                            required: requiredDrivers,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // -------------------------------------------------------------
              // QUICK SUMMARY
              // -------------------------------------------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 0),

                child: Row(
                  children: [
                    Expanded(
                      child: _JobQuickMetric(
                        icon: Icons.calendar_today_outlined,
                        value: travelDate != null
                            ? DateFormat('MMM d').format(travelDate)
                            : 'Pending',
                        label: 'Date',
                      ),
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: _JobQuickMetric(
                        icon: Icons.groups_outlined,
                        value: passengerText ?? '${adults + children}',
                        label: 'Tourists',
                      ),
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: _JobQuickMetric(
                        icon: Icons.route_outlined,
                        value: '$itineraryStopCount',
                        label: 'Stops',
                      ),
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: _JobQuickMetric(
                        icon: Icons.payments_outlined,
                        value: '₱${totalAmount.toStringAsFixed(0)}',
                        label: 'Amount',
                      ),
                    ),
                  ],
                ),
              ),

              // -------------------------------------------------------------
              // DETAILS
              // -------------------------------------------------------------
              Padding(
                padding: const EdgeInsets.all(14),

                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.calendar_month_outlined,
                      label: 'Tour date',
                      value: travelDate != null
                          ? DateFormat('MMMM d, yyyy').format(travelDate)
                          : 'Date pending',
                    ),

                    const _JobDivider(),

                    _InfoRow(
                      icon: Icons.group_outlined,
                      label: 'Travel group',
                      value:
                          passengerText ??
                          '$adults adult${adults == 1 ? '' : 's'}'
                              '${children > 0 ? ' • $children child${children == 1 ? '' : 'ren'}' : ''}',
                    ),

                    const _JobDivider(),

                    _InfoRow(
                      icon: Icons.trip_origin_rounded,
                      label: 'Pickup point',
                      value: pickupAddress,
                    ),

                    const _JobDivider(),

                    _InfoRow(
                      icon: Icons.flag_outlined,
                      label: 'Destination',
                      value: dropoffAddress,
                    ),

                    if (itineraryItems.isNotEmpty) ...[
                      const SizedBox(height: 12),

                      _ItineraryPreview(items: itineraryItems),
                    ],

                    if (isAdvanced) ...[
                      const SizedBox(height: 12),

                      const _PaymentNotice(),
                    ],

                    if (isGroup) ...[
                      const SizedBox(height: 12),

                      _GroupDriversStatusBar(
                        accepted: acceptedDrivers,
                        required: requiredDrivers,
                      ),
                    ],

                    const SizedBox(height: 15),

                    SizedBox(
                      width: double.infinity,
                      height: 48,

                      child: FilledButton.icon(
                        onPressed: accepting || isDisabled ? null : onAccept,

                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2F7EFF),

                          disabledBackgroundColor: const Color(0xFFCBD5E1),

                          foregroundColor: Colors.white,

                          disabledForegroundColor: const Color(0xFF64748B),

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),

                        icon: accepting
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                isOutOfArea
                                    ? Icons.location_off_outlined
                                    : isFull
                                    ? Icons.group_off_outlined
                                    : alreadyAccepted
                                    ? Icons.check_circle_rounded
                                    : isDisabled
                                    ? Icons.info_outline_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 18,
                              ),

                        label: Text(
                          accepting
                              ? 'Accepting...'
                              : isOutOfArea
                              ? 'Outside Your Area'
                              : isFull
                              ? 'Booking Full'
                              : alreadyAccepted
                              ? 'Already Accepted'
                              : isDisabled
                              ? 'Cannot Accept'
                              : 'Accept Assignment',

                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),

                    if (disabledReason != null) ...[
                      const SizedBox(height: 9),

                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),

                        decoration: BoxDecoration(
                          color: isOutOfArea || isFull
                              ? const Color(0xFFFFF7E8)
                              : const Color(0xFFF4F7FA),

                          borderRadius: BorderRadius.circular(11),
                        ),

                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 14,
                              color: isOutOfArea || isFull
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFF718096),
                            ),

                            const SizedBox(width: 6),

                            Expanded(
                              child: Text(
                                disabledReason!,

                                style: TextStyle(
                                  color: isOutOfArea || isFull
                                      ? const Color(0xFF92400E)
                                      : const Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _str(dynamic value) {
    if (value == null) {
      return null;
    }

    final string = value.toString().trim();

    return string.isEmpty ? null : string;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }
}

// =============================================================================
// QUICK METRIC
// =============================================================================

class _JobQuickMetric extends StatelessWidget {
  const _JobQuickMetric({
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
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),

      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),

        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: const Color(0xFFE9EEF5)),
      ),

      child: Column(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF2F7EFF)),

          const SizedBox(height: 5),

          Text(
            value,

            maxLines: 1,

            overflow: TextOverflow.ellipsis,

            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
            ),
          ),

          const SizedBox(height: 1),

          Text(
            label,

            style: const TextStyle(
              color: Color(0xFF8A98AB),
              fontWeight: FontWeight.w600,
              fontSize: 8.5,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// JOB DIVIDER
// =============================================================================

class _JobDivider extends StatelessWidget {
  const _JobDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),

      child: Divider(height: 1, color: Color(0xFFEDF1F6)),
    );
  }
}

// =============================================================================
// PAYMENT NOTICE
// =============================================================================

class _PaymentNotice extends StatelessWidget {
  const _PaymentNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),

      decoration: BoxDecoration(
        color: const Color(0xFFF3F8FF),

        borderRadius: BorderRadius.circular(13),

        border: Border.all(color: const Color(0xFFDDE9F9)),
      ),

      child: const Row(
        children: [
          Icon(Icons.payments_outlined, color: Color(0xFF2F7EFF), size: 17),

          SizedBox(width: 8),

          Expanded(
            child: Text(
              '50% down payment received • remaining balance due on tour day',
              style: TextStyle(
                color: Color(0xFF57708F),
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ITINERARY
// =============================================================================

class _ItineraryPreview extends StatelessWidget {
  const _ItineraryPreview({required this.items});

  final List<BookingItineraryItem> items;

  @override
  Widget build(BuildContext context) {
    final displayItems = items.take(4).toList();

    final extra = items.length - displayItems.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),

      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),

        borderRadius: BorderRadius.circular(15),

        border: Border.all(color: const Color(0xFFDDE9F9)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              const Icon(
                Icons.route_outlined,
                color: Color(0xFF2F7EFF),
                size: 15,
              ),

              const SizedBox(width: 6),

              const Text(
                'ITINERARY',
                style: TextStyle(
                  color: Color(0xFF8090A5),
                  fontWeight: FontWeight.w900,
                  fontSize: 9,
                  letterSpacing: 0.7,
                ),
              ),

              const Spacer(),

              Text(
                '${items.length} stop${items.length == 1 ? '' : 's'}',

                style: const TextStyle(
                  color: Color(0xFF2F7EFF),
                  fontWeight: FontWeight.w700,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: 9),

          ...displayItems.asMap().entries.map((entry) {
            final index = entry.key;

            final item = entry.value;

            final isLast = index == displayItems.length - 1;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Column(
                  children: [
                    Container(
                      width: 23,
                      height: 23,

                      decoration: const BoxDecoration(
                        color: Color(0xFFE4EFFF),
                        shape: BoxShape.circle,
                      ),

                      child: Center(
                        child: Text(
                          '${index + 1}',

                          style: const TextStyle(
                            color: Color(0xFF2F7EFF),
                            fontWeight: FontWeight.w900,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),

                    if (!isLast)
                      Container(
                        width: 2,
                        height: 26,
                        color: const Color(0xFFDCE8F8),
                      ),
                  ],
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 8),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Text(
                          item.destinationName,

                          maxLines: 1,

                          overflow: TextOverflow.ellipsis,

                          style: const TextStyle(
                            color: Color(0xFF253047),
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),

                        if (item.destinationAddress.isNotEmpty) ...[
                          const SizedBox(height: 2),

                          Text(
                            item.destinationAddress,

                            maxLines: 1,

                            overflow: TextOverflow.ellipsis,

                            style: const TextStyle(
                              color: Color(0xFF8A98AB),
                              fontWeight: FontWeight.w500,
                              fontSize: 9.8,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),

          if (extra > 0) ...[
            const SizedBox(height: 6),

            Text(
              '+$extra more stop${extra == 1 ? '' : 's'}',

              style: const TextStyle(
                color: Color(0xFF2F7EFF),
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// TYPE PILL
// =============================================================================

class _TypePill extends StatelessWidget {
  const _TypePill({required this.isAdvanced});

  final bool isAdvanced;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),

      decoration: BoxDecoration(
        color: isAdvanced ? const Color(0xFFFFF6E8) : const Color(0xFFECFDF3),

        borderRadius: BorderRadius.circular(999),
      ),

      child: Text(
        isAdvanced ? 'Advanced' : 'Same Day',

        style: TextStyle(
          color: isAdvanced ? const Color(0xFFD97706) : const Color(0xFF15803D),
          fontWeight: FontWeight.w900,
          fontSize: 9,
        ),
      ),
    );
  }
}

// =============================================================================
// INFO ROW
// =============================================================================

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
          width: 33,
          height: 33,

          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),

            borderRadius: BorderRadius.circular(11),
          ),

          child: Icon(icon, size: 16, color: const Color(0xFF2F7EFF)),
        ),

        const SizedBox(width: 10),

        SizedBox(
          width: 76,

          child: Text(
            label,

            style: const TextStyle(
              color: Color(0xFF8A98AB),
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ),

        const SizedBox(width: 5),

        Expanded(
          child: Text(
            value,

            maxLines: 2,

            overflow: TextOverflow.ellipsis,

            textAlign: TextAlign.right,

            style: const TextStyle(
              color: Color(0xFF253047),
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// GROUP PILL
// =============================================================================

class _GroupPill extends StatelessWidget {
  const _GroupPill({required this.accepted, required this.required});

  final int accepted;
  final int required;

  @override
  Widget build(BuildContext context) {
    final full = accepted >= required;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),

      decoration: BoxDecoration(
        color: full ? const Color(0xFFECFDF3) : const Color(0xFFFFF6E8),

        borderRadius: BorderRadius.circular(999),
      ),

      child: Text(
        full ? '$required/$required Full' : '$accepted/$required Drivers',

        style: TextStyle(
          color: full ? const Color(0xFF15803D) : const Color(0xFFD97706),
          fontWeight: FontWeight.w900,
          fontSize: 8.5,
        ),
      ),
    );
  }
}

// =============================================================================
// GROUP STATUS
// =============================================================================

class _GroupDriversStatusBar extends StatelessWidget {
  const _GroupDriversStatusBar({
    required this.accepted,
    required this.required,
  });

  final int accepted;
  final int required;

  @override
  Widget build(BuildContext context) {
    final remaining = required - accepted;

    final full = remaining <= 0;

    final progress = required > 0 ? (accepted / required).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(11),

      decoration: BoxDecoration(
        color: full ? const Color(0xFFECFDF3) : const Color(0xFFFFF7E8),

        borderRadius: BorderRadius.circular(14),

        border: Border.all(
          color: full ? const Color(0xFFBBF7D0) : const Color(0xFFF7D9A3),
        ),
      ),

      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.directions_car_outlined,

                size: 16,

                color: full ? const Color(0xFF15803D) : const Color(0xFFB45309),
              ),

              const SizedBox(width: 7),

              Expanded(
                child: Text(
                  full
                      ? 'All $required drivers confirmed'
                      : '$accepted of $required drivers confirmed',

                  style: TextStyle(
                    color: full
                        ? const Color(0xFF15803D)
                        : const Color(0xFF92400E),
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
              ),

              if (!full)
                Text(
                  '$remaining left',

                  style: const TextStyle(
                    color: Color(0xFFB45309),
                    fontWeight: FontWeight.w900,
                    fontSize: 9.5,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          ClipRRect(
            borderRadius: BorderRadius.circular(999),

            child: LinearProgressIndicator(
              value: progress,

              minHeight: 5,

              backgroundColor: full
                  ? const Color(0xFFBBF7D0)
                  : const Color(0xFFFDE5BA),

              valueColor: AlwaysStoppedAnimation(
                full ? const Color(0xFF16A34A) : const Color(0xFFF59E0B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
