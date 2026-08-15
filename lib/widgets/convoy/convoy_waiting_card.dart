import 'package:flutter/material.dart';

import '../../core/models/convoy_state.dart';
import '../../core/services/convoy_barrier_service.dart';

/// Simplest-possible "why can't I depart yet" card for a barrier-gated
/// driver action. Deliberately plain — Phase 2b scope is "make it clear
/// who's blocking and for how long," not the animated roster strip from
/// the full UI spec (that's Phase 2c).
class ConvoyWaitingCard extends StatelessWidget {
  const ConvoyWaitingCard({
    super.key,
    required this.blockingDrivers,
    this.now,
  });

  /// Drivers the barrier is waiting on — from
  /// ConvoyBarrierService.blockingDepartFrom*() / blockingCompleteTour().
  final List<ConvoyDriverSnapshot> blockingDrivers;

  /// Injectable clock for tests; defaults to [DateTime.now].
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    if (blockingDrivers.isEmpty) return const SizedBox.shrink();
    final effectiveNow = now ?? DateTime.now();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  blockingDrivers.length == 1
                      ? 'Waiting for 1 driver'
                      : 'Waiting for ${blockingDrivers.length} drivers',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final driver in blockingDrivers)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _BlockingDriverLine(driver: driver, now: effectiveNow),
            ),
        ],
      ),
    );
  }
}

class _BlockingDriverLine extends StatelessWidget {
  const _BlockingDriverLine({required this.driver, required this.now});

  final ConvoyDriverSnapshot driver;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final elapsed = ConvoyBarrierService.elapsedAtCurrentState(
      driver,
      now: now,
    );
    final isStuck = ConvoyBarrierService.isStuck(driver, now: now);
    final isOffline = ConvoyBarrierService.isOffline(driver, now: now);
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds.remainder(60);
    final elapsedLabel =
        '$minutes:${seconds.toString().padLeft(2, '0')}';

    final label = driver.plateNumber.isNotEmpty
        ? '${driver.driverName} (${driver.plateNumber})'
        : driver.driverName;
    final detail = isOffline
        ? 'May have lost signal'
        : '${driver.journeyState.label} · waiting $elapsedLabel';
    final detailColor = isOffline || isStuck
        ? const Color(0xFFDC2626)
        : const Color(0xFF92400E);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isOffline ? Icons.signal_wifi_off_rounded : Icons.pending_rounded,
          size: 14,
          color: detailColor,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 11.5,
                  color: detailColor,
                  fontWeight: isStuck || isOffline
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
