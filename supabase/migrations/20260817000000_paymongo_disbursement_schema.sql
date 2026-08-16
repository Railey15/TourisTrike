-- ============================================================
-- PayMongo disbursement — schema only (Phase B0).
--
-- Completes payout_records (Phase 0 shipped the shape, deliberately
-- unused — see its own comment in 20260805000000_convoy_phase0_data_model.sql)
-- and makes the three structural changes the PayMongo split flow needs:
--   1. payout_records gets the actual PayMongo tracking fields.
--   2. payment_records.payee_id becomes nullable — a single tourist
--      payment now fans out to N drivers via payout_records, so there is
--      no longer one payee to name on the payment_records row itself.
--   3. payment_disputes gets a tourist-framed reason distinct from the
--      existing recipient-framed ones ("nagbayad ako, hindi nag-confirm
--      ang driver" vs. "hindi ko natanggap 'to").
--   4. driver_details gets a GCash verification gate — currently
--      gcash_number/gcash_name are free text with no verification step,
--      which is exactly how a mismatched name turns into a failed
--      transfer with money stuck mid-flight.
--
-- No RPCs, no triggers, no Edge Function wiring here on purpose — see
-- 20260817010000_paymongo_disbursement_rpcs_and_triggers.sql for those.
-- Nothing writes to payout_records yet, so every change below is a
-- pure column add/drop — no data migration needed.
-- ============================================================

-- ── 1. payout_records: complete the PayMongo tracking columns ──────
alter table public.payout_records
  drop column if exists paymongo_reference;

alter table public.payout_records
  add column if not exists disbursement_mode text
    check (disbursement_mode is null or disbursement_mode in ('live', 'stub', 'cash')),
  add column if not exists paymongo_transfer_id text unique,
  add column if not exists reference_number text,
  add column if not exists provider_reference_number text,
  add column if not exists error_message text,
  add column if not exists retry_count integer not null default 0,
  add column if not exists gate_satisfied_at timestamptz;

create index if not exists idx_payout_records_paymongo_transfer_id
  on public.payout_records(paymongo_transfer_id);

-- ── 2. payment_records: payee_id no longer meaningful for a split ──
-- payment across N drivers. Kept for the single-payee ride/cash paths
-- (record_ride_payment, cash confirmation) where it's still exactly one
-- driver; PayMongo-collected rows will insert it as null.
alter table public.payment_records
  alter column payee_id drop not null;

alter table public.payment_records
  add column if not exists provider_payment_id text unique;

comment on column public.payment_records.payee_id is
  'Single recipient for the ride/cash paths. Null for PayMongo-collected '
  'group-booking payments — see payout_records for the per-driver split.';

-- ── 3. payment_disputes: tourist-framed reason, distinct from the ──
-- existing recipient-framed ones. Not reusing 'other' — needs to be
-- filterable/reportable on its own.
alter table public.payment_disputes
  drop constraint if exists payment_disputes_reason_check;
alter table public.payment_disputes
  add constraint payment_disputes_reason_check
  check (reason in (
    'not_received', 'wrong_amount', 'duplicate', 'fake_reference',
    'payer_says_paid_not_confirmed', 'other'
  ));

-- ── 4. driver_details: GCash payout verification gate ──────────────
-- Free-text gcash_number/gcash_name today with no verification step —
-- this is the gate a driver must clear before they're eligible to
-- receive a PayMongo disbursement (cash bookings are unaffected).
alter table public.driver_details
  add column if not exists gcash_verification_status text not null default 'unverified'
    check (gcash_verification_status in ('unverified', 'pending_review', 'verified', 'rejected')),
  add column if not exists gcash_verification_note text,
  add column if not exists gcash_verified_at timestamptz,
  add column if not exists gcash_verified_by uuid references public.profiles(id) on delete set null;

-- Re-verification required whenever the driver changes their GCash
-- number/name — a verified screenshot for the OLD number must not carry
-- over to a new one.
create or replace function public.reset_gcash_verification_on_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (new.gcash_number is distinct from old.gcash_number)
     or (new.gcash_name is distinct from old.gcash_name) then
    new.gcash_verification_status := 'unverified';
    new.gcash_verified_at := null;
    new.gcash_verified_by := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reset_gcash_verification on public.driver_details;
create trigger trg_reset_gcash_verification
before update on public.driver_details
for each row execute function public.reset_gcash_verification_on_change();

-- ── 5. payout_records RLS: tourist needs to see their own booking's ──
-- split breakdown (who got how much) — the Phase 0 policy only covered
-- the driver themselves and admin/subtenant.
drop policy if exists payout_records_select on public.payout_records;
create policy payout_records_select
on public.payout_records
for select
using (
  auth.uid() = driver_id
  or public.current_profile_role() in ('admin', 'subtenant')
  or exists (
    select 1 from public.package_bookings pb
    where pb.id = payout_records.booking_id and pb.tourist_id = auth.uid()
  )
);
