import 'package:flutter/material.dart';

import 'administrator_models.dart';
import 'widgets/system_admin_shared.dart';

class AdministratorAuditLogsScreen extends StatefulWidget {
  const AdministratorAuditLogsScreen({
    super.key,
    required this.entries,
    required this.actorNames,
  });

  final List<PlatformAuditEntry> entries;
  final Map<String, String> actorNames;

  @override
  State<AdministratorAuditLogsScreen> createState() =>
      _AdministratorAuditLogsScreenState();
}

class _AdministratorAuditLogsScreenState
    extends State<AdministratorAuditLogsScreen> {
  final _search = TextEditingController();
  String? _table;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tables =
        widget.entries
            .map((entry) => entry.tableName)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final entries = widget.entries
        .where((entry) {
          return entry.matches(
                _search.text,
                actorName: widget.actorNames[entry.actorId] ?? '',
              ) &&
              (_table == null || entry.tableName == _table);
        })
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        AdministratorPanel(
          title: 'Audit logs',
          subtitle: 'Latest recorded platform and administrative actions',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdministratorFilterBar(
                search: _search,
                hint: 'Search action, actor, table, record, or description',
                onChanged: (_) => setState(() {}),
                filters: [
                  AdministratorDropdownFilter<String>(
                    value: _table,
                    hint: 'All sources',
                    values: tables,
                    label: administratorTitleCase,
                    onChanged: (value) => setState(() => _table = value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${entries.length} of ${widget.entries.length} events',
                style: const TextStyle(
                  color: AdministratorColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              AdministratorAuditList(
                entries: entries,
                actorNames: widget.actorNames,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AdministratorAuditList extends StatelessWidget {
  const AdministratorAuditList({
    super.key,
    required this.entries,
    required this.actorNames,
  });

  final List<PlatformAuditEntry> entries;
  final Map<String, String> actorNames;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const AdministratorEmptyState(
        icon: Icons.fact_check_outlined,
        title: 'No audit events found',
        message: 'No events match the current filters.',
      );
    }
    return Column(
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.history_rounded,
                color: AdministratorColors.blue,
              ),
            ),
            title: Text(
              administratorTitleCase(entries[index].action),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              administratorAuditSubtitle(
                entries[index],
                actorNames[entries[index].actorId] ?? '',
              ),
            ),
            trailing: Text(
              administratorDateTime(entries[index].createdAt),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AdministratorColors.muted,
                fontSize: 12,
              ),
            ),
          ),
          if (index < entries.length - 1)
            const Divider(height: 1, color: AdministratorColors.line),
        ],
      ],
    );
  }
}
