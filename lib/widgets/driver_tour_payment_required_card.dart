import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/models/driver_tour_action.dart';

class DriverTourPaymentRequiredCard extends StatelessWidget {
  const DriverTourPaymentRequiredCard({super.key, required this.gate});
  final DriverTourPaymentGate? gate;

  @override
  Widget build(BuildContext context) {
    String money(double value) => '₱${NumberFormat('#,##0.00').format(value)}';
    Widget amount(String label, double value, {bool total = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 4,
        children: [
          Text(label),
          Text(
            money(value),
            style: TextStyle(
              fontWeight: total ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, color: Color(0xFF92400E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  gate == null ? 'CHECKING PAYMENT' : 'PAYMENT REQUIRED',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (gate case final summary?) ...[
            amount('Package Remaining', summary.packageRemaining),
            amount('Finalized Additional Waiting', summary.finalizedWaiting),
            const Divider(),
            amount('Total Remaining', summary.totalRemaining, total: true),
          ],
          const SizedBox(height: 8),
          Text(
            gate == null
                ? 'Drop-off is locked until payment is verified. Pull to refresh to retry.'
                : 'Waiting for the tourist to settle payment. Drop-off unlocks after confirmed settlement.',
          ),
        ],
      ),
    );
  }
}
