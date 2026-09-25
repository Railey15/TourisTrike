import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/models/convoy_state.dart';
import 'package:touristrike/core/models/tour_tracking_status.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

void main() {
  test(
    'stream sends GPS evidence to backend without choosing a target stop',
    () async {
      final at = DateTime.utc(2026, 9, 25, 12);
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(
            request.url.path,
            '/rest/v1/rpc/observe_driver_journey_location',
          );
          expect(jsonDecode(request.body), {
            'p_booking_id': 'booking',
            'p_latitude': 15.0,
            'p_longitude': 121.0,
            'p_accuracy_meters': 12.0,
            'p_speed_mps': 1.0,
            'p_sampled_at': at.toIso8601String(),
          });
          return http.Response(
            jsonEncode({
              'changed': true,
              'phase': 'next_stop',
              'current_stop_index': 1,
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final result = TourTrackingStatus(
        await TourisTrikeRepository(
          client: client,
        ).observeDriverJourneyLocation(
          bookingId: 'booking',
          latitude: 15,
          longitude: 121,
          accuracyMeters: 12,
          speedMps: 1,
          sampledAt: at,
        ),
      );
      expect(result.changed, isTrue);
      expect(result.label, contains('Next Stop'));
      await client.dispose();
    },
  );

  test(
    'restart reads server stage/index instead of guessing from planned time',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/get_tour_tracking_status');
          expect(jsonDecode(request.body), {'p_booking_id': 'booking'});
          return http.Response(
            jsonEncode({
              'journey_state': 'at_stop',
              'current_stop_index': 2,
              'phase': 'stop_in_progress',
              'interrupted_at': '2026-09-24T12:00:00Z',
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final result = await TourisTrikeRepository(
        client: client,
      ).fetchTourTrackingStatus('booking');
      expect(result['journey_state'], 'at_stop');
      expect(result['current_stop_index'], 2);
      expect(TourTrackingStatus(result).label, contains('interrupted'));
      await client.dispose();
    },
  );

  test(
    'manual recovery binds audit reason to the displayed stage and index',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/recover_driver_journey');
          expect(jsonDecode(request.body), {
            'p_booking_id': 'booking',
            'p_expected_state': 'at_stop',
            'p_stop_index': 2,
            'p_reason': 'GPS unavailable under roof',
          });
          return http.Response(
            '{"no_op":true}',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      expect(
        await TourisTrikeRepository(client: client).recoverDriverJourney(
          bookingId: 'booking',
          expectedState: ConvoyJourneyState.atStop,
          stopIndex: 2,
          reason: 'GPS unavailable under roof',
        ),
        {'no_op': true},
      );
      await client.dispose();
    },
  );

  test(
    'interrupted tour is recoverable but excluded from normal Active count',
    () {
      final activity = packageActivityFromPersistedBooking(
        {
          'id': 'booking',
          'status': 'ongoing',
          'booking_status': 'on_tour',
          'tracking_interrupted_at': '2026-09-24T12:00:00Z',
          'package_activities': {'id': 'activity', 'tour_status': 'at_spot'},
        },
        bookingDriver: {'status': 'accepted', 'journey_state': 'at_stop'},
      );
      expect(activity.lifecycleStatus, 'interrupted');
      expect(activity.isActiveLifecycle, isFalse);
      expect(activity.id, 'activity');
      expect(activity.driverJourneyState, 'at_stop');
    },
  );

  test(
    'overdue time alone never changes lifecycle to Completed or Interrupted',
    () {
      final activity = packageActivityFromPersistedBooking(
        {
          'id': 'booking',
          'status': 'ongoing',
          'estimated_end_at': '2020-01-01T00:00:00Z',
        },
        bookingDriver: {
          'status': 'accepted',
          'journey_state': 'en_route_dropoff',
        },
      );
      expect(activity.lifecycleStatus, 'ongoing');
    },
  );

  test('terminal state wins over historical interruption metadata', () {
    final activity = packageActivityFromPersistedBooking({
      'id': 'booking',
      'status': 'completed',
      'tracking_interrupted_at': '2026-09-24T12:00:00Z',
    });
    expect(activity.lifecycleStatus, 'completed');
  });

  test('automatic phases explain verification and payment waits', () {
    expect(
      const TourTrackingStatus({'phase': 'detecting_arrival'}).label,
      contains('Detecting Arrival'),
    );
    expect(
      const TourTrackingStatus({'phase': 'detecting_departure'}).label,
      contains('Detecting Departure'),
    );
    expect(
      const TourTrackingStatus({
        'phase': 'waiting_for_convoy_or_payment',
      }).label,
      contains('payment'),
    );
    expect(
      const TourTrackingStatus({'phase': 'gps_interrupted'}).label,
      contains('accurate fix'),
    );
    expect(
      const TourTrackingStatus({'phase': 'completion_pending'}).label,
      contains('payment review'),
    );
  });
}
