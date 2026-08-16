import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/supabase/touristrike_models.dart';

/// Tourist-facing view of a payment stage's per-driver split — "kanino
/// napunta, magkano, kailan, ano ang reference" for EVERY driver, not a
/// single collapsed "pending"/"partially paid" string. When some drivers
/// have confirmed and others haven't, this makes it obvious who's still
/// outstanding by name.
class PaymentSplitBreakdownWidget extends StatelessWidget {
  const PaymentSplitBreakdownWidget({
    super.key,
    required this.records,
    required this.driverNames,
  });

  final List<PayoutRecord> records;

  /// driverId -> display name, e.g. sourced from the convoy roster
  /// (ConvoyDriverSnapshot.driverName) already loaded on the tracking screen.
  final Map<String, String> driverNames;

  static final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  static final _time = DateFormat('MMM d, h:mm a');

  String _stageLabel(String stage) => switch (stage) {
    'down_payment' => 'Down Payment',
    'remaining_balance' => 'Remaining Balance',
    _ => 'Full Payment',
  };

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();

    final byStage = <String, List<PayoutRecord>>{};
    for (final r in records) {
      byStage.putIfAbsent(r.paymentStage, () => []).add(r);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Breakdown',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 10),
          for (final entry in byStage.entries) ...[
            Text(
              _stageLabel(entry.key),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 6),
            ...entry.value.map((r) => _DriverSplitTile(
              driverName: driverNames[r.driverId] ?? 'Driver',
              record: r,
              currency: _currency,
              timeFormat: _time,
            )),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _DriverSplitTile extends StatelessWidget {
  const _DriverSplitTile({
    required this.driverName,
    required this.record,
    required this.currency,
    required this.timeFormat,
  });

  final String driverName;
  final PayoutRecord record;
  final NumberFormat currency;
  final DateFormat timeFormat;

  (Color, String) get _statusVisuals => switch (record.status) {
    'paid' => (const Color(0xFF16A34A), 'Paid'),
    'processing' => (const Color(0xFFB45309), 'Processing'),
    'failed' => (const Color(0xFFDC2626), 'Failed — being retried'),
    _ => (const Color(0xFF64748B), 'Waiting'),
  };

  @override
  Widget build(BuildContext context) {
    final (color, label) = _statusVisuals;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        driverName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    Text(
                      currency.format(record.amount),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A)),
                    ),
                  ],
                ),
                Text(
                  record.isPaid && record.updatedAt != null
                      ? '$label • ${timeFormat.format(record.updatedAt!)}'
                      : label,
                  style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
                ),
                if (record.isPaid && record.providerReferenceNumber.isNotEmpty)
                  Text(
                    'Ref: ${record.providerReferenceNumber}',
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
