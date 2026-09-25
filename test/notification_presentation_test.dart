import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/notifications/notification_presentation_guard.dart';
import 'package:touristrike/core/notifications/notification_service.dart';
import 'package:touristrike/core/notifications/tour_notification.dart';
import 'package:touristrike/screens/shared/notification_center_screen.dart';
import 'package:touristrike/widgets/notification_bell.dart';
import 'package:touristrike/widgets/notification_host.dart';

TourNotification item({
  String id = '1',
  bool push = true,
  bool read = false,
  DateTime? date,
}) => TourNotification(
  id: id,
  title: 'Driver Arrived',
  body: 'Your driver has arrived at the pickup point.',
  type: 'driver_arrived',
  createdAt: date ?? DateTime.now(),
  isRead: read,
  pushEnabled: push,
);
void main() {
  testWidgets(
    'app-level banner renders above Navigator with a working dismiss tooltip',
    (tester) async {
      final events = StreamController<TourNotification>.broadcast();
      addTearDown(events.close);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              NotificationHost(incoming: events.stream, child: child!),
          home: Scaffold(body: Center(child: Text('Tracking content'))),
        ),
      );
      events.add(item());
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Driver Arrived'), findsOneWidget);
      final banner = tester.getRect(find.byType(NotificationForegroundBanner));
      final page = tester.getRect(find.byType(Scaffold));
      expect(banner.height, greaterThan(0));
      expect(banner.bottom, lessThanOrEqualTo(page.top));
      await tester.tap(find.byTooltip('Dismiss notification'));
      await tester.pumpAndSettle();
      expect(find.text('Driver Arrived'), findsNothing);
      events.add(item(id: '2'));
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Driver Arrived'), findsNothing);
    },
  );
  test('live delivery is not suppressed by a skewed device clock', () {
    final guard = NotificationPresentationGuard();
    final arrived = item(
      date: DateTime.now().subtract(const Duration(minutes: 10)),
    );
    expect(
      guard.shouldPresent(
        arrived,
        now: DateTime.now(),
        resumed: true,
        ready: true,
        liveDelivery: true,
      ),
      true,
    );
    expect(
      guard.shouldPresent(
        arrived,
        now: DateTime.now(),
        resumed: true,
        ready: true,
        liveDelivery: true,
      ),
      false,
    );
  });
  testWidgets('foreground banner is tappable and compact on a narrow device', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var tapped = false;
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationForegroundBanner(
            item: item(),
            onTap: () => tapped = true,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Driver Arrived'));
    expect(tapped, true);
    await tester.tap(find.byTooltip('Dismiss notification'));
    expect(dismissed, true);
  });
  testWidgets(
    'existing preferences remain available without changing history',
    (tester) async {
      final service = NotificationService.instance;
      service.preferences = {
        'booking_updates': false,
        'driver_updates': true,
        'payment_updates': true,
      };
      service.items = [];
      service.loading = false;
      service.error = null;
      await tester.pumpWidget(
        const MaterialApp(home: NotificationCenterScreen()),
      );
      await tester.tap(find.byTooltip('Notification preferences'));
      await tester.pumpAndSettle();
      expect(find.text('Booking updates'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNWidgets(3));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
        false,
      );
      service.preferences = null;
    },
  );
  test(
    'foreground Realtime plus FCM presents one banner; refresh and background are silent',
    () {
      final guard = NotificationPresentationGuard();
      final notification = item();
      bool present(
        TourNotification n, {
        bool resumed = true,
        bool ready = true,
      }) => guard.shouldPresent(
        n,
        now: DateTime.now(),
        resumed: resumed,
        ready: ready,
      );
      expect(present(notification), true);
      expect(present(notification), false);
      expect(present(item(id: '2', push: false)), false);
      expect(present(item(id: '3', read: true)), false);
      expect(present(item(id: '4'), resumed: false), false);
      expect(present(item(id: '5'), ready: false), false);
      expect(
        present(
          item(
            id: '6',
            date: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ),
        false,
      );
      guard.reset();
      expect(present(notification), true);
    },
  );
  testWidgets('shared bell caps unread badge and opens persistent history', (
    tester,
  ) async {
    final service = NotificationService.instance;
    service.items = [item()];
    service.unreadCount = 12;
    service.hasMore = false;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NotificationBell())),
    );
    expect(find.text('9+'), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Driver Arrived'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    String? tapped;
    service.onOpen = (id) async {
      tapped = id;
    };
    // With no authenticated binding, the tap remains queued instead of navigating.
    await tester.tap(find.text('Driver Arrived'));
    expect(tapped, isNull);
    service.onOpen = null;
    service.items = [];
    service.unreadCount = 0;
  });
  testWidgets(
    'denied/unconfigured push does not hide the empty Notification Center',
    (tester) async {
      final service = NotificationService.instance;
      service.items = [];
      service.loading = false;
      service.error = null;
      service.pushAvailable = false;
      await tester.pumpWidget(
        const MaterialApp(home: NotificationCenterScreen()),
      );
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(
        find.text('Important booking and tour updates will appear here.'),
        findsOneWidget,
      );
    },
  );
}
