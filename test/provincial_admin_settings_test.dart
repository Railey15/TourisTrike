import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';

void main() {
  test(
    'provincial office settings use the authenticated profile as fallback',
    () {
      const profile = ProvincialAdminProfile(
        id: 'admin-id',
        role: 'admin',
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

  test('settings is part of the persistent Provincial Admin navigation', () {
    expect(
      provincialAdminNavItems.any(
        (item) => item.destination == ProvincialAdminDestination.settings,
      ),
      isTrue,
    );
  });

  test(
    'migration reuses authoritative settings and enforces protected scope',
    () {
      final migration = File(
        'supabase/migrations/20260926010000_provincial_admin_settings.sql',
      ).readAsStringSync();

      expect(migration, contains('alter table public.admin_settings'));
      expect(migration, contains('public.package_cancellation_policy'));
      expect(migration, contains('public.protect_own_profile_scope()'));
      expect(migration, contains('ROLE_AND_TENANT_SCOPE_ARE_READ_ONLY'));
      expect(
        migration,
        contains('public.apply_provincial_admin_notification_preference()'),
      );
      expect(migration, isNot(contains('create table public.admin_settings')));
      expect(migration, isNot(contains('insert into storage.buckets')));
    },
  );
}
