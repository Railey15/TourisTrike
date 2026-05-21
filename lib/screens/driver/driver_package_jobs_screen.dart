import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/driver/driver_package_booking_details_screen.dart';
import 'package:touristrike/screens/driver/driver_package_tracking_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_driver.dart';

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
  final _repo = TourisTrikeRepository();
  final _supabase = Supabase.instance.client;

  List<PackageActivity> _jobs = [];
  bool _loading = true;
  String? _error;
  bool _accepting = false;
  bool _hasActiveTour = false;
  Set<String> _acceptedBookingIds = {};
  Map<String, int> _itineraryCounts = {};
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
      final itineraryCounts = await _repo.fetchBookingItineraryCounts(
        jobs.map((job) => job.bookingId),
      );
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _hasActiveTour = hasActiveTour;
        _acceptedBookingIds = acceptedIds;
        _itineraryCounts = itineraryCounts;
        _driverProfile = profile;
        _driverDetails = driverDetails;
        _driverApplication = driverApplication;
        _driverMunicipality = driverMunicipality;
        _driverProvince = driverProvince;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

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
        );
    _channel!.subscribe();
  }

  Future<void> _accept(PackageActivity job) async {
    if (_accepting) return;
    final disabledReason = _acceptDisabledReason(job);
    if (disabledReason != null) {
      _showSnack(disabledReason);
      return;
    }
    setState(() => _accepting = true);
    try {
      final result = await _repo.acceptPackageBooking(bookingId: job.bookingId);
      if (!mounted) return;

      final accepted = (result['accepted_count'] as num?)?.toInt() ?? 1;
      final required = (result['required_count'] as num?)?.toInt() ?? 1;
      final allFilled = result['all_filled'] as bool? ?? true;
      final remaining = required - accepted;

      final msg = allFilled
          ? 'All drivers confirmed! Head to tracking.'
          : 'Slot accepted! Waiting for $remaining more driver${remaining == 1 ? '' : 's'}.';
      _showSnack(msg);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              DriverPackageTrackingScreen(activityId: job.id.toString()),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint(
        'DriverPackageJobsScreen accept failed '
        'bookingId=${job.bookingId} driverId=${_repo.currentUserId ?? 'unknown'} '
        'error=$e',
      );
      // Surface human-readable messages from the RPC
      final msg = _humanizeError(e.toString());
      _showSnack(msg);
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

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

  String _normalizedLocationText(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

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

  String? _acceptDisabledReason(PackageActivity job) {
    final driver = _driverProfile;
    final booking = job.bookingRow;

    // ── Debug log all approval signals ───────────────────────────────────────
    final profileMap = driver?.row ?? const {};
    final detailsMap = _driverDetails?.row;
    final applicationMap = _driverApplication?.row;
    final approved = isDriverApproved(
      profile: profileMap,
      driverDetails: detailsMap,
      driverApplication: applicationMap,
    );
    debugPrint(
      '[PackageJobs] driverId=${_repo.currentUserId} '
      'city=$_driverMunicipality province=$_driverProvince '
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      body: Column(
        children: [
          _buildHeader(),
          if (_hasActiveTour)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: const Text(
                'You already have an active tour. Complete it first before accepting another booking.',
                style: TextStyle(
                  color: Color(0xFF9A3412),
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: const AppBottomNavDriver(currentIndex: 1),
    );
  }

  Widget _buildHeader() {
    final rating = _driverProfile?.averageRating ?? 0.0;
    final reviews = _driverProfile?.totalReviews ?? 0;
    final hasRating = reviews > 0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 16,
        20,
        18,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F6FFF), Color(0xFF42B8FF)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.work_outline_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Package Jobs',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                Text(
                  _loading
                      ? 'Loading...'
                      : _hasActiveTour
                      ? 'Finish your active tour before accepting another job.'
                      : _acceptedBookingIds.isNotEmpty
                      ? '${_jobs.length} available · ${_acceptedBookingIds.length} accepted'
                      : '${_jobs.length} pending assignment${_jobs.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                if (hasRating) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 14),
                      const SizedBox(width: 3),
                      Text(
                        '${rating.toStringAsFixed(1)}  ($reviews review${reviews == 1 ? '' : 's'})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Color(0xFFEF4444),
              ),
              const SizedBox(height: 12),
              Text(
                'Failed to load jobs',
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_jobs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_rounded, size: 64, color: Color(0xFFCBD5E1)),
                  SizedBox(height: 16),
                  Text(
                    'No pending package jobs',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'New tour bookings will appear here.\nPull to refresh.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF64748B), height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _jobs.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _JobCard(
          job: _jobs[index],
          itineraryCount: _itineraryCounts[_jobs[index].bookingId] ?? 0,
          accepting: _accepting,
          disabledReason: _acceptDisabledReason(_jobs[index]),
          onAccept: () => _accept(_jobs[index]),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DriverPackageBookingDetailsScreen(
                  activityId: _jobs[index].id.toString(),
                  initialJob: _jobs[index],
                  initialItineraryCount:
                      _itineraryCounts[_jobs[index].bookingId] ?? 0,
                  disabledReason: _acceptDisabledReason(_jobs[index]),
                ),
              ),
            );
            if (mounted) _load();
          },
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.itineraryCount,
    required this.accepting,
    required this.disabledReason,
    required this.onAccept,
    required this.onTap,
  });

  final PackageActivity job;
  final int itineraryCount;
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
    final pickupAddr = _str(booking?['pickup_address']) ?? 'Pickup pending';
    final dropoffAddr = _str(booking?['dropoff_address']) ?? 'Drop-off pending';
    final isAdvanced = bookingType == 'advanced';
    final requiredDrivers =
        (booking?['required_drivers'] as num?)?.toInt() ?? 1;
    final acceptedDrivers =
        (booking?['accepted_drivers_count'] as num?)?.toInt() ?? 0;
    final isGroup = requiredDrivers > 1;
    // Prefer booking municipality, fall back to package city, then province
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7EEF7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.055),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top banner
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEAF2FF), Color(0xFFF0F9FF)],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        packageTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isGroup)
                      _GroupPill(
                        accepted: acceptedDrivers,
                        required: requiredDrivers,
                      ),
                    if (isGroup) const SizedBox(width: 6),
                    _TypePill(isAdvanced: isAdvanced),
                  ],
                ),
              ),
              // Details
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.calendar_today_rounded,
                      label: 'Tour date',
                      value: travelDate != null
                          ? DateFormat('MMM d, yyyy').format(travelDate)
                          : 'Date pending',
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.groups_rounded,
                      label: 'Group',
                      value:
                          passengerText ??
                          '$adults adult${adults == 1 ? '' : 's'}${children > 0 ? ' · $children child${children == 1 ? '' : 'ren'}' : ''}',
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.location_city_rounded,
                      label: 'Area',
                      value: areaLabel,
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.map_rounded,
                      label: 'Itinerary',
                      value:
                          '$itineraryCount spot${itineraryCount == 1 ? '' : 's'}',
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.trip_origin_rounded,
                      label: 'Pickup',
                      value: pickupAddr,
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.flag_rounded,
                      label: 'Drop-off',
                      value: dropoffAddr,
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.payments_rounded,
                      label: 'Amount',
                      value: _money(totalAmount),
                    ),
                    if (isAdvanced) ...[
                      const SizedBox(height: 10),
                      _InfoRow(
                        icon: Icons.info_outline_rounded,
                        label: 'Payment',
                        value: '50% down paid · remaining on tour day',
                      ),
                    ],
                    if (isGroup) ...[
                      const SizedBox(height: 10),
                      _GroupDriversStatusBar(
                        accepted: acceptedDrivers,
                        required: requiredDrivers,
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: accepting || isDisabled ? null : onAccept,
                        style: FilledButton.styleFrom(
                          backgroundColor: isDisabled && !accepting
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF2F6FFF),
                          disabledBackgroundColor: const Color(0xFF94A3B8),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: accepting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                isOutOfArea
                                    ? Icons.location_off_rounded
                                    : isFull
                                    ? Icons.group_off_rounded
                                    : alreadyAccepted
                                    ? Icons.verified_rounded
                                    : isDisabled
                                    ? Icons.info_outline_rounded
                                    : Icons.check_circle_outline_rounded,
                              ),
                        label: Text(
                          accepting
                              ? 'Accepting...'
                              : isOutOfArea
                              ? 'Out of Your Area'
                              : isFull
                              ? 'Booking Full'
                              : alreadyAccepted
                              ? 'Already Accepted'
                              : isDisabled
                              ? 'Cannot Accept'
                              : 'Accept This Job',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    if (disabledReason != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          disabledReason!,
                          style: TextStyle(
                            color: isOutOfArea || isFull
                                ? const Color(0xFF92400E)
                                : const Color(0xFF64748B),
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
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

  String _money(double v) => 'PHP ${v.toStringAsFixed(2)}';

  String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.isAdvanced});
  final bool isAdvanced;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isAdvanced ? const Color(0xFFFFF7ED) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isAdvanced ? 'Advanced' : 'Same Day',
        style: TextStyle(
          color: isAdvanced ? const Color(0xFFEA580C) : const Color(0xFF16A34A),
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 17, color: const Color(0xFF2F6FFF)),
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
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
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

class _GroupPill extends StatelessWidget {
  const _GroupPill({required this.accepted, required this.required});

  final int accepted;
  final int required;

  @override
  Widget build(BuildContext context) {
    final full = accepted >= required;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: full ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        full ? 'Full ($required/$required)' : 'Group $accepted/$required',
        style: TextStyle(
          color: full ? const Color(0xFF16A34A) : const Color(0xFFEA580C),
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: full ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: full ? const Color(0xFF86EFAC) : const Color(0xFFFED7AA),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.directions_car_rounded,
            size: 16,
            color: full ? const Color(0xFF16A34A) : const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GROUP BOOKING',
                  style: TextStyle(
                    color: full
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF92400E),
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  full
                      ? 'All $required drivers confirmed'
                      : '$accepted of $required drivers accepted · $remaining slot${remaining == 1 ? '' : 's'} open',
                  style: TextStyle(
                    color: full
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF92400E),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: required > 0 ? accepted / required : 0,
                backgroundColor: full
                    ? const Color(0xFFBBF7D0)
                    : const Color(0xFFFED7AA),
                valueColor: AlwaysStoppedAnimation(
                  full ? const Color(0xFF16A34A) : const Color(0xFFF59E0B),
                ),
                minHeight: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
