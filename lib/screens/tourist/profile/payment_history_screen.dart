import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/shared/acknowledgement_receipt_screen.dart';
import 'package:touristrike/screens/shared/payment_dispute_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_tourist.dart';

// PayMongo remains the payment processor; TourisTrike does not store card data.
// Outside AMLA covered-person scope (RA 9160).
class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TourisTrikeRepository _repo = TourisTrikeRepository();

  bool _loading = true;
  List<PaymentHistoryEntry> _items = const [];
  RealtimeChannel? _paymentsChannel;
  RealtimeChannel? _refundsChannel;

  User? get _user => _supabase.auth.currentUser;

  static const _bg = Color(0xFFF6F8FC);
  static const _blue = Color(0xFF2563EB);

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _paymentsChannel?.unsubscribe();
    _refundsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = _user?.id;

    if (userId == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final items = await _repo.fetchTouristPaymentHistory(limit: 200);

      if (!mounted) return;

      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('PaymentHistoryScreen _loadData error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() => _loading = false);
      _showError('Unable to load payment history.');
    }
  }

  void _subscribeToRealtime() {
    final userId = _user?.id;
    if (userId == null) return;

    _paymentsChannel?.unsubscribe();

    _paymentsChannel = _supabase
        .channel('tourist_payment_records_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payment_records',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'payer_id',
            value: userId,
          ),
          callback: (_) => _loadData(),
        )
        .subscribe();

    // Refund RLS only exposes rows involving this tourist (including rows
    // linked through the original payment), so the refresh remains scoped.
    _refundsChannel?.unsubscribe();
    _refundsChannel = _supabase
        .channel('tourist_refund_requests_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'refund_requests',
          callback: (_) => _loadData(),
        )
        .subscribe();
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFDC2626),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  double get _totalPaid {
    return _items
        .where((item) => !item.isRefund && item.payment.isConfirmed)
        .fold<double>(0, (sum, item) => sum + item.amount);
  }

  double get _totalRefunded => _items
      .where(
        (item) =>
            item.isRefund &&
            const {
              'completed',
              'refunded',
            }.contains(item.refund!.status.toLowerCase()),
      )
      .fold<double>(0, (sum, item) => sum + item.amount);

  int get _confirmedCount {
    return _items.where((item) {
      if (item.isRefund) {
        return const {
          'completed',
          'refunded',
        }.contains(item.refund!.status.toLowerCase());
      }
      return item.payment.isConfirmed;
    }).length;
  }

  int get _pendingCount {
    return _items.where((item) {
      final status = item.isRefund
          ? item.refund!.status.toLowerCase()
          : item.payment.status.toLowerCase();
      return !const {
        'confirmed',
        'completed',
        'refunded',
        'cancelled',
        'rejected',
        'failed',
        'disputed',
      }.contains(status);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: const SafeArea(
        top: false,
        child: SizedBox(height: 86, child: AppBottomNav(selectedIndex: 2)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: _blue,
          onRefresh: _loadData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            children: [
              const _PageHeader(),

              const SizedBox(height: 20),

              _PaymentSummaryCard(
                totalPaid: _totalPaid,
                totalRefunded: _totalRefunded,
                entryCount: _items.length,
                confirmedCount: _confirmedCount,
                pendingCount: _pendingCount,
              ),

              const SizedBox(height: 28),

              _SectionHeader(count: _items.length),

              const SizedBox(height: 12),

              if (_loading)
                const _LoadingPaymentsState()
              else if (_items.isEmpty)
                const _EmptyState()
              else
                ..._items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TransactionCard(
                      item: item,
                      onViewReceipt: item.isRefund || item.payment.isConfirmed
                          ? () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AcknowledgementReceiptScreen(
                                    record: item.payment,
                                    historyEntry: item,
                                  ),
                                ),
                              );
                            }
                          : null,
                      onReportProblem:
                          item.isRefund || item.payment.status == 'cancelled'
                          ? null
                          : () {
                              Navigator.of(context)
                                  .push(
                                    MaterialPageRoute(
                                      builder: (_) => PaymentDisputeScreen(
                                        record: item.payment,
                                      ),
                                    ),
                                  )
                                  .then((_) => _loadData());
                            },
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

// ============================================================================
// PAGE HEADER
// ============================================================================

class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: 4),
        Text(
          'Payment History',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
            letterSpacing: -0.4,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Review your submitted and confirmed payments',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF98A2B3),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// SUMMARY CARD
// ============================================================================

class _PaymentSummaryCard extends StatelessWidget {
  const _PaymentSummaryCard({
    required this.totalPaid,
    required this.totalRefunded,
    required this.entryCount,
    required this.confirmedCount,
    required this.pendingCount,
  });

  final double totalPaid;
  final double totalRefunded;
  final int entryCount;
  final int confirmedCount;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF8FBFF)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6EDF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF23395D).withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE9F2FF), Color(0xFFDDEBFF)],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Color(0xFF2563EB),
                  size: 24,
                ),
              ),

              const SizedBox(width: 13),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Paid',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Confirmed payments only',
                      style: TextStyle(
                        color: Color(0xFF98A2B3),
                        fontWeight: FontWeight.w500,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F6FC),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '$entryCount ${entryCount == 1 ? 'entry' : 'entries'}',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            'PHP ${totalPaid.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 28,
              height: 1,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              letterSpacing: -0.8,
            ),
          ),

          if (totalRefunded > 0) ...[
            const SizedBox(height: 7),
            Text(
              'Total Refunded: PHP ${totalRefunded.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF16A34A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],

          const SizedBox(height: 7),

          const Text(
            'For your payment records only. This is not a stored wallet balance.',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: Color(0xFF8A97AA),
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 18),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFFEAF0F6)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryStat(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Confirmed',
                    value: confirmedCount.toString(),
                    iconColor: const Color(0xFF16A34A),
                  ),
                ),
                Container(width: 1, height: 31, color: const Color(0xFFE4EAF1)),
                Expanded(
                  child: _SummaryStat(
                    icon: Icons.schedule_rounded,
                    label: 'Pending',
                    value: pendingCount.toString(),
                    iconColor: const Color(0xFFD97706),
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

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 17, color: iconColor),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF98A2B3),
                fontWeight: FontWeight.w500,
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// TRANSACTIONS HEADER
// ============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transactions',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Your latest payment activity',
                style: TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Color(0xFF2563EB),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// TRANSACTION CARD
// ============================================================================

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.item,
    this.onViewReceipt,
    this.onReportProblem,
  });

  final PaymentHistoryEntry item;
  final VoidCallback? onViewReceipt;
  final VoidCallback? onReportProblem;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2563EB);
    const green = Color(0xFF16A34A);
    const amber = Color(0xFFD97706);
    const red = Color(0xFFDC2626);
    const textDark = Color(0xFF111827);
    const textMid = Color(0xFF667085);

    final payment = item.payment;
    final normalizedStatus = item.isRefund
        ? item.refund!.status.toLowerCase()
        : payment.status.toLowerCase();
    final isSuccessful = item.isRefund
        ? const {'completed', 'refunded'}.contains(normalizedStatus)
        : normalizedStatus == 'confirmed';

    final statusColor = isSuccessful
        ? green
        : normalizedStatus == 'disputed'
        ? red
        : normalizedStatus == 'cancelled'
        ? textMid
        : amber;

    final statusBg = isSuccessful
        ? const Color(0xFFECFDF3)
        : normalizedStatus == 'disputed'
        ? const Color(0xFFFEF2F2)
        : normalizedStatus == 'cancelled'
        ? const Color(0xFFF2F4F7)
        : const Color(0xFFFFF7E6);

    final statusIcon = isSuccessful
        ? Icons.check_circle_rounded
        : normalizedStatus == 'disputed'
        ? Icons.report_problem_rounded
        : normalizedStatus == 'cancelled'
        ? Icons.cancel_outlined
        : Icons.schedule_rounded;

    final createdLabel =
        payment.payerSubmittedAt != null || payment.createdAt != null
        ? DateFormat(
            'MMM d, yyyy • h:mm a',
          ).format((payment.payerSubmittedAt ?? payment.createdAt!).toLocal())
        : '-';

    final paidLabel = payment.payeeConfirmedAt != null || payment.paidAt != null
        ? DateFormat(
            'MMM d, yyyy • h:mm a',
          ).format((payment.payeeConfirmedAt ?? payment.paidAt!).toLocal())
        : 'Not confirmed yet';

    final occurredLabel = item.occurredAt == null
        ? '-'
        : DateFormat(
            'MMM d, yyyy • h:mm a',
          ).format(item.occurredAt!.toLocal());
    final providerReference = item.providerReference;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EDF5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF23395D).withValues(alpha: 0.045),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: blue,
                  size: 22,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.22,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      occurredLabel,
                      style: const TextStyle(
                        color: Color(0xFF98A2B3),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
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
                    '${item.amountPrefix} PHP ${item.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: item.isRefund ? green : textDark,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          item.statusLabel.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                            fontSize: 8.8,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEDF1F6)),
            ),
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.map_outlined,
                  label: 'Package',
                  value: item.packageName,
                ),
                _DetailRow(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Transaction',
                  value: item.transactionType,
                ),
                _DetailRow(
                  icon: Icons.payments_outlined,
                  label: 'Amount',
                  value:
                      '${item.amountPrefix} PHP ${item.amount.toStringAsFixed(2)}',
                ),
                if (!item.isRefund &&
                    payment.paymentStage == 'remaining_balance' &&
                    payment.remainingPackageComponent != null &&
                    payment.additionalWaitingComponent != null) ...[
                  _DetailRow(
                    icon: Icons.receipt_outlined,
                    label: 'Remaining Package Balance',
                    value:
                        'PHP ${payment.remainingPackageComponent!.toStringAsFixed(2)}',
                  ),
                  _DetailRow(
                    icon: Icons.timer_outlined,
                    label: 'Additional Waiting Fee',
                    value:
                        'PHP ${payment.additionalWaitingComponent!.toStringAsFixed(2)}',
                  ),
                  _DetailRow(
                    icon: Icons.summarize_outlined,
                    label: 'Total Remaining Amount',
                    value: 'PHP ${payment.amount.toStringAsFixed(2)}',
                  ),
                ],
                _DetailRow(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Booking',
                  value: item.bookingReference,
                ),
                _DetailRow(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Method',
                  value: paymentMethodLabel(payment.paymentMethod),
                ),
                _DetailRow(
                  icon: Icons.info_outline_rounded,
                  label: 'Status',
                  value: item.statusLabel,
                ),
                if (providerReference.isNotEmpty)
                  _DetailRow(
                    icon: Icons.tag_rounded,
                    label: 'Provider Ref.',
                    value: providerReference,
                  ),
                _DetailRow(
                  icon: Icons.schedule_rounded,
                  label: 'Submitted',
                  value: createdLabel,
                ),
                if (item.isRefund) ...[
                  _DetailRow(
                    icon: Icons.link_rounded,
                    label: 'Original',
                    value: item.originalPaymentReference,
                  ),
                  _DetailRow(
                    icon: Icons.notes_rounded,
                    label: 'Reason',
                    value: item.refund!.reason.isEmpty
                        ? 'Not specified'
                        : _toTitleCase(
                            item.refund!.reason.replaceAll('_', ' '),
                          ),
                  ),
                  _DetailRow(
                    icon: Icons.currency_exchange_rounded,
                    label: 'Refunded',
                    value: item.refund!.completedAt == null
                        ? 'Pending'
                        : occurredLabel,
                    isLast: true,
                  ),
                ] else
                  _DetailRow(
                    icon: Icons.verified_outlined,
                    label: 'Confirmed',
                    value: paidLabel,
                    isLast: true,
                  ),
              ],
            ),
          ),

          if (onViewReceipt != null || onReportProblem != null) ...[
            const SizedBox(height: 13),
            Row(
              children: [
                if (onReportProblem != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReportProblem,
                      icon: const Icon(Icons.report_problem_outlined, size: 16),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: red,
                        side: const BorderSide(color: Color(0xFFF3C7C7)),
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                      label: const Text('Report Problem'),
                    ),
                  ),

                if (onReportProblem != null && onViewReceipt != null)
                  const SizedBox(width: 8),

                if (onViewReceipt != null)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onViewReceipt,
                      icon: const Icon(Icons.receipt_rounded, size: 16),
                      style: FilledButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                      label: const Text('View Receipt'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _toTitleCase(String value) {
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

// ============================================================================
// DETAIL ROW
// ============================================================================

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 14, color: const Color(0xFF2563EB)),
          ),

          const SizedBox(width: 10),

          SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontWeight: FontWeight.w600,
                  fontSize: 10.5,
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF344054),
                  fontWeight: FontWeight.w600,
                  fontSize: 10.5,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EMPTY STATE
// ============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 32, 22, 30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EDF5)),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 31,
              color: Color(0xFF2563EB),
            ),
          ),

          const SizedBox(height: 16),

          const Text(
            'No payments yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 6),

          const Text(
            'Your payment records will appear here after you submit a payment for a booking or tour package.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF98A2B3),
              fontWeight: FontWeight.w500,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// LOADING STATE
// ============================================================================

class _LoadingPaymentsState extends StatelessWidget {
  const _LoadingPaymentsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EDF5)),
      ),
      child: const Column(
        children: [
          SizedBox(
            width: 29,
            height: 29,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF2563EB),
            ),
          ),
          SizedBox(height: 13),
          Text(
            'Loading your payments...',
            style: TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
