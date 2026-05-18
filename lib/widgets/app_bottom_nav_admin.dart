import 'package:flutter/material.dart';
import 'package:touristrike/screens/admin/provincial_admin_dashboard_screen.dart';
import 'package:touristrike/screens/admin/province_packages_screen.dart';
import 'package:touristrike/screens/admin/province_reports_screen.dart';
//import 'package:touristrike/screens/admin/profile/admin_profile_screen.dart';

class AppBottomNavAdmin extends StatelessWidget {
  const AppBottomNavAdmin({
    super.key,
    required this.currentIndex,
  });

  final int currentIndex;

  static const Color activeColor = Color(0xFF2A86FF);
  static const Color inactiveColor = Color(0xFF6B7280);

  void _goTo(BuildContext context, int index) {
    if (index == currentIndex) return;

    Widget screen;
    switch (index) {
      case 0:
        screen = const ProvincialAdminDashboardScreen();
        break;
      case 1:
        screen = const ProvinceReportsScreen();
        break;
      case 2:
        screen = const ProvincePackagesScreen();
        break;
      case 3:
        //  screen = const AdminProfileScreen();
        return;
      default:
        screen = const ProvincialAdminDashboardScreen();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      top: false,
      child: Container(
        height: 92 + (bottomPadding > 0 ? 0 : 6),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
          border: const Border(
            top: BorderSide(
              color: Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Row(
              children: [
                Expanded(
                  child: _NavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: 'Home',
                    selected: currentIndex == 0,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    onTap: () => _goTo(context, 0),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.bar_chart_outlined,
                    activeIcon: Icons.bar_chart_rounded,
                    label: 'Performance',
                    selected: currentIndex == 1,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    onTap: () => _goTo(context, 1),
                  ),
                ),
                const Expanded(child: SizedBox()),
                Expanded(
                  child: _NavItem(
                    icon: Icons.inventory_2_outlined,
                    activeIcon: Icons.inventory_2_rounded,
                    label: 'Package List',
                    selected: currentIndex == 2,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    onTap: () => _goTo(context, 2),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_rounded,
                    label: 'Profile',
                    selected: currentIndex == 3,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    onTap: () => _goTo(context, 3),
                  ),
                ),
              ],
            ),
            Positioned(
              top: -18,
              child: _CenterNavButton(
                selected: currentIndex == 2,
                onTap: () => _goTo(context, 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterNavButton extends StatelessWidget {
  const _CenterNavButton({
    required this.selected,
    required this.onTap,
  });

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF58AEFF),
              Color(0xFF2A86FF),
            ],
          ),
          border: Border.all(
            color: Colors.white,
            width: 5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2A86FF).withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(
          selected ? Icons.shield_rounded : Icons.shield_outlined,
          color: const Color(0xFF0F172A),
          size: 30,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: double.infinity,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? activeIcon : icon,
                color: color,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}