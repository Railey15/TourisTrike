import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_packages_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';

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

  testWidgets(
    'archive action confirms and immediately removes a package from default view',
    (tester) async {
      await _setDesktopSize(tester);
      final archiveGate = Completer<void>();
      final service = _FakePackageService(
        packages: [_package(id: 1, title: 'Package to archive')],
        archiveGate: archiveGate,
      );

      await _pumpScreen(tester, service);
      expect(find.text('Package to archive'), findsOneWidget);
      expect(find.textContaining('1 package'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Archive Package'), findsOneWidget);

      await tester.tap(find.text('Archive Package'));
      await tester.pumpAndSettle();
      expect(find.text('Archive Package?'), findsOneWidget);
      expect(
        find.text(
          'This package will be removed from the active package library but can be restored later.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Archive'));
      await tester.pump();

      expect(find.text('Package to archive'), findsNothing);
      expect(service.archiveCalls, 1);
      expect(service.packages.single.isArchived, isFalse);

      archiveGate.complete();
      await tester.pumpAndSettle();
      expect(service.packages.single.isArchived, isTrue);
    },
  );

  testWidgets(
    'filters separate active publication states from archived packages and counts',
    (tester) async {
      await _setDesktopSize(tester);
      final service = _FakePackageService(
        packages: [
          _package(
            id: 1,
            title: 'Published but hidden',
            status: 'published',
            visibility: 'hidden',
          ),
          _package(id: 2, title: 'Draft package'),
          _package(
            id: 3,
            title: 'Archived package',
            archivedAt: DateTime.utc(2026, 10, 8),
          ),
        ],
      );

      await _pumpScreen(tester, service);
      expect(find.textContaining('2 packages'), findsOneWidget);
      expect(find.text('Published but hidden'), findsOneWidget);
      expect(find.text('Draft package'), findsOneWidget);
      expect(find.text('Archived package'), findsNothing);

      await _selectFilter(tester, 'Published');
      expect(find.text('Published but hidden'), findsOneWidget);
      expect(find.text('Draft package'), findsNothing);
      expect(find.textContaining('1 package'), findsOneWidget);

      await _selectFilter(tester, 'Draft / Unpublished');
      expect(find.text('Draft package'), findsOneWidget);
      expect(find.text('Published but hidden'), findsNothing);
      expect(find.textContaining('1 package'), findsOneWidget);

      await _selectFilter(tester, 'Archived');
      expect(find.text('Archived package'), findsOneWidget);
      expect(find.text('Published but hidden'), findsNothing);
      expect(find.text('Draft package'), findsNothing);
      expect(find.textContaining('1 package'), findsOneWidget);
      expect(find.text('Archived'), findsWidgets);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    },
  );

  testWidgets('restore returns an archived package to the default library', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final service = _FakePackageService(
      packages: [
        _package(
          id: 9,
          title: 'Restorable package',
          archivedAt: DateTime.utc(2026, 10, 8),
        ),
      ],
    );

    await _pumpScreen(tester, service);
    await _selectFilter(tester, 'Archived');
    expect(find.text('Restorable package'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Restore Package'), findsOneWidget);
    await tester.tap(find.text('Restore Package'));
    await tester.pumpAndSettle();

    expect(service.restoreCalls, 1);
    expect(find.text('Restorable package'), findsNothing);

    await _selectFilter(tester, 'All Packages');
    expect(find.text('Restorable package'), findsOneWidget);
    expect(find.textContaining('1 package'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpScreen(tester, service);
    expect(find.text('Restorable package'), findsOneWidget);
  });

  test('archiving preserves package data and uses non-destructive storage', () {
    final original = _package(
      id: 42,
      title: 'Data-safe package',
      status: 'published',
      visibility: 'hidden',
    );
    final archived = original.withArchivedAt(DateTime.utc(2026, 10, 8));

    expect(archived.id, original.id);
    expect(archived.title, original.title);
    expect(archived.description, original.description);
    expect(archived.priceText, original.priceText);
    expect(archived.durationText, original.durationText);
    expect(archived.status, 'published');
    expect(archived.visibilityStatus, 'hidden');
    expect(archived.isArchived, isTrue);

    final migration = File(
      'supabase/migrations/20261008000000_package_archiving.sql',
    ).readAsStringSync();
    final coreSchema = File(
      'supabase/migrations/20260508000000_touristrike_core_schema.sql',
    ).readAsStringSync();
    final serviceSource = File(
      'lib/screens/subtenant/subtenant_service.dart',
    ).readAsStringSync();
    final repositorySource = File(
      'lib/core/supabase/touristrike_repository.dart',
    ).readAsStringSync();

    expect(migration, contains('add column if not exists archived_at'));
    expect(migration, contains('package.archived_at is null'));
    expect(migration, contains('can_access_package_history'));
    expect(migration, isNot(contains('delete from public.tour_packages')));
    expect(
      coreSchema,
      contains(
        'package_id bigint not null references public.tour_packages(id) on delete restrict',
      ),
    );
    expect(serviceSource, contains("'archived_at': archived"));
    expect(serviceSource, contains("isFilter('archived_at', null)"));
    expect(serviceSource, isNot(contains("action: 'delete_package'")));
    expect(repositorySource, contains("isFilter('archived_at', null)"));
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakePackageService service,
) async {
  await tester.pumpWidget(
    MaterialApp(home: SubTenantPackagesScreen(service: service)),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectFilter(WidgetTester tester, String label) async {
  final toolbarLabels = <String>[
    'All Packages',
    'Published',
    'Draft / Unpublished',
    'Archived',
  ];
  final toolbarLabel = toolbarLabels
      .map(find.text)
      .firstWhere((finder) => finder.evaluate().isNotEmpty);
  await tester.tap(toolbarLabel.first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.tap(find.text('Apply Filters'));
  await tester.pumpAndSettle();
}

Future<void> _setDesktopSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

SubTenantPackage _package({
  required int id,
  required String title,
  String status = 'draft',
  String visibility = 'visible',
  DateTime? archivedAt,
}) {
  return SubTenantPackage(
    id: id,
    title: title,
    subtitle: 'Package subtitle',
    description: 'Package description and preserved itinerary metadata',
    city: 'Baliwag',
    priceText: 'From PHP 1,200',
    durationText: '8 hours',
    estimatedBudget: 1200,
    groupSize: 4,
    routeDistanceKm: 12.5,
    imageUrl: '',
    coverImageUrl: '',
    status: status,
    visibilityStatus: visibility,
    submittedBy: 'admin-1',
    submittedByName: 'Administrator',
    createdAt: DateTime.utc(2026, 10, 1),
    archivedAt: archivedAt,
  );
}

const _profile = SubTenantProfile(
  id: 'admin-1',
  role: 'subtenant',
  fullName: 'Administrator',
  firstName: 'Admin',
  lastName: 'User',
  email: 'admin@example.com',
  mobile: '',
  address: '',
  city: 'Baliwag',
  province: 'Bulacan',
  profileImageUrl: '',
  raw: <String, dynamic>{},
);

class _FakePackageService extends SubTenantService {
  _FakePackageService({required this.packages, this.archiveGate});

  List<SubTenantPackage> packages;
  final Completer<void>? archiveGate;
  int archiveCalls = 0;
  int restoreCalls = 0;

  @override
  Future<SubTenantProfile> loadCurrentProfile() async => _profile;

  @override
  Future<List<SubTenantPackage>> fetchPackages(
    SubTenantProfile profile, {
    bool includeArchived = false,
  }) async {
    return packages
        .where((package) => includeArchived || !package.isArchived)
        .toList(growable: false);
  }

  @override
  Future<void> setPackageArchived(
    SubTenantProfile profile,
    SubTenantPackage package,
    bool archived,
  ) async {
    if (archived) {
      archiveCalls += 1;
      await archiveGate?.future;
    } else {
      restoreCalls += 1;
    }
    packages = packages
        .map(
          (item) => stId(item.id) == stId(package.id)
              ? item.withArchivedAt(archived ? DateTime.now().toUtc() : null)
              : item,
        )
        .toList(growable: false);
  }
}
