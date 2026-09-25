import 'package:flutter/material.dart';
import '../core/notifications/notification_service.dart';
import '../screens/shared/notification_center_screen.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key, this.color});
  final Color? color;
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NotificationService.instance.markAppReady();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: NotificationService.instance,
    builder: (context, _) {
      final count = NotificationService.instance.unreadCount;
      return IconButton(
        tooltip: count > 0 ? 'Notifications, $count unread' : 'Notifications',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const NotificationCenterScreen(),
          ),
        ),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 9 ? '9+' : '$count'),
          child: Icon(Icons.notifications_none_rounded, color: widget.color),
        ),
      );
    },
  );
}
