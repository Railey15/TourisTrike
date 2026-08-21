import 'package:flutter/material.dart';

import '../../core/models/convoy_state.dart';

/// "Your Driver" (solo) / "Your Drivers (N)" (group) card list — Phase 3.
/// One code path for both: a length-1 convoy just renders one card with
/// the singular header, no special-cased branch.
class ConvoyTouristDriverList extends StatelessWidget {
  const ConvoyTouristDriverList({
    super.key,
    required this.convoy,
    this.selectedDriverId,
    this.onSelect,
    this.onCall,
    this.onMessage,
  });

  final List<ConvoyDriverSnapshot> convoy;
  final String? selectedDriverId;
  final ValueChanged<String>? onSelect;
  final ConvoyContactCallback? onCall;
  final ConvoyContactCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    if (convoy.isEmpty) return const SizedBox.shrink();

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
          Text(
            convoy.length == 1 ? 'Your Driver' : 'Your Drivers (${convoy.length})',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < convoy.length; i++) ...[
            _DriverCard(
              index: i,
              driver: convoy[i],
              selected: convoy[i].driverId == selectedDriverId,
              showPassengerCount: convoy.length > 1,
              onTap: onSelect == null ? null : () => onSelect!(convoy[i].driverId),
              onCall: onCall == null ? null : () => onCall!(convoy[i]),
              onMessage: onMessage == null ? null : () => onMessage!(convoy[i]),
            ),
            if (i != convoy.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.index,
    required this.driver,
    required this.selected,
    required this.showPassengerCount,
    this.onTap,
    this.onCall,
    this.onMessage,
  });

  final int index;
  final ConvoyDriverSnapshot driver;
  final bool selected;
  final bool showPassengerCount;
  final VoidCallback? onTap;
  final VoidCallback? onCall;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF2F6FFF) : const Color(0xFFE7EEF7),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFEAF2FF),
                  backgroundImage: driver.avatarUrl.isNotEmpty
                      ? NetworkImage(driver.avatarUrl)
                      : null,
                  child: driver.avatarUrl.isEmpty
                      ? const Icon(Icons.person_rounded, color: Color(0xFF2F6FFF))
                      : null,
                ),
                Positioned(
                  left: -2,
                  top: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2F6FFF),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driver.driverName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  if (driver.plateNumber.isNotEmpty || driver.todaName.isNotEmpty)
                    Text(
                      [
                        driver.plateNumber,
                        driver.todaName,
                      ].where((s) => s.isNotEmpty).join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    driver.journeyState.label,
                    style: const TextStyle(
                      color: Color(0xFF2F6FFF),
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                  if (showPassengerCount && driver.assignedPassengers > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${driver.assignedPassengers} passenger${driver.assignedPassengers == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (onCall != null)
              IconButton(
                onPressed: onCall,
                icon: const Icon(Icons.call_rounded, size: 19),
                color: const Color(0xFF16A34A),
                tooltip: 'Call ${driver.driverName}',
                visualDensity: VisualDensity.compact,
              ),
            if (onMessage != null)
              IconButton(
                onPressed: onMessage,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
                color: const Color(0xFF2F6FFF),
                tooltip: 'Message ${driver.driverName}',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}
