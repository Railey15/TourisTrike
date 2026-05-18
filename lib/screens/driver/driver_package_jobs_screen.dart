import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/driver/driver_package_tracking_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_driver.dart';

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
      final results = await Future.wait([
        _repo.fetchPendingPackageActivities(),
        _repo.driverHasActivePackageTour(),
      ]);
      final jobs = results[0] as List<PackageActivity>;
      final hasActiveTour = results[1] as bool;
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _hasActiveTour = hasActiveTour;
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
    if (_hasActiveTour) {
      _showSnack(
        'You already have an active tour. Complete it first before accepting another booking.',
      );
      return;
    }
    setState(() => _accepting = true);
    try {
      await _repo.acceptPackageBooking(
        activityId: job.id.toString(),
        bookingId: job.bookingId,
      );
      if (!mounted) return;
      _showSnack('Booking accepted! Head to tracking.');
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              DriverPackageTrackingScreen(activityId: job.id.toString()),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to accept: $e');
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
                      : '${_jobs.length} pending assignment${_jobs.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
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
              const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFEF4444)),
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
                  Icon(
                    Icons.inbox_rounded,
                    size: 64,
                    color: Color(0xFFCBD5E1),
                  ),
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
          accepting: _accepting,
          canAccept: !_hasActiveTour,
          onAccept: () => _accept(_jobs[index]),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.accepting,
    required this.canAccept,
    required this.onAccept,
  });

  final PackageActivity job;
  final bool accepting;
  final bool canAccept;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final booking = job.bookingRow;
    final package = job.packageRow;
    final packageTitle = _str(package?['title']) ?? 'Package Tour';
    final travelDate = _parseDate(booking?['travel_date']);
    final adults = booking?['adults'] is num ? (booking!['adults'] as num).toInt() : 1;
    final children = booking?['children'] is num ? (booking!['children'] as num).toInt() : 0;
    final bookingType = _str(booking?['booking_type']) ?? 'same_day';
    final pickupAddr = _str(booking?['pickup_address']) ?? 'Pickup pending';
    final dropoffAddr = _str(booking?['dropoff_address']) ?? 'Drop-off pending';
    final isAdvanced = bookingType == 'advanced';

    return Container(
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEAF2FF), Color(0xFFF0F9FF)],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
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
                      '$adults adult${adults == 1 ? '' : 's'}${children > 0 ? ' · $children child${children == 1 ? '' : 'ren'}' : ''}',
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
                  value: _money(job.price),
                ),
                if (isAdvanced) ...[
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.info_outline_rounded,
                    label: 'Payment',
                    value: '50% down paid · remaining on tour day',
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: accepting || !canAccept ? null : onAccept,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F6FFF),
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
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      accepting
                          ? 'Accepting...'
                          : canAccept
                          ? 'Accept This Job'
                          : 'Active Tour In Progress',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
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
