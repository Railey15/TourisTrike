# Package-tour included stay and additional waiting

## Tour feature deployment gate — 2026-09-28: DEPLOYED / RATE_CONFIGURATION_REQUIRED

**20260928000000 is deployed.** Its payment blocker is resolved; 92 applied migrations are aligned. Approved rates remain required for Baliwag, Bustos and Malolos, Bulacan. [Current deployment and payment evidence](supabase_tour_feature_gate_20260928.json). Earlier BLOCKED entries below are dated history; [archived blocked evidence](supabase_tour_feature_blocked_gate_20260928.json).

The booked Time of Stay at each destination comes from
`booking_itinerary_items.estimated_stay_duration_minutes`. Driver waiting is
included until the server-recorded arrival plus that duration. The destination's
recommended visit duration does not change the booked allowance.

The responsible city or municipal tourism office configures
`subtenant_fare_settings.tour_waiting_fee_per_15_minutes`. The older
`waiting_fee` remains an hourly fare input in the existing fare calculator.
New bookings require an active municipal tour rate. The booking snapshots it,
and each stop snapshots that rate again with its booked allowance and arrival.
Existing bookings without a snapshot use the active rate at arrival. If no rate
was configured at arrival, that stop records a null rate and zero additional
fee, even when the stay ran overtime; its departure can still finalize. A rate
configured later does not retroactively charge that historical stop. The
stop/trip log and tourist notice explicitly state that no fee was assessed.

Overtime is billed per started 15-minute interval after included stay. A stop
with 1–15 minutes of overtime has one interval; 16–30 minutes has two. The
server finalizes the obligation at the driver's departure slide. Accrued amounts
are estimates until departure. The original package total and confirmed payment
records do not change. Finalized waiting is added to the remaining payment
requirement before the existing final-payment gate.

Reports label package totals as completed booking value. Confirmed collections
come only from confirmed `payment_records`; finalized waiting fees are obligations
and are not counted as collected cash. The existing allocation/payout flow handles
the single final remaining-balance payment. No separate payout is created from an
accrued charge.

The booking review displays the municipal rate and these operational rules.
Owner approval is still required for formal Terms & Conditions wording and for
how pre-migration bookings should be notified of their applicable rate.

## Deployment checkpoint

As of September 27, 2026, the tour-specific rate column, waiting ledger, and
Driver-to-Tourist review table are not deployed. The two active municipality
fare rows have no tour-specific rate. Municipality offices must approve and
configure those rates in a staged rollout before the booking snapshot trigger
and booking disclosure can be released. The existing ride `waiting_fee` must
not be copied or divided to infer a tour rate.

The final tourist destination is followed by the booked drop-off leg. Sliding
from the final stop finalizes its waiting charge before the remaining-payment
gate; the Driver completes the tour by sliding at drop-off. GPS arrival alone
never completes a stop or the tour.


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
