import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/auth/app_role.dart';
import 'package:touristrike/core/maintenance/maintenance_screen.dart';
import 'package:touristrike/core/maintenance/maintenance_settings.dart';
import 'package:touristrike/screens/administrator/administrator_configuration_screen.dart';
import 'package:touristrike/screens/administrator/administrator_models.dart';

void main() {
  final start = DateTime.utc(2026, 10, 1, 1);
  final end = DateTime.utc(2026, 10, 1, 3);

  group('maintenance effective state and role access', () {
    test(
      'scheduled maintenance is normal before, active during, and normal after',
      () {
        final settings = maintenance(
          startsAt: start,
          endsAt: end,
          serverActive: false,
        );

        expect(
          settings.statusAt(start.subtract(const Duration(seconds: 1))),
          MaintenanceSystemStatus.scheduled,
        );
        expect(
          settings.statusAt(start.add(const Duration(minutes: 1))),
          MaintenanceSystemStatus.active,
        );
        expect(settings.statusAt(end), MaintenanceSystemStatus.operational);
      },
    );

    test('indefinite maintenance remains active', () {
      final settings = maintenance(
        startsAt: start,
        endsAt: null,
        indefinite: true,
      );
      expect(
        settings.statusAt(start.add(const Duration(days: 500))),
        MaintenanceSystemStatus.active,
      );
    });

    test('administrator always remains allowed', () {
      final settings = maintenance(startsAt: start, endsAt: end);
      expect(settings.allowsRole(AppRole.administrator), isTrue);
      expect(settings.allowsRole(AppRole.tourist), isFalse);
      expect(settings.allowsRole(AppRole.driver), isFalse);
      expect(settings.allowsRole(AppRole.subtenant), isFalse);
      expect(settings.allowsRole(AppRole.mainTenant), isFalse);
    });

    test('main tenant is allowed only when configured', () {
      expect(
        maintenance(
          startsAt: start,
          endsAt: end,
        ).allowsRole(AppRole.mainTenant),
        isFalse,
      );
      expect(
        maintenance(
          startsAt: start,
          endsAt: end,
          allowMainTenant: true,
        ).allowsRole(AppRole.mainTenant),
        isTrue,
      );
    });

    test('disabled maintenance restores normal status', () {
      final settings = maintenance(
        enabled: false,
        startsAt: start,
        endsAt: end,
        serverActive: false,
      );
      expect(settings.status, MaintenanceSystemStatus.operational);
      expect(settings.blocksViewer, isFalse);
    });
  });

  group('maintenance screen', () {
    for (final size in <Size>[const Size(390, 844), const Size(1440, 900)]) {
      testWidgets(
        'renders branded maintenance message at ${size.width.toInt()}px',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              home: MaintenanceScreen(
                settings: maintenance(
                  startsAt: DateTime.now().toUtc().subtract(
                    const Duration(hours: 1),
                  ),
                  endsAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
                  serverActive: true,
                ),
                onTryAgain: () async {},
              ),
            ),
          );

          expect(find.text("We'll be right back!"), findsOneWidget);
          expect(
            find.text(
              'TourisTrike is temporarily unavailable while we perform system maintenance. Your account and booking information remain safe.',
            ),
            findsOneWidget,
          );
          expect(find.text('Thank you for your patience.'), findsOneWidget);
          expect(find.byIcon(Icons.construction_rounded), findsOneWidget);
          expect(find.text('Expected availability'), findsNothing);
          expect(find.text('Last updated'), findsNothing);
          expect(
            find.byKey(const ValueKey('maintenance-try-again')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('maintenance-administrator-access')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('does not expose an administrator sign-in action', (
      tester,
    ) async {
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MaintenanceScreen(
            settings: maintenance(
              startsAt: DateTime.now().toUtc().subtract(
                const Duration(hours: 1),
              ),
              endsAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            ),
            onTryAgain: () async {},
            onAdministratorAccess: () async => opened = true,
          ),
        ),
      );

      final administratorAccess = find.byKey(
        const ValueKey('maintenance-administrator-access'),
      );
      expect(administratorAccess, findsNothing);
      expect(opened, isFalse);
    });
  });

  testWidgets('administrator confirms enabling maintenance', (tester) async {
    MaintenanceUpdate? submitted;
    final data = AdministratorPortalData(
      profile: const AdministratorProfile(
        id: 'administrator-id',
        name: 'System Administrator',
        role: AppRole.administrator,
        email: 'admin@example.com',
      ),
      accounts: const [],
      tenants: const [],
      auditEntries: const [],
      healthChecks: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdministratorConfigurationScreen(
            data: data,
            onUpdateMaintenance: (update) async {
              submitted = update;
              return maintenance(
                startsAt: update.startsAt!,
                endsAt: update.endsAt,
                indefinite: update.indefinite,
                allowMainTenant: update.allowMainTenant,
                serverActive: true,
              );
            },
          ),
        ),
      ),
    );

    final enableButton = find.byKey(const ValueKey('maintenance-enable-now'));
    await tester.ensureVisible(enableButton);
    await tester.pumpAndSettle();
    await tester.tap(enableButton);
    await tester.pumpAndSettle();
    final confirmButton = find.byKey(const ValueKey('maintenance-confirm'));
    expect(confirmButton, findsOneWidget);
    await tester.ensureVisible(confirmButton);
    await tester.pumpAndSettle();
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.enabled, isTrue);
  });

  test('database migration secures, enforces, and audits maintenance', () {
    final sql = File(
      'supabase/migration_hold/20261001080000_system_maintenance.sql',
    ).readAsStringSync();

    expect(sql, contains('public.is_system_administrator()'));
    expect(sql, contains("raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED'"));
    expect(sql, contains("coalesce(p.role, '') <> 'administrator'"));
    expect(sql, contains("coalesce(p.role, '') = 'main_tenant'"));
    expect(sql, contains('maintenance_allow_main_tenant'));
    expect(sql, contains('maintenance_starts_at <= now()'));
    expect(sql, contains('maintenance_ends_at > now()'));
    expect(sql, contains('maintenance_indefinite'));
    expect(sql, contains("'SYSTEM_MAINTENANCE_ENABLED'"));
    expect(sql, contains("'SYSTEM_MAINTENANCE_DISABLED'"));
    expect(sql, contains("'SYSTEM_MAINTENANCE_SCHEDULED'"));
    expect(sql, contains("'SYSTEM_MAINTENANCE_UPDATED'"));
    expect(sql, contains('pgrst.db_pre_request'));
    expect(sql, contains("raise exception 'ACCOUNT_SUSPENDED'"));
    expect(sql, contains("raise exception 'SYSTEM_MAINTENANCE_ACTIVE'"));
    expect(sql, contains("current_setting('role', true) <> 'service_role'"));
    expect(
      sql.indexOf("raise exception 'ACCOUNT_SUSPENDED'"),
      lessThan(sql.indexOf("raise exception 'SYSTEM_MAINTENANCE_ACTIVE'")),
    );
    expect(sql, contains('insert into public.audit_logs'));
    expect(sql, contains("'/rpc/get_maintenance_status'"));
  });
}

MaintenanceSettings maintenance({
  bool enabled = true,
  required DateTime startsAt,
  required DateTime? endsAt,
  bool indefinite = false,
  bool allowMainTenant = false,
  bool serverActive = true,
}) {
  return MaintenanceSettings(
    enabled: enabled,
    title: "We'll be right back!",
    message:
        'TourisTrike is temporarily unavailable while we perform system maintenance. Your account and booking information remain safe.',
    startsAt: startsAt,
    endsAt: endsAt,
    indefinite: indefinite,
    allowMainTenant: allowMainTenant,
    updatedBy: 'administrator-id',
    updatedByName: 'System Administrator',
    updatedAt: DateTime.utc(2026, 9, 30),
    viewerRole: AppRole.tourist,
    viewerAllowed: !serverActive,
    serverActive: serverActive,
  );
}
