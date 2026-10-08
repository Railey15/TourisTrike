import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  late String migration;
  late String touristTracking;
  late String driverTracking;
  late String repository;

  setUpAll(() {
    migration = source(
      'supabase/migrations/20261009080000_live_tracking_start_gate_driver_withdrawal.sql',
    );
    touristTracking = source(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    );
    driverTracking = source(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    );
    repository = source('lib/core/supabase/touristrike_repository.dart');
  });

  test('server time and scheduled start authorize participant tracking', () {
    expect(migration, contains('can_access_live_tour_tracking'));
    expect(migration, contains('now() >= b.scheduled_start_at'));
    expect(migration, contains("'BEFORE_SCHEDULED_START'"));
    expect(migration, contains("bd.status = 'accepted'"));
    expect(migration, contains('get_live_tour_tracking_eligibility'));
    expect(repository, contains('fetchLiveTourTrackingEligibility'));
  });

  test('both participant screens fail closed and show the scheduled lock', () {
    for (final screen in [touristTracking, driverTracking]) {
      expect(screen, contains('serverAuthorized:'));
      expect(screen, contains('LiveTrackingLockedCard('));
      expect(screen, contains('_syncScheduleGateTimer'));
      expect(screen, contains('refreshLocationsOnUnlock: true'));
    }
  });

  test('live subscriptions and markers do not activate before eligibility', () {
    expect(touristTracking, contains('if (!_canShowLiveTourMap) {'));
    expect(touristTracking, contains('_locationChannel?.unsubscribe()'));
    expect(touristTracking, contains('_touristGpsSub?.cancel()'));
    expect(
      touristTracking,
      contains('if (_canShowLiveTourMap && _touristPosition != null)'),
    );
    expect(driverTracking, contains('_syncDriverLocationSubscriptions'));
    expect(
      driverTracking,
      contains('_participantLocationChannel?.unsubscribe()'),
    );
    expect(
      driverTracking,
      contains('if (_canShowLiveTourMap && _touristLivePosition != null)'),
    );
  });

  test('database policies block premature live location reads and writes', () {
    expect(migration, contains('create policy live_loc_select_active_trip'));
    expect(migration, contains('create policy "live_loc_driver_upsert"'));
    expect(
      migration,
      contains('create policy participant_live_locations_read'),
    );
    expect(
      migration,
      contains('public.can_access_live_tour_tracking(booking_id, auth.uid())'),
    );
    expect(
      migration,
      contains("raise exception 'LIVE_TRACKING_NOT_AVAILABLE'"),
    );
  });

  test(
    'static destination information remains available while map is locked',
    () {
      for (final screen in [touristTracking, driverTracking]) {
        expect(screen, contains("MarkerId('pickup')"));
        expect(screen, contains("MarkerId('dropoff')"));
        expect(screen, contains("MarkerId('spot_\$index')"));
      }
      expect(touristTracking, contains('_LocationsCard('));
      expect(driverTracking, contains('_ModernLocationsCard('));
    },
  );

  test('confirmed payment is not a driver withdrawal guard', () {
    final withdrawal = migration.substring(
      migration.indexOf(
        'create or replace function public.request_driver_withdrawal',
      ),
    );
    expect(withdrawal, isNot(contains('payment_records')));
    expect(withdrawal, isNot(contains('payment_status')));
    expect(withdrawal, contains("'payment_preserved', true"));
    expect(withdrawal, contains("status = 'cancelled'"));
    expect(withdrawal, contains("replacement_status = 'awaiting_replacement'"));
    expect(withdrawal, contains('notify_eligible_replacement_drivers'));
  });

  test('ordinary withdrawal stops at authoritative boarded progression', () {
    expect(migration, contains("'boarded', 'en_route_stop', 'at_stop'"));
    expect(migration, contains("raise exception 'TOUR_ALREADY_STARTED'"));
    expect(driverTracking, contains('assignmentJourneyState:'));
    expect(driverTracking, contains('Withdraw from Tour'));
  });

  test(
    'successful withdrawal clears tracking and removes navigation stack',
    () {
      expect(driverTracking, contains('_liveMarkerPositions.clear()'));
      expect(
        driverTracking,
        contains('_participantLocationChannel?.unsubscribe()'),
      );
      expect(driverTracking, contains('pushAndRemoveUntil'));
      expect(driverTracking, contains('DriverPackageJobsScreen'));
    },
  );

  test(
    'existing replacement allocation and refund lifecycle remains installed',
    () {
      final lifecycle = source(
        'supabase/migrations/20261009000000_paymongo_test_pending_payout_lifecycle.sql',
      );
      expect(lifecycle, contains('reconcile_allocations_after_roster_change'));
      expect(lifecycle, contains('replacement_for_booking_driver_id'));
      expect(lifecycle, contains('process_expired_driver_replacements'));
      expect(lifecycle, contains('create_full_test_refund_requests'));
    },
  );
}
