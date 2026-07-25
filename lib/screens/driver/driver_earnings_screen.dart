import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/shared/acknowledgement_receipt_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_driver.dart';

// TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
// Replaces the old "Driver Wallet" screen. There is no app-held balance here —
// this is a read-only record of GCash-to-GCash payments the driver has
// received directly from tourists.
class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  final TourisTrikeRepository _repo = TourisTrikeRepository();

  bool _loading = true;
  List<PaymentRecord> _records = const [];
  List<PackageActivity> _activities = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _repo.fetchPaymentRecords(role: 'payee', limit: 200),
        _repo.fetchDriverActivities(),
      ]);
      if (!mounted) return;
      setState(() {
        _records = results[0] as List<PaymentRecord>;
        _activities = results[1] as List<PackageActivity>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load earnings: $e')),
      );
    }
  }

  double get _totalEarned => _records
      .where((r) => r.isConfirmed)
      .fold<double>(0, (sum, r) => sum + r.amount);

  int get _activeCount =>
      _activities.where((a) => a.lifecycleStatus == 'accepted' || a.lifecycleStatus == 'ongoing').length;

  int get _completedCount =>
      _activities.where((a) => a.lifecycleStatus == 'completed').length;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: blue,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const Text(
                'Earnings',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textDark),
              ),
              const SizedBox(height: 4),
              const Text(
                'Money moves directly to your GCash — TourisTrike only keeps a record.',
                style: TextStyle(color: textMid, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2A86FF), Color(0xFF1D4ED8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Recorded Earnings',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      money.format(_totalEarned),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Recorded lang ito — nasa GCash mo na ang aktwal na pera.',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(label: 'Active Tours', value: '$_activeCount'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(label: 'Completed', value: '$_completedCount'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: 'Confirmed',
                      value: '${_records.where((r) => r.isConfirmed).length}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Transaction History',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textDark),
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(color: blue),
                  ),
                )
              else if (_records.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Text(
                      'No payments recorded yet.',
                      style: TextStyle(fontWeight: FontWeight.w900, color: textMid),
                    ),
                  ),
                )
              else
                ..._records.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _EarningTile(record: r),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNavDriver(currentIndex: 3),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _EarningTile extends StatelessWidget {
  const _EarningTile({required this.record});

  final PaymentRecord record;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF16A34A);
    const amber = Color(0xFFB45309);
    const red = Color(0xFFDC2626);
    final statusColor = record.status == 'confirmed'
        ? green
        : record.status == 'disputed'
        ? red
        : amber;
    final dateLabel = record.createdAt != null
        ? DateFormat.yMMMd().add_jm().format(record.createdAt!.toLocal())
        : '-';

    return InkWell(
      onTap: record.isConfirmed
          ? () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AcknowledgementReceiptScreen(record: record),
              ),
            )
          : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
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
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF2A86FF)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.serviceDescription.isEmpty
                        ? record.paymentStage.replaceAll('_', ' ')
                        : record.serviceDescription,
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF64748B), fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${record.amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                Text(
                  record.status.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(fontWeight: FontWeight.w900, color: statusColor, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
