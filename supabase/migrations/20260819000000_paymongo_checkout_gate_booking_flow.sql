-- ============================================================
-- Gate advanced+GCash booking visibility on the down payment actually
-- clearing PayMongo Checkout, instead of collecting it later once a
-- driver is already assigned (see docs/payment-architecture.md Phase C3
-- design notes for the full rationale).
--
-- Two new functions, plus one touched function:
--
--   activate_booking_after_down_payment — called by
--     paymongo-create-checkout's "resolve" (success) action, right after
--     it calls record_payment_and_create_payouts. Flips a booking from
--     'pending_payment' (created hidden — driver_package_jobs_screen and
--     accept_package_booking both already only recognize 'pending' /
--     'waiting_for_drivers' as acceptable, so 'pending_payment' is
--     invisible to drivers for free, no query changes needed anywhere)
--     to 'waiting_for_drivers', at which point it behaves exactly like
--     any other booking always has.
--
--   fanout_pending_payouts_for_booking — closes a real gap: paying
--     before any driver is assigned means compute_payout_split() (see
--     20260805000000_convoy_phase0_data_model.sql) returns ZERO rows at
--     payment time, because it only ever splits across currently-
--     'accepted' booking_drivers rows, and there are none yet. So a
--     payment_records row can end up with no corresponding payout_records
--     at all. This function is the retroactive fix: given a booking,
--     find any 'confirmed' payment_records row with no payout_records
--     pointing at it yet, and run the split now that drivers exist.
--     Called once, from inside accept_package_booking, at the exact
--     moment the group becomes fully staffed (mirrors the existing
--     assumption baked into record_payment_and_create_payouts that
--     payment happens once the driver roster is known).
--
--   accept_package_booking — re-created byte-for-byte from the version
--     in 20260815000000_fix_total_passengers_type_drift.sql, with one
--     addition: a call to fanout_pending_payouts_for_booking() inside the
--     "group fully staffed" branch.
-- ============================================================

-- ── 1. activate_booking_after_down_payment ──────────────────────────────
create or replace function public.activate_booking_after_down_payment(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Idempotent: a redelivered/duplicate resolve call is a silent no-op,
  -- not an error — mirrors the idempotency pattern already used by
  -- record_payment_and_create_payouts (keyed on provider_payment_id) and
  -- advance_driver_journey_state (same-state no-op).
  update public.package_bookings
  set booking_status = 'waiting_for_drivers',
      updated_at = now()
  where id = p_booking_id
    and booking_status = 'pending_payment';
end;
$$;

grant execute on function public.activate_booking_after_down_payment(uuid) to service_role;

-- ── 2. fanout_pending_payouts_for_booking ───────────────────────────────
create or replace function public.fanout_pending_payouts_for_booking(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment record;
  v_split record;
begin
  for v_payment in
    select pr.id, pr.amount, pr.payment_stage
    from public.payment_records pr
    where pr.booking_id = p_booking_id
      and pr.status = 'confirmed'
      and not exists (
        select 1 from public.payout_records po
        where po.source_payment_record_id = pr.id
      )
  loop
    for v_split in
      select * from public.compute_payout_split(p_booking_id, v_payment.amount, 'equal_split')
    loop
      insert into public.payout_records (
        booking_id, driver_id, payment_stage, split_strategy, amount,
        gcash_number_snapshot, gcash_name_snapshot, status, source_payment_record_id
      )
      select
        p_booking_id, v_split.driver_id, v_payment.payment_stage, 'equal_split', v_split.amount,
        dd.gcash_number, dd.gcash_name, 'pending', v_payment.id
      from public.driver_details dd
      where dd.driver_id = v_split.driver_id
      on conflict (booking_id, driver_id, payment_stage) do nothing;
    end loop;
  end loop;
end;
$$;

-- Internal-only helper, called from accept_package_booking (SECURITY
-- DEFINER) — no direct grant to authenticated/service_role needed beyond
-- what its caller already has.

-- ── 3. accept_package_booking — add the fan-out call ────────────────────
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

    -- Defensive ::integer cast on both branches — see header comment.
    update public.booking_drivers bd
    set assigned_passengers = split.passenger_count
    from public.compute_passenger_split(
      p_booking_id,
      case when coalesce(v_booking.total_passengers, 0) > 0
           then v_booking.total_passengers::integer
           else (v_booking.adults + coalesce(v_booking.children, 0))::integer
      end
    ) as split
    where bd.booking_id = p_booking_id
      and bd.driver_id = split.driver_id;

    -- NEW: the group is now fully staffed — if the tourist already paid
    -- the down payment via PayMongo Checkout before any driver existed,
    -- compute_payout_split() returned nothing at that time (see header
    -- comment). Run the split now that booking_drivers is populated.
    perform public.fanout_pending_payouts_for_booking(p_booking_id);
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
