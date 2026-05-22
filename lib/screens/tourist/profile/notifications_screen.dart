import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _markingAllRead = false;
  bool _savingSettings = false;
  String? _settingsWarning;
  List<_AppNotification> _notifications = const [];
  _NotificationSettings? _settings;
  RealtimeChannel? _notificationsChannel;

  User? get _user => _supabase.auth.currentUser;

  int get _unreadCount => _notifications.where((item) => !item.isRead).length;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _notificationsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = _user?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _notifications = const [];
          _settings = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final notificationsRows = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      _NotificationSettings? settings;
      String? settingsWarning;

      try {
        settings = await _loadOrCreateSettings(userId);
      } catch (error, stackTrace) {
        debugPrint('NotificationsScreen settings sync error: $error');
        debugPrintStack(stackTrace: stackTrace);
        settings = _NotificationSettings.defaults(userId);
        settingsWarning =
            'Notification preferences could not sync with the database.';
      }

      if (!mounted) return;
      setState(() {
        _notifications = (notificationsRows as List<dynamic>)
            .map(
              (row) => _AppNotification.fromMap(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList();
        _settings = settings;
        _settingsWarning = settingsWarning;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('NotificationsScreen _loadData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Unable to load notifications.');
    }
  }

  Future<_NotificationSettings> _loadOrCreateSettings(String userId) async {
    final row = await _supabase
        .from('notification_settings')
        .select()
        .eq('tourist_id', userId)
        .maybeSingle();

    if (row != null) {
      return _NotificationSettings.fromMap(row, userId);
    }

    final defaults = _NotificationSettings.defaults(userId);
    await _supabase
        .from('notification_settings')
        .upsert(defaults.toMap(), onConflict: 'tourist_id');
    return defaults;
  }

  void _subscribeToRealtime() {
    final userId = _user?.id;
    if (userId == null) return;

    _notificationsChannel?.unsubscribe();
    _notificationsChannel = _supabase
        .channel('tourist_notifications_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _loadData(),
        )
        .subscribe();
  }

  Future<void> _markNotificationAsRead(_AppNotification notification) async {
    final userId = _user?.id;
    if (userId == null || notification.isRead) return;

    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notification.id)
          .eq('user_id', userId);
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map(
              (item) => item.id == notification.id
                  ? item.copyWith(isRead: true)
                  : item,
            )
            .toList();
      });
    } catch (error, stackTrace) {
      debugPrint('NotificationsScreen _markNotificationAsRead error: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showError('Unable to mark this notification as read.');
    }
  }

  Future<void> _markAllAsRead() async {
    final userId = _user?.id;
    if (userId == null || _markingAllRead || _unreadCount == 0) return;

    if (mounted) {
      setState(() => _markingAllRead = true);
    }

    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map((item) => item.copyWith(isRead: true))
            .toList();
        _markingAllRead = false;
      });
      _showSuccess('All notifications marked as read.');
    } catch (error, stackTrace) {
      debugPrint('NotificationsScreen _markAllAsRead error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _markingAllRead = false);
      _showError('Unable to mark all notifications as read.');
    }
  }

  Future<void> _saveData(_NotificationSettings nextSettings) async {
    final userId = _user?.id;
    if (userId == null || _savingSettings) return;

    final previous = _settings ?? _NotificationSettings.defaults(userId);
    if (mounted) {
      setState(() {
        _settings = nextSettings;
        _savingSettings = true;
      });
    }

    try {
      await _supabase
          .from('notification_settings')
          .upsert(nextSettings.toMap(), onConflict: 'tourist_id');
      if (!mounted) return;
      setState(() {
        _savingSettings = false;
        _settingsWarning = null;
      });
      _showSuccess('Notification preferences updated.');
    } catch (error, stackTrace) {
      debugPrint('NotificationsScreen _saveData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _settings = previous;
        _savingSettings = false;
      });
      _showError('Unable to update notification preferences.');
    }
  }

  void _showSuccess(String message) => _showSnack(message, isError: false);

  void _showError(String message) => _showSnack(message, isError: true);

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    final settings =
        _settings ?? _NotificationSettings.defaults(_user?.id ?? '');

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _TopCircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 20.5,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: (_markingAllRead || _unreadCount == 0)
                        ? null
                        : _markAllAsRead,
                    child: _markingAllRead
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Mark all read'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: blue,
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                  children: [
                    _OverviewCard(unreadCount: _unreadCount),
                    if (_settingsWarning != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Text(
                          _settingsWarning!,
                          style: const TextStyle(
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const _SectionTitle('Preferences'),
                    const SizedBox(height: 10),
                    _Card(
                      child: Column(
                        children: [
                          _SwitchRow(
                            icon: Icons.book_online_rounded,
                            title: 'Booking updates',
                            subtitle: 'Booking confirmations and changes',
                            value: settings.bookingUpdates,
                            onChanged: (value) => _saveData(
                              settings.copyWith(bookingUpdates: value),
                            ),
                          ),
                          const Divider(height: 18, color: Color(0xFFE7EEF7)),
                          _SwitchRow(
                            icon: Icons.drive_eta_rounded,
                            title: 'Driver updates',
                            subtitle: 'Driver assignment and trip progress',
                            value: settings.driverUpdates,
                            onChanged: (value) => _saveData(
                              settings.copyWith(driverUpdates: value),
                            ),
                          ),
                          const Divider(height: 18, color: Color(0xFFE7EEF7)),
                          _SwitchRow(
                            icon: Icons.payments_rounded,
                            title: 'Payment updates',
                            subtitle: 'Payment status and receipts',
                            value: settings.paymentUpdates,
                            onChanged: (value) => _saveData(
                              settings.copyWith(paymentUpdates: value),
                            ),
                          ),
                          const Divider(height: 18, color: Color(0xFFE7EEF7)),
                          _SwitchRow(
                            icon: Icons.local_offer_rounded,
                            title: 'Promotions',
                            subtitle: 'Offers, promos, and announcements',
                            value: settings.promotions,
                            onChanged: (value) =>
                                _saveData(settings.copyWith(promotions: value)),
                          ),
                          const Divider(height: 18, color: Color(0xFFE7EEF7)),
                          _SwitchRow(
                            icon: Icons.warning_amber_rounded,
                            title: 'Emergency alerts',
                            subtitle: 'Critical safety notices',
                            value: settings.emergencyAlerts,
                            onChanged: (value) => _saveData(
                              settings.copyWith(emergencyAlerts: value),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_savingSettings)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'Saving your notification preferences...',
                          style: TextStyle(
                            color: textMid,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const _SectionTitle('Recent Notifications'),
                    const SizedBox(height: 10),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: CircularProgressIndicator(color: blue),
                        ),
                      )
                    else if (_notifications.isEmpty)
                      const _EmptyState()
                    else
                      ..._notifications.map(
                        (notification) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _NotificationCard(
                            notification: notification,
                            onTap: () => _markNotificationAsRead(notification),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppNotification {
  const _AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });

  factory _AppNotification.fromMap(Map<String, dynamic> map) {
    return _AppNotification(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      isRead: map['is_read'] == true,
      createdAt: DateTime.tryParse((map['created_at'] ?? '').toString()),
    );
  }

  final String id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime? createdAt;

  _AppNotification copyWith({bool? isRead}) {
    return _AppNotification(
      id: id,
      title: title,
      body: body,
      type: type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  String get dateLabel {
    if (createdAt == null) return 'Unknown date';
    return DateFormat.yMMMd().add_jm().format(createdAt!.toLocal());
  }
}

class _NotificationSettings {
  const _NotificationSettings({
    required this.touristId,
    required this.bookingUpdates,
    required this.driverUpdates,
    required this.paymentUpdates,
    required this.promotions,
    required this.emergencyAlerts,
  });

  factory _NotificationSettings.fromMap(
    Map<String, dynamic> map,
    String userId,
  ) {
    return _NotificationSettings(
      touristId: (map['tourist_id'] ?? userId).toString(),
      bookingUpdates: map['booking_updates'] != false,
      driverUpdates: map['driver_updates'] != false,
      paymentUpdates: map['payment_updates'] != false,
      promotions: map['promotions'] == true,
      emergencyAlerts: map['emergency_alerts'] != false,
    );
  }

  factory _NotificationSettings.defaults(String userId) {
    return _NotificationSettings(
      touristId: userId,
      bookingUpdates: true,
      driverUpdates: true,
      paymentUpdates: true,
      promotions: false,
      emergencyAlerts: true,
    );
  }

  final String touristId;
  final bool bookingUpdates;
  final bool driverUpdates;
  final bool paymentUpdates;
  final bool promotions;
  final bool emergencyAlerts;

  _NotificationSettings copyWith({
    bool? bookingUpdates,
    bool? driverUpdates,
    bool? paymentUpdates,
    bool? promotions,
    bool? emergencyAlerts,
  }) {
    return _NotificationSettings(
      touristId: touristId,
      bookingUpdates: bookingUpdates ?? this.bookingUpdates,
      driverUpdates: driverUpdates ?? this.driverUpdates,
      paymentUpdates: paymentUpdates ?? this.paymentUpdates,
      promotions: promotions ?? this.promotions,
      emergencyAlerts: emergencyAlerts ?? this.emergencyAlerts,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tourist_id': touristId,
      'booking_updates': bookingUpdates,
      'driver_updates': driverUpdates,
      'payment_updates': paymentUpdates,
      'promotions': promotions,
      'emergency_alerts': emergencyAlerts,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF0F172A)),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.notifications_active_rounded, color: blue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Unread Notifications',
                  style: TextStyle(color: textMid, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  unreadCount.toString(),
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontWeight: FontWeight.w900,
        fontSize: 16,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: child,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF2A86FF)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final _AppNotification notification;
  final VoidCallback onTap;

  IconData get _icon {
    final value = notification.type.toLowerCase();
    if (value.contains('payment')) return Icons.payments_rounded;
    if (value.contains('driver')) return Icons.drive_eta_rounded;
    if (value.contains('book')) return Icons.book_online_rounded;
    if (value.contains('emergency')) return Icons.warning_amber_rounded;
    return Icons.notifications_rounded;
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: notification.isRead
                ? const Color(0xFFE7EEF7)
                : const Color(0xFFBBD7FF),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(_icon, color: blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: const TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (notification.body.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        color: textMid,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    notification.dateLabel,
                    style: const TextStyle(
                      color: textMid,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: const Text(
        'No notifications yet. New updates will appear here in realtime.',
        style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w900),
      ),
    );
  }
}
