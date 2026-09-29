import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/auth/app_role.dart';
import 'package:touristrike/screens/administrator/administrator_models.dart';
import 'package:touristrike/screens/administrator/administrator_portal_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PlatformAccountSummary account({
    String id = 'account-1',
    String name = 'TourisTrike Developer',
    String email = 'developer@touristrike.test',
    AppRole role = AppRole.administrator,
    DateTime? emailConfirmedAt,
    DateTime? bannedUntil,
    bool authMetadataAvailable = true,
    AdministratorSuspensionRecord? suspension,
  }) {
    return PlatformAccountSummary(
      id: id,
      name: name,
      email: email,
      role: role,
      city: 'Malolos',
      province: 'Bulacan',
      profileCreatedAt: DateTime.utc(2026, 1, 1),
      authCreatedAt: DateTime.utc(2026, 1, 1),
      emailConfirmedAt: emailConfirmedAt,
      lastSignInAt: DateTime.utc(2026, 1, 2),
      bannedUntil: bannedUntil,
      authMetadataAvailable: authMetadataAvailable,
      suspension: suspension,
    );
  }

  AdministratorPortalData portalData({
    List<PlatformAccountSummary>? accounts,
    List<TenantOfficeSummary>? tenants,
    List<PlatformAuditEntry>? auditEntries,
  }) {
    return AdministratorPortalData(
      profile: const AdministratorProfile(
        id: 'account-1',
        name: 'TourisTrike Developer',
        role: AppRole.administrator,
        email: 'developer@touristrike.test',
      ),
      accounts:
          accounts ??
          [
            account(emailConfirmedAt: DateTime.utc(2026, 1, 1)),
            account(
              id: 'province-1',
              name: 'Bulacan Provincial Tourism Office',
              role: AppRole.mainTenant,
              emailConfirmedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
      tenants:
          tenants ??
          [
            TenantOfficeSummary(
              accountId: 'province-1',
              officeName: 'Bulacan Provincial Tourism Office',
              kind: TenantOfficeKind.provincial,
              city: '',
              province: 'Bulacan',
              contactPerson: 'Maria Santos',
              email: 'tourism@bulacan.gov.ph',
              verificationStatus: 'active',
              isActive: true,
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
      auditEntries:
          auditEntries ??
          [
            PlatformAuditEntry(
              id: '1',
              actorId: 'account-1',
              action: 'platform_review',
              tableName: 'profiles',
              recordId: 'province-1',
              description: 'Reviewed platform account directory.',
              createdAt: DateTime.utc(2026, 1, 2),
            ),
          ],
      healthChecks: [
        PlatformHealthCheck(
          name: 'Account directory',
          description: 'Account metadata',
          state: PlatformHealthState.operational,
          latency: const Duration(milliseconds: 10),
          checkedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
  }

  test('account status uses real authentication metadata', () {
    expect(
      account(emailConfirmedAt: DateTime.utc(2026, 1, 1)).status,
      PlatformAccountStatus.active,
    );
    expect(account().status, PlatformAccountStatus.pendingVerification);
    expect(
      account(
        emailConfirmedAt: DateTime.utc(2026, 1, 1),
        bannedUntil: DateTime.utc(2100, 1, 1),
      ).status,
      PlatformAccountStatus.suspended,
    );
    expect(
      account(authMetadataAvailable: false).status,
      PlatformAccountStatus.unknown,
    );
  });

  test('account status honors temporary and permanent suspension records', () {
    final now = DateTime.now().toUtc();
    final temporary = AdministratorSuspensionRecord(
      id: 'temporary-suspension',
      reason: AdministratorSuspensionReason.policyViolation,
      details: '',
      suspendedAt: now.subtract(const Duration(hours: 1)),
      suspendedUntil: now.add(const Duration(days: 3)),
      isPermanent: false,
    );
    final expired = AdministratorSuspensionRecord(
      id: 'expired-suspension',
      reason: AdministratorSuspensionReason.verificationIssue,
      details: '',
      suspendedAt: now.subtract(const Duration(days: 4)),
      suspendedUntil: now.subtract(const Duration(days: 1)),
      isPermanent: false,
    );
    final permanent = AdministratorSuspensionRecord(
      id: 'permanent-suspension',
      reason: AdministratorSuspensionReason.securityConcern,
      details: '',
      suspendedAt: now,
      suspendedUntil: null,
      isPermanent: true,
    );

    expect(
      account(
        emailConfirmedAt: DateTime.utc(2026),
        suspension: temporary,
      ).status,
      PlatformAccountStatus.suspended,
    );
    expect(
      account(
        emailConfirmedAt: DateTime.utc(2026),
        suspension: permanent,
      ).status,
      PlatformAccountStatus.suspended,
    );
    expect(
      account(emailConfirmedAt: DateTime.utc(2026), suspension: expired).status,
      PlatformAccountStatus.active,
    );
  });

  test('account search covers identity, role, and location', () {
    final administrator = account();

    expect(administrator.matches('developer@touristrike'), isTrue);
    expect(administrator.matches('system administrator'), isTrue);
    expect(administrator.matches('administrator'), isTrue);
    expect(administrator.matches('malolos'), isTrue);
    expect(administrator.matches('unrelated'), isFalse);
  });

  test('portal aggregates accounts, tenants, and live health checks', () {
    final data = portalData(
      tenants: [
        TenantOfficeSummary(
          accountId: 'province-1',
          officeName: 'Bulacan Provincial Tourism Office',
          kind: TenantOfficeKind.provincial,
          city: '',
          province: 'Bulacan',
          contactPerson: '',
          email: '',
          verificationStatus: 'active',
          isActive: true,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        TenantOfficeSummary(
          accountId: 'local-1',
          officeName: 'Malolos Tourism Office',
          kind: TenantOfficeKind.cityMunicipal,
          city: 'Malolos',
          province: 'Bulacan',
          contactPerson: '',
          email: '',
          verificationStatus: 'verified',
          isActive: true,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );

    expect(data.countFor(AppRole.administrator), 1);
    expect(data.countFor(AppRole.mainTenant), 1);
    expect(data.activeLocalTenants, 1);
    expect(data.operationalHealthChecks, 1);
  });

  test('portal exposes all platform administration sections', () {
    expect(AdministratorSection.values, [
      AdministratorSection.overview,
      AdministratorSection.accounts,
      AdministratorSection.tenants,
      AdministratorSection.configuration,
      AdministratorSection.integrations,
      AdministratorSection.security,
      AdministratorSection.audit,
    ]);
  });

  testWidgets(
    'administrator portal renders, filters, and navigates platform controls',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: AdministratorPortalScreen(dataLoader: () async => portalData()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsWidgets);
      expect(
        find.text('Platform oversight & account controls'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('administrator-nav-accounts')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('2 accounts available'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'no-match');
      await tester.pump();
      expect(find.text('No matching accounts'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('administrator-nav-tenants')));
      await tester.pumpAndSettle();
      expect(find.text('Bulacan Provincial Tourism Office'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('administrator-nav-configuration')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Access model'), findsOneWidget);
      expect(find.textContaining('administrator'), findsWidgets);

      await tester.tap(
        find.byKey(const ValueKey('administrator-nav-integrations')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Integrations status'), findsOneWidget);
      expect(find.text('Account directory'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('administrator-nav-security')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current administrator session'), findsOneWidget);
      expect(find.text('Security controls'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('administrator-nav-audit')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Reviewed platform account directory.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('system-admin-account-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Account profile'));
      await tester.pumpAndSettle();
      expect(find.text('Technical role'), findsOneWidget);
      expect(find.text('administrator'), findsOneWidget);
    },
  );

  testWidgets('portal wires temporary suspension and reactivation callbacks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var suspended = false;
    var loadCount = 0;
    AdministratorSuspensionRequest? submittedRequest;
    var reactivated = false;

    AdministratorPortalData loadData() {
      loadCount += 1;
      final now = DateTime.now().toUtc();
      return portalData(
        accounts: [
          account(emailConfirmedAt: DateTime.utc(2026)),
          account(
            id: 'target-account',
            name: 'Target Account',
            role: AppRole.tourist,
            emailConfirmedAt: DateTime.utc(2026),
            suspension: suspended
                ? AdministratorSuspensionRecord(
                    id: 'suspension-1',
                    reason: AdministratorSuspensionReason.policyViolation,
                    details: '',
                    suspendedAt: now,
                    suspendedUntil: now.add(const Duration(days: 7)),
                    isPermanent: false,
                    suspendedById: 'account-1',
                    suspendedByName: 'TourisTrike Developer',
                  )
                : null,
          ),
        ],
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: AdministratorPortalScreen(
          initialSection: AdministratorSection.accounts,
          dataLoader: () async => loadData(),
          suspendAccount: (target, request) async {
            expect(target.id, 'target-account');
            submittedRequest = request;
            suspended = true;
          },
          reactivateAccount: (target) async {
            expect(target.id, 'target-account');
            suspended = false;
            reactivated = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Target Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspend Account'));
    await tester.pumpAndSettle();
    final reasonDropdown = find.byType(
      DropdownButtonFormField<AdministratorSuspensionReason>,
    );
    await tester.ensureVisible(reasonDropdown);
    await tester.tap(reasonDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Policy violation').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspend Account'));
    await tester.pumpAndSettle();

    expect(
      submittedRequest?.reason,
      AdministratorSuspensionReason.policyViolation,
    );
    expect(submittedRequest?.totalDays, 7);
    expect(suspended, isTrue);
    expect(loadCount, greaterThan(1));

    await tester.tap(find.text('Target Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reactivate Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reactivate Account'));
    await tester.pumpAndSettle();

    expect(reactivated, isTrue);
    expect(suspended, isFalse);
  });

  testWidgets(
    'account menu signs out and returns to the portal login destination',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var signedOut = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AdministratorPortalScreen(
            dataLoader: () async => portalData(),
            signOut: () async => signedOut = true,
            signedOutDestinationBuilder: (_) =>
                const Scaffold(body: Text('Portal login destination')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('system-admin-account-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsNWidgets(2));
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();

      expect(signedOut, isTrue);
      expect(find.text('Portal login destination'), findsOneWidget);
    },
  );

  testWidgets(
    'administrator portal has loading, empty, error, and compact states',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final pending = Completer<AdministratorPortalData>();
      await tester.pumpWidget(
        MaterialApp(
          home: AdministratorPortalScreen(
            initialSection: AdministratorSection.accounts,
            dataLoader: () => pending.future,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ChoiceChip), findsWidgets);
      expect(
        find.byKey(const ValueKey('administrator-nav-overview')),
        findsNothing,
      );

      pending.complete(portalData(accounts: const [], tenants: const []));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Users & Roles'));
      await tester.pumpAndSettle();
      expect(find.text('No accounts available'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: AdministratorPortalScreen(
            key: UniqueKey(),
            dataLoader: () => Future<AdministratorPortalData>.error(
              StateError('deliberate portal failure'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to load System Administrator data'),
        findsOneWidget,
      );
      expect(find.textContaining('deliberate portal failure'), findsOneWidget);
    },
  );

  test('administrator migration is read-only and exactly role-guarded', () {
    final migration = File(
      'supabase/migrations/20260927030000_administrator_portal.sql',
    ).readAsStringSync();

    expect(migration, contains('administrator_list_accounts'));
    expect(migration, contains('public.is_system_administrator()'));
    expect(migration, contains('join auth.users'));
    expect(migration, contains('security definer'));
    expect(migration, contains("set search_path = ''"));
    expect(migration, contains('revoke all'));
    expect(migration, contains('grant execute'));
    expect(migration, isNot(contains("role = 'admin'")));
    expect(migration, isNot(contains("role = 'system_admin'")));
    expect(migration, isNot(contains("role = 'provincial_admin'")));
    expect(migration, isNot(contains('insert into')));
    expect(migration, isNot(contains('update public.')));
    expect(migration, isNot(contains('delete from')));
  });

  test('account suspension backend is role-guarded and auditable', () {
    final migration = File(
      'supabase/migrations/20260927040000_administrator_account_suspensions.sql',
    ).readAsStringSync();
    final edgeFunction = File(
      'supabase/functions/administrator-account-access/index.ts',
    ).readAsStringSync();

    expect(
      migration,
      contains('create table if not exists public.account_suspensions'),
    );
    expect(migration, contains('SELF_SUSPENSION_NOT_ALLOWED'));
    expect(migration, contains('LAST_USABLE_ADMINISTRATOR'));
    expect(migration, contains('SYSTEM_ADMINISTRATOR_REQUIRED'));
    expect(migration, contains("'account_suspended'"));
    expect(migration, contains("'account_reactivated'"));
    expect(migration, contains('pgrst.db_pre_request'));
    expect(migration, contains('security definer'));
    expect(edgeFunction, contains('auth.admin.updateUserById'));
    expect(edgeFunction, contains("ban_duration: 'none'"));
    expect(edgeFunction, contains("return '876000h'"));
    final flutterService = File(
      'lib/screens/administrator/administrator_service.dart',
    ).readAsStringSync();
    expect(edgeFunction, contains("Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')"));
    expect(flutterService, isNot(contains('SUPABASE_SERVICE_ROLE_KEY')));
  });
}
