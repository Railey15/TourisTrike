import 'package:flutter/material.dart';

import 'package:touristrike/screens/tourist/profile/payment_history_screen.dart';
import 'package:touristrike/screens/tourist/tourist_activity_screen.dart';
import 'package:touristrike/screens/tourist/tourist_explore_screen.dart';
import 'package:touristrike/screens/tourist/tourist_home_screen.dart';
import 'package:touristrike/screens/tourist/tourist_messages_screen.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.selectedIndex, this.onSelect});

  final int selectedIndex;
  final ValueChanged<int>? onSelect;

  // 0 = Home, 1 = Explore, 2 = Payments, 3 = Activity, 4 = Messages
  void _go(BuildContext context, int index) {
    if (index == selectedIndex) return;
    onSelect?.call(index);

    final Widget target = switch (index) {
      0 => const TouristHomeScreen(),
      1 => const TouristExploreScreen(),
      2 => const PaymentHistoryScreen(),
      3 => const ActivityScreen(),
      4 => const TouristMessagesScreen(),
      _ => const TouristHomeScreen(),
    };

    // Bottom-nav destinations are peers, so switching between them should be
    // immediate instead of using Material's page-push transition.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => target,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(8, 10, 8, 12 + bottomInset),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _NavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              selected: selectedIndex == 0,
              onTap: () => _go(context, 0),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.explore_rounded,
              label: 'Explore',
              selected: selectedIndex == 1,
              onTap: () => _go(context, 1),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.receipt_rounded,
              label: 'Payments',
              selected: selectedIndex == 2,
              onTap: () => _go(context, 2),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.receipt_long_rounded,
              label: 'Activity',
              selected: selectedIndex == 3,
              onTap: () => _go(context, 3),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Messages',
              selected: selectedIndex == 4,
              onTap: () => _go(context, 4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF2A86FF) : const Color(0xFF475569);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 60,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 23),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
