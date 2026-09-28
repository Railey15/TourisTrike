import 'package:flutter/material.dart';
import 'package:touristrike/core/auth/app_role.dart';

import 'administrator_models.dart';
import 'widgets/system_admin_shared.dart';

class AdministratorSecurityScreen extends StatelessWidget {
  const AdministratorSecurityScreen({super.key, required this.data});

  final AdministratorPortalData data;

  @override
  Widget build(BuildContext context) {
    final authMetadataAccounts = data.accounts
        .where((account) => account.authMetadataAvailable)
        .length;
    final guardOperational = data.healthChecks.any(
      (check) =>
          check.name == 'Authentication and role guard' && check.isOperational,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            AdministratorMetric(
              label: 'Auth metadata available',
              value: '$authMetadataAccounts/${data.accounts.length}',
              icon: Icons.key_outlined,
              color: AdministratorColors.blue,
            ),
            AdministratorMetric(
              label: 'Pending verification',
              value: data.statusCount(
                PlatformAccountStatus.pendingVerification,
              ),
              icon: Icons.mark_email_unread_outlined,
              color: AdministratorColors.amber,
            ),
            AdministratorMetric(
              label: 'Suspended accounts',
              value: data.statusCount(PlatformAccountStatus.suspended),
              icon: Icons.block_outlined,
              color: AdministratorColors.red,
            ),
          ],
        ),
        const SizedBox(height: 18),
        AdministratorPanel(
          title: 'Current administrator session',
          subtitle: 'Authenticated identity and enforced access boundary',
          child: Column(
            children: [
              AdministratorLabelValueRow(
                label: data.profile.name,
                value: data.profile.role.displayName,
                icon: Icons.person_outline_rounded,
              ),
              AdministratorLabelValueRow(
                label: data.profile.email.isEmpty
                    ? 'Authenticated account'
                    : data.profile.email,
                value: guardOperational ? 'Verified' : 'Degraded',
                icon: Icons.shield_outlined,
                color: guardOperational
                    ? AdministratorColors.green
                    : AdministratorColors.amber,
              ),
              AdministratorLabelValueRow(
                label: 'Technical role',
                value: data.profile.role.databaseValue,
                icon: Icons.admin_panel_settings_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdministratorPanel(
          title: 'Security controls',
          subtitle: 'Observed controls for this portal session',
          child: Column(
            children: [
              AdministratorLabelValueRow(
                label: 'Administrator role guard',
                value: guardOperational ? 'Operational' : 'Degraded',
                icon: Icons.verified_user_outlined,
                color: guardOperational
                    ? AdministratorColors.green
                    : AdministratorColors.amber,
              ),
              AdministratorLabelValueRow(
                label: 'Canonical role boundaries',
                value: '${AppRole.values.length} roles',
                icon: Icons.account_tree_outlined,
              ),
              const AdministratorLabelValueRow(
                label: 'Portal operations',
                value: 'Read-only',
                icon: Icons.visibility_outlined,
                color: AdministratorColors.green,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
