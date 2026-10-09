import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/auth/web_portal_landing_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_payment_disputes_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';

const _runtimeViewports = <Size>[
  Size(1920, 1080),
  Size(1600, 900),
  Size(1440, 900),
  Size(1366, 768),
  Size(1280, 720),
  Size(1024, 768),
  Size(939, 1205),
  Size(900, 700),
  Size(768, 1024),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
    );
  });

  tearDownAll(() async {
    await Supabase.instance.dispose();
  });

  testWidgets('landing page renders and scrolls without overflow', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final viewport in _runtimeViewports) {
      tester.view.physicalSize = viewport;
      await tester.pumpWidget(
        const MaterialApp(home: WebPortalLandingScreen()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Landing page overflowed at '
            '${viewport.width}x${viewport.height}',
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    }
  });

  testWidgets('disputes summary cards render without overflow', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    final service = _RuntimeCaseService();

    for (final viewport in _runtimeViewports) {
      tester.view.physicalSize = viewport;
      await tester.pumpWidget(
        MaterialApp(home: SubTenantPaymentDisputesScreen(service: service)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      for (final label in const [
        'Needs Review',
        'Under Review',
        'Closed',
        'Total',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        tester.takeException(),
        isNull,
        reason:
            'Disputes screen overflowed at '
            '${viewport.width}x${viewport.height}',
      );
    }
  });

  testWidgets('municipal complaint renders in unified case workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SubTenantPaymentDisputesScreen(
          service: _RuntimeComplaintCaseService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Driver conduct complaint'), findsOneWidget);
    expect(find.text('Complaint'), findsOneWidget);
    final needsReviewMetric = find.ancestor(
      of: find.text('Needs Review'),
      matching: find.byType(DashboardMetricCard),
    );
    expect(
      find.descendant(of: needsReviewMetric, matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.text('Review Case'), findsOneWidget);
    await tester.ensureVisible(find.text('Review Case'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review Case'));
    await tester.pumpAndSettle();
    expect(find.text('Report / Complaint Details'), findsOneWidget);
    expect(find.text('Municipal Booking History'), findsOneWidget);
    expect(find.text('Supporting Evidence'), findsOneWidget);
    expect(find.text('Admin Actions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RuntimeCaseService extends SubTenantService {
  @override
  Future<List<SubTenantCase>> fetchCases({String? caseId}) async {
    return const <SubTenantCase>[];
  }
}

class _RuntimeComplaintCaseService extends SubTenantService {
  @override
  Future<List<SubTenantCase>> fetchCases({String? caseId}) async {
    return [
      SubTenantCase.fromComplaintMap({
        'id': 'aaaaaaaa-1234-1234-1234-123456789012',
        'booking_id': 'bbbbbbbb-1234-1234-1234-123456789012',
        'municipality': 'Baliwag',
        'province': 'Bulacan',
        'reporter_id': 'tourist-id',
        'reporter_name': 'Tourist Reporter',
        'reported_user_id': 'driver-id',
        'reported_name': 'Driver Reported',
        'reported_role': 'driver',
        'category': 'conduct',
        'description': 'The driver behaved unsafely during the booked tour.',
        'status': 'submitted',
        'booking_status': 'completed',
        'booking_travel_date': '2026-10-01',
        'booking_history': [
          {
            'booking_id': 'cccccccc-1234-1234-1234-123456789012',
            'travel_date': '2026-09-01',
            'booking_status': 'completed',
          },
        ],
        'evidence': const <Map<String, dynamic>>[],
        'events': [
          {
            'action': 'submitted',
            'details': 'Complaint submitted for MTO review',
            'created_at': '2026-10-02T01:00:00Z',
          },
        ],
        'created_at': '2026-10-02T01:00:00Z',
      }),
    ];
  }
}
