import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/main_tenant/layouts/main_tenant_shell.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_models.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_nav.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';

const _viewports = <Size>[
  Size(360, 800),
  Size(390, 844),
  Size(412, 915),
  Size(768, 1024),
  Size(768, 600),
  Size(820, 1180),
  Size(900, 700),
  Size(939, 1205),
  Size(1024, 768),
  Size(1280, 720),
  Size(1366, 600),
  Size(1366, 768),
  Size(1440, 900),
  Size(1536, 864),
  Size(1600, 900),
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

  testWidgets('all eight subtenant headers keep desktop controls aligned', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);

    _SubTenantHeaderGeometry? baseline;
    for (var index = 0; index < 8; index++) {
      await tester.pumpWidget(
        MaterialApp(
          home: SubTenantPortalScreen(
            key: ValueKey<int>(index),
            initialIndex: index,
            pageBuilder: (pageIndex) => _SubTenantHeaderProbe(index: pageIndex),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final geometry = _subtenantHeaderGeometry(tester);
      expect(geometry.header.height, 92);
      expect(geometry.search.width, 260);
      expect(geometry.actionSlot.width, 190);
      expect(geometry.search.center.dy, geometry.actionSlot.center.dy);
      expect(geometry.search.center.dy, geometry.notifications.center.dy);
      expect(geometry.search.center.dy, geometry.administrator.center.dy);
      expect(tester.takeException(), isNull);

      final previous = baseline;
      if (previous != null) {
        expect(geometry.header, previous.header);
        expect(geometry.search, previous.search);
        expect(geometry.actionSlot, previous.actionSlot);
        expect(geometry.notifications, previous.notifications);
        expect(geometry.administrator, previous.administrator);
      } else {
        baseline = geometry;
      }

      expect(find.text('Add Spot'), index == 1 ? findsOneWidget : findsNothing);
      expect(
        find.text('Create Package'),
        index == 2 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byTooltip('Refresh settings'),
        index == 6 ? findsOneWidget : findsNothing,
      );
    }
  });

  testWidgets('all eight subtenant headers adapt consistently on tablet', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(820, 1180);

    _SubTenantHeaderGeometry? baseline;
    for (var index = 0; index < 8; index++) {
      await tester.pumpWidget(
        MaterialApp(
          home: SubTenantPortalScreen(
            key: ValueKey<int>(index),
            initialIndex: index,
            pageBuilder: (pageIndex) => _SubTenantHeaderProbe(index: pageIndex),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final geometry = _subtenantHeaderGeometry(tester);
      expect(geometry.header.height, 146);
      expect(geometry.search.width, 260);
      expect(geometry.actionSlot.width, 190);
      expect(geometry.search.center.dy, geometry.actionSlot.center.dy);
      expect(tester.takeException(), isNull);

      final previous = baseline;
      if (previous != null) {
        expect(geometry.header, previous.header);
        expect(geometry.search, previous.search);
        expect(geometry.actionSlot, previous.actionSlot);
        expect(geometry.notifications, previous.notifications);
        expect(geometry.administrator, previous.administrator);
      } else {
        baseline = geometry;
      }
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

class _SubTenantHeaderProbe extends StatelessWidget {
  const _SubTenantHeaderProbe({required this.index});

  final int index;

  static const _titles = <String>[
    'Dashboard',
    'Tourist Spots',
    'Packages',
    'Bookings',
    'Drivers & Guides',
    'Municipality Reports',
    'Settings',
    'Disputes & Cases',
  ];

  @override
  Widget build(BuildContext context) {
    final actions = switch (index) {
      1 => <Widget>[
        SubTenantHeaderAction(
          onPressed: () {},
          icon: Icons.add_location_alt_rounded,
          label: 'Add Spot',
        ),
      ],
      2 => <Widget>[
        SubTenantHeaderAction(
          onPressed: () {},
          icon: Icons.add_box_rounded,
          label: 'Create Package',
        ),
      ],
      6 => <Widget>[
        IconButton(
          onPressed: () {},
          tooltip: 'Refresh settings',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      _ => const <Widget>[],
    };

    return SubTenantAdminShell(
      currentIndex: index,
      title: _titles[index],
      subtitle: 'Municipality-scoped portal information and operations.',
      actions: actions,
      child: const SizedBox.expand(),
    );
  }
}

class _SubTenantHeaderGeometry {
  const _SubTenantHeaderGeometry({
    required this.header,
    required this.search,
    required this.actionSlot,
    required this.notifications,
    required this.administrator,
  });

  final Rect header;
  final Rect search;
  final Rect actionSlot;
  final Rect notifications;
  final Rect administrator;
}

_SubTenantHeaderGeometry _subtenantHeaderGeometry(WidgetTester tester) {
  return _SubTenantHeaderGeometry(
    header: tester.getRect(find.byKey(SubTenantHeaderKeys.header)),
    search: tester.getRect(find.byKey(SubTenantHeaderKeys.search)),
    actionSlot: tester.getRect(find.byKey(SubTenantHeaderKeys.actionSlot)),
    notifications: tester.getRect(
      find.byKey(SubTenantHeaderKeys.notifications),
    ),
    administrator: tester.getRect(
      find.byKey(SubTenantHeaderKeys.administrator),
    ),
  );
}
