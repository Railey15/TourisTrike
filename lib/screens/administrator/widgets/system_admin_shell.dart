import 'package:flutter/material.dart';

import '../administrator_models.dart';
import 'system_admin_header.dart';
import 'system_admin_shared.dart';
import 'system_admin_sidebar.dart';

class SystemAdminShell extends StatelessWidget {
  const SystemAdminShell({
    super.key,
    required this.section,
    required this.profile,
    required this.onSelected,
    required this.onRefresh,
    required this.onSignOut,
    required this.body,
  });

  final AdministratorSection section;
  final AdministratorProfile? profile;
  final ValueChanged<AdministratorSection> onSelected;
  final VoidCallback onRefresh;
  final VoidCallback onSignOut;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdministratorColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 980;
            return Row(
              children: [
                if (desktop)
                  SystemAdminSidebar(
                    section: section,
                    onSelected: onSelected,
                    onSignOut: onSignOut,
                  ),
                Expanded(
                  child: Column(
                    children: [
                      SystemAdminHeader(
                        section: section,
                        profile: profile,
                        onRefresh: onRefresh,
                        onSignOut: onSignOut,
                        compact: !desktop,
                      ),
                      if (!desktop)
                        _CompactNavigation(
                          section: section,
                          onSelected: onSelected,
                        ),
                      Expanded(child: body),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CompactNavigation extends StatelessWidget {
  const _CompactNavigation({required this.section, required this.onSelected});

  final AdministratorSection section;
  final ValueChanged<AdministratorSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        itemCount: AdministratorSection.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = AdministratorSection.values[index];
          return ChoiceChip(
            selected: item == section,
            avatar: Icon(administratorSectionIcon(item), size: 17),
            label: Text(administratorSectionLabel(item)),
            onSelected: (_) => onSelected(item),
          );
        },
      ),
    );
  }
}
