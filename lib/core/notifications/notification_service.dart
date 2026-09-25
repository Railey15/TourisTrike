import 'dart:async';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tour_notification.dart';
import 'notification_presentation_guard.dart';
import 'notification_diagnostics.dart';

@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (kDebugMode) debugPrint('[NOTIFICATION] Background message received');
  // FCM's notification payload is displayed by Android. Never insert history here.
}

class NotificationService extends ChangeNotifier with WidgetsBindingObserver {
  NotificationService._();
  static final instance = NotificationService._();
  final _incoming = StreamController<TourNotification>.broadcast();
  Stream<TourNotification> get incoming => _incoming.stream;
  final _presentation = NotificationPresentationGuard();
  final diagnostics = NotificationDiagnostics.instance;
  final _waitingForPresenter = <String, TourNotification>{};
  bool _presenterReady = false;
  int _requestVersion = 0;
  SupabaseClient get _db => Supabase.instance.client;
  RealtimeChannel? _channel;
  String? _userId;
  String? get userId => _userId;
  int _generation = 0;
  bool _started = false, _resumed = true, _ready = false;
  bool pushAvailable = false,
      pushGranted = false,
      loading = false,
      hasMore = true;
  String? error;
  Map<String, bool>? preferences;
  int unreadCount = 0;
  List<TourNotification> items = [];
  String? _pendingTap;
  Future<void> Function(String)? onOpen;

  Future<void> initialize() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _db.auth.onAuthStateChange.listen((state) {
      if (_userId != state.session?.user.id) unawaited(_bindUser());
    });
    unawaited(_bindUser());
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await Firebase.initializeApp().timeout(const Duration(seconds: 8));
        diagnostics.firebase = 'Initialized';
        diagnostics.record('Firebase initialized');
        FirebaseMessaging.onBackgroundMessage(notificationBackgroundHandler);
        diagnostics.record('Background handler registered before runApp');
        pushAvailable = true;
        FirebaseMessaging.onMessage.listen((message) {
          diagnostics.record('Foreground message received');
          final id = TourNotification.payloadId(message.data);
          if (id != null) {
            unawaited(_receiveId(id));
          } else {
            diagnostics.record(
              'Foreground message ignored: missing persistent notification ID',
            );
          }
        });
        FirebaseMessaging.onMessageOpenedApp.listen(
          (message) => openPayload(message.data),
        );
        FirebaseMessaging.instance.onTokenRefresh.listen(
          (token) {
            diagnostics.token = 'Obtained (refreshed)';
            diagnostics.record('FCM token refreshed');
            unawaited(_registerToken(token));
          },
          onError: (Object error) =>
              diagnostics.failure('Token refresh', error),
        );
        diagnostics.record('Foreground listener registered');
        unawaited(_loadInitialMessage());
        unawaited(syncPermission());
      } catch (error) {
        // Missing Google configuration must not prevent login or persistent history.
        pushAvailable = false;
        diagnostics.firebase =
            'Unavailable: Firebase configuration missing or invalid';
        diagnostics.failure('Firebase initialization', error);
      }
    }
    notifyListeners();
  }

  Future<void> _loadInitialMessage() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        diagnostics.record('Notification launch received');
        openPayload(initial.data);
      }
    } catch (error) {
      diagnostics.failure('Initial notification lookup', error);
    }
  }

  // Foreground delivery depends on the app-level presenter, not a home bell.
  // A restored/deep-linked tracking route may never build that bell.
  void attachPresenter() {
    _presenterReady = true;
    diagnostics.record('In-app presenter ready');
    final pending = _waitingForPresenter.values.toList();
    _waitingForPresenter.clear();
    for (final item in pending) {
      _announce(item);
    }
  }

  void detachPresenter() {
    _presenterReady = false;
  }

  Future<void> _bindUser() async {
    final previous = _userId;
    _userId = _db.auth.currentUser?.id;
    _generation++;
    _ready = false;
    items = [];
    unreadCount = 0;
    loading = false;
    hasMore = true;
    preferences = null;
    _presentation.reset();
    _waitingForPresenter.clear();
    diagnostics.registration = 'Not registered';
    error = null;
    if (previous != null) _pendingTap = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(_db.removeChannel(channel));
    notifyListeners();
    if (_userId == null) {
      diagnostics.realtime = 'Signed out';
      if (pushAvailable) {
        try {
          await FirebaseMessaging.instance.deleteToken();
        } catch (_) {}
      }
      return;
    }
    final user = _userId!;
    _channel = _db
        .channel('notification-center:$user')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user,
          ),
          callback: (payload) {
            if (user != _userId) return;
            if (payload.eventType == PostgresChangeEvent.insert &&
                payload.newRecord['user_id'] == user) {
              diagnostics.record(
                'Realtime event received: ${payload.newRecord['type']}',
              );
              _announce(TourNotification.fromMap(payload.newRecord));
            }
            unawaited(refresh());
          },
        )
        .subscribe((status, error) {
          diagnostics.realtime = status.name;
          diagnostics.record('Realtime subscription: ${status.name}');
          if (error != null) {
            diagnostics.failure('Realtime subscription', error);
          }
          if (status == RealtimeSubscribeStatus.subscribed && user == _userId) {
            unawaited(refresh());
          }
        });
    await refresh();
    try {
      final row = await _db
          .from('notification_settings')
          .select('booking_updates,driver_updates,payment_updates')
          .eq('tourist_id', user)
          .maybeSingle();
      if (_userId == user && row != null) {
        preferences = {
          for (final key in [
            'booking_updates',
            'driver_updates',
            'payment_updates',
          ])
            key: row[key] != false,
        };
        notifyListeners();
      }
    } catch (_) {
      /* Older schemas do not have optional preference rows. */
    }
    await syncPermission();
  }

  Future<void> setPreference(String key, bool enabled) async {
    if (_userId == null || preferences?.containsKey(key) != true) return;
    final user = _userId!;
    await _db
        .from('notification_settings')
        .update({key: enabled})
        .eq('tourist_id', user);
    if (_userId == user) {
      preferences = {...preferences!, key: enabled};
      notifyListeners();
    }
  }

  Future<void> refresh({bool more = false}) async {
    final user = _userId;
    if (user == null) return;
    if (more && loading) return;
    final generation = _generation;
    final requestVersion = ++_requestVersion;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final offset = more ? items.length : 0;
      final rows = await _db
          .from('notifications')
          .select()
          .eq('user_id', user)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + 49);
      final count = await _db
          .from('notifications')
          .count(CountOption.exact)
          .eq('user_id', user)
          .eq('is_read', false);
      if (generation != _generation || requestVersion != _requestVersion) {
        return;
      }
      final page = rows.map(TourNotification.fromMap).toList();
      final merged = <String, TourNotification>{
        for (final n in more ? items : <TourNotification>[]) n.id: n,
        for (final n in page) n.id: n,
      };
      items = merged.values.toList();
      hasMore = page.length == 50;
      unreadCount = count;
    } catch (error) {
      if (generation == _generation && requestVersion == _requestVersion) {
        diagnostics.failure('Notification history read', error);
        this.error = 'Unable to load notifications. Pull down to try again.';
      }
    } finally {
      if (generation == _generation && requestVersion == _requestVersion) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> markRead([String? id]) async {
    final user = _userId;
    if (user == null) return;
    var query = _db
        .from('notifications')
        .update({
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', user)
        .eq('is_read', false);
    if (id != null) query = query.eq('id', id);
    await query;
    await refresh();
  }

  void _announce(TourNotification item) {
    if (!_presenterReady && _resumed && item.inAppEnabled && !item.isRead) {
      _waitingForPresenter[item.id] = item;
      if (_waitingForPresenter.length > 5) {
        _waitingForPresenter.remove(_waitingForPresenter.keys.first);
      }
      diagnostics.record('Foreground event waiting for presenter');
      return;
    }
    if (_presentation.shouldPresent(
      item,
      now: DateTime.now(),
      resumed: _resumed,
      ready: _presenterReady,
      liveDelivery: true,
    )) {
      diagnostics.presentation = 'Event delivered to presenter';
      diagnostics.record(
        'Foreground event delivered to presenter: ${item.type}',
      );
      _incoming.add(item);
    } else {
      diagnostics.record(
        'Banner suppressed: background, read, history-only, or duplicate',
      );
    }
  }

  Future<void> _receiveId(String id) async {
    final user = _userId;
    if (user == null) return;
    try {
      final row = await _db
          .from('notifications')
          .select()
          .eq('id', id)
          .eq('user_id', user)
          .maybeSingle();
      if (user != _userId || row == null) return;
      _announce(TourNotification.fromMap(row));
      await refresh();
    } catch (error) {
      diagnostics.failure('Foreground notification lookup', error);
    }
  }

  void openPayload(Map<String, dynamic> payload) {
    final id = TourNotification.payloadId(payload);
    if (id != null) open(id);
  }

  void open(String id) {
    _pendingTap = id;
    _flushTap();
  }

  void markAppReady() {
    _ready = true;
    _flushTap();
  }

  void _flushTap() {
    if (!_ready || _userId == null || onOpen == null || _pendingTap == null) {
      return;
    }
    final id = _pendingTap!;
    _pendingTap = null;
    unawaited(onOpen!(id));
  }

  Future<String> _installationId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('notification_installation');
    if (existing != null) return existing;
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final id =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await prefs.setString('notification_installation', id);
    return id;
  }

  Future<void> _registerToken(String token) async {
    if (_userId == null || !pushGranted) return;
    final user = _userId;
    try {
      final installation = await _installationId();
      if (user != _userId) return;
      await _db.rpc(
        'register_notification_device',
        params: {'p_installation_id': installation, 'p_token': token},
      );
      if (user != _userId) return;
      final proof = await _db.rpc(
        'notification_device_status',
        params: {'p_installation_id': installation},
      );
      if (proof is! Map || proof['registered'] != true) {
        throw StateError('Registration not verified');
      }
      diagnostics.registration = 'Verified on Supabase';
      diagnostics.record('Token registration: success (verified on Supabase)');
    } catch (error) {
      diagnostics.registration = 'Failed; will retry on resume';
      diagnostics.failure('Token registration', error);
      /* Retried on resume/token refresh; history remains available. */
    }
  }

  Future<void> syncPermission() async {
    if (!pushAvailable || _userId == null) return;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      pushGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized;
      diagnostics.permission = settings.authorizationStatus.name;
      diagnostics.record('Permission: ${settings.authorizationStatus.name}');
      if (pushGranted) {
        await FirebaseMessaging.instance.setAutoInitEnabled(true);
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          diagnostics.token = 'Obtained';
          diagnostics.record('FCM token obtained');
          await _registerToken(token);
        } else {
          diagnostics.token = 'Unavailable';
          diagnostics.record('FCM returned no registration token');
        }
      }
    } catch (error) {
      diagnostics.failure('Permission/token initialization', error);
    }
    notifyListeners();
  }

  // Only called from the explanatory, user-initiated Notification Center action.
  Future<void> requestPushPermission() async {
    if (!pushAvailable) return;
    diagnostics.record('User requested notification permission');
    await FirebaseMessaging.instance.requestPermission();
    await syncPermission();
  }

  Future<void> prepareSignOut() async {
    if (!pushAvailable) return;
    try {
      await _db.rpc(
        'unregister_notification_device',
        params: {'p_installation_id': await _installationId()},
      );
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) {
      unawaited(refresh());
      unawaited(syncPermission());
    }
  }
}
