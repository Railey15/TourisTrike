import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';
import 'package:touristrike/screens/shared/payment_dispute_screen.dart'
    show paymentDisputeReasons;

// TourisTrike does NOT custody funds.
// Resolving a dispute only updates its record/status.
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

  String _statusFilter = 'active';

  final Set<String> _processingDisputeIds = <String>{};

  static const List<String> _filterOptions = [
    'active',
    'open',
    'under_review',
    'closed',
    'all',
  ];

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

      if (row != null) {
        records[id] = PaymentRecord(row);
      }
    }

    final userIds = <String>{
      ...disputes.map((d) => d.raisedBy),
      ...records.values.map((r) => r.payerId),
      ...records.values.map((r) => r.payeeId),
    }..removeWhere((id) => id.isEmpty);

    for (final id in userIds) {
      final profile = await _repo.fetchProfile(id);

      if (profile != null) {
        profiles[id] = profile;
      }
    }

    return _DisputesLoad(
      disputes: disputes,
      records: records,
      profiles: profiles,
    );
  }

  void _reload() {
    final nextLoad = _load();

    if (!mounted) return;

    setState(() {
      _future = nextLoad;
    });
  }

  Future<void> _refresh() async {
    final nextLoad = _load();

    if (!mounted) return;

    setState(() {
      _future = nextLoad;
    });

    try {
      await nextLoad;
    } catch (_) {
      // FutureBuilder displays the error.
    }
  }

  bool _isClosedStatus(String status) {
    return status == 'resolved_valid' ||
        status == 'resolved_refund_arranged' ||
        status == 'rejected';
  }

  bool _matchesFilter(PaymentDispute dispute) {
    switch (_statusFilter) {
      case 'active':
        return dispute.status == 'open' ||
            dispute.status == 'under_review';

      case 'open':
        return dispute.status == 'open';

      case 'under_review':
        return dispute.status == 'under_review';

      case 'closed':
        return _isClosedStatus(dispute.status);

      case 'all':
        return true;

      default:
        return true;
    }
  }

  int _countOpen(List<PaymentDispute> disputes) {
    return disputes.where((d) => d.status == 'open').length;
  }

  int _countUnderReview(List<PaymentDispute> disputes) {
    return disputes.where((d) => d.status == 'under_review').length;
  }

  int _countClosed(List<PaymentDispute> disputes) {
    return disputes.where((d) => _isClosedStatus(d.status)).length;
  }

  int _countForFilter(
    List<PaymentDispute> disputes,
    String filter,
  ) {
    switch (filter) {
      case 'active':
        return _countOpen(disputes) + _countUnderReview(disputes);

      case 'open':
        return _countOpen(disputes);

      case 'under_review':
        return _countUnderReview(disputes);

      case 'closed':
        return _countClosed(disputes);

      case 'all':
        return disputes.length;

      default:
        return 0;
    }
  }

  String _filterLabel(String filter) {
    switch (filter) {
      case 'active':
        return 'Needs Attention';

      case 'open':
        return 'Needs Review';

      case 'under_review':
        return 'Under Review';

      case 'closed':
        return 'Closed';

      case 'all':
        return 'All Disputes';

      default:
        return filter;
    }
  }

  IconData _filterIcon(String filter) {
    switch (filter) {
      case 'active':
        return Icons.pending_actions_rounded;

      case 'open':
        return Icons.error_outline_rounded;

      case 'under_review':
        return Icons.manage_search_rounded;

      case 'closed':
        return Icons.task_alt_rounded;

      case 'all':
        return Icons.list_alt_rounded;

      default:
        return Icons.filter_list_rounded;
    }
  }

  Color _filterColor(String filter) {
    switch (filter) {
      case 'active':
        return const Color(0xFF1557D6);

      case 'open':
        return const Color(0xFFDC2626);

      case 'under_review':
        return const Color(0xFFD97706);

      case 'closed':
        return const Color(0xFF16A34A);

      default:
        return const Color(0xFF64748B);
    }
  }

  Future<void> _startReview(PaymentDispute dispute) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.manage_search_rounded,
                color: Color(0xFFD97706),
              ),
              SizedBox(width: 10),
              Text('Start Review'),
            ],
          ),
          content: const SizedBox(
            width: 430,
            child: Text(
              'Mark this dispute as under review? '
              'This only changes its review status and does not resolve it.',
              style: TextStyle(
                height: 1.5,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
              ),
              child: const Text('Start Review'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await _updateDispute(
      dispute: dispute,
      newStatus: 'under_review',
      resolutionNote: null,
    );
  }

  Future<void> _showResolveDialog(
    PaymentDispute dispute,
  ) async {
    String? selectedOutcome;
    final noteController = TextEditingController();

    final result = await showDialog<_ResolutionResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              titlePadding:
                  const EdgeInsets.fromLTRB(24, 22, 24, 0),
              contentPadding:
                  const EdgeInsets.fromLTRB(24, 18, 24, 8),
              actionsPadding:
                  const EdgeInsets.fromLTRB(16, 8, 16, 16),
              title: const Row(
                children: [
                  Icon(
                    Icons.gavel_rounded,
                    color: Color(0xFF1557D6),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Resolve Dispute',
                    style: TextStyle(
                      color: Color(0xFF10213F),
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose the final outcome of this dispute.',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),

                    _ResolutionOption(
                      selected:
                          selectedOutcome == 'resolved_valid',
                      icon: Icons.verified_outlined,
                      title: 'Payment is valid',
                      description:
                          'The reported payment was verified and no refund is required.',
                      color: const Color(0xFF16A34A),
                      onTap: () {
                        setDialogState(() {
                          selectedOutcome = 'resolved_valid';
                        });
                      },
                    ),

                    const SizedBox(height: 10),

                    _ResolutionOption(
                      selected: selectedOutcome ==
                          'resolved_refund_arranged',
                      icon: Icons.handshake_outlined,
                      title: 'Refund arranged directly',
                      description:
                          'The tourist and driver have arranged the refund outside TourisTrike.',
                      color: const Color(0xFF7C3AED),
                      onTap: () {
                        setDialogState(() {
                          selectedOutcome =
                              'resolved_refund_arranged';
                        });
                      },
                    ),

                    const SizedBox(height: 10),

                    _ResolutionOption(
                      selected: selectedOutcome == 'rejected',
                      icon: Icons.block_outlined,
                      title: 'Reject dispute',
                      description:
                          'The dispute is invalid or does not require further action.',
                      color: const Color(0xFFDC2626),
                      onTap: () {
                        setDialogState(() {
                          selectedOutcome = 'rejected';
                        });
                      },
                    ),

                    const SizedBox(height: 18),

                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Resolution note',
                        hintText:
                            'Optional details about the decision',
                        alignLabelWithHint: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1557D6)
                            .withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 17,
                            color: Color(0xFF1557D6),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Resolving this dispute only updates its '
                              'TourisTrike record. TourisTrike does not '
                              'hold or transfer GCash/cash funds.',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selectedOutcome == null
                      ? null
                      : () {
                          Navigator.pop(
                            dialogContext,
                            _ResolutionResult(
                              status: selectedOutcome!,
                              note: noteController.text.trim(),
                            ),
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF1557D6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('Confirm Resolution'),
                ),
              ],
            );
          },
        );
      },
    );

    noteController.dispose();

    if (result == null || !mounted) return;

    await _updateDispute(
      dispute: dispute,
      newStatus: result.status,
      resolutionNote:
          result.note.isEmpty ? null : result.note,
    );
  }

  Future<void> _updateDispute({
    required PaymentDispute dispute,
    required String newStatus,
    required String? resolutionNote,
  }) async {
    final disputeId = dispute.id as String;

    if (_processingDisputeIds.contains(disputeId)) {
      return;
    }

    setState(() {
      _processingDisputeIds.add(disputeId);
    });

    try {
      await _repo.resolvePaymentDispute(
        disputeId: disputeId,
        newStatus: newStatus,
        resolutionNote: resolutionNote,
      );

      if (!mounted) return;

      final nextLoad = _load();

      setState(() {
        _future = nextLoad;
      });

      showSubTenantSnack(
        context,
        _successMessage(newStatus),
        error: false,
      );
    } catch (e) {
      if (!mounted) return;

      showSubTenantSnack(
        context,
        'Unable to update dispute: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingDisputeIds.remove(disputeId);
        });
      }
    }
  }

  String _successMessage(String status) {
    switch (status) {
      case 'under_review':
        return 'Dispute is now under review.';

      case 'resolved_valid':
        return 'Dispute closed. Payment confirmed as valid.';

      case 'resolved_refund_arranged':
        return 'Dispute closed. Direct refund arrangement recorded.';

      case 'rejected':
        return 'Dispute closed as rejected.';

      default:
        return 'Dispute updated.';
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'Needs Review';

      case 'under_review':
        return 'Under Review';

      case 'resolved_valid':
        return 'Payment Valid';

      case 'resolved_refund_arranged':
        return 'Refund Arranged';

      case 'rejected':
        return 'Rejected';

      default:
        return status.replaceAll('_', ' ');
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return const Color(0xFFDC2626);

      case 'under_review':
        return const Color(0xFFD97706);

      case 'resolved_valid':
        return const Color(0xFF16A34A);

      case 'resolved_refund_arranged':
        return const Color(0xFF7C3AED);

      case 'rejected':
        return const Color(0xFFDC2626);

      default:
        return const Color(0xFF64748B);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'open':
        return Icons.error_outline_rounded;

      case 'under_review':
        return Icons.manage_search_rounded;

      case 'resolved_valid':
        return Icons.verified_outlined;

      case 'resolved_refund_arranged':
        return Icons.handshake_outlined;

      case 'rejected':
        return Icons.block_outlined;

      default:
        return Icons.receipt_long_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: 7,
      title: 'Payment Disputes',
      subtitle:
          'Review and resolve reported GCash and cash payment issues.',
      child: FutureBuilder<_DisputesLoad>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const SubTenantLoadingView();
          }

          if (snapshot.hasError) {
            return SubTenantErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final load = snapshot.data!;

          final filtered = load.disputes
              .where(_matchesFilter)
              .toList();

          final openCount =
              _countOpen(load.disputes);

          final reviewCount =
              _countUnderReview(load.disputes);

          final closedCount =
              _countClosed(load.disputes);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ResponsivePageContainer(
              children: [
                _DisputeToolbar(
                  openCount: openCount,
                  reviewCount: reviewCount,
                  closedCount: closedCount,
                  totalCount: load.disputes.length,
                  selectedFilter: _statusFilter,
                  filterOptions: _filterOptions,
                  filterLabel: _filterLabel,
                  filterIcon: _filterIcon,
                  filterColor: _filterColor,
                  filterCount: (filter) =>
                      _countForFilter(
                    load.disputes,
                    filter,
                  ),
                  onFilterChanged: (filter) {
                    setState(() {
                      _statusFilter = filter;
                    });
                  },
                ),

                const SizedBox(height: 18),

                _ResultsHeader(
                  title: _filterLabel(_statusFilter),
                  count: filtered.length,
                ),

                const SizedBox(height: 10),

                if (filtered.isEmpty)
                  _EmptyDisputes(
                    label: _filterLabel(_statusFilter),
                  )
                else
                  ...filtered.map(
                    (dispute) {
                      final record =
                          load.records[
                              dispute.paymentRecordId];

                      final disputeId =
                          dispute.id as String;

                      return Padding(
                        padding:
                            const EdgeInsets.only(
                          bottom: 12,
                        ),
                        child: _DisputeCard(
                          dispute: dispute,
                          record: record,
                          raisedByName: load
                                  .profiles[
                                      dispute.raisedBy]
                                  ?.displayName ??
                              'Unknown',
                          payerName: record != null
                              ? load
                                  .profiles[
                                      record.payerId]
                                  ?.displayName
                              : null,
                          payeeName: record != null
                              ? load
                                  .profiles[
                                      record.payeeId]
                                  ?.displayName
                              : null,
                          isProcessing:
                              _processingDisputeIds
                                  .contains(
                            disputeId,
                          ),
                          statusColor:
                              _statusColor(
                            dispute.status,
                          ),
                          statusIcon:
                              _statusIcon(
                            dispute.status,
                          ),
                          statusLabel:
                              _statusLabel(
                            dispute.status,
                          ),
                          onStartReview: () {
                            _startReview(dispute);
                          },
                          onResolve: () {
                            _showResolveDialog(
                              dispute,
                            );
                          },
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 8),

                const _PolicyNote(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DisputeToolbar extends StatelessWidget {
  const _DisputeToolbar({
    required this.openCount,
    required this.reviewCount,
    required this.closedCount,
    required this.totalCount,
    required this.selectedFilter,
    required this.filterOptions,
    required this.filterLabel,
    required this.filterIcon,
    required this.filterColor,
    required this.filterCount,
    required this.onFilterChanged,
  });

  final int openCount;
  final int reviewCount;
  final int closedCount;
  final int totalCount;

  final String selectedFilter;

  final List<String> filterOptions;

  final String Function(String) filterLabel;
  final IconData Function(String) filterIcon;
  final Color Function(String) filterColor;
  final int Function(String) filterCount;

  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 850;

        final counts = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _CountItem(
              label: 'Needs Review',
              value: openCount,
              icon:
                  Icons.error_outline_rounded,
              color:
                  const Color(0xFFDC2626),
            ),
            _CountItem(
              label: 'Under Review',
              value: reviewCount,
              icon:
                  Icons.manage_search_rounded,
              color:
                  const Color(0xFFD97706),
            ),
            _CountItem(
              label: 'Closed',
              value: closedCount,
              icon:
                  Icons.task_alt_rounded,
              color:
                  const Color(0xFF16A34A),
            ),
            _CountItem(
              label: 'Total',
              value: totalCount,
              icon:
                  Icons.receipt_long_outlined,
              color:
                  const Color(0xFF64748B),
            ),
          ],
        );

        final filter =
            PopupMenuButton<String>(
          tooltip: 'Filter disputes',
          initialValue: selectedFilter,
          onSelected: onFilterChanged,
          position:
              PopupMenuPosition.under,
          offset: const Offset(0, 6),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(16),
          ),
          itemBuilder: (context) {
            return filterOptions
                .map((filter) {
              final selected =
                  filter == selectedFilter;

              final color =
                  filterColor(filter);

              return PopupMenuItem<String>(
                value: filter,
                child: SizedBox(
                  width: 230,
                  child: Row(
                    children: [
                      Icon(
                        filterIcon(filter),
                        size: 18,
                        color: color,
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      Expanded(
                        child: Text(
                          filterLabel(
                            filter,
                          ),
                          style: TextStyle(
                            fontWeight:
                                selected
                                    ? FontWeight
                                        .w800
                                    : FontWeight
                                        .w600,
                            color:
                                const Color(
                              0xFF10213F,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration:
                            BoxDecoration(
                          color: const Color(
                            0xFFF1F5F9,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            99,
                          ),
                        ),
                        child: Text(
                          '${filterCount(filter)}',
                          style:
                              const TextStyle(
                            color: Color(
                              0xFF64748B,
                            ),
                            fontSize: 11,
                            fontWeight:
                                FontWeight
                                    .w700,
                          ),
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(
                          width: 8,
                        ),
                        const Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: Color(
                            0xFF1557D6,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList();
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(12),
              border: Border.all(
                color:
                    const Color(0xFFDCE4EF),
              ),
            ),
            child: Row(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const Icon(
                  Icons.filter_list_rounded,
                  size: 18,
                  color:
                      Color(0xFF1557D6),
                ),
                const SizedBox(width: 8),
                Text(
                  filterLabel(
                    selectedFilter,
                  ),
                  style: const TextStyle(
                    color:
                        Color(0xFF10213F),
                    fontSize: 12,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons
                      .keyboard_arrow_down_rounded,
                  size: 17,
                  color:
                      Color(0xFF64748B),
                ),
              ],
            ),
          ),
        );

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(18),
            border: Border.all(
              color:
                  const Color(0xFFE2E8F0),
            ),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    counts,
                    const SizedBox(
                      height: 14,
                    ),
                    Align(
                      alignment:
                          Alignment
                              .centerRight,
                      child: filter,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: counts,
                    ),
                    const SizedBox(
                      width: 16,
                    ),
                    filter,
                  ],
                ),
        );
      },
    );
  }
}

class _CountItem extends StatelessWidget {
  const _CountItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.07,
        ),
        borderRadius:
            BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight:
                  FontWeight.w900,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color:
                  Color(0xFF475569),
              fontSize: 11,
              fontWeight:
                  FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.title,
    required this.count,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color:
                    Color(0xFF10213F),
                fontSize: 14,
                fontWeight:
                    FontWeight.w800,
              ),
            ),
          ),
          Text(
            '$count ${count == 1 ? 'dispute' : 'disputes'}',
            style: const TextStyle(
              color:
                  Color(0xFF64748B),
              fontSize: 11,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DisputeCard extends StatelessWidget {
  const _DisputeCard({
    required this.dispute,
    required this.record,
    required this.raisedByName,
    required this.payerName,
    required this.payeeName,
    required this.isProcessing,
    required this.statusColor,
    required this.statusIcon,
    required this.statusLabel,
    required this.onStartReview,
    required this.onResolve,
  });

  final PaymentDispute dispute;
  final PaymentRecord? record;

  final String raisedByName;
  final String? payerName;
  final String? payeeName;

  final bool isProcessing;

  final Color statusColor;
  final IconData statusIcon;
  final String statusLabel;

  final VoidCallback onStartReview;
  final VoidCallback onResolve;

  bool get _canResolve =>
      dispute.status == 'open' ||
      dispute.status == 'under_review';

  @override
  Widget build(BuildContext context) {
    final createdLabel =
        dispute.createdAt != null
            ? DateFormat.yMMMd()
                .add_jm()
                .format(
                  dispute.createdAt!
                      .toLocal(),
                )
            : '-';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color:
              const Color(0xFFE2E8F0),
        ),
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(18),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 190,
              color: statusColor,
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  18,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Row(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration:
                              BoxDecoration(
                            color: statusColor
                                .withValues(
                              alpha: 0.09,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              12,
                            ),
                          ),
                          child: Icon(
                            statusIcon,
                            size: 20,
                            color:
                                statusColor,
                          ),
                        ),
                        const SizedBox(
                          width: 12,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                paymentDisputeReasons[
                                        dispute
                                            .reason] ??
                                    dispute
                                        .reason,
                                style:
                                    const TextStyle(
                                  color: Color(
                                    0xFF10213F,
                                  ),
                                  fontSize: 14,
                                  fontWeight:
                                      FontWeight
                                          .w800,
                                ),
                              ),
                              const SizedBox(
                                height: 3,
                              ),
                              Text(
                                'Raised by $raisedByName',
                                style:
                                    const TextStyle(
                                  color: Color(
                                    0xFF64748B,
                                  ),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration:
                              BoxDecoration(
                            color: statusColor
                                .withValues(
                              alpha: 0.08,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              99,
                            ),
                          ),
                          child: Text(
                            statusLabel
                                .toUpperCase(),
                            style:
                                TextStyle(
                              color:
                                  statusColor,
                              fontSize: 9,
                              fontWeight:
                                  FontWeight
                                      .w800,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    _PaymentInfo(
                      record: record,
                      payerName:
                          payerName,
                      payeeName:
                          payeeName,
                      createdLabel:
                          createdLabel,
                    ),

                    if (dispute
                        .description
                        .isNotEmpty) ...[
                      const SizedBox(
                        height: 12,
                      ),
                      Text(
                        dispute
                            .description,
                        style:
                            const TextStyle(
                          color: Color(
                            0xFF475569,
                          ),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],

                    if (dispute
                        .resolutionNote
                        .isNotEmpty) ...[
                      const SizedBox(
                        height: 12,
                      ),
                      Container(
                        width:
                            double.infinity,
                        padding:
                            const EdgeInsets
                                .all(10),
                        decoration:
                            BoxDecoration(
                          color: const Color(
                            0xFFF8FAFC,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            10,
                          ),
                        ),
                        child: Text(
                          'Resolution note: ${dispute.resolutionNote}',
                          style:
                              const TextStyle(
                            color: Color(
                              0xFF64748B,
                            ),
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],

                    if (_canResolve) ...[
                      const SizedBox(
                        height: 14,
                      ),
                      const Divider(
                        height: 1,
                        color: Color(
                          0xFFE2E8F0,
                        ),
                      ),
                      const SizedBox(
                        height: 12,
                      ),

                      if (isProcessing)
                        const Row(
                          mainAxisSize:
                              MainAxisSize
                                  .min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            ),
                            SizedBox(
                              width: 8,
                            ),
                            Text(
                              'Updating dispute...',
                              style:
                                  TextStyle(
                                color: Color(
                                  0xFF64748B,
                                ),
                                fontSize:
                                    12,
                                fontWeight:
                                    FontWeight
                                        .w600,
                              ),
                            ),
                          ],
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (dispute
                                    .status ==
                                'open')
                              OutlinedButton
                                  .icon(
                                onPressed:
                                    onStartReview,
                                icon:
                                    const Icon(
                                  Icons
                                      .manage_search_rounded,
                                  size: 17,
                                ),
                                label:
                                    const Text(
                                  'Start Review',
                                ),
                              ),

                            FilledButton
                                .icon(
                              onPressed:
                                  onResolve,
                              icon:
                                  const Icon(
                                Icons
                                    .gavel_rounded,
                                size: 17,
                              ),
                              label:
                                  const Text(
                                'Resolve Dispute',
                              ),
                              style:
                                  FilledButton
                                      .styleFrom(
                                backgroundColor:
                                    const Color(
                                  0xFF1557D6,
                                ),
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  horizontal:
                                      16,
                                  vertical:
                                      12,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentInfo extends StatelessWidget {
  const _PaymentInfo({
    required this.record,
    required this.payerName,
    required this.payeeName,
    required this.createdLabel,
  });

  final PaymentRecord? record;
  final String? payerName;
  final String? payeeName;
  final String createdLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            const Color(0xFFF8FAFC),
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color:
              const Color(0xFFEDF1F6),
        ),
      ),
      child: Wrap(
        spacing: 28,
        runSpacing: 10,
        children: [
          _InfoItem(
            label: 'Amount',
            value: record != null
                ? 'PHP ${record!.amount.toStringAsFixed(2)}'
                : 'Unavailable',
            emphasized: true,
          ),
          _InfoItem(
            label: 'Method',
            value: record != null
                ? record!
                    .paymentMethod
                    .toUpperCase()
                : '—',
          ),
          if (record != null &&
              record!
                  .externalReferenceNo
                  .isNotEmpty)
            _InfoItem(
              label: 'Reference',
              value: record!
                  .externalReferenceNo,
            ),
          if (payerName != null)
            _InfoItem(
              label: 'Payer',
              value: payerName!,
            ),
          if (payeeName != null)
            _InfoItem(
              label: 'Payee',
              value: payeeName!,
            ),
          _InfoItem(
            label: 'Filed',
            value: createdLabel,
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints:
          const BoxConstraints(
        minWidth: 90,
        maxWidth: 220,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color:
                  Color(0xFF94A3B8),
              fontSize: 8,
              fontWeight:
                  FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow:
                TextOverflow.ellipsis,
            style: TextStyle(
              color:
                  const Color(
                0xFF334155,
              ),
              fontSize:
                  emphasized ? 13 : 11,
              fontWeight:
                  emphasized
                      ? FontWeight.w900
                      : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolutionOption
    extends StatelessWidget {
  const _ResolutionOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(14),
      child: AnimatedContainer(
        duration:
            const Duration(
          milliseconds: 150,
        ),
        padding:
            const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(
                  alpha: 0.06,
                )
              : Colors.white,
          borderRadius:
              BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? color
                : const Color(
                    0xFFE2E8F0,
                  ),
            width:
                selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(
                  alpha: 0.09,
                ),
                borderRadius:
                    BorderRadius.circular(
                  11,
                ),
              ),
              child: Icon(
                icon,
                size: 19,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(
                        0xFF10213F,
                      ),
                      fontSize: 13,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    description,
                    style:
                        const TextStyle(
                      color: Color(
                        0xFF64748B,
                      ),
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected
                  ? Icons
                      .radio_button_checked
                  : Icons
                      .radio_button_off,
              color: selected
                  ? color
                  : const Color(
                      0xFFCBD5E1,
                    ),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDisputes
    extends StatelessWidget {
  const _EmptyDisputes({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 44,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color:
              const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(
                0xFF16A34A,
              ).withValues(
                alpha: 0.08,
              ),
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
            ),
            child: const Icon(
              Icons
                  .verified_outlined,
              color:
                  Color(0xFF16A34A),
              size: 25,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Nothing here',
            style: TextStyle(
              color:
                  Color(0xFF10213F),
              fontSize: 15,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'There are no $label disputes right now.',
            textAlign:
                TextAlign.center,
            style: const TextStyle(
              color:
                  Color(0xFF64748B),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyNote extends StatelessWidget {
  const _PolicyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(
          0xFF1557D6,
        ).withValues(
          alpha: 0.045,
        ),
        borderRadius:
            BorderRadius.circular(13),
        border: Border.all(
          color: const Color(
            0xFF1557D6,
          ).withValues(
            alpha: 0.10,
          ),
        ),
      ),
      child: const Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 17,
            color:
                Color(0xFF1557D6),
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Resolving a dispute updates its TourisTrike record only. '
              'TourisTrike does not hold or transfer GCash/cash funds. '
              'Any applicable refund is arranged directly between the parties.',
              style: TextStyle(
                color:
                    Color(0xFF475569),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolutionResult {
  const _ResolutionResult({
    required this.status,
    required this.note,
  });

  final String status;
  final String note;
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