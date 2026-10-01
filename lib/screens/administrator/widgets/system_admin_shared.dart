import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/auth/app_role.dart';

import '../administrator_models.dart';

enum AdministratorSection {
  overview,
  accounts,
  tenants,
  configuration,
  integrations,
  security,
  developerTools,
  audit,
}

abstract final class AdministratorColors {
  static const background = Color(0xFFF4F7FB);
  static const surface = Colors.white;
  static const sidebar = Color(0xFF102A56);
  static const sidebarSelected = Color(0xFF235096);
  static const blue = Color(0xFF155EEF);
  static const ink = Color(0xFF172B4D);
  static const muted = Color(0xFF667085);
  static const line = Color(0xFFE4E7EC);
  static const green = Color(0xFF079455);
  static const amber = Color(0xFFDC6803);
  static const red = Color(0xFFD92D20);
}

class AdministratorFilterBar extends StatelessWidget {
  const AdministratorFilterBar({
    super.key,
    required this.search,
    required this.hint,
    required this.onChanged,
    required this.filters,
  });

  final TextEditingController search;
  final String hint;
  final ValueChanged<String> onChanged;
  final List<Widget> filters;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final searchWidth = compact ? constraints.maxWidth : 390.0;
        final filterWidth = compact ? constraints.maxWidth : 190.0;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: searchWidth,
              child: TextField(
                controller: search,
                onChanged: onChanged,
                decoration: InputDecoration(
                  hintText: hint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ),
            for (final filter in filters)
              SizedBox(width: filterWidth, child: filter),
          ],
        );
      },
    );
  }
}

class AdministratorDropdownFilter<T> extends StatelessWidget {
  const AdministratorDropdownFilter({
    super.key,
    required this.value,
    required this.hint,
    required this.values,
    required this.label,
    required this.onChanged,
  });

  final T? value;
  final String hint;
  final List<T> values;
  final String Function(T value) label;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AdministratorColors.line),
        borderRadius: BorderRadius.circular(11),
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: true,
          hint: Text(hint),
          items: [
            DropdownMenuItem<T?>(value: null, child: Text(hint)),
            ...values.map(
              (item) =>
                  DropdownMenuItem<T?>(value: item, child: Text(label(item))),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class AdministratorMetric extends StatelessWidget {
  const AdministratorMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final Object value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: AdministratorPanel(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: const TextStyle(
                      color: AdministratorColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 2,
                    style: const TextStyle(
                      color: AdministratorColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdministratorPanel extends StatelessWidget {
  const AdministratorPanel({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
  });

  final String? title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdministratorColors.surface,
        border: Border.all(color: AdministratorColors.line),
        borderRadius: BorderRadius.circular(16),
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
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                color: AdministratorColors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: AdministratorColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

class AdministratorLabelValueRow extends StatelessWidget {
  const AdministratorLabelValueRow({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AdministratorColors.blue,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class AdministratorStatusPill extends StatelessWidget {
  const AdministratorStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.inverted = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final foreground = inverted ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: inverted
            ? Colors.white.withValues(alpha: 0.14)
            : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdministratorAccountStatusBadge extends StatelessWidget {
  const AdministratorAccountStatusBadge({super.key, required this.status});

  final PlatformAccountStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      PlatformAccountStatus.active => AdministratorColors.green,
      PlatformAccountStatus.pendingVerification => AdministratorColors.amber,
      PlatformAccountStatus.suspended => AdministratorColors.red,
      PlatformAccountStatus.unknown => AdministratorColors.muted,
    };
    return AdministratorStatusPill(
      label: administratorAccountStatusLabel(status),
      color: color,
    );
  }
}

class AdministratorInlineDetail extends StatelessWidget {
  const AdministratorInlineDetail({
    super.key,
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AdministratorColors.muted),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: AdministratorColors.muted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class AdministratorDetailLine extends StatelessWidget {
  const AdministratorDetailLine({
    super.key,
    required this.icon,
    required this.value,
  });

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AdministratorColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AdministratorColors.muted,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdministratorLoadingState extends StatelessWidget {
  const AdministratorLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class AdministratorEmptyState extends StatelessWidget {
  const AdministratorEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AdministratorColors.muted),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: AdministratorColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AdministratorColors.muted),
          ),
        ],
      ),
    );
  }
}

class AdministratorErrorState extends StatelessWidget {
  const AdministratorErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: AdministratorColors.red,
            ),
            const SizedBox(height: 12),
            const Text(
              'Unable to load System Administrator data',
              style: TextStyle(
                color: AdministratorColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

String administratorSectionLabel(AdministratorSection section) =>
    switch (section) {
      AdministratorSection.overview => 'Dashboard',
      AdministratorSection.accounts => 'Users & Roles',
      AdministratorSection.tenants => 'Tenant Directory',
      AdministratorSection.configuration => 'System Configuration',
      AdministratorSection.integrations => 'Integrations',
      AdministratorSection.security => 'Security',
      AdministratorSection.developerTools => 'Developer Tools',
      AdministratorSection.audit => 'Audit Logs',
    };

String administratorSectionSubtitle(AdministratorSection section) =>
    switch (section) {
      AdministratorSection.overview =>
        'Platform account, tenant, activity, and service summary',
      AdministratorSection.accounts =>
        'Inspect role assignment, verification, and account activity',
      AdministratorSection.tenants =>
        'Inspect provincial and city/municipal office identity and status',
      AdministratorSection.configuration =>
        'Manage maintenance mode and review platform configuration',
      AdministratorSection.integrations =>
        'Review live availability checks for administrator data services',
      AdministratorSection.security =>
        'Review authentication, account status, and access boundaries',
      AdministratorSection.developerTools =>
        'Authorize narrow, time-limited booking test sessions',
      AdministratorSection.audit =>
        'Search the latest recorded platform and administrative events',
    };

IconData administratorSectionIcon(AdministratorSection section) =>
    switch (section) {
      AdministratorSection.overview => Icons.dashboard_outlined,
      AdministratorSection.accounts => Icons.manage_accounts_outlined,
      AdministratorSection.tenants => Icons.account_balance_outlined,
      AdministratorSection.configuration => Icons.tune_outlined,
      AdministratorSection.integrations => Icons.hub_outlined,
      AdministratorSection.security => Icons.security_outlined,
      AdministratorSection.developerTools => Icons.science_outlined,
      AdministratorSection.audit => Icons.fact_check_outlined,
    };

IconData administratorRoleIcon(AppRole role) => switch (role) {
  AppRole.administrator => Icons.admin_panel_settings_outlined,
  AppRole.mainTenant => Icons.account_balance_outlined,
  AppRole.subtenant => Icons.location_city_outlined,
  AppRole.driver => Icons.electric_rickshaw_outlined,
  AppRole.tourist => Icons.luggage_outlined,
};

String administratorAccountStatusLabel(PlatformAccountStatus status) =>
    switch (status) {
      PlatformAccountStatus.active => 'Active',
      PlatformAccountStatus.pendingVerification => 'Pending verification',
      PlatformAccountStatus.suspended => 'Suspended',
      PlatformAccountStatus.unknown => 'Unavailable',
    };

String administratorAccountLocation(PlatformAccountSummary account) {
  final value = [
    account.city,
    account.province,
  ].where((part) => part.isNotEmpty).join(', ');
  return value.isEmpty ? 'Not assigned' : value;
}

String administratorAuditSubtitle(PlatformAuditEntry entry, String actorName) {
  final source = administratorTitleCase(entry.tableName);
  final actor = actorName.isEmpty
      ? (entry.actorId.isEmpty ? 'System' : entry.actorId)
      : actorName;
  final description = entry.description.trim();
  return '$actor • $source${description.isEmpty ? '' : ' — $description'}';
}

String administratorDate(DateTime? value) {
  if (value == null) return 'Unavailable';
  return DateFormat.yMMMd().format(value.toLocal());
}

String administratorDateTime(DateTime? value) {
  if (value == null) return 'Unavailable';
  return DateFormat.yMMMd().add_jm().format(value.toLocal());
}

String administratorTitleCase(String value) {
  final normalized = value.replaceAll('_', ' ').trim();
  if (normalized.isEmpty) return 'Unknown';
  return normalized
      .split(RegExp(r'\s+'))
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}
