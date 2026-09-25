import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/notifications/tour_notification.dart';

void main() {
  test('foreground eligibility is independent of Android push', () {
    final item = TourNotification.fromMap({
      'id': '42',
      'created_at': '2026-09-25T01:00:00Z',
      'push_enabled': false,
      'in_app_enabled': true,
    });
    expect(item.pushEnabled, false);
    expect(item.inAppEnabled, true);
  });
  test('tap payload accepts existing numeric and UUID IDs only', () {
    expect(TourNotification.payloadId({'notification_id': '42'}), '42');
    expect(
      TourNotification.payloadId({
        'notification_id': '00000000-0000-0000-0000-000000000001',
      }),
      isNotNull,
    );
    for (final value in [
      null,
      42,
      'https://evil.example',
      '../booking',
      '42 or true',
    ]) {
      expect(TourNotification.payloadId({'notification_id': value}), isNull);
    }
    expect(TourNotification.payloadId({'booking_id': '42'}), isNull);
  });
  test('history preserves read state and explicit foreground eligibility', () {
    final item = TourNotification.fromMap({
      'id': 42,
      'title': 'Driver Arrived',
      'body': '1 of 2 drivers has arrived.',
      'type': 'driver_arrived',
      'created_at': '2026-09-24T01:00:00Z',
      'is_read': false,
      'push_enabled': false,
    });
    expect(item.id, '42');
    expect(item.isRead, false);
    expect(item.pushEnabled, false);
    expect(item.body, contains('1 of 2'));
  });
}
