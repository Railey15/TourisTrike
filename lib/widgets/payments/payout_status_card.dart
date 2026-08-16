import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/supabase/touristrike_models.dart';

/// Driver-facing payout status — one card per booking, one row per stage
/// (down_payment / remaining_balance / full) they're owed. Shows WHY the
/// amount is what it is (their split share, not the booking total) and
/// surfaces failed disbursements loudly with a retry action, per the
/// "failed disbursement must not be silent" UI requirement.
class PayoutStatusCard extends StatelessWidget {
  const PayoutStatusCard({
    super.key,
    required this.records,
    this.onRetry,
    this.retryingStage,
  });

  final List<PayoutRecord> records;

  /// Called with the record to retry — caller owns the actual RPC/Edge
  /// Function call (TourisTrikeRepository.retryDisbursement) and refresh.
  final ValueChanged<PayoutRecord>? onRetry;

  /// payment_stage currently mid-retry, so its button can show a spinner
  /// instead of the whole card reacting.
  final String? retryingStage;

  static final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();

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
            'Your Earnings — This Booking',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < records.length; i++) ...[
            if (i > 0) const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _PayoutRow(
              record: records[i],
              currency: _currency,
              onRetry: onRetry,
              isRetrying: retryingStage == records[i].paymentStage,
            ),
          ],
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({
    required this.record,
    required this.currency,
    required this.onRetry,
    required this.isRetrying,
  });

  final PayoutRecord record;
  final NumberFormat currency;
  final ValueChanged<PayoutRecord>? onRetry;
  final bool isRetrying;

  String get _stageLabel => switch (record.paymentStage) {
    'down_payment' => 'Down Payment',
    'remaining_balance' => 'Remaining Balance',
    _ => 'Full Payment',
  };

  (Color, Color, String, IconData) get _statusVisuals => switch (record.status) {
    'paid' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A), 'Paid', Icons.check_circle_rounded),
    'processing' => (const Color(0xFFFEF3C7), const Color(0xFFB45309), 'Processing', Icons.autorenew_rounded),
    'failed' => (const Color(0xFFFEE2E2), const Color(0xFFDC2626), 'Failed', Icons.error_rounded),
    _ => (const Color(0xFFF1F5F9), const Color(0xFF64748B), 'Pending', Icons.schedule_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label, icon) = _statusVisuals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _stageLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    currency.format(record.amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: fg),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: fg),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (record.isFailed) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.errorMessage.isNotEmpty
                      ? record.errorMessage
                      : 'Disbursement failed. Please check your GCash details and try again.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D), fontWeight: FontWeight.w600),
                ),
                if (record.retryCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Retry attempts: ${record.retryCount}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B)),
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: OutlinedButton.icon(
                      onPressed: isRetrying ? null : () => onRetry!(record),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFDC2626)),
                      ),
                      icon: isRetrying
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(isRetrying ? 'Retrying…' : 'Retry Disbursement'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (record.isPaid && record.providerReferenceNumber.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Ref: ${record.providerReferenceNumber}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ],
    );
  }
}
