import 'tour_notification.dart';

/// FCM and Realtime may deliver the same event. Reconnect history never becomes
/// a backlog of banners. Durable event deduplication remains in PostgreSQL.
class NotificationPresentationGuard {
  final _seen = <String>{};
  bool shouldPresent(
    TourNotification item, {
    required DateTime now,
    required bool resumed,
    required bool ready,
    bool liveDelivery = false,
  }) {
    if (!ready || !item.foregroundEligible || !_seen.add(item.id)) {
      return false;
    }
    if (_seen.length > 300) _seen.remove(_seen.first);
    // Remember background receipts too: a delayed second transport must not
    // replay the same event when the app resumes.
    return resumed &&
        (liveDelivery || now.difference(item.createdAt).inSeconds <= 60);
  }

  void reset() => _seen.clear();
}
