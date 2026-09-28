# Supabase migration reconciliation — current checkpoint

## Tour feature deployment gate — 2026-09-28: DEPLOYED / RATE_CONFIGURATION_REQUIRED

**20260928000000 is deployed.** Its payment blocker is resolved; 92 applied migrations are aligned. Approved rates remain required for Baliwag, Bustos and Malolos, Bulacan. [Current deployment and payment evidence](supabase_tour_feature_gate_20260928.json). Earlier BLOCKED entries below are dated history; [archived blocked evidence](supabase_tour_feature_blocked_gate_20260928.json).

## Deployment verification — 2026-09-28: HISTORICAL_RECONCILIATION_COMPLETE

The historical repair '20260927230000' is deployed and live-verified. All four previous blockers are resolved. Migration history is **91 aligned applied / only '20260928000000' local-only**. The tour migration and all three manual-review Driver records are unchanged. [Deployment and live evidence](supabase_historical_deployment_complete_20260928.json). Earlier readiness/blocked sections below are dated history, superseded by this checkpoint.

## 2026-09-27 continuation

The September 25 audit below is retained as dated evidence. Its statement that
54 versions are Local-only is no longer the live migration-list state. A linked
`npx supabase migration list` on September 27 showed all 84 former local
versions recorded remotely, plus six applied Remote-only versions:
`20260926010000`, `20260927005000`, `20260927010000`, `20260927020000`,
`20260927030000`, and `20260927040000`. Only `20260928000000` was Local-only.
No history repair was performed during this checkpoint.

The six missing local files were restored without changing the database.
`20260926010000` came from `origin/main`; the other five were recovered in
statement order from applied `supabase_migrations.schema_migrations` records
because `supabase migration fetch --linked` failed on the CLI's IPv6 path.
A later `db push --linked --dry-run --skip-vault` succeeded and listed only
`20260928000000_tour_stay_waiting_and_tourist_reviews.sql`. Do not use the
CLI's suggested `migration repair --status reverted` on applied versions.

The applied `20260927005000_historical_schema_reconciliation` contains 151
recorded statements and explicitly restores previously missing legacy RLS,
selected policies and indexes, same-day payment guards, and municipal scope
rules. Read-only live checks found all eleven legacy tables named in the
September 25 audit now have RLS enabled. These checks do not certify every
former unresolved historical migration individually. The earlier per-version
findings remain below; each still needs a current effect/successor verification
record before the historical audit can be marked complete. Recorded migration
history alone is insufficient evidence.

Read-only linked schema checks confirmed the required booking, itinerary,
arrival, payment, fare, notification, audit, role, and journey objects exist.
`emit_tour_notification` accepts the seven-argument calls used by the new
migration through its defaulted eighth argument. The waiting ledger, tourist
review table, and tour-rate column were absent, as expected. A copy of
`20260928000000` ran to completion in a transaction with a one-second lock
timeout and explicit `ROLLBACK`. That proves SQL compatibility with the live
schema at that instant; it does not verify deployed feature behavior.

Read-only authenticated role probes found one `administrator`, one
`main_tenant`, three `subtenant`, five `driver`, seven `tourist`, and zero
stored legacy `admin` profiles. An active-fare Subtenant saw one municipal
fare and zero other-city fare or booking rows. The Administrator saw zero
package bookings and zero fare rows. Main Tenant access uses
`is_main_tenant()`; `current_profile_role()` returns `admin` for compatibility.
An older permissive `profiles_select_authenticated` policy still makes profile
rows readable to authenticated users; its necessity and scope need separate
review.

Deployment is **blocked**. The full historical effect audit is unfinished,
and the two active fare municipalities have no tour-specific rate configured
because `tour_waiting_fee_per_15_minutes` does not yet exist. The new booking
snapshot trigger requires an active tour rate. Applying it before owner-approved
municipal values and a staged configuration plan would block new package
bookings. Next, certify the remaining historical effects or obtain the
applying team's verification ledger, agree both municipal tour rates with their
offices, deploy the reviewed migration, and configure rates before releasing
the Flutter booking flow. No production rate, account, booking, payment, or
review was modified for testing.

Flutter verification: `dart format .` completed, `flutter analyze` reported
zero errors and 183 existing warnings/info notices, and the full `flutter test`
suite passed 298 tests. Focused isolated PostgreSQL checks passed 50 waiting/
review, 12 explicit-slide, and 77 automatic-tour checks. These local checks
do not substitute for live tour, payment, notification, or RLS tests after
deployment.

## Earlier audit — 2026-09-25

At the 2026-09-25 checkpoint, automatic-tour deployment succeeded: 22
verified historical entries were repaired, and the new migration was executed
and recorded. Of the 84 local migrations present at that checkpoint, 30 had
remote records and **54 remained unresolved**. Later local migration files are
accounted for in the continuation checkpoint below. There are no remote-only
versions, and normal `db push` remains blocked.

Only `20260927000000_automatic_tour_progression.sql` was executed against the application schema, using `supabase db query --linked --file` and its existing transaction, followed by verified `migration repair --status applied`. No historical SQL was replayed, migration file edited/moved/deleted, database reset, RLS disabled, or application code changed in this reconciliation task. Earlier application changes remain untouched.

## 2026-09-27 continuation checkpoint (review complete; not deployed)

The live ledger remains unchanged at **30 recorded migrations**. All **55**
historical local-only timestamps now have a reviewed disposition. This is the
original set of 54 plus the later-added but still local-only
`20260926010000_provincial_admin_settings.sql`. No migration
repair, `db push`, reset, or live DDL/DML was run during this continuation.

### Final role-series preflight attempt: BLOCKED by live checkpoint state

A later read-only verification against linked project
`mvtqhsrdgtwdeootgjci` found that the claimed history-repair checkpoint is not
present remotely. `npx supabase migration list` still reports the 55
historical versions, `20260927005000`, and the three role-series migrations as
local-only (**59 local-only total**). The forward post-check also still reports
the unreconciled state: 11 disabled-RLS tables, 12 missing settings columns,
13 missing indexes, 16 missing triggers, the expected policy/function gaps,
and zero eligible same-day backfill rows. Linked error-level database lint
still returns the same seven errors targeted by `20260927005000`.

The final read-only catalog preflight for `010000`/`020000`/`030000` found no
intrinsic duplicate-object or incompatible-signature conflict. Existing role
data is valid for the conversion (one `admin` profile, zero unexpected profile
or conversation roles, and zero persisted `admin` labels in the other current
role-label columns). However, `020000` is not executable against the current
live schema because all twelve `20260926010000` settings columns and both
predecessor notification functions are absent. Those prerequisites are
supplied by the unapplied forward reconciliation. Consequently all three
migrations remain blocked by ordering; none was deployed or edited.

Read-only evidence:

- `build/migration-reconciliation-20260927/role_portal_preflight.sql`
- `build/migration-reconciliation-20260927/role_portal_preflight_details.sql`
- `build/migration-reconciliation-20260927/post_forward_verification.sql`

Focused role/settings/Administrator/reconciliation tests pass **21/21**, and
`git diff --check` passes. Re-run the approved reconciliation commands below;
do not start the role-series deployment until `migration list` contains only
`20260927010000`, `20260927020000`, and `20260927030000` as local-only and the
two role-series preflight queries are clean.

The reviewed forward migration is
`20260927005000_historical_schema_reconciliation.sql` (SHA-256
`14B435F0268CB3409639C4A95686780A101F2B31030E75D835600AC8ECFD3F96`). It
contains only the missing current behavior and explicit successors needed to
make the historical ledger truthful:

- enables RLS on the 11 public tables found exposed and adds the four missing
  insert policies required before those switches can be enabled;
- restores policies for the two already-RLS-enabled lookup/content tables that
  currently have no policies (`tourism_categories`, `tourism_policies`);
- restores 13 missing historical performance indexes and nine `updated_at`
  triggers; an existing equivalent tourist-spot-image index is reused;
- applies the reviewed same-day/advance staged-payment function slices from
  `20260831010000` while excluding lifecycle functions superseded by
  `20260927000000`;
- applies the reviewed Phase 4 scope/policy/index slice from `20260905030000`;
- supplies the twelve settings columns, self-scope policy, nine functions and
  seven triggers from local-only `20260926010000`, which are absent live but
  are required inputs to `20260927020000`; its two SECURITY DEFINER helpers are
  explicitly unavailable to client roles;
- retires five broken, unused SECURITY DEFINER legacy RPCs that have verified
  replacements, repairs the actively used registration RPC's UUID/text
  mismatch, and repairs the service-role payout result RPC to use live columns;
- performs no top-level production-row update. The historical same-day
  backfill is replaced by a fail-closed assertion because the live eligible
  row count is zero.

Read-only preflight results: no required columns or functions are missing; all
three required payment triggers exist and are enabled; the eligible backfill
count is zero. The pre-apply post-check captures exactly 11 missing RLS
switches, eight absent policies plus one existing policy-definition mismatch,
13 missing indexes, 16 missing triggers, twelve missing settings columns, ten
false payment/scope predicate checks, and the expected false historical
function checks (including all nine absent `20260926010000` functions). Linked
`db lint` additionally reports the same seven broken function
definitions: the five retired RPCs plus the two repaired RPCs. These are the
expected deltas implemented by the forward migration.

Local verification after authoring the initial forward migration: the extracted
payment source slices match byte-for-byte after line-ending normalization; the
Phase 4 slice matches except for one deliberately omitted duplicate index whose
live equivalent was verified; the migration has one `begin`/`commit` pair and
excludes all listed obsolete lifecycle/wallet/sharing definitions; its focused
tests pass **5/5**; the complete Flutter suite passes **321/321**; and
`flutter analyze` reports **0 errors** (50 existing warnings and 138 info
lints). These checks were rerun after adding the newly discovered
`20260926010000` dependency, using the workspace's documented Flutter 3.41.2 /
Dart 3.11.0 SDK rather than the stale outer SDK on the machine PATH.

The remaining verification boundary is PostgreSQL server parsing of the new
transaction. Docker/local PostgreSQL is unavailable, and the Management API
does not expose a read-only parse-only mode for DDL. Executing the transaction
inside a rollback would still acquire production locks and run DDL, so it was
not used. This checkpoint therefore stops before live application and history
repair; the first command below is the controlled deployment step.

### Final classification of the 55 historical local-only versions

`Represented` means current live objects or a verified later successor already
provide the migration's durable behavior. `Retired` means the old behavior was
deliberately removed/replaced and must not be replayed. `Forward` means the
remaining current behavior is supplied by `20260927005000`; its history entry
must not be repaired until that forward migration passes the post-check.

| Version | Disposition | Evidence / successor |
| --- | --- | --- |
| `20260508000000` | Forward + represented successors | Core relations exist; deprecated `payments` has a verified `payment_records` successor. Forward migration restores the missing RLS switches, policies, indexes and timestamp triggers. |
| `20260511000000` | Represented | Application table/index/policies exist; `profiles_insert_own` is the current successor to the old self-insert policy. |
| `20260513000000` | Forward + superseded | The live bigint overload is invalid against the UUID table. Forward migration installs the app-compatible text-ID RPC with the current Main Tenant guard; the separate legacy activation helper remains retired. |
| `20260513001000` | Forward + superseded | Same registration-RPC repair as `20260513000000`; the absent legacy activation helper is replaced by the current assignment/profile flow and is not recreated. |
| `20260516000000` | Represented | All 16 inventoried package-customization/Google-place objects are present. |
| `20260517000000` | Retired/superseded | Wallet tables are `_deprecated_*`; GCash/payment-record architecture replaced wallet helpers. |
| `20260518093000` | Retired/superseded | Legacy wallet cash-in RPC is absent and explicitly retired by `20260725000000`. |
| `20260518130000` | Represented | All three booking/payment columns and constraints are present. |
| `20260519000000` | Retired/superseded | Old `payments` table/policies were replaced by `payment_records`; restoring broad legacy policies would be unsafe. |
| `20260519020000` | Forward + represented/retired | Tracking functions match and current activity objects/policies exist. Forward migration removes the two still-live but invalid wallet helpers; wallet-specific columns/policies remain retired. |
| `20260519030000` | Forward + represented/retired | Activity flow has verified current successors. Forward migration removes the invalid debit/credit helpers; `reference_key` belongs to the retired wallet system. |
| `20260519040000` | Represented | Schedule/emergency/message objects are present; current profile-visibility policies supersede the old assigned-driver/chat policy. |
| `20260520093000` | Represented | Both functions match and current message/activity policies supersede the missing legacy profile-policy name. |
| `20260520120000` | Represented | 30/31 named effects are present; current profile-visibility policy supersedes the sole old policy name. |
| `20260520143000` | Represented | All ten itinerary table/index/policy/trigger effects are present. |
| `20260520150000` | Represented | All nine booking-location/itinerary cleanup effects are present. |
| `20260520160000` | Represented | Group/live-tracking tables and columns exist; later participant-scoped RLS replaces the six permissive `*_read_all`/write policies. |
| `20260520170000` | Forward + represented successor | Dispatch behavior and schema effects are represented by later acceptance RPCs; forward migration removes the invalid superseded `driver_accept_group_booking` overload. |
| `20260520180000` | Represented | Acceptance RPC has a verified successor; later participant policies replace the three permissive booking-driver policies. |
| `20260520190000` | Represented | Driver package-job RPC and trigger effect match. |
| `20260521020000` | Represented | Populate helper and both itinerary RLS effects match. |
| `20260521030000` | Represented | Itinerary update policy is present. |
| `20260521040000` | Represented | Both completion RPCs have verified successors and the driver-access policy is present. |
| `20260521050000` | Represented | Driver-review table, function, indexes, policies and trigger are present. |
| `20260521090000` | Retired/superseded | Fare/storage behavior is represented by `subtenant_fare_settings` and current bucket policies; obsolete admin-setting columns are not restored. |
| `20260522000000` | Represented | Sharing tables/policies/triggers are present; the RPC is superseded by the verified five-argument read-only implementation. |
| `20260522010000` | Retired/superseded | Anonymous direct-table policies were deliberately removed by `20260907010000/020000`; token RPC access is the verified successor. |
| `20260522020000` | Retired/superseded | Obsolete two-argument sharing RPC was replaced by the verified five-argument RPC. |
| `20260522080000` | Represented | Emergency table/function/current policies and trigger are present; current scoped staff policy supersedes the old admin policy name. |
| `20260523000001` | Represented | Package-review and itinerary-access effects are present; completion helpers have verified successors. |
| `20260523100000` | Represented | Review/profile helpers and both municipality-scoped policies are present or have verified successors. |
| `20260523110000` | Represented | Non-recursive profile helpers/policies are present or superseded by the current profile-visibility implementation. |
| `20260523123000` | Represented | All nine schema effects are present and completion helpers have verified successors. |
| `20260523133000` | Represented | Driver/subtenant status synchronization effect is present. |
| `20260523140000` | Represented | All 20 fare-setting table/constraint/index/policy/trigger effects are present. |
| `20260725000000` | Represented | All 25 GCash trail schema effects exist; six functions match and three have verified later successors. |
| `20260805000000` | Represented | All 12 convoy data-model effects exist; functions match or have verified successors. |
| `20260805010000` | Represented | Participant-history activity RLS successor is present. |
| `20260805020000` | Represented | Journey-state helper matches and progression RPC has a verified automatic-tour successor. |
| `20260821000000` | Represented | Six functions match, 21/22 named effects exist, and the current scoped cancellation policy supersedes the old policy name. |
| `20260827000000` | Forward + represented successors | All 21 schema effects exist; sharing and lifecycle functions have verified successors. Forward migration supplies the missing unified payment guard/requirements behavior. |
| `20260827010000` | Forward | Forward migration installs the final unified client-write guard, superseding this intermediate guard. |
| `20260827030000` | Represented | All 50 PayMongo foundation table/column/constraint/index/policy/trigger effects are present. |
| `20260827060000` | Forward + represented successors | Connected payment functions are present; forward migration supplies the final unified group-cash implementation. |
| `20260828000000` | Forward | Forward migration installs the final unified booking guard, superseding this intermediate hardening version. |
| `20260830010000` | Represented | Debug registration table and reset RPC effects are present. |
| `20260831000000` | Represented | Automatic developer-test table/function effects are present. |
| `20260831010000` | Forward + represented successors | Existing triggers/helpers and later automatic-tour lifecycle successors are preserved; forward migration supplies only the missing staged-payment functions. Zero rows need the omitted historical backfill. |
| `20260902000000` | Forward + represented successors | All 19 audit schema effects exist and 11/12 functions match or have successors; forward migration supplies the final authenticated group-conversation helper. |
| `20260905000000` | Forward + represented successors | All 90 scope/settings effects exist and 15/17 functions match or have successors; forward migration supplies the two final Phase 4 helper bodies. |
| `20260905010000` | Represented | All three office-identity effects exist and both functions have verified later successors. |
| `20260905020000` | Represented | Both functions and all five classification-review effects match. |
| `20260905030000` | Forward | Forward migration copies the reviewed Phase 4 helper, policy, grant and index slice exactly. |
| `20260924000000` | Represented | Both notification tables, constraints, grants, publication/trigger effects and all functions are present directly or through recorded `20260925000000` successors. |
| `20260926010000` | Forward | Read-only catalog evidence confirms all twelve settings columns, all nine functions and all seven triggers are absent, while `own_settings` is the older broad policy. The forward migration supplies these prerequisites without rewriting rows; `20260927020000` then migrates office identity and replaces the legacy-role notification behavior. |

### Approved next-command plan (not executed)

Run these only in this order and stop on the first failed verification:

```powershell
npx supabase db query --linked --file supabase/migrations/20260927005000_historical_schema_reconciliation.sql
npx supabase db query --linked --file build/migration-reconciliation-20260927/post_forward_verification.sql --output json --agent=no
npx supabase db lint --linked --schema public --level error --fail-on error
```

The post-check must return empty `missing_settings_columns`, `missing_rls`,
`missing_policies`, `missing_indexes`, and `missing_triggers`; every
payment/scope and historical function check must be `true`; and
`eligible_same_day_backfill_rows` must remain `0`. Then run
`npx supabase db lint --linked --schema public --level
error --fail-on error`; it must return no errors. Only then record
the forward migration and the 55 verified historical versions:

```powershell
npx supabase migration repair --linked --status applied 20260508000000 20260511000000 20260513000000 20260513001000 20260516000000 20260517000000 20260518093000 20260518130000 20260519000000 20260519020000 20260519030000 20260519040000 20260520093000 20260520120000 20260520143000 20260520150000 20260520160000 20260520170000 20260520180000 20260520190000 20260521020000 20260521030000 20260521040000 20260521050000 20260521090000 20260522000000 20260522010000 20260522020000 20260522080000 20260523000001 20260523100000 20260523110000 20260523123000 20260523133000 20260523140000 20260725000000 20260805000000 20260805010000 20260805020000 20260821000000 20260827000000 20260827010000 20260827030000 20260827060000 20260828000000 20260830010000 20260831000000 20260831010000 20260902000000 20260905000000 20260905010000 20260905020000 20260905030000 20260924000000 20260926010000 20260927005000
npx supabase migration list
```

At that checkpoint, the only local-only migrations should be
`20260927010000`, `20260927020000`, and `20260927030000`. Re-run their live
dependency/conflict preflight before deploying them in order. Do not provision
an Administrator account without an explicitly supplied Auth UUID and email.

## Repaired history entries

Each entry below had all of its relevant current effects verified, including documented successors. An applied repair records the verified current state; it does not assert that this exact old file was originally executed. The two completion bundles were repaired only after the new migration supplied their verified successors.

| Version | Evidence / reason |
| --- | --- |
| `20260511001000` | Application RPC body, signature, defaults, security-definer/search_path and execute grants match. |
| `20260518120000` | children is integer NOT NULL DEFAULT 0 with the validated nonnegative constraint. |
| `20260519010000` | All six pickup/drop-off address and coordinate columns match type, nullability and defaults. |
| `20260520162000` | Acceptance RPC is superseded by the verified 20260725000000 implementation; authenticated access retained. |
| `20260521010000` | All three completion RPC signatures have verified successors (including the newly deployed automatic-tour implementation); authenticated grants match. |
| `20260522030000` | Shared-trip RPC superseded by verified 20260907020000; retired overloads absent and guest/authenticated grants match. |
| `20260522040000` | Shared-trip RPC superseded by verified 20260907020000; obsolete overloads absent and grants match. |
| `20260805030000` | cancel_driver_slot matches exactly; accept_package_booking matches its P0 successor; grants match. |
| `20260827020000` | Atomic creation RPC matches recorded successor 20260830000000; PUBLIC revoked and authenticated granted. |
| `20260827040000` | All nine functions match directly or verified successors. Permissions verified, including the deliberately authenticated wrapper introduced by recorded 20260829010000. |
| `20260827050000` | Payout/refund RPCs match directly or verified successor; exact enabled triggers and service/client permissions verified. |
| `20260830020000` | All five debug RPCs match directly or verified successors; internal helpers remain inaccessible to client roles. |
| `20260903000000` | Diagnostics RPC body, signature, attributes and grants match. |
| `20260903001000` | Read-only identity/seed check confirms the intended QA account and enabled developer-test registration; no account data changed. |
| `20260906000000` | After automatic-tour deployment, all ten functions match or have verified successors; actual departed_at, milestone trigger, grants and review publication verified. |
| `20260906010000` | Advance function and GPS/debug guard successors verified; debug RPC grants match. |
| `20260906020000` | Downpayment predicate matches; PUBLIC, anon and authenticated execution revoked. |
| `20260906030000` | GPS-verified debug wrapper and client-role permissions match. |
| `20260906040000` | Radius helper, proximity guard and arrival fallback match before deployment; later fallback superseded by the deployed migration; helper grants match. |
| `20260906050000` | Remaining-payment guard function, exact enabled trigger and restricted execution match. |
| `20260907010000` | Verified convoy-sharing successor preserves token access; anonymous direct table policies are absent and RPC grants match. |
| `20260907020000` | Shared-trip function body, signature/defaults/security, RPC grants and removal of anonymous table policies match. |

## Deployment and verification

- Deployed migration SHA-256: `cad0311877d1ff8e7f6f00f870c65e1f8162d190415d1b4784e61feb1f3eb5c2`. All 84 original SQL file hashes are unchanged.
- All 11 deployed function bodies, signatures, argument defaults, volatility, security-definer flags and search paths match. The evidence table, timestamp field, two guards and active five-minute cron job exist.
- 174 history certification checks and 23 live automatic-tour deployment checks passed. SQL is evaluated read-only for metadata checks; function comparisons preserve quoted literal content.
- Local PostgreSQL regressions: automatic tour 77/77, event-driven trip 86/86, notifications 64/64, service area 46/46: **273 passed, 0 failed**. Automatic-tour scenarios also passed **77/77** with the deployed payment predicates/finalizer substituted into the isolated fixture.
- Live P0 regression: **22 passed, 2 failed**, identical before/after. Failures: the payment update policy still exists; an old guest-GPS source-string assertion no longer matches the current convoy RPC (the current function does clear terminal GPS).
- Live PayMongo regression: **31 passed, 1 failed**, identical before/after; its service-only entry-point assertion predates the recorded authenticated wrapper. The suite also declares 30 tests while executing 32. These suites were run in rollback transactions; their temporary pgTAP extension was not retained.
- Full phase-4 RLS regression was not run: its required cross-city dispute fixture is absent. The read-only/rollback fixture probe confirmed the gap; no production fixture was created.
- Fingerprints covered **66 existing tables / 1413 rows**. No table lost rows; **62/66** tables retained identical full-row hashes. Original booking fields (excluding the new column), all seven assignments, payments, refunds, storage and service-area data match. The remaining changes were one appended interruption audit, activity metadata, live location and auth metadata during the live verification window; the latter two cannot be attributed from aggregate hashes alone.
- Cron ran successfully and marked one overdue tour interrupted, adding one audit row. All original booking status/completion/payment fields remained byte-equivalent in the fingerprints: no time-based false completion occurred.
- All **177 existing public/storage policies**, existing table RLS flags/ACLs, constraints, storage buckets and existing trigger definitions are unchanged. Six functions were added and exactly the five existing functions named in this migration were replaced. The existing booking publication now includes the added timestamp column.
- Pre-existing security debt remains: RLS is disabled on eleven public tables (listed below). Preservation of the baseline is not certification that the baseline is secure.
- Final `supabase db push --linked --dry-run --skip-vault` exited **1** with `LegacyDbPushMissingRemoteError`, listing exactly the 54 unresolved versions. No unsafe suggested flag was used.

## Unresolved history and real drift

Not every missing entry represents missing schema. The remaining files contain a mixture of retired functionality, present objects, changed signatures/policies, unverified data backfills, and genuinely missing changes. They were **not** falsely marked applied or hidden by removing them from the migration directory. A clean normal push cannot be certified within a history-only repair while these non-obsolete effects remain missing.

- `20260508000000`: confirmed partial bootstrap. Existing disabled-RLS tables: `admin_settings`, `driver_details`, `driver_documents`, `ride_feedback`, `ride_reviews`, `tour_package_day_items`, `tour_package_days`, `tour_package_spots`, `tour_package_views`, `tourist_spot_images`, `tourist_spot_views`.
- `20260831010000`: confirmed missing portions of unified same-day payment enforcement. Do not replay its old lifecycle definitions over automatic-tour functions.
- `20260905030000`: confirmed missing authorization/index changes. Do not mark it applied to silence the CLI.
- Wallet cash-in and older sharing signatures are obsolete. They were neither replayed nor falsely certified. A future explicit baseline retirement must preserve their source and carry any still-needed mixed changes into forward migrations.
- The safe path to a clean queue is a reviewed baseline/retirement decision plus new forward migrations for genuinely missing security/payment behavior. This task does not introduce those unrelated behavior changes.

| Unresolved version | Audit finding |
| --- | --- |
| `20260508000000` | Confirmed partial: eleven original public tables still have RLS disabled, many original indexes/triggers are absent, IDs/types differ, and payments was renamed. Must not certify or replay this bootstrap. |
| `20260511000000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260513000000` | The local text-signature approval/activation pair is not deployed as written: live approval takes bigint and activate_approved_city_admin is absent. |
| `20260513001000` | Same approval/activation signature drift; do not overwrite the live approval implementation. |
| `20260516000000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260517000000` | Wallet tables were renamed to _deprecated_* and wallet helper functions retired by the GCash migration. Do not recreate the obsolete wallet system. |
| `20260518093000` | Obsolete cash-in RPC is absent and explicitly dropped by 20260725000000. Leave unrecorded; never replay to restore wallet functionality. |
| `20260518130000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260519000000` | Original payments table is now _deprecated_payments; its original broad staff policies cannot be certified by matching a current table name. |
| `20260519020000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260519030000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. Unmatched functions: `deduct_wallet_balance`, `credit_driver_wallet`. |
| `20260519040000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260520093000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260520120000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260520143000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260520150000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260520160000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260520170000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260520180000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260520190000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260521020000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260521030000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260521040000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260521050000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260521090000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260522000000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. Unmatched functions: `get_shared_trip_details`. |
| `20260522010000` | Original anonymous direct-table policies were deliberately removed by the verified read-only sharing successors. Mixed publication/function/policy bundle is not independently certified. |
| `20260522020000` | Obsolete two-argument shared-trip signature was replaced by the verified five-argument RPC. Do not replay the signature downgrade. |
| `20260522080000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260523000001` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260523100000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260523110000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260523123000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260523133000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260523140000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260725000000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260805000000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260805010000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260805020000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260821000000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260827000000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. Unmatched functions: `guard_package_booking_client_write`, `ensure_booking_payment_requirements`, `get_shared_trip_details`. |
| `20260827010000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. Unmatched functions: `guard_package_booking_client_write`. |
| `20260827030000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260827060000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. Unmatched functions: `prepare_group_cash_remaining_balance`. |
| `20260828000000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. Unmatched functions: `guard_package_booking_client_write`. |
| `20260830010000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260831000000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260831010000` | Confirmed partial: live same-day payment paths differ from this migration. ensure_booking_payment_requirements and remaining-payment predicates/finalizer still exempt non-advanced bookings; validation/checkout/cash/debug payment paths differ. |
| `20260902000000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. Unmatched functions: `ensure_booking_group_conversation`. |
| `20260905000000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. Unmatched functions: `subtenant_can_access_payment_record`, `ensure_booking_group_conversation`. |
| `20260905010000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260905020000` | Mixed historical effects are not fully certified. Named-object presence or matching functions alone does not establish all columns, constraints, policies, grants and data backfills. |
| `20260905030000` | Confirmed partial: payment scope helper and group-conversation authorization differ; three intended indexes are absent by name. Missing checks must be carried into a new forward migration, not silently marked applied. |
| `20260924000000` | Notification functions match directly or recorded 20260925000000 successors and named DDL is present, but the entire mixed table/constraint/column-grant/publication bundle was not certified. No blanket applied marker. |

Full per-file hashes, function comparisons, DDL-name inventory and repair checks: [audit ledger](supabase_migration_reconciliation_20260925.json). DDL inventory booleans record name presence only; a missing old name can be a deliberate rename/removal, and presence alone is never treated as proof of a complete migration. Raw catalog snapshots and aggregate fingerprints are kept locally under ignored `build/migration-audit/`.

## September 28 effect certification checkpoint

The [per-version historical effect ledger](HISTORICAL_MIGRATION_EFFECT_LEDGER.md) records the intended effect, [728 live named-object checks](supabase_historical_catalog_20260928.json), [current definitions](supabase_historical_definition_snapshot_20260928.json), [156 function identities and successors](supabase_historical_function_audit_20260928.json), [constraint findings](supabase_historical_constraint_audit_20260928.json), and [54/54 source/recorded-statement matches](supabase_historical_statement_match_20260928.json). Its current decisions for the **54** formerly unresolved migrations are **8 VERIFIED_PRESENT, 34 VERIFIED_SUPERSEDED, 1 INTENTIONALLY_OBSOLETE, 10 MISSING_EFFECT_REQUIRES_FORWARD_FIX, 1 STILL_NEEDS_REVIEW**. The older table above records the earlier audit and is superseded by the linked ledger for current decisions.

The remaining review case is `20260523133000`: three Driver profiles say `pending` while their linked Driver details say `approved`. Later profile updates exist, but there is no field-level status history or owner decision proving whether this is a missed backfill or an intentional later change. No account status was changed. Ten missing-effect rows cover confirmed profile INSERT/itinerary authorization defects (six rows, addressed by the local forward migration) and the separately scoped broad profile SELECT policy (four rows, deferred to the [profile security review](ROLE_ARCHITECTURE_REFACTOR.md)). The bootstrap and retired wallet objects were evaluated against current successors rather than replayed. The same-day payment functions and phase-four scope functions now match their intended bodies after `20260927005000`; the old spot-image index has an equivalent live index.

The local [20260927230000 forward repair](../supabase/migrations/20260927230000_historical_schema_reconciliation.sql) contains only the confirmed profile INSERT and itinerary RLS corrections. Its [isolated SQL regression](../supabase/tests/historical_reconciliation_regression.mjs) passed six authorization checks. A live rollback-only preflight passed and showed the unrelated Driver itinerary read changing from three rows to zero; the transaction was rolled back. A follow-up live query found zero applied `20260927230000` rows, the original profile INSERT and self-bound itinerary policies still present, and the replacement profile INSERT policy absent. `npx supabase migration list` shows every earlier local version aligned with remote history and exactly two local-only versions: `20260927230000`, then `20260928000000`. No historical version was falsely marked applied, no source migration was replayed, and no production row or schema was changed by this review. Resolve Driver-status provenance and the dedicated profile SELECT security correction, review/deploy the repair, verify live authorization, then review/deploy the tour feature and run its live checks. **Status: BLOCKED — HISTORICAL REVIEW INCOMPLETE.**

## Final historical security review — 2026-09-28 (supersedes the checkpoint above)

The existing [effect ledger](HISTORICAL_MIGRATION_EFFECT_LEDGER.md) now contains **8 VERIFIED_PRESENT, 35 VERIFIED_SUPERSEDED, 1 INTENTIONALLY_OBSOLETE, 10 MISSING_EFFECT_REQUIRES_FORWARD_FIX, 0 STILL_NEEDS_REVIEW**. The last entry, `20260523133000`, is superseded by the exact live `20260827000000` package-acceptance workflow. Its one-time profile-cache backfill did not create a permanent synchronization invariant. All three current Driver cache discrepancies remain **REQUIRES_MANUAL_REVIEW** with no automatic account changes; their provenance is ambiguous, but they do not establish a missing surviving migration effect and do not block this schema/security repair.

The undeployed [20260927230000 repair](../supabase/migrations/20260927230000_historical_schema_reconciliation.sql) now represents all ten missing-effect rows, including the dedicated broad profile SELECT correction. Full profile rows are limited to self and geographic operational staff. Participant/client queries use a fixed-column identity RPC; contact is returned only for active assignments or scoped staff. Administrator account oversight retains the existing restricted RPC. A conversation identity guard prevents clients from inventing/repointing a relationship to gain profile visibility. The [canonical matrix and source-query trace](ROLE_ARCHITECTURE_REFACTOR.md) define the exact access.

Verification: **48 isolated SQL/RLS checks**, **3 focused client tests**, zero Dart errors with six existing warnings in the eight analyzed files, and **PASS** for the live rollback-only preflight. Live reads covered 17 real actors, 172 unrelated pairs, 8 booking identity pairs and 20 messaging identity pairs, plus Administrator oversight and itinerary/INSERT checks. [Pre/post evidence](supabase_profile_security_review_20260928.json) shows matching data/policy/grant hashes; all four new functions and the replacement policies remain absent from production. No production data/schema changes persisted. No Driver account, historical source, tour feature behavior, or tour feature migration was changed.

`npx supabase migration list`: 90 aligned applied versions; only `20260927230000` and `20260928000000` are local-only, in that order. Do not deploy either in this phase. Future dependency: historical repair → verify live profile/itinerary authorization → release matching client identity queries → independently review/deploy tour feature → approved municipality rate configuration → live feature regression. The RPC must exist before releasing its new client queries. Driver manual operational review stays separate.

**READY_TO_DEPLOY_HISTORICAL_RECONCILIATION.** This records readiness of the local correction. The production broad policy still exists until a separately authorized deployment and live verification. Tour-feature readiness remains subject to its existing rate/release gates.


### Deployment attempt verification — 2026-09-28T05:58:54.560136+00:00

**Status: BLOCKED; deployment timestamp: none.** Migration history remains 90 aligned applied versions, with only `20260927230000` and `20260928000000` local-only. Both migration SHA-256 values match the reviewed checkpoint. The final source review found no waiting/rating feature schema, production row deletion/backfill, deprecated wallet restoration or unexpected source changes. No database DDL/DML or history repair was issued.

The original 48 isolated SQL checks pass. Nine additional deployment gates produce five passes and four failures: Driver self-profile INSERT is accepted; a Main Tenant without province sees two itinerary fixture rows; a Main Tenant sees one foreign-province itinerary row; a Subtenant sees one same-city foreign-province itinerary row. Staff/admin self-insertion, insertion for another user, provincial Main Tenant itinerary reads and foreign-municipality Subtenant denial pass. These are local fixture results, not post-deployment certification.

Fresh live read-only checks confirm the broad `profiles_select_authenticated USING (true)` policy still exists, all four new functions remain absent, and neither pending version is remotely applied. The current Subtenant booking helper checks package city only. Profile, Driver-details/application and conversation hashes match the prior rollback snapshot. All three Driver records (`59a7c2c3…`, `a1b8f8e3…`, `a912c958…`) remain unchanged and **REQUIRES_MANUAL_REVIEW**. Production data changes/anomalies caused by this attempt: NONE. Existing profile exposure and previously documented status discrepancies remain unresolved.

Focused Flutter tests: **3 PASS**. Full `flutter test`: **301 PASS**. `flutter analyze`: **0 errors / 48 warnings / 135 info** (exit 1 for lint findings; no client source changed). `dart format .` completed successfully on 238 files, changing 66; their exact pre-run source bytes were restored to preserve existing work and avoid unrelated formatting edits. No new client changes were required or made. SQL tests and documentation are the only tracked changes in this attempt.

Post-deployment SQL/RLS, live repaired-backend Flutter/screens, and live new SECURITY DEFINER ownership/grant checks were **not run**, because the repair was not deployed. The previous rollback-only identity/contact/conversation/Administrator/anonymous evidence remains dated preflight evidence. It cannot certify the additional itinerary province gates. Historical classifications remain 8 present / 35 superseded / 1 obsolete / 10 missing requiring forward correction / 0 unreviewed.

Required next work: resolve Driver provisioning versus current signup, correct the itinerary municipal/provincial scope in the pending historical repair, rerun the failed gates and rollback preflight, then selectively deploy only `20260927230000` after the pre-deployment gates pass. `20260928000000` stays untouched and must not be deployed in this phase. **HISTORICAL_RECONCILIATION_COMPLETE has not been reached.**


### Completed deployment verification — 2026-09-28T06:20:45.845209+00:00

**HISTORICAL_RECONCILIATION_COMPLETE.** Successful CLI deployment receipt: **2026-09-28T06:14:22.870Z**. An isolated deployment directory copied the 90 already applied migrations and the exact tested repair; it excluded the tour migration. The supported CLI dry run selected only '20260927230000', and the actual push applied only that version. No original migration was renamed/reordered, no old migration replayed, and no already aligned history repaired. Live history confirms 91 applied versions and only '20260928000000' local-only.

Driver OTP signup upserts only 'id' and Tourist/Driver 'role'; normal onboarding supplies personal/contact/document fields. Legitimate Driver provisioning stays allowed, with pending/false approval defaults. Owner approval fields are now guarded on profiles, Driver details and applications, including INSERT and UPDATE. Cross-user profile INSERT and staff/admin self-assignment are denied. Existing staff accreditation writes remain subject to their existing RLS. No existing Driver status was changed or backfilled.

Itinerary staff reads use the existing authoritative Main Tenant 'profiles.province' and active Subtenant office 'city + province', matched to the booking province and linked package city. Missing, blank or malformed Main Tenant province fails closed. Same-city/different-province Subtenant access is denied. The broad pending-job Driver itinerary preview policy was removed; assigned/accepted participants retain access. Staff gain no itinerary INSERT/UPDATE/DELETE or lazy-initialization rights. The existing 'ensure_booking_itinerary' body now authenticates and checks actual participation before reading or creating items. Arrival/completion RPCs already bind assignments and stop IDs to the same booking; their feature logic is unchanged. Existing pending-job clients catch unavailable itinerary reads/initialization and retain their placeholder behavior.

**Verification:** 93/93 isolated SQL gates; rollback-only live preflight PASS (26 focused gates, 17 real account scopes, 172 unrelated pairs, 8 booking identities, 20 messaging identities). All 66 public-table data hashes, auth-user hash, schema and policy/function snapshot fields matched exactly after rollback; replacement functions remained absent before deployment. Post-deployment live checks repeat the 26 gates, independently compare itinerary visibility for all 17 real accounts, verify the identity/contact/conversation/Administrator/anonymous checks, and validate seven new/changed definer functions (postgres ownership, empty search_path and precise execution grants). The broad profile policy is absent. Participant lookups return only the documented fixed columns and mask historical/messaging-only contact.

**Client/tests:** three focused request/error tests PASS; five deployed-backend client checks PASS (four actual RPC/RLS calls through the Dart SQL transport and one real anonymous PostgREST denial). Authenticated HTTP/UI sessions were not exercised; this limit is recorded rather than claimed as UI coverage. Normal 'flutter test': 301 PASS, with five opt-in live checks skipped because they ran separately. 'flutter analyze': 0 errors / 48 warnings / 135 info. No product-client/UI changes were made in this targeted continuation; only the opt-in live test was added and formatted.

**Production anomalies: NONE.** After deployment and live tests, all 66 public-table data hashes, auth-user hash and public table-column schema hash match the pre-deployment snapshot. No persistent test account/session remains. Payments, payouts, bookings, waiting rates, tour schema and the three manual-review Driver records are unchanged. All three records remain **REQUIRES_MANUAL_REVIEW**. Historical ledger now totals **8 VERIFIED_PRESENT / 45 VERIFIED_SUPERSEDED / 1 INTENTIONALLY_OBSOLETE / 0 MISSING_EFFECT_REQUIRES_FORWARD_FIX / 0 STILL_NEEDS_REVIEW**. The ten formerly missing rows are superseded by the deployed, live-tested forward repair.

The next migration eligible for separate review/deployment is '20260928000000_tour_stay_waiting_and_tourist_reviews.sql'. It was **not deployed or modified** in this phase. [Machine-readable deployment evidence](supabase_historical_deployment_complete_20260928.json).


## Feature review continuation — 2026-09-28T06:43:36.229Z

**20260928000000: NOT DEPLOYED. Final status: BLOCKED.** All 91 applied migrations remain unchanged and aligned; only the feature migration is local-only. This continuation reviewed only feature dependencies against the current live schema, without reopening historical reconciliation or Driver-status cases.

**Critical financial regression:** after a confirmed 750-peso remaining payment, the outstanding balance is zero while the historical requirement records 750. A later 40-peso waiting charge correctly creates 40 outstanding, but `finalize_booking_stop_waiting_charge` increments the old requirement to 790 and reopens it. The current deployed `validate_booking_payment_submission` requires both payment amount and current requirement amount to match the outstanding balance. Thus the correct 40-peso payment cannot pass (`PAYMENT_STAGE_NOT_REQUIRED`). No additional payment or collection should be inferred from finalized waiting. The focused PostgreSQL regression reproduces **790 required versus 40 outstanding**. Deployment and live preflight stopped at this critical failed gate, as instructed. No payment transaction was submitted to production.

**Local review corrections prepared:** province-qualified municipal rate resolution and booking/stop snapshots; a shared waiting/review booking scope requiring accepted/completed or assigned Driver participation and active Subtenant municipality **and province**; province-scoped Subtenant reports; capped Main Tenant fare visibility; explicit empty function search paths and restricted execution grants. Same-city foreign-province, missing province, ambiguous rate, and 0/1/15/16/30/31-minute boundary cases were added. These changes remain in the pending feature migration and have not received live certification. The financial finalization defect remains unfixed because the user explicitly required STOP on a critical SQL failure.

**Rates:** active offices requiring approved configuration are **Baliwag, Bulacan; Bustos, Bulacan; Malolos, Bulacan**. Baliwag and Bustos have active fare rows but no tour rate; Malolos has no fare row. No approved peso values were supplied or found in project documentation. None was invented/configured. Fixture rates are isolated test values, not approvals. Existing hourly ride `waiting_fee` was not copied, divided or changed. New booking snapshot logic fails clearly without a configured rate. Existing bookings remain accessible; a legacy stop with no rate at arrival retains an explicit NULL snapshot and a disclosed zero assessed charge rather than retroactive billing.

**Tests:** 84 waiting/review SQL assertions pass before the new financial assertion fails; the explicit GPS/slide SQL suite passes 12/12. Focused Flutter 7/7; full Flutter 301/301 (five opt-in historical live checks skipped); analyze 0 errors / 48 warnings / 135 info. `dart format .` ran on 239 files; its 66 formatting-only source changes were restored to preserve existing work. Existing report/PDF paths use the same report RPC/model, but no PDF was generated or compared to live feature metrics.

**Coverage limits:** local SQL proves booked stay/interval/snapshot and simulated GPS/slide behavior; it does not prove physical GPS arrival, real UI progression, realtime reconnect, delivered notifications, real payment collection or a live PDF export. Those checks, deployed feature RLS and rollback-only feature preflight were not run after the blocking SQL failure. No such live flow is claimed PASS.

**Production writes by this attempt: NONE.** Current read-only snapshots match the completed historical checkpoint across all 66 public-table data hashes, table-column schema, profile/itinerary policies and the secured itinerary initializer. **Observed difference:** the auth-user aggregate hash changed from `999068bd3e175801c4a25e7c984338b1` to `792aaf38eeb8e01d5a3102e610c03082` since that earlier checkpoint. Its origin is unverified; this attempt issued no production writes. Historical profile security remains deployed; the feature remains absent. The three manual-review Driver records were not examined or edited.

**Next targeted action:** correct the pending feature finalizer so the reopened remaining requirement reflects net outstanding debt, retains historical confirmed payments, and cannot reuse old payment proof for the new fee. Verify the 750 + 60 = 810 then confirmed 810 = 0 case and the additional-after-settlement case against the current payment architecture. Rerun the focused SQL gate; only after it passes run the rollback live preflight, verify rollback, then consider feature deployment and approved-rate configuration.


## Targeted payment fix and deployment — 2026-09-28T07:42:07.019Z

**TOUR_FEATURE_DEPLOYED_RATE_CONFIGURATION_REQUIRED.** The supported linked CLI dry run selected only 20260928000000; the actual push applied only that version. Migration history is now **92/92 ALIGNED**, no local-only versions. The 91 prior applied migration files match their checkpoint hashes; none was edited/replayed. No original package price, confirmed payment, existing allocation, auth user or manual-review Driver record was changed by this task. Product client source was not changed.

**Root cause and authoritative fix:** a satisfied remaining-stage requirement retains its old collection target, while the booking balance is already net of credited payments. The departure trigger used to add the waiting amount to that historical target. It now atomically increases the persisted outstanding balance, reads that exact result and updates/inserts the single current remaining requirement to the result, clearing stale satisfaction proof. It does not recompute/subtract receipts again or redefine downpayment/full-stage semantics. Existing payment preparation also needed to ignore older confirmed remaining receipts, and the unique index now limits unresolved remaining submissions while preserving multiple confirmed receipts. Provider idempotency-key reuse still identifies its original record. A paid webhook replay for a confirmed remaining receipt is ignored before it can satisfy a newer equal-amount requirement. Existing validation, roster, identity, amount, route, provider-trust and allocation guards remain.

**Exact scenario (isolated regression and live SQL rollback):** 750 remaining obligation; 750 already confirmed; 40 finalized waiting -> **40 outstanding / 40 required**. The real authenticated-role group-cash preparation accepts a distinct 40-peso receipt and allocates only that 40; the assigned Driver confirmation produces **0 outstanding** and **790 confirmed remaining-stage collections**. The 40-peso finalized ledger persists; the prior 750 receipt and allocations are unchanged. The example concerns the remaining stage; normal downpayment evidence is separate. Existing partially credited 1000 - 400 + 40 requires 640. Two stops 40 + 20 after fully paid 750 require 60. Unpaid 750 + 60 requires 810; confirmed 810 leaves zero and retains the waiting ledger. New partial submissions remain unsupported: the existing validator requires the entire currently unpaid stage amount.

**Tests:** waiting/review SQL **134/134**, slide SQL **12/12**, focused Flutter **7/7**, standard Flutter **301/301** (five opt-in historical live checks skipped), analyze **0 errors / 48 warnings / 135 info**. No Dart source changed in this continuation. The SQL additions use 15 current backend dependency bodies for real validation, preparation, allocation and settlement; nonfinancial external completion services are stubbed only in isolated tests. Regression checks cover missing requirements, existing partial credits, multiple stops, 0/1/15/16/30/31-minute boundaries, invalid amounts, repeated departures, repeated preparation/confirmation, historical receipt/allocation preservation, provider event replay and report collections.

**Rollback/live evidence:** 38 recorded preflight gates passed before deployment. Full preflight snapshots and original payment function/trigger/index/constraint definitions match after rollback. After deployment, **57 recorded backend gates** pass, including six-role access/anonymous denial, read-only financial ledgers, missing-rate booking rejection, actual booked-duration arrival snapshots, legacy NULL-rate safe departure, valid/invalid/duplicate reviews, scoped municipal/provincial reports and function owner/path/ACL checks. The post-deployment legacy fixtures temporarily suspend only the new INSERT rate-snapshot trigger during creation, then re-enable it before verification; all operations roll back. No auth/profile/Driver-detail row is created or modified. The old two-argument completion overload is retained with its existing search path; the 20 newly created/replaced feature bodies have empty paths and postgres ownership, and anonymous execution is denied.

**Reports and collections:** finalized waiting remains historical obligation, never automatically collected revenue. The report sums only confirmed payment records; the single current remaining-stage collection uses the existing cash/PayMongo allocation architecture. No extra payout is invented from accrual or finalization. Original package values and historical allocations remain intact. Existing PDF builders consume the existing report model/RPC; no new export system was added. **Generated PDF/export values were not live-tested.**

**Rate configuration REQUIRED:** **Baliwag, Bulacan; Bustos, Bulacan; Malolos, Bulacan**. No approved amounts were provided, none was configured, and hourly ride waiting_fee is unchanged. Malolos still has no fare row. Its normal authorized path is Subtenant City Profile -> Fare Settings -> the existing own subtenant/city upsert, after approved tour and required fare values are supplied. No municipality row or monetary values were invented. Synthetic 40-peso ledger snapshots belong only to rolled-back tests. New bookings clearly fail TOUR_WAITING_RATE_NOT_CONFIGURED; existing legacy bookings remain accessible and disclose a NULL arrival-rate snapshot without retroactive billing.

**Live limits:** tests exercise the deployed database under existing identities and authenticated/anonymous SQL roles, not real HTTP/browser/device sessions. Physical GPS/navigation, actual Driver slides, Tourist/Driver UI synchronization, notification delivery, reconnect/realtime behavior, final physical drop-off/completion, external real-money provider collection and generated PDF export remain **NOT LIVE-TESTED**. Completion for review fixtures is a trusted backend fixture transition, not proof of the real slide/drop-off flow.

**Auth investigation:** **EXPLAINED as expected mutable auth activity**, based on targeted read-only timestamp correlation. One existing account signed in at 06:31:41 UTC between earlier checkpoints. At 07:31:06 UTC its account update, new refresh token and session refresh occur within milliseconds; no new auth user exists. These expected metadata writes explain why an all-fields auth hash changes. No auth mutation was issued by this task. A complete old per-field auth baseline is unavailable, so this is a supported metadata explanation, not forensic certification of every auth field.

**Production preservation:** all original fields in all 66 existing public tables match the pre-deployment hashes after excluding only the newly added nullable tour fields. New waiting/review tables have zero persistent test rows, and configured tour-rate count is zero. The full immediately post-deployment snapshot matches the final snapshot after live-test rollback. Profile policies, itinerary policies and the secured itinerary initializer retain their hashes. Expected persistent changes are the feature schema/functions/index/RLS/cron and migration-history row. Production anomalies: **NONE beyond the explained mutable auth hash change**. [Machine-readable evidence](supabase_tour_feature_gate_20260928.json).
