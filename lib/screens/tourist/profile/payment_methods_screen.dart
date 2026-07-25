import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  int _selectedIndex = 0;
  List<_PaymentMethodViewModel> _methods = const [];

  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final userId = _user?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _methods = _buildStaticMethods(const <String, _MethodUsage>{});
          _loading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final rows = await _supabase
          .from('payment_records')
          .select('payment_method, created_at')
          .eq('payer_id', userId);

      final usage = <String, _MethodUsage>{};

      for (final row in rows as List<dynamic>) {
        final map = Map<String, dynamic>.from(row as Map);
        final method = (map['payment_method'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (method.isEmpty) continue;
        final createdAt = DateTime.tryParse(
          (map['created_at'] ?? '').toString(),
        );
        final current = usage[method];
        usage[method] = _MethodUsage(
          count: (current?.count ?? 0) + 1,
          lastUsedAt: _latestDate(current?.lastUsedAt, createdAt),
        );
      }

      if (!mounted) return;
      setState(() {
        _methods = _buildStaticMethods(usage);
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('PaymentMethodsScreen _loadData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _methods = _buildStaticMethods(const <String, _MethodUsage>{});
        _loading = false;
      });
      _showError('Unable to load payment methods.');
    }
  }

  List<_PaymentMethodViewModel> _buildStaticMethods(
    Map<String, _MethodUsage> usage,
  ) {
    final supported = <_PaymentMethodViewModel>[
      _PaymentMethodViewModel(
        key: 'cash',
        title: 'Cash',
        subtitle: 'Pay directly during your booking',
        icon: Icons.payments_rounded,
        usage: usage['cash'],
      ),
      _PaymentMethodViewModel(
        key: 'gcash',
        title: 'GCash',
        subtitle: 'Mobile wallet payments',
        icon: Icons.account_balance_wallet_rounded,
        usage: usage['gcash'],
      ),
      _PaymentMethodViewModel(
        key: 'maya',
        title: 'Maya',
        subtitle: 'Maya digital wallet payments',
        icon: Icons.wallet_rounded,
        usage: usage['maya'],
      ),
    ];

    supported.sort((a, b) {
      final aUsed = a.usage?.count ?? 0;
      final bUsed = b.usage?.count ?? 0;
      if (aUsed != bUsed) return bUsed.compareTo(aUsed);
      return a.title.compareTo(b.title);
    });
    return supported;
  }

  DateTime? _latestDate(DateTime? first, DateTime? second) {
    if (first == null) return second;
    if (second == null) return first;
    return first.isAfter(second) ? first : second;
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

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

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
                      'Payment Methods',
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
                        border: Border.all(color: line),
                      ),
                      child: const Text(
                        'This screen reflects supported payment methods plus methods found in your payment history. TourisTrike never holds your money — GCash and Maya payments go directly to the driver.',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: textMid,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Available Methods',
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
                    else
                      ..._methods.asMap().entries.map((entry) {
                        final index = entry.key;
                        final method = entry.value;
                        final isSelected = index == _selectedIndex;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTap: () => setState(() => _selectedIndex = index),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: isSelected ? blue : line,
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: 0.045,
                                    ),
                                    blurRadius: 18,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEAF2FF),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(method.icon, color: blue),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                method.title,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: textDark,
                                                ),
                                              ),
                                            ),
                                            if (method.usage != null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFEAF2FF,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  '${method.usage!.count} used',
                                                  style: const TextStyle(
                                                    color: blue,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          method.subtitle,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: textMid,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          method.lastUsedLabel,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: textMid,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: blue,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
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

class _MethodUsage {
  const _MethodUsage({required this.count, required this.lastUsedAt});

  final int count;
  final DateTime? lastUsedAt;
}

class _PaymentMethodViewModel {
  const _PaymentMethodViewModel({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.usage,
  });

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final _MethodUsage? usage;

  String get lastUsedLabel {
    if (usage?.lastUsedAt == null) {
      return 'No recorded usage yet';
    }
    return 'Last used ${DateFormat.yMMMd().add_jm().format(usage!.lastUsedAt!.toLocal())}';
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
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF0F172A)),
      ),
    );
  }
}
