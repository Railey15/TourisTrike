import 'package:flutter/material.dart';

import '../administrator_models.dart';
import 'system_admin_shared.dart';

class SystemAdminHeader extends StatelessWidget {
  const SystemAdminHeader({
    super.key,
    required this.section,
    required this.profile,
    required this.onRefresh,
    required this.onSignOut,
    required this.compact,
  });

  final AdministratorSection section;
  final AdministratorProfile? profile;
  final VoidCallback onRefresh;
  final VoidCallback onSignOut;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 18 : 28, 20, 20, 16),
      decoration: const BoxDecoration(
        color: AdministratorColors.surface,
        border: Border(bottom: BorderSide(color: AdministratorColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  administratorSectionLabel(section),
                  style: const TextStyle(
                    color: AdministratorColors.ink,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  administratorSectionSubtitle(section),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AdministratorColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh platform data',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (profile != null) ...[
            const SizedBox(width: 8),
            _AccountMenu(profile: profile!, onSignOut: onSignOut),
          ] else if (compact)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: CircleAvatar(
                radius: 18,
                child: Icon(Icons.person_outline_rounded, size: 19),
              ),
            ),
        ],
      ),
    );
  }
}

enum _AdministratorAccountAction { profile, signOut }

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.profile, required this.onSignOut});

  final AdministratorProfile profile;
  final VoidCallback onSignOut;

  Future<void> _showProfile(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account profile'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: const Color(0xFFE8F0FF),
                child: Text(
                  profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: AdministratorColors.blue,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ProfileValue(label: 'Name', value: profile.name),
              _ProfileValue(
                label: 'Email',
                value: profile.email.isEmpty ? 'Unavailable' : profile.email,
              ),
              _ProfileValue(label: 'Role', value: profile.role.displayName),
              _ProfileValue(
                label: 'Technical role',
                value: profile.role.databaseValue,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return PopupMenuButton<_AdministratorAccountAction>(
      key: const ValueKey('system-admin-account-menu'),
      tooltip: 'Account menu',
      onSelected: (value) {
        switch (value) {
          case _AdministratorAccountAction.profile:
            _showProfile(context);
          case _AdministratorAccountAction.signOut:
            onSignOut();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _AdministratorAccountAction.profile,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_outline_rounded),
            title: Text('Account profile'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _AdministratorAccountAction.signOut,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded),
            title: Text('Sign out'),
          ),
        ),
      ],
      child: Container(
        padding: EdgeInsets.fromLTRB(6, 5, compact ? 6 : 12, 5),
        decoration: BoxDecoration(
          border: Border.all(color: AdministratorColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: const Color(0xFFE8F0FF),
              child: Text(
                profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                style: const TextStyle(
                  color: AdministratorColors.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 9),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      profile.role.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdministratorColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.expand_more_rounded, size: 19),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileValue extends StatelessWidget {
  const _ProfileValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: AdministratorColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
