import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _suspensionBlue = Color(0xFF2A86FF);
const _suspensionInk = Color(0xFF0F172A);
const _suspensionMuted = Color(0xFF64748B);
const _suspensionBorder = Color(0xFFE4EBF4);
const _suspensionWarning = Color(0xFFB45309);

class TouristBookingSuspension {
  const TouristBookingSuspension({
    required this.caseId,
    required this.reason,
    required this.startsAt,
    required this.endsAt,
    required this.cancellationCount,
    required this.active,
    required this.appealStatus,
    this.offenseNumber = 1,
    this.manualReviewRequired = false,
    this.riskLevel = 'standard',
  });

  factory TouristBookingSuspension.fromMap(Map<String, dynamic> map) {
    DateTime? date(dynamic value) =>
        value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
    return TouristBookingSuspension(
      caseId: map['case_id']?.toString() ?? '',
      reason: map['reason']?.toString().trim().isNotEmpty == true
          ? map['reason'].toString().trim()
          : 'Three tourist-initiated bookings were cancelled today.',
      startsAt: date(map['starts_at']),
      endsAt: date(map['ends_at'] ?? map['restricted_until']),
      cancellationCount:
          int.tryParse(map['cancellation_count']?.toString() ?? '') ?? 3,
      active: map['active'] == true,
      appealStatus: map['appeal_status']?.toString() ?? '',
      offenseNumber: int.tryParse(map['offense_number']?.toString() ?? '') ?? 1,
      manualReviewRequired: map['manual_review_required'] == true,
      riskLevel: map['risk_level']?.toString() ?? 'standard',
    );
  }

  final String caseId;
  final String reason;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int cancellationCount;
  final bool active;
  final String appealStatus;
  final int offenseNumber;
  final bool manualReviewRequired;
  final String riskLevel;

  bool get appealPending => appealStatus == 'pending_review';
}

Future<TouristBookingSuspension?> loadMyTouristBookingSuspension() async {
  final value = await Supabase.instance.client.rpc(
    'get_my_tourist_booking_restriction',
  );
  if (value is! Map) return null;
  return TouristBookingSuspension.fromMap(Map<String, dynamic>.from(value));
}

Future<bool> showTouristBookingSuspensionSheet(
  BuildContext context, {
  required TouristBookingSuspension suspension,
  Future<void> Function(String reason)? onSubmitAppeal,
}) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TouristBookingSuspensionSheet(
      suspension: suspension,
      onSubmitAppeal:
          onSubmitAppeal ??
          (reason) async {
            await Supabase.instance.client.rpc(
              'appeal_tourist_booking_restriction',
              params: {'p_reason': reason},
            );
          },
    ),
  );
  return submitted == true;
}

class TouristBookingSuspensionSheet extends StatefulWidget {
  const TouristBookingSuspensionSheet({
    super.key,
    required this.suspension,
    required this.onSubmitAppeal,
  });

  final TouristBookingSuspension suspension;
  final Future<void> Function(String reason) onSubmitAppeal;

  @override
  State<TouristBookingSuspensionSheet> createState() =>
      _TouristBookingSuspensionSheetState();
}

class _TouristBookingSuspensionSheetState
    extends State<TouristBookingSuspensionSheet> {
  final _reason = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmitAppeal(_reason.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final message = error.toString();
      final duplicate =
          message.contains('APPEAL_ALREADY_SUBMITTED') ||
          message.contains('APPEAL_ALREADY_PENDING');
      setState(() {
        _submitting = false;
        _error = duplicate
            ? 'An appeal for this suspension is already under review.'
            : 'Unable to submit your appeal right now. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final end = widget.suspension.endsAt;
    final endLabel = end == null
        ? 'End time unavailable'
        : DateFormat('MMM d, yyyy, h:mm a').format(end);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFFFFF7ED),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.lock_clock_outlined,
                            color: _suspensionWarning,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Appeal Booking Suspension',
                          style: TextStyle(
                            color: _suspensionInk,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your booking privileges are temporarily suspended. Existing bookings, payments, refunds, and support remain available.',
                    style: TextStyle(color: _suspensionMuted, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SuspensionDetail(
                          label: 'Reason',
                          value: widget.suspension.reason,
                        ),
                        const SizedBox(height: 10),
                        _SuspensionDetail(
                          label: 'Suspension ends',
                          value: endLabel,
                        ),
                        const SizedBox(height: 10),
                        _SuspensionDetail(
                          label: 'Offense level',
                          value: 'Offense #${widget.suspension.offenseNumber}',
                        ),
                        if (widget.suspension.appealStatus.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _SuspensionDetail(
                            label: 'Appeal status',
                            value: widget.suspension.appealStatus.replaceAll(
                              '_',
                              ' ',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.suspension.appealPending) ...[
                    const SizedBox(height: 16),
                    const _AppealPendingNotice(),
                  ] else ...[
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _reason,
                      enabled: !_submitting,
                      minLines: 4,
                      maxLines: 7,
                      maxLength: 1000,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Explain your reason',
                        hintText:
                            'Tell the tourism office why this suspension should be reviewed.',
                        alignLabelWithHint: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: _suspensionBorder,
                          ),
                        ),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 10
                          ? 'Please provide at least 10 characters.'
                          : null,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                          child: Text(
                            widget.suspension.appealPending
                                ? 'Close'
                                : 'Cancel',
                          ),
                        ),
                      ),
                      if (!widget.suspension.appealPending) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _submitting ? null : _submit,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              backgroundColor: _suspensionBlue,
                            ),
                            child: _submitting
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Submit Appeal'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TouristBookingSuspensionNotice extends StatefulWidget {
  const TouristBookingSuspensionNotice({super.key});

  @override
  State<TouristBookingSuspensionNotice> createState() =>
      _TouristBookingSuspensionNoticeState();
}

class _TouristBookingSuspensionNoticeState
    extends State<TouristBookingSuspensionNotice> {
  late Future<TouristBookingSuspension?> _future =
      loadMyTouristBookingSuspension();

  void _refresh() {
    final next = loadMyTouristBookingSuspension();
    if (!mounted) return;
    setState(() => _future = next);
  }

  Future<void> _appeal(TouristBookingSuspension suspension) async {
    final submitted = await showTouristBookingSuspensionSheet(
      context,
      suspension: suspension,
    );
    if (!mounted || !submitted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Your appeal was submitted for review.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TouristBookingSuspension?>(
      future: _future,
      builder: (context, snapshot) {
        final suspension = snapshot.data;
        if (suspension == null || !suspension.active) {
          return const SizedBox.shrink();
        }
        final end = suspension.endsAt;
        final endLabel = end == null
            ? 'the stated end time'
            : DateFormat('MMM d, yyyy, h:mm a').format(end);
        return Card(
          color: const Color(0xFFFFFBEB),
          margin: const EdgeInsets.only(bottom: 14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_clock_outlined, color: _suspensionWarning),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Booking privileges temporarily suspended',
                        style: TextStyle(
                          color: _suspensionInk,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Your booking privileges have been temporarily suspended for 3 days because ${suspension.cancellationCount} bookings were cancelled today.',
                  style: const TextStyle(color: _suspensionMuted, height: 1.4),
                ),
                const SizedBox(height: 5),
                Text(
                  'Ends $endLabel',
                  style: const TextStyle(
                    color: _suspensionInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Offense #${suspension.offenseNumber}'
                  '${suspension.manualReviewRequired ? ' · Manual review required' : ''}',
                  style: const TextStyle(
                    color: _suspensionWarning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                if (suspension.appealPending)
                  const Text(
                    'Appeal pending review',
                    style: TextStyle(
                      color: _suspensionWarning,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _appeal(suspension),
                    icon: const Icon(Icons.rate_review_outlined),
                    label: const Text('Appeal'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SuspensionDetail extends StatelessWidget {
  const _SuspensionDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: _suspensionMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(
          color: _suspensionInk,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    ],
  );
}

class _AppealPendingNotice extends StatelessWidget {
  const _AppealPendingNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFBFDBFE)),
    ),
    child: const Row(
      children: [
        Icon(Icons.schedule_rounded, color: _suspensionBlue),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Your appeal is pending review. You cannot submit another appeal for this suspension.',
            style: TextStyle(color: _suspensionInk, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class TouristBookingSuspensionDetailsScreen extends StatefulWidget {
  const TouristBookingSuspensionDetailsScreen({super.key});

  @override
  State<TouristBookingSuspensionDetailsScreen> createState() =>
      _TouristBookingSuspensionDetailsScreenState();
}

class _TouristBookingSuspensionDetailsScreenState
    extends State<TouristBookingSuspensionDetailsScreen> {
  late Future<TouristBookingSuspension?> _future =
      loadMyTouristBookingSuspension();

  void _reload() => setState(() {
    _future = loadMyTouristBookingSuspension();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Booking Suspension')),
    body: FutureBuilder<TouristBookingSuspension?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          );
        }
        final suspension = snapshot.data;
        if (suspension == null) {
          return const Center(
            child: Text('No booking suspension record is available.'),
          );
        }
        final end = suspension.endsAt;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suspension.active
                          ? 'Booking privileges temporarily suspended'
                          : 'Booking suspension ended',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SuspensionDetail(
                      label: 'Reason',
                      value: suspension.reason,
                    ),
                    const SizedBox(height: 12),
                    _SuspensionDetail(
                      label: 'End date and time',
                      value: end == null
                          ? 'Unavailable'
                          : DateFormat('MMM d, yyyy, h:mm a').format(end),
                    ),
                    const SizedBox(height: 12),
                    _SuspensionDetail(
                      label: 'Offense level',
                      value: 'Offense #${suspension.offenseNumber}',
                    ),
                    const SizedBox(height: 12),
                    _SuspensionDetail(
                      label: 'Appeal status',
                      value: suspension.appealStatus.isEmpty
                          ? 'Eligible to appeal'
                          : suspension.appealStatus.replaceAll('_', ' '),
                    ),
                    if (suspension.active &&
                        !suspension.appealPending &&
                        suspension.appealStatus.isEmpty) ...[
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () async {
                          final submitted =
                              await showTouristBookingSuspensionSheet(
                                context,
                                suspension: suspension,
                              );
                          if (submitted && mounted) _reload();
                        },
                        icon: const Icon(Icons.rate_review_outlined),
                        label: const Text('Submit Appeal'),
                      ),
                    ],
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
