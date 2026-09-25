import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/notifications/notification_service.dart';
import '../core/notifications/notification_visibility.dart';
import '../core/notifications/tour_notification.dart';
import '../screens/driver/driver_package_jobs_screen.dart';
import '../screens/driver/driver_package_tracking_screen.dart';
import '../screens/tourist/tourist_activity_tracking_screen.dart';
import '../screens/shared/notification_center_screen.dart';
import 'notification_foreground_banner.dart';
export 'notification_foreground_banner.dart';

final notificationNavigatorKey = GlobalKey<NavigatorState>();
final notificationMessengerKey = GlobalKey<ScaffoldMessengerState>();

class NotificationHost extends StatefulWidget {
  const NotificationHost({
    super.key,
    required this.child,
    this.incoming,
    this.onOpen,
  });
  final Widget child;
  // Injectable source and tap handler for shell tests; never creates events.
  final Stream<TourNotification>? incoming;
  final Future<void> Function(String)? onOpen;
  @override
  State<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends State<NotificationHost>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _maxPending = 3;
  static const _maxWait = Duration(seconds: 20);
  final _pending = Queue<({TourNotification item, DateTime receivedAt})>();
  final _seen = <String>{};
  final _bannerKey = GlobalKey();
  late final AnimationController _animation;
  StreamSubscription<TourNotification>? _subscription;
  TourNotification? _banner;
  String? _opening, _user;
  Timer? _dismissTimer;
  bool _foreground = true, _exiting = false, _reduceMotion = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    final service = NotificationService.instance;
    _user = service.userId;
    service.onOpen = _open;
    service.addListener(_checkAccount);
    notificationCenterVisible.addListener(_checkCenter);
    _subscription = (widget.incoming ?? service.incoming).listen(_receive);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) service.attachPresenter();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _animation.duration = _reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 240);
    _animation.reverseDuration = _reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
  }

  void _receive(TourNotification item) {
    if (!item.foregroundEligible || !_seen.add(item.id)) return;
    if (_seen.length > 300) _seen.remove(_seen.first);
    if (!_foreground || notificationCenterVisible.value) return;
    if (_pending.length == _maxPending) _pending.removeFirst();
    _pending.add((item: item, receivedAt: DateTime.now()));
    _showNext();
  }

  void _showNext() {
    if (!mounted ||
        _banner != null ||
        !_foreground ||
        notificationCenterVisible.value) {
      return;
    }
    while (_pending.isNotEmpty) {
      final next = _pending.removeFirst();
      if (DateTime.now().difference(next.receivedAt) > _maxWait) continue;
      setState(() => _banner = next.item);
      unawaited(_enter(next.item));
      return;
    }
  }

  Future<void> _enter(TourNotification item) async {
    final revision = _revision;
    try {
      await _animation.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted ||
        revision != _revision ||
        _banner?.id != item.id ||
        _exiting) {
      return;
    }
    final box = _bannerKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize && box.size.height > 0) {
      final diagnostics = NotificationService.instance.diagnostics;
      diagnostics.presentation = 'Banner displayed';
      diagnostics.record('In-app banner displayed');
    }
    _dismissTimer = Timer(const Duration(milliseconds: 4500), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_banner == null || _exiting) return;
    _exiting = true;
    _dismissTimer?.cancel();
    final revision = _revision;
    try {
      await _animation.reverse().orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || revision != _revision) return;
    setState(() {
      _banner = null;
      _exiting = false;
    });
    _showNext();
  }

  void _clear({bool resetSeen = false}) {
    _revision++;
    _dismissTimer?.cancel();
    _animation.stop();
    _pending.clear();
    if (resetSeen) _seen.clear();
    if (mounted) {
      setState(() {
        _banner = null;
        _exiting = false;
      });
    }
  }

  void _checkAccount() {
    final user = NotificationService.instance.userId;
    if (_user == user) return;
    _user = user;
    _clear(resetSeen: true);
  }

  void _checkCenter() {
    // RouteAware can notify while a route is mounting.
    if (!notificationCenterVisible.value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && notificationCenterVisible.value) _clear();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _clear();
  }

  void _tap() {
    final item = _banner;
    if (item == null || _exiting) return;
    _clear();
    unawaited((widget.onOpen ?? _open)(item.id));
  }

  Future<void> _open(String id) async {
    if (_opening == id) return;
    _opening = id;
    String? user;
    try {
      final db = Supabase.instance.client;
      user = db.auth.currentUser?.id;
      if (user == null) return;
      final destination = await db.rpc(
        'notification_destination',
        params: {'p_notification_id': id},
      );
      if (!mounted || db.auth.currentUser?.id != user) return;
      if (destination is! Map) throw StateError('Unavailable');
      final Widget page = switch (destination['screen']) {
        'tourist_booking' => ActivityTrackingScreen(
          bookingId: destination['booking_id'] as String,
        ),
        'driver_tracking' => DriverPackageTrackingScreen(
          activityId: destination['activity_id'] as String,
        ),
        'driver_jobs' => const DriverPackageJobsScreen(),
        _ => const NotificationCenterScreen(),
      };
      try {
        await NotificationService.instance.markRead(id);
      } catch (_) {}
      if (!mounted || db.auth.currentUser?.id != user) return;
      _clear();
      await notificationNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    } catch (_) {
      if (mounted &&
          user != null &&
          Supabase.instance.client.auth.currentUser?.id == user) {
        _clear();
        await notificationNavigatorKey.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => const NotificationCenterScreen(),
          ),
        );
      }
    } finally {
      _opening = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notificationCenterVisible.removeListener(_checkCenter);
    NotificationService.instance.detachPresenter();
    NotificationService.instance.removeListener(_checkAccount);
    NotificationService.instance.onOpen = null;
    _dismissTimer?.cancel();
    _subscription?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay.wrap(
    // Own Overlay supports tooltips above the Navigator. Reserve space so the
    // AppBar, dialogs and payment controls cannot be covered by the card.
    child: ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          if (_banner != null)
            SizeTransition(
              sizeFactor: _animation,
              axisAlignment: -1,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: FadeTransition(
                    opacity: _animation,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: _reduceMotion
                                ? Offset.zero
                                : const Offset(0, -0.12),
                            end: Offset.zero,
                          ).animate(
                            _animation.drive(
                              CurveTween(curve: Curves.easeOutCubic),
                            ),
                          ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: NotificationForegroundBanner(
                          key: _bannerKey,
                          item: _banner!,
                          onDismiss: _dismiss,
                          onTap: _tap,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: _banner != null,
              child: widget.child,
            ),
          ),
        ],
      ),
    ),
  );
}
