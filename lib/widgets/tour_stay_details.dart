import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Displays server snapshots; elapsed time is only a display countdown.
class TourStayDetails extends StatelessWidget {
  const TourStayDetails({
    super.key,
    required this.destination,
    required this.includedMinutes,
    this.secondsRemaining,
    this.rate,
    this.accruedWaiting,
    this.intervalMinutes = 15,
    this.showDestination = true,
    this.showIncluded = true,
  });
  final String destination;
  final int? includedMinutes;
  final int? secondsRemaining;
  final double? rate;
  final double? accruedWaiting;
  final int intervalMinutes;
  final bool showDestination;
  final bool showIncluded;
  @override
  Widget build(BuildContext context) {
    final seconds = secondsRemaining;
    final overtime = seconds != null && seconds < 0;
    final inGrace = overtime && -seconds < intervalMinutes * 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDestination) ...[
          Text(
            'CURRENT DESTINATION',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Text(destination, style: Theme.of(context).textTheme.titleMedium),
        ],
        if (showIncluded && includedMinutes != null)
          Text('Included stay: $includedMinutes min'),
        if (seconds != null) ...[
          SizedBox(height: showDestination || showIncluded ? 8 : 0),
          Text(
            overtime
                ? inGrace
                      ? 'Free grace: ${((intervalMinutes * 60 + seconds) / 60).ceil()} min remaining'
                      : 'Overtime: ${(-seconds / 60).ceil()} min'
                : 'Included time remaining: ${(seconds / 60).ceil()} min',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: overtime ? const Color(0xFFB45309) : null,
            ),
          ),
        ],
        if (overtime) ...[
          const SizedBox(height: 4),
          Text(
            rate == null
                ? 'No additional waiting fee for this stop'
                : 'Additional waiting: ₱${NumberFormat('#,##0.00').format(rate)} / $intervalMinutes min after one free interval',
          ),
          if (rate != null && accruedWaiting != null)
            Text(
              'Accrued: ₱${NumberFormat('#,##0.00').format(accruedWaiting)}',
            ),
        ],
      ],
    );
  }
}

class TourPaymentSummary extends StatelessWidget {
  const TourPaymentSummary({
    super.key,
    required this.packageBalance,
    required this.additionalWaiting,
    required this.totalRemaining,
  });
  final double packageBalance;
  final double additionalWaiting;
  final double totalRemaining;
  @override
  Widget build(BuildContext context) {
    Widget row(String label, double amount, {bool total = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              '₱${NumberFormat('#,##0.00').format(amount)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: total ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('Package balance', packageBalance),
        row('Additional waiting', additionalWaiting),
        const Divider(),
        row('Total remaining', totalRemaining, total: true),
      ],
    );
  }
}
