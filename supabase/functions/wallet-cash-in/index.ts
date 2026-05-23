import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/widgets/app_bottom_nav_driver.dart';

class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({
    super.key,
    this.onBottomNavTap,
    this.initialDeepLink,
  });

  final ValueChanged<int>? onBottomNavTap;
  final Uri? initialDeepLink;

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen>
    with WidgetsBindingObserver {
  final TourisTrikeRepository _repo = TourisTrikeRepository();
  Wallet? _wallet;
  List<WalletTransaction> _transactions = [];
  List<PackageActivity> _activities = [];
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
    unawaited(_loadData());
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
    if (_wallet == null) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final wallet = await _repo.fetchOrCreateWallet(role: 'driver');
      final transactions = await _repo.fetchWalletTransactions(role: 'driver');
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

  Future<void> _loadData() async {
    await _loadWalletData();
    try {
      final activities = await _repo.fetchDriverActivities();
      if (!mounted) return;
      setState(() => _activities = activities);
    } catch (_) {}
  }

  Future<void> _reload() => _loadData();

  void _subscribeToWalletRealtime() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _walletChannel = Supabase.instance.client
        .channel('driver_wallet_balance_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'wallets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            final updated = Wallet(
              Map<String, dynamic>.from(payload.newRecord),
            );
            setState(() => _wallet = updated);
          },
        )
        .subscribe();
  }

  void _subscribeToTransactionsRealtime() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _txLiveChannel = Supabase.instance.client
        .channel('driver_wallet_txs_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'wallet_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            final newTx = WalletTransaction(
              Map<String, dynamic>.from(payload.newRecord),
            );
            setState(() => _transactions = [newTx, ..._transactions]);
            unawaited(_loadWalletData());
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
          callback: (payload) {
            if (!mounted) return;
            final updatedTx = WalletTransaction(
              Map<String, dynamic>.from(payload.newRecord),
            );
            final updatedId = dbString(updatedTx.id);
            setState(() {
              final index = _transactions.indexWhere(
                (tx) => dbString(tx.id) == updatedId,
              );
              if (index == -1) {
                _transactions = [updatedTx, ..._transactions];
              } else {
                final next = List<WalletTransaction>.from(_transactions);
                next[index] = updatedTx;
                _transactions = next;
              }
            });

            if (_pendingCashInTransactionId == updatedId) {
              final status = updatedTx.status.trim().toLowerCase();
              if (_isSuccessfulStatus(status)) {
                _pendingCashInTransactionId = null;
                _showSnack(
                  'Driver wallet cash-in completed.',
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
    // app_links removed for web compatibility; deep links handled at startup on mobile
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
        'Payment received. Refreshing your driver wallet...',
        backgroundColor: const Color(0xFF2F6FFF),
      );
    }

    try {
      for (var attempt = 0; attempt < 12; attempt++) {
        await _loadWalletData();
        if (!mounted) return;

        WalletTransaction? tx;
        for (final item in _transactions) {
          if (dbString(item.id) == transactionId) {
            tx = item;
            break;
          }
        }

        if (tx != null) {
          final status = tx.status.trim().toLowerCase();
          if (_isSuccessfulStatus(status)) {
            _pendingCashInTransactionId = null;
            _showSnack(
              'Driver wallet cash-in completed.',
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
      backgroundColor: const Color(0xFF2F6FFF),
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
      builder: (_) => _DriverCashInSheet(
        repo: _repo,
        onCheckoutLaunched: _handleCheckoutLaunched,
      ),
    );
  }

  Future<void> _showScanToPay() async {
    try {
      final picker = ImagePicker();
      await picker.pickImage(source: ImageSource.camera);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera unavailable: $e'), backgroundColor: const Color(0xFFDC2626)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      bottomNavigationBar: AppBottomNavDriver(
        currentIndex: 3,
        onTap: widget.onBottomNavTap,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF2F6FFF)),
              )
            : _loadError != null
            ? _DriverWalletErrorState(
                message: _loadError!,
                onRetry: () => unawaited(_loadData()),
              )
            : RefreshIndicator(
                onRefresh: _reload,
                color: const Color(0xFF2F6FFF),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  children: [
                    _DriverWalletHero(
                      wallet: _wallet!,
                      balanceHidden: _balanceHidden,
                      onToggleHide: () {
                        setState(() => _balanceHidden = !_balanceHidden);
                      },
                      onCashIn: _showCashIn,
                      onScanToPay: _showScanToPay,
                    ),
                    const SizedBox(height: 16),
                    _DriverWalletStats(activities: _activities),
                    const SizedBox(height: 22),
                    const Text(
                      'Recent Earnings',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DriverEarningsList(activities: _activities),
                    const SizedBox(height: 22),
                    const Text(
                      'Transaction History',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DriverTransactionList(transactions: _transactions),
                  ],
                ),
              ),
      ),
    );
  }
}

class _DriverWalletHero extends StatelessWidget {
  const _DriverWalletHero({
    required this.wallet,
    required this.balanceHidden,
    required this.onToggleHide,
    required this.onCashIn,
    required this.onScanToPay,
  });

  final Wallet wallet;
  final bool balanceHidden;
  final VoidCallback onToggleHide;
  final VoidCallback onCashIn;
  final VoidCallback onScanToPay;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 2);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF143F72), Color(0xFF2F6FFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F6FFF).withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
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
                      'Driver Wallet',
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
              IconButton(
                onPressed: onToggleHide,
                icon: Icon(
                  balanceHidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                color: Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Available Balance',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            balanceHidden ? 'PHP ******' : money.format(wallet.balance),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 32,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onCashIn,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(
                    'Cash In',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF2F6FFF),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onScanToPay,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: const Text(
                    'Scan To Pay',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverWalletStats extends StatelessWidget {
  const _DriverWalletStats({required this.activities});

  final List<PackageActivity> activities;

  @override
  Widget build(BuildContext context) {
    final completed = activities.where((item) => item.status == 'completed');
    final active = activities.where(
      (item) => item.status == 'accepted' || item.status == 'ongoing',
    );
    final totalEarned = completed.fold<double>(
      0,
      (sum, item) => sum + item.price,
    );

    return Row(
      children: [
        Expanded(
          child: _DriverWalletStatCard(
            label: 'Active Tours',
            value: '${active.length}',
            icon: Icons.route_rounded,
            color: const Color(0xFF0EA5E9),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DriverWalletStatCard(
            label: 'Completed',
            value: '${completed.length}',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF16A34A),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DriverWalletStatCard(
            label: 'Earned',
            value: NumberFormat.compactCurrency(
              symbol: 'PHP ',
              decimalDigits: 0,
            ).format(totalEarned),
            icon: Icons.payments_rounded,
            color: const Color(0xFF2F6FFF),
          ),
        ),
      ],
    );
  }
}

class _DriverWalletStatCard extends StatelessWidget {
  const _DriverWalletStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          Text(
            label,
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

class _DriverEarningsList extends StatelessWidget {
  const _DriverEarningsList({required this.activities});

  final List<PackageActivity> activities;

  @override
  Widget build(BuildContext context) {
    final completed = activities
        .where((item) => item.status == 'completed')
        .take(5)
        .toList(growable: false);

    if (completed.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7EEF7)),
        ),
        child: const Text(
          'No completed package earnings yet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Column(
      children: completed
          .map(
            (activity) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DriverEarningCard(activity: activity),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _DriverEarningCard extends StatelessWidget {
  const _DriverEarningCard({required this.activity});

  final PackageActivity activity;

  @override
  Widget build(BuildContext context) {
    final booking = activity.bookingRow;
    final package = activity.packageRow;
    final title = dbString(package?['title'], fallback: 'Tour Package');
    final travelDate = booking?['travel_date'] == null
        ? null
        : DateTime.tryParse(booking!['travel_date'].toString());

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF16A34A),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  travelDate == null
                      ? 'Date unavailable'
                      : DateFormat('MMM d, yyyy').format(travelDate),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            NumberFormat.currency(
              symbol: 'PHP ',
              decimalDigits: 0,
            ).format(activity.price),
            style: const TextStyle(
              color: Color(0xFF16A34A),
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverTransactionList extends StatelessWidget {
  const _DriverTransactionList({required this.transactions});

  final List<WalletTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7EEF7)),
        ),
        child: const Text(
          'No transactions yet. Tap Top Up to add funds to your wallet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Column(
      children: transactions
          .map(
            (tx) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DriverTransactionCard(tx: tx),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _DriverTransactionCard extends StatelessWidget {
  const _DriverTransactionCard({required this.tx});

  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final date = tx.createdAt == null
        ? ''
        : DateFormat('MMM d, yyyy - h:mm a').format(tx.createdAt!);
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 2);
    final isCredit =
        tx.type == 'cash_in' ||
        tx.type == 'driver_earning' ||
        tx.type == 'refund';

    final (icon, color, background, label) = switch (tx.type) {
      'cash_in' => (
        Icons.arrow_downward_rounded,
        const Color(0xFF16A34A),
        const Color(0xFFDCFCE7),
        'Cash In',
      ),
      'driver_earning' => (
        Icons.payments_rounded,
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
        tx.type.replaceAll('_', ' ').toUpperCase(),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: background,
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
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
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
                    if (date.isNotEmpty)
                      Text(
                        date,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
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
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverCashInSheet extends StatefulWidget {
  const _DriverCashInSheet({
    required this.repo,
    required this.onCheckoutLaunched,
  });

  final TourisTrikeRepository repo;
  final ValueChanged<String?> onCheckoutLaunched;

  @override
  State<_DriverCashInSheet> createState() => _DriverCashInSheetState();
}

class _DriverCashInSheetState extends State<_DriverCashInSheet> {
  final _amountController = TextEditingController();

  String _method = 'gcash';
  bool _loading = false;
  String? _error;

  static const _methods = [
    ('gcash', 'GCash', Icons.mobile_friendly_rounded, Color(0xFF0073CF)),
    ('maya', 'Maya', Icons.account_balance_rounded, Color(0xFF00B14F)),
    ('card', 'Card', Icons.credit_card_rounded, Color(0xFF6366F1)),
  ];

  static const _quickAmounts = [100.0, 200.0, 500.0, 1000.0, 2000.0];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _proceed() async {
    final raw = _amountController.text.trim();
    final amount = double.tryParse(raw.replaceAll(',', ''));

    if (amount == null || amount < 50) {
      setState(() => _error = 'Minimum cash-in is PHP 50.');
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
        role: 'driver',
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
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
            'Top Up Driver Wallet',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add funds using GCash, Maya, or card.',
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
            decoration: InputDecoration(
              prefixText: 'PHP  ',
              prefixStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Color(0xFF2F6FFF),
              ),
              hintText: '0.00',
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
                  color: Color(0xFF2F6FFF),
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
                            'PHP ${amount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Color(0xFF2F6FFF),
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
              'Chrome or your external browser will open automatically. After payment, PayMongo will return you to the driver wallet screen.',
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
                backgroundColor: const Color(0xFF2F6FFF),
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

class _DriverWalletErrorState extends StatelessWidget {
  const _DriverWalletErrorState({required this.message, required this.onRetry});

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
