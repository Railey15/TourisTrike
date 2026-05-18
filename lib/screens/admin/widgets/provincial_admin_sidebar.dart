import 'package:flutter/material.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class ProvincialAdminSidebar extends StatelessWidget {
  const ProvincialAdminSidebar({
    super.key,
    required this.current,
    required this.onDestinationSelected,
    required this.onLogout,
    this.compact = false,
    this.onToggleCompact,
  });

  final ProvincialAdminDestination current;
  final ValueChanged<ProvincialAdminDestination> onDestinationSelected;
  final VoidCallback onLogout;
  final bool compact;
  final VoidCallback? onToggleCompact;

  static Drawer drawer({
    required ProvincialAdminDestination current,
    required ValueChanged<ProvincialAdminDestination> onDestinationSelected,
    required VoidCallback onLogout,
  }) {
    return Drawer(
      width: 292,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ProvincialAdminSidebar(
            current: current,
            onDestinationSelected: onDestinationSelected,
            onLogout: onLogout,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: compact ? 88 : 270,
      margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      decoration: BoxDecoration(
        gradient: ProvincialAdminColors.gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: ProvincialAdminColors.deepBlue.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, 16, compact ? 12 : 10, 10),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                  ),
                  child: const Icon(
                    Icons.account_balance_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  const Expanded(
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
                        SizedBox(height: 3),
                        Text(
                          'Provincial Admin',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFFDCEBFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onToggleCompact != null)
                    IconButton(
                      tooltip: 'Collapse sidebar',
                      onPressed: onToggleCompact,
                      icon: const Icon(
                        Icons.keyboard_double_arrow_left_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (compact && onToggleCompact != null)
            IconButton(
              tooltip: 'Expand sidebar',
              onPressed: onToggleCompact,
              icon: const Icon(
                Icons.keyboard_double_arrow_right_rounded,
                color: Colors.white,
              ),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: provincialAdminNavItems.map((item) {
                return _SidebarTile(
                  item: item,
                  compact: compact,
                  active: item.destination == current,
                  onTap: () => onDestinationSelected(item.destination),
                );
              }).toList(growable: false),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
            child: _LogoutTile(compact: compact, onLogout: onLogout),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.compact,
    required this.active,
    required this.onTap,
  });

  final ProvincialAdminNavItem item;
  final bool compact;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 52,
      margin: const EdgeInsets.only(bottom: 7),
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 14),
      decoration: BoxDecoration(
        color: active ? Colors.white.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: active
            ? Border.all(color: Colors.white.withValues(alpha: 0.24))
            : null,
      ),
      child: Row(
        mainAxisAlignment: compact
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: Colors.white, size: 20),
          ),
          if (!compact) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: compact ? item.label : '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: content,
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.compact, required this.onLogout});

  final bool compact;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onLogout,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 52,
        padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: compact
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
            if (!compact) ...[
              const SizedBox(width: 12),
              const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
