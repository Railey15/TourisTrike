import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
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

    final destinations = ProvincialAdminPortalScreen.destinations;
    final initializationCounts = <ProvincialAdminDestination, int>{};

    await tester.pumpWidget(
      MaterialApp(
        home: ProvincialAdminPortalScreen(
          profileOverride: const ProvincialAdminProfile(
            id: 'admin-test-id',
            role: 'admin',
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
    expect(find.text('Admin probe 0'), findsOneWidget);

    for (var index = 1; index < destinations.length; index++) {
      await tester.tap(find.byKey(ValueKey<String>('admin-next-${index - 1}')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Admin probe $index'), findsOneWidget);
      expect(initializationCounts[destinations[index]], 1);
    }

    await tester.tap(
      find.byKey(ValueKey<String>('admin-next-${destinations.length - 1}')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Admin probe 0'), findsOneWidget);
    expect(initializationCounts.length, destinations.length);
    expect(initializationCounts.values, everyElement(1));
    expect(find.byType(ProvincialAdminPortalScreen), findsOneWidget);
  });
}

class _AdminProbeTab extends StatefulWidget {
  const _AdminProbeTab({required this.destination, required this.onInitialize});

  final ProvincialAdminDestination destination;
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
    final destinations = ProvincialAdminPortalScreen.destinations;
    final index = destinations.indexOf(widget.destination);
    final nextDestination = destinations[(index + 1) % destinations.length];

    return ProvincialAdminShell(
      current: widget.destination,
      title: 'Admin probe $index',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Admin probe $index'),
            FilledButton(
              key: ValueKey<String>('admin-next-$index'),
              onPressed: () => ProvincialAdminShell.navigateTo(
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
