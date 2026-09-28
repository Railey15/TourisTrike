import 'package:flutter/material.dart';
import 'package:touristrike/core/auth/app_role.dart';

import 'administrator_models.dart';
import 'administrator_audit_logs_screen.dart';
import 'widgets/system_admin_shared.dart';

class AdministratorDashboardScreen extends StatelessWidget {
  const AdministratorDashboardScreen({
    super.key,
    required this.data,
  });

  final AdministratorPortalData data;

  @override
  Widget build(BuildContext context) {
    final totalHealthChecks = data.healthChecks.length;
    final operationalChecks = data.operationalHealthChecks;
    final degradedChecks = totalHealthChecks - operationalChecks;
    final healthy =
        totalHealthChecks == 0 || operationalChecks == totalHealthChecks;

    return ColoredBox(
      color: AdministratorColors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 1200
              ? 32.0
              : constraints.maxWidth >= 700
                  ? 24.0
                  : 16.0;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              24,
              horizontalPadding,
              48,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WelcomeCard(
                        profile: data.profile,
                        healthy: healthy,
                        operationalChecks: operationalChecks,
                        totalHealthChecks: totalHealthChecks,
                      ),
                      const SizedBox(height: 22),

                      _SectionIntro(
                        eyebrow: 'OVERVIEW',
                        title: 'Platform at a glance',
                        subtitle:
                            'Monitor account activity, tourism offices, and platform health from one place.',
                      ),
                      const SizedBox(height: 14),

                      _MetricsGrid(
                        data: data,
                        healthy: healthy,
                        degradedChecks: degradedChecks,
                      ),
                      const SizedBox(height: 24),

                      LayoutBuilder(
                        builder: (context, innerConstraints) {
                          final wide = innerConstraints.maxWidth >= 980;

                          final rolePanel = _RoleDistribution(data: data);
                          final healthPanel = _HealthSummary(
                            checks: data.healthChecks,
                          );

                          if (!wide) {
                            return Column(
                              children: [
                                rolePanel,
                                const SizedBox(height: 18),
                                healthPanel,
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: rolePanel,
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                flex: 5,
                                child: healthPanel,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      _RecentActivitySection(
                        data: data,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.profile,
    required this.healthy,
    required this.operationalChecks,
    required this.totalHealthChecks,
  });

  final AdministratorProfile profile;
  final bool healthy;
  final int operationalChecks;
  final int totalHealthChecks;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF102E61),
                Color(0xFF155EEF),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF155EEF).withValues(alpha: 0.16),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              const Positioned(
                right: -48,
                top: -58,
                child: _DecorativeCircle(
                  size: 190,
                  opacity: 0.06,
                ),
              ),
              const Positioned(
                right: 80,
                bottom: -75,
                child: _DecorativeCircle(
                  size: 150,
                  opacity: 0.05,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(
                  compact ? 20 : 26,
                ),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _WelcomeContent(profile: profile),
                          const SizedBox(height: 20),
                          _WelcomeStatusCard(
                            healthy: healthy,
                            operationalChecks: operationalChecks,
                            totalHealthChecks: totalHealthChecks,
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _WelcomeContent(profile: profile),
                          ),
                          const SizedBox(width: 24),
                          _WelcomeStatusCard(
                            healthy: healthy,
                            operationalChecks: operationalChecks,
                            totalHealthChecks: totalHealthChecks,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WelcomeContent extends StatelessWidget {
  const _WelcomeContent({
    required this.profile,
  });

  final AdministratorProfile profile;

  @override
  Widget build(BuildContext context) {
    final name = profile.name.trim().isEmpty
        ? 'System Administrator'
        : profile.name.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                size: 15,
                color: Color(0xFFD8E6FF),
              ),
              SizedBox(width: 6),
              Text(
                'SYSTEM ADMINISTRATION',
                style: TextStyle(
                  color: Color(0xFFD8E6FF),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Welcome back, $name',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 650),
          child: Text(
            'Review platform activity, account distribution, tenant status, '
            'and system health across TourisTrike.',
            style: TextStyle(
              color: Color(0xFFDDE8FF),
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (profile.email.isNotEmpty) ...[
          const SizedBox(height: 15),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.alternate_email_rounded,
                size: 15,
                color: Color(0xFFC8DAFC),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  profile.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFC8DAFC),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _WelcomeStatusCard extends StatelessWidget {
  const _WelcomeStatusCard({
    required this.healthy,
    required this.operationalChecks,
    required this.totalHealthChecks,
  });

  final bool healthy;
  final int operationalChecks;
  final int totalHealthChecks;

  @override
  Widget build(BuildContext context) {
    final statusColor = healthy
        ? const Color(0xFF6CE9A6)
        : const Color(0xFFFEC84B);

    return Container(
      constraints: const BoxConstraints(
        minWidth: 220,
        maxWidth: 270,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdministratorStatusPill(
            label: healthy
                ? 'All systems operational'
                : 'Attention required',
            color: healthy
                ? AdministratorColors.green
                : AdministratorColors.amber,
            icon: healthy
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            inverted: true,
          ),
          const SizedBox(height: 15),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$operationalChecks',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: 4,
                  bottom: 2,
                ),
                child: Text(
                  '/ $totalHealthChecks',
                  style: const TextStyle(
                    color: Color(0xFFDDE8FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Operational health checks',
            style: TextStyle(
              color: Color(0xFFDDE8FF),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: totalHealthChecks == 0
                  ? 1
                  : operationalChecks / totalHealthChecks,
              backgroundColor: Colors.white.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation<Color>(
                statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DecorativeCircle extends StatelessWidget {
  const _DecorativeCircle({
    required this.size,
    required this.opacity,
  });

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: AdministratorColors.blue,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            color: AdministratorColors.ink,
            fontSize: 20,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: AdministratorColors.muted,
            fontSize: 12.5,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.data,
    required this.healthy,
    required this.degradedChecks,
  });

  final AdministratorPortalData data;
  final bool healthy;
  final int degradedChecks;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;

        final columns = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 720
                ? 2
                : 1;

        final width =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        final metrics = <Widget>[
          _DashboardMetricCard(
            label: 'Total accounts',
            value: '${data.accounts.length}',
            helper: 'Registered platform users',
            icon: Icons.people_alt_outlined,
            color: AdministratorColors.blue,
          ),
          _DashboardMetricCard(
            label: 'Active accounts',
            value: '${data.statusCount(PlatformAccountStatus.active)}',
            helper: 'Currently active accounts',
            icon: Icons.verified_user_outlined,
            color: AdministratorColors.green,
          ),
          _DashboardMetricCard(
            label: 'Tourism offices',
            value: '${data.activeLocalTenants}',
            helper: 'Active local tourism offices',
            icon: Icons.location_city_outlined,
            color: const Color(0xFF7A5AF8),
          ),
          _DashboardMetricCard(
            label: 'System health',
            value: healthy ? 'Healthy' : '$degradedChecks issue(s)',
            helper: healthy
                ? 'All monitored checks passed'
                : 'Review integration status',
            icon: healthy
                ? Icons.monitor_heart_outlined
                : Icons.warning_amber_rounded,
            color: healthy
                ? AdministratorColors.green
                : AdministratorColors.amber,
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: metric,
              ),
          ],
        );
      },
    );
  }
}

class _DashboardMetricCard extends StatelessWidget {
  const _DashboardMetricCard({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AdministratorColors.line,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 22,
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AdministratorColors.ink,
              fontSize: 24,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AdministratorColors.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            helper,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AdministratorColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleDistribution extends StatelessWidget {
  const _RoleDistribution({
    required this.data,
  });

  final AdministratorPortalData data;

  @override
  Widget build(BuildContext context) {
    final totalAccounts = data.accounts.length;

    return AdministratorPanel(
      title: 'Accounts by role',
      subtitle: 'Distribution across TourisTrike access levels',
      child: Column(
        children: [
          for (var index = 0; index < AppRole.values.length; index++) ...[
            _RoleDistributionItem(
              role: AppRole.values[index],
              count: data.countFor(AppRole.values[index]),
              total: totalAccounts,
            ),
            if (index < AppRole.values.length - 1)
              const SizedBox(height: 15),
          ],
        ],
      ),
    );
  }
}

class _RoleDistributionItem extends StatelessWidget {
  const _RoleDistributionItem({
    required this.role,
    required this.count,
    required this.total,
  });

  final AppRole role;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : count / total;
    final color = _roleColor(role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                administratorRoleIcon(role),
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.displayName,
                    style: const TextStyle(
                      color: AdministratorColors.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    total == 0
                        ? 'No accounts'
                        : '${(ratio * 100).toStringAsFixed(0)}% of all accounts',
                    style: const TextStyle(
                      color: AdministratorColors.muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: ratio.clamp(0.0, 1.0),
            backgroundColor: const Color(0xFFF0F3F8),
            valueColor: AlwaysStoppedAnimation<Color>(
              color,
            ),
          ),
        ),
      ],
    );
  }
}

class _HealthSummary extends StatelessWidget {
  const _HealthSummary({
    required this.checks,
  });

  final List<PlatformHealthCheck> checks;

  @override
  Widget build(BuildContext context) {
    final operational = checks.where((check) => check.isOperational).length;
    final healthy = checks.isEmpty || operational == checks.length;

    return AdministratorPanel(
      title: 'System & integrations',
      subtitle: 'Live availability from this authenticated session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: healthy
                  ? AdministratorColors.green.withValues(alpha: 0.06)
                  : AdministratorColors.amber.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: healthy
                    ? AdministratorColors.green.withValues(alpha: 0.16)
                    : AdministratorColors.amber.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: healthy
                        ? AdministratorColors.green.withValues(alpha: 0.12)
                        : AdministratorColors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    healthy
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                    color: healthy
                        ? AdministratorColors.green
                        : AdministratorColors.amber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        healthy
                            ? 'All monitored services are operational'
                            : 'Some services need attention',
                        style: const TextStyle(
                          color: AdministratorColors.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$operational of ${checks.length} checks passed',
                        style: const TextStyle(
                          color: AdministratorColors.muted,
                          fontSize: 10.8,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (checks.isEmpty)
            const _DashboardEmptyState(
              icon: Icons.monitor_heart_outlined,
              title: 'No health checks available',
              message:
                  'Integration health information is not available for this session.',
            )
          else
            for (var index = 0; index < checks.length; index++) ...[
              _HealthItem(check: checks[index]),
              if (index < checks.length - 1)
                const Divider(
                  height: 18,
                  color: AdministratorColors.line,
                ),
            ],
        ],
      ),
    );
  }
}

class _HealthItem extends StatelessWidget {
  const _HealthItem({
    required this.check,
  });

  final PlatformHealthCheck check;

  @override
  Widget build(BuildContext context) {
    final color = check.isOperational
        ? AdministratorColors.green
        : AdministratorColors.amber;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            check.isOperational
                ? Icons.check_rounded
                : Icons.priority_high_rounded,
            size: 18,
            color: color,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      check.name,
                      style: const TextStyle(
                        color: AdministratorColors.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _HealthStatusBadge(
                    operational: check.isOperational,
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                check.description,
                style: const TextStyle(
                  color: AdministratorColors.muted,
                  fontSize: 10.8,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (check.detail.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  check.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HealthStatusBadge extends StatelessWidget {
  const _HealthStatusBadge({
    required this.operational,
  });

  final bool operational;

  @override
  Widget build(BuildContext context) {
    final color = operational
        ? AdministratorColors.green
        : AdministratorColors.amber;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        operational ? 'Operational' : 'Degraded',
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({
    required this.data,
  });

  final AdministratorPortalData data;

  @override
  Widget build(BuildContext context) {
    final recentEntries = data.auditEntries
        .take(8)
        .toList(growable: false);

    return AdministratorPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent platform activity',
                    style: TextStyle(
                      color: AdministratorColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Latest auditable actions recorded across TourisTrike',
                    style: TextStyle(
                      color: AdministratorColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AdministratorColors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      size: 15,
                      color: AdministratorColors.blue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${recentEntries.length} recent',
                      style: const TextStyle(
                        color: AdministratorColors.blue,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (recentEntries.isEmpty)
            const _DashboardEmptyState(
              icon: Icons.history_toggle_off_rounded,
              title: 'No recent activity',
              message:
                  'Platform activity will appear here when auditable actions are recorded.',
            )
          else
            AdministratorAuditList(
              entries: recentEntries,
              actorNames: data.accountNamesById,
            ),
        ],
      ),
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 28,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AdministratorColors.line,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AdministratorColors.blue.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: AdministratorColors.blue,
              size: 23,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AdministratorColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdministratorColors.muted,
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _roleColor(AppRole role) {
  return switch (role) {
    AppRole.administrator => const Color(0xFF155EEF),
    AppRole.mainTenant => const Color(0xFF7A5AF8),
    AppRole.subtenant => const Color(0xFF0BA5EC),
    AppRole.driver => const Color(0xFF079455),
    AppRole.tourist => const Color(0xFFF79009),
  };
}