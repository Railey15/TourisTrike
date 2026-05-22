import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  List<_PaymentHistoryItem> _items = const [];
  RealtimeChannel? _paymentsChannel;
  RealtimeChannel? _walletTransactionsChannel;

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
    _walletTransactionsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = _user?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _items = const [];
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final results = await Future.wait([
        _supabase
            .from('payments')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false),
        _supabase
            .from('wallet_transactions')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false),
      ]);

      final paymentItems = (results[0] as List<dynamic>)
          .map(
            (row) => _PaymentHistoryItem.fromPayment(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
      final walletItems = (results[1] as List<dynamic>)
          .map(
            (row) => _PaymentHistoryItem.fromWalletTransaction(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();

      final items = [...paymentItems, ...walletItems]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

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
    _walletTransactionsChannel?.unsubscribe();

    _paymentsChannel = _supabase
        .channel('tourist_payments_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _loadData(),
        )
        .subscribe();

    _walletTransactionsChannel = _supabase
        .channel('tourist_wallet_transactions_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallet_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
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

  double get _totalAmount {
    return _items
        .where((item) => item.isSuccessful)
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
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _TopCircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Payment History',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: blue,
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                  children: [
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
                            child: const Icon(
                              Icons.payments_rounded,
                              color: blue,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Successful Total',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: textMid,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'PHP ${_totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: textDark,
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
                          child: _TransactionCard(item: item),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentHistoryItem {
  const _PaymentHistoryItem({
    required this.id,
    required this.source,
    required this.amount,
    required this.method,
    required this.status,
    required this.type,
    required this.reference,
    required this.description,
    required this.createdAt,
    required this.paidAt,
  });

  factory _PaymentHistoryItem.fromPayment(Map<String, dynamic> map) {
    return _PaymentHistoryItem(
      id: (map['id'] ?? '').toString(),
      source: 'payment',
      amount: _toDouble(map['amount']),
      method: (map['payment_method'] ?? 'Unknown').toString(),
      status: (map['payment_status'] ?? map['status'] ?? 'pending').toString(),
      type: (map['payment_type'] ?? 'payment').toString(),
      reference: (map['payment_reference'] ?? map['reference_key'] ?? '')
          .toString(),
      description: (map['description'] ?? 'Tour or booking payment').toString(),
      createdAt: _toDateTime(map['created_at']),
      paidAt: _toDateTime(map['paid_at']),
    );
  }

  factory _PaymentHistoryItem.fromWalletTransaction(Map<String, dynamic> map) {
    final type = (map['type'] ?? 'wallet').toString();
    return _PaymentHistoryItem(
      id: (map['id'] ?? '').toString(),
      source: 'wallet',
      amount: _toDouble(map['amount']),
      method: (map['payment_method'] ?? 'wallet').toString(),
      status: (map['status'] ?? 'pending').toString(),
      type: type,
      reference: (map['reference_key'] ?? map['paymongo_reference_id'] ?? '')
          .toString(),
      description: _walletDescription(type, map['metadata']),
      createdAt: _toDateTime(map['created_at']),
      paidAt: _toDateTime(map['updated_at']),
    );
  }

  final String id;
  final String source;
  final double amount;
  final String method;
  final String status;
  final String type;
  final String reference;
  final String description;
  final DateTime createdAt;
  final DateTime? paidAt;

  bool get isSuccessful {
    final normalized = status.trim().toLowerCase();
    return normalized == 'paid' ||
        normalized == 'completed' ||
        normalized == 'fully_paid' ||
        normalized == 'dp_paid';
  }

  String get createdLabel =>
      DateFormat.yMMMd().add_jm().format(createdAt.toLocal());

  String get paidLabel {
    if (paidAt == null) return 'Not paid yet';
    return DateFormat.yMMMd().add_jm().format(paidAt!.toLocal());
  }

  String get statusLabel => status.replaceAll('_', ' ').toUpperCase();

  String get title {
    final sourceLabel = source == 'wallet' ? 'Wallet' : 'Payment';
    return '$sourceLabel ${type.replaceAll('_', ' ')}';
  }

  static DateTime _toDateTime(dynamic value) {
    return DateTime.tryParse((value ?? '').toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  static String _walletDescription(String type, dynamic metadata) {
    if (metadata is Map && metadata['description'] != null) {
      return metadata['description'].toString();
    }
    switch (type.toLowerCase()) {
      case 'cash_in':
        return 'Wallet cash-in';
      case 'package_payment':
        return 'Wallet package payment';
      case 'driver_earning':
        return 'Driver earning credit';
      case 'withdrawal':
        return 'Wallet withdrawal';
      case 'refund':
        return 'Wallet refund';
      default:
        return 'Wallet transaction';
    }
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.item});

  final _PaymentHistoryItem item;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const green = Color(0xFF16A34A);
    const red = Color(0xFFDC2626);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    final statusColor = item.isSuccessful ? green : red;

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
                      item.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textMid,
                        fontSize: 12.5,
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
                    item.statusLabel,
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
          _DetailRow(label: 'Method', value: item.method),
          _DetailRow(label: 'Type', value: item.type.replaceAll('_', ' ')),
          _DetailRow(
            label: 'Reference',
            value: item.reference.trim().isEmpty ? 'N/A' : item.reference,
          ),
          _DetailRow(label: 'Created', value: item.createdLabel),
          _DetailRow(label: 'Paid', value: item.paidLabel),
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
            width: 74,
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

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: const Color(0xFF0F172A)),
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
