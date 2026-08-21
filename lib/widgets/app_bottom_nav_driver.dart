import 'package:flutter/material.dart';

import 'package:touristrike/screens/driver/driver_earnings_screen.dart';
import 'package:touristrike/screens/driver/driver_home_screen.dart';
import 'package:touristrike/screens/driver/driver_messages_screen.dart';
import 'package:touristrike/screens/driver/driver_package_jobs_screen.dart';
import 'package:touristrike/screens/driver/driver_trips.dart';

class AppBottomNavDriver extends StatelessWidget {
  /// 0: Home, 1: Tours, 2: Activity, 3: Earnings, 4: Messages
  const AppBottomNavDriver({super.key, required this.currentIndex, this.onTap});

  final int currentIndex;
  final ValueChanged<int>? onTap;

  static const Color _activeColor = Color(0xFF2F6FFF);
  static const Color _inactiveColor = Color(0xFF64748B);

  void _handleTap(BuildContext context, int index) {
    if (index == currentIndex) return;

    Widget page;
    switch (index) {
      case 0:
        page = const DriverHomeScreen();
        break;
      case 1:
        page = const DriverPackageJobsScreen();
        break;
      case 2:
        page = DriverTripsScreen(
          navIndex: 2,
          onBottomNavTap: (value) => _handleTap(context, value),
        );
        break;
      case 3:
        page = const DriverEarningsScreen();
        break;
      case 4:
        page = const DriverMessagesScreen();
        break;
      default:
        page = const DriverHomeScreen();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(10, 10, 10, 10 + bottomInset),
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
          _NavItem(
            label: 'Home',
            icon: Icons.dashboard_rounded,
            isActive: currentIndex == 0,
            onPressed: () => _handleTap(context, 0),
          ),
          _NavItem(
            label: 'Tours',
            icon: Icons.tour_rounded,
            isActive: currentIndex == 1,
            onPressed: () => _handleTap(context, 1),
          ),
          _NavItem(
            label: 'Activity',
            icon: Icons.assignment_rounded,
            isActive: currentIndex == 2,
            onPressed: () => _handleTap(context, 2),
          ),
          _NavItem(
            label: 'Earnings',
            icon: Icons.receipt_long_rounded,
            isActive: currentIndex == 3,
            onPressed: () => _handleTap(context, 3),
          ),
          _NavItem(
            label: 'Messages',
            icon: Icons.chat_bubble_outline_rounded,
            isActive: currentIndex == 4,
            onPressed: () => _handleTap(context, 4),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? AppBottomNavDriver._activeColor
        : AppBottomNavDriver._inactiveColor;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? AppBottomNavDriver._activeColor.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
