import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('tab navigation is lazy and preserves initialized tab state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final initializationCounts = List<int>.filled(8, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: SubTenantPortalScreen(
          pageBuilder: (index) => _ProbeTab(
            index: index,
            onInitialize: () => initializationCounts[index]++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(initializationCounts, <int>[1, 0, 0, 0, 0, 0, 0, 0]);
    expect(find.text('Probe tab 0'), findsOneWidget);
    expect(find.text('TourisTrike Admin'), findsOneWidget);

    for (var expectedIndex = 1; expectedIndex < 8; expectedIndex++) {
      await tester.tap(
        find.byKey(ValueKey<String>('next-${expectedIndex - 1}')),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Probe tab $expectedIndex'), findsOneWidget);
      expect(initializationCounts[expectedIndex], 1);
      expect(find.text('TourisTrike Admin'), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey<String>('next-7')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Probe tab 0'), findsOneWidget);
    expect(initializationCounts, List<int>.filled(8, 1));
    expect(find.byType(SubTenantPortalScreen), findsOneWidget);
  });
}

class _ProbeTab extends StatefulWidget {
  const _ProbeTab({required this.index, required this.onInitialize});

  final int index;
  final VoidCallback onInitialize;

  @override
  State<_ProbeTab> createState() => _ProbeTabState();
}

class _ProbeTabState extends State<_ProbeTab> {
  @override
  void initState() {
    super.initState();
    widget.onInitialize();
  }

  @override
  Widget build(BuildContext context) {
    final nextIndex = (widget.index + 1) % 8;

    return SubTenantAdminShell(
      currentIndex: widget.index,
      title: 'Probe ${widget.index}',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Probe tab ${widget.index}'),
            FilledButton(
              key: ValueKey<String>('next-${widget.index}'),
              onPressed: () => SubTenantAdminShell.navigateTo(
                context,
                nextIndex,
                currentIndex: widget.index,
              ),
              child: const Text('Next tab'),
            ),
          ],
        ),
      ),
    );
  }
}
