import 'package:flutter/material.dart';

import 'administrator_models.dart';
import 'widgets/system_admin_shared.dart';

class AdministratorTenantsScreen extends StatefulWidget {
  const AdministratorTenantsScreen({super.key, required this.tenants});

  final List<TenantOfficeSummary> tenants;

  @override
  State<AdministratorTenantsScreen> createState() =>
      _AdministratorTenantsScreenState();
}

class _AdministratorTenantsScreenState
    extends State<AdministratorTenantsScreen> {
  final _search = TextEditingController();
  TenantOfficeKind? _kind;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenants = widget.tenants
        .where(
          (tenant) =>
              tenant.matches(_search.text) &&
              (_kind == null || tenant.kind == _kind),
        )
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        AdministratorPanel(
          title: 'Tenant directory',
          subtitle:
              'Read-only organization, assignment, and activation oversight',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdministratorFilterBar(
                search: _search,
                hint: 'Search office, locality, contact, or account ID',
                onChanged: (_) => setState(() {}),
                filters: [
                  AdministratorDropdownFilter<TenantOfficeKind>(
                    value: _kind,
                    hint: 'All tenant types',
                    values: TenantOfficeKind.values,
                    label: (value) => switch (value) {
                      TenantOfficeKind.provincial => 'Provincial office',
                      TenantOfficeKind.cityMunicipal => 'City/Municipal office',
                    },
                    onChanged: (value) => setState(() => _kind = value),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (tenants.isEmpty)
                const AdministratorEmptyState(
                  icon: Icons.location_city_outlined,
                  title: 'No matching tenant offices',
                  message: 'Adjust the search or tenant type filter.',
                )
              else
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final tenant in tenants) _TenantCard(tenant: tenant),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.tenant});

  final TenantOfficeSummary tenant;

  @override
  Widget build(BuildContext context) {
    final active = tenant.isActive;
    return SizedBox(
      width: 340,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: AdministratorColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FF),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    tenant.kind == TenantOfficeKind.provincial
                        ? Icons.account_balance_rounded
                        : Icons.location_city_rounded,
                    color: AdministratorColors.blue,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tenant.officeName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AdministratorColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        tenant.scopeLabel,
                        style: const TextStyle(
                          color: AdministratorColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                AdministratorStatusPill(
                  label: administratorTitleCase(tenant.statusLabel),
                  color: active
                      ? AdministratorColors.green
                      : AdministratorColors.amber,
                ),
              ],
            ),
            const SizedBox(height: 14),
            AdministratorDetailLine(
              icon: Icons.map_outlined,
              value: [
                tenant.city,
                tenant.province,
              ].where((part) => part.isNotEmpty).join(', '),
            ),
            AdministratorDetailLine(
              icon: Icons.person_outline_rounded,
              value: tenant.contactPerson,
            ),
            AdministratorDetailLine(
              icon: Icons.email_outlined,
              value: tenant.email,
            ),
            AdministratorDetailLine(
              icon: Icons.update_rounded,
              value: 'Updated ${administratorDateTime(tenant.updatedAt)}',
            ),
          ],
        ),
      ),
    );
  }
}
