import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_models.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_nav.dart';

void main() {
  test(
    'provincial office settings use the authenticated profile as fallback',
    () {
      const profile = MainTenantProfile(
        id: 'main-tenant-id',
        role: 'main_tenant',
        fullName: 'Maria Santos',
        firstName: 'Maria',
        lastName: 'Santos',
        email: 'admin@bulacan.gov.ph',
        mobile: '09170000000',
        city: '',
        province: 'Bulacan',
        profileImageUrl: '',
        raw: {'address': 'Malolos, Bulacan'},
      );

      final settings = ProvincialOfficeSettings.fromMap(const {}, profile);

      expect(settings.officeName, 'Provincial Tourism Office of Bulacan');
      expect(settings.contactPerson, 'Maria Santos');
      expect(settings.officialEmail, 'admin@bulacan.gov.ph');
      expect(settings.officeAddress, 'Malolos, Bulacan');
    },
  );

  test('notification preferences default to enabled', () {
    final preferences = ProvincialNotificationPreferences.fromMap(const {});

    expect(preferences.cityApplications, isTrue);
    expect(preferences.driverStatusUpdates, isTrue);
    expect(preferences.bookingIssues, isTrue);
    expect(preferences.paymentDisputes, isTrue);
  });

  test(
    'settings is part of the persistent Provincial Administrator navigation',
    () {
      expect(
        mainTenantNavItems.any(
          (item) => item.destination == MainTenantDestination.settings,
        ),
        isTrue,
      );
    },
  );

  test(
    'migration reuses authoritative settings and enforces protected scope',
    () {
      final migration = File(
        'supabase/migrations/20260927020000_main_tenant_settings.sql',
      ).readAsStringSync();

      expect(migration, contains('public.provincial_office_details'));
      expect(migration, contains('alter table public.admin_settings'));
      expect(
        migration,
        contains('public.apply_main_tenant_notification_preference()'),
      );
      expect(migration, contains("where p.role = 'main_tenant'"));
      expect(migration, contains('drop column if exists office_name'));
      expect(migration, contains("set search_path = ''"));
      expect(migration, isNot(contains('set search_path = public')));
      expect(migration, contains("if tg_op = 'INSERT'"));
      expect(migration, contains('new.province := v_assigned_province'));
      expect(migration, contains("p.role = 'main_tenant'"));
    },
  );

  test('office contact fields never write to admin_settings', () {
    final service = File(
      'lib/screens/main_tenant/main_tenant_service.dart',
    ).readAsStringSync();
    final officeMethod = service.substring(
      service.indexOf('Future<void> updateProvincialOffice'),
      service.indexOf('Future<void> updateBranding'),
    );
    final preferenceMethod = service.substring(
      service.indexOf('Future<void> updateNotificationPreferences'),
      service.indexOf('Future<void> changePassword'),
    );

    expect(officeMethod, contains('_upsertOwnProvincialOffice'));
    expect(officeMethod, contains("'contact_number'"));
    expect(officeMethod, contains("'official_email'"));
    expect(preferenceMethod, contains('_upsertOwnMainTenantSettings'));
    expect(preferenceMethod, isNot(contains("'contact_number'")));
    expect(preferenceMethod, isNot(contains("'official_email'")));
  });
}
