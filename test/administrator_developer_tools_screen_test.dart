import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      find.text('Authorized override: scheduled start only'),
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
    expect(find.textContaining('RPC unavailable'), findsOneWidget);

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
    await tester.pumpWidget(
      testHarness(
        AdministratorDeveloperToolsScreen(
          loadData: (query) async => AdministratorDeveloperToolsData(
            overview: const AdministratorDeveloperTestingOverview(
              enabled: true,
              eligibleBookings: 1,
              activeSessions: 1,
              upcomingBookings: 1,
              expiringSoon: 1,
            ),
            bookings: [active],
            totalCount: 1,
            query: query,
          ),
          reset: (_) async => reset = true,
          deactivate: (_) async => deactivated = true,
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
      find.text('Authorized override: scheduled start only'),
      findsOneWidget,
    );
    expect(find.text('Early start regression test'), findsOneWidget);

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
  });
}
