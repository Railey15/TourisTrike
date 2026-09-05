import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';

String _read(String path) => File(
  path,
).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

void main() {
  late String phase1;
  late String phase2;
  late String phase3;
  late String phase4;
  late String rlsRegression;
  late String subtenantSettingsScreen;
  late String adminService;
  late String adminHeader;
  late String allSubtenantCode;
  late String citySuggestionService;
  late String googlePlacesWebGateway;

  setUpAll(() {
    phase1 = _read(
      'supabase/migrations/20260905000000_phase1_subtenant_scope_and_settings.sql',
    );
    phase2 = _read(
      'supabase/migrations/20260905010000_phase2_subtenant_office_identity.sql',
    );
    phase3 = _read(
      'supabase/migrations/20260905020000_phase3_admin_classification_review.sql',
    );
    phase4 = _read(
      'supabase/migrations/20260905030000_phase4_stabilization.sql',
    );
    rlsRegression = _read('supabase/tests/phase4_rls_regression.sql');
    subtenantSettingsScreen = _read(
      'lib/screens/subtenant/subtenant_city_profile_screen.dart',
    );
    adminService = _read('lib/screens/admin/provincial_admin_service.dart');
    adminHeader = _read('lib/screens/admin/widgets/admin_header_tools.dart');
    allSubtenantCode = Directory('lib/screens/subtenant')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    citySuggestionService = _read('lib/core/places/city_spot_suggestions.dart');
    googlePlacesWebGateway = _read(
      'lib/core/places/google_places_gateway_web.dart',
    );
  });

  test('Phase 1-4 migrations declare a strict dependency chain', () {
    expect(phase1, contains('20260902000000_live_transaction_audit.sql'));
    expect(
      phase2,
      contains('20260905000000_phase1_subtenant_scope_and_settings.sql'),
    );
    expect(
      phase3,
      contains('20260905010000_phase2_subtenant_office_identity.sql'),
    );
    expect(
      phase4,
      contains('20260905020000_phase3_admin_classification_review.sql'),
    );
  });

  test('payment scope prefers booking ownership over local payee identity', () {
    expect(phase4, contains('when pr.booking_id is not null then'));
    expect(
      phase4,
      contains('public.subtenant_can_access_booking(pr.booking_id)'),
    );
    expect(phase4, isNot(contains('subtenant_can_access_driver(pr.payee_id)')));
  });

  test('Subtenant discovery reads remain municipality-scoped', () {
    for (final policy in [
      'spots_read',
      'packages_read',
      'announcements_select',
    ]) {
      expect(phase4, contains('create policy $policy'));
    }
    expect(
      phase4,
      contains("current_profile_role() is distinct from 'subtenant'"),
    );
  });

  test('updated-row RLS checks proposed booking and payment scope keys', () {
    expect(
      phase4,
      contains(
        'where package.id = package_bookings.package_id\n'
        '      and public.cities_match',
      ),
    );
    expect(
      phase4,
      contains(
        'booking_id is not null\n    and public.subtenant_can_access_booking',
      ),
    );
  });

  test('SECURITY DEFINER conversation entry point rejects null auth', () {
    expect(phase4, contains("raise exception 'UNAUTHENTICATED'"));
    expect(
      phase4,
      contains(
        'revoke all on function public.ensure_booking_group_conversation(uuid)',
      ),
    );
    expect(
      phase4,
      contains(
        'grant execute on function public.ensure_booking_group_conversation(uuid)',
      ),
    );
  });

  test('live RLS plan covers every Phase 4 role boundary', () {
    for (final contract in [
      'cross_city_spots',
      'cross_city_packages',
      'cross_city_drivers',
      'cross_city_bookings',
      'cross_city_payments',
      'cross_city_disputes',
      'municipality assignment change was blocked',
      'LGU classification change was blocked',
      'admin spot moderation allowed',
      'admin LGU classification review allowed',
      'tourist_booking',
      'driver_booking',
    ]) {
      expect(rlsRegression, contains(contract));
    }
    expect(rlsRegression, contains('rollback;'));
  });

  test('fare settings survive persistence mapping and reload parsing', () {
    const profile = SubTenantProfile(
      id: 'subtenant-id',
      role: 'subtenant',
      fullName: 'Officer',
      firstName: '',
      lastName: '',
      email: '',
      mobile: '',
      address: '',
      city: 'Bustos',
      province: 'Bulacan',
      profileImageUrl: '',
      raw: <String, dynamic>{},
    );
    const original = SubTenantFareSettings(
      subtenantId: 'subtenant-id',
      city: 'Bustos',
      baseFare: 75,
      farePerKm: 18.5,
      minimumFare: 120,
      waitingFee: 25,
    );

    final parsed = SubTenantFareSettings.fromMap(original.toMap(), profile);

    expect(parsed.subtenantId, original.subtenantId);
    expect(parsed.city, original.city);
    expect(parsed.baseFare, original.baseFare);
    expect(parsed.farePerKm, original.farePerKm);
    expect(parsed.minimumFare, original.minimumFare);
    expect(parsed.waitingFee, original.waitingFee);
  });

  test(
    'removed settings and optional AI controls stay absent from UI code',
    () {
      expect(subtenantSettingsScreen, isNot(contains('AI Suggestions')));
      expect(subtenantSettingsScreen, isNot(contains('enable_ai_suggestions')));
      expect(subtenantSettingsScreen, isNot(contains('General Settings')));
      expect(
        subtenantSettingsScreen,
        isNot(contains('Tourism Office Settings')),
      );
      expect(
        File(
          'lib/screens/admin/provincial_admin_settings_screen.dart',
        ).existsSync(),
        isFalse,
      );
      expect(allSubtenantCode, isNot(contains('enable_ai_suggestions')));
      expect(allSubtenantCode, isNot(contains('enableAiSuggestions')));
      expect(phase2, contains('set enable_ai_suggestions = true'));
    },
  );

  test(
    'Admin search, notifications and mutation confirmation remain wired',
    () {
      expect(
        adminService,
        contains('Future<List<AdminSearchResult>> searchProvince'),
      );
      expect(adminService, contains('.limit(5)'));
      expect(adminService, contains('fetchAdminNotifications'));
      expect(adminService, contains('markAdminNotificationRead'));
      expect(adminService, contains(".select('id')\n        .single()"));
      expect(adminHeader, contains('AdminSearchResultType.tenant'));
      expect(adminHeader, contains('AdminSearchResultType.booking'));
      expect(adminHeader, contains('No matching province records.'));
      expect(adminHeader, contains('Unable to load notifications'));
    },
  );

  test('responsive regressions retain bounded and scrollable controls', () {
    expect(subtenantSettingsScreen, contains('constraints.maxWidth < 560'));
    expect(adminHeader, contains('viewport.height - 190'));
    expect(adminHeader, contains('SingleChildScrollView'));
    expect(phase3, contains('profiles_driver_admin_search_idx'));
  });

  test('Google Places configuration has no hardcoded fallback key', () {
    expect(citySuggestionService, isNot(contains('AIza')));
    expect(citySuggestionService, contains('resolveGoogleMapsApiKey().trim()'));
    expect(
      googlePlacesWebGateway,
      contains("resolveGoogleMapsApiKey() => '';"),
    );
    expect(googlePlacesWebGateway, isNot(contains('maps.googleapis.com')));
  });
}
