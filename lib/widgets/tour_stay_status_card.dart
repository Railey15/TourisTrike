import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only presentation of the server's booked-stay and waiting ledger.
class TourStayStatusCard extends StatefulWidget {
  const TourStayStatusCard({
    super.key,
    required this.bookingId,
    this.currentItemId,
    this.currentDestination,
  });

  final String bookingId;
  final String? currentItemId;
  final String? currentDestination;

  @override
  State<TourStayStatusCard> createState() => _TourStayStatusCardState();
}

class _TourStayStatusCardState extends State<TourStayStatusCard> {
  Map<String, dynamic>? _summary;
  RealtimeChannel? _channel;
  Timer? _ticker;
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
  }

  @override
  void didUpdateWidget(covariant TourStayStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId) {
      _summary = null;
      _load();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _channel?.unsubscribe();
    _serverClock.stop();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await Supabase.instance.client.rpc(
        'get_booking_waiting_summary',
        params: {'p_booking_id': widget.bookingId},
      );
      if (!mounted || result is! Map) return;
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
        .subscribe();
  }

  DateTime get _now =>
      (_serverTime ?? DateTime.now().toUtc()).add(_serverClock.elapsed);

  static double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static String _money(Object? value) =>
      '₱${NumberFormat('#,##0.00').format(_number(value))}';

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse('$value')?.toLocal();

  static String _clock(Duration duration) {
    final seconds = duration.inSeconds.abs();
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

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
    final arrival = _date(current?['arrived_at']);
    final seconds = deadline == null
        ? 0
        : deadline.difference(_now.toLocal()).inSeconds;
    final overtime =
        current != null && current['status'] == 'active' && seconds < 0;
    final rate = current == null
        ? summary['current_rate_per_15_minutes']
        : current['rate_per_interval'];
    final rateConfigured = rate != null;
    final fmt = DateFormat('MMM d, h:mm a');
    final finalized = charges
        .where(
          (row) =>
              row['status'] == 'finalized' &&
              _number(row['additional_amount']) > 0,
        )
        .toList();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              overtime
                  ? (rateConfigured ? 'ADDITIONAL WAITING' : 'STAY OVERTIME')
                  : 'INCLUDED TIME OF STAY',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              current?['destination_name']?.toString() ??
                  widget.currentDestination ??
                  'Next destination',
            ),
            Text('Municipality: ${summary['municipality'] ?? '—'}'),
            Text(
              rateConfigured
                  ? 'Additional waiting: ${_money(rate)} per started 15 minutes'
                  : current == null
                  ? 'Municipality waiting rate is not configured'
                  : 'No additional waiting fee for this stop: the municipality rate was not configured at arrival',
            ),
            if (arrival != null) ...[
              const SizedBox(height: 8),
              Text('Arrived: ${fmt.format(arrival)}'),
              Text('Included stay: ${current!['included_minutes']} minutes'),
              Text('Paid until: ${fmt.format(deadline!)}'),
              if (current['status'] == 'active')
                Text(
                  overtime
                      ? 'Overtime: ${_clock(Duration(seconds: -seconds))}'
                      : 'Remaining included time: ${_clock(Duration(seconds: seconds))}',
                ),
              if (!overtime && current['status'] == 'active' && seconds <= 900)
                const Text('Paid stay ending soon'),
              if (overtime) ...[
                if (rateConfigured) ...[
                  Text(
                    'Chargeable intervals: ${current['chargeable_intervals']}',
                  ),
                  Text(
                    'Accrued additional waiting: ${_money(current['additional_amount'])}',
                  ),
                ],
              ],
            ],
            if (finalized.isNotEmpty) ...[
              const Divider(height: 22),
              for (final row in finalized)
                Text(
                  '${row['destination_name']}: '
                  '${(row['overtime_seconds'] as num? ?? 0).toInt() ~/ 60} min, '
                  '${row['chargeable_intervals']} intervals, '
                  '${_money(row['additional_amount'])}',
                ),
            ],
            const Divider(height: 22),
            Text('Package remaining: ${_money(summary['package_remaining'])}'),
            Text(
              'Finalized additional waiting: ${_money(summary['finalized_waiting'])}',
            ),
            if (_number(summary['accrued_waiting']) > 0)
              Text(
                'Accrued additional waiting: ${_money(summary['accrued_waiting'])}',
              ),
            Text(
              'Total remaining: ${_money(summary['total_remaining'])}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
