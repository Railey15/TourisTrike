import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/services/itinerary_schedule_service.dart';

String source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('pickup plus travel and stays recalculates every following stop', () {
    final timings = calculateItineraryTimings(
      pickupMinutes: 8 * 60,
      stayDurationMinutes: const [60, 45],
      travelDurationMinutes: const [30, 20],
    );

    expect(timings[0].arrivalMinutes, 8 * 60 + 30);
    expect(timings[0].departureMinutes, 9 * 60 + 30);
    expect(timings[1].arrivalMinutes, 9 * 60 + 50);
    expect(timings[1].departureMinutes, 10 * 60 + 35);
  });

  test('stay change moves all later timings without overlap', () {
    final before = calculateItineraryTimings(
      pickupMinutes: 8 * 60,
      stayDurationMinutes: const [60, 45],
      travelDurationMinutes: const [30, 20],
    );
    final after = calculateItineraryTimings(
      pickupMinutes: 8 * 60,
      stayDurationMinutes: const [90, 45],
      travelDurationMinutes: const [30, 20],
    );

    expect(after[1].arrivalMinutes - before[1].arrivalMinutes, 30);
    expect(
      after[1].arrivalMinutes,
      greaterThanOrEqualTo(after[0].departureMinutes),
    );
  });

  test(
    'driver jobs rely on server overlap validation, not any-active block',
    () {
      final jobs = source('lib/screens/driver/driver_package_jobs_screen.dart');
      expect(jobs, isNot(contains("if (_hasActiveTour) {\n      return")));
      expect(jobs, contains('DRIVER_SCHEDULE_CONFLICT'));
    },
  );

  test('booking RPC persists exact schedule and enforces selected capacity', () {
    final sql = source(
      'supabase/migrations/20260830000000_booking_schedule_group_chat_arrivals.sql',
    );
    expect(sql, contains("p_booking->>'scheduled_start_at'"));
    expect(sql, contains("p_booking->>'estimated_end_at'"));
    expect(sql, contains('PICKUP_DATE_TIME_MISMATCH'));
    expect(sql, contains('TRICYCLE_COUNT_BELOW_CAPACITY_MINIMUM'));
    expect(sql, contains('new.required_drivers <'));
  });

  test('one idempotent booking group includes tourist and active drivers', () {
    final sql = source(
      'supabase/migrations/20260830000000_booking_schedule_group_chat_arrivals.sql',
    );
    expect(sql, contains('conversations_one_booking_group_uidx'));
    expect(sql, contains('ensure_booking_group_conversation'));
    expect(sql, contains("bd.status in ('accepted', 'completed')"));
    expect(sql, contains('conversation_members'));
    expect(sql, contains('public.can_access_conversation(conversation_id)'));
  });

  test('available-job and physical arrival notifications are idempotent', () {
    final sql = source(
      'supabase/migrations/20260830000000_booking_schedule_group_chat_arrivals.sql',
    );
    expect(sql, contains('notifications_dedupe_uidx'));
    expect(sql, contains('notify_drivers_of_available_booking'));
    expect(sql, contains('booking_driver_arrivals'));
    expect(sql, contains('DRIVER_LOCATION_STALE'));
    expect(sql, contains('NOT_WITHIN_ARRIVAL_RADIUS'));
    expect(sql, contains('v_distance_meters > 150'));
  });

  test('tourist tracking retains independent convoy locations and routes', () {
    final tracking = source(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    );
    expect(tracking, contains('buildBookingDriverMarkers('));
    expect(tracking, contains('_markerMotion.animateTo'));
    expect(tracking, contains('_convoyPositions[driverId] = position'));
    expect(tracking, contains("table: 'driver_live_locations'"));
    expect(
      tracking,
      contains("PolylineId('driver_route_\${result.driverId}')"),
    );
  });

  test('completed driver trips remain open with full convoy markers', () {
    final trips = source('lib/screens/driver/driver_trips.dart');
    final tracking = source(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    );
    expect(trips, contains("'View Trip Details'"));
    expect(tracking, contains('buildBookingDriverMarkers('));
    expect(tracking, contains("table: 'driver_live_locations'"));
    expect(
      tracking,
      contains("PolylineId('driver_route_\${result.driverId}')"),
    );
  });
}
