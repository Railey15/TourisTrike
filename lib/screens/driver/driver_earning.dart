import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/screens/driver/driver_trips.dart';
import 'package:touristrike/widgets/app_bottom_nav_driver.dart';

class DriverEarningScreen extends StatefulWidget {
  const DriverEarningScreen({
    super.key,
    required this.onBottomNavTap,
    this.dailyGoalAmount = 120,
  });

  /// Reuse your existing navigation handler from parent/root screen
  final ValueChanged<int> onBottomNavTap;

  /// UI goal only.
  /// Tour/earning values are all realtime from database.
  final double dailyGoalAmount;

  @override
  State<DriverEarningScreen> createState() => _DriverEarningScreenState();
}

class _DriverEarningScreenState extends State<DriverEarningScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  Stream<List<DriverRide>> _ridesStream(String driverId) {
    return _supabase
        .from('rides')
        .stream(primaryKey: ['id'])
        .eq('driver_id', driverId)
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map((row) => DriverRide.fromMap(row))
              .where((ride) => ride.isCompleted)
              .toList(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No authenticated driver found. Please sign in again.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: StreamBuilder<List<DriverRide>>(
          stream: _ridesStream(user.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorState(
                message: 'Failed to load earnings.\n${snapshot.error}',
                onRetry: () => setState(() {}),
              );
            }

            if (!snapshot.hasData) {
              return const _LoadingState();
            }

            final rides = snapshot.data ?? [];
            final summary = DriverEarningSummary.fromRides(
              rides: rides,
              dailyGoalAmount: widget.dailyGoalAmount,
            );

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: _HeaderSection(
                      driverName:
                          user.userMetadata?['full_name']?.toString() ??
                          user.userMetadata?['name']?.toString() ??
                          'Driver',
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _TodayEarningsCard(summary: summary),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.account_balance_wallet_rounded,
                            iconBg: const Color(0xFFEAF2FF),
                            label: 'TOTAL',
                            value: _currency(summary.totalEarnings),
                            subtitle: 'Total earnings',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.radio_button_unchecked_rounded,
                            iconBg: const Color(0xFFF6F1FF),
                            label: 'COUNT',
                            value: '${summary.completedTrips}',
                            subtitle: 'Completed tours',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                    child: Row(
                      children: [
                        Text(
                          'Recent Tours',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1C2430),
                              ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF2FF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Today',
                            style: TextStyle(
                              color: Color(0xFF2F6FFF),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => DriverTripsScreen(
                                  onBottomNavTap: widget.onBottomNavTap,
                                ),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF2F6FFF),
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'View All',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (summary.todayTrips.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 120),
                      child: _EmptyTripsCard(),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    sliver: SliverList.separated(
                      itemCount: summary.todayTrips.length,
                      itemBuilder: (context, index) {
                        final ride = summary.todayTrips[index];
                        return _TripTile(ride: ride);
                      },
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                    ),
                  ),
              ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNavDriver(
        currentIndex: 3,
        onTap: widget.onBottomNavTap,
      ),
    );
  }

  static String _currency(num value) {
    return NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: value % 1 == 0 ? 0 : 2,
    ).format(value);
  }
}

class DriverRide {
  final String id;
  final String? touristId;
  final String? driverId;
  final String pickupName;
  final double pickupLat;
  final double pickupLng;
  final String dropoffName;
  final double dropoffLat;
  final double dropoffLng;
  final double distanceKm;
  final double fareAmount;
  final String paymentMethod;
  final String status;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final double? driverLat;
  final double? driverLng;
  final DateTime? driverLastSeen;

  DriverRide({
    required this.id,
    required this.touristId,
    required this.driverId,
    required this.pickupName,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffName,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.distanceKm,
    required this.fareAmount,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
    required this.completedAt,
    required this.driverLat,
    required this.driverLng,
    required this.driverLastSeen,
  });

  factory DriverRide.fromMap(Map<String, dynamic> map) {
    return DriverRide(
      id: map['id'].toString(),
      touristId: map['tourist_id']?.toString(),
      driverId: map['driver_id']?.toString(),
      pickupName: (map['pickup_name'] ?? '').toString(),
      pickupLat: _toDouble(map['pickup_lat']),
      pickupLng: _toDouble(map['pickup_lng']),
      dropoffName: (map['dropoff_name'] ?? '').toString(),
      dropoffLat: _toDouble(map['dropoff_lat']),
      dropoffLng: _toDouble(map['dropoff_lng']),
      distanceKm: _toDouble(map['distance_km']),
      fareAmount: _toDouble(map['fare_amount']),
      paymentMethod: (map['payment_method'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      createdAt: _toDateTime(map['created_at']),
      completedAt: _toDateTime(map['completed_at']),
      driverLat: map['driver_lat'] == null
          ? null
          : _toDouble(map['driver_lat']),
      driverLng: map['driver_lng'] == null
          ? null
          : _toDouble(map['driver_lng']),
      driverLastSeen: _toDateTime(map['driver_last_seen']),
    );
  }

  bool get isCompleted {
    final normalized = status.trim().toLowerCase();
    return completedAt != null ||
        normalized == 'completed' ||
        normalized == 'complete' ||
        normalized == 'finished' ||
        normalized == 'done';
  }

  DateTime? get effectiveCompletedTime => completedAt ?? createdAt;

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

class DriverEarningSummary {
  final double todayEarnings;
  final double totalEarnings;
  final int completedTrips;
  final int todayTripCount;
  final double dailyGoalAmount;
  final List<DriverRide> todayTrips;
  final double progress;

  DriverEarningSummary({
    required this.todayEarnings,
    required this.totalEarnings,
    required this.completedTrips,
    required this.todayTripCount,
    required this.dailyGoalAmount,
    required this.todayTrips,
    required this.progress,
  });

  factory DriverEarningSummary.fromRides({
    required List<DriverRide> rides,
    required double dailyGoalAmount,
  }) {
    final now = DateTime.now();

    final todayRides = rides.where((ride) {
      final completedTime = ride.effectiveCompletedTime;
      if (completedTime == null) return false;
      return completedTime.year == now.year &&
          completedTime.month == now.month &&
          completedTime.day == now.day;
    }).toList();

    final totalEarnings = rides.fold<double>(
      0,
      (sum, ride) => sum + ride.fareAmount,
    );

    final todayEarnings = todayRides.fold<double>(
      0,
      (sum, ride) => sum + ride.fareAmount,
    );

    final safeGoal = dailyGoalAmount <= 0 ? 1 : dailyGoalAmount;
    final progress = (todayEarnings / safeGoal).clamp(0, 1).toDouble();

    return DriverEarningSummary(
      todayEarnings: todayEarnings,
      totalEarnings: totalEarnings,
      completedTrips: rides.length,
      todayTripCount: todayRides.length,
      dailyGoalAmount: dailyGoalAmount,
      todayTrips: todayRides,
      progress: progress,
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.driverName});

  final String driverName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(21),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Center(
                child: Icon(
                  Icons.person_rounded,
                  size: 24,
                  color: Color(0xFF64748B),
                ),
              ),
              Positioned(
                right: 1,
                bottom: 1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                driverName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              const Row(
                children: [
                  Icon(Icons.circle, size: 8, color: Color(0xFF22C55E)),
                  SizedBox(width: 6),
                  Text(
                    'Online Now',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TodayEarningsCard extends StatelessWidget {
  const _TodayEarningsCard({required this.summary});

  final DriverEarningSummary summary;

  @override
  Widget build(BuildContext context) {
    final remaining = (summary.dailyGoalAmount - summary.todayEarnings).clamp(
      0,
      double.infinity,
    );
    final percent = (summary.progress * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF3A82FF), Color(0xFF2F6FFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F6FFF).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "TODAY'S EARNINGS",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  NumberFormat.currency(
                    locale: 'en_PH',
                    symbol: '₱',
                    decimalDigits: summary.todayEarnings % 1 == 0 ? 0 : 2,
                  ).format(summary.todayEarnings),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Text(
                  summary.todayEarnings <= 0 ? '0%' : '+$percent%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF235FDC).withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Daily Goal Progress',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '${_money(summary.todayEarnings)} / ${_money(summary.dailyGoalAmount)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: summary.progress,
                    minHeight: 10,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF7FF0A5),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  remaining <= 0
                      ? 'Nice work! You already reached your goal today.'
                      : 'Keep it up! Just ${_money(remaining)} more to reach your goal.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.90),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _money(num value) {
    return NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: value % 1 == 0 ? 0 : 2,
    ).format(value);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconBg;
  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF0F2F6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 15, color: const Color(0xFF2F6FFF)),
              ),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFB0B9C6),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 31 * 0.65,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF7B8794),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripTile extends StatelessWidget {
  const _TripTile({required this.ride});

  final DriverRide ride;

  @override
  Widget build(BuildContext context) {
    final completedTime = ride.effectiveCompletedTime;
    final timeText = completedTime == null
        ? '--:--'
        : DateFormat('hh:mm a').format(completedTime);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF1F3F7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Column(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFFD8DEE8),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 1.2,
                  height: 32,
                  color: const Color(0xFFE5EAF1),
                ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F6FFF),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride.pickupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9AA5B1),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ride.dropoffName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 22 * 0.78,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 13,
                          color: Color(0xFF2F6FFF),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeText,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 13,
                          color: Color(0xFF16A34A),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Completed',
                          style: TextStyle(
                            color: Color(0xFF16A34A),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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
              Text(
                NumberFormat.currency(
                  locale: 'en_PH',
                  symbol: '₱',
                  decimalDigits: ride.fareAmount % 1 == 0 ? 0 : 2,
                ).format(ride.fareAmount),
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${ride.distanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyTripsCard extends StatelessWidget {
  const _EmptyTripsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F3F7)),
      ),
      child: const Column(
        children: [
          Icon(Icons.route_rounded, size: 38, color: Color(0xFF2F6FFF)),
          SizedBox(height: 12),
          Text(
            'No completed tours today yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Completed tour assignments will appear here automatically in realtime.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF7B8794),
              fontSize: 13,
              fontWeight: FontWeight.w500,
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
    return const Center(child: CircularProgressIndicator());
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
            const Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF344054),
                fontWeight: FontWeight.w600,
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
