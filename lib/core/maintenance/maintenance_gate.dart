import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'maintenance_screen.dart';
import 'maintenance_service.dart';
import 'maintenance_settings.dart';

class MaintenanceGate extends StatefulWidget {
  const MaintenanceGate({
    super.key,
    required this.child,
    this.service,
    this.pollInterval = const Duration(seconds: 15),
    this.onAdministratorAccess,
    this.authStateChanges,
  });

  final Widget child;
  final MaintenanceStatusService? service;
  final Duration pollInterval;
  final Future<void> Function()? onAdministratorAccess;
  final Stream<AuthState>? authStateChanges;

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate>
    with WidgetsBindingObserver {
  late final MaintenanceStatusService _service =
      widget.service ?? MaintenanceService();
  MaintenanceSettings? _settings;
  Timer? _pollTimer;
  Timer? _boundaryTimer;
  StreamSubscription<AuthState>? _authSubscription;
  bool _checking = false;
  bool _administratorAccess = false;
  String? _dismissedNoticeKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final authStateChanges =
        widget.authStateChanges ??
        Supabase.instance.client.auth.onAuthStateChange;
    _authSubscription = authStateChanges.listen((_) {
      if (mounted) setState(() => _administratorAccess = false);
      unawaited(_refresh());
    });
    _pollTimer = Timer.periodic(
      widget.pollInterval,
      (_) => unawaited(_refresh()),
    );
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_checking) return;
    _checking = true;
    try {
      final settings = await _service.fetchStatus();
      if (!mounted) return;
      setState(() => _settings = settings);
      _scheduleBoundaryRefresh(settings);
    } catch (_) {
      // Fail open in the UI when settings are absent or malformed. Protected
      // backend requests remain governed by the database pre-request guard.
    } finally {
      _checking = false;
    }
  }

  void _scheduleBoundaryRefresh(MaintenanceSettings settings) {
    _boundaryTimer?.cancel();
    final now = DateTime.now().toUtc();
    final boundaries = <DateTime>[
      if (settings.enabled &&
          settings.startsAt != null &&
          settings.startsAt!.isAfter(now))
        settings.startsAt!,
      if (settings.enabled &&
          !settings.indefinite &&
          settings.endsAt != null &&
          settings.endsAt!.isAfter(now))
        settings.endsAt!,
    ]..sort();
    if (boundaries.isEmpty) return;
    final delay =
        boundaries.first.difference(now) + const Duration(milliseconds: 250);
    _boundaryTimer = Timer(delay, () => unawaited(_refresh()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _boundaryTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final showNotice = _showUpcomingNotice(settings);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (showNotice)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 10,
            left: 12,
            right: 12,
            child: _ScheduledMaintenanceNotice(
              settings: settings!,
              onDismiss: () => setState(() {
                _dismissedNoticeKey = settings.startsAt?.toIso8601String();
              }),
            ),
          ),
        if ((settings?.blocksViewer ?? false) && !_administratorAccess)
          Positioned.fill(
            child: MaintenanceScreen(
              settings: settings!,
              checking: _checking,
              onTryAgain: _refresh,
              onAdministratorAccess: widget.onAdministratorAccess == null
                  ? null
                  : _openAdministratorAccess,
            ),
          ),
      ],
    );
  }

  Future<void> _openAdministratorAccess() async {
    setState(() => _administratorAccess = true);
    await widget.onAdministratorAccess?.call();
    if (!mounted) return;
    setState(() => _administratorAccess = false);
    await _refresh();
  }

  bool _showUpcomingNotice(MaintenanceSettings? settings) {
    if (settings == null ||
        !settings.isScheduled ||
        settings.viewerRole == null) {
      return false;
    }
    final start = settings.startsAt!;
    if (start.difference(DateTime.now().toUtc()) > const Duration(hours: 24)) {
      return false;
    }
    return _dismissedNoticeKey != start.toIso8601String();
  }
}

class _ScheduledMaintenanceNotice extends StatelessWidget {
  const _ScheduledMaintenanceNotice({
    required this.settings,
    required this.onDismiss,
  });

  final MaintenanceSettings settings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final start = DateFormat.MMMd().add_jm().format(
      settings.startsAt!.toLocal(),
    );
    final end = settings.indefinite || settings.endsAt == null
        ? 'until further notice'
        : DateFormat.MMMd().add_jm().format(settings.endsAt!.toLocal());
    return Material(
      elevation: 8,
      color: const Color(0xFFFFF7E8),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded, color: Color(0xFFB54708)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Scheduled maintenance $start to $end.',
                style: const TextStyle(
                  color: Color(0xFF7A2E0E),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
