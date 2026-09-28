import 'package:flutter/material.dart';
import 'package:touristrike/core/auth/app_role.dart';

import 'administrator_models.dart';
import 'widgets/system_admin_shared.dart';

class AdministratorConfigurationScreen extends StatelessWidget {
  const AdministratorConfigurationScreen({super.key, required this.data});

  final AdministratorPortalData data;

  @override
  Widget build(BuildContext context) {
    final provincialOffices = data.tenants
        .where((tenant) => tenant.kind == TenantOfficeKind.provincial)
        .length;
    final localOffices = data.tenants
        .where((tenant) => tenant.kind == TenantOfficeKind.cityMunicipal)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final accessModel = AdministratorPanel(
              title: 'Access model',
              subtitle: 'Canonical deployed roles and current user totals',
              child: Column(
                children: [
                  for (final role in AppRole.values)
                    AdministratorLabelValueRow(
                      label: '${role.displayName} (${role.databaseValue})',
                      value: '${data.countFor(role)}',
                      icon: administratorRoleIcon(role),
                    ),
                ],
              ),
            );
            final tenantModel = AdministratorPanel(
              title: 'Tenant structure',
              subtitle: 'Current offices visible to platform oversight',
              child: Column(
                children: [
                  AdministratorLabelValueRow(
                    label: 'Provincial offices',
                    value: '$provincialOffices',
                    icon: Icons.account_balance_outlined,
                  ),
                  AdministratorLabelValueRow(
                    label: 'City/Municipal offices',
                    value: '$localOffices',
                    icon: Icons.location_city_outlined,
                  ),
                  AdministratorLabelValueRow(
                    label: 'Active local offices',
                    value: '${data.activeLocalTenants}',
                    icon: Icons.verified_outlined,
                    color: AdministratorColors.green,
                  ),
                ],
              ),
            );
            if (constraints.maxWidth < 900) {
              return Column(
                children: [
                  accessModel,
                  const SizedBox(height: 16),
                  tenantModel,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: accessModel),
                const SizedBox(width: 16),
                Expanded(child: tenantModel),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const AdministratorPanel(
          title: 'Configuration policy',
          subtitle: 'Safe platform configuration boundary',
          child: _ConfigurationNotice(),
        ),
      ],
    );
  }
}

class _ConfigurationNotice extends StatelessWidget {
  const _ConfigurationNotice();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, color: AdministratorColors.blue),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Role values, tenant boundaries, and platform authorization are enforced by the deployed database schema and application routing. This portal intentionally exposes verified configuration as read-only.',
            style: TextStyle(color: AdministratorColors.muted, height: 1.45),
          ),
        ),
      ],
    );
  }
}
