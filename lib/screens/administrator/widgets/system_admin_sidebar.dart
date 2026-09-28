import 'package:flutter/material.dart';

import 'system_admin_shared.dart';

class SystemAdminSidebar extends StatelessWidget {
  const SystemAdminSidebar({
    super.key,
    required this.section,
    required this.onSelected,
    required this.onSignOut,
  });

  final AdministratorSection section;
  final ValueChanged<AdministratorSection> onSelected;
  final VoidCallback onSignOut;

  static const double _itemRadius = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 272,
      color: AdministratorColors.sidebar,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              _BrandMark(),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TourisTrike',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'System Administrator',
                      style: TextStyle(
                        color: Color(0xFFBBD0F5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 34),

          for (final item in AdministratorSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SidebarItem(
                item: item,
                isSelected: item == section,
                onTap: () => onSelected(item),
              ),
            ),

          const Spacer(),

          const _ReadOnlyNotice(),

          const SizedBox(height: 12),

          TextButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_itemRadius),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final AdministratorSection item;
  final bool isSelected;
  final VoidCallback onTap;

  static const double _radius = 12;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(_radius);

    return Material(
      color: isSelected
          ? AdministratorColors.sidebarSelected
          : Colors.transparent,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        hoverColor: Colors.white.withValues(alpha: 0.07),
        highlightColor: Colors.white.withValues(alpha: 0.05),
        splashColor: Colors.white.withValues(alpha: 0.08),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 52,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            borderRadius: borderRadius,
          ),
          child: Row(
            children: [
              Icon(
                administratorSectionIcon(item),
                color: Colors.white,
                size: 22,
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Text(
                  administratorSectionLabel(item),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.hub_rounded,
        color: Colors.white,
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            color: Color(0xFFBBD0F5),
            size: 18,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Platform oversight & account controls',
              style: TextStyle(
                color: Color(0xFFDBE8FF),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}