import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/widgets/app_bottom_nav_driver.dart';

class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({super.key, this.onBottomNavTap});

  final ValueChanged<int>? onBottomNavTap;

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen> {
  final _repo = TourisTrikeRepository();
  late Future<_DriverWalletData> _future;
  bool _balanceHidden = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DriverWalletData> _load() async {
    final wallet = await _repo.fetchOrCreateWallet(role: 'driver');
    final transactions = await _repo.fetchWalletTransactions(role: 'driver');
    final activities = await _repo.fetchDriverActivities();
    return _DriverWalletData(
      wallet: wallet,
      transactions: transactions,
      activities: activities,
    );
  }

  void _reload() => setState(() => _future = _load());

  void _showWithdrawComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Withdrawal feature coming soon!'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
        child: FutureBuilder<_DriverWalletData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF2F6FFF)),
              );
            }
            if (snap.hasError) {
              return _ErrorState(
                  message: snap.error.toString(), onRetry: _reload);
            }
            final data = snap.data!;

            final completedActivities =
                data.activities.where((a) => a.status == 'completed').toList();
            final pendingActivities =
                data.activities.where((a) => a.status == 'ongoing').toList();
            final totalEarned = completedActivities.fold<double>(
                0, (s, a) => s + a.price);

            return RefreshIndicator(
              onRefresh: () async => _reload(),
              color: const Color(0xFF2F6FFF),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  // ── Header ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        const SizedBox(width: 44),
                        const Expanded(
                          child: Center(
                            child: Text(
                              'My Wallet',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _reload,
                          icon: const Icon(Icons.refresh_rounded,
                              color: Color(0xFF2F6FFF)),
                        ),
                      ],
                    ),
                  ),

                  // ── Earnings card ───────────────────────────
                  _EarningsCard(
                    wallet: data.wallet,
                    balanceHidden: _balanceHidden,
                    onToggleHide: () =>
                        setState(() => _balanceHidden = !_balanceHidden),
                    onWithdraw: _showWithdrawComingSoon,
                  ),
                  const SizedBox(height: 20),

                  // ── Stats ───────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Completed',
                            value: '${completedActivities.length}',
                            icon: Icons.check_circle_rounded,
                            color: const Color(0xFF16A34A),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            label: 'Ongoing',
                            value: '${pendingActivities.length}',
                            icon: Icons.directions_car_rounded,
                            color: const Color(0xFF0EA5E9),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            label: 'Total Earned',
                            value: NumberFormat.compactCurrency(
                              symbol: '₱',
                              decimalDigits: 0,
                            ).format(totalEarned),
                            icon: Icons.payments_rounded,
                            color: const Color(0xFF2F6FFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Completed packages ──────────────────────
                  if (completedActivities.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Text(
                        'Completed Packages',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    ...completedActivities.take(5).map(
                          (a) => Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: _EarningCard(activity: a),
                          ),
                        ),
                    const SizedBox(height: 6),
                  ],

                  // ── Transaction history ─────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      'Transaction History',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _TxList(transactions: data.transactions),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DriverWalletData {
  _DriverWalletData({
    required this.wallet,
    required this.transactions,
    required this.activities,
  });
  final Wallet wallet;
  final List<WalletTransaction> transactions;
  final List<PackageActivity> activities;
}

// ── Earnings card ──────────────────────────────────────────────
class _EarningsCard extends StatelessWidget {
  const _EarningsCard({
    required this.wallet,
    required this.balanceHidden,
    required this.onToggleHide,
    required this.onWithdraw,
  });

  final Wallet wallet;
  final bool balanceHidden;
  final VoidCallback onToggleHide;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3A6B), Color(0xFF2F6FFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F6FFF).withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -25,
            right: -25,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
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
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions_car_rounded,
                              color: Colors.white, size: 15),
                          SizedBox(width: 6),
                          Text(
                            'Driver Earnings',
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
                  balanceHidden ? '₱ ••••••' : money.format(wallet.balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 32,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onWithdraw,
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    label: const Text(
                      'Request Withdrawal',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2F6FFF),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
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

// ── Stat card ──────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  const _StatCard({
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
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
            label,
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

// ── Earning card (completed package) ──────────────────────────
class _EarningCard extends StatelessWidget {
  const _EarningCard({required this.activity});

  final PackageActivity activity;

  @override
  Widget build(BuildContext context) {
    final pkg = activity.packageRow;
    final booking = activity.bookingRow;
    final packageTitle = dbString(pkg?['title'], fallback: 'Tour Package');
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    DateTime? travelDate;
    if (booking?['travel_date'] != null) {
      travelDate = DateTime.tryParse(booking!['travel_date'].toString());
    }
    final dateStr = travelDate == null
        ? '—'
        : DateFormat('MMM d, yyyy').format(travelDate);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
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
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: Color(0xFF16A34A), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  packageTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money.format(activity.price),
                style: const TextStyle(
                  color: Color(0xFF16A34A),
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'EARNED',
                  style: TextStyle(
                    color: Color(0xFF16A34A),
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
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

// ── Transaction list ───────────────────────────────────────────
class _TxList extends StatelessWidget {
  const _TxList({required this.transactions});

  final List<WalletTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE7EEF7)),
        ),
        child: const Text(
          'No transactions yet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Column(
      children: transactions.map((tx) => _TxRow(tx: tx)).toList(),
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx});

  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final date = tx.createdAt == null
        ? ''
        : DateFormat('MMM d, yyyy').format(tx.createdAt!);

    final isCredit = tx.type == 'driver_earning' || tx.type == 'refund';

    final (icon, color, bg) = switch (tx.type) {
      'driver_earning' => (
          Icons.arrow_downward_rounded,
          const Color(0xFF16A34A),
          const Color(0xFFDCFCE7),
        ),
      'withdrawal' => (
          Icons.arrow_upward_rounded,
          const Color(0xFFDC2626),
          const Color(0xFFFEE2E2),
        ),
      _ => (
          Icons.swap_horiz_rounded,
          const Color(0xFF64748B),
          const Color(0xFFF1F5F9),
        ),
    };

    final typeLabel = switch (tx.type) {
      'driver_earning' => 'Package Earning',
      'withdrawal' => 'Withdrawal',
      'refund' => 'Refund',
      _ => tx.type.replaceAll('_', ' ').toUpperCase(),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration:
                BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeLabel,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                if (date.isNotEmpty)
                  Text(
                    date,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
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
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFDC2626), size: 40),
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
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
