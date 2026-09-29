import 'package:flutter/material.dart';
import 'tour_stay_details.dart';
import 'package:touristrike/core/models/driver_tour_action.dart';

class DriverTourPaymentRequiredCard extends StatelessWidget {
  const DriverTourPaymentRequiredCard({super.key, required this.gate});
  final DriverTourPaymentGate? gate;

  @override
  Widget build(BuildContext context) {
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
            TourPaymentSummary(
              packageBalance: summary.packageRemaining,
              additionalWaiting: summary.finalizedWaiting,
              totalRemaining: summary.totalRemaining,
            ),
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
