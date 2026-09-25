# Supabase migration reconciliation — 2026-09-25

Automatic-tour deployment succeeded. History reconciliation is **partial**: 22 verified historical entries were repaired, and the new migration was executed and recorded. Of 84 local migrations, 30 now have remote records; **54 remain unresolved**, so normal `db push` is still blocked. There are no remote-only versions.

Only `20260927000000_automatic_tour_progression.sql` was executed against the application schema, using `supabase db query --linked --file` and its existing transaction, followed by verified `migration repair --status applied`. No historical SQL was replayed, migration file edited/moved/deleted, database reset, RLS disabled, or application code changed in this reconciliation task. Earlier application changes remain untouched.

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
