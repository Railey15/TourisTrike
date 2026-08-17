# PayMongo Disbursement Architecture

Status as of 2026-08-17, branch `feat/convoy-group-booking`. This document
describes the **as-built** state (the schema/RPCs/Edge Functions already
exist and are committed) plus what's still open. It is not a proposal —
it's a record of what shipped in commits `7bb7aec`..`01fa3d0`, so future
sessions don't have to re-derive it by reading five migration files and
five Edge Functions from scratch.

Two legs exist and are **independent**:

- **Collection** (tourist → TourisTrike): tourist pays for the booking.
  **Not implemented yet.** Still the legacy manual GCash sheet (tourist
  sends money, uploads proof, driver/admin confirms) via `payment_records`.
  No PayMongo Checkout/Payment Intent code exists anywhere in the repo —
  confirmed by grep, nothing in `supabase/functions/` creates a checkout
  session.
- **Disbursement** (TourisTrike → drivers): once a tourist payment is
  confirmed, split it N ways and pay each driver's personal GCash via
  PayMongo Transfers. **Implemented, stub-only** (see State Machine below).

`paymongo-payment-webhook` is the seam between the two legs: it assumes a
payment already happened via *some* collection mechanism and reacts to
PayMongo's `payment.paid` webhook. Today nothing fires that webhook for
real (no Checkout integration), so this function is wired but dormant
until Collection is built.

## a) Edge Function structure

Three functions, two shared modules, all in `supabase/functions/`:

| Function | Trigger | Auth | Does |
|---|---|---|---|
| `paymongo-payment-webhook` | PayMongo `payment.paid` webhook | HMAC via `Paymongo-Signature` header, `PAYMONGO_WEBHOOK_SECRET` | Calls `record_payment_and_create_payouts` RPC — writes `payment_records`, fans out N `payout_records` rows via `compute_payout_split` |
| `paymongo-disburse` | (1) DB trigger on `booking_drivers.journey_state → boarded` or `package_bookings.booking_status → completed`, via `X-Internal-Secret`; (2) manual "Retry Disbursement" tap, via Supabase user JWT | Internal secret OR (admin/subtenant OR the driver who owns the payout) | Calls `claim_payout_for_disbursement` RPC (re-derives the gate — never trusts the caller), checks GCash verification, calls `createTransfer()` |
| `paymongo-transfer-webhook` | PayMongo transfer callback_url, or the stub's self-simulated delayed callback | Real: HMAC signature (same secret/scheme as payment-webhook, **unconfirmed for callback_url payloads specifically** — see Open Questions). Stub: `X-Stub-Callback` == `INTERNAL_TRIGGER_SECRET` | Calls `record_transfer_result` RPC — resolves a payout to `paid`/`failed` |
| `_shared/paymongoClient.ts` | n/a (imported) | n/a | `createTransfer()` — the ONE place that knows live vs. stub |
| `_shared/paymongoSignature.ts` | n/a (imported) | n/a | `verifyPaymongoSignature()` — the ONE place implementing the HMAC check |

**Hygiene issue found during verification, not yet fixed:** the working
tree currently has *uncommitted* edits to `_shared/paymongoClient.ts` (adds
a Deno/Node-agnostic `envGet()` — harmless) and to
`paymongo-payment-webhook/index.ts` that **inline a second copy** of
`hmacSha256Hex`/`timingSafeEqual`/signature-parsing instead of importing
`verifyPaymongoSignature` from `_shared/paymongoSignature.ts`. That file's
own header says explicitly: *"used by both webhooks so there's exactly one
place implementing the HMAC check, not two copies that can drift."* The
uncommitted change reintroduces exactly that drift and breaks Code Hygiene
rule 6 (one source of truth). Recommend reverting that one file's
uncommitted diff and re-importing the shared function — flagging, not
fixing, since this session is verification-only.

## b) Schema

**`payout_records`** (base: `20260805000000_convoy_phase0_data_model.sql`,
completed: `20260817000000_paymongo_disbursement_schema.sql`):

```
id                          uuid pk
booking_id                  uuid -> package_bookings
driver_id                   uuid -> profiles
payment_stage               text: down_payment | remaining_balance | full
split_strategy               text: equal_split | per_passenger
amount                       numeric
gcash_number_snapshot        text   -- at time of split computation
gcash_name_snapshot          text
status                       text: pending | processing | paid | failed
disbursement_mode            text: live | stub | cash (nullable)
paymongo_transfer_id         text unique
reference_number             text   -- our deterministic ref, see (e)
provider_reference_number    text   -- PayMongo's own ref, post-transfer
error_message                text
retry_count                  integer default 0
gate_satisfied_at            timestamptz
source_payment_record_id     uuid -> payment_records
notes, created_at, updated_at
unique (booking_id, driver_id, payment_stage)
```

**`payment_records`** (base: `20260725000000_gcash_payment_trail.sql`,
`payee_id` loosened in `20260817000000_...`):

```
id                     uuid pk
ride_id / booking_id   uuid, at least one required
payer_id               uuid -> profiles, not null
payee_id               uuid -> profiles, NULLABLE now
                        -- single-recipient path (ride/cash) still sets it;
                        -- PayMongo group-booking rows insert null since
                        -- payout_records is the per-driver breakdown
amount                 numeric
payment_method         text: cash | gcash | maya
payment_stage          text: full | down_payment | remaining_balance
external_reference_no  text
proof_image_url        text
status                 text: pending_confirmation | confirmed | disputed | cancelled
provider_payment_id    text unique   -- PayMongo payment id, idempotency key
payer_submitted_at / payee_confirmed_at
receipt_no unique, service_description, notes
created_at, updated_at
```

Dart model: `PayoutRecord` in
[touristrike_models.dart:455](../lib/core/supabase/touristrike_models.dart#L455)
mirrors every column 1:1, plus `isPending/isProcessing/isPaid/isFailed`
helpers.

Also touched: `driver_details` gets a GCash verification gate
(`gcash_verification_status`: unverified/pending_review/verified/rejected
+ note/verified_at/verified_by), auto-reset to `unverified` on
number/name change via `trg_reset_gcash_verification`. `paymongo-disburse`
refuses to disburse to an unverified driver (checked fresh at disburse
time, not from the split-time snapshot).

## c) Stub mode design

Already implemented exactly per the "one boundary, not two
implementations" rule, in `_shared/paymongoClient.ts`:

```ts
export async function createTransfer(input) {
  return MODE === "live" ? createLiveTransfer(input) : createStubTransfer(input);
}
```

`paymongo-disburse` imports only `createTransfer()` and has zero
awareness of which mode it's in. `MODE` comes from the `PAYMONGO_MODE` env
var (Supabase Edge Function secret), defaults to `"stub"` so a live
disbursement never happens because a var was merely left unset.

`createStubTransfer` fabricates a `stub_tr_<uuid>` transfer id, decides
pass/fail using the **same regex the DB check-constraint uses**
(`^(09|\+639)\d{9}$` against the GCash number) so a stub failure is
explainable rather than magic, and schedules a delayed (4-8s) self-POST to
`paymongo-transfer-webhook` carrying `X-Stub-Callback` instead of a real
PayMongo signature. `paymongo-transfer-webhook` cannot tell a stub
callback from a real one once auth passes — same `record_transfer_result`
call either way. This is exactly the demo-safe mode requested: full
create → processing → webhook → paid/failed flow, zero calls to PayMongo.

`createLiveTransfer` currently just throws
(`"PAYMONGO_MODE=live is not implemented yet"`) — GCash
receiving-institution BIC lookup
(`GET /v2/transfers/receiving_institutions?provider=instapay`) is
unresolved. **Do not flip `PAYMONGO_MODE=live`** until that's built; it
fails loudly, not silently, which is intentional.

## d) State machine — one payout_record

```
                 record_payment_and_create_payouts (payment webhook)
                              │
                              ▼
                          [pending]  ── unique(booking_id, driver_id, payment_stage)
                              │
          gate event fires (boarded, or booking completed)
                              │  claim_payout_for_disbursement
                              │  (re-derives gate server-side; no-op if
                              │   status isn't pending/failed)
                              ▼
                        [processing] ── gate_satisfied_at stamped
                              │
              ┌───────────────┼────────────────┐
     GCash unverified   createTransfer()   createTransfer() throws
     (fail_payout_precheck)   succeeds      (network/API error, uncaught
              │                │             in current code — see Open Q)
              ▼                ▼
          [failed]      record_transfer_submitted
       error_message set  (paymongo_transfer_id, reference_number written,
       retry_count intact)  status STAYS 'processing')
                              │
                    real or stub async callback
                              │  paymongo-transfer-webhook
                              │  record_transfer_result
                    ┌─────────┴─────────┐
                    ▼                   ▼
                 [paid]              [failed]
             (terminal, idempotent  error_message set,
              re-delivery no-ops)   retry_count preserved
                                          │
                              retry (manual, from UI) or
                              next gate re-fire →
                              claim_payout_for_disbursement
                              (status='failed' is claimable,
                               retry_count += 1)
                              back to [processing]
```

Terminal states (`paid`, `failed`) are idempotent sinks in
`record_transfer_result` — a redelivered webhook is a silent no-op, not a
double-apply.

## e) Webhook handling + idempotency

Two independent idempotency layers, both already implemented:

1. **Payment idempotency** — `payment_records.provider_payment_id unique`
   + `record_payment_and_create_payouts` selects-before-insert on that
   column; a redelivered `payment.paid` event returns the existing row
   instead of creating a duplicate payment/duplicate payout skeleton.
2. **Transfer idempotency** — the brief specified a deterministic key
   shaped `booking_id:driver_id:payment_stage`. What's actually built
   (`paymongo-disburse/index.ts:112-113`) is close but not colon-joined:
   ```ts
   const referenceNumber = `booking_${bookingId}_driver_${driverId}_${paymentStage}`;
   const idempotencyKey = `${referenceNumber}_attempt_${claimed.retry_count}`;
   ```
   `referenceNumber` alone is the stable, booking/driver/stage-deterministic
   identity (matches the brief's intent). The `_attempt_N` suffix on
   `idempotencyKey` is a deliberate deviation: it lets a legitimate retry
   (after a real failure) get a fresh PayMongo idempotency key instead of
   being permanently deduped against the failed first attempt, while
   `claim_payout_for_disbursement`'s own `status not in ('pending','failed')`
   guard is what actually prevents a concurrent double-fire from both
   trigger and manual retry hitting this code path at once.

Signature verification (`_shared/paymongoSignature.ts`): parses
`Paymongo-Signature: t=<ts>,te=<test_sig>,li=<live_sig>`, computes
HMAC-SHA256 of `"{t}.{rawBody}"` with the webhook secret, compares against
both `te` and `li` with a timing-safe compare. **Must** run against
`await req.text()` before any JSON parsing — both webhook functions do
this correctly.

## f) UI screens

Already built (`01fa3d0`):

- `lib/widgets/payments/payout_status_card.dart` — driver-facing,
  per-booking-per-stage status card with a failed-disbursement banner +
  Retry button wired to `retryDisbursement()`.
- `lib/widgets/payments/payment_split_breakdown_widget.dart` —
  tourist-facing, lists every driver's amount/status/reference by name.
- `driver_earnings_screen.dart` — new "PayMongo Disbursements" section,
  additive only; does NOT touch the existing Transaction History query
  (that query has the C1 bug — see below — explicitly deferred to a later
  phase).
- `tourist_activity_tracking_screen.dart` — fetches `payout_records`
  alongside `payment_records`, refreshed on the existing 15s convoy poll.

Still needed (no code exists for this leg yet):

- A PayMongo Checkout/Payment Intent flow for tourist-side Collection —
  currently 100% the manual GCash sheet. This is the biggest remaining
  gap; disbursement has nothing real to react to without it.
- GCash verification submission UI for drivers (upload proof that
  `gcash_number`/`gcash_name` are real, to move
  `gcash_verification_status` from `unverified` → `pending_review` →
  `verified`) — the DB gate exists, nothing populates it from the app
  yet.

## g) Phased plan (each phase independently deployable, per Code Hygiene rule 8)

Already shipped:
- **Phase B0** — schema (`20260817000000`)
- **Phase B1-B3** — RPCs + triggers (`20260817010000`)
- **Phase B4** — Edge Functions (disburse, both webhooks) + stub/live boundary
- **Phase B5** — payout status UI (driver card, tourist breakdown)

Not started, proposed order:
- **Phase C1** — Fix `fetchDriverActivities`/`driver_home_screen` to read
  `booking_drivers` instead of `package_activities.driver_id` (this is C1
  below — blocks correct earnings for every driver except the first
  legacy-assigned one).
- **Phase C2** — GCash verification submission UI (photo/proof upload →
  `pending_review`), plus an admin review screen to flip it to `verified`
  — required before any real disbursement, live or stub-only demo aside.
- **Phase C3** — PayMongo Checkout integration for Collection (the
  currently-unstarted leg). Gated on the PayMongo support answers in
  the email below.
- **Phase C4** — `createLiveTransfer` — GCash receiving-institution BIC
  lookup, then flip `PAYMONGO_MODE=live` for real. Gated on PayMongo
  support confirming test-mode Disbursement availability for an
  unverified/personal account.

## Open questions (carried over, still unresolved)

1. Whether `callback_url` transfer payloads are signed the same way as
   the account-level `Paymongo-Signature` webhook header — assumed yes in
   `paymongo-transfer-webhook`, unconfirmed against PayMongo's docs. See
   the PayMongo support email, question 3.
2. `createTransfer()` throwing (network error, PayMongo 5xx) inside
   `disburseOne()` in `paymongo-disburse/index.ts` is not caught per-driver
   — it propagates up through `Promise.all` and the payout stays stuck in
   `processing` with no `error_message` and no path back to `failed` (only
   `fail_payout_precheck` — called for the GCash-unverified case — writes
   `failed`; a thrown transfer error has no equivalent call). Worth a
   `try/catch` around the `createTransfer` call in a later phase.
