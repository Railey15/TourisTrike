-- ============================================================
-- PayMongo disbursement — RPCs + DB-driven triggers (Phase B1-B3).
--
-- Three SECURITY DEFINER RPCs, all service_role-only (the Edge Functions
-- are the only intended caller — nothing here is meant to be reachable
-- with a normal user JWT):
--
--   record_payment_and_create_payouts — payment webhook calls this once
--     PayMongo confirms a tourist payment. Idempotent on provider_payment_id.
--     Uses compute_payout_split (Phase 0) as the ONLY split-math source —
--     not reimplemented here.
--
--   claim_payout_for_disbursement — paymongo-disburse calls this before
--     ever talking to PayMongo/the stub. Re-derives the gate condition
--     itself from booking_drivers/package_bookings — never trusts the
--     caller's claim about journey_state, since the Edge Function's own
--     auth on this path is a shared secret, not a signed Postgres event.
--
--   record_transfer_submitted / record_transfer_result — write back the
--     transfer id after submission, and the terminal paid/failed status
--     once the (real or stubbed) callback lands.
--
-- Plus two triggers that fire the disbursement automatically:
--   booking_drivers.journey_state -> 'boarded'   => down_payment, per driver
--   package_bookings.booking_status -> 'completed' => remaining_balance, all drivers
-- via pg_net (fire-and-forget HTTP POST, doesn't block the state-change
-- transaction). The shared secret they send is read from a Postgres GUC
-- (app.settings.internal_trigger_secret) set separately via SQL editor —
-- deliberately NOT a literal in this file, since this file is committed
-- to git and a hardcoded secret here would defeat the point.
-- ============================================================

create extension if not exists pg_net with schema extensions;

-- ── 1. record_payment_and_create_payouts ────────────────────────────
create or replace function public.record_payment_and_create_payouts(
  p_provider_payment_id text,
  p_booking_id uuid,
  p_payment_stage text,
  p_amount numeric,
  p_payment_method text default 'gcash'
)
returns public.payment_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_payment public.payment_records;
  v_split record;
begin
  if p_payment_stage not in ('down_payment', 'remaining_balance', 'full') then
    raise exception 'INVALID_PAYMENT_STAGE: %', p_payment_stage;
  end if;

  select * into v_booking from public.package_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'BOOKING_NOT_FOUND';
  end if;

  -- Idempotent against webhook redelivery — same PayMongo payment id
  -- arriving twice is a no-op, not a duplicate payment_records row.
  select * into v_payment from public.payment_records where provider_payment_id = p_provider_payment_id;
  if found then
    return v_payment;
  end if;

  insert into public.payment_records (
    booking_id, payer_id, payee_id, amount, payment_method, payment_stage,
    status, provider_payment_id, service_description
  ) values (
    p_booking_id, v_booking.tourist_id, null, p_amount, p_payment_method, p_payment_stage,
    'confirmed', p_provider_payment_id, 'PayMongo payment — ' || p_payment_stage
  ) returning * into v_payment;

  for v_split in
    select * from public.compute_payout_split(p_booking_id, p_amount, 'equal_split')
  loop
    insert into public.payout_records (
      booking_id, driver_id, payment_stage, split_strategy, amount,
      gcash_number_snapshot, gcash_name_snapshot, status, source_payment_record_id
    )
    select
      p_booking_id, v_split.driver_id, p_payment_stage, 'equal_split', v_split.amount,
      dd.gcash_number, dd.gcash_name, 'pending', v_payment.id
    from public.driver_details dd
    where dd.driver_id = v_split.driver_id
    on conflict (booking_id, driver_id, payment_stage) do nothing;
  end loop;

  return v_payment;
end;
$$;

grant execute on function public.record_payment_and_create_payouts(text, uuid, text, numeric, text) to service_role;

-- ── 2. claim_payout_for_disbursement ────────────────────────────────
create or replace function public.claim_payout_for_disbursement(
  p_booking_id uuid,
  p_driver_id uuid,
  p_payment_stage text
)
returns public.payout_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.payout_records;
  v_gate_met boolean := false;
begin
  select * into v_row
  from public.payout_records
  where booking_id = p_booking_id
    and driver_id = p_driver_id
    and payment_stage = p_payment_stage
  for update;

  if not found then
    raise exception 'PAYOUT_RECORD_NOT_FOUND';
  end if;

  -- pending = never attempted. failed = a retry. Anything else
  -- (processing/paid) is already in flight or done — no-op, not an error,
  -- so a duplicate trigger fire or a double-tapped retry button is safe.
  if v_row.status not in ('pending', 'failed') then
    raise exception 'NOT_CLAIMABLE: status=%', v_row.status;
  end if;

  if p_payment_stage = 'down_payment' then
    select journey_state = 'boarded' into v_gate_met
    from public.booking_drivers
    where booking_id = p_booking_id and driver_id = p_driver_id and status = 'accepted';
  else
    select booking_status = 'completed' into v_gate_met
    from public.package_bookings
    where id = p_booking_id;
  end if;

  if not coalesce(v_gate_met, false) then
    raise exception 'GATE_NOT_MET';
  end if;

  update public.payout_records
  set status = 'processing',
      gate_satisfied_at = coalesce(gate_satisfied_at, now()),
      retry_count = case when v_row.status = 'failed' then retry_count + 1 else retry_count end,
      error_message = null,
      updated_at = now()
  where id = v_row.id
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.claim_payout_for_disbursement(uuid, uuid, text) to service_role;

-- ── 3. record_transfer_submitted ────────────────────────────────────
create or replace function public.record_transfer_submitted(
  p_payout_record_id uuid,
  p_paymongo_transfer_id text,
  p_reference_number text,
  p_provider_reference_number text,
  p_disbursement_mode text
)
returns public.payout_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.payout_records;
begin
  update public.payout_records
  set paymongo_transfer_id = p_paymongo_transfer_id,
      reference_number = p_reference_number,
      provider_reference_number = p_provider_reference_number,
      disbursement_mode = p_disbursement_mode,
      updated_at = now()
  where id = p_payout_record_id
  returning * into v_row;

  if not found then
    raise exception 'PAYOUT_RECORD_NOT_FOUND';
  end if;

  return v_row;
end;
$$;

grant execute on function public.record_transfer_submitted(uuid, text, text, text, text) to service_role;

-- ── 4. record_transfer_result ───────────────────────────────────────
create or replace function public.record_transfer_result(
  p_paymongo_transfer_id text,
  p_status text,
  p_provider_reference_number text default null,
  p_error_message text default null
)
returns public.payout_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.payout_records;
begin
  if p_status not in ('paid', 'failed') then
    raise exception 'INVALID_STATUS: %', p_status;
  end if;

  select * into v_row
  from public.payout_records
  where paymongo_transfer_id = p_paymongo_transfer_id
  for update;

  if not found then
    raise exception 'TRANSFER_NOT_FOUND: %', p_paymongo_transfer_id;
  end if;

  -- Idempotent — a redelivered webhook re-applying the same terminal
  -- status is a silent no-op.
  if v_row.status in ('paid', 'failed') then
    return v_row;
  end if;

  update public.payout_records
  set status = p_status,
      provider_reference_number = coalesce(p_provider_reference_number, provider_reference_number),
      error_message = case when p_status = 'failed' then p_error_message else null end,
      updated_at = now()
  where id = v_row.id
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.record_transfer_result(text, text, text, text) to service_role;

-- ── 5. fail_payout_precheck ─────────────────────────────────────────
-- For failures caught BEFORE PayMongo/the stub is ever called (e.g. the
-- driver's GCash isn't verified) — no paymongo_transfer_id exists yet to
-- key off of, so this takes the payout_record id directly. Only valid
-- from 'processing' (i.e. right after claim_payout_for_disbursement),
-- so it can't be used to fail an already-terminal row.
create or replace function public.fail_payout_precheck(
  p_payout_record_id uuid,
  p_error_message text
)
returns public.payout_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.payout_records;
begin
  update public.payout_records
  set status = 'failed',
      error_message = p_error_message,
      updated_at = now()
  where id = p_payout_record_id and status = 'processing'
  returning * into v_row;

  if not found then
    raise exception 'PAYOUT_RECORD_NOT_FOUND_OR_NOT_PROCESSING';
  end if;

  return v_row;
end;
$$;

grant execute on function public.fail_payout_precheck(uuid, text) to service_role;

-- ── 6. Auto-trigger disbursement on the gate events ─────────────────
create or replace function public.notify_paymongo_disburse()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := 'https://mvtqhsrdgtwdeootgjci.supabase.co/functions/v1/paymongo-disburse';
  v_secret text := coalesce(current_setting('app.settings.internal_trigger_secret', true), '');
  v_payload jsonb;
begin
  if tg_table_name = 'booking_drivers' then
    if new.journey_state <> 'boarded' or old.journey_state is not distinct from new.journey_state then
      return new;
    end if;
    v_payload := jsonb_build_object(
      'booking_id', new.booking_id,
      'driver_id', new.driver_id,
      'payment_stage', 'down_payment'
    );
  elsif tg_table_name = 'package_bookings' then
    if new.booking_status <> 'completed' or old.booking_status is not distinct from new.booking_status then
      return new;
    end if;
    -- No driver_id — paymongo-disburse fans this out to every accepted
    -- driver on the booking for the remaining_balance stage.
    v_payload := jsonb_build_object(
      'booking_id', new.id,
      'payment_stage', 'remaining_balance'
    );
  else
    return new;
  end if;

  if v_secret = '' then
    raise warning 'notify_paymongo_disburse: app.settings.internal_trigger_secret is unset — skipping HTTP call, payload=%', v_payload;
  else
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'X-Internal-Secret', v_secret),
      body := v_payload
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_disburse_on_boarded on public.booking_drivers;
create trigger trg_disburse_on_boarded
after update on public.booking_drivers
for each row execute function public.notify_paymongo_disburse();

drop trigger if exists trg_disburse_on_completed on public.package_bookings;
create trigger trg_disburse_on_completed
after update on public.package_bookings
for each row execute function public.notify_paymongo_disburse();
