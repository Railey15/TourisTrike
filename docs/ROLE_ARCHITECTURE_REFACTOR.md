# Role Architecture Refactor Progress

Last updated: 2026-09-27

## Status

Implementation is at a safe, locally verified checkpoint. The application code
and migrations implement the five-role architecture and expanded System
Administrator portal. All 321 Flutter tests pass and the web release build
completes under Flutter 3.41.2 / Dart 3.11.0. Supabase CLI authentication and
project linking now work. The forward reconciliation and three role/portal
migrations have **not been deployed** because the reviewed historical
reconciliation must be applied and verified first; no history repair has been
run. Docker remains unavailable.

## Role architecture

| Technical role | Display role | Scope |
| --- | --- | --- |
| `administrator` | System Administrator | Platform account visibility and audit logs |
| `main_tenant` | Provincial Administrator | Bulacan province-wide tourism administration |
| `subtenant` | City/Municipal Administrator | Assigned municipality only |
| `driver` | Driver-Tour Guide | Driver application |
| `tourist` | Tourist | Tourist application |

The former database value `admin` is treated only as a legacy name for the
Provincial Administrator. It migrates to `main_tenant`; it is never converted
to `administrator`.

## Completed phases

1. **Project-wide audit:** Audited Flutter role parsing/routing, role-specific
   folders and services, tests, migrations, policies, SECURITY DEFINER
   functions, notifications, storage policies, and settings persistence.
2. **Role model/constants:** Added `AppRole` and `AppRoleDestination` as the
   application source of truth for all five roles and route destinations.
3. **Database role migration authored:** Added the ordered, data-preserving
   `admin -> main_tenant` migration and final five-value profile constraint.
4. **Current portal renamed:** Moved the former `screens/admin` implementation
   to `screens/main_tenant` and renamed the portal, shell, service, navigation,
   models, widgets, imports, and tests to `MainTenant*` terminology.
5. **Visible terminology:** The provincial portal displays Provincial
   Administrator; primary municipality portal labels display City/Municipal
   Administrator.
6. **Main Tenant data architecture:** Added `provincial_office_details` for
   provincial office identity and branding. It is separate from
   `subtenant_details` and locks province/owner scope.
7. **Settings correction:** Main Tenant office and branding now load/save via
   `provincial_office_details`; notification preferences remain in the existing
   `admin_settings` preference table; cancellation rules and policy documents
   remain in their authoritative existing tables.
8. **Subtenant preservation:** Existing municipality-scoped architecture and
   feature code were preserved. No province-wide permission was added.
9. **System Administrator portal:** Added a separate, responsive platform
   portal with Overview, Accounts, Tenants, Audit Log, and System Health
   sections. It uses real account/Auth metadata, tenant office records, recent
   audit events, and measured backend checks. It has no fake operational
   controls and does not reuse the provincial dashboard.
10. **Authentication/routing:** Login, web portal login, and loading redirects
    now distinguish all five roles. Main Tenant and System Administrator route
    to different portals.
11. **RLS/function semantics:** Added explicit `is_main_tenant()` and
    `is_system_administrator()` helpers. System Administrator access is limited
    to profile visibility, audit history, and province-office metadata. Existing
    provincial operational policies continue to resolve to Main Tenant only.
12. **Tests authored/updated:** Added parsing, route mapping, portal-boundary,
    migration, and settings-architecture assertions; renamed existing
    provincial tests to Main Tenant tests.
13. **Static validation:** Ran formatting on new/targeted files, full Flutter
    analysis, focused test command, migration content assertions, and final role
    and import searches.
14. **Continuation verification:** Repaired the project Flutter toolchain,
    hardened new SECURITY DEFINER search paths, bound new provincial office
    rows to the protected profile province, ran the full test suite, and
    completed a web release build.

## Files changed

### Added

- `lib/core/auth/app_role.dart`
- `lib/core/auth/app_role_destination.dart`
- `lib/screens/administrator/administrator_models.dart`
- `lib/screens/administrator/administrator_service.dart`
- `lib/screens/administrator/administrator_portal_screen.dart`
- `supabase/migrations/20260927010000_role_architecture.sql`
- `supabase/migrations/20260927020000_main_tenant_settings.sql`
- `supabase/migrations/20260927030000_administrator_portal.sql`
- `test/app_role_test.dart`
- `test/administrator_portal_test.dart`
- `test/historical_schema_reconciliation_test.dart`
- `docs/ROLE_ARCHITECTURE_REFACTOR.md`

### Added during continuation verification

- `.vscode/settings.json` now selects `C:\flutter\flutter` for this workspace
  (Flutter 3.41.2 / Dart 3.11.0).
- Administrator widget coverage now verifies desktop/compact navigation,
  search, loading, empty, error, audit, tenant, and health states.

### Renamed/moved and updated

- `lib/screens/admin/` -> `lib/screens/main_tenant/`
- `admin_models.dart` -> `main_tenant_models.dart`
- `layouts/provincial_admin_shell.dart` -> `layouts/main_tenant_shell.dart`
- `provincial_admin_dashboard_screen.dart` -> `main_tenant_dashboard_screen.dart`
- `provincial_admin_nav.dart` -> `main_tenant_nav.dart`
- `provincial_admin_service.dart` -> `main_tenant_service.dart`
- `provincial_admin_settings_screen.dart` -> `main_tenant_settings_screen.dart`
- all role-specific `widgets/admin_*.dart` -> `widgets/main_tenant_*.dart`
- `widgets/provincial_admin_sidebar.dart` -> `widgets/main_tenant_sidebar.dart`
- `widgets/provincial_admin_style.dart` -> `widgets/main_tenant_style.dart`
- `lib/widgets/app_bottom_nav_admin.dart` ->
  `lib/widgets/app_bottom_nav_main_tenant.dart`
- `test/admin_phase3_models_test.dart` ->
  `test/main_tenant_phase3_models_test.dart`
- `test/provincial_admin_portal_navigation_test.dart` ->
  `test/main_tenant_portal_navigation_test.dart`
- `test/provincial_admin_settings_test.dart` ->
  `test/main_tenant_settings_test.dart`

### Updated in place

- `lib/core/supabase/touristrike_models.dart`
- `lib/screens/auth/login_screen.dart`
- `lib/screens/auth/loading_screen.dart`
- `lib/screens/auth/web_portal_login_screen.dart`
- `lib/screens/subtenant/layouts/subtenant_admin_shell.dart`
- `lib/screens/subtenant/widgets/subtenant_sidebar.dart`
- `test/phase4_stabilization_test.dart`

## Migrations created/deployed

Created:

- `20260927005000_historical_schema_reconciliation.sql`
  - reviewed forward-only repair for the 55 classified historical ledger gaps
  - includes the verified-absent `20260926010000` settings/notification
    prerequisites needed by the Main Tenant settings migration, without a
    top-level production-row rewrite
  - enables 11 missing RLS switches and completes required policies
  - restores missing current indexes and timestamp triggers
  - completes same-day staged-payment and Phase 4 scope hardening without
    replaying obsolete wallet, sharing, or automatic-tour lifecycle code
  - performs no production-row rewrite; it aborts if the verified zero-row
    historical backfill precondition changes
- `20260927010000_role_architecture.sql`
  - temporarily accepts legacy and final roles
  - migrates every `profiles.role = 'admin'` row to `main_tenant`
  - installs the final constraint containing only `tourist`, `driver`,
    `subtenant`, `main_tenant`, and `administrator`
  - fails if any legacy profile remains
  - adds least-privilege role helpers and System Administrator profile/audit
    visibility
  - uses empty SECURITY DEFINER search paths with schema-qualified objects
  - does not grant the new role-check helpers to `anon`
- `20260927020000_main_tenant_settings.sql`
  - creates and scopes `provincial_office_details`
  - migrates existing provincial office/branding values
  - removes those duplicate columns from `admin_settings`
  - retargets required settings and provincial notifications to `main_tenant`
  - binds an inserted office province to the protected Main Tenant profile and
    prevents later owner/province changes
  - uses empty SECURITY DEFINER search paths with schema-qualified objects
- `20260927030000_administrator_portal.sql`
  - adds a role-guarded, read-only account directory joining profiles with
    Supabase Auth metadata
  - permits System Administrator inspection of city/municipal tenant identity
    and activation metadata
  - does not grant access to bookings, payments, tourism content, or Main
    Tenant business operations

Deployed from this role/portal series: **none**. CLI authentication and linking
to TourisTrike project ref `mvtqhsrdgtwdeootgjci` now work. The live ledger has
30 recorded migrations and 55 classified historical local-only versions. The
reviewed forward reconciliation migration and the three role/portal migrations
remain local-only. No migration was partially executed and no history entry was
changed during the 2026-09-27 continuation. Docker remains unavailable; live
inspection uses read-only Management API catalog queries.

## Tests and validation completed

- Root cause of the Flutter failure: PATH selected an outer Flutter 3.38.1 /
  Dart 3.10.0 checkout while a valid Flutter 3.41.2 / Dart 3.11.0 SDK existed
  at `C:\flutter\flutter`. The workspace now selects the valid SDK. Generated
  artifacts were cleaned and regenerated.
- `flutter doctor -v`: Flutter, Windows, Chrome, Visual Studio, connected
  devices, and network checks pass. The unrelated Android SDK path-with-spaces
  warning remains.
- `flutter pub get`: passed.
- `flutter analyze`: **0 errors**, 50 existing warnings, and 138 existing info
  lints (185 total diagnostics).
- Focused role/settings/navigation/Administrator tests: **21 passed**.
- Full `flutter test`: **321 passed, 0 failed**.
- `flutter build web --no-pub`: passed and produced `build/web`. The optional
  Wasm dry run reports existing third-party `dart:html`/`dart:ffi`
  incompatibilities; the normal JavaScript web release build succeeds.
- `dart format --output=none --set-exit-if-changed .` found 76 unrelated legacy
  Dart files that would be reformatted. They were intentionally not rewritten;
  every Dart file changed by this continuation was formatted.
- Static migration assertions passed for ordering, legacy conversion, the
  exact final role set, safe SECURITY DEFINER search paths, removal of
  unnecessary anonymous helper grants, settings data preservation, immutable
  provincial scope, municipality isolation, the Administrator RPC role guard,
  read-only behavior, Auth join, and transaction closure.
- Final Flutter search found no old `/screens/admin`, `ProvincialAdmin*`,
  `provincial_admin`, role-specific `Admin*` portal classes, or raw generated
  `role = 'admin'` application checks.

## Continuation verification matrix

| Item | State | Evidence / blocker |
| --- | --- | --- |
| Flutter SDK repaired | PASS | Workspace uses Flutter 3.41.2 / Dart 3.11.0; dependencies, tests, and build run successfully. System PATH still has an older machine-level entry. |
| `flutter analyze` | PASS | 0 errors; 50 warnings and 138 info lints remain. |
| `flutter test` | PASS | 321 passed, 0 failed. |
| Migration `010000` deployed | BLOCKED | CLI access works, but the reviewed historical reconciliation must be applied, verified, and recorded first. |
| Migration `020000` deployed | BLOCKED | Depends on `010000` and the historical reconciliation checkpoint. |
| Migration `030000` deployed | BLOCKED | Depends on the prior migrations and the historical reconciliation checkpoint. |
| Live `admin -> main_tenant` verified | BLOCKED | Migration is statically verified but not deployed. |
| Live five-role constraint verified | BLOCKED | Migration is statically verified but not deployed. |
| Administrator provisioning | BLOCKED | No developer UUID/email is designated; no account was guessed or changed. |
| Five-role routing | PASS | Full role/destination matrix and portal tests pass. |
| RLS isolation | BLOCKED | Live catalog identified 11 disabled RLS tables; the reviewed forward migration fixes them, but it is intentionally not deployed yet. |
| Main Tenant Settings | BLOCKED | Persistence mapping/tests pass, including `contact_number` isolation; live save/reload requires deployment. |
| Administrator portal runtime | BLOCKED | Widget runtime states pass; real Supabase data/RPC checks require deployment and a designated Administrator. |
| Database tests | BLOCKED | Read-only live catalog preflight passes, but the reviewed forward reconciliation and role/portal migrations are intentionally not deployed yet; Docker is unavailable. |
| Build validation | PASS | JavaScript web release build completed successfully. |

## Intentional compatibility and remaining `admin` references

- `AppRole.tryParse('admin')` temporarily reads a legacy value as
  `AppRole.mainTenant`; no application code generates `admin`.
- `current_profile_role()` temporarily returns the old `admin` token for a
  `main_tenant` so older deployed RPCs/policies that use this helper keep their
  provincial permissions. New authorization uses explicit helpers.
- `is_provincial_admin()` remains as a deprecated database compatibility alias
  to `is_main_tenant()` because many previously deployed policies depend on its
  function identity.
- Historical migration files retain their original `admin` references. Later
  migrations correct the live final state without rewriting migration history.
- Generic/business names such as `admin_settings`, `city_admin_*`,
  `approved_by`, notification channel `admin_updates`, and ordinary
  “administrative” wording remain where they are not the old role identity.

## Remaining work

1. Review and execute the documented forward-reconciliation command plan in
   `docs/SUPABASE_MIGRATION_RECONCILIATION.md`. Stop unless its post-check is
   completely green, then repair the 55 classified historical timestamps and
   the forward migration's history entry exactly as documented.
2. Confirm `npx supabase migration list` then shows only `20260927010000`,
   `20260927020000`, and `20260927030000` as local-only. Re-run the live
   dependency/conflict preflight and deploy those three in timestamp order.
3. After deployment, use a trusted service-role/admin database workflow to set
   a specifically designated developer account to `administrator`. No existing
   provincial account is promoted automatically, and there is intentionally no
   public self-promotion UI.
4. Verify after deployment:
   - no `profiles.role = 'admin'` rows remain;
   - the final role constraint contains exactly the five canonical values;
   - an existing provincial account routes to Main Tenant and can save/reload
     office, branding, policies, notification preferences, and password;
   - a seeded `administrator` can read account summaries/audit logs but cannot
     read provincial operational data through Main Tenant policies;
   - the Administrator portal loads Overview, Accounts, Tenants, Audit Log,
     and System Health from live data, and reports partial backend failures as
     degraded instead of showing fabricated health;
   - a subtenant remains restricted to its assigned municipality.
5. After production clients and operational RPCs are confirmed migrated, plan a
   later cleanup migration to remove the two documented database compatibility
   shims. Do not remove them during initial rollout.

## Exact next step

Follow the exact **Approved next-command plan (not executed)** in
`docs/SUPABASE_MIGRATION_RECONCILIATION.md`: apply only
`20260927005000_historical_schema_reconciliation.sql`, require the documented
read-only post-check to be completely green, and only then repair the 55
classified historical entries plus `20260927005000`. Run
`npx supabase migration list` and stop unless the only local-only entries are
the three role/portal migrations. Do not use `db push` before that checkpoint,
and do not provision an Administrator until a specific Auth UUID and matching
email are supplied.

The latest linked read-only preflight confirms this gate is still unmet: the
remote ledger has 59 local-only entries and the forward reconciliation schema
effects are absent. The three role-series migration files have no intrinsic
catalog conflict, but all remain blocked by this ordering prerequisite.

## Safe Administrator provisioning procedure

No documented account is designated as the System Administrator. Obtain the
intended developer's exact Auth UUID **and** email, verify that they identify
the same `auth.users` row, and only then run the following through the Supabase
SQL editor or another trusted database-owner workflow. Replace both
placeholders; never expose this as a client RPC:

```sql
begin;

update public.profiles p
set role = 'administrator'
where p.id = '<DESIGNATED_AUTH_UUID>'::uuid
  and exists (
    select 1
    from auth.users u
    where u.id = p.id
      and lower(u.email) = lower('<DESIGNATED_AUTH_EMAIL>')
  )
returning p.id, p.role;

-- Commit only when exactly one expected UUID is returned.
commit;
```
