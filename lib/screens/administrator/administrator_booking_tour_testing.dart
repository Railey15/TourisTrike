import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/administrator/widgets/system_admin_shared.dart';

@visibleForTesting
int bookingTestChargeableIntervals(int overtimeMinutes, int intervalMinutes) {
  if (overtimeMinutes < 0 || intervalMinutes < 1) return 0;
  return overtimeMinutes ~/ intervalMinutes;
}

abstract class BookingDeveloperToolsGateway {
  Future<Map<String, dynamic>> load(dynamic bookingId);

  Future<Map<String, dynamic>> applyTiming({
    required dynamic bookingId,
    required String mode,
    required int minutes,
    double? customRate,
  });

  Future<Map<String, dynamic>> resetTiming({
    required dynamic bookingId,
    required String scope,
  });

  Future<Map<String, dynamic>> progress({
    required dynamic bookingId,
    required String action,
    required String expectedState,
    required int expectedStopIndex,
  });
}

class SupabaseBookingDeveloperToolsGateway
    implements BookingDeveloperToolsGateway {
  SupabaseBookingDeveloperToolsGateway({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> load(dynamic bookingId) async {
    final result = await _client.rpc(
      'administrator_get_booking_developer_state_v2',
      params: {'p_booking_id': bookingId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<Map<String, dynamic>> applyTiming({
    required dynamic bookingId,
    required String mode,
    required int minutes,
    double? customRate,
  }) async {
    final result = await _client.rpc(
      'administrator_apply_booking_timing_test',
      params: {
        'p_booking_id': bookingId,
        'p_mode': mode,
        'p_minutes': minutes,
        'p_custom_rate': customRate,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<Map<String, dynamic>> resetTiming({
    required dynamic bookingId,
    required String scope,
  }) async {
    final result = await _client.rpc(
      'administrator_reset_booking_timing_test',
      params: {'p_booking_id': bookingId, 'p_scope': scope},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<Map<String, dynamic>> progress({
    required dynamic bookingId,
    required String action,
    required String expectedState,
    required int expectedStopIndex,
  }) async {
    final result = await _client.rpc(
      'administrator_progress_booking_test_v2',
      params: {
        'p_booking_id': bookingId,
        'p_action': action,
        'p_expected_state': expectedState,
        'p_expected_stop_index': expectedStopIndex,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }
}

@immutable
class BookingDeveloperState {
  const BookingDeveloperState({
    required this.raw,
    required this.serverTime,
    required this.effectiveDeadline,
  });

  factory BookingDeveloperState.fromMap(Map<String, dynamic> map) {
    return BookingDeveloperState(
      raw: Map<String, dynamic>.unmodifiable(map),
      serverTime: DateTime.tryParse('${map['server_time']}')?.toUtc(),
      effectiveDeadline: DateTime.tryParse(
        '${map['effective_deadline'] ?? ''}',
      )?.toUtc(),
    );
  }

  final Map<String, dynamic> raw;
  final DateTime? serverTime;
  final DateTime? effectiveDeadline;

  String text(String key, [String fallback = 'Not available']) {
    final value = raw[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  int integer(String key) => switch (raw[key]) {
    final num value => value.toInt(),
    final Object value => int.tryParse('$value') ?? 0,
    _ => 0,
  };

  double number(String key) => switch (raw[key]) {
    final num value => value.toDouble(),
    final Object value => double.tryParse('$value') ?? 0,
    _ => 0,
  };

  bool boolean(String key) => raw[key] == true;

  bool get controlsEnabled => boolean('controls_enabled');
  bool get overrideActive => boolean('override_active');
  bool get terminal =>
      boolean('booking_completed') ||
      const {
        'completed',
        'done',
        'cancelled',
        'rejected',
        'expired',
      }.contains(text('booking_status'));
  bool get activeStopLedger => boolean('active_stop_waiting_ledger');
  String? actionBlocker(String action) {
    if (!controlsEnabled) {
      return 'Enable testing and activate this booking session.';
    }
    if (terminal) return 'A terminal booking cannot be changed.';
    if (raw.containsKey('accepted_driver_count') &&
        integer('accepted_driver_count') < integer('required_driver_count')) {
      return 'All required Driver slots must be accepted.';
    }
    if (raw.containsKey('convoy_aligned') && !boolean('convoy_aligned')) {
      return 'Driver tour states must align before testing can continue.';
    }
    final journey = text('journey_state');
    switch (action) {
      case 'force_start':
        if (!const {
          'assigned',
          'en_route_pickup',
          'at_pickup',
          'boarded',
        }.contains(journey)) {
          return 'Tour start is unavailable from $journey.';
        }
        if (!boolean('downpayment_ready')) {
          return 'Confirmed downpayment is required.';
        }
      case 'simulate_arrival':
        if (journey != 'en_route_stop' && journey != 'en_route_dropoff') {
          return 'The tour must be en route to a destination.';
        }
        if (journey == 'en_route_dropoff' &&
            !boolean('dropoff_payment_ready')) {
          return 'Remaining payment must be settled before drop-off.';
        }
      case 'complete_stop':
        if (journey != 'at_stop' || text('arrival_status') != 'arrived') {
          return 'Arrive at the current stop first.';
        }
        if (boolean('current_stop_completed')) {
          return 'This stop is already complete.';
        }
      case 'simulate_departure':
        if (journey != 'at_stop') return 'Arrive at the current stop first.';
        if (!boolean('current_stop_completed')) {
          return 'Complete the current stop first.';
        }
      case 'next_stop':
        if (journey != 'stop_done' || !boolean('current_stop_departed')) {
          return 'Complete and depart from the current stop first.';
        }
        if (integer('current_stop_index') + 1 >= integer('stop_count') &&
            (!boolean('dropoff_payment_ready') ||
                !boolean('remaining_payment_ready'))) {
          return 'Settle remaining payment before the drop-off leg.';
        }
      case 'previous_stop':
        if (integer('current_stop_index') == 0) {
          return 'Already at the first stop.';
        }
        if (journey != 'en_route_stop') {
          return 'Return is available only before arriving at this stop.';
        }
        if (!boolean('previous_stop_available')) {
          return 'The previous stop has a charge or settled payment history.';
        }
      case 'force_complete':
        if (journey != 'at_dropoff') return 'Arrive at drop-off first.';
        if (!boolean('all_stops_completed')) {
          return 'Complete every itinerary stop first.';
        }
        if (boolean('active_waiting_charge')) {
          return 'Finalize the waiting charge first.';
        }
        if (!boolean('remaining_payment_ready') ||
            !boolean('dropoff_payment_ready')) {
          return 'Settle remaining payment first.';
        }
    }
    return null;
  }

  int get intervalMinutes => math.max(1, integer('interval_minutes'));
  double get configuredRate => number('configured_rate');
  double? get customRate =>
      raw['custom_rate'] == null ? null : number('custom_rate');
}

class AdministratorBookingTourTesting extends StatefulWidget {
  const AdministratorBookingTourTesting({
    super.key,
    required this.bookingId,
    this.gateway,
    this.onChanged,
  });

  final dynamic bookingId;
  final BookingDeveloperToolsGateway? gateway;
  final FutureOr<void> Function()? onChanged;

  @override
  State<AdministratorBookingTourTesting> createState() =>
      _AdministratorBookingTourTestingState();
}

class _AdministratorBookingTourTestingState
    extends State<AdministratorBookingTourTesting> {
  late final BookingDeveloperToolsGateway _gateway;
  final Stopwatch _serverClock = Stopwatch();
  final TextEditingController _rateController = TextEditingController();
  final List<RealtimeChannel> _channels = <RealtimeChannel>[];
  BookingDeveloperState? _state;
  Timer? _ticker;
  bool _loading = true;
  bool _busy = false;
  bool _customRate = false;
  int _testOvertimeMinutes = 15;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? SupabaseBookingDeveloperToolsGateway();
    unawaited(_load());
    if (widget.gateway == null) _subscribe();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _serverClock.stop();
    _rateController.dispose();
    for (final channel in _channels) {
      unawaited(channel.unsubscribe());
    }
    super.dispose();
  }

  void _subscribe() {
    final client = Supabase.instance.client;
    for (final table in const [
      'package_bookings',
      'booking_drivers',
      'booking_itinerary_items',
      'booking_stop_waiting_charges',
    ]) {
      final channel = client
          .channel('admin-dev:$table:${widget.bookingId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: table == 'package_bookings' ? 'id' : 'booking_id',
              value: '${widget.bookingId}',
            ),
            callback: (_) => unawaited(_load(silent: true)),
          )
          .subscribe();
      _channels.add(channel);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final map = await _gateway.load(widget.bookingId);
      if (!mounted) return;
      final next = BookingDeveloperState.fromMap(map);
      _serverClock
        ..reset()
        ..start();
      setState(() {
        _state = next;
        _loading = false;
        _error = null;
        _customRate = next.customRate != null;
        _rateController.text = next.customRate?.toStringAsFixed(2) ?? '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = null;
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  DateTime get _now =>
      (_state?.serverTime ?? DateTime.now().toUtc()).add(_serverClock.elapsed);

  int get _remainingMinutes {
    final deadline = _state?.effectiveDeadline;
    if (deadline == null) return _state?.integer('remaining_minutes') ?? 0;
    return math.max(0, (deadline.difference(_now).inSeconds / 60).ceil());
  }

  int get _overtimeMinutes {
    final deadline = _state?.effectiveDeadline;
    if (deadline == null) return _state?.integer('overtime_minutes') ?? 0;
    return math.max(0, (_now.difference(deadline).inSeconds / 60).floor());
  }

  Future<void> _run(
    Future<Map<String, dynamic>> Function() operation, {
    String success = 'Developer override applied.',
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final map = await operation();
      if (!mounted) return;
      // The mutation response is authoritative for this transaction. Follow it
      // with a fresh read so payment and action eligibility cannot stay stale.
      Map<String, dynamic> refreshed;
      var refreshFailed = false;
      const refreshMessage =
          'Change saved, but the latest tour and payment state could not be refreshed. Close and reopen this booking.';
      try {
        refreshed = await _gateway.load(widget.bookingId);
      } catch (_) {
        refreshed = map;
        refreshFailed = true;
      }
      if (!mounted) return;
      final next = BookingDeveloperState.fromMap(refreshed);
      _serverClock
        ..reset()
        ..start();
      setState(() {
        _state = next;
        _error = refreshFailed ? refreshMessage : null;
        _customRate = next.customRate != null;
        _rateController.text = next.customRate?.toStringAsFixed(2) ?? '';
      });
      await widget.onChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(refreshFailed ? refreshMessage : success)),
      );
    } catch (error) {
      if (!mounted) return;
      final message = _friendlyError(error);
      await _load(silent: true);
      if (!mounted) return;
      try {
        await widget.onChanged?.call();
      } catch (_) {
        // The modal's own authoritative refresh still determines eligibility.
      }
      if (!mounted) return;
      if (_state != null) setState(() => _error = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setRemaining(int minutes) async {
    await _run(
      () => _gateway.applyTiming(
        bookingId: widget.bookingId,
        mode: 'remaining',
        minutes: minutes,
      ),
      success:
          'Remaining stay set to $minutes minute${minutes == 1 ? '' : 's'}.',
    );
  }

  Future<void> _applyOvertime() async {
    final customRate = _customRate
        ? double.tryParse(_rateController.text.trim())
        : null;
    if (_customRate && (customRate == null || customRate < 0)) {
      _showMessage('Enter a valid custom rate of zero or more.');
      return;
    }
    await _run(
      () => _gateway.applyTiming(
        bookingId: widget.bookingId,
        mode: 'overtime',
        minutes: _testOvertimeMinutes,
        customRate: customRate,
      ),
      success: 'Overtime test applied.',
    );
  }

  Future<void> _reset(String scope) async {
    final confirmed = await _confirm(
      title: scope == 'stay'
          ? 'Reset stay timer override?'
          : 'Reset overtime test?',
      message:
          'The booking will return to its production timer and configured fare. Package and payment history will not be changed.',
      action: 'Reset',
    );
    if (!confirmed) return;
    await _run(
      () => _gateway.resetTiming(bookingId: widget.bookingId, scope: scope),
      success: 'Test override reset.',
    );
  }

  Future<void> _progress(String action, String label) async {
    final snapshot = _state;
    if (snapshot == null) return;
    final blocker = snapshot.actionBlocker(action);
    if (blocker != null) {
      _showMessage(blocker);
      return;
    }
    final irreversible = action == 'force_complete';
    if (irreversible) {
      final confirmed = await _confirm(
        title: 'Force Complete Tour?',
        message:
            'Completion is allowed only when every stop is complete, no waiting ledger is active, and payment is settled.',
        action: 'Force Complete',
      );
      if (!confirmed) return;
    }
    await _run(() async {
      final fresh = BookingDeveloperState.fromMap(
        await _gateway.load(widget.bookingId),
      );
      if (!mounted) throw StateError('Tour testing screen closed.');
      setState(() => _state = fresh);
      final freshBlocker = fresh.actionBlocker(action);
      if (freshBlocker != null) throw StateError(freshBlocker);
      if (fresh.text('journey_state') != snapshot.text('journey_state') ||
          fresh.integer('current_stop_index') !=
              snapshot.integer('current_stop_index')) {
        throw StateError('Tour state changed. Refresh and try again.');
      }
      final result = await _gateway.progress(
        bookingId: widget.bookingId,
        action: action,
        expectedState: snapshot.text('journey_state'),
        expectedStopIndex: snapshot.integer('current_stop_index'),
      );
      final after = BookingDeveloperState.fromMap(result);
      if (after.text('journey_state') == snapshot.text('journey_state') &&
          after.integer('current_stop_index') ==
              snapshot.integer('current_stop_index') &&
          after.boolean('current_stop_completed') ==
              snapshot.boolean('current_stop_completed')) {
        throw StateError(
          'The tour state did not change. Refresh and try again.',
        );
      }
      return result;
    }, success: '$label completed.');
  }

  Future<int?> _customMinutes(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutes',
            helperText: 'Minimum 0 minutes',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 0) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyError(Object error) {
    if (error is StateError) return error.message;
    final source = '$error';
    const messages = <String, String>{
      'SYSTEM_ADMINISTRATOR_REQUIRED':
          'Only a System Administrator can use booking test controls.',
      'ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED':
          'Activate a booking test session in system Developer Tools first.',
      'ACTIVE_STOP_WAITING_LEDGER_REQUIRED':
          'Simulate arrival at the current stop before changing its timer.',
      'ARRIVAL_REQUIRES_EN_ROUTE_STOP':
          'The tour must be en route to a stop before arrival can be simulated.',
      'DEPARTURE_REQUIRES_AT_STOP':
          'The tour must be at the current stop before departure can be simulated.',
      'NEXT_STOP_REQUIRES_COMPLETED_STOP':
          'Complete the current stop before moving to the next stop.',
      'DRIVER_SLOTS_NOT_FILLED': 'All required Driver slots must be accepted.',
      'CONVOY_STATE_NOT_ALIGNED':
          'Driver tour states must align before testing can continue.',
      'DEPARTURE_REQUIRES_COMPLETED_STOP':
          'Complete the current stop before simulating departure.',
      'COMPLETE_REQUIRES_ARRIVAL': 'Arrive at the current stop first.',
      'FORCE_COMPLETE_REQUIRES_NO_ACTIVE_WAITING_LEDGER':
          'Finalize the current waiting charge before completion.',
      'STALE_BOOKING_TEST_STATE': 'Tour state changed. Refresh and try again.',
      'TERMINAL_BOOKING_CANNOT_BE_TESTED':
          'This booking was cancelled or completed and cannot be force started.',
      'DOWNPAYMENT_NOT_CONFIRMED':
          'Confirm the downpayment before starting the tour.',
      'REMAINING_BALANCE_NOT_CONFIRMED':
          'Settle remaining payment before drop-off.',
      'DROPOFF_REQUIRED_BEFORE_COMPLETION':
          'Arrive at drop-off before completing the tour.',
      'BOOKING_HAS_PRODUCTION_FINANCIAL_HISTORY':
          'This booking has production financial history and cannot be overridden.',
      'PGRST202':
          'Developer Tools RPC is missing remotely. Apply the pending migration.',
      'FORCE_COMPLETE_REQUIRES_SETTLED_PAYMENT':
          'Force completion is blocked until payment is settled.',
      'FORCE_COMPLETE_REQUIRES_COMPLETED_ITINERARY':
          'Complete every itinerary stop before force completion.',
      'PREVIOUS_STOP_BLOCKED_BY_FINANCIAL_HISTORY':
          'The previous stop has financial history and cannot be reopened.',
    };
    for (final entry in messages.entries) {
      if (source.contains(entry.key)) return entry.value;
    }
    return 'Developer action failed: $source';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _state == null) return const AdministratorLoadingState();
    if (_state == null) {
      return AdministratorErrorState(
        message: _error ?? 'Developer state unavailable.',
        onRetry: _load,
      );
    }
    final state = _state!;
    final enabled = state.controlsEnabled && !state.terminal && !_busy;
    final timingEnabled = enabled && state.activeStopLedger;
    final interval = state.intervalMinutes;
    final persistedOvertime = _overtimeMinutes;
    final persistedFee = state.number('additional_fee');
    final testRate = _customRate
        ? double.tryParse(_rateController.text.trim()) ?? 0
        : state.configuredRate;
    final testIntervals = bookingTestChargeableIntervals(
      _testOvertimeMinutes,
      interval,
    );
    final testFee = testIntervals * testRate;
    final baseTotal =
        state.number('booking_total') - state.number('additional_fee');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        _DeveloperWarning(active: state.overrideActive),
        if (!state.controlsEnabled) ...[
          const SizedBox(height: 12),
          _DeveloperNotice(
            text: state.raw['financially_safe'] == false
                ? 'Controls are locked because this booking has live payment or irreversible financial history.'
                : 'Controls are locked. A System Administrator must enable Developer Testing and activate this booking session.',
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _DeveloperNotice(text: _error!),
        ],
        if (state.controlsEnabled &&
            !state.activeStopLedger &&
            !state.terminal) ...[
          const SizedBox(height: 12),
          const _DeveloperNotice(
            text: 'Arrive at the current stop to enable Time of Stay controls.',
          ),
        ],
        const SizedBox(height: 14),
        _DeveloperSection(
          title: 'Current Tour State',
          icon: Icons.monitor_heart_outlined,
          child: _ValueGrid(
            values: [
              ('Status', state.text('booking_status')),
              ('Tour State', state.text('journey_state')),
              ('Current Stop', state.text('current_stop_name')),
              ('Stop Index', '${state.integer('current_stop_index') + 1}'),
              ('Arrival', state.text('arrival_status')),
              ('Departure', state.text('departure_status')),
              (
                'Stops',
                '${state.integer('current_stop_index') + 1} / ${state.integer('stop_count')}',
              ),
              (
                'Downpayment',
                state.boolean('downpayment_ready') ? 'Confirmed' : 'Required',
              ),
              (
                'Remaining Payment',
                state.boolean('remaining_payment_ready')
                    ? 'Satisfied'
                    : 'Required',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DeveloperSection(
          title: 'Stay Timer Controls',
          icon: Icons.timer_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ValueGrid(
                values: [
                  (
                    'Included Stay',
                    '${state.integer('included_minutes')} min · Package configuration',
                  ),
                  ('Elapsed', '${state.integer('elapsed_minutes')} min'),
                  (
                    'Remaining',
                    '$_remainingMinutes min${state.overrideActive ? ' · Developer override' : ''}',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Set Remaining Time'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in const [1, 5, 10])
                    OutlinedButton(
                      key: Key('developer-remaining-$minutes'),
                      onPressed: timingEnabled
                          ? () => _setRemaining(minutes)
                          : null,
                      child: Text('$minutes min'),
                    ),
                  OutlinedButton(
                    onPressed: timingEnabled
                        ? () async {
                            final value = await _customMinutes(
                              'Set Remaining Time',
                            );
                            if (value != null) await _setRemaining(value);
                          }
                        : null,
                    child: const Text('Custom'),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('developer-trigger-overtime'),
                    onPressed: timingEnabled
                        ? () => _run(
                            () => _gateway.applyTiming(
                              bookingId: widget.bookingId,
                              mode: 'overtime',
                              minutes: 0,
                            ),
                            success: 'Overtime activated.',
                          )
                        : null,
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('Trigger Overtime Now'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: timingEnabled ? () => _reset('stay') : null,
                child: const Text('Reset Stay Timer Override'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DeveloperSection(
          title: 'Overtime Test Controls',
          icon: Icons.more_time_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ValueGrid(
                values: [
                  ('Current Overtime', '$persistedOvertime min'),
                  ('Billing Interval', '$interval min'),
                  (
                    'Configured Rate',
                    '${_money(state.configuredRate)} per interval',
                  ),
                  ('Current Additional Fee', _money(persistedFee)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in const [15, 30, 45, 60])
                    ChoiceChip(
                      label: Text('$minutes min'),
                      selected: _testOvertimeMinutes == minutes,
                      onSelected: timingEnabled
                          ? (_) =>
                                setState(() => _testOvertimeMinutes = minutes)
                          : null,
                    ),
                  ActionChip(
                    label: const Text('Custom'),
                    onPressed: timingEnabled
                        ? () async {
                            final value = await _customMinutes(
                              'Set Overtime Duration',
                            );
                            if (value != null && mounted) {
                              setState(() => _testOvertimeMinutes = value);
                            }
                          }
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Overtime Fee Rule',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Use Configured Fare'),
                    selected: !_customRate,
                    onSelected: timingEnabled
                        ? (_) => setState(() => _customRate = false)
                        : null,
                  ),
                  ChoiceChip(
                    label: const Text('Custom Test Rate'),
                    selected: _customRate,
                    onSelected: timingEnabled
                        ? (_) => setState(() => _customRate = true)
                        : null,
                  ),
                ],
              ),
              if (_customRate) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _rateController,
                    enabled: timingEnabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Custom Test Rate',
                      prefixText: 'PHP ',
                      suffixText: '/ $interval min',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AdministratorColors.line),
                ),
                child: _ValueGrid(
                  values: [
                    ('Overtime Duration', '$_testOvertimeMinutes min'),
                    ('Billing Intervals', '$testIntervals'),
                    ('Rate / Interval', _money(testRate)),
                    ('Additional Fee', _money(testFee)),
                    ('Updated Booking Total', _money(baseTotal + testFee)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('developer-apply-overtime'),
                    onPressed: timingEnabled ? _applyOvertime : null,
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Apply Overtime Test'),
                  ),
                  OutlinedButton(
                    onPressed: timingEnabled ? () => _reset('overtime') : null,
                    child: const Text('Reset Overtime Test'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ActionSection(
          title: 'Tour Progression',
          icon: Icons.route_outlined,
          enabled: enabled,
          blocker: state.actionBlocker,
          actions: [
            (
              state.text('journey_state') == 'en_route_dropoff'
                  ? 'Simulate Drop-off Arrival'
                  : 'Simulate Arrival',
              'simulate_arrival',
            ),
            ('Simulate Departure', 'simulate_departure'),
            ('Move to Previous Stop', 'previous_stop'),
            (
              state.text('journey_state') == 'stop_done' &&
                      state.integer('current_stop_index') + 1 >=
                          state.integer('stop_count')
                  ? 'Proceed to Drop-off'
                  : 'Move to Next Stop',
              'next_stop',
            ),
            ('Complete Current Stop', 'complete_stop'),
          ],
          onAction: _progress,
        ),
        const SizedBox(height: 12),
        _ActionSection(
          title: 'Booking State',
          icon: Icons.flag_outlined,
          enabled: enabled,
          blocker: state.actionBlocker,
          actions: const [
            ('Force Start Tour', 'force_start'),
            ('Force Complete Tour', 'force_complete'),
          ],
          onAction: _progress,
        ),
        const SizedBox(height: 12),
        _RecentTestActions(actions: state.raw['recent_test_actions']),
        if (_busy) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  String _money(double value) =>
      NumberFormat.currency(symbol: 'PHP ', decimalDigits: 2).format(value);
}

class _RecentTestActions extends StatelessWidget {
  const _RecentTestActions({required this.actions});

  final Object? actions;

  @override
  Widget build(BuildContext context) {
    final rows = (actions as List? ?? const <Object>[])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    return _DeveloperSection(
      title: 'Recent Test Actions',
      icon: Icons.history_rounded,
      child: rows.isEmpty
          ? const Text(
              'No booking manipulation actions have been recorded yet.',
              style: TextStyle(color: AdministratorColors.muted),
            )
          : Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  _AuditActionRow(row: rows[index]),
                  if (index != rows.length - 1) const Divider(height: 20),
                ],
              ],
            ),
    );
  }
}

class _AuditActionRow extends StatelessWidget {
  const _AuditActionRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final action = '${row['action'] ?? 'developer_action'}'.replaceAll(
      '_',
      ' ',
    );
    final actor =
        '${row['actor_name'] ?? row['actor_id'] ?? 'System Administrator'}';
    final occurredAt = DateTime.tryParse('${row['created_at'] ?? ''}');
    final timestamp = occurredAt == null
        ? 'Timestamp unavailable'
        : DateFormat('MMM d, y · h:mm a').format(occurredAt.toLocal());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.verified_user_outlined,
          size: 18,
          color: AdministratorColors.blue,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action,
                style: const TextStyle(
                  color: AdministratorColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '$actor · $timestamp',
                style: const TextStyle(
                  color: AdministratorColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeveloperWarning extends StatelessWidget {
  const _DeveloperWarning({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.science_outlined, color: Color(0xFFC2410C)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'DEVELOPER / TESTING TOOLS',
                      style: TextStyle(
                        color: Color(0xFF9A3412),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (active)
                      const Chip(
                        label: Text('TEST OVERRIDE ACTIVE'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Testing controls affect this booking only. Original package and fare configuration remain unchanged.',
                  style: TextStyle(color: Color(0xFF9A3412), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperNotice extends StatelessWidget {
  const _DeveloperNotice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFBFDBFE)),
    ),
    child: Text(text, style: const TextStyle(color: Color(0xFF1D4ED8))),
  );
}

class _DeveloperSection extends StatelessWidget {
  const _DeveloperSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AdministratorColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AdministratorColors.blue, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: AdministratorColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _ValueGrid extends StatelessWidget {
  const _ValueGrid({required this.values});
  final List<(String, String)> values;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final value in values)
        Container(
          constraints: const BoxConstraints(minWidth: 150, maxWidth: 300),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value.$1,
                style: const TextStyle(
                  color: AdministratorColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value.$2,
                style: const TextStyle(
                  color: AdministratorColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.title,
    required this.icon,
    required this.enabled,
    required this.blocker,
    required this.actions,
    required this.onAction,
  });

  final String title;
  final IconData icon;
  final bool enabled;
  final String? Function(String action) blocker;
  final List<(String, String)> actions;
  final Future<void> Function(String action, String label) onAction;

  @override
  Widget build(BuildContext context) => _DeveloperSection(
    title: title,
    icon: icon,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in actions)
              Tooltip(
                message: blocker(action.$2) ?? action.$1,
                child: OutlinedButton(
                  key: Key('developer-action-${action.$2}'),
                  onPressed: enabled && blocker(action.$2) == null
                      ? () => onAction(action.$2, action.$1)
                      : null,
                  child: Text(action.$1),
                ),
              ),
          ],
        ),
        for (final action in actions)
          if (blocker(action.$2) case final reason?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${action.$1}: $reason',
                style: const TextStyle(
                  color: AdministratorColors.muted,
                  fontSize: 12,
                ),
              ),
            ),
      ],
    ),
  );
}
