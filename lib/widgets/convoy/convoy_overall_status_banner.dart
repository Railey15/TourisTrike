import 'package:flutter/material.dart';

import '../../core/models/convoy_state.dart';
import '../../core/services/convoy_barrier_service.dart';

/// Tourist-facing aggregate status — Phase 3, Requirement A item 3. Shows
/// the SLOWEST driver's progress (Open Question 4) in plain language:
/// never a raw journey_state name, never the word "barrier".
class ConvoyOverallStatusBanner extends StatelessWidget {
  const ConvoyOverallStatusBanner({super.key, required this.convoy});

  final List<ConvoyDriverSnapshot> convoy;

  @override
  Widget build(BuildContext context) {
    if (convoy.isEmpty) return const SizedBox.shrink();
    final overall = ConvoyBarrierService.deriveOverallState(convoy);
    if (overall == null) return const SizedBox.shrink();

    final isSolo = convoy.length == 1;
    final readyCount = convoy.where(ConvoyBarrierService.isAtGate).length;
    final allReady = readyCount == convoy.length;

    final String headline;
    if (overall == ConvoyJourneyState.completed) {
      headline = 'Tour completed';
    } else if (isSolo) {
      // Solo booking: no group to wait on, just show the driver's own
      // plain-language status directly.
      headline = overall.label;
    } else if (allReady) {
      headline = 'All tricycles ready';
    } else {
      headline = 'Waiting for all tricycles';
    }

    final (bg, border, fg, icon) = switch (overall) {
      ConvoyJourneyState.completed => (
        const Color(0xFFECFDF5),
        const Color(0xFFA7F3D0),
        const Color(0xFF16A34A),
        Icons.task_alt_rounded,
      ),
      _ when allReady => (
        const Color(0xFFECFDF5),
        const Color(0xFFA7F3D0),
        const Color(0xFF16A34A),
        Icons.check_circle_rounded,
      ),
      _ => (
        const Color(0xFFFFF7ED),
        const Color(0xFFFED7AA),
        const Color(0xFF92400E),
        Icons.hourglass_top_rounded,
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                if (!isSolo && overall != ConvoyJourneyState.completed) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$readyCount of ${convoy.length} tricycles arrived',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
