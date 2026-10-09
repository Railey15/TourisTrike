import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/driver/driver_package_tracking_screen.dart';

String source(String path) => File(path).readAsStringSync();

String section(String value, String start, String end) {
  final startIndex = value.indexOf(start);
  final endIndex = value.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing $end');
  return value.substring(startIndex, endIndex);
}

void main() {
  test('tracking route keeps live and history modes explicit', () {
    const live = DriverPackageTrackingScreen(activityId: 'activity-live');
    const history = DriverPackageTrackingScreen(
      activityId: 'activity-complete',
      bookingId: 'booking-complete',
      historyMode: true,
    );

    expect(live.historyMode, isFalse);
    expect(history.historyMode, isTrue);
    expect(history.bookingId, 'booking-complete');
  });

  test('completed Activity navigation is booking-scoped and read-only', () {
    final trips = source('lib/screens/driver/driver_trips.dart');

    expect(trips, contains('bookingId: activity.bookingId'));
    expect(
      trips,
      contains("historyMode: activity.lifecycleStatus == 'completed'"),
    );
  });

  test(
    'history loader reads persisted data without starting live services',
    () {
      final tracking = source(
        'lib/screens/driver/driver_package_tracking_screen.dart',
      );
      final loader = section(
        tracking,
        'Future<void> _loadHistory()',
        '// CONVOY SYNC',
      );

      expect(loader, contains('fetchMyDriverActivityForBooking(bookingId)'));
      expect(loader, contains('fetchMyBookingDriverAssignment(bookingId)'));
      expect(loader, contains('fetchPackageBookingDetails(bookingId)'));
      expect(loader, contains('fetchBookingItinerary(bookingId)'));
      expect(loader, contains('fetchPaymentRecordsFor'));
      expect(loader, contains('fetchPaymentAllocationsForBooking'));
      expect(loader, isNot(contains('fetchLiveTourTrackingEligibility')));
      expect(loader, isNot(contains('fetchTourTrackingStatus')));
      expect(loader, isNot(contains('ensureBookingItinerary')));
      expect(loader, isNot(contains('_subscribeRealtime')));
      expect(loader, isNot(contains('_startGpsStreaming')));
      expect(loader, isNot(contains('_fetchCurrentRoute')));
    },
  );

  test('history UI omits progression and communication actions', () {
    final tracking = source(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    );
    final historyUi = section(
      tracking,
      'Widget _buildHistoryContent()',
      'Widget _buildCancelledContent()',
    );

    expect(historyUi, contains("subtitle: 'Read-only tour history'"));
    expect(historyUi, contains('_HistoricalRouteSummaryCard'));
    expect(historyUi, contains('_ModernSpotProgressCard'));
    expect(historyUi, contains('showContactActions: false'));
    expect(historyUi, contains('_HistoricalPaymentSummaryCard'));
    expect(historyUi, isNot(contains('_PersistentDriverActionBar')));
    expect(historyUi, isNot(contains('_currentPrimaryAction')));
    expect(historyUi, isNot(contains('_NavigationMapCard')));
  });

  test('history query and SQL keep completed access driver-scoped', () {
    final repository = source('lib/core/supabase/touristrike_repository.dart');
    final query = section(
      repository,
      'Future<PackageActivity?> fetchMyDriverActivityForBooking(',
      '//',
    );
    expect(query, contains(".eq('booking_id', normalizedBookingId)"));
    expect(query, contains(".eq('driver_id', driverId)"));
    expect(
      query,
      contains(".inFilter('status', const ['accepted', 'completed'])"),
    );

    final migration = source(
      'supabase/migrations/20261009150000_completed_driver_tour_history.sql',
    );
    expect(migration, contains('bd.driver_id = v_actor'));
    expect(migration, contains("bd.status in ('accepted', 'completed')"));
    expect(migration, contains("then 'BOOKING_NOT_TRACKABLE'"));
    expect(
      migration,
      contains(
        'v_can_access := public.can_access_live_tour_tracking(p_booking_id, v_actor)',
      ),
    );
  });
}
