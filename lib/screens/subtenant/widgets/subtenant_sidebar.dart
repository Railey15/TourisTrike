import 'package:flutter/material.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantSidebar extends StatefulWidget {
  const SubTenantSidebar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.onLogout,
    this.compact = false,
    this.asDrawer = false,
  });

  const SubTenantSidebar.drawer({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.onLogout,
  }) : compact = false,
       asDrawer = true;

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onLogout;
  final bool compact;
  final bool asDrawer;

  @override
  State<SubTenantSidebar> createState() => _SubTenantSidebarState();
}

class _SubTenantSidebarState extends State<SubTenantSidebar> {
  bool _hovered = false;
  bool _expanded = true;

  static const List<_SidebarDestination> _destinations = [
    _SidebarDestination(
      label: 'Dashboard',
      icon: Icons.dashboard_rounded,
      index: 0,
    ),
    _SidebarDestination(label: 'Spots', icon: Icons.place_rounded, index: 1),
    _SidebarDestination(
      label: 'Packages',
      icon: Icons.inventory_2_rounded,
      index: 2,
    ),
    _SidebarDestination(
      label: 'Bookings',
      icon: Icons.receipt_long_rounded,
      index: 3,
    ),
    _SidebarDestination(label: 'Drivers', icon: Icons.badge_rounded, index: 4),
    _SidebarDestination(
      label: 'Reports',
      icon: Icons.bar_chart_rounded,
      index: 5,
    ),
    _SidebarDestination(
      label: 'Settings',
      icon: Icons.settings_rounded,
      index: 6,
    ),
  ];

  bool get _effectiveExpanded {
    if (widget.asDrawer) return true;
    if (widget.compact) return _hovered;
    return _expanded || _hovered;
  }

  @override
  Widget build(BuildContext context) {
    final expanded = _effectiveExpanded;
    final width = widget.asDrawer ? 292.0 : (expanded ? 258.0 : 86.0);

    final sidebar = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        width: width,
        margin: widget.asDrawer ? EdgeInsets.zero : const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF536DFE), Color(0xFF2A86FF), Color(0xFF1E63E9)],
          ),
          borderRadius: BorderRadius.circular(widget.asDrawer ? 0 : 28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
          boxShadow: widget.asDrawer
              ? null
              : [
                  BoxShadow(
                    color: SubTenantColors.blue.withValues(alpha: 0.30),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
        ),
        child: Column(
          children: [
            _SidebarBrand(
              expanded: expanded,
              showToggle: !widget.asDrawer && !widget.compact,
              isPinnedOpen: _expanded,
              onToggle: () => setState(() => _expanded = !_expanded),
            ),
            const SizedBox(height: 22),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemBuilder: (context, index) {
                  final item = _destinations[index];
                  return SidebarNavItem(
                    label: item.label,
                    icon: item.icon,
                    expanded: expanded,
                    active: widget.currentIndex == item.index,
                    onTap: () => widget.onDestinationSelected(item.index),
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(height: 9),
                itemCount: _destinations.length,
              ),
            ),
            const SizedBox(height: 12),
            SidebarNavItem(
              label: 'Logout',
              icon: Icons.logout_rounded,
              expanded: expanded,
              active: false,
              danger: true,
              onTap: widget.onLogout,
            ),
          ],
        ),
      ),
    );

    if (widget.asDrawer) {
      return Drawer(
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: SafeArea(child: sidebar),
      );
    }

    return sidebar;
  }
}

class SidebarNavItem extends StatefulWidget {
  const SidebarNavItem({
    super.key,
    required this.label,
    required this.icon,
    required this.expanded,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final bool expanded;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  @override
  State<SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.danger ? const Color(0xFFFFE4E6) : Colors.white;
    final activeColor = Colors.white.withValues(alpha: 0.18);
    final hoverColor = Colors.white.withValues(alpha: 0.10);

    final item = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            height: 52,
            padding: EdgeInsets.symmetric(
              horizontal: widget.expanded ? 14 : 0,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: widget.active
                  ? activeColor
                  : (_hovered ? hoverColor : Colors.transparent),
              borderRadius: BorderRadius.circular(18),
              border: widget.active
                  ? Border.all(color: Colors.white.withValues(alpha: 0.26))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: widget.expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 190),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.active
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.icon, color: foreground, size: 21),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: widget.expanded
                      ? Padding(
                          key: const ValueKey('label'),
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 13.5,
                              fontWeight: widget.active
                                  ? FontWeight.w900
                                  : FontWeight.w800,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('collapsed')),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.expanded) return item;
    return Tooltip(message: widget.label, child: item);
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({
    required this.expanded,
    required this.showToggle,
    required this.isPinnedOpen,
    required this.onToggle,
  });

  final bool expanded;
  final bool showToggle;
  final bool isPinnedOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
          ),
          child: Image.asset(
            'assets/images/touristrike_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: expanded
              ? const Padding(
                  key: ValueKey('brand-copy'),
                  padding: EdgeInsets.only(left: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TourisTrike',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'City Admin',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xDDEAF4FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('brand-collapsed')),
        ),
        if (expanded && showToggle) ...[
          const Spacer(),
          Tooltip(
            message: isPinnedOpen ? 'Collapse sidebar' : 'Pin sidebar open',
            child: IconButton(
              onPressed: onToggle,
              icon: Icon(
                isPinnedOpen
                    ? Icons.keyboard_double_arrow_left_rounded
                    : Icons.keyboard_double_arrow_right_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SidebarDestination {
  const _SidebarDestination({
    required this.label,
    required this.icon,
    required this.index,
  });

  final String label;
  final IconData icon;
  final int index;
}
