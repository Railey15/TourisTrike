import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'layouts/subtenant_admin_shell.dart';
import 'subtenant_models.dart';
import 'subtenant_service.dart';
import 'widgets/subtenant_admin_widgets.dart';
import 'widgets/subtenant_components.dart';
const caseCategories = <String, String>{
  'all': 'All Categories',
  'payment': 'Payment',
  'booking': 'Booking',
  'driver': 'Driver',
  'tourist': 'Tourist',
  'tour_package': 'Tour / Package',
  'fare_charge': 'Fare / Additional Charges',
  'safety_incident': 'Safety / Incident',
  'other': 'Other',
};
const caseStatuses = <String, String>{
  'attention': 'Needs Attention',
  'needs_review': 'Needs Review',
  'under_review': 'Under Review',
  'closed': 'Closed',
  'all': 'All Cases',
};
const caseResolutions = <String, String>{
  'no_action_required': 'Resolved – No Action Required',
  'warning_issued': 'Warning Issued',
  'driver_suspended': 'Driver Suspended',
  'booking_issue_resolved': 'Booking Issue Resolved',
  'payment_issue_resolved': 'Payment Issue Resolved',
  'referred_tourism_office': 'Referred to Tourism Office',
  'dismissed_insufficient_evidence': 'Dismissed / Insufficient Evidence',
  'other_resolution': 'Other Resolution',
};
class SubTenantPaymentDisputesScreen extends StatefulWidget {
  const SubTenantPaymentDisputesScreen({super.key, this.service});
  final SubTenantService? service;
  @override
  State<SubTenantPaymentDisputesScreen> createState() =>
      _SubTenantPaymentDisputesScreenState();
}
class _SubTenantPaymentDisputesScreenState
    extends State<SubTenantPaymentDisputesScreen> {
  late final SubTenantService _service;
  late Future<List<SubTenantCase>> _future;
  final _search = TextEditingController();
  final Set<String> _processing = {};
  String _category = 'all';
  String _status = 'attention';
  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SubTenantService();
    _future = _service.fetchCases();
  }
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
  void _reload() => setState(() => _future = _service.fetchCases());
  Future<void> _refresh() async {
    final next = _service.fetchCases();
    setState(() => _future = next);
    await next;
  }
  bool _matches(SubTenantCase item) {
    return item.matchesFilters(
      categoryFilter: _category,
      statusFilter: _status,
      searchQuery: _search.text,
    );
  }
  Future<void> _mutate(
    SubTenantCase item,
    Future<void> Function() action,
    String message,
  ) async {
    if (_processing.contains(item.id)) return;
    setState(() => _processing.add(item.id));
    try {
      await action();
      if (!mounted) return;
      showSubTenantSnack(context, message, error: false);
      _reload();
    } catch (error) {
      if (mounted) showSubTenantSnack(context, 'Unable to update case: $error');
    } finally {
      if (mounted) setState(() => _processing.remove(item.id));
    }
  }
  Future<void> _startReview(SubTenantCase item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Review'),
        content: Text(
          'Start reviewing ${item.reference}? The involved parties will be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start Review'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _mutate(
        item,
        () => _service.startCaseReview(item.id),
        'Case is now under review.',
      );
    }
  }
  Future<void> _resolve(SubTenantCase item) async {
    final result = await showDialog<_ResolutionInput>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ResolveDialog(),
    );
    if (result == null) return;
    await _mutate(
      item,
      () => _service.resolveCase(
        caseId: item.id,
        resolutionType: result.type,
        resolutionNotes: result.notes,
        customResolution: result.custom,
      ),
      result.type == 'driver_suspended'
          ? 'Case closed. Use Driver Management for the separate suspension action.'
          : 'Case resolved and closed.',
    );
  }
  Future<void> _view(SubTenantCase item) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CaseDialog(
        item: item,
        busy: _processing.contains(item.id),
        onStart: () {
          Navigator.pop(context);
          _startReview(item);
        },
        onResolve: () {
          Navigator.pop(context);
          _resolve(item);
        },
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: 7,
      title: 'Disputes & Cases',
      subtitle:
          'Review and resolve reported issues involving bookings, payments, drivers, tourists, tours, and service incidents.',
      child: FutureBuilder<List<SubTenantCase>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SubTenantLoadingView();
          }
          if (snapshot.hasError) {
            return SubTenantErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final all = snapshot.data ?? const <SubTenantCase>[];
          final visible = all.where(_matches).toList(growable: false);
          int count(String status) =>
              all.where((item) => item.status == status).length;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ResponsivePageContainer(
              children: [
                ResponsiveGrid(
                  minItemWidth: 180,
                  mobileAspectRatio: 2.25,
                  desktopAspectRatio: 3.25,
                  children: [
                    _metric(
                      'Needs Review',
                      count('needs_review'),
                      Icons.report_problem_outlined,
                      const Color(0xFFDC2626),
                      'needs_review',
                    ),
                    _metric(
                      'Under Review',
                      count('under_review'),
                      Icons.manage_search_rounded,
                      const Color(0xFFD97706),
                      'under_review',
                    ),
                    _metric(
                      'Closed',
                      count('closed'),
                      Icons.task_alt_rounded,
                      const Color(0xFF16A34A),
                      'closed',
                    ),
                    _metric(
                      'Total',
                      all.length,
                      Icons.folder_copy_outlined,
                      SubTenantColors.blue,
                      'all',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _filters(),
                const SizedBox(height: 12),
                _CaseWorkspace(
                  minHeight: (MediaQuery.sizeOf(context).height - 470)
                      .clamp(300.0, 680.0),
                  visible: visible,
                  emptyMessage: _emptyMessage(),
                  processing: _processing,
                  onView: _view,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  Widget _metric(
    String label,
    int value,
    IconData icon,
    Color color,
    String status,
  ) {
    return DashboardMetricCard(
      icon: icon,
      label: label,
      value: '$value',
      color: color,
      onTap: () => setState(() => _status = status),
    );
  }
  Widget _filters() {
    return DashboardSectionCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search cases...',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
          );
          final category = _Filter(
            value: _category,
            values: caseCategories,
            onChanged: (value) => setState(() => _category = value),
          );
          final status = _Filter(
            value: _status,
            values: caseStatuses,
            onChanged: (value) => setState(() => _status = value),
          );
          if (constraints.maxWidth < 720) {
            return Column(
              children: [
                search,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: category),
                    const SizedBox(width: 10),
                    Expanded(child: status),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              SizedBox(width: 220, child: category),
              const SizedBox(width: 12),
              SizedBox(width: 190, child: status),
            ],
          );
        },
      ),
    );
  }
  String _emptyMessage() {
    if (_search.text.trim().isNotEmpty) {
      return 'No cases match your search and filters.';
    }
    return switch (_status) {
      'needs_review' => 'There are no Needs Review cases right now.',
      'under_review' => 'There are no cases currently under review.',
      'closed' => 'There are no closed cases for this filter.',
      'attention' => 'There are no cases needing attention right now.',
      _ => 'There are no cases for the selected filters.',
    };
  }
}
class _CaseWorkspace extends StatelessWidget {
  const _CaseWorkspace({
    required this.minHeight,
    required this.visible,
    required this.emptyMessage,
    required this.processing,
    required this.onView,
  });

  final double minHeight;
  final List<SubTenantCase> visible;
  final String emptyMessage;
  final Set<String> processing;
  final ValueChanged<SubTenantCase> onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SubTenantColors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.folder_open_rounded,
                    color: SubTenantColors.blue,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cases',
                        style: TextStyle(
                          color: SubTenantColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        visible.isEmpty
                            ? 'No cases in the current view'
                            : '${visible.length} ${visible.length == 1 ? 'case' : 'cases'} in this view',
                        style: const TextStyle(
                          color: SubTenantColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (visible.isEmpty)
            SizedBox(
              height: (minHeight - 142).clamp(180.0, 540.0),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: SubTenantColors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.inbox_outlined,
                          color: SubTenantColors.blue,
                          size: 25,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Nothing here',
                        style: TextStyle(
                          color: SubTenantColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        emptyMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: SubTenantColors.muted,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  for (var i = 0; i < visible.length; i++) ...[
                    _CaseCard(
                      item: visible[i],
                      busy: processing.contains(visible[i].id),
                      onView: () => onView(visible[i]),
                    ),
                    if (i != visible.length - 1)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.all(11),
            child: _HandlingNotice(embedded: true),
          ),
        ],
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter({
    required this.value,
    required this.values,
    required this.onChanged,
  });
  final String value;
  final Map<String, String> values;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: const InputDecoration(border: OutlineInputBorder()),
    items: [
      for (final entry in values.entries)
        DropdownMenuItem(
          value: entry.key,
          child: Text(entry.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}
class _CaseCard extends StatelessWidget {
  const _CaseCard({
    required this.item,
    required this.busy,
    required this.onView,
  });
  final SubTenantCase item;
  final bool busy;
  final VoidCallback onView;
  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Badge(
                label:
                    caseCategories[item.category] ?? stTitleCase(item.category),
                color: _categoryColor(item.category),
              ),
              _Badge(
                label: _statusLabel(item.status),
                color: _statusColor(item.status),
              ),
              _Badge(
                label: stTitleCase(item.priority),
                color: _priorityColor(item.priority),
              ),
              Text(
                item.reference,
                style: const TextStyle(
                  color: SubTenantColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.subject,
            style: const TextStyle(
              color: SubTenantColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: SubTenantColors.muted, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _Inline(
                icon: Icons.person_outline,
                text: 'Reporter: ${item.reporter.name}',
              ),
              if (item.reportedUser != null)
                _Inline(
                  icon: Icons.person_search_outlined,
                  text: 'Reported: ${item.reportedUser!.name}',
                ),
              if (item.bookingId.isNotEmpty)
                _Inline(
                  icon: Icons.book_online_outlined,
                  text: 'Booking ${_shortId(item.bookingId)}',
                ),
              _Inline(
                icon: Icons.schedule_rounded,
                text: _date(item.createdAt),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: busy ? null : onView,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('View Case'),
            ),
          ),
        ],
      ),
    );
  }
}
class _CaseDialog extends StatelessWidget {
  const _CaseDialog({
    required this.item,
    required this.busy,
    required this.onStart,
    required this.onResolve,
  });
  final SubTenantCase item;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onResolve;
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.subject,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.reference,
                          style: const TextStyle(color: SubTenantColors.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      title: 'Case Summary',
                      child: _Details(
                        rows: {
                          'Case ID': item.reference,
                          'Category':
                              caseCategories[item.category] ??
                              stTitleCase(item.category),
                          'Status': _statusLabel(item.status),
                          'Priority': stTitleCase(item.priority),
                          'Submitted': _date(item.createdAt),
                          'Municipality': item.municipality,
                        },
                      ),
                    ),
                    _Section(
                      title: 'Parties Involved',
                      child: Column(
                        children: [
                          _Party(label: 'Reporter', party: item.reporter),
                          if (item.reportedUser != null) ...[
                            const Divider(),
                            _Party(
                              label: 'Reported party',
                              party: item.reportedUser!,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (item.booking != null || item.tourPackage != null)
                      _Section(
                        title: 'Related Booking / Tour',
                        child: _Details(
                          rows: {
                            if (item.bookingId.isNotEmpty)
                              'Booking': item.bookingId,
                            if (item.booking != null)
                              'Booking status': stTitleCase(
                                stString(item.booking!, const ['status']),
                              ),
                            if (item.tourPackage != null)
                              'Tour / Package': stString(
                                item.tourPackage!,
                                const ['title'],
                              ),
                            if (item.booking?['travel_date'] != null)
                              'Travel date': item.booking!['travel_date']
                                  .toString(),
                          },
                        ),
                      ),
                    _Section(
                      title: 'Description',
                      child: Text(
                        item.description.isEmpty
                            ? 'No additional description was supplied.'
                            : item.description,
                        style: const TextStyle(
                          height: 1.5,
                          color: SubTenantColors.muted,
                        ),
                      ),
                    ),
                    if (item.category == 'payment' && item.payment != null)
                      _Section(
                        title: 'Payment Details',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Details(
                              rows: {
                                'Payment method': stTitleCase(
                                  stString(item.payment!, const [
                                    'payment_method',
                                  ]),
                                ),
                                'Amount': _currency(item.payment!['amount']),
                                'Payment status': stTitleCase(
                                  stString(item.payment!, const ['status']),
                                ),
                                'Reference': stString(item.payment!, const [
                                  'reference',
                                ], fallback: '—'),
                                'Payment record': stString(
                                  item.payment!,
                                  const ['id'],
                                ),
                              },
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'TourisTrike does not hold or transfer direct GCash/cash funds.',
                              style: TextStyle(
                                color: SubTenantColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    _Section(
                      title: 'Evidence',
                      child: item.evidence.isEmpty
                          ? const Text(
                              'No evidence was attached.',
                              style: TextStyle(color: SubTenantColors.muted),
                            )
                          : Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final evidence in item.evidence)
                                  _Evidence(evidence: evidence),
                              ],
                            ),
                    ),
                    _Section(
                      title: 'Case Timeline',
                      child: Column(
                        children: [
                          for (final event in item.timeline)
                            _Timeline(
                              label: event.label,
                              date: _date(event.at),
                            ),
                        ],
                      ),
                    ),
                    if (item.status == 'closed')
                      _Section(
                        title: 'Resolution',
                        child: _Details(
                          rows: {
                            'Outcome': item.customResolution.isNotEmpty
                                ? item.customResolution
                                : (caseResolutions[item.resolutionType] ??
                                      stTitleCase(item.resolutionType)),
                            'Notes': item.resolutionNotes,
                            'Closed': _date(item.resolvedAt),
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (item.status != 'closed') ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: busy
                        ? null
                        : (item.status == 'needs_review' ? onStart : onResolve),
                    icon: Icon(
                      item.status == 'needs_review'
                          ? Icons.manage_search_rounded
                          : Icons.gavel_rounded,
                    ),
                    label: Text(
                      item.status == 'needs_review'
                          ? 'Start Review'
                          : 'Resolve Case',
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog();
  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}
class _ResolveDialogState extends State<_ResolveDialog> {
  final _key = GlobalKey<FormState>();
  final _notes = TextEditingController();
  final _custom = TextEditingController();
  String? _type;
  @override
  void dispose() {
    _notes.dispose();
    _custom.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Resolve Case'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          child: Form(
            key: _key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Resolution type',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final entry in caseResolutions.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) => setState(() => _type = value),
                  validator: (value) =>
                      value == null ? 'Choose a resolution type.' : null,
                ),
                if (_type == 'other_resolution') ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _custom,
                    decoration: const InputDecoration(
                      labelText: 'Custom resolution',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter the custom resolution.'
                        : null,
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notes,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Resolution notes',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Resolution notes are required.'
                      : null,
                ),
                if (_type == 'driver_suspended') ...[
                  const SizedBox(height: 12),
                  const Text(
                    'This records the outcome only. Suspend the driver separately in Driver Management, where reason and duration are required.',
                    style: TextStyle(
                      color: SubTenantColors.muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_key.currentState!.validate()) return;
            Navigator.pop(
              context,
              _ResolutionInput(
                type: _type!,
                notes: _notes.text.trim(),
                custom: _custom.text.trim(),
              ),
            );
          },
          child: const Text('Confirm Resolution'),
        ),
      ],
    );
  }
}
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: Border.all(color: SubTenantColors.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: child,
        ),
      ],
    ),
  );
}
class _Details extends StatelessWidget {
  const _Details({required this.rows});
  final Map<String, String> rows;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth < 540
          ? constraints.maxWidth
          : (constraints.maxWidth - 16) / 2;
      return Wrap(
        spacing: 16,
        runSpacing: 13,
        children: [
          for (final entry in rows.entries)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: const TextStyle(
                      color: SubTenantColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SelectableText(
                    entry.value.isEmpty ? '—' : entry.value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
class _Party extends StatelessWidget {
  const _Party({required this.label, required this.party});
  final String label;
  final SubTenantCaseParty party;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const CircleAvatar(child: Icon(Icons.person_outline)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label • ${stTitleCase(party.role)}',
              style: const TextStyle(
                color: SubTenantColors.muted,
                fontSize: 11,
              ),
            ),
            Text(
              party.name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (party.mobile.isNotEmpty)
              Text(
                party.mobile,
                style: const TextStyle(
                  color: SubTenantColors.muted,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
class _Evidence extends StatelessWidget {
  const _Evidence({required this.evidence});
  final SubTenantCaseEvidence evidence;
  Future<void> _open(BuildContext context) async {
    if (evidence.isImage) {
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
            child: InteractiveViewer(
              child: Image.network(
                evidence.url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('Unable to preview this image.'),
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(evidence.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => _open(context),
    child: Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: SubTenantColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            evidence.isImage ? Icons.image_outlined : Icons.attach_file_rounded,
            color: SubTenantColors.blue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              evidence.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}
class _Timeline extends StatelessWidget {
  const _Timeline({required this.label, required this.date});
  final String label;
  final String date;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: Color(0xFF16A34A),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          date,
          style: const TextStyle(color: SubTenantColors.muted, fontSize: 12),
        ),
      ],
    ),
  );
}
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
    ),
  );
}
class _Inline extends StatelessWidget {
  const _Inline({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: SubTenantColors.lightMuted),
      const SizedBox(width: 5),
      Text(
        text,
        style: const TextStyle(color: SubTenantColors.muted, fontSize: 12),
      ),
    ],
  );
}
class _HandlingNotice extends StatelessWidget {
  const _HandlingNotice({this.embedded = false});

  final bool embedded;
  @override
  Widget build(BuildContext context) => Container(
    margin: embedded ? EdgeInsets.zero : const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: SubTenantColors.blue.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: SubTenantColors.blue.withValues(alpha: 0.18)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: SubTenantColors.blue),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Case handling notice: TourisTrike records and facilitates dispute resolution but does not independently transfer or hold GCash/cash funds. Payment-related settlements or refunds, when applicable, are arranged according to the involved parties and TourisTrike policies.',
            style: TextStyle(color: SubTenantColors.muted, height: 1.45),
          ),
        ),
      ],
    ),
  );
}
class _ResolutionInput {
  const _ResolutionInput({
    required this.type,
    required this.notes,
    required this.custom,
  });
  final String type;
  final String notes;
  final String custom;
}
String _statusLabel(String status) => switch (status) {
  'needs_review' => 'Needs Review',
  'under_review' => 'Under Review',
  'closed' => 'Closed',
  _ => stTitleCase(status),
};
Color _statusColor(String status) => switch (status) {
  'needs_review' => const Color(0xFFDC2626),
  'under_review' => const Color(0xFFD97706),
  'closed' => const Color(0xFF16A34A),
  _ => SubTenantColors.muted,
};
Color _priorityColor(String priority) => switch (priority) {
  'urgent' => const Color(0xFFB91C1C),
  'high' => const Color(0xFFEA580C),
  'low' => const Color(0xFF0284C7),
  _ => SubTenantColors.muted,
};
Color _categoryColor(String category) => switch (category) {
  'payment' => const Color(0xFF7C3AED),
  'safety_incident' => const Color(0xFFDC2626),
  'driver' => const Color(0xFF0369A1),
  'tourist' => const Color(0xFF0F766E),
  'booking' => const Color(0xFF1D4ED8),
  _ => SubTenantColors.blue,
};
String _shortId(String value) =>
    value.length > 8 ? value.substring(0, 8).toUpperCase() : value;
String _date(DateTime? value) =>
    value == null ? '—' : DateFormat('MMM d, y • h:mm a').format(value);
String _currency(dynamic value) => NumberFormat.currency(
  symbol: '₱',
  decimalDigits: 2,
).format(stDouble(value));
