import 'package:flutter/material.dart';

/// Explicit error + retry state for a failed/empty convoy roster fetch.
/// Adjustment 5: an empty `fetchConvoyRoster()` result must never render
/// as a silent blank screen or crash — this is what shows instead.
class ConvoyRosterErrorCard extends StatelessWidget {
  const ConvoyRosterErrorCard({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFDC2626),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Couldn't load convoy status",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
