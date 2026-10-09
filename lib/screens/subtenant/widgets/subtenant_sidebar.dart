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
    _SidebarDestination(
      label: 'Disputes',
      icon: Icons.report_problem_rounded,
      index: 7,
    ),
    _SidebarDestination(
      label: 'Complaints',
      icon: Icons.gavel_outlined,
      index: 8,
    ),
  ];

  bool get _effectiveExpanded {
    if (widget.asDrawer) return true;
    if (widget.compact) return false;
    return _expanded;
  }

  bool get _canToggle {
    return !widget.asDrawer && !widget.compact;
  }

  void _toggleSidebar() {
    if (!_canToggle) return;

    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final expanded = _effectiveExpanded;

    final width = widget.asDrawer
        ? 292.0
        : expanded
        ? 258.0
        : 86.0;

    final sidebar = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: width,
      margin: widget.asDrawer ? EdgeInsets.zero : const EdgeInsets.all(12),
      padding: EdgeInsets.fromLTRB(
        expanded ? 10 : 8,
        14,
        expanded ? 10 : 8,
        14,
      ),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentExpanded = expanded && constraints.maxWidth >= 180;
          return Column(
            children: [
              _SidebarBrand(
                expanded: contentExpanded,
                showToggle: _canToggle,
                onToggle: _toggleSidebar,
              ),
              SizedBox(height: contentExpanded ? 22 : 14),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  itemCount: _destinations.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    final item = _destinations[index];
                    return SidebarNavItem(
                      label: item.label,
                      icon: item.icon,
                      expanded: contentExpanded,
                      active: widget.currentIndex == item.index,
                      onTap: () => widget.onDestinationSelected(item.index),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SidebarNavItem(
                label: 'Logout',
                icon: Icons.logout_rounded,
                expanded: contentExpanded,
                active: false,
                danger: true,
                onTap: widget.onLogout,
              ),
            ],
          );
        },
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

// ============================================================
// SIDEBAR NAVIGATION ITEM
// ============================================================

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
      onEnter: (_) {
        setState(() {
          _hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          _hovered = false;
        });
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            height: 52,
            width: double.infinity,
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
            child: widget.expanded
                ? Row(
                    children: [
                      _SidebarNavIcon(
                        icon: widget.icon,
                        foreground: foreground,
                        active: widget.active,
                      ),

                      const SizedBox(width: 12),

                      Expanded(
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
                      ),
                    ],
                  )
                : Center(
                    child: _SidebarNavIcon(
                      icon: widget.icon,
                      foreground: foreground,
                      active: widget.active,
                    ),
                  ),
          ),
        ),
      ),
    );

    if (widget.expanded) {
      return item;
    }

    return Tooltip(message: widget.label, child: item);
  }
}

// ============================================================
// SIDEBAR NAVIGATION ICON
// ============================================================

class _SidebarNavIcon extends StatelessWidget {
  const _SidebarNavIcon({
    required this.icon,
    required this.foreground,
    required this.active,
  });

  final IconData icon;
  final Color foreground;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: foreground, size: 21),
    );
  }
}

// ============================================================
// SIDEBAR BRAND
// ============================================================

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({
    required this.expanded,
    required this.showToggle,
    required this.onToggle,
  });

  final bool expanded;
  final bool showToggle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SidebarLogo(),

            if (showToggle) ...[
              const SizedBox(height: 8),

              Tooltip(
                message: 'Expand sidebar',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(10),
                    child: const SizedBox(
                      width: 38,
                      height: 28,
                      child: Center(
                        child: Icon(
                          Icons.keyboard_double_arrow_right_rounded,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Row(
        children: [
          const _SidebarLogo(),

          const SizedBox(width: 10),

          const Expanded(child: _SidebarBrandCopy()),

          if (showToggle) ...[
            const SizedBox(width: 2),

            Tooltip(
              message: 'Collapse sidebar',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(10),
                  child: const SizedBox(
                    width: 28,
                    height: 38,
                    child: Center(
                      child: Icon(
                        Icons.keyboard_double_arrow_left_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// SIDEBAR LOGO
// ============================================================

class _SidebarLogo extends StatelessWidget {
  const _SidebarLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Image.network(
        'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/logo1.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) {
          return const Icon(
            Icons.admin_panel_settings_rounded,
            color: Colors.white,
          );
        },
      ),
    );
  }
}

// ============================================================
// SIDEBAR BRAND COPY
// ============================================================

class _SidebarBrandCopy extends StatelessWidget {
  const _SidebarBrandCopy();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
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
          'City/Municipal Administrator',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Color(0xDDEAF4FF),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// DESTINATION MODEL
// ============================================================

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
