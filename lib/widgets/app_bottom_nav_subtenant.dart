import 'package:flutter/material.dart';
import 'package:touristrike/screens/subtenant/subtenant_bookings_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_dashboard_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_drivers_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_packages_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_profile_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_reports_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_spots_screen.dart';

class AppBottomNavSubTenant extends StatelessWidget {
  const AppBottomNavSubTenant({
    super.key,
    required this.currentIndex,
    this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int>? onTap;

  static const Color _activeColor = Color(0xFF2A86FF);
  static const Color _inactiveColor = Color(0xFF64748B);

  static Widget pageForIndex(int index) {
    switch (index) {
      case 0:
        return const SubTenantDashboardScreen();
      case 1:
        return const SubTenantSpotsScreen();
      case 2:
        return const SubTenantPackagesScreen();
      case 3:
        return const SubTenantBookingsScreen();
      case 4:
        return const SubTenantDriversScreen();
      case 5:
        return const SubTenantReportsScreen();
      case 6:
        return const SubTenantProfileScreen();
      default:
        return const SubTenantDashboardScreen();
    }
  }

  static void navigateToIndex(
    BuildContext context,
    int index, {
    required int currentIndex,
  }) {
    if (index == currentIndex) return;

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => pageForIndex(index)));
  }

  void _handleTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    onTap?.call(index);
    navigateToIndex(context, index, currentIndex: currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(8, 9, 8, 9 + bottomInset),
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
            active: currentIndex == 0,
            onTap: () => _handleTap(context, 0),
          ),
          _NavItem(
            label: 'Spots',
            icon: Icons.place_rounded,
            active: currentIndex == 1,
            onTap: () => _handleTap(context, 1),
          ),
          _NavItem(
            label: 'Packages',
            icon: Icons.inventory_2_rounded,
            active: currentIndex == 2,
            onTap: () => _handleTap(context, 2),
          ),
          _NavItem(
            label: 'Bookings',
            icon: Icons.receipt_long_rounded,
            active: currentIndex == 3,
            onTap: () => _handleTap(context, 3),
          ),
          _NavItem(
            label: 'Drivers',
            icon: Icons.badge_rounded,
            active: currentIndex == 4,
            onTap: () => _handleTap(context, 4),
          ),
          _NavItem(
            label: 'Reports',
            icon: Icons.bar_chart_rounded,
            active: currentIndex == 5,
            onTap: () => _handleTap(context, 5),
          ),
          _NavItem(
            label: 'Settings',
            icon: Icons.settings_rounded,
            active: currentIndex == 6,
            onTap: () => _handleTap(context, 6),
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
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AppBottomNavSubTenant._activeColor
        : AppBottomNavSubTenant._inactiveColor;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
            decoration: BoxDecoration(
              color: active
                  ? AppBottomNavSubTenant._activeColor.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 21),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: active ? FontWeight.w900 : FontWeight.w700,
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
