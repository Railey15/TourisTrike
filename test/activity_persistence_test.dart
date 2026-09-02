import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';

void main() {
  group('Activity persistence mapping', () {
    test('tourist activity is reconstructed from package_bookings', () {
      final activity = packageActivityFromPersistedBooking({
        'id': 'booking-1',
        'tourist_id': 'tourist-1',
        'package_id': 12,
        'status': 'confirmed',
        'booking_status': 'accepted',
        'total_amount': 7200,
        'tour_packages': {'title': 'Testing', 'city': 'Bustos'},
        'package_activities': {
          'id': 'activity-1',
          'status': 'accepted',
          'tour_status': 'driver_accepted',
          'driver_id': 'driver-b',
        },
      });

      expect(activity.bookingId, 'booking-1');
      expect(activity.bookingRow?['booking_status'], 'accepted');
      expect(activity.packageRow?['title'], 'Testing');
      expect(activity.lifecycleStatus, 'accepted');
      expect(activity.isActiveLifecycle, isTrue);
    });

    test('tourist booking remains visible without a derived activity row', () {
      final activity = packageActivityFromPersistedBooking({
        'id': 'booking-without-activity',
        'tourist_id': 'tourist-1',
        'package_id': 12,
        'status': 'pending',
        'booking_status': 'waiting_for_drivers',
        'total_amount': 1200,
        'tour_packages': {'title': 'Persisted Booking'},
      });

      expect(activity.bookingId, 'booking-without-activity');
      expect(activity.packageRow?['title'], 'Persisted Booking');
      expect(activity.lifecycleStatus, 'pending');
    });

    test('accepted convoy membership is active for every driver', () {
      final activity = packageActivityFromPersistedBooking(
        {
          'id': 'booking-1',
          'tourist_id': 'tourist-1',
          'package_id': 12,
          'status': 'pending',
          'booking_status': 'waiting_for_drivers',
          'package_activities': {
            'id': 'activity-1',
            'status': 'pending',
            'driver_id': 'driver-b',
          },
        },
        bookingDriver: {
          'driver_id': 'driver-a',
          'status': 'accepted',
          'journey_state': 'assigned',
        },
        effectiveDriverId: 'driver-a',
      );

      expect(activity.driverId, 'driver-a');
      expect(activity.bookingDriverStatus, 'accepted');
      expect(activity.lifecycleStatus, 'accepted');
      expect(activity.isActiveLifecycle, isTrue);
    });

    test('completed membership is historical and strips live coordinates', () {
      final activity = packageActivityFromPersistedBooking(
        {
          'id': 'booking-1',
          'tourist_id': 'tourist-1',
          'status': 'confirmed',
          'booking_status': 'on_tour',
          'package_activities': {
            'id': 'activity-1',
            'status': 'ongoing',
            'tour_status': 'on_tour',
            'driver_latitude': 14.9,
            'driver_longitude': 120.9,
            'driver_last_seen': '2026-08-29T10:00:00Z',
          },
        },
        bookingDriver: {'status': 'completed', 'journey_state': 'completed'},
        effectiveDriverId: 'driver-a',
      );

      expect(activity.lifecycleStatus, 'assignment_completed');
      expect(activity.isActiveLifecycle, isFalse);
      expect(activity.driverLatitude, isNull);
      expect(activity.driverLongitude, isNull);
      expect(activity.driverLastSeen, isNull);
    });
  });

  test('participant RLS keeps accepted and completed convoy history visible', () {
    final sql = File(
      'supabase/migrations/20260829000000_activity_participant_history_rls.sql',
    ).readAsStringSync();

    expect(sql, contains("bd.status in ('accepted', 'completed')"));
    expect(sql, isNot(contains('using (true)')));
  });
}
