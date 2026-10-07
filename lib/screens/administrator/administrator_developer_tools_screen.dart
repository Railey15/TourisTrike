import 'dart:async';



import 'package:flutter/material.dart';

import 'package:intl/intl.dart';



import 'administrator_models.dart';

import 'administrator_service.dart';

import 'widgets/system_admin_shared.dart';



typedef AdministratorDeveloperToolsLoader =

    Future<AdministratorDeveloperToolsData> Function(

      AdministratorDeveloperToolsQuery query,

    );

typedef AdministratorDeveloperTestingToggle =

    Future<void> Function(bool enabled);

typedef AdministratorDeveloperTestActivator =

    Future<void> Function(

      AdministratorDeveloperTestBooking booking,

      AdministratorDeveloperTestActivation activation,

    );

typedef AdministratorDeveloperTestDeactivator =

    Future<void> Function(AdministratorDeveloperTestBooking booking);

typedef AdministratorDeveloperTestResetter =

    Future<void> Function(AdministratorDeveloperTestBooking booking);



class AdministratorDeveloperToolsScreen extends StatefulWidget {

  const AdministratorDeveloperToolsScreen({

    super.key,

    @visibleForTesting this.loadData,

    @visibleForTesting this.setEnabled,

    @visibleForTesting this.activate,

    @visibleForTesting this.deactivate,

    @visibleForTesting this.reset,
    @visibleForTesting this.deleteBooking,

  });



  final AdministratorDeveloperToolsLoader? loadData;

  final AdministratorDeveloperTestingToggle? setEnabled;

  final AdministratorDeveloperTestActivator? activate;

  final AdministratorDeveloperTestDeactivator? deactivate;

  final AdministratorDeveloperTestResetter? reset;
  final Future<void> Function(AdministratorDeveloperTestBooking)? deleteBooking;



  @override

  State<AdministratorDeveloperToolsScreen> createState() =>

      _AdministratorDeveloperToolsScreenState();

}



class _AdministratorDeveloperToolsScreenState

    extends State<AdministratorDeveloperToolsScreen> {

  final _search = TextEditingController();

  AdministratorService? _service;

  Timer? _searchTimer;

  var _query = const AdministratorDeveloperToolsQuery();

  late Future<AdministratorDeveloperToolsData> _future = _load();

  bool _mutating = false;



  AdministratorService get _activeService =>

      _service ??= AdministratorService();



  Future<AdministratorDeveloperToolsData> _load() =>

      widget.loadData?.call(_query) ??

      _activeService.loadDeveloperTools(_query);



  void _reload({bool resetPage = false}) {

    if (resetPage) _query = _query.copyWith(offset: 0);

    setState(() {

      _future = _load();

    });

  }



  void _searchChanged(String value) {

    _searchTimer?.cancel();

    _searchTimer = Timer(const Duration(milliseconds: 350), () {

      if (!mounted) return;

      _query = _query.copyWith(search: value, offset: 0);

      _reload();

    });

  }



  Future<void> _toggleGlobal(bool enabled) async {

    final confirmed = await showDialog<bool>(

      context: context,

      builder: (context) => AlertDialog(

        title: Text(

          enabled ? 'Enable developer testing?' : 'Disable developer testing?',

        ),

        content: Text(

          enabled

              ? 'Existing eligible booking sessions can become effective. All normal payment, Driver, GPS, convoy, and journey-state rules remain enforced.'

              : 'All sessions immediately become ineffective. Their records and expiry times are preserved.',

        ),

        actions: [

          TextButton(

            onPressed: () => Navigator.pop(context, false),

            child: const Text('Cancel'),

          ),

          FilledButton(

            key: const Key('developer-testing-confirm-toggle'),

            onPressed: () => Navigator.pop(context, true),

            child: Text(enabled ? 'Enable' : 'Disable'),

          ),

        ],

      ),

    );

    if (confirmed != true) return;

    await _mutate(() async {

      await (widget.setEnabled?.call(enabled) ??

          _activeService.setDeveloperTestingEnabled(enabled));

    });

  }



  Future<void> _deleteBooking(AdministratorDeveloperTestBooking booking) async {
    if (_mutating) return;
    var deleting = false;
    String? failure;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Delete booking?'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${booking.reference} · ${booking.packageName}'),
                Text('Tourist: ${booking.touristName}'),
                Text('Schedule: ${_formatDate(booking.scheduledStartAt)}'),
                const SizedBox(height: 16),
                const Text(
                  'This will permanently delete this booking and its related test data. '
                  'This action cannot be undone.',
                ),
                if (failure != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to delete booking',
                    style: TextStyle(
                      color: AdministratorColors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(failure!, style: const TextStyle(color: AdministratorColors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: deleting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('developer-booking-confirm-delete'),
              onPressed: deleting
                  ? null
                  : () async {
                      if (_mutating) return;
                      setState(() => _mutating = true);
                      setDialogState(() {
                        deleting = true;
                        failure = null;
                      });
                      try {
                        await (widget.deleteBooking?.call(booking) ??
                            _activeService.deleteDeveloperTestBooking(booking));
                        if (!mounted || !dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _reload(resetPage: true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text(
                            'Booking deleted successfully.',
                          )),
                        );
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            deleting = false;
                            failure = _friendlyError(error);
                          });
                        }
                      } finally {
                        if (mounted) setState(() => _mutating = false);
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: AdministratorColors.red),
              child: deleting
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 8),
                        Text('Deleting…'),
                      ],
                    )
                  : const Text('Delete Booking'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBooking(

    AdministratorDeveloperTestBooking booking,

    bool globalEnabled,

  ) async {

    if (_mutating) return;

    final action = await showDialog<_DeveloperBookingAction>(

      context: context,

      builder: (context) => _DeveloperBookingDialog(

        booking: booking,

        globalEnabled: globalEnabled,

      ),

    );

    if (!mounted || action == null) return;

    if (action == _DeveloperBookingAction.activate) {

      final activation = await _requestActivation(booking);

      if (activation == null) return;

      await _mutate(() async {

        await (widget.activate?.call(booking, activation) ??

            _activeService.activateDeveloperTestSession(booking, activation));

      });

      return;

    }



    if (action == _DeveloperBookingAction.reset) {

      final confirmed = await showDialog<bool>(

        context: context,

        builder: (context) => AlertDialog(

          title: const Text('Reset test trip?'),

          content: const Text(

            'Journey progress, arrivals, and unfinished waiting state will return to pre-tour state. Assignments, itinerary identity, payments, allocations, payouts, disputes, and the active test session are preserved. Trips with irreversible financial activity cannot be reset.',

          ),

          actions: [

            TextButton(

              onPressed: () => Navigator.pop(context, false),

              child: const Text('Cancel'),

            ),

            FilledButton(

              key: const Key('developer-session-confirm-reset'),

              onPressed: () => Navigator.pop(context, true),

              child: const Text('Reset Test Trip'),

            ),

          ],

        ),

      );

      if (confirmed != true) return;

      await _mutate(() async {

        await (widget.reset?.call(booking) ??

            _activeService.resetDeveloperTestTrip(booking));

      });

      return;

    }



    final confirmed = await showDialog<bool>(

      context: context,

      builder: (context) => AlertDialog(

        title: const Text('Deactivate test session?'),

        content: const Text(

          'The scheduled-start override will stop working immediately. The audit history is retained.',

        ),

        actions: [

          TextButton(

            onPressed: () => Navigator.pop(context, false),

            child: const Text('Cancel'),

          ),

          FilledButton(

            key: const Key('developer-session-confirm-deactivate'),

            onPressed: () => Navigator.pop(context, true),

            style: FilledButton.styleFrom(

              backgroundColor: AdministratorColors.red,

            ),

            child: const Text('Deactivate'),

          ),

        ],

      ),

    );

    if (confirmed != true) return;

    await _mutate(() async {

      await (widget.deactivate?.call(booking) ??

          _activeService.deactivateDeveloperTestSession(booking));

    });

  }



  Future<AdministratorDeveloperTestActivation?> _requestActivation(

    AdministratorDeveloperTestBooking booking,

  ) {

    return showDialog<AdministratorDeveloperTestActivation>(

      context: context,

      builder: (context) => _DeveloperActivationDialog(booking: booking),

    );

  }



  Future<void> _mutate(Future<void> Function() operation) async {

    if (_mutating) return;

    setState(() => _mutating = true);

    try {

      await operation();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(content: Text('Developer testing settings updated.')),

      );

      _reload();

    } catch (error) {

      if (!mounted) return;

      ScaffoldMessenger.of(

        context,

      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));

    } finally {

      if (mounted) setState(() => _mutating = false);

    }

  }



  String _friendlyError(Object error) {

    final text = error.toString();
    if (text.contains('BOOKING_HAS_LIVE_PROVIDER_PAYMENT')) {
      return 'This booking contains a live provider payment that must be retained.';
    }
    if (text.contains('BOOKING_HAS_PAYMENT_EVIDENCE')) {
      return 'This booking contains confirmed or externally documented payment evidence that must be retained.';
    }
    if (text.contains('BOOKING_HAS_REFUND')) {
      return 'This booking contains a refund record that must be retained.';
    }
    if (text.contains('BOOKING_HAS_DISPUTE')) {
      return 'This booking contains a financial dispute that must be retained.';
    }
    if (text.contains('BOOKING_HAS_PAYOUT') || text.contains('BOOKING_HAS_TRANSFER')) {
      return 'This booking contains a payout or transfer record that must be retained.';
    }
    if (text.contains('BOOKING_HAS_EMERGENCY_RECORD')) {
      return 'This booking contains an emergency record that must be retained.';
    }
    if (text.contains('BOOKING_HAS_REVIEW')) {
      return 'This booking contains a review that must be retained.';
    }
    if (text.contains('BOOKING_HAS_OTHER_REFERENCE')) {
      return 'This booking has another related record that prevents deletion.';
    }
    if (text.contains('BOOKING_NOT_ELIGIBLE_FOR_DEVELOPER_CLEANUP')) {
      return 'This booking is no longer eligible for Developer Tools cleanup. Refresh the list.';
    }
    if (text.contains('BOOKING_NOT_FOUND')) {
      return 'This booking is no longer available. Refresh the list.';
    }
    return 'Unable to update Developer Tools. Please refresh and try again.';

  }



  @override

  void dispose() {

    _searchTimer?.cancel();

    _search.dispose();

    super.dispose();

  }



  @override

  Widget build(BuildContext context) {

    return FutureBuilder<AdministratorDeveloperToolsData>(

      future: _future,

      builder: (context, snapshot) {

        if (snapshot.connectionState != ConnectionState.done) {

          return const AdministratorLoadingState();

        }

        if (snapshot.hasError) {

          return AdministratorErrorState(

            message: 'Please refresh and try again.',

            onRetry: _reload,

          );

        }

        return _buildContent(snapshot.requireData);

      },

    );

  }



  Widget _buildContent(AdministratorDeveloperToolsData data) {

    final overview = data.overview;

    return Stack(

      children: [

        SingleChildScrollView(

          padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              _GlobalDeveloperTestingCard(

                overview: overview,

                enabled: !_mutating,

                onChanged: _toggleGlobal,

              ),

              const SizedBox(height: 16),

              Wrap(

                spacing: 12,

                runSpacing: 12,

                children: [

                  AdministratorMetric(

                    label: 'Eligible bookings',

                    value: overview.eligibleBookings,

                    icon: Icons.task_alt_outlined,

                    color: AdministratorColors.green,

                  ),

                  AdministratorMetric(

                    label: 'Active sessions',

                    value: overview.activeSessions,

                    icon: Icons.science_outlined,

                    color: AdministratorColors.blue,

                  ),

                  AdministratorMetric(

                    label: 'Upcoming bookings',

                    value: overview.upcomingBookings,

                    icon: Icons.upcoming_outlined,

                    color: AdministratorColors.amber,

                  ),

                  AdministratorMetric(

                    label: 'Expiring within 3 hours',

                    value: overview.expiringSoon,

                    icon: Icons.timer_outlined,

                    color: AdministratorColors.red,

                  ),

                ],

              ),

              const SizedBox(height: 16),

              AdministratorPanel(

                title: 'Booking test authorizations',

                subtitle:

                    'Sessions allow only an early assigned → en route to pickup transition. They never simulate payment, GPS, or journey progress.',

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    AdministratorFilterBar(

                      search: _search,

                      hint: 'Search booking, Tourist, Driver, package, or city',

                      onChanged: _searchChanged,

                      filters: [

                        AdministratorDropdownFilter<

                          AdministratorDeveloperBookingFilter

                        >(

                          value: _query.bookingFilter,

                          hint: 'Booking status',

                          values: AdministratorDeveloperBookingFilter.values,

                          label: (value) => value.label,

                          onChanged: (value) {

                            if (value == null) return;

                            _query = _query.copyWith(

                              bookingFilter: value,

                              offset: 0,

                            );

                            _reload();

                          },

                        ),

                        AdministratorDropdownFilter<

                          AdministratorDeveloperTestFilter

                        >(

                          value: _query.testFilter,

                          hint: 'Test status',

                          values: AdministratorDeveloperTestFilter.values,

                          label: (value) => value.label,

                          onChanged: (value) {

                            if (value == null) return;

                            _query = _query.copyWith(

                              testFilter: value,

                              offset: 0,

                            );

                            _reload();

                          },

                        ),

                      ],

                    ),

                    const SizedBox(height: 14),

                    if (data.bookings.isEmpty)

                      const AdministratorEmptyState(

                        icon: Icons.search_off_rounded,

                        title: 'No bookings found',

                        message: 'Try a different search or filter.',

                      )

                    else

                      LayoutBuilder(

                        builder: (context, constraints) =>

                            constraints.maxWidth >= 900

                            ? _DeveloperBookingsTable(

                                bookings: data.bookings,

                                globalEnabled: overview.enabled,

                                onOpen: _openBooking,
                                onDelete: _deleteBooking,

                              )

                            : _DeveloperBookingCards(

                                bookings: data.bookings,

                                globalEnabled: overview.enabled,

                                onOpen: _openBooking,
                                onDelete: _deleteBooking,

                              ),

                      ),

                    if (data.totalCount > 0) ...[

                      const SizedBox(height: 12),

                      _PaginationBar(

                        data: data,

                        onPrevious: data.hasPreviousPage

                            ? () {

                                _query = _query.copyWith(

                                  offset: (_query.offset - _query.limit).clamp(

                                    0,

                                    data.totalCount,

                                  ),

                                );

                                _reload();

                              }

                            : null,

                        onNext: data.hasNextPage

                            ? () {

                                _query = _query.copyWith(

                                  offset: _query.offset + _query.limit,

                                );

                                _reload();

                              }

                            : null,

                      ),

                    ],

                  ],

                ),

              ),

            ],

          ),

        ),

        if (_mutating)

          const Positioned.fill(

            child: ColoredBox(

              color: Color(0x22000000),

              child: Center(child: CircularProgressIndicator()),

            ),

          ),

      ],

    );

  }

}



class _GlobalDeveloperTestingCard extends StatelessWidget {

  const _GlobalDeveloperTestingCard({

    required this.overview,

    required this.enabled,

    required this.onChanged,

  });



  final AdministratorDeveloperTestingOverview overview;

  final bool enabled;

  final ValueChanged<bool> onChanged;



  @override

  Widget build(BuildContext context) {

    final color = overview.enabled

        ? AdministratorColors.amber

        : AdministratorColors.muted;

    return AdministratorPanel(

      child: LayoutBuilder(

        builder: (context, constraints) {

          final compact = constraints.maxWidth < 760;

          final icon = Container(

            padding: const EdgeInsets.all(11),

            decoration: BoxDecoration(

              color: color.withValues(alpha: 0.10),

              borderRadius: BorderRadius.circular(12),

            ),

            child: Icon(Icons.warning_amber_rounded, color: color),

          );

          final controls = Row(

            mainAxisSize: MainAxisSize.min,

            children: [

              AdministratorStatusPill(

                label: overview.enabled ? 'Enabled' : 'Disabled',

                color: overview.enabled

                    ? AdministratorColors.amber

                    : AdministratorColors.muted,

              ),

              const SizedBox(width: 8),

              Switch.adaptive(

                key: const Key('developer-testing-global-switch'),

                value: overview.enabled,

                onChanged: enabled ? onChanged : null,

              ),

            ],

          );

          final details = Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              if (compact) ...[

                Row(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    icon,

                    const SizedBox(width: 12),

                    const Expanded(child: _DeveloperTestingCardTitle()),

                  ],

                ),

                const SizedBox(height: 10),

                controls,

              ] else

                Row(

                  children: [

                    const Expanded(child: _DeveloperTestingCardTitle()),

                    controls,

                  ],

                ),

              const SizedBox(height: 5),

              const Text(

                'High-risk control. An active session can bypass only the scheduled start time for an eligible booking. Disabling this switch preserves sessions but makes every one ineffective.',

                style: TextStyle(color: AdministratorColors.muted),

              ),

              if (overview.updatedAt != null) ...[

                const SizedBox(height: 8),

                Text(

                  'Last updated ${_formatDate(overview.updatedAt)}',

                  style: const TextStyle(

                    color: AdministratorColors.muted,

                    fontSize: 12,

                  ),

                ),

              ],

            ],

          );

          if (compact) return details;

          return Row(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              icon,

              const SizedBox(width: 14),

              Expanded(child: details),

            ],

          );

        },

      ),

    );

  }

}



class _DeveloperTestingCardTitle extends StatelessWidget {

  const _DeveloperTestingCardTitle();



  @override

  Widget build(BuildContext context) => const Text(

    'Global developer testing',

    style: TextStyle(

      color: AdministratorColors.ink,

      fontSize: 17,

      fontWeight: FontWeight.w800,

    ),

  );

}



class _DeveloperBookingsTable extends StatelessWidget {
  const _DeveloperBookingsTable({
    required this.bookings,
    required this.globalEnabled,
    required this.onOpen,
    required this.onDelete,
  });

  final List<AdministratorDeveloperTestBooking> bookings;
  final bool globalEnabled;
  final void Function(AdministratorDeveloperTestBooking, bool) onOpen;
  final void Function(AdministratorDeveloperTestBooking) onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill all available panel width on desktop instead of allowing
        // DataTable to shrink to its intrinsic content width. At narrower
        // desktop widths, keep a sensible minimum width and allow horizontal
        // scrolling rather than compressing the columns.
        final tableWidth =
            constraints.maxWidth < 1500 ? 1500.0 : constraints.maxWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: DataTable(
              horizontalMargin: 20,
              columnSpacing: 28,
              headingRowHeight: 46,
              dataRowMinHeight: 58,
              dataRowMaxHeight: 68,
              columns: const [
                DataColumn(label: Text('Booking')),
                DataColumn(label: Text('Tourist / package')),
                DataColumn(label: Text('Schedule')),
                DataColumn(label: Text('Drivers')),
                DataColumn(label: Text('Payment readiness')),
                DataColumn(label: Text('Test status')),
                DataColumn(label: SizedBox.shrink()),
              ],
              rows: [
                for (final booking in bookings)
                  DataRow(
                    cells: [
                      DataCell(
                        _TwoLineText(
                          primary: booking.reference,
                          secondary: _titleCase(booking.bookingStatus),
                        ),
                        onTap: () => onOpen(booking, globalEnabled),
                      ),
                      DataCell(
                        _TwoLineText(
                          primary: booking.touristName,
                          secondary: booking.packageName,
                        ),
                        onTap: () => onOpen(booking, globalEnabled),
                      ),
                      DataCell(
                        _TwoLineText(
                          primary: _formatDate(booking.scheduledStartAt),
                          secondary: booking.municipality,
                        ),
                        onTap: () => onOpen(booking, globalEnabled),
                      ),
                      DataCell(
                        Text(
                          '${booking.assignedDriverCount}/${booking.requiredDrivers}',
                        ),
                        onTap: () => onOpen(booking, globalEnabled),
                      ),
                      DataCell(
                        _Readiness(
                          downpayment: booking.downpaymentReady,
                          remaining: booking.remainingPaymentReady,
                        ),
                        onTap: () => onOpen(booking, globalEnabled),
                      ),
                      DataCell(
                        _TestStatus(booking: booking),
                        onTap: () => onOpen(booking, globalEnabled),
                      ),
                      DataCell(
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('developer-booking-${booking.id}'),
                                tooltip: 'Open booking test controls',
                                onPressed: () => onOpen(booking, globalEnabled),
                                icon: const Icon(Icons.open_in_new_rounded),
                              ),
                              IconButton(
                                key: Key('developer-booking-delete-${booking.id}'),
                                tooltip: 'Delete booking',
                                color: AdministratorColors.red,
                                onPressed: () => onDelete(booking),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}


class _DeveloperBookingCards extends StatelessWidget {

  const _DeveloperBookingCards({

    required this.bookings,

    required this.globalEnabled,

    required this.onOpen,
    required this.onDelete,

  });



  final List<AdministratorDeveloperTestBooking> bookings;

  final bool globalEnabled;

  final void Function(AdministratorDeveloperTestBooking, bool) onOpen;
  final void Function(AdministratorDeveloperTestBooking) onDelete;



  @override

  Widget build(BuildContext context) {

    return Column(

      children: [

        for (final booking in bookings) ...[

          InkWell(

            key: Key('developer-booking-${booking.id}'),

            onTap: () => onOpen(booking, globalEnabled),

            borderRadius: BorderRadius.circular(12),

            child: Container(

              width: double.infinity,

              padding: const EdgeInsets.all(14),

              decoration: BoxDecoration(

                border: Border.all(color: AdministratorColors.line),

                borderRadius: BorderRadius.circular(12),

              ),

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Row(

                    children: [

                      Expanded(

                        child: Text(

                          '${booking.reference} · ${booking.packageName}',

                          style: const TextStyle(fontWeight: FontWeight.w800),

                        ),

                      ),

                      _TestStatus(booking: booking),

                    ],

                  ),

                  const SizedBox(height: 8),

                  Text('${booking.touristName} · ${booking.municipality}'),

                  const SizedBox(height: 4),

                  Text(

                    '${_formatDate(booking.scheduledStartAt)} · Drivers ${booking.assignedDriverCount}/${booking.requiredDrivers}',

                    style: const TextStyle(color: AdministratorColors.muted),

                  ),

                  if (!booking.eligible &&

                      booking.eligibilityReason.isNotEmpty) ...[

                    const SizedBox(height: 7),

                    Text(

                      booking.eligibilityReason,

                      style: const TextStyle(

                        color: AdministratorColors.red,

                        fontSize: 12,

                      ),

                    ),

                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        key: Key('developer-booking-open-${booking.id}'),
                        tooltip: 'Open booking test controls',
                        onPressed: () => onOpen(booking, globalEnabled),
                        icon: const Icon(Icons.open_in_new_rounded),
                      ),
                      IconButton(
                        key: Key('developer-booking-delete-${booking.id}'),
                        tooltip: 'Delete booking',
                        color: AdministratorColors.red,
                        onPressed: () => onDelete(booking),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),

                ],

              ),

            ),

          ),

          const SizedBox(height: 10),

        ],

      ],

    );

  }

}



class _DeveloperBookingDialog extends StatelessWidget {

  const _DeveloperBookingDialog({

    required this.booking,

    required this.globalEnabled,

  });



  final AdministratorDeveloperTestBooking booking;

  final bool globalEnabled;



  @override

  Widget build(BuildContext context) {

    final canActivate = globalEnabled && booking.canActivate;

    final canReset =

        globalEnabled && booking.testSessionActive && booking.bookingStateValid;

    return AlertDialog(

      title: Text('${booking.reference} · ${booking.packageName}'),

      content: SizedBox(

        width: 570,

        child: SingleChildScrollView(

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              _DialogLine(label: 'Tourist', value: booking.touristName),

              _DialogLine(label: 'Municipality', value: booking.municipality),

              _DialogLine(

                label: 'Schedule',

                value:

                    '${_formatDate(booking.scheduledStartAt)} – ${_formatDate(booking.estimatedEndAt)}',

              ),

              _DialogLine(

                label: 'Booking / tour status',

                value:

                    '${_titleCase(booking.bookingStatus)} / ${_titleCase(booking.tourStatus)}',

              ),

              _DialogLine(

                label: 'Drivers',

                value: booking.drivers.isEmpty

                    ? 'None assigned'

                    : booking.drivers.map((driver) => driver.name).join(', '),

              ),

              _DialogLine(

                label: 'Downpayment',

                value: booking.downpaymentReady ? 'Confirmed' : 'Not confirmed',

              ),

              _DialogLine(

                label: 'Remaining payment',

                value: booking.remainingPaymentReady

                    ? 'Satisfied'

                    : 'Not satisfied',

              ),

              const Divider(height: 26),

              const Text(

                'Testing eligibility',

                style: TextStyle(fontWeight: FontWeight.w800),

              ),

              const SizedBox(height: 7),

              _EligibilityCheck(

                passed: booking.bookingStateValid,

                label: 'Booking is not cancelled, rejected, or completed',

              ),

              _EligibilityCheck(

                passed: booking.validTourist,

                label: 'Valid Tourist exists',

              ),

              _EligibilityCheck(

                passed: booking.driversReady,

                label: 'All required Driver slots are accepted',

              ),

              _EligibilityCheck(

                passed: globalEnabled,

                label: 'Global developer testing is enabled',

              ),

              const Divider(height: 26),

              if (booking.testSessionActive) ...[

                const Text(

                  'Active test session',

                  style: TextStyle(fontWeight: FontWeight.w800),

                ),

                const SizedBox(height: 8),

                _DialogLine(

                  label: 'Activated by',

                  value: booking.activatedByName.isEmpty

                      ? booking.activatedBy

                      : booking.activatedByName,

                ),

                _DialogLine(

                  label: 'Activated',

                  value: _formatDate(booking.activatedAt),

                ),

                _DialogLine(

                  label: 'Expires',

                  value: _formatDate(booking.expiresAt),

                ),

                _DialogLine(label: 'Reason', value: booking.reason),

                const Text(

                  'Authorized override: scheduled start only',

                  style: TextStyle(

                    color: AdministratorColors.amber,

                    fontWeight: FontWeight.w700,

                  ),

                ),

              ] else if (!globalEnabled)

                const Text(

                  'Global developer testing is disabled.',

                  style: TextStyle(color: AdministratorColors.red),

                )

              else if (!booking.eligible)

                Text(

                  booking.eligibilityReason,

                  style: const TextStyle(color: AdministratorColors.red),

                )

              else

                const Text(

                  'This booking is eligible for a time-limited scheduled-start override.',

                ),

            ],

          ),

        ),

      ),

      actions: [

        TextButton(

          onPressed: () => Navigator.pop(context),

          child: const Text('Close'),

        ),

        if (booking.testSessionActive) ...[

          OutlinedButton.icon(

            key: const Key('developer-session-reset'),

            onPressed: canReset

                ? () => Navigator.pop(context, _DeveloperBookingAction.reset)

                : null,

            icon: const Icon(Icons.restart_alt_rounded),

            label: const Text('Reset Test Trip'),

          ),

          FilledButton(

            key: const Key('developer-session-deactivate'),

            onPressed: () =>

                Navigator.pop(context, _DeveloperBookingAction.deactivate),

            style: FilledButton.styleFrom(

              backgroundColor: AdministratorColors.red,

            ),

            child: const Text('Deactivate session'),

          ),

        ] else

          FilledButton.icon(

            key: const Key('developer-session-activate'),

            onPressed: canActivate

                ? () => Navigator.pop(context, _DeveloperBookingAction.activate)

                : null,

            icon: const Icon(Icons.science_outlined),

            label: const Text('Activate test session'),

          ),

      ],

    );

  }

}



class _DeveloperActivationDialog extends StatefulWidget {

  const _DeveloperActivationDialog({required this.booking});



  final AdministratorDeveloperTestBooking booking;



  @override

  State<_DeveloperActivationDialog> createState() =>

      _DeveloperActivationDialogState();

}



class _DeveloperActivationDialogState

    extends State<_DeveloperActivationDialog> {

  final _reason = TextEditingController();

  int _hours = 3;



  @override

  void dispose() {

    _reason.dispose();

    super.dispose();

  }



  @override

  Widget build(BuildContext context) {

    final valid = _reason.text.trim().length >= 3;

    return AlertDialog(

      title: Text('Activate ${widget.booking.reference} for testing'),

      content: SizedBox(

        width: 480,

        child: Column(

          mainAxisSize: MainAxisSize.min,

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            const Text(

              'This creates authorization only. It does not alter booking status, payments, GPS data, Drivers, or notifications.',

            ),

            const SizedBox(height: 16),

            TextField(

              key: const Key('developer-session-reason'),

              controller: _reason,

              onChanged: (_) => setState(() {}),

              minLines: 2,

              maxLines: 4,

              maxLength: 500,

              decoration: const InputDecoration(

                labelText: 'Testing reason',

                hintText: 'Describe the test scenario and owner',

                border: OutlineInputBorder(),

              ),

            ),

            const SizedBox(height: 10),

            DropdownButtonFormField<int>(

              key: const Key('developer-session-expiry'),

              initialValue: _hours,

              decoration: const InputDecoration(

                labelText: 'Session duration',

                border: OutlineInputBorder(),

              ),

              items: const [

                DropdownMenuItem(value: 1, child: Text('1 hour')),

                DropdownMenuItem(value: 3, child: Text('3 hours')),

                DropdownMenuItem(value: 6, child: Text('6 hours')),

                DropdownMenuItem(value: 12, child: Text('12 hours')),

                DropdownMenuItem(value: 24, child: Text('24 hours')),

              ],

              onChanged: (value) => setState(() => _hours = value ?? 3),

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

          key: const Key('developer-session-confirm-activate'),

          onPressed: valid

              ? () => Navigator.pop(

                  context,

                  AdministratorDeveloperTestActivation(

                    reason: _reason.text.trim(),

                    expiresAt: DateTime.now().toUtc().add(

                      Duration(hours: _hours),

                    ),

                  ),

                )

              : null,

          child: const Text('Activate'),

        ),

      ],

    );

  }

}



class _Readiness extends StatelessWidget {

  const _Readiness({required this.downpayment, required this.remaining});



  final bool downpayment;

  final bool remaining;



  @override

  Widget build(BuildContext context) => Column(

    mainAxisAlignment: MainAxisAlignment.center,

    crossAxisAlignment: CrossAxisAlignment.start,

    children: [

      Text(

        downpayment ? 'Downpayment ready' : 'Downpayment pending',

        style: TextStyle(

          color: downpayment

              ? AdministratorColors.green

              : AdministratorColors.red,

          fontSize: 12,

        ),

      ),

      Text(

        remaining ? 'Balance ready' : 'Balance pending',

        style: const TextStyle(color: AdministratorColors.muted, fontSize: 12),

      ),

    ],

  );

}



class _EligibilityCheck extends StatelessWidget {

  const _EligibilityCheck({required this.passed, required this.label});



  final bool passed;

  final String label;



  @override

  Widget build(BuildContext context) => Padding(

    padding: const EdgeInsets.only(bottom: 6),

    child: Row(

      children: [

        Icon(

          passed ? Icons.check_circle_outline : Icons.cancel_outlined,

          size: 18,

          color: passed ? AdministratorColors.green : AdministratorColors.red,

        ),

        const SizedBox(width: 7),

        Expanded(child: Text(label)),

      ],

    ),

  );

}



class _TestStatus extends StatelessWidget {

  const _TestStatus({required this.booking});



  final AdministratorDeveloperTestBooking booking;



  @override

  Widget build(BuildContext context) => AdministratorStatusPill(

    label: booking.testSessionActive ? 'Active' : 'Inactive',

    color: booking.testSessionActive

        ? AdministratorColors.amber

        : AdministratorColors.muted,

    icon: booking.testSessionActive ? Icons.timer_outlined : null,

  );

}



class _TwoLineText extends StatelessWidget {

  const _TwoLineText({required this.primary, required this.secondary});



  final String primary;

  final String secondary;



  @override

  Widget build(BuildContext context) => Column(

    mainAxisAlignment: MainAxisAlignment.center,

    crossAxisAlignment: CrossAxisAlignment.start,

    children: [

      Text(primary, style: const TextStyle(fontWeight: FontWeight.w700)),

      Text(

        secondary,

        maxLines: 1,

        overflow: TextOverflow.ellipsis,

        style: const TextStyle(color: AdministratorColors.muted, fontSize: 12),

      ),

    ],

  );

}



class _DialogLine extends StatelessWidget {

  const _DialogLine({required this.label, required this.value});



  final String label;

  final String value;



  @override

  Widget build(BuildContext context) => Padding(

    padding: const EdgeInsets.only(bottom: 9),

    child: Row(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        SizedBox(

          width: 150,

          child: Text(

            label,

            style: const TextStyle(color: AdministratorColors.muted),

          ),

        ),

        Expanded(

          child: Text(

            value.isEmpty ? '—' : value,

            style: const TextStyle(fontWeight: FontWeight.w600),

          ),

        ),

      ],

    ),

  );

}



class _PaginationBar extends StatelessWidget {

  const _PaginationBar({

    required this.data,

    required this.onPrevious,

    required this.onNext,

  });



  final AdministratorDeveloperToolsData data;

  final VoidCallback? onPrevious;

  final VoidCallback? onNext;



  @override

  Widget build(BuildContext context) {

    final first = data.query.offset + 1;

    final last = data.query.offset + data.bookings.length;

    return Row(

      children: [

        Expanded(

          child: Text(

            '$first–$last of ${data.totalCount}',

            style: const TextStyle(color: AdministratorColors.muted),

          ),

        ),

        IconButton(

          tooltip: 'Previous page',

          onPressed: onPrevious,

          icon: const Icon(Icons.chevron_left_rounded),

        ),

        IconButton(

          tooltip: 'Next page',

          onPressed: onNext,

          icon: const Icon(Icons.chevron_right_rounded),

        ),

      ],

    );

  }

}



enum _DeveloperBookingAction { activate, reset, deactivate }



String _formatDate(DateTime? value) => value == null

    ? 'Not scheduled'

    : DateFormat('MMM d, y · h:mm a').format(value.toLocal());



String _titleCase(String value) => value

    .replaceAll('_', ' ')

    .split(' ')

    .where((part) => part.isNotEmpty)

    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')

    .join(' ');
