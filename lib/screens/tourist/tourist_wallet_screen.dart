import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/widgets/app_bottom_nav_tourist.dart';
import 'package:touristrike/components/tourist/ai_chatbot_floating_widget.dart';

class TouristWalletScreen extends StatefulWidget {
  const TouristWalletScreen({super.key, this.initialDeepLink});

  final Uri? initialDeepLink;

  @override
  State<TouristWalletScreen> createState() => _TouristWalletScreenState();
}

class _TouristWalletScreenState extends State<TouristWalletScreen>
    with WidgetsBindingObserver {
  final TourisTrikeRepository _repo = TourisTrikeRepository();
  Wallet? _wallet;
  List<WalletTransaction> _transactions = [];
  bool _loading = true;
  String? _loadError;

  StreamSubscription<Uri>? _walletLinkSubscription;
  RealtimeChannel? _walletChannel;
  RealtimeChannel? _txLiveChannel;

  bool _balanceHidden = false;
  bool _refreshingCheckoutState = false;
  String? _pendingCashInTransactionId;
  String? _lastHandledWalletLink;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadWalletData());
    _subscribeToWalletRealtime();
    _subscribeToTransactionsRealtime();
    _listenForWalletDeepLinks();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialDeepLink = widget.initialDeepLink;
      if (initialDeepLink != null) {
        unawaited(_handleWalletDeepLink(initialDeepLink));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _walletLinkSubscription?.cancel();
    _walletChannel?.unsubscribe();
    _txLiveChannel?.unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_refreshingCheckoutState) {
      if (_pendingCashInTransactionId != null) {
        unawaited(_pollForCheckoutSettlement());
      } else {
        unawaited(_loadWalletData());
      }
    }
  }

  Future<void> _loadWalletData() async {
    if (!mounted) return;
    if (_wallet == null) setState(() { _loading = true; _loadError = null; });
    try {
      final wallet = await _repo.fetchOrCreateWallet(role: 'tourist');
      final transactions = await _repo.fetchWalletTransactions(role: 'tourist');
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _transactions = transactions;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reload() => _loadWalletData();

  void _subscribeToWalletRealtime() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _walletChannel = Supabase.instance.client
        .channel('wallet_balance_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'wallets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (PostgresChangePayload payload) {
            if (!mounted) return;
            final updated =
                Wallet(Map<String, dynamic>.from(payload.newRecord));
            setState(() => _wallet = updated);
          },
        )
        .subscribe();
  }

  void _subscribeToTransactionsRealtime() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _txLiveChannel = Supabase.instance.client
        .channel('wallet_txs_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'wallet_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (PostgresChangePayload payload) {
            if (!mounted) return;
            final newTx = WalletTransaction(
                Map<String, dynamic>.from(payload.newRecord));
            setState(() => _transactions = [newTx, ..._transactions]);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'wallet_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (PostgresChangePayload payload) {
            if (!mounted) return;
            final updatedTx = WalletTransaction(
                Map<String, dynamic>.from(payload.newRecord));
            final updatedId = dbString(updatedTx.id);
            setState(() {
              final idx = _transactions
                  .indexWhere((t) => dbString(t.id) == updatedId);
              if (idx != -1) {
                final list = List<WalletTransaction>.from(_transactions);
                list[idx] = updatedTx;
                _transactions = list;
              } else {
                _transactions = [updatedTx, ..._transactions];
              }
            });
            if (_pendingCashInTransactionId != null &&
                updatedId == _pendingCashInTransactionId) {
              final status = updatedTx.status.trim().toLowerCase();
              if (_isSuccessfulStatus(status)) {
                _pendingCashInTransactionId = null;
                _showSnack(
                  'Wallet cash-in completed.',
                  backgroundColor: const Color(0xFF16A34A),
                );
              } else if (status == 'failed') {
                _pendingCashInTransactionId = null;
                _showSnack(
                  'Cash-in failed. No balance was added.',
                  backgroundColor: const Color(0xFFDC2626),
                );
              }
            }
          },
        )
        .subscribe();
  }

  void _listenForWalletDeepLinks() {
    // app_links removed for web compatibility; deep links handled via initialDeepLink on mobile
  }

  bool _isWalletDeepLink(Uri uri) {
    return uri.scheme.toLowerCase() == 'touristrike' &&
        uri.host.toLowerCase() == 'wallet';
  }

  Future<void> _handleWalletDeepLink(Uri uri) async {
    if (!_isWalletDeepLink(uri)) return;

    final normalized = uri.toString();
    if (_lastHandledWalletLink == normalized) return;
    _lastHandledWalletLink = normalized;

    final action = uri.pathSegments.isEmpty
        ? ''
        : uri.pathSegments.first.toLowerCase();
    final transactionId = uri.queryParameters['transaction_id']?.trim();

    if (transactionId != null && transactionId.isNotEmpty) {
      _pendingCashInTransactionId = transactionId;
    }

    switch (action) {
      case 'success':
        await _pollForCheckoutSettlement(showIntroSnack: true);
        break;
      case 'cancel':
        _pendingCashInTransactionId = null;
        await _loadWalletData();
        _showSnack(
          'Cash-in was cancelled. No balance was added.',
          backgroundColor: const Color(0xFFF59E0B),
        );
        break;
      default:
        await _loadWalletData();
        break;
    }
  }

  bool _isSuccessfulStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'paid' || normalized == 'completed';
  }

  Future<void> _pollForCheckoutSettlement({bool showIntroSnack = false}) async {
    final transactionId = _pendingCashInTransactionId;
    if (transactionId == null || transactionId.isEmpty) {
      await _loadWalletData();
      return;
    }

    if (_refreshingCheckoutState) return;
    _refreshingCheckoutState = true;

    if (showIntroSnack) {
      _showSnack(
        'Payment received. Refreshing your wallet...',
        backgroundColor: const Color(0xFF2A86FF),
      );
    }

    try {
      for (var attempt = 0; attempt < 12; attempt++) {
        await _loadWalletData();
        if (!mounted) return;

        WalletTransaction? tx;
        for (final t in _transactions) {
          if (dbString(t.id) == transactionId) {
            tx = t;
            break;
          }
        }

        if (tx != null) {
          final status = tx.status.trim().toLowerCase();
          if (_isSuccessfulStatus(status)) {
            _pendingCashInTransactionId = null;
            _showSnack(
              'Wallet cash-in completed.',
              backgroundColor: const Color(0xFF16A34A),
            );
            return;
          }
          if (status == 'failed') {
            _pendingCashInTransactionId = null;
            _showSnack(
              'Cash-in failed. No balance was added.',
              backgroundColor: const Color(0xFFDC2626),
            );
            return;
          }
        }

        if (attempt < 11) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }

      _showSnack(
        'Payment is still processing. Pull down to refresh in a moment.',
        backgroundColor: const Color(0xFFF59E0B),
      );
    } finally {
      _refreshingCheckoutState = false;
    }
  }

  void _handleCheckoutLaunched(String? transactionId) {
    if (transactionId != null && transactionId.trim().isNotEmpty) {
      _pendingCashInTransactionId = transactionId.trim();
    }

    _showSnack(
      'Checkout opened in your browser. Complete the payment, then return to the app.',
      backgroundColor: const Color(0xFF2A86FF),
    );

    unawaited(_loadWalletData());
  }

  void _showSnack(String message, {Color? backgroundColor}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: backgroundColor ?? const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  void _showCashIn() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CashInSheet(
        repo: _repo,
        onCheckoutLaunched: _handleCheckoutLaunched,
      ),
    );
  }

  void _showComingSoon(String feature) {
    _showSnack(
      '$feature - coming soon!',
      backgroundColor: const Color(0xFF334155),
    );
  }

  void _scrollToHistory() {}

  @override
  Widget build(BuildContext context) {
    return TouristAiChatbotWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        bottomNavigationBar: const SafeArea(
          top: false,
          child: SizedBox(height: 86, child: AppBottomNav(selectedIndex: 2)),
        ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF2A86FF)),
              )
            : _loadError != null
                ? _ErrorState(
                    message: _loadError!,
                    onRetry: () => unawaited(_loadWalletData()),
                  )
                : RefreshIndicator(
                    onRefresh: _reload,
                    color: const Color(0xFF2A86FF),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _WalletCard(
                          wallet: _wallet!,
                          balanceHidden: _balanceHidden,
                          onToggleHide: () {
                            setState(() => _balanceHidden = !_balanceHidden);
                          },
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _ActionButton(
                                icon: Icons.add_rounded,
                                label: 'Cash In',
                                color: const Color(0xFF2A86FF),
                                onTap: _showCashIn,
                              ),
                              _ActionButton(
                                icon: Icons.payment_rounded,
                                label: 'Pay Package',
                                color: const Color(0xFF0EA5E9),
                                onTap: () => _showComingSoon('Pay Package'),
                              ),
                              _ActionButton(
                                icon: Icons.send_rounded,
                                label: 'Transfer',
                                color: const Color(0xFF6366F1),
                                onTap: () => _showComingSoon('Transfer'),
                              ),
                              _ActionButton(
                                icon: Icons.receipt_long_rounded,
                                label: 'History',
                                color: const Color(0xFF475569),
                                onTap: _scrollToHistory,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: _TransactionList(
                              transactions: _transactions),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
      ),
    ));
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.wallet,
    required this.balanceHidden,
    required this.onToggleHide,
  });

  final Wallet wallet;
  final bool balanceHidden;
  final VoidCallback onToggleHide;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF2A86FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A86FF).withValues(alpha: 0.38),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: 60,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'TourisPay',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onToggleHide,
                      child: Icon(
                        balanceHidden
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Available Balance',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  balanceHidden
                      ? '₱ ******'
                      : money.format(wallet.balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 34,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Icon(
                      Icons.shield_rounded,
                      color: Colors.white.withValues(alpha: 0.60),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Secured by PayMongo',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.60),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({required this.transactions});

  final List<WalletTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Transactions',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 12),
        if (transactions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE7EEF7)),
            ),
            child: const Text(
              'No transactions yet.\nTap Cash In to top up your wallet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          ...transactions.map((tx) => _TxCard(tx: tx)),
      ],
    );
  }
}

class _TxCard extends StatelessWidget {
  const _TxCard({required this.tx});

  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final date = tx.createdAt == null
        ? ''
        : DateFormat('MMM d, yyyy - h:mm a').format(tx.createdAt!);

    final isCredit =
        tx.type == 'cash_in' ||
        tx.type == 'driver_earning' ||
        tx.type == 'refund';

    final (icon, color, bg, label) = switch (tx.type) {
      'cash_in' => (
        Icons.arrow_downward_rounded,
        const Color(0xFF16A34A),
        const Color(0xFFDCFCE7),
        'Cash In',
      ),
      'package_payment' => (
        Icons.tour_rounded,
        const Color(0xFF2A86FF),
        const Color(0xFFEAF2FF),
        'Package Payment',
      ),
      'driver_earning' => (
        Icons.directions_car_rounded,
        const Color(0xFF0EA5E9),
        const Color(0xFFE0F2FE),
        'Driver Earning',
      ),
      'withdrawal' => (
        Icons.arrow_upward_rounded,
        const Color(0xFFDC2626),
        const Color(0xFFFEE2E2),
        'Withdrawal',
      ),
      'refund' => (
        Icons.refresh_rounded,
        const Color(0xFF16A34A),
        const Color(0xFFDCFCE7),
        'Refund',
      ),
      _ => (
        Icons.swap_horiz_rounded,
        const Color(0xFF475569),
        const Color(0xFFF1F5F9),
        'Transaction',
      ),
    };

    final normalizedStatus = tx.status.trim().toLowerCase();
    final statusColor =
        normalizedStatus == 'paid' || normalizedStatus == 'completed'
        ? const Color(0xFF16A34A)
        : normalizedStatus == 'failed'
        ? const Color(0xFFDC2626)
        : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        tx.status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    if (date.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          date,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}${money.format(tx.amount)}',
            style: TextStyle(
              color: isCredit
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626),
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _CashInSheet extends StatefulWidget {
  const _CashInSheet({required this.repo, required this.onCheckoutLaunched});

  final TourisTrikeRepository repo;
  final ValueChanged<String?> onCheckoutLaunched;

  @override
  State<_CashInSheet> createState() => _CashInSheetState();
}

class _CashInSheetState extends State<_CashInSheet> {
  final _amountController = TextEditingController();

  String _method = 'gcash';
  bool _loading = false;
  String? _error;

  static const _methods = [
    ('gcash', 'GCash', Icons.mobile_friendly_rounded, Color(0xFF0073CF)),
    ('maya', 'Maya', Icons.account_balance_rounded, Color(0xFF00B14F)),
    ('card', 'Card', Icons.credit_card_rounded, Color(0xFF6366F1)),
  ];

  static const _quickAmounts = [50.0, 100.0, 200.0, 500.0, 1000.0];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _proceed() async {
    final raw = _amountController.text.trim();
    final amount = double.tryParse(raw.replaceAll(',', ''));

    if (amount == null || amount < 50) {
      setState(() => _error = 'Minimum cash-in is ₱50.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.repo.cashIn(
        amount: amount,
        paymentMethod: _method,
      );

      final checkoutUrl = result['checkout_url'] as String?;
      final transactionId = result['transaction_id'] as String?;

      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        throw Exception('No checkout URL received.');
      }

      final uri = Uri.parse(checkoutUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        await Clipboard.setData(ClipboardData(text: checkoutUrl));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Checkout URL copied. Open it in your browser to pay.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      widget.onCheckoutLaunched(transactionId);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Cash In',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add money to your TouristPay wallet',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Payment Method',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: _methods
                .map((method) {
                  final (key, label, icon, color) = method;
                  final selected = _method == key;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _method = key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? color.withValues(alpha: 0.10)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected ? color : const Color(0xFFE2E8F0),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icon,
                                color: selected
                                    ? color
                                    : const Color(0xFF94A3B8),
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                label,
                                style: TextStyle(
                                  color: selected
                                      ? color
                                      : const Color(0xFF64748B),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: 20),
          const Text(
            'Amount',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
            ],
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              prefixText: '₱  ',
              prefixStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Color(0xFF2A86FF),
              ),
              hintText: '0.00',
              hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF2A86FF),
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickAmounts
                  .map((amount) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          _amountController.text = amount.toStringAsFixed(0);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF2FF),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '₱${amount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Color(0xFF2A86FF),
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Chrome or your external browser will open automatically. After you pay, PayMongo will return you to the wallet screen.',
              style: TextStyle(
                color: Color(0xFF1E3A8A),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFDC2626),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _proceed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A86FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Continue to Payment',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
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
