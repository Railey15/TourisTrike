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
    final tables = widget.entries
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
          subtitle: 'Review recorded platform and administrative actions',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdministratorFilterBar(
                search: _search,
                hint: 'Search activity, actor, source, or description',
                onChanged: (_) => setState(() {}),
                filters: [
                  AdministratorDropdownFilter<String>(
                    value: _table,
                    hint: 'All sources',
                    values: tables,
                    label: _sourceLabel,
                    onChanged: (value) => setState(() => _table = value),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    '${entries.length} ${entries.length == 1 ? 'event' : 'events'}',
                    style: const TextStyle(
                      color: AdministratorColors.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'of ${widget.entries.length}',
                    style: const TextStyle(
                      color: AdministratorColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdministratorColors.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            for (var index = 0; index < entries.length; index++) ...[
              _AuditActivityTile(
                entry: entries[index],
                actorName: actorNames[entries[index].actorId] ?? '',
              ),
              if (index < entries.length - 1)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AdministratorColors.line,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AuditActivityTile extends StatefulWidget {
  const _AuditActivityTile({
    required this.entry,
    required this.actorName,
  });

  final PlatformAuditEntry entry;
  final String actorName;

  @override
  State<_AuditActivityTile> createState() => _AuditActivityTileState();
}

class _AuditActivityTileState extends State<_AuditActivityTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final actor = widget.actorName.trim().isEmpty
        ? 'System'
        : widget.actorName.trim();

    final appearance = _activityAppearance(entry);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered
            ? const Color(0xFFF8FAFD)
            : Colors.white,
        child: InkWell(
          onTap: () => showAdministratorAuditDetails(
            context,
            entry: entry,
            actorName: actor,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;

                final icon = Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: appearance.color.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    appearance.icon,
                    color: appearance.color,
                    size: 20,
                  ),
                );

                final information = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activityTitle(entry),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdministratorColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _InlineMetadata(
                          icon: Icons.person_outline_rounded,
                          text: actor,
                        ),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: const BoxDecoration(
                            color: Color(0xFFCBD5E1),
                            shape: BoxShape.circle,
                          ),
                        ),
                        _InlineMetadata(
                          icon: Icons.category_outlined,
                          text: _sourceLabel(entry.tableName),
                        ),
                      ],
                    ),
                  ],
                );

                if (compact) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      icon,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            information,
                            const SizedBox(height: 8),
                            Text(
                              administratorDateTime(entry.createdAt),
                              style: const TextStyle(
                                color: AdministratorColors.muted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    icon,
                    const SizedBox(width: 13),
                    Expanded(child: information),
                    const SizedBox(width: 16),
                    Text(
                      administratorDateTime(entry.createdAt),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AdministratorColors.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF94A3B8),
                      size: 20,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineMetadata extends StatelessWidget {
  const _InlineMetadata({
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
        Icon(
          icon,
          size: 13,
          color: AdministratorColors.muted,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: AdministratorColors.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

Future<void> showAdministratorAuditDetails(
  BuildContext context, {
  required PlatformAuditEntry entry,
  required String actorName,
}) async {
  final appearance = _activityAppearance(entry);

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 24,
        ),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 610,
            maxHeight: 720,
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 20, 16, 18),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AdministratorColors.line,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: appearance.color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          appearance.icon,
                          color: appearance.color,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Activity details',
                              style: TextStyle(
                                color: AdministratorColors.muted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _activityTitle(entry),
                              style: const TextStyle(
                                color: AdministratorColors.ink,
                                fontSize: 18,
                                height: 1.25,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: AdministratorColors.muted,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailSection(
                          title: 'Activity',
                          children: [
                            _DetailRow(
                              label: 'Action',
                              value: _activityTitle(entry),
                            ),
                            _DetailRow(
                              label: 'Performed by',
                              value: actorName.trim().isEmpty
                                  ? 'System'
                                  : actorName.trim(),
                            ),
                            _DetailRow(
                              label: 'Date & time',
                              value: administratorDateTime(entry.createdAt),
                              isLast: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _DetailSection(
                          title: 'Source',
                          children: [
                            _DetailRow(
                              label: 'Category',
                              value: _sourceLabel(entry.tableName),
                            ),
                            if (entry.recordId.trim().isNotEmpty)
                              _DetailRow(
                                label: 'Reference',
                                value: _friendlyReference(entry.recordId),
                                isLast: true,
                              )
                            else
                              const _DetailRow(
                                label: 'Reference',
                                value: 'Not available',
                                isLast: true,
                              ),
                          ],
                        ),
                        if (entry.description.trim().isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _DescriptionCard(
                            description: _friendlyDescription(
                              entry.description,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFAFBFC),
                    border: Border(
                      top: BorderSide(
                        color: AdministratorColors.line,
                      ),
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AdministratorColors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdministratorColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 9),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: AdministratorColors.muted,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(
                  color: AdministratorColors.line,
                ),
              ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AdministratorColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: const TextStyle(
                    color: AdministratorColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 115,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AdministratorColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  value,
                  style: const TextStyle(
                    color: AdministratorColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({
    required this.description,
  });

  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdministratorColors.blue.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AdministratorColors.blue.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.notes_rounded,
                color: AdministratorColors.blue,
                size: 17,
              ),
              SizedBox(width: 7),
              Text(
                'DESCRIPTION',
                style: TextStyle(
                  color: AdministratorColors.blue,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          SelectableText(
            description,
            style: const TextStyle(
              color: AdministratorColors.ink,
              fontSize: 12,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityAppearance {
  const _ActivityAppearance(this.icon, this.color);

  final IconData icon;
  final Color color;
}

_ActivityAppearance _activityAppearance(PlatformAuditEntry entry) {
  final value =
      '${entry.action} ${entry.tableName} ${entry.description}'.toLowerCase();

  if (value.contains('delete') ||
      value.contains('remove') ||
      value.contains('suspend') ||
      value.contains('ban') ||
      value.contains('reject')) {
    return const _ActivityAppearance(
      Icons.block_rounded,
      AdministratorColors.red,
    );
  }

  if (value.contains('maintenance')) {
    return const _ActivityAppearance(
      Icons.construction_rounded,
      AdministratorColors.amber,
    );
  }

  if (value.contains('payment') ||
      value.contains('payout') ||
      value.contains('disbursement')) {
    return const _ActivityAppearance(
      Icons.payments_outlined,
      Color(0xFF7A5AF8),
    );
  }

  if (value.contains('approve') ||
      value.contains('verify') ||
      value.contains('activate') ||
      value.contains('restore')) {
    return const _ActivityAppearance(
      Icons.verified_outlined,
      AdministratorColors.green,
    );
  }

  if (value.contains('account') ||
      value.contains('profile') ||
      value.contains('user')) {
    return const _ActivityAppearance(
      Icons.person_outline_rounded,
      AdministratorColors.blue,
    );
  }

  if (value.contains('booking') ||
      value.contains('tour') ||
      value.contains('package')) {
    return const _ActivityAppearance(
      Icons.map_outlined,
      Color(0xFF0BA5EC),
    );
  }

  return const _ActivityAppearance(
    Icons.history_rounded,
    AdministratorColors.blue,
  );
}

String _activityTitle(PlatformAuditEntry entry) {
  final action = entry.action.trim();

  if (action.isEmpty) {
    return 'Platform activity';
  }

  return administratorTitleCase(action);
}

String _sourceLabel(String value) {
  final normalized = value
      .trim()
      .replaceAll('public.', '')
      .replaceAll('_', ' ');

  if (normalized.isEmpty) {
    return 'Platform';
  }

  final specialLabels = <String, String>{
    'profiles': 'Accounts',
    'tourist spots': 'Tourist Spots',
    'tour packages': 'Tour Packages',
    'package bookings': 'Bookings',
    'driver details': 'Drivers',
    'driver documents': 'Driver Documents',
    'payment records': 'Payments',
    'payment disputes': 'Payment Disputes',
    'payouts': 'Payouts',
    'system settings': 'System Settings',
    'audit logs': 'Audit Logs',
    'subtenant details': 'Tourism Offices',
  };

  return specialLabels[normalized.toLowerCase()] ??
      administratorTitleCase(normalized);
}

String _friendlyReference(String value) {
  final trimmed = value.trim();

  if (trimmed.isEmpty) {
    return 'Not available';
  }

  if (trimmed.length <= 18) {
    return trimmed;
  }

  return '${trimmed.substring(0, 8)}…${trimmed.substring(trimmed.length - 6)}';
}

String _friendlyDescription(String value) {
  var text = value.trim();

  if (text.isEmpty) {
    return 'No additional description was recorded.';
  }

  // Make common database-style descriptions easier to read without
  // changing the actual information recorded in the audit entry.
  text = text
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('_', ' ')
      .trim();

  if (text.isEmpty) {
    return 'No additional description was recorded.';
  }

  return text[0].toUpperCase() + text.substring(1);
}