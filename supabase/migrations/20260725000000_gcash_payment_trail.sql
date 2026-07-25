-- ============================================================
-- GCash-to-GCash direct payment trail.
-- Replaces the custodial "TourisPay" wallet (wallets / wallet_transactions)
-- and the PayMongo-backed `payments` table with a non-custodial payment
-- trail: money moves directly from the tourist's personal GCash to the
-- driver's personal GCash. TourisTrike never holds a balance and is
-- outside the AMLA covered-person scope (RA 9160) as a result.
-- ============================================================

-- ── 1. Archive the custodial tables (rename preserves FKs/indexes) ──
alter table if exists public.wallet_transactions rename to _deprecated_wallet_transactions;
alter table if exists public.wallets rename to _deprecated_wallets;
alter table if exists public.payments rename to _deprecated_payments;

-- ── 2. Driver GCash payment details ──────────────────────────
alter table public.driver_details
  add column if not exists gcash_number text
    check (gcash_number is null or gcash_number ~ '^(09|\+639)\d{9}$'),
  add column if not exists gcash_name text,
  add column if not exists gcash_qr_url text;

-- ── 3. payment_records: the payment trail itself ─────────────
create table if not exists public.payment_records (
  id uuid primary key default gen_random_uuid(),
  ride_id    uuid references public.rides(id),
  booking_id uuid references public.package_bookings(id),
  payer_id   uuid not null references public.profiles(id),
  payee_id   uuid not null references public.profiles(id),
  amount     numeric not null default 0 check (amount >= 0),
  payment_method text not null check (payment_method in ('cash', 'gcash', 'maya')),
  payment_stage text not null default 'full'
    check (payment_stage in ('full', 'down_payment', 'remaining_balance')),
  external_reference_no text
    check (external_reference_no is null or external_reference_no ~ '^\d{10,13}$'),
  proof_image_url text,
  status text not null default 'pending_confirmation'
    check (status in ('pending_confirmation', 'confirmed', 'disputed', 'cancelled')),
  payer_submitted_at timestamptz not null default now(),
  payee_confirmed_at timestamptz,
  receipt_no text unique,
  service_description text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payment_records_link_check check (ride_id is not null or booking_id is not null)
);

create index if not exists idx_payment_records_payer on public.payment_records(payer_id);
create index if not exists idx_payment_records_payee on public.payment_records(payee_id);
create index if not exists idx_payment_records_status on public.payment_records(status);
create index if not exists idx_payment_records_booking on public.payment_records(booking_id);
create index if not exists idx_payment_records_ride on public.payment_records(ride_id);

-- updated_at (shared trigger, same as every other table)
drop trigger if exists set_payment_records_updated_at on public.payment_records;
create trigger set_payment_records_updated_at before update on public.payment_records
for each row execute function public.set_updated_at();

-- Auto-issue an Acknowledgement Receipt number the moment a payment is confirmed.
create sequence if not exists public.receipt_no_seq;

create or replace function public.set_payment_receipt_no()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'confirmed' and new.receipt_no is null then
    new.receipt_no := 'TT-' || to_char(now(), 'YYYY') || '-' ||
                       lpad(nextval('public.receipt_no_seq')::text, 6, '0');
    new.payee_confirmed_at := coalesce(new.payee_confirmed_at, now());
  end if;
  return new;
end;
$$;

-- `before insert or update` (not just update) so the self-serve ride-payment
-- RPC below, which inserts an already-confirmed row, still gets a receipt no.
drop trigger if exists trg_set_payment_receipt_no on public.payment_records;
create trigger trg_set_payment_receipt_no before insert or update on public.payment_records
for each row execute function public.set_payment_receipt_no();

-- ── 4. payment_disputes ───────────────────────────────────────
create table if not exists public.payment_disputes (
  id uuid primary key default gen_random_uuid(),
  payment_record_id uuid not null references public.payment_records(id),
  booking_id uuid references public.package_bookings(id),
  ride_id    uuid references public.rides(id),
  raised_by  uuid not null references public.profiles(id),
  reason text not null
    check (reason in ('not_received', 'wrong_amount', 'duplicate', 'fake_reference', 'other')),
  description text,
  evidence_url text,
  status text not null default 'open'
    check (status in ('open', 'under_review', 'resolved_valid', 'resolved_refund_arranged', 'rejected')),
  resolved_by uuid references public.profiles(id),
  resolution_note text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists idx_payment_disputes_status on public.payment_disputes(status);
create index if not exists idx_payment_disputes_record on public.payment_disputes(payment_record_id);

-- ── 5. AMLC guardrail: immutable audit trail on every payment event ──
-- TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
create or replace function public.log_payment_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_logs (actor_id, action, table_name, record_id, description)
  values (
    coalesce(auth.uid(), new.payee_id),
    lower(tg_op) || '_payment_record',
    'payment_records',
    new.id::text,
    'status=' || coalesce(new.status, '') ||
      ' | amount=' || new.amount ||
      ' | method=' || new.payment_method ||
      ' | stage=' || new.payment_stage ||
      ' | ref=' || coalesce(new.external_reference_no, '-')
  );
  return new;
end;
$$;

drop trigger if exists trg_log_payment_audit on public.payment_records;
create trigger trg_log_payment_audit
after insert or update on public.payment_records
for each row execute function public.log_payment_audit();

-- ── 6. Row Level Security ────────────────────────────────────
alter table public.payment_records enable row level security;
alter table public.payment_disputes enable row level security;

drop policy if exists payment_records_select on public.payment_records;
create policy payment_records_select
on public.payment_records
for select
using (
  auth.uid() = payer_id
  or auth.uid() = payee_id
  or public.current_profile_role() in ('admin', 'subtenant')
);

-- Only the payer (the one sending money) can create a payment record.
drop policy if exists payment_records_insert on public.payment_records;
create policy payment_records_insert
on public.payment_records
for insert
with check (auth.uid() = payer_id);

-- Only the payee (the one confirming receipt) or an admin/subtenant can update
-- status directly (e.g. confirm). Dispute creation/resolution goes through the
-- SECURITY DEFINER RPCs below so the payer can flip status to 'disputed' too,
-- without a blanket payer-update grant.
drop policy if exists payment_records_update on public.payment_records;
create policy payment_records_update
on public.payment_records
for update
using (
  auth.uid() = payee_id
  or public.current_profile_role() in ('admin', 'subtenant')
)
with check (
  auth.uid() = payee_id
  or public.current_profile_role() in ('admin', 'subtenant')
);

drop policy if exists payment_disputes_select on public.payment_disputes;
create policy payment_disputes_select
on public.payment_disputes
for select
using (
  auth.uid() = raised_by
  or exists (
    select 1 from public.payment_records pr
    where pr.id = payment_record_id
      and (pr.payer_id = auth.uid() or pr.payee_id = auth.uid())
  )
  or public.current_profile_role() in ('admin', 'subtenant')
);

-- ── 7. Dispute RPCs (SECURITY DEFINER so a payer can raise a dispute
--       without needing a direct UPDATE grant on payment_records) ──
create or replace function public.raise_payment_dispute(
  p_payment_record_id uuid,
  p_reason text,
  p_description text default null,
  p_evidence_url text default null
)
returns public.payment_disputes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pr public.payment_records;
  v_dispute public.payment_disputes;
begin
  select * into v_pr from public.payment_records where id = p_payment_record_id for update;
  if not found then
    raise exception 'PAYMENT_RECORD_NOT_FOUND';
  end if;

  if auth.uid() is null or (auth.uid() <> v_pr.payer_id and auth.uid() <> v_pr.payee_id) then
    raise exception 'NOT_A_PARTICIPANT';
  end if;

  insert into public.payment_disputes (
    payment_record_id, booking_id, ride_id, raised_by, reason, description, evidence_url
  ) values (
    p_payment_record_id, v_pr.booking_id, v_pr.ride_id, auth.uid(), p_reason, p_description, p_evidence_url
  ) returning * into v_dispute;

  update public.payment_records set status = 'disputed' where id = p_payment_record_id;

  return v_dispute;
end;
$$;

grant execute on function public.raise_payment_dispute(uuid, text, text, text) to authenticated;

-- Lets the payer attach a proof screenshot after the row already exists
-- (needed because the payment_records UPDATE policy only allows the payee/
-- admin to change status — this RPC only ever touches proof_image_url).
create or replace function public.attach_payment_proof(
  p_payment_record_id uuid,
  p_proof_image_url text
)
returns public.payment_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pr public.payment_records;
begin
  select * into v_pr from public.payment_records where id = p_payment_record_id for update;
  if not found then
    raise exception 'PAYMENT_RECORD_NOT_FOUND';
  end if;

  if auth.uid() is null or auth.uid() <> v_pr.payer_id then
    raise exception 'NOT_THE_PAYER';
  end if;

  update public.payment_records
  set proof_image_url = p_proof_image_url
  where id = p_payment_record_id
  returning * into v_pr;

  return v_pr;
end;
$$;

grant execute on function public.attach_payment_proof(uuid, text) to authenticated;

-- Tricycle single-ride flow (`rides` table) has no live tourist-facing tracking
-- screen in this app today (it's a separate, older flow from package tours),
-- so there is no in-app way for the tourist to self-submit a ride payment the
-- way they do for package bookings. As a scoped, explicit compromise, the
-- DRIVER records the payment directly when completing a ride — self-attesting
-- what the tourist already told/paid them (verbally-shared GCash reference,
-- or cash-in-hand). The record is created already CONFIRMED since there is no
-- separate payer submission step to confirm against for this flow.
-- TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
create or replace function public.record_ride_payment(
  p_ride_id uuid,
  p_payment_method text,
  p_amount numeric,
  p_external_reference_no text default null
)
returns public.payment_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ride public.rides;
  v_record public.payment_records;
begin
  select * into v_ride from public.rides where id = p_ride_id;
  if not found then
    raise exception 'RIDE_NOT_FOUND';
  end if;

  if auth.uid() is null or auth.uid() <> v_ride.driver_id then
    raise exception 'NOT_THE_DRIVER';
  end if;

  if p_payment_method not in ('cash', 'gcash', 'maya') then
    raise exception 'INVALID_PAYMENT_METHOD';
  end if;

  insert into public.payment_records (
    ride_id, payer_id, payee_id, amount, payment_method,
    payment_stage, external_reference_no, status, service_description
  ) values (
    p_ride_id, v_ride.tourist_id, auth.uid(), p_amount, p_payment_method,
    'full', p_external_reference_no, 'confirmed',
    'Tricycle ride #' || p_ride_id
  )
  returning * into v_record;

  return v_record;
end;
$$;

grant execute on function public.record_ride_payment(uuid, text, numeric, text) to authenticated;

create or replace function public.resolve_payment_dispute(
  p_dispute_id uuid,
  p_new_status text,
  p_resolution_note text default null
)
returns public.payment_disputes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dispute public.payment_disputes;
begin
  if public.current_profile_role() not in ('admin', 'subtenant') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_new_status not in ('under_review', 'resolved_valid', 'resolved_refund_arranged', 'rejected') then
    raise exception 'INVALID_STATUS';
  end if;

  update public.payment_disputes
  set status = p_new_status,
      resolution_note = coalesce(p_resolution_note, resolution_note),
      resolved_by = auth.uid(),
      resolved_at = case
        when p_new_status in ('resolved_valid', 'resolved_refund_arranged', 'rejected') then now()
        else resolved_at
      end
  where id = p_dispute_id
  returning * into v_dispute;

  if not found then
    raise exception 'DISPUTE_NOT_FOUND';
  end if;

  -- No fund movement happens here — this only changes the record status.
  -- Any actual refund is arranged directly between tourist and driver.
  update public.payment_records
  set status = case
    when p_new_status = 'resolved_valid' then 'confirmed'
    when p_new_status = 'resolved_refund_arranged' then 'cancelled'
    when p_new_status = 'rejected' then 'confirmed'
    else 'disputed'
  end
  where id = v_dispute.payment_record_id;

  insert into public.audit_logs (actor_id, action, table_name, record_id, description)
  values (
    auth.uid(),
    'resolve_payment_dispute',
    'payment_disputes',
    v_dispute.id::text,
    'Dispute resolved: ' || p_new_status || coalesce(' | note=' || p_resolution_note, '')
  );

  return v_dispute;
end;
$$;

grant execute on function public.resolve_payment_dispute(uuid, text, text) to authenticated;

-- ── 8. Storage ────────────────────────────────────────────────
-- Private bucket for GCash payment-proof screenshots.
insert into storage.buckets (id, name, public)
values ('payment-proofs', 'payment-proofs', false)
on conflict (id) do update set public = false;

drop policy if exists payment_proofs_select on storage.objects;
create policy payment_proofs_select
on storage.objects
for select
using (
  bucket_id = 'payment-proofs'
  and (
    public.current_profile_role() in ('admin', 'subtenant')
    or exists (
      select 1 from public.payment_records pr
      where pr.id::text = (storage.foldername(name))[1]
        and (pr.payer_id = auth.uid() or pr.payee_id = auth.uid())
    )
  )
);

drop policy if exists payment_proofs_insert on storage.objects;
create policy payment_proofs_insert
on storage.objects
for insert
with check (
  bucket_id = 'payment-proofs'
  and exists (
    select 1 from public.payment_records pr
    where pr.id::text = (storage.foldername(name))[1]
      and pr.payer_id = auth.uid()
  )
);

-- Driver's own GCash QR, uploaded under public-assets/driver-payment/{driverId}/...
-- (bucket-wide SELECT is already public via the existing public_assets_select policy).
drop policy if exists public_assets_driver_payment_insert on storage.objects;
create policy public_assets_driver_payment_insert
on storage.objects
for insert
with check (
  bucket_id = 'public-assets'
  and (storage.foldername(name))[1] = 'driver-payment'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists public_assets_driver_payment_update on storage.objects;
create policy public_assets_driver_payment_update
on storage.objects
for update
using (
  bucket_id = 'public-assets'
  and (storage.foldername(name))[1] = 'driver-payment'
  and (storage.foldername(name))[2] = auth.uid()::text
)
with check (
  bucket_id = 'public-assets'
  and (storage.foldername(name))[1] = 'driver-payment'
  and (storage.foldername(name))[2] = auth.uid()::text
);

-- ── 9. Patch RPCs that referenced the now-archived wallet tables ──

-- driver_accept_package_activity: drop the "credit driver wallet for the initial
-- wallet payment" block. Nothing replaces it here — the down payment is now
-- collected via a GCash payment_records row created by the app after this
-- RPC succeeds (driver is known, driver's GCash QR can be shown).
create or replace function public.driver_accept_package_activity(
  p_activity_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_activity public.package_activities;
  v_booking public.package_bookings;
begin
  if v_driver_id is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = v_driver_id and role = 'driver'
  ) then
    raise exception 'DRIVER_ROLE_REQUIRED';
  end if;

  if exists (
    select 1
    from public.package_activities a
    where a.driver_id = v_driver_id
      and a.id <> p_activity_id
      and a.status in ('accepted', 'ongoing')
      and a.tour_status not in ('completed', 'dropped_off')
  ) then
    raise exception 'ACTIVE_TOUR_EXISTS';
  end if;

  select *
  into v_activity
  from public.package_activities
  where id = p_activity_id
  for update;

  if not found then
    raise exception 'ACTIVITY_NOT_FOUND';
  end if;

  if v_activity.driver_id is not null then
    raise exception 'BOOKING_ALREADY_ASSIGNED';
  end if;

  select *
  into v_booking
  from public.package_bookings
  where id = v_activity.booking_id
  for update;

  update public.package_activities
  set driver_id = v_driver_id,
      status = 'accepted',
      tour_status = 'driver_accepted',
      accepted_at = now(),
      updated_at = now()
  where id = p_activity_id;

  update public.package_bookings
  set assigned_driver_id = v_driver_id,
      status = 'confirmed',
      booking_status = 'accepted',
      accepted_at = now(),
      updated_at = now()
  where id = v_activity.booking_id;

  return jsonb_build_object(
    'success', true,
    'activity_id', v_activity.id,
    'booking_id', v_activity.booking_id
  );
end;
$$;

grant execute on function public.driver_accept_package_activity(uuid) to authenticated;

-- accept_package_booking: this is the RPC actually invoked from the app
-- (TourisTrikeRepository.acceptPackageBooking). It queried the now-archived
-- `payments` table (unguarded — would raise `relation "payments" does not
-- exist` and break every driver acceptance) and credited the driver wallet.
-- Both are removed; the down payment is now collected via a GCash
-- payment_records row created by the app once the driver is known.
create or replace function public.accept_package_booking(
  p_booking_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id     uuid := auth.uid();
  v_driver        public.profiles;
  v_booking       public.package_bookings;
  v_activity_id   uuid;
  v_live_count    integer;
  v_new_count     integer;
begin
  -- ── Auth ──────────────────────────────────────────────────────────────────
  if v_driver_id is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select * into v_driver from public.profiles where id = v_driver_id;
  if not found then
    raise exception 'DRIVER_NOT_FOUND';
  end if;
  if v_driver.role <> 'driver' then
    raise exception 'DRIVER_ROLE_REQUIRED';
  end if;
  if not (coalesce(v_driver.is_online, false) or coalesce(v_driver.is_available, false)) then
    raise exception 'DRIVER_NOT_AVAILABLE';
  end if;

  -- ── Load & lock booking ───────────────────────────────────────────────────
  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'BOOKING_NOT_FOUND';
  end if;

  if v_booking.booking_status not in ('pending', 'waiting_for_drivers') then
    raise exception 'BOOKING_NOT_AVAILABLE';
  end if;

  if v_booking.municipality is not null
     and trim(v_booking.municipality) <> ''
  then
    if trim(lower(coalesce(v_driver.city, ''))) <> trim(lower(v_booking.municipality)) then
      raise exception 'MUNICIPALITY_MISMATCH: Booking is for % only.', v_booking.municipality;
    end if;
  end if;

  -- ── Live recount (avoids stale counter bugs) ──────────────────────────────
  select count(*) into v_live_count
  from public.booking_drivers
  where booking_id = p_booking_id and status = 'accepted';

  if v_live_count >= coalesce(v_booking.required_drivers, 1) then
    raise exception 'BOOKING_ALREADY_FULL';
  end if;

  if exists (
    select 1 from public.booking_drivers
    where booking_id = p_booking_id and driver_id = v_driver_id
  ) then
    raise exception 'ALREADY_ACCEPTED';
  end if;

  select id into v_activity_id
  from public.package_activities
  where booking_id = p_booking_id
  limit 1;

  insert into public.booking_drivers
    (booking_id, driver_id, status, accepted_at)
  values
    (p_booking_id, v_driver_id, 'accepted', now());

  v_new_count := v_live_count + 1;

  if v_new_count >= coalesce(v_booking.required_drivers, 1) then
    if v_activity_id is not null then
      update public.package_activities
      set driver_id   = v_driver_id,
          status      = 'accepted',
          tour_status = 'driver_accepted',
          accepted_at = now(),
          updated_at  = now()
      where id = v_activity_id;
    end if;

    update public.package_bookings
    set assigned_driver_id     = v_driver_id,
        accepted_drivers_count = v_new_count,
        status                 = 'confirmed',
        booking_status         = 'accepted',
        accepted_at            = now(),
        updated_at             = now()
    where id = p_booking_id;
  else
    update public.package_bookings
    set accepted_drivers_count = v_new_count,
        booking_status         = 'waiting_for_drivers',
        updated_at             = now()
    where id = p_booking_id;
  end if;

  return jsonb_build_object(
    'success',        true,
    'booking_id',     p_booking_id,
    'accepted_count', v_new_count,
    'required_count', coalesce(v_booking.required_drivers, 1),
    'all_filled',     v_new_count >= coalesce(v_booking.required_drivers, 1)
  );
end;
$$;

grant execute on function public.accept_package_booking(uuid) to authenticated;

-- complete_package_tour: drop the "auto-insert a cash payment + credit driver
-- wallet" block for the remaining balance. Replaced with a guard requiring a
-- CONFIRMED payment_records row for the remaining balance (created by the app's
-- GCash/cash flow with explicit driver confirmation) before the tour can close.
-- p_remaining_payment_method is kept for call-site compatibility but ignored.
create or replace function public.complete_package_tour(
  p_activity_id uuid,
  p_remaining_payment_method text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_activity public.package_activities;
  v_booking public.package_bookings;
  v_total_items integer := 0;
  v_completed_items integer := 0;
begin
  if v_driver_id is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select *
  into v_activity
  from public.package_activities
  where id = p_activity_id
  for update;

  if not found then
    raise exception 'ACTIVITY_NOT_FOUND';
  end if;

  if v_activity.driver_id <> v_driver_id then
    raise exception 'NOT_ASSIGNED_DRIVER';
  end if;

  select *
  into v_booking
  from public.package_bookings
  where id = v_activity.booking_id
  for update;

  select count(*)
  into v_total_items
  from public.booking_itinerary_items
  where booking_id = v_booking.id;

  select count(*)
  into v_completed_items
  from public.booking_itinerary_items
  where booking_id = v_booking.id
    and lower(coalesce(spot_status, 'pending')) = 'completed';

  if v_total_items = 0 or v_completed_items < v_total_items then
    raise exception 'INCOMPLETE_ITINERARY';
  end if;

  if v_activity.dropped_off_at is null
     and lower(coalesce(v_activity.tour_status, '')) <> 'ready_to_complete' then
    raise exception 'DROPOFF_NOT_COMPLETED';
  end if;

  if v_booking.booking_type = 'advanced' and coalesce(v_booking.remaining_balance, 0) > 0 then
    if not exists (
      select 1
      from public.payment_records
      where booking_id = v_booking.id
        and payment_stage = 'remaining_balance'
        and status = 'confirmed'
        and amount >= v_booking.remaining_balance
    ) then
      raise exception 'REMAINING_BALANCE_UNPAID';
    end if;
  end if;

  update public.package_activities
  set status = 'completed',
      tour_status = 'completed',
      current_spot_index = v_total_items,
      dropped_off_at = coalesce(dropped_off_at, now()),
      updated_at = now()
  where id = p_activity_id;

  update public.package_bookings
  set status = 'completed',
      booking_status = 'completed',
      current_spot_index = v_total_items,
      completed_at = coalesce(completed_at, now()),
      updated_at = now()
  where id = v_booking.id;

  update public.package_activities
  set dropped_off_at = coalesce(dropped_off_at, now())
  where id = p_activity_id;

  update public.booking_drivers
  set status = 'completed',
      completed_at = coalesce(completed_at, now())
  where booking_id = v_booking.id
    and driver_id = v_driver_id
    and status = 'accepted';

  return jsonb_build_object(
    'success', true,
    'activity_id', v_activity.id,
    'booking_id', v_booking.id,
    'completed_items', v_completed_items,
    'total_items', v_total_items
  );
end;
$$;

grant execute on function public.complete_package_tour(uuid, text) to authenticated;

-- ── 10. Drop now-orphaned wallet RPCs ────────────────────────
drop function if exists public.get_or_create_wallet(uuid, text);
drop function if exists public.credit_wallet(uuid, numeric);
drop function if exists public.debit_wallet(uuid, text, numeric);
drop function if exists public.deduct_wallet_balance(uuid, text, numeric, uuid, text, text, text);
drop function if exists public.credit_driver_wallet(uuid, numeric, uuid, text, text);
drop function if exists public.complete_wallet_cash_in(uuid, text, jsonb, numeric, text);

-- ── 11. Realtime ──────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'payment_records'
  ) then
    alter publication supabase_realtime add table public.payment_records;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'payment_disputes'
  ) then
    alter publication supabase_realtime add table public.payment_disputes;
  end if;
end $$;
