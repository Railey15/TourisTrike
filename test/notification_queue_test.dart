import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/notifications/notification_presentation_guard.dart';
import 'package:touristrike/core/notifications/notification_service.dart';
import 'package:touristrike/core/notifications/notification_visibility.dart';
import 'package:touristrike/core/notifications/tour_notification.dart';
import 'package:touristrike/screens/shared/notification_center_screen.dart';
import 'package:touristrike/widgets/notification_host.dart';

TourNotification event(
  String id, {
  String type = 'spot_arrived',
  bool eligible = true,
}) => TourNotification(
  id: id,
  title: 'Arrived at iPlant Cafe $id',
  body: 'You have arrived at your tour destination.',
  type: type,
  createdAt: DateTime.now(),
  isRead: false,
  pushEnabled: false,
  inAppEnabled: eligible,
);

void main() {
  late StreamController<TourNotification> events;
  late GlobalKey<NavigatorState> navigator;
  Future<void> mount(
    WidgetTester tester, {
    Widget? home,
    bool reducedMotion = false,
    double textScale = 1,
    Future<void> Function(String)? onOpen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [notificationRouteObserver],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: NotificationHost(
            incoming: events.stream,
            onOpen: onOpen,
            child: child!,
          ),
        ),
        home: home ?? const Scaffold(body: Text('Home')),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> receive(WidgetTester tester, TourNotification item) async {
    events.add(item);
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<void> dismiss(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    events = StreamController<TourNotification>.broadcast();
    navigator = GlobalKey<NavigatorState>();
    notificationCenterVisible.value = false;
    NotificationService.instance.items = [];
    NotificationService.instance.preferences = null;
    NotificationService.instance.error = null;
    NotificationService.instance.loading = false;
  });
  tearDown(() async {
    await events.close();
    notificationCenterVisible.value = false;
    NotificationService.instance.items = [];
  });

  testWidgets(
    'one root subscription survives Home, Tracking, Dashboard and Profile routes',
    (tester) async {
      await mount(tester);
      for (final page in [
        'Home',
        'Tour Tracking',
        'Driver Dashboard',
        'Profile',
        'Chat',
        'Booking',
      ]) {
        if (page != 'Home') {
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(body: Text(page)),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        await receive(tester, event(page));
        expect(find.byType(NotificationForegroundBanner), findsOneWidget);
        expect(find.text('Arrived at iPlant Cafe $page'), findsOneWidget);
        await dismiss(tester);
        await receive(tester, event(page)); // replay after route/build/dismiss
        expect(find.byType(NotificationForegroundBanner), findsNothing);
      }
    },
  );

  testWidgets(
    'FIFO queue never replaces the current card and bounds waiting events to three',
    (tester) async {
      await mount(tester);
      await receive(tester, event('A'));
      for (final id in ['B', 'C', 'D', 'E', 'E']) {
        events.add(event(id));
      }
      await tester.pumpAndSettle();
      expect(find.text('Arrived at iPlant Cafe A'), findsOneWidget);
      for (final id in ['C', 'D', 'E']) {
        await dismiss(tester);
        expect(find.byType(NotificationForegroundBanner), findsOneWidget);
        expect(find.text('Arrived at iPlant Cafe $id'), findsOneWidget);
      }
      await dismiss(tester);
      expect(find.byType(NotificationForegroundBanner), findsNothing);
    },
  );

  testWidgets(
    'timeout and swipe dismiss without altering persistent history or read state',
    (tester) async {
      await mount(tester);
      final row = event('history');
      NotificationService.instance.items = [row];
      await receive(tester, row);
      expect(find.text('Just now'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 4500));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationForegroundBanner), findsNothing);
      expect(NotificationService.instance.items.single, same(row));
      expect(row.isRead, false);
      await receive(tester, event('swipe'));
      await tester.fling(
        find.byType(NotificationForegroundBanner),
        const Offset(0, -120),
        700,
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotificationForegroundBanner), findsNothing);
    },
  );

  testWidgets(
    'background clears active and queued cards; resume cannot replay suppressed IDs',
    (tester) async {
      await mount(tester);
      await receive(tester, event('A'));
      events.add(event('B'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      events.add(event('C'));
      await tester.pump();
      expect(find.byType(NotificationForegroundBanner), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (final id in ['A', 'B', 'C']) {
        events.add(event(id));
      }
      await tester.pumpAndSettle();
      expect(find.byType(NotificationForegroundBanner), findsNothing);
      await receive(tester, event('D'));
      expect(find.text('Arrived at iPlant Cafe D'), findsOneWidget);
      await dismiss(tester);
    },
  );

  test(
    'transport guard remembers a background event reported again on resume',
    () {
      final guard = NotificationPresentationGuard();
      final row = event('same-id');
      expect(
        guard.shouldPresent(
          row,
          now: DateTime.now(),
          resumed: false,
          ready: true,
          liveDelivery: true,
        ),
        false,
      );
      expect(
        guard.shouldPresent(
          row,
          now: DateTime.now(),
          resumed: true,
          ready: true,
          liveDelivery: true,
        ),
        false,
      );
    },
  );

  testWidgets(
    'Notification Center retains history without a redundant banner; new routes resume presentation',
    (tester) async {
      await mount(tester);
      final row = event('center');
      NotificationService.instance.items = [row];
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const NotificationCenterScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(notificationCenterVisible.value, true);
      await receive(tester, row);
      expect(find.text(row.title), findsOneWidget);
      expect(find.byType(NotificationForegroundBanner), findsNothing);
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Profile')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(notificationCenterVisible.value, false);
      await receive(tester, event('profile'));
      expect(find.byType(NotificationForegroundBanner), findsOneWidget);
      await dismiss(tester);
    },
  );

  testWidgets(
    'arrival never navigates; tap uses the existing ID and clears waiting banners',
    (tester) async {
      final opened = <String>[];
      await mount(
        tester,
        onOpen: (id) async {
          opened.add(id);
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('Authorized destination')),
              ),
            ),
          );
        },
      );
      await receive(tester, event('tap'));
      events.add(event('queued'));
      await tester.pump();
      expect(opened, isEmpty);
      expect(find.text('Home'), findsOneWidget);
      await tester.tap(find.text('Arrived at iPlant Cafe tap'));
      await tester.pumpAndSettle();
      expect(opened, ['tap']);
      expect(find.text('Authorized destination'), findsOneWidget);
      expect(find.byType(NotificationForegroundBanner), findsNothing);
    },
  );

  testWidgets(
    'dialog, keyboard focus and confirmation controls survive a foreground event',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await mount(tester);
      unawaited(
        showDialog<void>(
          context: navigator.currentContext!,
          builder: (_) => AlertDialog(
            title: const Text('Payment confirmation'),
            content: TextField(focusNode: focus),
            actions: [
              TextButton(onPressed: () {}, child: const Text('Confirm')),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetViewInsets);
      await receive(tester, event('payment', type: 'remaining_balance_due'));
      expect(focus.hasFocus, true);
      expect(find.text('Payment confirmation'), findsOneWidget);
      expect(find.text('Confirm').hitTestable(), findsOneWidget);
      expect(find.byType(NotificationForegroundBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
      await dismiss(tester);
    },
  );

  testWidgets('noise, debug, read/history-only events do not enter the queue', (
    tester,
  ) async {
    await mount(tester);
    for (final type in [
      'gps_changed',
      'eta_updated',
      'map_refreshed',
      'realtime_reconnect',
      'debug_event',
      'notification_test',
    ]) {
      await receive(tester, event(type, type: type));
    }
    await receive(tester, event('history', eligible: false));
    expect(find.byType(NotificationForegroundBanner), findsNothing);
  });

  for (final width in [320.0, 430.0, 768.0]) {
    testWidgets('safe area and large text fit at $width with reduced motion', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 48);
      addTearDown(tester.view.reset);
      await mount(tester, reducedMotion: true, textScale: 1.6);
      await receive(tester, event('accessible'));
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(NotificationForegroundBanner));
      expect(card.top, greaterThanOrEqualTo(48));
      expect(card.left, greaterThanOrEqualTo(16));
      expect(card.right, lessThanOrEqualTo(width - 16));
      expect(
        tester.getRect(find.byType(Scaffold)).top,
        greaterThanOrEqualTo(card.bottom),
      );
      await dismiss(tester);
    });
  }
}
