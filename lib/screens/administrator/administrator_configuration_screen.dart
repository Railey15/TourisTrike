import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/auth/app_role.dart';
import 'package:touristrike/core/maintenance/maintenance_settings.dart';

import 'administrator_models.dart';
import 'widgets/system_admin_shared.dart';

typedef AdministratorMaintenanceUpdateCallback =
    Future<MaintenanceSettings> Function(MaintenanceUpdate update);

class AdministratorConfigurationScreen extends StatefulWidget {
  const AdministratorConfigurationScreen({
    super.key,
    required this.data,
    required this.onUpdateMaintenance,
  });

  final AdministratorPortalData data;
  final AdministratorMaintenanceUpdateCallback onUpdateMaintenance;

  @override
  State<AdministratorConfigurationScreen> createState() =>
      _AdministratorConfigurationScreenState();
}

class _AdministratorConfigurationScreenState
    extends State<AdministratorConfigurationScreen> {
  late final TextEditingController _title;
  late final TextEditingController _message;
  late DateTime _startsAt;
  DateTime? _endsAt;
  late bool _indefinite;
  late bool _allowMainTenant;
  bool _saving = false;

  MaintenanceSettings get _settings => widget.data.maintenance;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: _settings.title);
    _message = TextEditingController(text: _settings.message);
    _applySettings(_settings, updateControllers: false);
  }

  @override
  void didUpdateWidget(covariant AdministratorConfigurationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.maintenance.updatedAt != _settings.updatedAt) {
      _applySettings(_settings);
    }
  }

  void _applySettings(
    MaintenanceSettings settings, {
    bool updateControllers = true,
  }) {
    if (updateControllers) {
      _title.text = settings.title;
      _message.text = settings.message;
    }
    final now = DateTime.now();
    _startsAt = (settings.startsAt ?? now).toLocal();
    _endsAt = settings.endsAt?.toLocal() ?? now.add(const Duration(hours: 2));
    _indefinite = settings.indefinite;
    _allowMainTenant = settings.allowMainTenant;
  }

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provincialOffices = widget.data.tenants
        .where((tenant) => tenant.kind == TenantOfficeKind.provincial)
        .length;
    final localOffices = widget.data.tenants
        .where((tenant) => tenant.kind == TenantOfficeKind.cityMunicipal)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        _MaintenanceStatusCard(settings: _settings),
        const SizedBox(height: 16),
        AdministratorPanel(
          title: 'Maintenance Mode',
          subtitle:
              'Configure immediate or scheduled platform-wide maintenance',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('maintenance-title'),
                controller: _title,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Maintenance title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('maintenance-message'),
                controller: _message,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Maintenance message',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (context, constraints) {
                  final start = _DateTimeTile(
                    key: const ValueKey('maintenance-start'),
                    label: 'Start date/time',
                    value: _startsAt,
                    icon: Icons.play_circle_outline_rounded,
                    onTap: _saving ? null : () => _pickDateTime(isStart: true),
                  );
                  final end = _DateTimeTile(
                    key: const ValueKey('maintenance-end'),
                    label: 'Expected end date/time',
                    value: _indefinite ? null : _endsAt,
                    emptyLabel: 'Until further notice',
                    icon: Icons.event_available_outlined,
                    onTap: _saving || _indefinite
                        ? null
                        : () => _pickDateTime(isStart: false),
                  );
                  if (constraints.maxWidth < 720) {
                    return Column(
                      children: [start, const SizedBox(height: 10), end],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: start),
                      const SizedBox(width: 12),
                      Expanded(child: end),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                key: const ValueKey('maintenance-indefinite'),
                contentPadding: EdgeInsets.zero,
                value: _indefinite,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _indefinite = value),
                title: const Text('Until manually disabled'),
                subtitle: const Text(
                  'No automatic end time; an administrator must disable maintenance.',
                ),
              ),
              SwitchListTile.adaptive(
                key: const ValueKey('maintenance-allow-main-tenant'),
                contentPadding: EdgeInsets.zero,
                value: _allowMainTenant,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _allowMainTenant = value),
                title: const Text(
                  'Allow Provincial Administrator access during maintenance',
                ),
                subtitle: const Text(
                  'System Administrators always remain allowed.',
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (!_settings.enabled) ...[
                    FilledButton.icon(
                      key: const ValueKey('maintenance-enable-now'),
                      onPressed: _saving ? null : _enableNow,
                      icon: const Icon(Icons.build_circle_outlined),
                      label: const Text('Enable maintenance now'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('maintenance-schedule'),
                      onPressed: _saving ? null : _schedule,
                      icon: const Icon(Icons.schedule_rounded),
                      label: const Text('Schedule maintenance'),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      key: const ValueKey('maintenance-update'),
                      onPressed: _saving ? null : _update,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Update maintenance'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('maintenance-disable'),
                      onPressed: _saving ? null : _disable,
                      icon: const Icon(Icons.power_settings_new_rounded),
                      label: const Text('Disable Maintenance Mode'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdministratorColors.red,
                      ),
                    ),
                  ],
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
                      value: '${widget.data.countFor(role)}',
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
                    value: '${widget.data.activeLocalTenants}',
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
      ],
    );
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart
        ? _startsAt
        : (_endsAt ?? _startsAt.add(const Duration(hours: 2)));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isStart) {
        _startsAt = value;
        if (!_indefinite && (_endsAt == null || !_endsAt!.isAfter(value))) {
          _endsAt = value.add(const Duration(hours: 2));
        }
      } else {
        _endsAt = value;
      }
    });
  }

  Future<void> _enableNow() async {
    final now = DateTime.now();
    setState(() {
      _startsAt = now;
      if (!_indefinite && (_endsAt == null || !_endsAt!.isAfter(now))) {
        _endsAt = now.add(const Duration(hours: 2));
      }
    });
    await _submit(enabled: true, action: 'enable maintenance now');
  }

  Future<void> _schedule() async {
    if (!_startsAt.isAfter(DateTime.now())) {
      _showError('Choose a future start date/time for scheduled maintenance.');
      return;
    }
    await _submit(enabled: true, action: 'schedule maintenance');
  }

  Future<void> _update() =>
      _submit(enabled: true, action: 'update maintenance settings');

  Future<void> _disable() =>
      _submit(enabled: false, action: 'disable Maintenance Mode');

  Future<void> _submit({required bool enabled, required String action}) async {
    final title = _title.text.trim();
    final message = _message.text.trim();
    if (title.isEmpty || message.isEmpty) {
      _showError('Enter both a maintenance title and message.');
      return;
    }
    if (enabled &&
        !_indefinite &&
        (_endsAt == null || !_endsAt!.isAfter(_startsAt))) {
      _showError('Expected end must be after the maintenance start.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm ${enabled ? 'maintenance change' : 'disable'}'),
        content: Text(
          'Are you sure you want to $action? This changes platform access for users.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('maintenance-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.onUpdateMaintenance(
        MaintenanceUpdate(
          enabled: enabled,
          title: title,
          message: message,
          startsAt: _startsAt,
          endsAt: _indefinite ? null : _endsAt,
          indefinite: _indefinite,
          allowMainTenant: _allowMainTenant,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Maintenance settings saved.'
                : 'Maintenance Mode disabled.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) _showError('Unable to update maintenance: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MaintenanceStatusCard extends StatelessWidget {
  const _MaintenanceStatusCard({required this.settings});

  final MaintenanceSettings settings;

  @override
  Widget build(BuildContext context) {
    final status = settings.status;
    final color = switch (status) {
      MaintenanceSystemStatus.operational => AdministratorColors.green,
      MaintenanceSystemStatus.scheduled => AdministratorColors.amber,
      MaintenanceSystemStatus.active => AdministratorColors.red,
    };
    final label = switch (status) {
      MaintenanceSystemStatus.operational => 'Operational',
      MaintenanceSystemStatus.scheduled => 'Scheduled Maintenance',
      MaintenanceSystemStatus.active => 'Maintenance Mode Active',
    };
    return AdministratorPanel(
      title: 'Current system status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdministratorStatusPill(
            label: label,
            color: color,
            icon: Icons.circle,
          ),
          if (settings.enabled) ...[
            const SizedBox(height: 14),
            Text(
              settings.title,
              style: const TextStyle(
                color: AdministratorColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(settings.message),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _StatusDetail(
                  label: status == MaintenanceSystemStatus.scheduled
                      ? 'Starts at'
                      : 'Started at',
                  value: _format(settings.startsAt),
                ),
                _StatusDetail(
                  label: 'Expected end',
                  value: settings.indefinite
                      ? 'Until further notice'
                      : _format(settings.endsAt),
                ),
                _StatusDetail(
                  label: 'Activated / updated by',
                  value: settings.updatedByName.isEmpty
                      ? 'System Administrator'
                      : settings.updatedByName,
                ),
                _StatusDetail(
                  label: 'Last updated',
                  value: _format(settings.updatedAt),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _format(DateTime? value) => value == null
      ? 'Not set'
      : DateFormat.yMMMd().add_jm().format(value.toLocal());
}

class _StatusDetail extends StatelessWidget {
  const _StatusDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AdministratorColors.muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({
    super.key,
    required this.label,
    required this.value,
    this.emptyLabel = 'Not set',
    required this.icon,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final String emptyLabel;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: AdministratorColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AdministratorColors.blue),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AdministratorColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value == null
                        ? emptyLabel
                        : DateFormat.yMMMd().add_jm().format(value!),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.edit_calendar_outlined, size: 19),
          ],
        ),
      ),
    );
  }
}
