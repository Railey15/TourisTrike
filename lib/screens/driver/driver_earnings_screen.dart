import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/shared/acknowledgement_receipt_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_driver.dart';
import 'package:touristrike/widgets/driver_page_header.dart';

// TourisTrike does NOT custody funds — GCash-to-GCash direct.
// Outside AMLA covered-person scope (RA 9160).
//
// This screen is a read-only transaction record.
// Actual money goes directly to the driver's GCash account.
class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  final TourisTrikeRepository _repo = TourisTrikeRepository();

  bool _loading = true;

  List<PaymentRecord> _records = const [];
  List<PaymentAllocation> _allocations = const [];
  List<PackageActivity> _activities = const [];
  RealtimeChannel? _earningsChannel;

  @override
  void initState() {
    super.initState();

    _load();
    final driverId = Supabase.instance.client.auth.currentUser?.id;
    if (driverId != null) {
      _earningsChannel = Supabase.instance.client
          .channel('driver-earnings:$driverId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'payment_allocations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'driver_id',
              value: driverId,
            ),
            callback: (_) => _load(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'payment_records',
            callback: (_) => _load(),
          )
          .subscribe();
    }
  }

  @override
  void dispose() {
    _earningsChannel?.unsubscribe();
    super.dispose();
  }

  // ===========================================================================
  // LOAD
  // ===========================================================================

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final results = await Future.wait([
        _repo.fetchPaymentRecords(role: 'payee', limit: 200),
        _repo.fetchConfirmedDriverPaymentAllocations(limit: 200),
        _repo.fetchDriverActivities(),
      ]);

      if (!mounted) return;

      setState(() {
        _records = results[0] as List<PaymentRecord>;
        _allocations = results[1] as List<PaymentAllocation>;
        _activities = results[2] as List<PackageActivity>;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('DriverEarningsScreen load failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            content: const Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 19,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Unable to load your earnings right now.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  // ===========================================================================
  // COMPUTED VALUES
  // ===========================================================================

  double get _totalEarned {
    final directPayments = _records
        .where((record) => record.isConfirmed)
        .fold<double>(0, (sum, record) => sum + record.amount);
    final packageShares = _allocations.fold<double>(
      0,
      (sum, allocation) => sum + allocation.driverAmount,
    );
    return directPayments + packageShares;
  }

  int get _activeCount {
    return _activities
        .where(
          (activity) =>
              activity.lifecycleStatus == 'accepted' ||
              activity.lifecycleStatus == 'ongoing',
        )
        .length;
  }

  int get _completedCount {
    return _activities
        .where((activity) => activity.lifecycleStatus == 'completed')
        .length;
  }

  int get _confirmedCount {
    return _records.where((record) => record.isConfirmed).length +
        _allocations.length;
  }

  int get _pendingCount {
    return _records.where((record) {
      final status = record.status.toLowerCase();

      return status != 'confirmed' &&
          status != 'disputed' &&
          status != 'cancelled';
    }).length;
  }

  double get _todayEarnings {
    final now = DateTime.now();

    final directPayments = _records
        .where((record) {
          if (!record.isConfirmed || record.createdAt == null) {
            return false;
          }

          final date = record.createdAt!.toLocal();

          return date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
        })
        .fold<double>(0, (sum, record) => sum + record.amount);
    final packageShares = _allocations
        .where((allocation) {
          final date = allocation.confirmedAt?.toLocal();
          return date != null &&
              date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
        })
        .fold<double>(0, (sum, allocation) => sum + allocation.driverAmount);
    return directPayments + packageShares;
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),

      bottomNavigationBar: const AppBottomNavDriver(currentIndex: 3),

      body: RefreshIndicator(
        color: const Color(0xFF2F7EFF),
        backgroundColor: Colors.white,
        onRefresh: _load,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.only(bottom: 30),
              children: [
                _buildEarningsHeader(),

                const SizedBox(height: 18),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: _EarningsRecordNotice(),
                ),

                const SizedBox(height: 20),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _PerformanceOverview(
                    activeTours: _activeCount,
                    completedTours: _completedCount,
                    confirmedPayments: _confirmedCount,
                    pendingPayments: _pendingCount,
                  ),
                ),

                const SizedBox(height: 24),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _TransactionSectionHeader(
                    count: _records.length + _allocations.length,
                  ),
                ),

                const SizedBox(height: 12),

                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: _EarningsLoadingState(),
                  )
                else if (_records.isEmpty && _allocations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: _EmptyTransactionsState(),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      children: [
                        ..._allocations.map(
                          (allocation) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _AllocationEarningTile(
                              allocation: allocation,
                            ),
                          ),
                        ),
                        ..._records.map(
                          (record) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _EarningTile(record: record),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEarningsHeader() {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return DriverPageHeader(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Earnings',
      subtitle: 'Your confirmed payment records',
      action: const DriverHeaderBadge(
        icon: Icons.verified_user_outlined,
        label: 'RECORDED',
      ),
      stats: [
        DriverHeaderStat(
          icon: Icons.account_balance_wallet_outlined,
          value: money.format(_totalEarned),
          label: 'Total Recorded',
        ),
        DriverHeaderStat(
          icon: Icons.today_outlined,
          value: money.format(_todayEarnings),
          label: 'Today',
        ),
        DriverHeaderStat(
          icon: Icons.check_circle_outline_rounded,
          value: '$_confirmedCount',
          label: 'Confirmed',
        ),
      ],
    );
  }
}

// =============================================================================
// HEADER
// =============================================================================

class _EarningsRecordNotice extends StatelessWidget {
  const _EarningsRecordNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8E7FB)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF2F7EFF), size: 17),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Confirmed package shares appear here as earnings. Transfer and '
              'payout status are tracked separately.',
              style: TextStyle(
                color: Color(0xFF57739A),
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PERFORMANCE OVERVIEW
// =============================================================================

class _PerformanceOverview extends StatelessWidget {
  const _PerformanceOverview({
    required this.activeTours,
    required this.completedTours,
    required this.confirmedPayments,
    required this.pendingPayments,
  });

  final int activeTours;
  final int completedTours;
  final int confirmedPayments;
  final int pendingPayments;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.insights_outlined,
          title: 'Earnings Overview',
          subtitle: 'Your tour and payment activity',
        ),

        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
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
          child: Row(
            children: [
              Expanded(
                child: _OverviewMetric(
                  icon: Icons.navigation_outlined,
                  value: '$activeTours',
                  label: 'Active Tours',
                ),
              ),

              const _OverviewDivider(),

              Expanded(
                child: _OverviewMetric(
                  icon: Icons.check_circle_outline_rounded,
                  value: '$completedTours',
                  label: 'Completed',
                ),
              ),

              const _OverviewDivider(),

              Expanded(
                child: _OverviewMetric(
                  icon: Icons.payments_outlined,
                  value: '$confirmedPayments',
                  label: 'Confirmed',
                ),
              ),
            ],
          ),
        ),

        if (pendingPayments > 0) ...[
          const SizedBox(height: 10),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF7D9A3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFFB45309),
                  size: 17,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    '$pendingPayments payment${pendingPayments == 1 ? '' : 's'} '
                    'still waiting for confirmation.',
                    style: const TextStyle(
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w700,
                      fontSize: 10.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
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
          style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),

        const SizedBox(height: 2),

        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF8795A8),
            fontWeight: FontWeight.w600,
            fontSize: 9.5,
          ),
        ),
      ],
    );
  }
}

class _OverviewDivider extends StatelessWidget {
  const _OverviewDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 52, color: const Color(0xFFE9EEF5));
  }
}

// =============================================================================
// SECTION TITLE
// =============================================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
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
          width: 37,
          height: 37,
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
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: -0.2,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                subtitle,
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
// TRANSACTION SECTION
// =============================================================================

class _TransactionSectionHeader extends StatelessWidget {
  const _TransactionSectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: _SectionTitle(
            icon: Icons.receipt_long_outlined,
            title: 'Transaction History',
            subtitle: 'Recorded direct payment activity',
          ),
        ),

        if (count > 0)
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
                fontSize: 10,
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// TRANSACTION TILE
// =============================================================================

class _AllocationEarningTile extends StatelessWidget {
  const _AllocationEarningTile({required this.allocation});

  final PaymentAllocation allocation;

  @override
  Widget build(BuildContext context) {
    final paidAt = allocation.confirmedAt?.toLocal();
    final dateLabel = paidAt == null
        ? '-'
        : DateFormat('MMM d, yyyy • h:mm a').format(paidAt);
    final stage = _titleCase(allocation.paymentStage.replaceAll('_', ' '));

    return Container(
      padding: const EdgeInsets.all(14),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.payments_outlined,
              color: Color(0xFF2F7EFF),
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Package $stage',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$dateLabel • PayMongo GCash',
                  style: const TextStyle(
                    color: Color(0xFF8A98AB),
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Booking ${_shortId(allocation.bookingId)}',
                  style: const TextStyle(
                    color: Color(0xFF8A98AB),
                    fontWeight: FontWeight.w600,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${allocation.driverAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF3),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'CONFIRMED',
                  style: TextStyle(
                    color: Color(0xFF15803D),
                    fontWeight: FontWeight.w900,
                    fontSize: 8.8,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _shortId(String value) {
    return value.length <= 8 ? value : value.substring(0, 8);
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

class _EarningTile extends StatelessWidget {
  const _EarningTile({required this.record});

  final PaymentRecord record;

  @override
  Widget build(BuildContext context) {
    final status = record.status.toLowerCase();

    final (statusLabel, statusColor, statusBg, statusIcon) = switch (status) {
      'confirmed' => (
        'Confirmed',
        const Color(0xFF15803D),
        const Color(0xFFECFDF3),
        Icons.check_circle_outline_rounded,
      ),
      'disputed' => (
        'Disputed',
        const Color(0xFFDC2626),
        const Color(0xFFFEF2F2),
        Icons.report_problem_outlined,
      ),
      'cancelled' => (
        'Cancelled',
        const Color(0xFF64748B),
        const Color(0xFFF1F5F9),
        Icons.cancel_outlined,
      ),
      _ => (
        'Pending',
        const Color(0xFFB45309),
        const Color(0xFFFFF7E8),
        Icons.schedule_rounded,
      ),
    };

    final dateLabel = record.createdAt != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(record.createdAt!.toLocal())
        : '-';

    final title = record.serviceDescription.isEmpty
        ? _titleCase(record.paymentStage.replaceAll('_', ' '))
        : record.serviceDescription;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: record.isConfirmed
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AcknowledgementReceiptScreen(record: record),
                  ),
                );
              }
            : null,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(14),
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
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      color: Color(0xFF2F7EFF),
                      size: 20,
                    ),
                  ),

                  const SizedBox(width: 11),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                            height: 1.25,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          dateLabel,
                          style: const TextStyle(
                            color: Color(0xFF8A98AB),
                            fontWeight: FontWeight.w600,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₱${record.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, color: statusColor, size: 11),

                            const SizedBox(width: 4),

                            Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 8.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              if (record.isConfirmed) ...[
                const SizedBox(height: 12),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F8FF),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_outlined,
                        color: Color(0xFF2F7EFF),
                        size: 15,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'View Acknowledgement Receipt',
                        style: TextStyle(
                          color: Color(0xFF2F7EFF),
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF2F7EFF),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ],
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
// EMPTY STATE
// =============================================================================

class _EmptyTransactionsState extends StatelessWidget {
  const _EmptyTransactionsState();

  @override
  Widget build(BuildContext context) {
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
            child: const Icon(
              Icons.receipt_long_outlined,
              color: Color(0xFF2F7EFF),
              size: 31,
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            'No earnings recorded yet',
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
            constraints: BoxConstraints(maxWidth: 310),
            child: Text(
              'Confirmed payments from completed or active tour bookings will appear here as a record.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF718096),
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),

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
                  Icons.account_balance_wallet_outlined,
                  color: Color(0xFF2F7EFF),
                  size: 14,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Actual funds go directly to your GCash',
                    style: TextStyle(
                      color: Color(0xFF57739A),
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
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
}

// =============================================================================
// LOADING STATE
// =============================================================================

class _EarningsLoadingState extends StatelessWidget {
  const _EarningsLoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5ECF5)),
      ),
      child: const Column(
        children: [
          SizedBox(
            width: 29,
            height: 29,
            child: CircularProgressIndicator(
              color: Color(0xFF2F7EFF),
              strokeWidth: 3,
            ),
          ),

          SizedBox(height: 12),

          Text(
            'Loading transaction history...',
            style: TextStyle(
              color: Color(0xFF718096),
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
