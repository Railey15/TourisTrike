import 'package:flutter/material.dart';

import 'administrator_models.dart';
import 'widgets/system_admin_shared.dart';

class AdministratorIntegrationsScreen extends StatelessWidget {
  const AdministratorIntegrationsScreen({super.key, required this.checks});

  final List<PlatformHealthCheck> checks;

  @override
  Widget build(BuildContext context) {
    final operational = checks.where((check) => check.isOperational).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        AdministratorPanel(
          title: 'Integrations status',
          subtitle:
              'Observed availability from live authenticated backend requests',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  AdministratorMetric(
                    label: 'Operational',
                    value: operational,
                    icon: Icons.check_circle_outline,
                    color: AdministratorColors.green,
                  ),
                  AdministratorMetric(
                    label: 'Degraded',
                    value: checks.length - operational,
                    icon: Icons.warning_amber_rounded,
                    color: AdministratorColors.amber,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              for (final check in checks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _HealthCard(check: check),
                ),
              const SizedBox(height: 2),
              const Text(
                'These checks verify the services used by this portal. They do not replace infrastructure monitoring outside Supabase.',
                style: TextStyle(
                  color: AdministratorColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.check});

  final PlatformHealthCheck check;

  @override
  Widget build(BuildContext context) {
    final color = check.isOperational
        ? AdministratorColors.green
        : AdministratorColors.amber;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        border: Border.all(color: AdministratorColors.line),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            check.isOperational
                ? Icons.check_circle_outline
                : Icons.error_outline,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.name,
                  style: const TextStyle(
                    color: AdministratorColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  check.description,
                  style: const TextStyle(color: AdministratorColors.muted),
                ),
                if (check.detail.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    check.detail,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AdministratorStatusPill(
                label: check.isOperational ? 'Operational' : 'Degraded',
                color: color,
              ),
              const SizedBox(height: 6),
              Text(
                '${check.latency.inMilliseconds} ms',
                style: const TextStyle(
                  color: AdministratorColors.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
