import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';
import 'package:touristrike/screens/shared/payment_dispute_screen.dart' show paymentDisputeReasons;

// TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
// Resolving a dispute here never moves money — it only changes record status.
// Any actual refund is arranged directly between the tourist and driver.
class SubTenantPaymentDisputesScreen extends StatefulWidget {
  const SubTenantPaymentDisputesScreen({super.key});

  @override
  State<SubTenantPaymentDisputesScreen> createState() =>
      _SubTenantPaymentDisputesScreenState();
}

class _SubTenantPaymentDisputesScreenState
    extends State<SubTenantPaymentDisputesScreen> {
  final TourisTrikeRepository _repo = TourisTrikeRepository();

  late Future<_DisputesLoad> _future;
  String _statusFilter = 'open';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DisputesLoad> _load() async {
    final disputes = await _repo.fetchPaymentDisputes(limit: 200);
    final recordIds = disputes.map((d) => d.paymentRecordId).toSet();
    final records = <String, PaymentRecord>{};
    final profiles = <String, Profile>{};

    for (final id in recordIds) {
      final row = await _repo.fetchOne(
        TourisTrikeTables.paymentRecords,
        equals: {'id': id},
      );
      if (row != null) records[id] = PaymentRecord(row);
    }

    final userIds = <String>{
      ...disputes.map((d) => d.raisedBy),
      ...records.values.map((r) => r.payerId),
      ...records.values.map((r) => r.payeeId),
    }..removeWhere((id) => id.isEmpty);

    for (final id in userIds) {
      final profile = await _repo.fetchProfile(id);
      if (profile != null) profiles[id] = profile;
    }

    return _DisputesLoad(disputes: disputes, records: records, profiles: profiles);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _resolve(PaymentDispute dispute, String newStatus) async {
    final note = await _promptResolutionNote(newStatus);
    if (note == null) return;
    try {
      await _repo.resolvePaymentDispute(
        disputeId: dispute.id as String,
        newStatus: newStatus,
        resolutionNote: note.trim().isEmpty ? null : note.trim(),
      );
      if (!mounted) return;
      showSubTenantSnack(context, 'Dispute updated.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Unable to update dispute: $e');
    }
  }

  Future<String?> _promptResolutionNote(String newStatus) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_statusLabel(newStatus)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Resolution note (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'under_review':
        return 'Mark as Under Review';
      case 'resolved_valid':
        return 'Resolve — Payment Was Valid';
      case 'resolved_refund_arranged':
        return 'Resolve — Refund Arranged Directly';
      case 'rejected':
        return 'Reject Dispute';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: 7,
      title: 'Payment Disputes',
      subtitle:
          'Review GCash/cash payment disputes. TourisTrike never holds funds — resolving a dispute only updates the record; any refund happens directly between the tourist and driver.',
      child: FutureBuilder<_DisputesLoad>(
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

          final load = snapshot.data!;
          final filtered = _statusFilter == 'all'
              ? load.disputes
              : load.disputes.where((d) => d.status == _statusFilter).toList();

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ResponsivePageContainer(
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final status in const [
                      'open',
                      'under_review',
                      'resolved_valid',
                      'resolved_refund_arranged',
                      'rejected',
                      'all',
                    ])
                      ChoiceChip(
                        label: Text(status.replaceAll('_', ' ')),
                        selected: _statusFilter == status,
                        onSelected: (_) => setState(() => _statusFilter = status),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (filtered.isEmpty)
                  const EmptyStateCard(
                    icon: Icons.verified_outlined,
                    title: 'No disputes here',
                    message: 'Nothing to review for this filter right now.',
                  )
                else
                  ...filtered.map(
                    (d) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _DisputeCard(
                        dispute: d,
                        record: load.records[d.paymentRecordId],
                        raisedByName: load.profiles[d.raisedBy]?.displayName ?? 'Unknown',
                        payerName: load.records[d.paymentRecordId] != null
                            ? load.profiles[load.records[d.paymentRecordId]!.payerId]?.displayName
                            : null,
                        payeeName: load.records[d.paymentRecordId] != null
                            ? load.profiles[load.records[d.paymentRecordId]!.payeeId]?.displayName
                            : null,
                        onResolve: (status) => _resolve(d, status),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DisputesLoad {
  const _DisputesLoad({
    required this.disputes,
    required this.records,
    required this.profiles,
  });

  final List<PaymentDispute> disputes;
  final Map<String, PaymentRecord> records;
  final Map<String, Profile> profiles;
}

class _DisputeCard extends StatelessWidget {
  const _DisputeCard({
    required this.dispute,
    required this.record,
    required this.raisedByName,
    required this.payerName,
    required this.payeeName,
    required this.onResolve,
  });

  final PaymentDispute dispute;
  final PaymentRecord? record;
  final String raisedByName;
  final String? payerName;
  final String? payeeName;
  final ValueChanged<String> onResolve;

  bool get _isOpen => dispute.status == 'open' || dispute.status == 'under_review';

  @override
  Widget build(BuildContext context) {
    final createdLabel = dispute.createdAt != null
        ? DateFormat.yMMMd().add_jm().format(dispute.createdAt!.toLocal())
        : '-';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  paymentDisputeReasons[dispute.reason] ?? dispute.reason,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: SubTenantColors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  dispute.status.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    color: SubTenantColors.blue,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (record != null)
            Text(
              'PHP ${record!.amount.toStringAsFixed(2)} — ${record!.paymentMethod.toUpperCase()}'
              '${record!.externalReferenceNo.isNotEmpty ? ' (Ref: ${record!.externalReferenceNo})' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          Text('Raised by: $raisedByName', style: const TextStyle(color: Color(0xFF64748B))),
          if (payerName != null) Text('Payer: $payerName', style: const TextStyle(color: Color(0xFF64748B))),
          if (payeeName != null) Text('Payee: $payeeName', style: const TextStyle(color: Color(0xFF64748B))),
          Text('Filed: $createdLabel', style: const TextStyle(color: Color(0xFF64748B))),
          if (dispute.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(dispute.description),
          ],
          if (dispute.evidenceUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(dispute.evidenceUrl, height: 160, fit: BoxFit.cover),
            ),
          ],
          if (dispute.resolutionNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Resolution note: ${dispute.resolutionNote}',
              style: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
            ),
          ],
          if (_isOpen) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (dispute.status == 'open')
                  OutlinedButton(
                    onPressed: () => onResolve('under_review'),
                    child: const Text('Mark Under Review'),
                  ),
                FilledButton(
                  onPressed: () => onResolve('resolved_valid'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                  child: const Text('Payment Was Valid'),
                ),
                FilledButton(
                  onPressed: () => onResolve('resolved_refund_arranged'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB45309)),
                  child: const Text('Refund Arranged Directly'),
                ),
                OutlinedButton(
                  onPressed: () => onResolve('rejected'),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
