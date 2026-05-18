import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/driver/driver_package_tracking_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_driver.dart';

class DriverTripsScreen extends StatefulWidget {
  const DriverTripsScreen({
    super.key,
    required this.onBottomNavTap,
    this.navIndex = 2,
  });

  final ValueChanged<int> onBottomNavTap;
  final int navIndex;

  @override
  State<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends State<DriverTripsScreen> {
  final _repo = TourisTrikeRepository();
  final _supabase = Supabase.instance.client;

  late Future<List<PackageActivity>> _future;
  _DriverActivityFilter _filter = _DriverActivityFilter.all;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchDriverActivities();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _reload() => setState(() => _future = _repo.fetchDriverActivities());

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('driver-activity:${_repo.currentUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'package_activities',
          callback: (_) => _reload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'package_activities',
          callback: (_) => _reload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'package_bookings',
          callback: (_) => _reload(),
        )
        .subscribe();
  }

  List<PackageActivity> _filtered(List<PackageActivity> items) {
    switch (_filter) {
      case _DriverActivityFilter.all:
        return items;
      case _DriverActivityFilter.active:
        return items
            .where(
              (item) => item.status == 'accepted' || item.status == 'ongoing',
            )
            .toList(growable: false);
      case _DriverActivityFilter.done:
        return items
            .where((item) => item.status == 'completed')
            .toList(growable: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: FutureBuilder<List<PackageActivity>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF2F6FFF)),
              );
            }
            if (snapshot.hasError) {
              return _DriverActivityError(
                message: snapshot.error.toString(),
                onRetry: _reload,
              );
            }

            final activities = snapshot.data ?? const [];
            final visible = _filtered(activities);
            final activeCount = activities
                .where((item) => item.status == 'accepted' || item.status == 'ongoing')
                .length;
            final doneCount = activities
                .where((item) => item.status == 'completed')
                .length;

            return RefreshIndicator(
              onRefresh: () async => _reload(),
              color: const Color(0xFF2F6FFF),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 44),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Activity',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _reload,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Color(0xFF2F6FFF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DriverActivityStat(
                          label: 'Bookings',
                          value: '${activities.length}',
                          icon: Icons.card_travel_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DriverActivityStat(
                          label: 'Active',
                          value: '$activeCount',
                          icon: Icons.navigation_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DriverActivityStat(
                          label: 'Done',
                          value: '$doneCount',
                          icon: Icons.check_circle_outline_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _DriverActivityFilterRow(
                    value: _filter,
                    onChanged: (value) => setState(() => _filter = value),
                  ),
                  const SizedBox(height: 14),
                  if (visible.isEmpty)
                    const _DriverActivityEmpty()
                  else
                    ...visible.map(
                      (activity) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _DriverActivityCard(activity: activity),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNavDriver(
        currentIndex: widget.navIndex,
        onTap: widget.onBottomNavTap,
      ),
    );
  }
}

enum _DriverActivityFilter { all, active, done }

class _DriverActivityCard extends StatelessWidget {
  const _DriverActivityCard({required this.activity});

  final PackageActivity activity;

  bool get _isActive => activity.status == 'accepted' || activity.status == 'ongoing';

  @override
  Widget build(BuildContext context) {
    final package = activity.packageRow;
    final booking = activity.bookingRow;
    final tourist = activity.touristRow;

    final packageTitle = dbString(package?['title'], fallback: 'Tour Package');
    final city = dbString(package?['city']);
    final touristName = dbString(
      tourist?['full_name'],
      fallback: [
        dbString(tourist?['first_name']),
        dbString(tourist?['last_name']),
      ].where((part) => part.isNotEmpty).join(' '),
    );
    final travelDate = booking?['travel_date'] == null
        ? null
        : DateTime.tryParse(booking!['travel_date'].toString());
    final totalAmount = booking?['total_amount'] is num
        ? (booking!['total_amount'] as num).toDouble()
        : activity.price;
    final bookingStatus = dbString(
      booking?['booking_status'],
      fallback: activity.tourStatus,
    );

    return InkWell(
      onTap: _isActive
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DriverPackageTrackingScreen(
                    activityId: activity.id.toString(),
                  ),
                ),
              );
            }
          : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7EEF7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _DriverStatusChip(status: activity.status),
              ],
            ),
            if (city.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                city,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _DriverActivityLine(
              icon: Icons.person_rounded,
              label: 'Tourist',
              value: touristName.isEmpty ? 'Tourist' : touristName,
            ),
            const SizedBox(height: 8),
            _DriverActivityLine(
              icon: Icons.calendar_today_rounded,
              label: 'Date',
              value: travelDate == null
                  ? 'Date pending'
                  : DateFormat('MMM d, yyyy').format(travelDate),
            ),
            const SizedBox(height: 8),
            _DriverActivityLine(
              icon: Icons.payments_outlined,
              label: 'Amount',
              value: NumberFormat.currency(
                symbol: 'PHP ',
                decimalDigits: 0,
              ).format(totalAmount),
            ),
            const SizedBox(height: 8),
            _DriverActivityLine(
              icon: Icons.info_outline_rounded,
              label: 'Progress',
              value: bookingStatus.replaceAll('_', ' '),
            ),
            if (_isActive) ...[
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Open live tracking',
                  style: TextStyle(
                    color: Color(0xFF2F6FFF),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DriverActivityStat extends StatelessWidget {
  const _DriverActivityStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF2F6FFF)),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverActivityFilterRow extends StatelessWidget {
  const _DriverActivityFilterRow({
    required this.value,
    required this.onChanged,
  });

  final _DriverActivityFilter value;
  final ValueChanged<_DriverActivityFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = const [
      (_DriverActivityFilter.all, 'All'),
      (_DriverActivityFilter.active, 'Active'),
      (_DriverActivityFilter.done, 'Done'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.map((item) {
          final selected = item.$1 == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(item.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF2F6FFF) : Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: const Color(0xFFE7EEF7)),
                ),
                child: Text(
                  item.$2,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _DriverActivityLine extends StatelessWidget {
  const _DriverActivityLine({
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
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _DriverStatusChip extends StatelessWidget {
  const _DriverStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status.toLowerCase()) {
      'accepted' => ('ACTIVE', const Color(0xFF2F6FFF)),
      'ongoing' => ('ONGOING', const Color(0xFF0EA5E9)),
      'completed' => ('DONE', const Color(0xFF16A34A)),
      _ => (status.toUpperCase(), const Color(0xFF64748B)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class _DriverActivityEmpty extends StatelessWidget {
  const _DriverActivityEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.route_rounded,
            size: 54,
            color: Color(0xFFCBD5E1),
          ),
          SizedBox(height: 14),
          Text(
            'No package activity yet',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Accepted and completed tour bookings will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverActivityError extends StatelessWidget {
  const _DriverActivityError({
    required this.message,
    required this.onRetry,
  });

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
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFDC2626),
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
