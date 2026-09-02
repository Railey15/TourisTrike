import 'package:flutter/material.dart';

import '../../core/models/convoy_state.dart';
import '../../core/services/convoy_barrier_service.dart';

/// Persistent horizontal roster of every driver in the convoy — Phase 2c.
/// Renders nothing for a solo (N<=1) booking; there's no one else to show.
class ConvoyRosterStrip extends StatelessWidget {
  const ConvoyRosterStrip({
    super.key,
    required this.convoy,
    required this.selfDriverId,
    required this.progress,
    this.now,
    this.onCall,
    this.onMessage,
  });

  final List<ConvoyDriverSnapshot> convoy;
  final String selfDriverId;
  final ConvoyStageProgress progress;
  final DateTime? now;
  final ConvoyContactCallback? onCall;
  final ConvoyContactCallback? onMessage;

  Color _statusColor(ConvoyDriverSnapshot d, DateTime now) {
    if (ConvoyBarrierService.isOffline(d, now: now)) {
      return const Color(0xFFDC2626); // red — offline/stuck
    }
    if (ConvoyBarrierService.isAtGate(d)) {
      return const Color(0xFF16A34A); // green
    }
    return const Color(0xFFF59E0B); // amber — en route
  }

  @override
  Widget build(BuildContext context) {
    if (convoy.length <= 1) return const SizedBox.shrink();
    final effectiveNow = now ?? DateTime.now();
    final satisfiedCount = progress.satisfiedDriverCount;
    final requiredCount = progress.requiredDriverCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Convoy',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                progress.allSatisfied
                    ? 'Convoy synchronized — $satisfiedCount of $requiredCount'
                    : 'Convoy progress — $satisfiedCount of $requiredCount',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: requiredCount == 0 ? 0 : satisfiedCount / requiredCount,
              minHeight: 5,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF16A34A)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 66,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: convoy.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final driver = convoy[index];
                return _RosterAvatar(
                  driver: driver,
                  isSelf: driver.driverId == selfDriverId,
                  color: _statusColor(driver, effectiveNow),
                  onTap: () => _showDriverSheet(context, driver),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDriverSheet(BuildContext context, ConvoyDriverSnapshot driver) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFEAF2FF),
                    backgroundImage: driver.avatarUrl.isNotEmpty
                        ? NetworkImage(driver.avatarUrl)
                        : null,
                    child: driver.avatarUrl.isEmpty
                        ? const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF2F6FFF),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver.driverName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        if (driver.plateNumber.isNotEmpty)
                          Text(
                            driver.plateNumber,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  driver.isAssignmentCompleted
                      ? 'Assignment completed'
                      : driver.journeyState.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (onCall != null && driver.phoneNumber.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          onCall!(driver);
                        },
                        icon: const Icon(Icons.call_rounded, size: 16),
                        label: const Text('Call'),
                      ),
                    ),
                  if (onCall != null &&
                      onMessage != null &&
                      driver.phoneNumber.isNotEmpty)
                    const SizedBox(width: 10),
                  if (onMessage != null)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          onMessage!(driver);
                        },
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 16,
                        ),
                        label: const Text('Message'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterAvatar extends StatelessWidget {
  const _RosterAvatar({
    required this.driver,
    required this.isSelf,
    required this.color,
    required this.onTap,
  });

  final ConvoyDriverSnapshot driver;
  final bool isSelf;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: EdgeInsets.all(isSelf ? 2.5 : 0),
                  decoration: isSelf
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF2F6FFF),
                            width: 2,
                          ),
                        )
                      : null,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFFEAF2FF),
                    backgroundImage: driver.avatarUrl.isNotEmpty
                        ? NetworkImage(driver.avatarUrl)
                        : null,
                    child: driver.avatarUrl.isEmpty
                        ? const Icon(
                            Icons.person_rounded,
                            size: 18,
                            color: Color(0xFF2F6FFF),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              isSelf
                  ? 'YOU'
                  : (driver.plateNumber.isNotEmpty
                        ? driver.plateNumber
                        : driver.driverName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: isSelf
                    ? const Color(0xFF2F6FFF)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
