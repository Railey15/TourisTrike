import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/auth/app_role.dart';
import 'package:touristrike/core/auth/app_role_destination.dart';

void main() {
  test('canonical role values parse and route independently', () {
    for (final role in AppRole.values) {
      expect(AppRole.tryParse(role.databaseValue), role);
    }

    expect(
      destinationForRole(AppRole.administrator),
      AppRoleDestination.administratorPortal,
    );
    expect(
      destinationForRole(AppRole.mainTenant),
      AppRoleDestination.mainTenantPortal,
    );
    expect(
      destinationForRole(AppRole.subtenant),
      AppRoleDestination.subtenantPortal,
    );
    expect(destinationForRole(AppRole.driver), AppRoleDestination.driverApp);
    expect(destinationForRole(AppRole.tourist), AppRoleDestination.touristApp);
  });

  test('legacy admin only maps to the provincial main tenant', () {
    expect(AppRole.tryParse('admin'), AppRole.mainTenant);
    expect(AppRole.tryParse('admin', acceptLegacyAdmin: false), isNull);
    expect(AppRole.tryParse('system_admin'), isNull);
    expect(AppRole.tryParse('provincial_admin'), isNull);
  });

  test('role portal boundaries do not overlap', () {
    expect(
      roleCanAccessDestination(
        AppRole.mainTenant,
        AppRoleDestination.mainTenantPortal,
      ),
      isTrue,
    );
    expect(
      roleCanAccessDestination(
        AppRole.mainTenant,
        AppRoleDestination.administratorPortal,
      ),
      isFalse,
    );
    expect(
      roleCanAccessDestination(
        AppRole.administrator,
        AppRoleDestination.mainTenantPortal,
      ),
      isFalse,
    );
    expect(
      roleCanAccessDestination(
        AppRole.subtenant,
        AppRoleDestination.mainTenantPortal,
      ),
      isFalse,
    );

    for (final role in AppRole.values) {
      for (final destination in AppRoleDestination.values) {
        expect(
          roleCanAccessDestination(role, destination),
          destination == destinationForRole(role),
          reason:
              '${role.databaseValue} must only access its canonical destination',
        );
      }
    }
  });

  test('role migration converts legacy rows before final constraint', () {
    final migration = File(
      'supabase/migrations/20260927010000_role_architecture.sql',
    ).readAsStringSync();

    expect(migration, contains("set role = 'main_tenant'"));
    expect(migration, contains("where role = 'admin'"));
    expect(migration, contains("'administrator'"));
    expect(migration, contains('legacy admin profiles remain'));
    expect(migration, contains('public.is_system_administrator()'));
    expect(migration, contains("set search_path = ''"));
    expect(
      migration,
      isNot(
        contains(
          'grant execute on function public.is_system_administrator() to anon',
        ),
      ),
    );
  });
}
