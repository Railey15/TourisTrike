import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/main_tenant/layouts/main_tenant_shell.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_models.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_nav.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';

const _viewports = <Size>[
  Size(360, 800),
  Size(390, 844),
  Size(412, 915),
  Size(768, 1024),
  Size(820, 1180),
  Size(1024, 768),
  Size(1280, 720),
  Size(1366, 600),
  Size(1366, 768),
  Size(1440, 900),
  Size(1536, 864),
  Size(1920, 1080),
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

  testWidgets('provincial portal shell has no overflow across web viewports', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final viewport in _viewports) {
      tester.view.physicalSize = viewport;
      await tester.pumpWidget(
        MaterialApp(
          home: MainTenantPortalScreen(
            profileOverride: const MainTenantProfile(
              id: 'responsive-admin',
              role: 'main_tenant',
              fullName:
                  'A Very Long Provincial Tourism Administrator Display Name',
              firstName: 'A Very Long Provincial Tourism',
              lastName: 'Administrator Display Name',
              email: 'long.provincial.administrator@example.gov.ph',
              mobile: '',
              city: '',
              province: 'Bulacan',
              profileImageUrl: '',
              raw: <String, dynamic>{},
            ),
            pageBuilder: (destination) =>
                _MainTenantResponsiveProbe(destination: destination),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Provincial portal overflowed at ${viewport.width}x${viewport.height}',
      );
    }
  });

  testWidgets('subtenant portal shell has no overflow across web viewports', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final viewport in _viewports) {
      tester.view.physicalSize = viewport;
      await tester.pumpWidget(
        MaterialApp(
          home: SubTenantPortalScreen(
            pageBuilder: (index) => _SubTenantResponsiveProbe(index: index),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Subtenant portal overflowed at ${viewport.width}x${viewport.height}',
      );
    }
  });

  testWidgets('mobile drawers keep navigation and logout accessible', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 600);

    await tester.pumpWidget(
      MaterialApp(
        home: MainTenantPortalScreen(
          profileOverride: const MainTenantProfile(
            id: 'responsive-admin',
            role: 'main_tenant',
            fullName: 'Responsive Administrator',
            firstName: 'Responsive',
            lastName: 'Administrator',
            email: 'admin@example.com',
            mobile: '',
            city: '',
            province: 'Bulacan',
            profileImageUrl: '',
            raw: <String, dynamic>{},
          ),
          pageBuilder: (destination) =>
              _MainTenantResponsiveProbe(destination: destination),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Logout'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: SubTenantPortalScreen(
          pageBuilder: (index) => _SubTenantResponsiveProbe(index: index),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Logout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MainTenantResponsiveProbe extends StatelessWidget {
  const _MainTenantResponsiveProbe({required this.destination});

  final MainTenantDestination destination;

  @override
  Widget build(BuildContext context) {
    return MainTenantShell(
      current: destination,
      title: 'Provincial Tourism Administration and Operations Dashboard',
      subtitle:
          'A deliberately long subtitle used to verify constrained header text.',
      actions: [
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download consolidated report'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text('Responsive provincial portal content'),
          SizedBox(height: 900),
        ],
      ),
    );
  }
}

class _SubTenantResponsiveProbe extends StatelessWidget {
  const _SubTenantResponsiveProbe({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: index,
      title: 'City and Municipal Tourism Administration Dashboard',
      subtitle:
          'A deliberately long municipality subtitle used for responsive testing.',
      actions: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text('Unsaved changes in municipality profile'),
        ),
        IconButton(
          onPressed: () {},
          tooltip: 'Refresh portal data',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text('Responsive subtenant portal content'),
          SizedBox(height: 900),
        ],
      ),
    );
  }
}
