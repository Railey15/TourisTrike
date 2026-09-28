import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_models.dart';
import 'package:touristrike/screens/main_tenant/layouts/main_tenant_shell.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_nav.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('admin tabs initialize lazily and preserve their state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final destinations = MainTenantPortalScreen.destinations;
    final initializationCounts = <MainTenantDestination, int>{};

    await tester.pumpWidget(
      MaterialApp(
        home: MainTenantPortalScreen(
          profileOverride: const MainTenantProfile(
            id: 'admin-test-id',
            role: 'main_tenant',
            fullName: 'Test Administrator',
            firstName: 'Test',
            lastName: 'Administrator',
            email: 'admin@example.com',
            mobile: '',
            city: '',
            province: 'Bulacan',
            profileImageUrl: '',
            raw: <String, dynamic>{},
          ),
          pageBuilder: (destination) => _AdminProbeTab(
            destination: destination,
            onInitialize: () {
              initializationCounts[destination] =
                  (initializationCounts[destination] ?? 0) + 1;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(initializationCounts[destinations.first], 1);
    expect(initializationCounts.length, 1);
    expect(find.byKey(const ValueKey('admin-probe-0')), findsOneWidget);

    for (var index = 1; index < destinations.length; index++) {
      await tester.tap(find.byKey(ValueKey<String>('admin-next-${index - 1}')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(ValueKey('admin-probe-$index')), findsOneWidget);
      expect(initializationCounts[destinations[index]], 1);
    }

    await tester.tap(
      find.byKey(ValueKey<String>('admin-next-${destinations.length - 1}')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('admin-probe-0')), findsOneWidget);
    expect(initializationCounts.length, destinations.length);
    expect(initializationCounts.values, everyElement(1));
    expect(find.byType(MainTenantPortalScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await Supabase.instance.dispose();
    await tester.pump(const Duration(milliseconds: 20));
  });
}

class _AdminProbeTab extends StatefulWidget {
  const _AdminProbeTab({required this.destination, required this.onInitialize});

  final MainTenantDestination destination;
  final VoidCallback onInitialize;

  @override
  State<_AdminProbeTab> createState() => _AdminProbeTabState();
}

class _AdminProbeTabState extends State<_AdminProbeTab> {
  @override
  void initState() {
    super.initState();
    widget.onInitialize();
  }

  @override
  Widget build(BuildContext context) {
    final destinations = MainTenantPortalScreen.destinations;
    final index = destinations.indexOf(widget.destination);
    final nextDestination = destinations[(index + 1) % destinations.length];

    return MainTenantShell(
      current: widget.destination,
      title: 'Admin probe $index',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Admin probe $index', key: ValueKey('admin-probe-$index')),
            FilledButton(
              key: ValueKey<String>('admin-next-$index'),
              onPressed: () => MainTenantShell.navigateTo(
                context,
                nextDestination,
                current: widget.destination,
              ),
              child: const Text('Next admin tab'),
            ),
          ],
        ),
      ),
    );
  }
}
