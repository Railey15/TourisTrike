import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/auth/city_admin_application.dart';

void main() {
  const migrationPath =
      'supabase/migrations/20261010130000_city_admin_application_privacy_fix.sql';
  const verificationFixPath =
      'supabase/migrations/20261010140000_fix_city_admin_verification_status.sql';

  test('City Admin draft contains registration data but no Tourist role', () {
    const draft = CityAdminApplicationDraft(
      email: 'OFFICE@example.test ',
      password: 'password',
      city: ' Malolos ',
      officeName: '',
      contactPerson: 'Maria Santos',
      contactNumber: '09171234567',
      officeAddress: 'City Hall',
    );

    final payload = draft.registrationPayload('applicant-id');

    expect(payload['user_id'], 'applicant-id');
    expect(payload['status'], 'pending');
    expect(payload['city'], 'Malolos');
    expect(payload['email'], 'office@example.test');
    expect(payload.containsKey('role'), isFalse);
    expect(payload.containsKey('privacy_notice_version'), isFalse);
  });

  test('submission fallback never inserts or updates profiles', () {
    final source = File(
      'lib/screens/auth/city_admin_verify_otp_screen.dart',
    ).readAsStringSync();
    final fallback = source.substring(
      source.indexOf('Future<String> _submitApplicationWithTables'),
      source.indexOf('Future<Map<String, dynamic>?> _latestRegistration'),
    );

    expect(fallback, isNot(contains(".from('profiles')\n          .insert")));
    expect(fallback, isNot(contains(".from('profiles')\n        .update")));
    expect(fallback, isNot(contains("'role': 'tourist'")));
    expect(fallback, contains("existingRole != null"));
    expect(
      fallback.indexOf('final existingRole'),
      lessThan(fallback.indexOf('final latestRegistration')),
    );
  });

  test('pending profile-less applicant is handled by portal login', () {
    final source = File(
      'lib/screens/auth/web_portal_login_screen.dart',
    ).readAsStringSync();
    final missingProfileBranch = source.substring(
      source.indexOf('if (profile == null)'),
      source.indexOf("final role = AppRole.tryParse"),
    );

    expect(missingProfileBranch, contains('_latestCityRegistration(user.id)'));
    expect(
      missingProfileBranch,
      contains('_portalAccessMessage(registration)'),
    );
  });

  test('forward migration separates pending applicants from profiles', () {
    final sql = File(migrationPath).readAsStringSync();
    final submit = sql.substring(
      sql.indexOf(
        'create or replace function public.submit_city_admin_application',
      ),
      sql.indexOf(
        'create or replace function public.approve_city_registration',
      ),
    );
    final approval = sql.substring(
      sql.indexOf(
        'create or replace function public.approve_city_registration',
      ),
      sql.indexOf(
        'create or replace function public.activate_approved_city_admin',
      ),
    );
    final activation = sql.substring(
      sql.indexOf(
        'create or replace function public.activate_approved_city_admin',
      ),
    );

    expect(
      sql,
      contains(
        'foreign key (user_id) references auth.users(id) on delete cascade',
      ),
    );
    expect(submit, isNot(contains('insert into public.profiles')));
    expect(submit, contains('elsif v_existing_role is not null then'));
    expect(submit, contains("in ('pending', 'approved')"));
    expect(approval, contains('insert into public.profiles'));
    expect(approval, contains("'subtenant'"));
    expect(approval, isNot(contains("'tourist'")));
    expect(approval, contains("'verified'"));
    expect(activation, contains("'verified'"));
    expect(
      approval,
      contains('Applicant profile could not be safely activated'),
    );
  });

  test('Tourist privacy enforcement remains intact', () {
    final privacySql = File(
      'supabase/migrations/20261008005000_payment_email_verification.sql',
    ).readAsStringSync();

    expect(privacySql, contains('PRIVACY_NOTICE_REQUIRED'));
    expect(privacySql, contains('PRIVACY_ACKNOWLEDGMENT_IMMUTABLE'));
    expect(privacySql, contains("not in ('1.0', '1.1')"));
  });

  test('forward migration keeps approval and verification statuses separate', () {
    final sql = File(verificationFixPath).readAsStringSync();
    final approval = sql.substring(
      sql.indexOf(
        'create or replace function public.approve_city_registration',
      ),
      sql.indexOf(
        'create or replace function public.activate_approved_city_admin',
      ),
    );
    final activation = sql.substring(
      sql.indexOf(
        'create or replace function public.activate_approved_city_admin',
      ),
    );

    expect(approval, contains("status = v_normalized_status"));
    expect(approval, contains("'verified'"));
    expect(approval, contains("'subtenant'"));
    expect(activation, contains("and lower(status) = 'approved'"));
    expect(activation, contains("'verified'"));
    expect(activation, contains("'subtenant'"));
    expect(sql, isNot(contains('drop constraint')));
    expect(sql, isNot(contains('add constraint')));
  });
}
