# Supabase migration reconciliation — 2026-09-25

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
