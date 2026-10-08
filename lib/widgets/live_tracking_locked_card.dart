import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LiveTrackingLockedCard extends StatelessWidget {
  const LiveTrackingLockedCard({super.key, required this.scheduledStartAt});

  final DateTime scheduledStartAt;

  @override
  Widget build(BuildContext context) {
    final start = DateFormat(
      'MMM d, yyyy • h:mm a',
    ).format(scheduledStartAt.toLocal());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EBF3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.lock_clock_outlined,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Live tour tracking is locked',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Map and participant live location will be available when your scheduled tour begins.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Tour starts: $start',
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
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
