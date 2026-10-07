import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_package_form_screen.dart';

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

  testWidgets('root back opens the existing Packages portal tab', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    await tester.pumpWidget(
      const MaterialApp(home: SubTenantPackageFormScreen()),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SubTenantPackageFormScreen), findsNothing);
    expect(find.byType(SubTenantPortalScreen), findsOneWidget);
  });

  testWidgets('pushed package form back pops to its Packages caller', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    await tester.pumpWidget(const MaterialApp(home: _PackagesCaller()));

    await tester.tap(find.text('Open package builder'));
    await tester.pumpAndSettle();
    expect(find.byType(SubTenantPackageFormScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(SubTenantPackageFormScreen), findsNothing);
    expect(find.text('Packages caller'), findsOneWidget);
  });
}

Future<void> _setDesktopSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _PackagesCaller extends StatelessWidget {
  const _PackagesCaller();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Packages caller'),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SubTenantPackageFormScreen(),
                ),
              ),
              child: const Text('Open package builder'),
            ),
          ],
        ),
      ),
    );
  }
}
