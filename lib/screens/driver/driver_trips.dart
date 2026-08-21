import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/driver/driver_package_tracking_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_driver.dart';
import 'package:touristrike/widgets/driver_page_header.dart';

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
  final TourisTrikeRepository _repo = TourisTrikeRepository();
  final SupabaseClient _supabase = Supabase.instance.client;

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

  void _reload() {
    if (!mounted) return;

    setState(() {
      _future = _repo.fetchDriverActivities();
    });
  }

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
            .where((item) => item.isActiveLifecycle)
            .toList(growable: false);

      case _DriverActivityFilter.done:
        return items
            .where((item) => item.lifecycleStatus == 'completed')
            .toList(growable: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),

      bottomNavigationBar: AppBottomNavDriver(
        currentIndex: widget.navIndex,
        onTap: widget.onBottomNavTap,
      ),

      body: FutureBuilder<List<PackageActivity>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _DriverActivityLoading();
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
              .where((item) => item.isActiveLifecycle)
              .length;

          final doneCount = activities
              .where((item) => item.lifecycleStatus == 'completed')
              .length;

          final totalCompletedAmount = activities
              .where((item) => item.lifecycleStatus == 'completed')
              .fold<double>(0, (total, item) {
                final booking = item.bookingRow;

                final amount = booking?['total_amount'] is num
                    ? (booking!['total_amount'] as num).toDouble()
                    : item.price;

                return total + amount;
              });

          return RefreshIndicator(
            color: const Color(0xFF2F7EFF),
            backgroundColor: Colors.white,
            onRefresh: () async {
              _reload();
            },
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.only(bottom: 28),
                  children: [
                    DriverPageHeader(
                      icon: Icons.history_rounded,
                      title: 'Activity',
                      subtitle: 'Track your accepted and completed tours',
                      onRefresh: _reload,
                      stats: [
                        DriverHeaderStat(
                          icon: Icons.luggage_outlined,
                          value: '${activities.length}',
                          label: 'Bookings',
                        ),
                        DriverHeaderStat(
                          icon: Icons.navigation_outlined,
                          value: '$activeCount',
                          label: 'Active',
                        ),
                        DriverHeaderStat(
                          icon: Icons.check_circle_outline_rounded,
                          value: '$doneCount',
                          label: 'Completed',
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    if (doneCount > 0) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.payments_outlined,
                              color: Color(0xFF64748B),
                              size: 15,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Completed tour value: '
                                '${NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0).format(totalCompletedAmount)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: _ActivitySectionHeader(
                        total: activities.length,
                        visible: visible.length,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: _DriverActivityFilterRow(
                        value: _filter,
                        onChanged: (value) {
                          setState(() {
                            _filter = value;
                          });
                        },
                      ),
                    ),

                    const SizedBox(height: 18),

                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: _DriverActivityEmpty(
                          filter: _filter,
                          hasAnyActivity: activities.isNotEmpty,
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Column(
                          children: visible
                              .map(
                                (activity) => Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _DriverActivityCard(
                                    activity: activity,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// FILTER ENUM
// =============================================================================

enum _DriverActivityFilter { all, active, done }

// =============================================================================
// HEADER
// =============================================================================

// =============================================================================
// SECTION HEADER
// =============================================================================

class _ActivitySectionHeader extends StatelessWidget {
  const _ActivitySectionHeader({required this.total, required this.visible});

  final int total;
  final int visible;

  @override
  Widget build(BuildContext context) {
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
            Icons.format_list_bulleted_rounded,
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
                'Tour History',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: -0.2,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                total == 0
                    ? 'Accepted tours will appear here'
                    : 'Showing $visible of $total tour${total == 1 ? '' : 's'}',

                style: const TextStyle(
                  color: Color(0xFF8A98AB),
                  fontWeight: FontWeight.w600,
                  fontSize: 10.8,
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
// FILTER ROW
// =============================================================================

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
      (_DriverActivityFilter.all, 'All', Icons.apps_rounded),
      (_DriverActivityFilter.active, 'Active', Icons.navigation_outlined),
      (
        _DriverActivityFilter.done,
        'Completed',
        Icons.check_circle_outline_rounded,
      ),
    ];

    return SizedBox(
      height: 41,

      child: ListView.separated(
        scrollDirection: Axis.horizontal,

        physics: const BouncingScrollPhysics(),

        itemCount: items.length,

        separatorBuilder: (_, _) => const SizedBox(width: 8),

        itemBuilder: (context, index) {
          final item = items[index];

          final selected = item.$1 == value;

          return Material(
            color: Colors.transparent,

            child: InkWell(
              onTap: () => onChanged(item.$1),

              borderRadius: BorderRadius.circular(999),

              child: AnimatedContainer(
                duration: const Duration(milliseconds: 170),

                curve: Curves.easeOut,

                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 9,
                ),

                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [Color(0xFF4FA7FF), Color(0xFF2F7EFF)],
                        )
                      : null,

                  color: selected ? null : Colors.white,

                  borderRadius: BorderRadius.circular(999),

                  border: Border.all(
                    color: selected
                        ? Colors.transparent
                        : const Color(0xFFE1E8F2),
                  ),

                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF2F7EFF,
                            ).withValues(alpha: 0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : null,
                ),

                child: Row(
                  mainAxisSize: MainAxisSize.min,

                  children: [
                    Icon(
                      item.$3,
                      color: selected ? Colors.white : const Color(0xFF667085),
                      size: 15,
                    ),

                    const SizedBox(width: 6),

                    Text(
                      item.$2,

                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : const Color(0xFF475569),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// ACTIVITY CARD
// =============================================================================

class _DriverActivityCard extends StatelessWidget {
  const _DriverActivityCard({required this.activity});

  final PackageActivity activity;

  bool get _isActive => activity.isActiveLifecycle;

  @override
  Widget build(BuildContext context) {
    final package = activity.packageRow;

    final booking = activity.bookingRow;

    final tourist = activity.touristRow;

    final packageTitle = dbString(package?['title'], fallback: 'Tour Package');

    final city = dbString(package?['city']);

    final municipality = dbString(booking?['municipality']);

    final province = dbString(booking?['province'], fallback: 'Bulacan');

    final location = municipality.isNotEmpty
        ? '$municipality, $province'
        : city;

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

    final touristCount = booking?['total_passengers'] is num
        ? (booking!['total_passengers'] as num).toInt()
        : null;

    return Material(
      color: Colors.transparent,

      child: InkWell(
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
            children: [
              // -------------------------------------------------------------
              // HEADER
              // -------------------------------------------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),

                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Container(
                      width: 46,
                      height: 46,

                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF3FF),

                        borderRadius: BorderRadius.circular(14),
                      ),

                      child: const Icon(
                        Icons.tour_outlined,
                        color: Color(0xFF2F7EFF),
                        size: 22,
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
                              height: 1.18,
                              letterSpacing: -0.2,
                            ),
                          ),

                          if (location.isNotEmpty) ...[
                            const SizedBox(height: 5),

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
                                    location,

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
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    _DriverStatusChip(status: activity.lifecycleStatus),
                  ],
                ),
              ),

              // -------------------------------------------------------------
              // QUICK INFO
              // -------------------------------------------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),

                child: Row(
                  children: [
                    Expanded(
                      child: _ActivityQuickMetric(
                        icon: Icons.calendar_month_outlined,
                        value: travelDate == null
                            ? 'Pending'
                            : DateFormat('MMM d').format(travelDate),
                        label: 'Date',
                      ),
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: _ActivityQuickMetric(
                        icon: Icons.person_outline_rounded,
                        value: touristCount == null ? '1' : '$touristCount',
                        label: 'Tourists',
                      ),
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: _ActivityQuickMetric(
                        icon: Icons.payments_outlined,
                        value: '₱${totalAmount.toStringAsFixed(0)}',
                        label: 'Amount',
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                height: 1,
                color: const Color(0xFFEDF1F6),
              ),

              // -------------------------------------------------------------
              // DETAILS
              // -------------------------------------------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),

                child: Column(
                  children: [
                    _DriverActivityLine(
                      icon: Icons.person_outline_rounded,
                      label: 'Tourist',
                      value: touristName.isEmpty ? 'Tourist' : touristName,
                    ),

                    const SizedBox(height: 10),

                    _DriverActivityLine(
                      icon: Icons.calendar_today_outlined,
                      label: 'Tour date',
                      value: travelDate == null
                          ? 'Date pending'
                          : DateFormat('MMM d, yyyy').format(travelDate),
                    ),

                    const SizedBox(height: 10),

                    _DriverActivityLine(
                      icon: Icons.payments_outlined,
                      label: 'Amount',
                      value: NumberFormat.currency(
                        symbol: 'PHP ',
                        decimalDigits: 0,
                      ).format(totalAmount),
                    ),

                    const SizedBox(height: 10),

                    _DriverActivityLine(
                      icon: Icons.timeline_rounded,
                      label: 'Progress',
                      value: _titleCase(bookingStatus.replaceAll('_', ' ')),
                    ),

                    if (_isActive) ...[
                      const SizedBox(height: 14),

                      Container(
                        width: double.infinity,

                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),

                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F6FF),

                          borderRadius: BorderRadius.circular(13),
                        ),

                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,

                          children: [
                            Icon(
                              Icons.navigation_rounded,
                              color: Color(0xFF2F7EFF),
                              size: 16,
                            ),

                            SizedBox(width: 6),

                            Text(
                              'Open Live Tracking',
                              style: TextStyle(
                                color: Color(0xFF2F7EFF),
                                fontWeight: FontWeight.w900,
                                fontSize: 11.5,
                              ),
                            ),

                            SizedBox(width: 3),

                            Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFF2F7EFF),
                              size: 17,
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

  static String _titleCase(String value) {
    return value
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

// =============================================================================
// QUICK METRIC
// =============================================================================

class _ActivityQuickMetric extends StatelessWidget {
  const _ActivityQuickMetric({
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
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),

      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),

        borderRadius: BorderRadius.circular(13),

        border: Border.all(color: const Color(0xFFE9EEF5)),
      ),

      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF2F7EFF), size: 16),

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
              fontSize: 8.8,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ACTIVITY DETAIL LINE
// =============================================================================

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
      crossAxisAlignment: CrossAxisAlignment.center,

      children: [
        Container(
          width: 32,
          height: 32,

          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),

            borderRadius: BorderRadius.circular(10),
          ),

          child: Icon(icon, size: 15, color: const Color(0xFF2F7EFF)),
        ),

        const SizedBox(width: 9),

        SizedBox(
          width: 72,

          child: Text(
            label,

            style: const TextStyle(
              color: Color(0xFF8A98AB),
              fontWeight: FontWeight.w600,
              fontSize: 10.2,
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
              fontSize: 11.3,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// STATUS CHIP
// =============================================================================

class _DriverStatusChip extends StatelessWidget {
  const _DriverStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();

    final (label, foreground, background, icon) = switch (normalized) {
      'accepted' => (
        'Active',
        const Color(0xFF2563EB),
        const Color(0xFFEEF5FF),
        Icons.navigation_outlined,
      ),

      'ongoing' => (
        'Ongoing',
        const Color(0xFF0284C7),
        const Color(0xFFEAF8FF),
        Icons.route_outlined,
      ),

      'completed' => (
        'Completed',
        const Color(0xFF15803D),
        const Color(0xFFECFDF3),
        Icons.check_circle_outline_rounded,
      ),

      'cancelled' => (
        'Cancelled',
        const Color(0xFFDC2626),
        const Color(0xFFFEF2F2),
        Icons.cancel_outlined,
      ),

      _ => (
        status.replaceAll('_', ' '),
        const Color(0xFF64748B),
        const Color(0xFFF1F5F9),
        Icons.info_outline_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),

      decoration: BoxDecoration(
        color: background,

        borderRadius: BorderRadius.circular(999),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(icon, size: 11, color: foreground),

          const SizedBox(width: 4),

          Text(
            label,

            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w900,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// EMPTY STATE
// =============================================================================

class _DriverActivityEmpty extends StatelessWidget {
  const _DriverActivityEmpty({
    required this.filter,
    required this.hasAnyActivity,
  });

  final _DriverActivityFilter filter;
  final bool hasAnyActivity;

  @override
  Widget build(BuildContext context) {
    final filteredEmpty = hasAnyActivity && filter != _DriverActivityFilter.all;

    String title;
    String subtitle;
    IconData icon;

    if (filteredEmpty) {
      switch (filter) {
        case _DriverActivityFilter.active:
          title = 'No active tours';
          subtitle = 'Tours you are currently handling will appear here.';
          icon = Icons.navigation_outlined;
          break;

        case _DriverActivityFilter.done:
          title = 'No completed tours yet';
          subtitle = 'Finished package tours will be saved here automatically.';
          icon = Icons.check_circle_outline_rounded;
          break;

        case _DriverActivityFilter.all:
          title = 'No activity yet';
          subtitle = 'Accepted and completed tours will appear here.';
          icon = Icons.route_outlined;
      }
    } else {
      title = 'Your tour history starts here';

      subtitle =
          'Once you accept package assignments, you can track active tours and review completed trips from this page.';

      icon = Icons.route_outlined;
    }

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.fromLTRB(26, 32, 26, 30),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(24),

        border: Border.all(color: const Color(0xFFE5ECF5)),

        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 22,
            offset: const Offset(0, 9),
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

            child: Icon(icon, color: const Color(0xFF2F7EFF), size: 31),
          ),

          const SizedBox(height: 18),

          Text(
            title,

            textAlign: TextAlign.center,

            style: const TextStyle(
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
              subtitle,

              textAlign: TextAlign.center,

              style: const TextStyle(
                color: Color(0xFF718096),
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),

          if (!filteredEmpty) ...[
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

              decoration: BoxDecoration(
                color: const Color(0xFFF4F8FF),

                borderRadius: BorderRadius.circular(999),
              ),

              child: const Row(
                mainAxisSize: MainAxisSize.min,

                children: [
                  Icon(Icons.sync_rounded, color: Color(0xFF2F7EFF), size: 14),

                  SizedBox(width: 6),

                  Text(
                    'Activity updates automatically',
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
        ],
      ),
    );
  }
}

// =============================================================================
// LOADING
// =============================================================================

class _DriverActivityLoading extends StatelessWidget {
  const _DriverActivityLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6F8FC),

      child: Column(
        children: [
          const DriverPageHeader(
            icon: Icons.history_rounded,
            title: 'Activity',
            subtitle: 'Track your accepted and completed tours',
            stats: [
              DriverHeaderStat(
                icon: Icons.luggage_outlined,
                value: '...',
                label: 'Bookings',
              ),
              DriverHeaderStat(
                icon: Icons.navigation_outlined,
                value: '...',
                label: 'Active',
              ),
              DriverHeaderStat(
                icon: Icons.check_circle_outline_rounded,
                value: '...',
                label: 'Completed',
              ),
            ],
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
// ERROR
// =============================================================================

class _DriverActivityError extends StatelessWidget {
  const _DriverActivityError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),

      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(22),

            child: Container(
              width: double.infinity,

              constraints: const BoxConstraints(maxWidth: 420),

              padding: const EdgeInsets.all(24),

              decoration: BoxDecoration(
                color: Colors.white,

                borderRadius: BorderRadius.circular(24),

                border: Border.all(color: const Color(0xFFE5ECF5)),

                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                    blurRadius: 22,
                    offset: const Offset(0, 9),
                  ),
                ],
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
                      color: Color(0xFFDC2626),
                      size: 29,
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'Unable to load activity',
                    textAlign: TextAlign.center,

                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),

                  const SizedBox(height: 7),

                  Text(
                    message,

                    textAlign: TextAlign.center,

                    style: const TextStyle(
                      color: Color(0xFF718096),
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
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
        ),
      ),
    );
  }
}
