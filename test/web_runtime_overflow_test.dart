import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/auth/web_portal_landing_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_payment_disputes_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';

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
}

class _RuntimeCaseService extends SubTenantService {
  @override
  Future<List<SubTenantCase>> fetchCases({String? caseId}) async {
    return const <SubTenantCase>[];
  }
}
