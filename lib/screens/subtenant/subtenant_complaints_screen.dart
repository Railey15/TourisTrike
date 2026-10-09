import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'layouts/subtenant_admin_shell.dart';

class SubTenantComplaintsScreen extends StatefulWidget {
  const SubTenantComplaintsScreen({super.key});
  @override
  State<SubTenantComplaintsScreen> createState() =>
      _SubTenantComplaintsScreenState();
}

class _SubTenantComplaintsScreenState extends State<SubTenantComplaintsScreen> {
  final _client = Supabase.instance.client;
  late Future<_ComplaintLoad> _future;
  String _status = 'all';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() {
    final next = _load();
    if (!mounted) return;
    setState(() {
      _future = next;
    });
  }

  Future<_ComplaintLoad> _load() async {
    final results = await Future.wait<dynamic>([
      _client.rpc('get_municipal_complaints'),
      _client.rpc('get_municipal_restrictions'),
    ]);
    List<Map<String, dynamic>> rows(dynamic value) => value is List
        ? value
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const [];
    return _ComplaintLoad(rows(results[0]), rows(results[1]));
  }

  Future<String?> _input(String title, {bool findings = false}) async {
    final note = TextEditingController();
    final finding = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (findings) ...[
                  TextField(
                    controller: finding,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Investigation findings',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason / notes',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (note.text.trim().length < 10 ||
                    (findings && finding.text.trim().length < 10)) {
                  return;
                }
                Navigator.pop(
                  context,
                  findings
                      ? '${finding.text.trim()}\u001e${note.text.trim()}'
                      : note.text.trim(),
                );
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
    } finally {
      note.dispose();
      finding.dispose();
    }
  }

  Future<void> _mutate(String rpc, Map<String, dynamic> params) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _client.rpc(rpc, params: params);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Decision saved and affected users notified.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save decision: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _caseAction(Map<String, dynamic> caseRow, String action) async {
    final id = caseRow['id'].toString();
    if (action == 'suspend') {
      await _suspend(caseRow);
      return;
    }
    final needsFindings = action == 'resolve' || action == 'dismiss';
    final value = await _input(switch (action) {
      'investigate' => 'Start investigation',
      'note' => 'Add investigation note',
      'warn' => 'Issue formal warning',
      'resolve' => 'Resolve complaint',
      _ => 'Dismiss complaint',
    }, findings: needsFindings);
    if (value == null) return;
    final parts = needsFindings ? value.split('\u001e') : const <String>[];
    await _mutate('update_municipal_complaint', {
      'p_complaint_id': id,
      'p_action': action,
      'p_notes': needsFindings ? parts.skip(1).join('\n') : value,
      'p_findings': needsFindings ? parts.first : null,
    });
  }

  Future<void> _suspend(Map<String, dynamic> caseRow) async {
    final reason = TextEditingController();
    var days = 7;
    var confirmed = false;
    try {
      final request = await showDialog<(String, int)?>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Manual municipal restriction'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account: ${caseRow['reported_name']} (${caseRow['reported_role']}). '
                    'Existing trips, payments, refunds, and appeals remain accessible.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    maxLines: 4,
                    onChanged: (_) => update(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Documented investigation reason',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: days,
                    decoration: const InputDecoration(
                      labelText: 'Duration',
                      border: OutlineInputBorder(),
                    ),
                    items: const [1, 7, 30, 90]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value day${value == 1 ? '' : 's'}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => update(() => days = value ?? days),
                  ),
                  CheckboxListTile(
                    value: confirmed,
                    title: const Text(
                      'I confirm this is a manual MTO decision after investigation.',
                    ),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) =>
                        update(() => confirmed = value == true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: !confirmed || reason.text.trim().length < 20
                    ? null
                    : () => Navigator.pop(context, (reason.text.trim(), days)),
                child: const Text('Impose restriction'),
              ),
            ],
          ),
        ),
      );
      if (request == null) return;
      await _mutate('impose_municipal_restriction', {
        'p_complaint_id': caseRow['id'],
        'p_reason': request.$1,
        'p_ends_at': DateTime.now()
            .toUtc()
            .add(Duration(days: request.$2))
            .toIso8601String(),
        'p_confirm': true,
      });
    } finally {
      reason.dispose();
    }
  }

  Future<void> _viewEvidence(Map<String, dynamic> evidence) async {
    try {
      final url = await _client.storage
          .from('municipal-complaint-evidence')
          .createSignedUrl(evidence['storage_path'].toString(), 60);
      if (!mounted) return;
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open the secure evidence link.');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Evidence unavailable: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SubTenantAdminShell(
    currentIndex: 8,
    title: 'Complaints Management',
    subtitle: 'Investigate booking reports and document manual decisions.',
    actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
    child: FutureBuilder<_ComplaintLoad>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return snapshot.hasError
              ? Center(
                  child: Text('Unable to load complaints: ${snapshot.error}'),
                )
              : const Center(child: CircularProgressIndicator());
        }
        final load = snapshot.data!;
        final visible = load.cases
            .where((item) => _status == 'all' || item['status'] == _status)
            .toList();
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _future;
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in const [
                    'all',
                    'submitted',
                    'under_investigation',
                    'resolved',
                    'dismissed',
                  ])
                    ChoiceChip(
                      label: Text(status.replaceAll('_', ' ')),
                      selected: _status == status,
                      onSelected: (_) => setState(() => _status = status),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (visible.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No complaints in this view.'),
                  ),
                ),
              ...visible.map((item) => _complaintCard(item)),
              const SizedBox(height: 20),
              Text(
                'Municipal restrictions & appeals',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (load.restrictions.isEmpty)
                const Text('No municipal restrictions.'),
              ...load.restrictions.map(_restrictionCard),
            ],
          ),
        );
      },
    ),
  );

  Widget _complaintCard(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? '';
    final evidence =
        (item['evidence'] as List?)?.whereType<Map>() ??
        const Iterable<Map>.empty();
    final events =
        (item['events'] as List?)?.whereType<Map>() ??
        const Iterable<Map>.empty();
    final warningIssued = events.any(
      (event) => event['action'] == 'warning_issued',
    );
    final bookingHistory =
        (item['booking_history'] as List?)?.whereType<Map>() ??
        const Iterable<Map>.empty();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(status.replaceAll('_', ' '))),
                Chip(label: Text(item['category'].toString())),
                Chip(
                  label: Text(
                    'Booking #${item['booking_id'].toString().substring(0, 8).toUpperCase()}',
                  ),
                ),
              ],
            ),
            Text(
              '${item['reporter_name']} reported ${item['reported_name']} '
              '(${item['reported_role']})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${item['municipality']}, ${item['province']} · '
              '${DateFormat.yMMMd().format(DateTime.parse(item['created_at'].toString()).toLocal())}',
            ),
            const SizedBox(height: 8),
            Text(item['description'].toString()),
            ExpansionTile(
              title: const Text('Municipal booking history'),
              subtitle: Text('${bookingHistory.length} recent booking(s)'),
              children: bookingHistory
                  .map(
                    (booking) => ListTile(
                      title: Text(
                        'Booking #${booking['booking_id'].toString().substring(0, 8).toUpperCase()}',
                      ),
                      subtitle: Text(
                        '${booking['travel_date']} · ${booking['booking_status']}',
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (item['investigation_notes'] != null)
              ListTile(
                title: const Text('Investigation notes'),
                subtitle: Text(item['investigation_notes'].toString()),
              ),
            if (item['findings'] != null)
              ListTile(
                title: const Text('Findings'),
                subtitle: Text(item['findings'].toString()),
              ),
            if (item['resolution_note'] != null)
              ListTile(
                title: const Text('Decision'),
                subtitle: Text(item['resolution_note'].toString()),
              ),
            if (evidence.isNotEmpty) ...[
              const Text(
                'Supporting evidence',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...evidence.map(
                (row) => TextButton.icon(
                  onPressed: () =>
                      _viewEvidence(Map<String, dynamic>.from(row)),
                  icon: const Icon(Icons.attach_file),
                  label: Text(row['file_name'].toString()),
                ),
              ),
            ],
            if (events.isNotEmpty)
              ExpansionTile(
                title: const Text('Decision history'),
                children: events
                    .map(
                      (event) => ListTile(
                        title: Text(
                          event['action'].toString().replaceAll('_', ' '),
                        ),
                        subtitle: Text(event['details'].toString()),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'submitted')
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _caseAction(item, 'investigate'),
                    child: const Text('Investigate'),
                  ),
                if (status == 'under_investigation') ...[
                  OutlinedButton(
                    onPressed: _busy ? null : () => _caseAction(item, 'note'),
                    child: const Text('Add note'),
                  ),
                  OutlinedButton(
                    onPressed: _busy || warningIssued
                        ? null
                        : () => _caseAction(item, 'warn'),
                    child: Text(
                      warningIssued ? 'Warning issued' : 'Issue warning',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _caseAction(item, 'suspend'),
                    child: const Text('Suspend manually'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _caseAction(item, 'resolve'),
                    child: const Text('Resolve'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _caseAction(item, 'dismiss'),
                    child: const Text('Dismiss'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _restrictionCard(Map<String, dynamic> row) {
    final appeals =
        (row['appeals'] as List?)?.whereType<Map>() ??
        const Iterable<Map>.empty();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${row['account_role']} · ${row['municipality']} · '
              '${row['active'] == true ? 'Active' : 'Expired / lifted'}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(row['reason'].toString()),
            Text(
              'Ends: ${DateFormat.yMMMd().add_jm().format(DateTime.parse(row['ends_at'].toString()).toLocal())}',
            ),
            if (row['active'] == true)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final note = await _input('Lift restriction');
                        if (note != null) {
                          await _mutate('lift_municipal_restriction', {
                            'p_restriction_id': row['id'],
                            'p_note': note,
                          });
                        }
                      },
                child: const Text('Lift restriction'),
              ),
            ...appeals.map(
              (appeal) => ListTile(
                title: Text('Appeal: ${appeal['status']}'),
                subtitle: Text(appeal['reason'].toString()),
                trailing: appeal['status'] == 'pending'
                    ? PopupMenuButton<bool>(
                        onSelected: (grant) async {
                          final note = await _input(
                            grant ? 'Grant appeal' : 'Uphold restriction',
                          );
                          if (note != null) {
                            await _mutate(
                              'decide_municipal_restriction_appeal',
                              {
                                'p_appeal_id': appeal['id'],
                                'p_grant': grant,
                                'p_note': note,
                              },
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: true,
                            child: Text('Grant appeal'),
                          ),
                          PopupMenuItem(
                            value: false,
                            child: Text('Uphold restriction'),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComplaintLoad {
  const _ComplaintLoad(this.cases, this.restrictions);
  final List<Map<String, dynamic>> cases;
  final List<Map<String, dynamic>> restrictions;
}
