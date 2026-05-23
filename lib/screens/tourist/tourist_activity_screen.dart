import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/tourist/tourist_activity_tracking_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_tourist.dart';
import 'package:touristrike/components/tourist/ai_chatbot_floating_widget.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _repo = TourisTrikeRepository();
  final _supabase = Supabase.instance.client;
  late Future<_ActivityPayload> _future;
  _StatusFilter _filter = _StatusFilter.all;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<_ActivityPayload> _loadData() async {
    final activities = await _repo.fetchTouristActivities();
    final driverInfos = await _repo.fetchDriverInfos(
      activities.map((activity) => activity.driverId),
    );
    return _ActivityPayload(activities: activities, driverInfos: driverInfos);
  }

  void _reload() => setState(() => _future = _loadData());

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('tourist-activity:${_repo.currentUserId}')
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
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'booking_drivers',
          callback: (_) => _reload(),
        )
        .subscribe();
  }

  List<PackageActivity> _filtered(List<PackageActivity> list) {
    if (_filter == _StatusFilter.all) return list;
    return list
        .where((a) {
          final status = a.lifecycleStatus;
          return switch (_filter) {
            _StatusFilter.all => true,
            _StatusFilter.pending => status == 'pending',
            _StatusFilter.active => status == 'accepted' || status == 'ongoing',
            _StatusFilter.completed => status == 'completed',
            _StatusFilter.cancelled => status == 'cancelled',
          };
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return TouristAiChatbotWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        bottomNavigationBar: const SafeArea(
          top: false,
          child: SizedBox(height: 86, child: AppBottomNav(selectedIndex: 3)),
        ),
        body: SafeArea(
          child: FutureBuilder<_ActivityPayload>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF2A86FF)),
                );
              }
              if (snap.hasError) {
                return _ErrorState(
                  message: snap.error.toString(),
                  onRetry: _reload,
                );
              }

              final payload = snap.data ?? const _ActivityPayload();
              final all = payload.activities;
              final shown = _filtered(all);

              // Summary stats
              final totalSpent = all
                  .where(
                    (a) =>
                        a.lifecycleStatus != 'cancelled' &&
                        a.paymentStatus == 'paid',
                  )
                  .fold<double>(
                    0,
                    (s, a) =>
                        s +
                        dbDouble(
                          a.bookingRow?['total_amount'],
                          fallback: a.price,
                        ),
                  );
              final activeCount = all.where((a) => a.isActiveLifecycle).length;

              return RefreshIndicator(
                onRefresh: () async => _reload(),
                color: const Color(0xFF2A86FF),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                      children: [
                    // ── Header ─────────────────────────────────
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Center(
                        child: Text(
                          'Activity',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Summary cards ──────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            title: 'Bookings',
                            value: '${all.length}',
                            icon: Icons.card_travel_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            title: 'Active',
                            value: '$activeCount',
                            icon: Icons.directions_car_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            title: 'Spent',
                            value: NumberFormat.compactCurrency(
                              symbol: '₱',
                              decimalDigits: 0,
                            ).format(totalSpent),
                            icon: Icons.payments_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // ── Filter tabs ─────────────────────────────
                    _FilterRow(
                      value: _filter,
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                    const SizedBox(height: 14),

                    // ── Activity cards ─────────────────────────
                    if (shown.isEmpty)
                      const _EmptyState()
                    else
                      ...shown.map(
                        (a) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ActivityCard(
                            activity: a,
                            driverInfo: payload.driverInfos[a.driverId],
                          ),
                        ),
                      ),
                  ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _StatusFilter { all, pending, active, completed, cancelled }

// ── Activity card ──────────────────────────────────────────────
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity, this.driverInfo});

  final PackageActivity activity;
  final DriverInfo? driverInfo;

  @override
  Widget build(BuildContext context) {
    final pkg = activity.packageRow;
    final booking = activity.bookingRow;
    final driver = activity.driverRow;

    final packageTitle = dbString(pkg?['title'], fallback: 'Tour Package');
    final municipality = dbString(booking?['municipality']);
    final province = dbString(booking?['province'], fallback: 'Bulacan');
    final areaLabel = municipality.isNotEmpty
        ? '$municipality, $province'
        : dbString(pkg?['city']);
    final imageUrl = dbString(
      pkg?['cover_image_url'],
      fallback: dbString(pkg?['image_url']),
    );

    DateTime? travelDate;
    if (booking?['travel_date'] != null) {
      travelDate = DateTime.tryParse(booking!['travel_date'].toString());
    }
    final dateStr = travelDate == null
        ? '—'
        : DateFormat('MMM d, yyyy').format(travelDate);

    final driverName = driverInfo?.name.isNotEmpty == true
        ? driverInfo!.name
        : dbString(
            driver?['full_name'],
            fallback: [
              dbString(driver?['first_name']),
              dbString(driver?['last_name']),
            ].where((s) => s.isNotEmpty).join(' '),
          );
    final driverPhone = driverInfo?.phoneNumber ?? dbString(driver?['mobile']);
    final vehicleInfo = driverInfo?.vehicleDetails ?? '';
    final bookingAmount = dbDouble(
      booking?['total_amount'],
      fallback: activity.price,
    );

    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    return InkWell(
      onTap: () {
        if (activity.bookingId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ActivityTrackingScreen(bookingId: activity.bookingId),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE7EEF7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: image + title + status
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: imageUrl.isEmpty
                        ? Container(
                            color: const Color(0xFFEAF2FF),
                            child: const Icon(
                              Icons.map_rounded,
                              color: Color(0xFF2A86FF),
                            ),
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: const Color(0xFFEAF2FF),
                              child: const Icon(
                                Icons.map_rounded,
                                color: Color(0xFF2A86FF),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              packageTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          _BookingStatusChip(status: activity.lifecycleStatus),
                        ],
                      ),
                      if (areaLabel.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 13,
                              color: Color(0xFF64748B),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              areaLabel,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _InfoPill(
                            icon: Icons.calendar_today_rounded,
                            text: dateStr,
                          ),
                          const SizedBox(width: 6),
                          _InfoPill(
                            icon: Icons.payments_outlined,
                            text: money.format(bookingAmount),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Group booking waiting indicator
            Builder(
              builder: (context) {
                final required =
                    (booking?['required_drivers'] as num?)?.toInt() ?? 1;
                final accepted =
                    (booking?['accepted_drivers_count'] as num?)?.toInt() ?? 0;
                if (required <= 1) return const SizedBox.shrink();
                final isWaiting =
                    activity.lifecycleStatus == 'pending' ||
                    activity.lifecycleStatus == 'accepted';
                if (!isWaiting) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _GroupDriversBar(
                    accepted: accepted,
                    required: required,
                  ),
                );
              },
            ),

            // Divider
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(color: Color(0xFFE7EEF7), height: 1),
            ),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.directions_car_rounded,
                  size: 15,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: driverName.isEmpty
                      ? const Text(
                          'No driver assigned',
                          style: TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Driver: $driverName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                            if (driverPhone.isNotEmpty)
                              Text(
                                'Contact: $driverPhone',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            if (vehicleInfo.isNotEmpty)
                              Text(
                                'Vehicle: $vehicleInfo',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                ),
                _PaymentStatusChip(status: activity.paymentStatus),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityPayload {
  const _ActivityPayload({
    this.activities = const [],
    this.driverInfos = const {},
  });

  final List<PackageActivity> activities;
  final Map<String, DriverInfo> driverInfos;
}

// ── Chips ──────────────────────────────────────────────────────
class _BookingStatusChip extends StatelessWidget {
  const _BookingStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status.toLowerCase()) {
      'pending' => ('PENDING', const Color(0xFFF59E0B)),
      'accepted' => ('ACCEPTED', const Color(0xFF2A86FF)),
      'ongoing' => ('ONGOING', const Color(0xFF0EA5E9)),
      'completed' => ('COMPLETED', const Color(0xFF16A34A)),
      'cancelled' => ('CANCELLED', const Color(0xFFDC2626)),
      _ => (status.toUpperCase(), const Color(0xFF64748B)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _PaymentStatusChip extends StatelessWidget {
  const _PaymentStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status.toLowerCase()) {
      'paid' => ('PAID', const Color(0xFF16A34A)),
      'refunded' => ('REFUNDED', const Color(0xFF0EA5E9)),
      _ => ('UNPAID', const Color(0xFFF59E0B)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ── Filter row ─────────────────────────────────────────────────
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.value, required this.onChanged});

  final _StatusFilter value;
  final ValueChanged<_StatusFilter> onChanged;

  static const _items = [
    (_StatusFilter.all, 'All'),
    (_StatusFilter.pending, 'Pending'),
    (_StatusFilter.active, 'Active'),
    (_StatusFilter.completed, 'Done'),
    (_StatusFilter.cancelled, 'Cancelled'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _items.map((item) {
          final (filter, label) = item;
          final selected = filter == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF2A86FF) : Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: const Color(0xFFE7EEF7)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Stat card ──────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
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
            child: Icon(icon, color: const Color(0xFF2A86FF), size: 18),
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
            title,
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

// ── Info pill ──────────────────────────────────────────────────
class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF64748B)),
          const SizedBox(width: 4),
          Text(
            text,
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

// ── Empty state ─────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.card_travel_rounded,
              color: Color(0xFF2A86FF),
              size: 32,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No activity found',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Book a tour package to see your activity here.',
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

// ── Group drivers bar ──────────────────────────────────────────
class _GroupDriversBar extends StatelessWidget {
  const _GroupDriversBar({required this.accepted, required this.required});

  final int accepted;
  final int required;

  @override
  Widget build(BuildContext context) {
    final allConfirmed = accepted >= required;
    final fg = allConfirmed ? const Color(0xFF16A34A) : const Color(0xFF92400E);
    final bg = allConfirmed ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED);
    final border = allConfirmed
        ? const Color(0xFF86EFAC)
        : const Color(0xFFFED7AA);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            allConfirmed
                ? Icons.check_circle_rounded
                : Icons.pending_actions_rounded,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              allConfirmed
                  ? 'All $required drivers confirmed'
                  : 'Waiting for drivers ($accepted / $required)',
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          if (!allConfirmed) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: required > 0 ? accepted / required : 0,
                  backgroundColor: const Color(0xFFFED7AA),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFF59E0B)),
                  minHeight: 5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Error state ────────────────────────────────────────────────
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
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
