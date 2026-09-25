import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/notifications/tour_notification.dart';
import '../../core/notifications/notification_diagnostics.dart';
import '../../core/notifications/notification_visibility.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});
  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen>
    with RouteAware {
  final service = NotificationService.instance;
  ModalRoute<dynamic>? _route;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      notificationRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) notificationRouteObserver.subscribe(this, route);
    }
  }

  void _visibility(bool visible) {
    _visible = visible;
    notificationCenterVisible.value = visible;
  }

  @override
  void didPush() => _visibility(true);
  @override
  void didPopNext() => _visibility(true);
  @override
  void didPushNext() => _visibility(false);
  @override
  void didPop() => _visibility(false);
  @override
  void dispose() {
    notificationRouteObserver.unsubscribe(this);
    if (_visible) notificationCenterVisible.value = false;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // This shared notifier also drives the underlying home bell. Wait until the
    // route is mounted before notifying listeners outside this new subtree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) service.refresh();
    });
  }

  Future<void> _markAll() async {
    try {
      await service.markRead();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to mark notifications as read. Try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final rows = <Widget>[];
      String? lastGroup;
      for (final item in service.items) {
        final group = !item.createdAt.isBefore(today)
            ? 'Today'
            : !item.createdAt.isBefore(today.subtract(const Duration(days: 1)))
            ? 'Yesterday'
            : 'Earlier';
        if (group != lastGroup) {
          rows.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(group, style: Theme.of(context).textTheme.labelLarge),
            ),
          );
          lastGroup = group;
        }
        rows.add(
          _NotificationTile(item: item, onTap: () => service.open(item.id)),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            if (service.preferences != null)
              IconButton(
                tooltip: 'Notification preferences',
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheetContext) => SafeArea(
                    child: ListenableBuilder(
                      listenable: service,
                      builder: (context, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'Notification preferences',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          for (final entry
                              in (service.preferences ?? <String, bool>{})
                                  .entries)
                            SwitchListTile(
                              title: Text(switch (entry.key) {
                                'booking_updates' => 'Booking updates',
                                'driver_updates' => 'Driver and tour updates',
                                _ => 'Payment updates',
                              }),
                              value: entry.value,
                              onChanged: (value) async {
                                try {
                                  await service.setPreference(entry.key, value);
                                } catch (_) {
                                  if (sheetContext.mounted) {
                                    ScaffoldMessenger.of(
                                      sheetContext,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Unable to save notification preferences.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'Your notification history remains available. Emergency alerts follow your Android notification settings.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (service.unreadCount > 0)
              IconButton(
                tooltip: 'Mark all as read',
                onPressed: _markAll,
                icon: const Icon(Icons.done_all_rounded),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: service.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (kDebugMode)
                ListenableBuilder(
                  listenable: NotificationDiagnostics.instance,
                  builder: (context, _) {
                    final d = NotificationDiagnostics.instance;
                    return ExpansionTile(
                      title: const Text('Notification diagnostics'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Firebase: ${d.firebase}\nPermission: ${d.permission}\nToken: ${d.token}\nRegistration: ${d.registration}\nRealtime: ${d.realtime}\nForeground: ${d.presentation}',
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              if (service.pushAvailable && !service.pushGranted)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stay updated on your tour',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Allow notifications for important booking, driver arrival, payment, and tour updates. Your history stays here even if you decline.',
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await service.requestPushPermission();
                            if (context.mounted && !service.pushGranted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'You can enable notifications in Android Settings.',
                                  ),
                                ),
                              );
                            }
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Unable to enable notifications. Try again later.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Enable notifications'),
                      ),
                    ],
                  ),
                ),
              if (service.loading && service.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (service.error != null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(service.error!),
                ),
              if (!service.loading &&
                  service.error == null &&
                  service.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(32, 80, 32, 32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.notifications_none_rounded,
                        size: 44,
                        color: Color(0xFF64748B),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No notifications yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Important booking and tour updates will appear here.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ...rows,
              if (service.hasMore && service.items.isNotEmpty)
                TextButton(
                  onPressed: service.loading
                      ? null
                      : () => service.refresh(more: true),
                  child: const Text('Load earlier notifications'),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});
  final TourNotification item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final age = DateTime.now().difference(item.createdAt);
    final time = age.inMinutes < 1
        ? 'Just now'
        : age.inHours < 1
        ? '${age.inMinutes} min ago'
        : age.inDays < 1
        ? '${age.inHours} hr ago'
        : DateFormat('MMM d, h:mm a').format(item.createdAt);
    final icon = item.type.contains('emergency')
        ? Icons.emergency_outlined
        : item.type.contains('payment') || item.type.contains('cash')
        ? Icons.payments_outlined
        : item.type.contains('cancel')
        ? Icons.event_busy_outlined
        : item.type.contains('arrived') || item.type.contains('spot')
        ? Icons.place_outlined
        : item.type.contains('completed')
        ? Icons.check_circle_outline_rounded
        : Icons.route_outlined;
    return Material(
      color: item.isRead ? Colors.transparent : const Color(0xFFEFF6FF),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: Icon(icon, color: const Color(0xFF2563EB)),
        title: Text(
          item.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.body),
            const SizedBox(height: 5),
            Text(
              time,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
        trailing: item.isRead
            ? null
            : const Icon(Icons.circle, size: 7, color: Color(0xFF2563EB)),
      ),
    );
  }
}
