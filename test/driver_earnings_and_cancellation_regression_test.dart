import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  late String migration;
  late String earnings;
  late String details;
  late String tracking;
  late String touristTracking;

  setUpAll(() {
    migration = source(
      'supabase/migrations/20261009140000_completed_driver_earnings_and_test_tracking.sql',
    );
    earnings = source('lib/screens/driver/driver_earnings_screen.dart');
    details = source(
      'lib/screens/driver/driver_package_booking_details_screen.dart',
    );
    tracking = source('lib/screens/driver/driver_package_tracking_screen.dart');
    touristTracking = source(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    );
  });

  test('completed earning is authoritative and exception-aware', () {
    expect(migration, contains('recompute_booking_driver_earnings'));
    expect(migration, contains("earning_status = case"));
    expect(migration, contains("then 'completed'"));
    expect(migration, contains("then 'disputed'"));
    expect(migration, contains("then 'refund_pending'"));
    expect(migration, contains("then 'refunded'"));
    expect(migration, contains("when pr.status = 'failed' then 'failed'"));
    expect(migration, contains('satisfied_by_payment_record_id'));
  });

  test('earnings history is specific, tappable, and export is compact', () {
    expect(earnings, contains('Export Earnings PDF'));
    expect(earnings, contains('Payment Details'));
    expect(earnings, contains('allocation.packageName'));
    expect(earnings, contains('allocation.touristDisplayName'));
    expect(earnings, contains('allocation.bookingReference'));
    expect(earnings, contains('allocation.transactionReference'));
    expect(earnings, contains('+ ₱'));
    expect(earnings, contains('SUCCESSFUL'));
  });

  test('tourist tracking hides internal payout transport wording', () {
    expect(touristTracking, isNot(contains('Driver Payout Pending')));
    expect(touristTracking, isNot(contains('Driver Payout Eligible')));
    expect(touristTracking, contains('Tour Payment Settled'));
  });

  test(
    'booking details and navigation redirect immediately on cancellation',
    () {
      for (final screen in [details, tracking]) {
        expect(screen, contains('PostgresChangeEvent.all'));
        expect(screen, contains('package_bookings'));
        expect(screen, contains('package_activities'));
        expect(screen, contains('DriverPackageJobsScreen'));
        expect(screen, contains('pushAndRemoveUntil'));
      }
      expect(details, contains('_cancellationChannel?.unsubscribe()'));
      expect(tracking, contains('_gpsSub?.cancel()'));
      expect(tracking, contains('_liveMarkerPositions.clear()'));
    },
  );
}
