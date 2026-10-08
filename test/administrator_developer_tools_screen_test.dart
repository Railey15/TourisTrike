import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/administrator/administrator_booking_tour_testing.dart';
import 'package:touristrike/screens/administrator/administrator_developer_tools_screen.dart';
import 'package:touristrike/screens/administrator/administrator_models.dart';
import 'package:touristrike/screens/administrator/widgets/system_admin_shared.dart';

void main() {
  Widget testHarness(Widget child) => MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: child),
  );

  final booking = AdministratorDeveloperTestBooking(
    id: '00000000-0000-0000-0000-000000000010',
    reference: '#00000000',
    touristId: 'tourist-id',
    touristName: 'Test Tourist',
    packageId: 1,
    packageName: 'Malolos Heritage Tour',
    municipality: 'Malolos',
    scheduledStartAt: DateTime.utc(2026, 10, 1, 8),
    estimatedEndAt: DateTime.utc(2026, 10, 1, 12),
    bookingStatus: 'confirmed',
    tourStatus: 'driver_accepted',
    drivers: const [
      AdministratorDeveloperTestDriver(id: 'driver-id', name: 'Test Driver'),
    ],
    requiredDrivers: 1,
    assignedDriverCount: 1,
    downpaymentReady: true,
    remainingPaymentReady: false,
    validTourist: true,
    driversReady: true,
    bookingStateValid: true,
    eligible: true,
    eligibilityReason: '',
    testSessionActive: false,
    bypassScheduledStart: false,
  );

  AdministratorDeveloperToolsData dataFor(
    AdministratorDeveloperToolsQuery query, {
    bool enabled = true,
  }) => AdministratorDeveloperToolsData(
    overview: AdministratorDeveloperTestingOverview(
      enabled: enabled,
      eligibleBookings: 1,
      activeSessions: 0,
      upcomingBookings: 1,
      expiringSoon: 0,
    ),
    bookings: [booking],
    totalCount: 1,
    query: query,
  );

  testWidgets('loads lazily and activates an eligible booking session', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var loads = 0;
    AdministratorDeveloperTestActivation? submitted;

    await tester.pumpWidget(
      testHarness(
        AdministratorDeveloperToolsScreen(
          loadData: (query) async {
            loads++;
            return dataFor(query);
          },
          setEnabled: (_) async {},
          activate: (_, activation) async => submitted = activation,
          deactivate: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(loads, 1);
    expect(find.text('Global developer testing'), findsOneWidget);
    expect(find.text('Malolos Heritage Tour'), findsWidgets);
    expect(find.text('Downpayment ready'), findsOneWidget);
    expect(find.text('Balance pending'), findsOneWidget);

    final bookingAction = find.byKey(Key('developer-booking-${booking.id}'));
    await tester.ensureVisible(bookingAction);
    await tester.tap(bookingAction);
    await tester.pumpAndSettle();
    expect(
      find.text('Authorized: booking-scoped Developer Tools'),
      findsNothing,
    );
    expect(find.byKey(const Key('developer-session-activate')), findsOneWidget);

    await tester.tap(find.byKey(const Key('developer-session-activate')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('does not alter booking status'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('developer-session-reason')),
      'Verify an early pickup departure safely',
    );
    await tester.pump();
    final confirmActivation = find.byKey(
      const Key('developer-session-confirm-activate'),
    );
    expect(tester.widget<FilledButton>(confirmActivation).onPressed, isNotNull);
    await tester.ensureVisible(confirmActivation);
    await tester.tap(confirmActivation);
    await tester.pumpAndSettle();

    expect(submitted?.reason, 'Verify an early pickup departure safely');
    expect(submitted!.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
    expect(loads, 2);
  });

  testWidgets('global disable requires confirmation and preserves UI context', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    bool? toggled;

    await tester.pumpWidget(
      testHarness(
        AdministratorDeveloperToolsScreen(
          loadData: (query) async => dataFor(query),
          setEnabled: (enabled) async => toggled = enabled,
          activate: (_, _) async {},
          deactivate: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Tourist · Malolos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('developer-testing-global-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Disable developer testing?'), findsOneWidget);
    expect(
      find.textContaining('sessions immediately become ineffective'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('developer-testing-confirm-toggle')));
    await tester.pumpAndSettle();
    expect(toggled, false);
  });

  test('administrator navigation exposes Developer Tools', () {
    expect(
      AdministratorSection.values,
      contains(AdministratorSection.developerTools),
    );
    expect(
      administratorSectionLabel(AdministratorSection.developerTools),
      'Developer Tools',
    );
  });

  testWidgets('renders loading, error, and empty states', (tester) async {
    final pending = Completer<AdministratorDeveloperToolsData>();
    await tester.pumpWidget(
      testHarness(
        AdministratorDeveloperToolsScreen(loadData: (_) => pending.future),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      testHarness(
        AdministratorDeveloperToolsScreen(
          key: const ValueKey('error'),
          loadData: (_) async => throw StateError('RPC unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to load System Administrator data'),
      findsOneWidget,
    );
    expect(find.textContaining('RPC unavailable'), findsNothing);
    expect(find.text('Please refresh and try again.'), findsOneWidget);

    await tester.pumpWidget(
      testHarness(
        AdministratorDeveloperToolsScreen(
          key: const ValueKey('empty'),
          loadData: (query) async => AdministratorDeveloperToolsData(
            overview: const AdministratorDeveloperTestingOverview(
              enabled: false,
              eligibleBookings: 0,
              activeSessions: 0,
              upcomingBookings: 0,
              expiringSoon: 0,
            ),
            bookings: const [],
            totalCount: 0,
            query: query,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No bookings found'), findsOneWidget);
  });

  testWidgets('booking and test filters reload with server-side values', (
    tester,
  ) async {
    final queries = <AdministratorDeveloperToolsQuery>[];
    await tester.pumpWidget(
      testHarness(
        AdministratorDeveloperToolsScreen(
          loadData: (query) async {
            queries.add(query);
            return dataFor(query);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bookingFilter = find.text('All bookings');
    await tester.ensureVisible(bookingFilter);
    await tester.tap(bookingFilter);
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsNothing);
    expect(find.text('Cancelled'), findsNothing);
    await tester.tap(find.text('Upcoming').last);
    await tester.pumpAndSettle();
    expect(
      queries.last.bookingFilter,
      AdministratorDeveloperBookingFilter.upcoming,
    );

    final testFilter = find.text('All test states');
    await tester.ensureVisible(testFilter);
    await tester.tap(testFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test active').last);
    await tester.pumpAndSettle();
    expect(queries.last.testFilter, AdministratorDeveloperTestFilter.active);
  });

  testWidgets('resets and deactivates an active test session', (tester) async {
    final active = AdministratorDeveloperTestBooking(
      id: booking.id,
      reference: booking.reference,
      touristId: booking.touristId,
      touristName: booking.touristName,
      packageId: booking.packageId,
      packageName: booking.packageName,
      municipality: booking.municipality,
      bookingStatus: booking.bookingStatus,
      tourStatus: booking.tourStatus,
      drivers: booking.drivers,
      requiredDrivers: booking.requiredDrivers,
      assignedDriverCount: booking.assignedDriverCount,
      downpaymentReady: booking.downpaymentReady,
      remainingPaymentReady: booking.remainingPaymentReady,
      validTourist: true,
      driversReady: true,
      bookingStateValid: true,
      eligible: true,
      eligibilityReason: '',
      testSessionId: 'session-id',
      testSessionActive: true,
      activatedByName: 'System Admin',
      activatedAt: DateTime.utc(2026, 10, 1, 1),
      expiresAt: DateTime.utc(2026, 10, 1, 4),
      reason: 'Early start regression test',
      bypassScheduledStart: true,
    );
    var reset = false;
    var deactivated = false;
    var deleted = false;
    var loads = 0;
    await tester.pumpWidget(
      testHarness(
        AdministratorDeveloperToolsScreen(
          loadData: (query) async {
            loads++;
            return AdministratorDeveloperToolsData(
            overview: const AdministratorDeveloperTestingOverview(
              enabled: true,
              eligibleBookings: 1,
              activeSessions: 1,
              upcomingBookings: 1,
              expiringSoon: 1,
            ),
            bookings: deleted ? [] : [active],
            totalCount: deleted ? 0 : 1,
            query: query,
            );
          },
          reset: (_) async => reset = true,
          deactivate: (_) async => deactivated = true,
          deleteBooking: (_) async => deleted = true,
          bookingTourGateway: _BookingTourGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bookingCard = find.byKey(Key('developer-booking-${booking.id}'));
    await tester.ensureVisible(bookingCard);
    await tester.tap(bookingCard);
    await tester.pumpAndSettle();
    expect(find.text('Active test session'), findsOneWidget);
    expect(
      find.text('Authorized: booking-scoped Developer Tools'),
      findsOneWidget,
    );
    expect(find.text('Early start regression test'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('developer-booking-tour-testing')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Booking / Tour Testing'), findsWidgets);
    expect(find.text('DEVELOPER / TESTING TOOLS'), findsOneWidget);
    expect(find.text('Current Tour State'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(bookingCard);
    await tester.tap(bookingCard);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('developer-session-reset')));
    await tester.pumpAndSettle();
    expect(find.text('Reset test trip?'), findsOneWidget);
    expect(
      find.textContaining('payments, allocations, payouts, disputes'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('developer-session-confirm-reset')));
    await tester.pumpAndSettle();
    expect(reset, isTrue);

    await tester.ensureVisible(bookingCard);
    await tester.tap(bookingCard);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('developer-session-deactivate')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('developer-session-confirm-deactivate')),
    );
    await tester.pumpAndSettle();
    expect(deactivated, isTrue);

    final deleteAction = find.byKey(Key('developer-booking-delete-${booking.id}'));
    await tester.ensureVisible(deleteAction);
    expect(find.byTooltip('Delete booking'), findsOneWidget);
    await tester.tap(deleteAction);
    await tester.pumpAndSettle();
    expect(find.text('Delete booking?'), findsOneWidget);
    expect(find.textContaining('This action cannot be undone'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(deleted, isFalse);

    await tester.tap(deleteAction);
    await tester.pumpAndSettle();
    final beforeDeleteLoads = loads;
    await tester.tap(find.byKey(const Key('developer-booking-confirm-delete')));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(loads, beforeDeleteLoads + 1);
    expect(find.text('No bookings found'), findsOneWidget);
  });

  testWidgets('inactive row exposes adjacent trash action with guarded progress', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pending = Completer<void>();
    var attempts = 0;
    var loads = 0;
    var deleted = false;
    await tester.pumpWidget(testHarness(AdministratorDeveloperToolsScreen(
      loadData: (query) async {
        loads++;
        if (!deleted) return dataFor(query);
        return AdministratorDeveloperToolsData(
          overview: const AdministratorDeveloperTestingOverview(
            enabled: true,
            eligibleBookings: 0,
            activeSessions: 0,
            upcomingBookings: 0,
            expiringSoon: 0,
          ),
          bookings: const [],
          totalCount: 0,
          query: query,
        );
      },
      deleteBooking: (_) async {
        attempts++;
        if (attempts == 1) {
          throw StateError(
            'PostgrestException(message: BOOKING_HAS_LIVE_PROVIDER_PAYMENT, code: P0001)',
          );
        }
        await pending.future;
        deleted = true;
      },
    )));
    await tester.pumpAndSettle();

    final open = find.byKey(Key('developer-booking-${booking.id}'));
    final trash = find.byKey(Key('developer-booking-delete-${booking.id}'));
    expect(open, findsOneWidget);
    expect(trash, findsOneWidget);
    expect(find.byTooltip('Delete booking'), findsOneWidget);
    await tester.ensureVisible(trash);
    await tester.tap(trash);
    await tester.pumpAndSettle();
    expect(find.text('Delete booking?'), findsOneWidget);
    expect(attempts, 0);

    final confirm = find.byKey(const Key('developer-booking-confirm-delete'));
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.text('Unable to delete booking'), findsOneWidget);
    expect(find.text('This booking contains a live provider payment that must be retained.'), findsOneWidget);
    expect(find.textContaining('PostgrestException'), findsNothing);
    expect(find.textContaining('P0001'), findsNothing);

    await tester.tap(confirm);
    await tester.pump();
    expect(attempts, 2);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(find.text('Deleting…'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(attempts, 2);
    expect(loads, 2);
    expect(find.text('No bookings found'), findsOneWidget);
    expect(find.text('Booking deleted successfully.'), findsOneWidget);
  });
}

class _BookingTourGateway implements BookingDeveloperToolsGateway {
  Map<String, dynamic> get _state => {
    'booking_id': '00000000-0000-0000-0000-000000000010',
    'controls_enabled': true,
    'booking_status': 'on_tour',
    'tour_status': 'at_spot',
    'journey_state': 'at_stop',
    'current_stop_index': 0,
    'current_stop_name': 'Cafe Supremo',
    'arrival_status': 'arrived',
    'departure_status': 'pending',
    'included_minutes': 60,
    'elapsed_minutes': 20,
    'effective_deadline': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 40))
        .toIso8601String(),
    'server_time': DateTime.now().toUtc().toIso8601String(),
    'remaining_minutes': 40,
    'overtime_minutes': 0,
    'interval_minutes': 15,
    'configured_rate': 30,
    'additional_fee': 0,
    'booking_total': 1200,
    'override_active': false,
    'recent_test_actions': const <Map<String, dynamic>>[],
  };

  @override
  Future<Map<String, dynamic>> load(dynamic bookingId) async => _state;

  @override
  Future<Map<String, dynamic>> applyTiming({
    required dynamic bookingId,
    required String mode,
    required int minutes,
    double? customRate,
  }) async => _state;

  @override
  Future<Map<String, dynamic>> progress({
    required dynamic bookingId,
    required String action,
  }) async => _state;

  @override
  Future<Map<String, dynamic>> resetTiming({
    required dynamic bookingId,
    required String scope,
  }) async => _state;
}
