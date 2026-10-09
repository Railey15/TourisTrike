import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tour_stay_details.dart';

/// Read-only presentation of the server's booked-stay and waiting ledger.
class TourStayStatusCard extends StatefulWidget {
  const TourStayStatusCard({
    super.key,
    required this.bookingId,
    this.currentItemId,
    this.currentDestination,
    this.includedMinutes,
    this.showPaymentSummary = false,
    this.showDestinationDetails = true,
    this.inlineTimingOnly = false,
  });

  final String bookingId;
  final String? currentItemId;
  final String? currentDestination;
  final int? includedMinutes;
  final bool showPaymentSummary;
  final bool showDestinationDetails;
  final bool inlineTimingOnly;

  @override
  State<TourStayStatusCard> createState() => _TourStayStatusCardState();
}

class _TourStayStatusCardState extends State<TourStayStatusCard> {
  Map<String, dynamic>? _summary;
  RealtimeChannel? _channel;
  Timer? _ticker;
  Timer? _refreshTimer;
  final Stopwatch _serverClock = Stopwatch();
  DateTime? _serverTime;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _summary != null) setState(() {});
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void didUpdateWidget(covariant TourStayStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId) {
      _summary = null;
      _load();
      _subscribe();
    } else if (oldWidget.currentItemId != widget.currentItemId ||
        oldWidget.showPaymentSummary != widget.showPaymentSummary) {
      _load();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _refreshTimer?.cancel();
    _channel?.unsubscribe();
    _serverClock.stop();
    super.dispose();
  }

  Future<void> _load() async {
    final bookingId = widget.bookingId;
    try {
      final result = await Supabase.instance.client.rpc(
        'get_booking_waiting_summary',
        params: {'p_booking_id': bookingId},
      );
      if (!mounted || bookingId != widget.bookingId || result is! Map) return;
      final summary = Map<String, dynamic>.from(result);
      _serverTime = DateTime.tryParse('${summary['server_time']}')?.toUtc();
      _serverClock
        ..reset()
        ..start();
      setState(() {
        _summary = summary;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Waiting policy unavailable');
    }
  }

  void _subscribe() {
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('waiting:${widget.bookingId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'booking_stop_waiting_charges',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: widget.bookingId,
          ),
          callback: (_) => unawaited(_load()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'booking_payment_requirements',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: widget.bookingId,
          ),
          callback: (_) => unawaited(_load()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'package_bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.bookingId,
          ),
          callback: (_) => unawaited(_load()),
        )
        .subscribe();
  }

  DateTime get _now =>
      (_serverTime ?? DateTime.now().toUtc()).add(_serverClock.elapsed);

  static double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse('$value')?.toLocal();

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null) {
      return _error == null
          ? const SizedBox.shrink()
          : Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            );
    }
    final charges = (summary['charges'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final active = charges
        .where((row) => row['status'] == 'active')
        .firstOrNull;
    final current =
        active ??
        charges
            .where(
              (row) =>
                  row['itinerary_item_id']?.toString() == widget.currentItemId,
            )
            .firstOrNull;
    final deadline = _date(current?['paid_until']);
    final seconds = deadline == null
        ? 0
        : deadline.difference(_now.toLocal()).inSeconds;
    final rate = current == null
        ? summary['current_rate_per_interval'] ??
              summary['current_rate_per_15_minutes']
        : current['rate_per_interval'];
    final intervalMinutes =
        (current?['interval_minutes'] as num?)?.toInt() ??
        (summary['current_interval_minutes'] as num?)?.toInt() ??
        15;
    final hasStop =
        current?['status'] == 'active' ||
        (widget.currentDestination?.trim().isNotEmpty ?? false);
    final hasFinancialSummary =
        ['package_remaining', 'finalized_waiting', 'total_remaining'].every(
          (key) =>
              summary[key] is num || double.tryParse('${summary[key]}') != null,
        );
    final paymentRequired =
        widget.showPaymentSummary &&
        (!hasFinancialSummary || _number(summary['total_remaining']) > 0);
    if (widget.inlineTimingOnly) {
      if (current?['status'] != 'active' || deadline == null) {
        return const SizedBox.shrink();
      }
      return TourStayDetails(
        destination: '',
        includedMinutes: null,
        secondsRemaining: seconds,
        rate: rate == null ? null : _number(rate),
        intervalMinutes: intervalMinutes,
        accruedWaiting: _number(current?['additional_amount']),
        showDestination: false,
        showIncluded: false,
      );
    }
    if (!(widget.showDestinationDetails && hasStop) && !paymentRequired) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showDestinationDetails && hasStop)
              TourStayDetails(
                destination:
                    current?['destination_name']?.toString() ??
                    widget.currentDestination!,
                includedMinutes:
                    (current?['included_minutes'] as num?)?.toInt() ??
                    widget.includedMinutes,
                secondsRemaining:
                    current?['status'] == 'active' && deadline != null
                    ? seconds
                    : null,
                rate: rate == null ? null : _number(rate),
                intervalMinutes: intervalMinutes,
                accruedWaiting: current == null
                    ? null
                    : _number(current['additional_amount']),
              ),
            if (paymentRequired) ...[
              if (widget.showDestinationDetails && hasStop)
                const Divider(height: 24),
              Text(
                'Payment required',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                hasFinancialSummary
                    ? 'Settle the remaining balance to unlock drop-off. Payment must be confirmed.'
                    : 'Payment details unavailable. Pull to refresh.',
              ),
              const SizedBox(height: 8),
              if (hasFinancialSummary)
                TourPaymentSummary(
                  packageBalance: _number(summary['package_remaining']),
                  additionalWaiting:
                      (_number(summary['total_remaining']) -
                              _number(summary['package_remaining']))
                          .clamp(0, double.infinity),
                  totalRemaining: _number(summary['total_remaining']),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
