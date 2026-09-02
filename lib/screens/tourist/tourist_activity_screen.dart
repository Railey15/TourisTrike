import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/tourist/booking_cancellation_result_screen.dart';
import 'package:touristrike/screens/tourist/tourist_activity_tracking_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_tourist.dart';
import 'package:touristrike/widgets/package_booking_cancellation_flow.dart';
import 'package:touristrike/components/tourist/ai_chatbot_floating_widget.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with WidgetsBindingObserver {
  final _repo = TourisTrikeRepository();
  final _supabase = Supabase.instance.client;

  late Future<_ActivityPayload> _future;

  _StatusFilter _filter = _StatusFilter.all;
  RealtimeChannel? _channel;

  static const String _forcedRole = String.fromEnvironment(
    'FORCE_ROLE',
    defaultValue: '',
  );

  bool get _isTouristPreview => _forcedRole.trim().toLowerCase() == 'tourist';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _loadData();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reload();
    }
  }

  Future<_ActivityPayload> _loadData() async {
    final user = _supabase.auth.currentUser;

    // Allows UI preview in Chrome using:
    // --dart-define=FORCE_ROLE=tourist
    if (user == null && _isTouristPreview) {
      debugPrint(
        'ACTIVITY preview: no authenticated user. '
        'Showing empty preview state.',
      );

      return const _ActivityPayload();
    }

    if (user == null) {
      throw StateError('Please sign in to view your activity.');
    }

    final activities = await _repo.fetchTouristActivities();

    final driverInfos = await _repo.fetchDriverInfos(
      activities.map((activity) => activity.driverId),
    );

    return _ActivityPayload(activities: activities, driverInfos: driverInfos);
  }

  Future<void> _reload() async {
    if (!mounted) return;

    final next = _loadData();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _cancelFromCard(PackageActivity activity) async {
    if (activity.bookingId.isEmpty) return;
    final booking = activity.bookingRow;
    final packageTitle = dbString(
      activity.packageRow?['title'],
      fallback: 'Tour Package',
    );
    final travelDate = dbDate(booking?['travel_date']);
    final result = await showPackageBookingCancellationFlow(
      context,
      bookingId: activity.bookingId,
      packageTitle: packageTitle,
      travelDate: travelDate,
      repository: _repo,
    );
    if (result == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookingCancellationResultScreen(
          result: result,
          packageTitle: packageTitle,
          travelDate: travelDate,
        ),
      ),
    );
    _reload();
  }

  void _subscribeRealtime() {
    final user = _supabase.auth.currentUser;

    // Do not subscribe during unauthenticated web preview.
    if (user == null) {
      debugPrint(
        'ACTIVITY realtime skipped: no authenticated Supabase session.',
      );
      return;
    }

    _channel = _supabase
        .channel('tourist-activity:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'package_bookings',
          callback: (_) => _reload(),
        )
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
        .where((activity) {
          final status = activity.lifecycleStatus;

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
        backgroundColor: const Color(0xFFF6F8FC),
        bottomNavigationBar: const SafeArea(
          top: false,
          child: SizedBox(height: 86, child: AppBottomNav(selectedIndex: 3)),
        ),
        body: SafeArea(
          bottom: false,
          child: FutureBuilder<_ActivityPayload>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _ActivityLoadingState();
              }

              if (snapshot.hasError) {
                return _ErrorState(
                  message: snapshot.error.toString(),
                  onRetry: _reload,
                );
              }

              final payload = snapshot.data ?? const _ActivityPayload();

              final all = payload.activities;
              final shown = _filtered(all);

              final totalSpent = all
                  .where(
                    (activity) =>
                        activity.lifecycleStatus != 'cancelled' &&
                        activity.paymentStatus == 'paid',
                  )
                  .fold<double>(
                    0,
                    (sum, activity) =>
                        sum +
                        dbDouble(
                          activity.bookingRow?['total_amount'],
                          fallback: activity.price,
                        ),
                  );

              final activeCount = all
                  .where((activity) => activity.isActiveLifecycle)
                  .length;

              return RefreshIndicator(
                onRefresh: () async {
                  await _reload();
                },
                color: const Color(0xFF2A86FF),
                backgroundColor: Colors.white,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
                      children: [
                        const _ActivityHeader(),

                        const SizedBox(height: 22),

                        _ActivitySummary(
                          bookings: all.length,
                          active: activeCount,
                          totalSpent: totalSpent,
                        ),

                        const SizedBox(height: 24),

                        const Text(
                          'Your Trips',
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          all.isEmpty
                              ? 'Your bookings and trip progress will appear here.'
                              : '${all.length} ${all.length == 1 ? 'booking' : 'bookings'} in your activity',
                          style: const TextStyle(
                            color: Color(0xFF7C8BA1),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 14),

                        _FilterRow(
                          value: _filter,
                          onChanged: (value) {
                            setState(() {
                              _filter = value;
                            });
                          },
                        ),

                        const SizedBox(height: 20),

                        if (shown.isEmpty)
                          _EmptyState(
                            filter: _filter,
                            hasAnyActivity: all.isNotEmpty,
                          )
                        else
                          ...shown.map(
                            (activity) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _ActivityCard(
                                activity: activity,
                                driverInfo:
                                    payload.driverInfos[activity.driverId],
                                onCancel: () => _cancelFromCard(activity),
                                onReturn: _reload,
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

// ─────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(2, 8, 2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.7,
              height: 1.05,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Track your bookings, trips and travel history.',
            style: TextStyle(
              color: Color(0xFF7C8BA1),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SUMMARY
// ─────────────────────────────────────────────────────────────

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({
    required this.bookings,
    required this.active,
    required this.totalSpent,
  });

  final int bookings;
  final int active;
  final double totalSpent;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.compactCurrency(
      symbol: '₱',
      decimalDigits: 0,
    ).format(totalSpent);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE6EDF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.055),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF5AAEFF), Color(0xFF2A86FF)],
                  ),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2A86FF).withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.route_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Travel Overview',
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Your TourisTrike activity at a glance',
                      style: TextStyle(
                        color: Color(0xFF8795AA),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.luggage_outlined,
                  value: '$bookings',
                  label: 'Bookings',
                ),
              ),
              const _SummaryDivider(),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.local_taxi_outlined,
                  value: '$active',
                  label: 'Active',
                ),
              ),
              const _SummaryDivider(),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.account_balance_wallet_outlined,
                  value: money,
                  label: 'Spent',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
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
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF2A86FF), size: 18),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF7C8BA1),
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: const Color(0xFFE9EEF6),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FILTERS
// ─────────────────────────────────────────────────────────────

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
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (filter, label) = _items[index];
          final selected = filter == value;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onChanged(filter),
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [Color(0xFF4DA5FF), Color(0xFF2A86FF)],
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
                              0xFF2A86FF,
                            ).withValues(alpha: 0.20),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF475569),
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ACTIVITY CARD
// ─────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.activity,
    this.driverInfo,
    this.onCancel,
    this.onReturn,
  });

  final PackageActivity activity;
  final DriverInfo? driverInfo;
  final VoidCallback? onCancel;
  final Future<void> Function()? onReturn;

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
        ? 'Date not set'
        : DateFormat('MMM d, yyyy').format(travelDate);

    final driverName = driverInfo?.name.isNotEmpty == true
        ? driverInfo!.name
        : dbString(
            driver?['full_name'],
            fallback: [
              dbString(driver?['first_name']),
              dbString(driver?['last_name']),
            ].where((value) => value.isNotEmpty).join(' '),
          );

    final driverPhone = driverInfo?.phoneNumber ?? dbString(driver?['mobile']);

    final vehicleInfo = driverInfo?.vehicleDetails ?? '';

    final bookingAmount = dbDouble(
      booking?['total_amount'],
      fallback: activity.price,
    );

    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (activity.bookingId.isEmpty) return;

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ActivityTrackingScreen(bookingId: activity.bookingId),
            ),
          );
          await onReturn?.call();
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE5ECF5)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.055),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PackageThumbnail(imageUrl: imageUrl),

                    const SizedBox(width: 13),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
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
                              ),
                              const SizedBox(width: 8),
                              _BookingStatusChip(
                                status: activity.lifecycleStatus,
                              ),
                              if ((activity.lifecycleStatus == 'pending' ||
                                      activity.lifecycleStatus == 'accepted') &&
                                  activity.tourStatus != 'driver_arrived' &&
                                  onCancel != null) ...[
                                const SizedBox(width: 2),
                                PopupMenuButton<String>(
                                  tooltip: 'Manage booking',
                                  padding: EdgeInsets.zero,
                                  onSelected: (_) => onCancel!(),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem<String>(
                                      value: 'cancel',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.event_busy_outlined,
                                            size: 19,
                                            color: Color(0xFFDC2626),
                                          ),
                                          SizedBox(width: 8),
                                          Text('Cancel Booking'),
                                        ],
                                      ),
                                    ),
                                  ],
                                  child: const Padding(
                                    padding: EdgeInsets.all(5),
                                    child: Icon(
                                      Icons.more_vert_rounded,
                                      size: 20,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),

                          if (areaLabel.isNotEmpty) ...[
                            const SizedBox(height: 7),
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
                                    areaLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF718096),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 10),

                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _InfoPill(
                                icon: Icons.calendar_month_outlined,
                                text: dateStr,
                              ),
                              _InfoPill(
                                icon: Icons.account_balance_wallet_outlined,
                                text: money.format(bookingAmount),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Builder(
                builder: (context) {
                  final required =
                      (booking?['required_drivers'] as num?)?.toInt() ?? 1;

                  final accepted =
                      (booking?['accepted_drivers_count'] as num?)?.toInt() ??
                      0;

                  if (required <= 1) {
                    return const SizedBox.shrink();
                  }

                  final isWaiting =
                      activity.lifecycleStatus == 'pending' ||
                      activity.lifecycleStatus == 'accepted';

                  if (!isWaiting) {
                    return const SizedBox.shrink();
                  }

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
                    child: _GroupDriversBar(
                      accepted: accepted,
                      required: required,
                    ),
                  );
                },
              ),

              Container(
                margin: const EdgeInsets.symmetric(horizontal: 13),
                height: 1,
                color: const Color(0xFFEDF1F6),
              ),

              if (activity.lifecycleStatus == 'cancelled')
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 13, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dbString(
                            booking?['cancelled_reason'],
                            fallback: 'Booking cancelled',
                          ),
                          style: const TextStyle(
                            color: Color(0xFF991B1B),
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (dbDate(booking?['cancelled_at']) != null)
                              DateFormat(
                                'MMM d, yyyy • h:mm a',
                              ).format(dbDate(booking?['cancelled_at'])!),
                            if (dbDouble(booking?['refundable_amount']) > 0)
                              '${money.format(dbDouble(booking?['refundable_amount']))} refund ${dbString(booking?['refund_status'], fallback: 'pending')}',
                            if (dbDouble(booking?['refundable_amount']) <= 0)
                              'No refundable amount',
                          ].join('  •  '),
                          style: const TextStyle(
                            color: Color(0xFF7F1D1D),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F6FF),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.local_taxi_outlined,
                        color: Color(0xFF2A86FF),
                        size: 19,
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: driverName.isEmpty
                          ? const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Driver assignment',
                                  style: TextStyle(
                                    color: Color(0xFF8795AA),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Waiting for a driver',
                                  style: TextStyle(
                                    color: Color(0xFF475569),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Your driver',
                                  style: TextStyle(
                                    color: Color(0xFF8795AA),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  driverName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF111827),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                  ),
                                ),
                                if (vehicleInfo.isNotEmpty ||
                                    driverPhone.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (vehicleInfo.isNotEmpty) vehicleInfo,
                                      if (driverPhone.isNotEmpty) driverPhone,
                                    ].join(' • '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF718096),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),

                    const SizedBox(width: 8),

                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _PaymentStatusChip(status: activity.paymentStatus),
                        const SizedBox(height: 7),
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View trip',
                              style: TextStyle(
                                color: Color(0xFF2A86FF),
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFF2A86FF),
                              size: 17,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackageThumbnail extends StatelessWidget {
  const _PackageThumbnail({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: SizedBox(
        width: 82,
        height: 92,
        child: imageUrl.isEmpty
            ? const _PackageImageFallback()
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) {
                  return const _PackageImageFallback();
                },
              ),
      ),
    );
  }
}

class _PackageImageFallback extends StatelessWidget {
  const _PackageImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF3FF),
      child: const Center(
        child: Icon(
          Icons.landscape_outlined,
          color: Color(0xFF2A86FF),
          size: 28,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STATUS CHIPS
// ─────────────────────────────────────────────────────────────

class _BookingStatusChip extends StatelessWidget {
  const _BookingStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color, background) = switch (status.toLowerCase()) {
      'pending' => (
        'Pending',
        const Color(0xFFD97706),
        const Color(0xFFFFF7E8),
      ),
      'accepted' => (
        'Accepted',
        const Color(0xFF2563EB),
        const Color(0xFFEEF5FF),
      ),
      'ongoing' => (
        'Ongoing',
        const Color(0xFF0284C7),
        const Color(0xFFEAF8FF),
      ),
      'completed' => (
        'Completed',
        const Color(0xFF15803D),
        const Color(0xFFECFDF3),
      ),
      'cancelled' => (
        'Cancelled',
        const Color(0xFFDC2626),
        const Color(0xFFFEF2F2),
      ),
      _ => (status, const Color(0xFF64748B), const Color(0xFFF1F5F9)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 9.5,
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
    final (label, color, background) = switch (status.toLowerCase()) {
      'paid' => ('Paid', const Color(0xFF15803D), const Color(0xFFECFDF3)),
      'refunded' => (
        'Refunded',
        const Color(0xFF0284C7),
        const Color(0xFFEAF8FF),
      ),
      _ => ('Unpaid', const Color(0xFFD97706), const Color(0xFFFFF7E8)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 9.5,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// INFO PILL
// ─────────────────────────────────────────────────────────────

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FA),
        borderRadius: BorderRadius.circular(999),
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
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// GROUP DRIVER STATUS
// ─────────────────────────────────────────────────────────────

class _GroupDriversBar extends StatelessWidget {
  const _GroupDriversBar({required this.accepted, required this.required});

  final int accepted;
  final int required;

  @override
  Widget build(BuildContext context) {
    final allConfirmed = accepted >= required;

    final foreground = allConfirmed
        ? const Color(0xFF15803D)
        : const Color(0xFFB45309);

    final background = allConfirmed
        ? const Color(0xFFECFDF3)
        : const Color(0xFFFFF8EB);

    final border = allConfirmed
        ? const Color(0xFFBBF7D0)
        : const Color(0xFFFDE6B5);

    final progress = required > 0 ? (accepted / required).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                allConfirmed
                    ? Icons.check_circle_outline_rounded
                    : Icons.groups_2_outlined,
                size: 17,
                color: foreground,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  allConfirmed
                      ? 'All $required drivers confirmed'
                      : 'Driver assignment $accepted of $required',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              if (!allConfirmed)
                Text(
                  '$accepted/$required',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
            ],
          ),

          if (!allConfirmed) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: const Color(0xFFFDE7BC),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFF59E0B)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.hasAnyActivity});

  final _StatusFilter filter;
  final bool hasAnyActivity;

  @override
  Widget build(BuildContext context) {
    final isFiltered = hasAnyActivity && filter != _StatusFilter.all;

    final title = isFiltered
        ? 'Nothing here yet'
        : 'Your adventures start here';

    final subtitle = isFiltered
        ? 'You don\'t have any bookings with this status.'
        : 'Once you book a TourisTrike package, you can track its progress and trip details here.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 34, 28, 34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE5ECF5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCEBFF),
                    shape: BoxShape.circle,
                  ),
                ),
                const Icon(
                  Icons.luggage_outlined,
                  color: Color(0xFF2A86FF),
                  size: 31,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

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
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF718096),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),

          if (!isFiltered) ...[
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
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFF2A86FF),
                    size: 15,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Your trips will be organized automatically',
                    style: TextStyle(
                      color: Color(0xFF4F6B8D),
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

// ─────────────────────────────────────────────────────────────
// LOADING STATE
// ─────────────────────────────────────────────────────────────

class _ActivityLoadingState extends StatelessWidget {
  const _ActivityLoadingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),

              const Text(
                'Activity',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.7,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'Loading your travel activity...',
                style: TextStyle(
                  color: Color(0xFF7C8BA1),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 28),

              Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFE6EDF7)),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      color: Color(0xFF2A86FF),
                      strokeWidth: 3,
                    ),
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

// ─────────────────────────────────────────────────────────────
// ERROR STATE
// ─────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFE5ECF5)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
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
                    size: 30,
                  ),
                ),

                const SizedBox(height: 17),

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
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                    label: const Text('Try Again'),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFF2A86FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PAYLOAD
// ─────────────────────────────────────────────────────────────

class _ActivityPayload {
  const _ActivityPayload({
    this.activities = const [],
    this.driverInfos = const {},
  });

  final List<PackageActivity> activities;
  final Map<String, DriverInfo> driverInfos;
}
