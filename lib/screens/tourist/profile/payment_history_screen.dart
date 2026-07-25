import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/shared/acknowledgement_receipt_screen.dart';
import 'package:touristrike/screens/shared/payment_dispute_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_tourist.dart';

// TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TourisTrikeRepository _repo = TourisTrikeRepository();

  bool _loading = true;
  List<PaymentRecord> _items = const [];
  RealtimeChannel? _paymentsChannel;

  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _paymentsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = _user?.id;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (mounted) setState(() => _loading = true);

    try {
      final items = await _repo.fetchPaymentRecords(role: 'payer', limit: 200);
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
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
  }

  double get _totalPaid {
    return _items
        .where((item) => item.isConfirmed)
        .fold<double>(0, (sum, item) => sum + item.amount);
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: const SafeArea(
        top: false,
        child: SizedBox(height: 86, child: AppBottomNav(selectedIndex: 2)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: blue,
          onRefresh: _loadData,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Center(
                  child: Text(
                    'Payment History',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE7EEF7)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.payments_rounded, color: blue),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Paid (confirmed)',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: textMid,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'PHP ${_totalPaid.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Informational only — not a wallet balance.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: textMid,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_items.length} entries',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textMid,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Transactions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: textDark,
                ),
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(color: blue),
                  ),
                )
              else if (_items.isEmpty)
                const _EmptyState()
              else
                ..._items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TransactionCard(
                      item: item,
                      onViewReceipt: item.isConfirmed
                          ? () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    AcknowledgementReceiptScreen(record: item),
                              ),
                            )
                          : null,
                      onReportProblem: item.status == 'cancelled'
                          ? null
                          : () => Navigator.of(context)
                                .push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PaymentDisputeScreen(record: item),
                                  ),
                                )
                                .then((_) => _loadData()),
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

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.item,
    this.onViewReceipt,
    this.onReportProblem,
  });

  final PaymentRecord item;
  final VoidCallback? onViewReceipt;
  final VoidCallback? onReportProblem;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const green = Color(0xFF16A34A);
    const amber = Color(0xFFB45309);
    const red = Color(0xFFDC2626);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    final statusColor = item.status == 'confirmed'
        ? green
        : item.status == 'disputed'
        ? red
        : item.status == 'cancelled'
        ? textMid
        : amber;

    final createdLabel = item.createdAt != null
        ? DateFormat.yMMMd().add_jm().format(item.createdAt!.toLocal())
        : '-';
    final paidLabel = item.payeeConfirmedAt != null
        ? DateFormat.yMMMd().add_jm().format(item.payeeConfirmedAt!.toLocal())
        : 'Not confirmed yet';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.receipt_long_rounded, color: blue, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.serviceDescription.isEmpty
                          ? item.paymentStage.replaceAll('_', ' ')
                          : item.serviceDescription,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'PHP ${item.amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: blue,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DetailRow(label: 'Method', value: item.paymentMethod.toUpperCase()),
          if (item.externalReferenceNo.isNotEmpty)
            _DetailRow(label: 'Reference', value: item.externalReferenceNo),
          _DetailRow(label: 'Submitted', value: createdLabel),
          _DetailRow(label: 'Confirmed', value: paidLabel),
          if (onViewReceipt != null || onReportProblem != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (onReportProblem != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReportProblem,
                      style: OutlinedButton.styleFrom(foregroundColor: red),
                      child: const Text('Report a Problem'),
                    ),
                  ),
                if (onReportProblem != null && onViewReceipt != null)
                  const SizedBox(width: 8),
                if (onViewReceipt != null)
                  Expanded(
                    child: FilledButton(
                      onPressed: onViewReceipt,
                      style: FilledButton.styleFrom(backgroundColor: blue),
                      child: const Text('View Receipt'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w800,
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
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),
        child: Text(
          'No payments yet.',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}
