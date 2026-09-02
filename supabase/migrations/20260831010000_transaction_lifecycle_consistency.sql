-- Atomic shared itinerary progression and payment-gated convoy completion.

begin;

create or replace function public.guard_package_booking_client_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Security-definer lifecycle/payment RPCs set this transaction-local flag.
  -- Direct tourist PostgREST writes never can.
  if coalesce(current_setting('touristrike.validated_transition', true), '') = 'true' then
    return new;
  end if;

  if public.current_profile_role() <> 'tourist' then return new; end if;

  if tg_op = 'INSERT' then
    if auth.uid() is null or new.tourist_id is distinct from auth.uid() then
      raise exception 'NOT_BOOKING_TOURIST';
    end if;
    if new.assigned_driver_id is not null then
      raise exception 'INVALID_INITIAL_ASSIGNED_DRIVER';
    end if;
    if coalesce(new.accepted_drivers_count, 0) <> 0 then
      raise exception 'INVALID_INITIAL_ACCEPTED_DRIVER_COUNT';
    end if;
    if new.required_drivers is null or new.required_drivers < 1 then
      raise exception 'INVALID_REQUIRED_DRIVERS';
    end if;
    if lower(coalesce(nullif(trim(new.status), ''), 'pending')) <> 'pending' then
      raise exception 'INVALID_INITIAL_STATUS';
    end if;
    if lower(coalesce(nullif(trim(new.booking_status), ''), 'waiting_for_drivers'))
       not in ('pending', 'waiting_for_drivers') then
      raise exception 'INVALID_INITIAL_BOOKING_STATE';
    end if;
    new.status := 'pending';
    new.booking_status := 'waiting_for_drivers';
    new.accepted_drivers_count := 0;

    -- Same-day and advance bookings share one staged PayMongo payment rule.
    if lower(coalesce(nullif(trim(new.payment_method), ''), '')) <> 'gcash' then
      raise exception 'PACKAGE_BOOKING_REQUIRES_GCASH';
    end if;
    if new.total_amount is null or new.downpayment_amount is null
       or new.remaining_balance is null then
      raise exception 'MISSING_PACKAGE_PAYMENT_AMOUNTS';
    end if;
    if new.downpayment_amount <> round(new.total_amount * 0.50, 2)
       or new.remaining_balance <> new.total_amount - new.downpayment_amount then
      raise exception 'INVALID_PACKAGE_PAYMENT_SPLIT';
    end if;
    return new;
  end if;

  if lower(coalesce(nullif(trim(new.booking_status), ''),
                    nullif(trim(new.status), ''), '')) = 'cancelled' then
    return new;
  end if;

  if new.status is distinct from old.status
     or new.booking_status is distinct from old.booking_status
     or new.assigned_driver_id is distinct from old.assigned_driver_id
     or new.accepted_drivers_count is distinct from old.accepted_drivers_count
     or new.required_drivers is distinct from old.required_drivers
     or new.booking_type is distinct from old.booking_type
     or new.payment_method is distinct from old.payment_method
     or new.total_amount is distinct from old.total_amount
     or new.downpayment_amount is distinct from old.downpayment_amount
     or new.remaining_balance is distinct from old.remaining_balance
     or new.travel_date is distinct from old.travel_date
     or new.scheduled_start_at is distinct from old.scheduled_start_at
     or new.estimated_end_at is distinct from old.estimated_end_at then
    raise exception 'BOOKING_UPDATE_RPC_REQUIRED';
  end if;
  return new;
end;
$$;

-- Repair unpaid, pre-tour same-day rows created by the legacy full-payment
-- branch. Never rewrite a booking whose payment stage has already started.
select set_config('touristrike.validated_transition', 'true', true);
update public.package_bookings pb
set payment_method = 'gcash',
    downpayment_amount = round(pb.total_amount * 0.50, 2),
    remaining_balance = pb.total_amount - round(pb.total_amount * 0.50, 2),
    updated_at = now()
where lower(coalesce(pb.booking_type, '')) = 'same_day'
  and coalesce(pb.total_amount, 0) > 0
  and coalesce(pb.downpayment_amount, 0) = 0
  and lower(coalesce(pb.booking_status, pb.status, '')) in (
    'pending', 'waiting_for_drivers', 'accepted', 'confirmed'
  )
  and not exists (
    select 1 from public.payment_records pr
    where pr.booking_id = pb.id and pr.status <> 'cancelled'
  );

create or replace function public.finalize_package_booking_if_eligible(
  p_booking_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_activity_id uuid;
  v_total_items integer := 0;
  v_completed_items integer := 0;
  v_required_slots integer := 1;
  v_active_slots integer := 0;
  v_completed_slots integer := 0;
  v_physical_tour_finished boolean := false;
  v_payment_satisfied boolean := false;
  v_overall_completed boolean := false;
  v_completion_progress jsonb;
begin
  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
     in ('cancelled', 'rejected') then
    return jsonb_build_object(
      'success', false,
      'booking_id', p_booking_id,
      'terminal_status', lower(coalesce(v_booking.booking_status, v_booking.status, '')),
      'overall_completed', false
    );
  end if;

  select count(*),
         count(*) filter (
           where lower(coalesce(bii.spot_status, 'pending')) = 'completed'
         )
  into v_total_items, v_completed_items
  from public.booking_itinerary_items bii
  where bii.booking_id = p_booking_id;

  v_required_slots := greatest(coalesce(v_booking.required_drivers, 1), 1);
  v_completion_progress := public.compute_convoy_stage_progress(
    p_booking_id, 'completed', null
  );
  v_active_slots := coalesce(
    (v_completion_progress->>'required_driver_count')::integer, 0
  );
  v_completed_slots := coalesce(
    (v_completion_progress->>'satisfied_driver_count')::integer, 0
  );

  v_physical_tour_finished :=
    v_total_items > 0
    and v_completed_items = v_total_items
    and v_active_slots >= v_required_slots
    and v_completed_slots = v_active_slots;

  v_payment_satisfied :=
    coalesce(v_booking.remaining_balance, 0) <= 0
    or exists (
      select 1
      from public.booking_payment_requirements bpr
      where bpr.booking_id = p_booking_id
        and bpr.payment_stage = 'remaining_balance'
        and bpr.amount >= v_booking.remaining_balance
        and (
          bpr.status = 'waived'
          or (
            bpr.status = 'satisfied'
            and exists (
              select 1
              from public.payment_records pr
              where pr.id = bpr.satisfied_by_payment_record_id
                and pr.booking_id = p_booking_id
                and pr.payment_stage = 'remaining_balance'
                and pr.status = 'confirmed'
                and pr.amount >= v_booking.remaining_balance
            )
          )
        )
    );

  select pa.id into v_activity_id
  from public.package_activities pa
  where pa.booking_id = p_booking_id
  limit 1;

  if v_physical_tour_finished then
    perform set_config('touristrike.validated_transition', 'true', true);

    if v_payment_satisfied then
      v_overall_completed := true;

      update public.package_activities
      set status = 'completed',
          tour_status = 'completed',
          current_spot_index = v_total_items,
          dropped_off_at = coalesce(dropped_off_at, now()),
          updated_at = now()
      where id = v_activity_id;

      update public.package_bookings
      set status = 'completed',
          booking_status = 'completed',
          current_spot_index = v_total_items,
          completed_at = coalesce(completed_at, now()),
          updated_at = now()
      where id = p_booking_id;
    else
      update public.package_activities
      set status = 'ongoing',
          tour_status = 'ready_to_complete',
          current_spot_index = v_total_items,
          dropped_off_at = coalesce(dropped_off_at, now()),
          updated_at = now()
      where id = v_activity_id;

      update public.package_bookings
      set status = case when status = 'completed' then 'confirmed' else status end,
          booking_status = 'awaiting_final_payment',
          current_spot_index = v_total_items,
          completed_at = null,
          updated_at = now()
      where id = p_booking_id;
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'booking_id', p_booking_id,
    'physical_tour_finished', v_physical_tour_finished,
    'remaining_payment_satisfied', v_payment_satisfied,
    'awaiting_final_payment', v_physical_tour_finished and not v_payment_satisfied,
    'overall_completed', v_overall_completed,
    'completed_items', v_completed_items,
    'total_items', v_total_items,
    'completed_slots', v_completed_slots,
    'active_slots', v_active_slots,
    'required_slots', v_required_slots
  );
end;
$$;

revoke all on function public.finalize_package_booking_if_eligible(uuid)
  from public, anon, authenticated;

-- One authoritative convoy-membership and stage-satisfaction calculation.
-- A completed assignment remains a required member and is satisfied at every
-- earlier stage instead of disappearing from an accepted-only query.
create or replace function public.compute_convoy_stage_progress(
  p_booking_id uuid,
  p_stage text,
  p_stop_index integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_stage text := lower(coalesce(nullif(trim(p_stage), ''), ''));
  v_required_count integer := 0;
  v_satisfied_count integer := 0;
  v_waiting_driver_ids jsonb := '[]'::jsonb;
  v_driver_states jsonb := '[]'::jsonb;
begin
  if not exists (
    select 1 from public.package_bookings where id = p_booking_id
  ) then raise exception 'BOOKING_NOT_FOUND'; end if;

  if v_stage not in (
    'assigned', 'en_route_pickup', 'at_pickup', 'boarded',
    'at_stop', 'stop_done', 'at_dropoff', 'completed'
  ) then raise exception 'INVALID_CONVOY_STAGE: %', v_stage; end if;
  if v_stage in ('at_stop', 'stop_done') and p_stop_index is null then
    raise exception 'STOP_INDEX_REQUIRED';
  end if;

  with required_assignments as (
    select bd.*,
      case
        when bd.status = 'completed' or bd.journey_state = 'completed' then true
        when v_stage = 'at_stop' then
          bd.current_stop_index > p_stop_index
          or (
            bd.current_stop_index = p_stop_index
            and bd.journey_state in (
              'at_stop', 'stop_done', 'en_route_dropoff', 'at_dropoff'
            )
          )
        when v_stage = 'stop_done' then
          bd.current_stop_index > p_stop_index
          or (
            bd.current_stop_index = p_stop_index
            and bd.journey_state in (
              'stop_done', 'en_route_dropoff', 'at_dropoff'
            )
          )
        else public.journey_state_order(bd.journey_state)
          >= public.journey_state_order(v_stage)
      end as satisfied
    from public.booking_drivers bd
    where bd.booking_id = p_booking_id
      and bd.status in ('accepted', 'completed')
  )
  select count(*),
         count(*) filter (where satisfied),
         coalesce(
           jsonb_agg(driver_id order by accepted_at, id)
             filter (where not satisfied),
           '[]'::jsonb
         ),
         coalesce(
           jsonb_agg(
             jsonb_build_object(
               'assignment_id', id,
               'driver_id', driver_id,
               'assignment_status', status,
               'journey_state', journey_state,
               'current_stop_index', current_stop_index,
               'satisfied', satisfied
             ) order by accepted_at, id
           ),
           '[]'::jsonb
         )
  into v_required_count, v_satisfied_count,
       v_waiting_driver_ids, v_driver_states
  from required_assignments;

  return jsonb_build_object(
    'booking_id', p_booking_id,
    'stage', v_stage,
    'stop_index', p_stop_index,
    'required_driver_count', v_required_count,
    'satisfied_driver_count', v_satisfied_count,
    'all_satisfied', v_required_count > 0
      and v_satisfied_count = v_required_count,
    'waiting_driver_ids', v_waiting_driver_ids,
    'driver_states', v_driver_states
  );
end;
$$;

revoke all on function public.compute_convoy_stage_progress(uuid, text, integer)
  from public, anon, authenticated;

create or replace function public.get_convoy_stage_progress(
  p_booking_id uuid,
  p_stage text,
  p_stop_index integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if coalesce(public.current_profile_role(), '') not in ('admin', 'subtenant')
     and not exists (
       select 1 from public.package_bookings pb
       where pb.id = p_booking_id and pb.tourist_id = v_user_id
     )
     and not exists (
       select 1 from public.booking_drivers bd
       where bd.booking_id = p_booking_id
         and bd.driver_id = v_user_id
         and bd.status in ('accepted', 'completed')
     ) then
    raise exception 'NOT_BOOKING_PARTICIPANT';
  end if;
  return public.compute_convoy_stage_progress(
    p_booking_id, p_stage, p_stop_index
  );
end;
$$;

revoke all on function public.get_convoy_stage_progress(uuid, text, integer)
  from public, anon;
grant execute on function public.get_convoy_stage_progress(uuid, text, integer)
  to authenticated;

-- Payment creation, cash confirmation, convoy barriers, and map membership
-- must all agree on the same required assignment set. A completed assignment
-- is still a valid member of the booking and must keep its payment allocation.
create or replace function public.required_booking_driver_roster(
  p_booking_id uuid
)
returns setof public.booking_drivers
language sql
stable
security definer
set search_path = public
as $$
  select bd.*
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id
    and bd.status in ('accepted', 'completed')
  order by bd.accepted_at, bd.id;
$$;

revoke all on function public.required_booking_driver_roster(uuid)
  from public, anon, authenticated;

create or replace function public.is_booking_driver_roster_full(
  p_booking_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_required_count integer;
  v_roster_count integer;
begin
  select greatest(coalesce(pb.required_drivers, 1), 1)
  into v_required_count
  from public.package_bookings pb
  where pb.id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  select count(*) into v_roster_count
  from public.required_booking_driver_roster(p_booking_id);
  return v_roster_count = v_required_count;
end;
$$;

revoke all on function public.is_booking_driver_roster_full(uuid)
  from public, anon, authenticated;

-- Booking type describes scheduling only. The confirmed payment record is the
-- single source of truth for whether any package booking may start.
create or replace function public.is_booking_downpayment_confirmed(
  p_booking_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_required_amount numeric(14,2);
begin
  select round(
    case
      when coalesce(pb.downpayment_amount, 0) > 0
        then pb.downpayment_amount
      else coalesce(pb.total_amount, 0) * 0.50
    end,
    2
  )
  into v_required_amount
  from public.package_bookings pb
  where pb.id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if v_required_amount <= 0 then return true; end if;

  return exists (
    select 1
    from public.payment_records pr
    where pr.booking_id = p_booking_id
      and pr.payment_stage in ('down_payment', 'full')
      and pr.status = 'confirmed'
      and pr.amount >= v_required_amount
  );
end;
$$;

revoke all on function public.is_booking_downpayment_confirmed(uuid)
  from public, anon, authenticated;

-- Replace the earlier accepted-only implementation. Requirements may need to
-- be recreated or reconciled after assignments have already completed.
create or replace function public.ensure_booking_payment_requirements(
  p_booking_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_written integer := 0;
begin
  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if not public.is_booking_driver_roster_full(p_booking_id) then
    return 0;
  end if;
  if coalesce(v_booking.downpayment_amount, 0) > 0 then
    insert into public.booking_payment_requirements(
      booking_id, payment_stage, amount
    ) values (
      p_booking_id, 'down_payment', round(v_booking.downpayment_amount, 2)
    )
    on conflict (booking_id, payment_stage) do update
    set amount = excluded.amount,
        status = case
          when booking_payment_requirements.status in ('satisfied', 'waived')
            then booking_payment_requirements.status
          else 'required'
        end;
    v_written := v_written + 1;
  end if;

  if coalesce(v_booking.remaining_balance, 0) > 0 then
    insert into public.booking_payment_requirements(
      booking_id, payment_stage, amount
    ) values (
      p_booking_id, 'remaining_balance', round(v_booking.remaining_balance, 2)
    )
    on conflict (booking_id, payment_stage) do update
    set amount = excluded.amount,
        status = case
          when booking_payment_requirements.status in ('satisfied', 'waived')
            then booking_payment_requirements.status
          else 'required'
        end;
    v_written := v_written + 1;
  end if;

  return v_written;
end;
$$;

revoke all on function public.ensure_booking_payment_requirements(uuid)
  from public, anon, authenticated;

create or replace function public.is_booking_remaining_payment_satisfied(
  p_booking_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_booking public.package_bookings;
begin
  select * into v_booking
  from public.package_bookings
  where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if coalesce(v_booking.remaining_balance, 0) <= 0 then
    return true;
  end if;

  return exists (
    select 1
    from public.booking_payment_requirements bpr
    where bpr.booking_id = p_booking_id
      and bpr.payment_stage = 'remaining_balance'
      and (
        bpr.status = 'waived'
        or (
          bpr.status = 'satisfied'
          and exists (
            select 1
            from public.payment_records pr
            where pr.id = bpr.satisfied_by_payment_record_id
              and pr.booking_id = p_booking_id
              and pr.payment_stage = 'remaining_balance'
              and pr.status = 'confirmed'
              and pr.amount >= bpr.amount
          )
        )
      )
  );
end;
$$;

revoke all on function public.is_booking_remaining_payment_satisfied(uuid)
  from public, anon, authenticated;

create or replace function public.is_booking_itinerary_complete(
  p_booking_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select count(*) > 0
    and count(*) filter (
      where lower(coalesce(bii.spot_status, 'pending')) = 'completed'
    ) = count(*)
  from public.booking_itinerary_items bii
  where bii.booking_id = p_booking_id;
$$;

revoke all on function public.is_booking_itinerary_complete(uuid)
  from public, anon, authenticated;

-- Validate payment stages by the booking's staged amounts, never its schedule
-- type. PayMongo remains the only route for a downpayment confirmation.
create or replace function public.validate_booking_payment_submission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_required_amount numeric;
  v_trusted_group_cash boolean :=
    coalesce(current_setting('touristrike.trusted_group_cash', true), '') = 'true';
begin
  if new.booking_id is null then return new; end if;

  select * into v_booking from public.package_bookings
  where id = new.booking_id for key share;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if new.provider = 'paymongo' then
    if auth.uid() is null or new.payer_id <> auth.uid()
       or new.payer_id <> v_booking.tourist_id then
      raise exception 'NOT_BOOKING_TOURIST';
    end if;
    if new.payee_id is not null then
      raise exception 'PAYMONGO_PAYEE_MUST_BE_NULL';
    end if;
    if new.payment_method <> 'gcash' then
      raise exception 'PAYMONGO_GCASH_REQUIRED';
    end if;
  elsif new.payee_id is null then
    if not v_trusted_group_cash or new.payer_id <> v_booking.tourist_id
       or new.payment_method <> 'cash'
       or new.payment_stage <> 'remaining_balance'
       or new.provider_status <> 'awaiting_cash_receipt' then
      raise exception 'TRUSTED_GROUP_CASH_BACKEND_REQUIRED';
    end if;
  elsif auth.uid() is null or new.payer_id <> auth.uid()
        or new.payer_id <> v_booking.tourist_id then
    raise exception 'NOT_BOOKING_TOURIST';
  elsif not exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = new.booking_id
      and bd.driver_id = new.payee_id
      and bd.status in ('accepted', 'completed')
  ) then
    raise exception 'PAYEE_NOT_ASSIGNED_DRIVER';
  end if;

  if lower(coalesce(v_booking.booking_status, v_booking.status, 'pending'))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_PAYABLE';
  end if;

  if new.payment_stage = 'down_payment' then
    v_required_amount := v_booking.downpayment_amount;
    if new.provider <> 'paymongo' or new.payment_method <> 'gcash' then
      raise exception 'DOWN_PAYMENT_REQUIRES_PAYMONGO_GCASH';
    end if;
  elsif new.payment_stage = 'remaining_balance' then
    v_required_amount := v_booking.remaining_balance;
    if not (
      (new.provider = 'paymongo' and new.payment_method = 'gcash')
      or (new.provider = 'manual' and new.payment_method = 'cash')
    ) then
      raise exception 'INVALID_REMAINING_PAYMENT_ROUTE';
    end if;
  else
    raise exception 'INVALID_PACKAGE_PAYMENT_STAGE';
  end if;

  if coalesce(v_required_amount, 0) <= 0
     or new.amount <> round(v_required_amount, 2) then
    raise exception 'INVALID_PAYMENT_AMOUNT';
  end if;
  if not exists (
    select 1 from public.booking_payment_requirements bpr
    where bpr.booking_id = new.booking_id
      and bpr.payment_stage = new.payment_stage
      and bpr.status <> 'waived'
      and bpr.amount = new.amount
  ) then
    raise exception 'PAYMENT_STAGE_NOT_REQUIRED';
  end if;

  return new;
end;
$$;

-- Override the trusted implementation behind the authenticated wrapper from
-- 20260829010000, preserving auth.uid() in the tourist's JWT context.
create or replace function public.prepare_paymongo_payment_authenticated_impl(
  p_booking_id uuid,
  p_payment_stage text,
  p_idempotency_key text,
  p_tourist_id uuid,
  p_provider_livemode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_payment public.payment_records;
  v_stage text := case when p_payment_stage = 'full_payment'
    then 'full' else p_payment_stage end;
  v_amount numeric(14,2);
  v_roster_count integer;
begin
  if p_tourist_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 16
     or length(p_idempotency_key) > 255 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  select * into v_booking from public.package_bookings
  where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking.tourist_id <> p_tourist_id then
    raise exception 'NOT_BOOKING_TOURIST';
  end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_PAYABLE';
  end if;

  select * into v_payment from public.payment_records
  where provider = 'paymongo' and idempotency_key = p_idempotency_key;
  if found then
    if v_payment.booking_id <> p_booking_id
       or v_payment.payment_stage <> v_stage
       or v_payment.payer_id <> p_tourist_id then
      raise exception 'IDEMPOTENCY_KEY_REUSED';
    end if;
    return jsonb_build_object(
      'payment', to_jsonb(v_payment),
      'amount_centavos', (v_payment.amount * 100)::bigint,
      'allocations', coalesce((
        select jsonb_agg(to_jsonb(a) order by a.created_at, a.id)
        from public.payment_allocations a
        where a.payment_record_id = v_payment.id
      ), '[]'::jsonb),
      'reused', true
    );
  end if;

  select count(*) into v_roster_count
  from public.required_booking_driver_roster(p_booking_id);
  if not public.is_booking_driver_roster_full(p_booking_id) then
    raise exception 'DRIVER_ROSTER_NOT_FULL';
  end if;

  perform public.ensure_booking_payment_requirements(p_booking_id);
  if v_stage = 'down_payment' then
    v_amount := v_booking.downpayment_amount;
  elsif v_stage = 'remaining_balance' then
    if not public.is_booking_itinerary_complete(p_booking_id) then
      raise exception 'REMAINING_PAYMENT_NOT_DUE';
    end if;
    if not public.is_booking_downpayment_confirmed(p_booking_id) then
      raise exception 'DOWNPAYMENT_NOT_CONFIRMED';
    end if;
    v_amount := v_booking.remaining_balance;
  else
    raise exception 'INVALID_PACKAGE_PAYMENT_STAGE';
  end if;
  if not exists (
    select 1 from public.booking_payment_requirements
    where booking_id = p_booking_id and payment_stage = v_stage
      and status = 'required' and amount = v_amount
  ) then
    raise exception 'PAYMENT_STAGE_NOT_DUE';
  end if;
  v_amount := round(v_amount, 2);
  if coalesce(v_amount, 0) <= 0 then raise exception 'INVALID_PAYMENT_AMOUNT'; end if;

  select * into v_payment from public.payment_records
  where booking_id = p_booking_id and payment_stage = v_stage
    and status <> 'cancelled' for update;
  if found then
    if v_payment.provider <> 'paymongo' then
      raise exception 'PAYMENT_STAGE_ALREADY_HAS_MANUAL_RECORD';
    end if;
    return jsonb_build_object(
      'payment', to_jsonb(v_payment),
      'amount_centavos', (v_payment.amount * 100)::bigint,
      'allocations', coalesce((
        select jsonb_agg(to_jsonb(a) order by a.created_at, a.id)
        from public.payment_allocations a
        where a.payment_record_id = v_payment.id
      ), '[]'::jsonb),
      'reused', true
    );
  end if;

  insert into public.payment_records(
    booking_id, payer_id, payee_id, amount, payment_method, payment_stage,
    status, provider, currency, provider_reference, provider_status,
    provider_livemode, idempotency_key, service_description
  ) values (
    p_booking_id, p_tourist_id, null, v_amount, 'gcash', v_stage,
    'pending_confirmation', 'paymongo', 'PHP', gen_random_uuid()::text,
    'preparing_checkout', p_provider_livemode, p_idempotency_key,
    'TourisTrike package booking payment'
  ) returning * into v_payment;

  insert into public.payment_allocations(
    payment_record_id, booking_id, booking_driver_id, driver_id,
    gross_amount, platform_fee, driver_amount, split_basis_points,
    currency, status, provider_recipient_id
  )
  with ranked as (
    select bd.*,
      (row_number() over (order by bd.accepted_at, bd.id))::integer
        as recipient_position
    from public.required_booking_driver_roster(p_booking_id) bd
  )
  select v_payment.id, p_booking_id, bd.id, bd.driver_id,
         split.amount_centavos / 100.0, 0, split.amount_centavos / 100.0,
         split.basis_points, 'PHP', 'held', dpa.provider_recipient_id
  from ranked bd
  join public.compute_equal_split_centavos(
    (v_amount * 100)::bigint, v_roster_count
  ) split on split.recipient_position = bd.recipient_position
  left join lateral (
    select account.provider_recipient_id
    from public.driver_payout_accounts account
    where account.driver_id = bd.driver_id
      and account.provider = 'paymongo'
      and account.destination_type = 'linked_account'
      and account.verification_status = 'verified'
      and account.is_default
      and account.provider_livemode = p_provider_livemode
    order by account.updated_at desc limit 1
  ) dpa on true;

  perform public.assert_payment_allocation_total(v_payment.id);

  return jsonb_build_object(
    'payment', to_jsonb(v_payment),
    'amount_centavos', (v_amount * 100)::bigint,
    'allocations', (
      select jsonb_agg(
        ranked.allocation || jsonb_build_object(
          'split_basis_points', ranked.allocation->'split_basis_points'
        ) order by ranked.recipient_position
      )
      from (
        select to_jsonb(a) as allocation,
          row_number() over (order by bd.accepted_at, bd.id)
            as recipient_position
        from public.payment_allocations a
        join public.booking_drivers bd on bd.id = a.booking_driver_id
        where a.payment_record_id = v_payment.id
      ) ranked
    ),
    'reused', false
  );
end;
$$;

revoke all on function public.prepare_paymongo_payment_authenticated_impl(
  uuid, text, text, uuid, boolean
) from public, anon, authenticated, service_role;

create or replace function public.prepare_group_cash_remaining_balance(
  p_booking_id uuid,
  p_idempotency_key text
)
returns public.payment_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_payment public.payment_records;
  v_roster_count integer;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 16
     or length(p_idempotency_key) > 255 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  select * into v_booking from public.package_bookings
  where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking.tourist_id <> auth.uid() then
    raise exception 'NOT_BOOKING_TOURIST';
  end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_PAYABLE';
  end if;

  select count(*) into v_roster_count
  from public.required_booking_driver_roster(p_booking_id);
  if not public.is_booking_driver_roster_full(p_booking_id) then
    raise exception 'DRIVER_ROSTER_NOT_FULL';
  end if;

  perform public.ensure_booking_payment_requirements(p_booking_id);
  if not public.is_booking_itinerary_complete(p_booking_id) then
    raise exception 'REMAINING_PAYMENT_NOT_DUE';
  end if;
  if not public.is_booking_downpayment_confirmed(p_booking_id) then
    raise exception 'DOWNPAYMENT_NOT_CONFIRMED';
  end if;
  if not exists (
    select 1 from public.booking_payment_requirements
    where booking_id = p_booking_id and payment_stage = 'remaining_balance'
      and status = 'required' and amount = v_booking.remaining_balance
  ) then raise exception 'PAYMENT_STAGE_NOT_DUE'; end if;

  select * into v_payment from public.payment_records
  where booking_id = p_booking_id and payment_stage = 'remaining_balance'
    and status <> 'cancelled'
  order by created_at desc limit 1 for update;
  if found then
    if v_payment.provider = 'manual' and v_payment.payment_method = 'cash'
       and v_payment.payee_id is null then
      return v_payment;
    end if;
    raise exception 'PAYMENT_STAGE_ALREADY_STARTED';
  end if;

  perform set_config('touristrike.trusted_group_cash', 'true', true);
  insert into public.payment_records(
    booking_id, payer_id, payee_id, amount, payment_method, payment_stage,
    status, provider, currency, provider_status, idempotency_key,
    service_description
  ) values (
    p_booking_id, auth.uid(), null, round(v_booking.remaining_balance, 2),
    'cash', 'remaining_balance', 'pending_confirmation', 'manual', 'PHP',
    'awaiting_cash_receipt', p_idempotency_key,
    'Cash remaining balance for TourisTrike package booking'
  ) returning * into v_payment;

  insert into public.payment_allocations(
    payment_record_id, booking_id, booking_driver_id, driver_id,
    gross_amount, platform_fee, driver_amount, split_basis_points,
    currency, status
  )
  with ranked as (
    select bd.*,
      (row_number() over (order by bd.accepted_at, bd.id))::integer
        as recipient_position
    from public.required_booking_driver_roster(p_booking_id) bd
  )
  select v_payment.id, p_booking_id, bd.id, bd.driver_id,
         split.amount_centavos / 100.0, 0, split.amount_centavos / 100.0,
         split.basis_points, 'PHP', 'awaiting_cash'
  from ranked bd
  join public.compute_equal_split_centavos(
    (round(v_booking.remaining_balance, 2) * 100)::bigint, v_roster_count
  ) split on split.recipient_position = bd.recipient_position;

  if (select count(*) from public.payment_allocations
      where payment_record_id = v_payment.id) <> v_roster_count
     or (select coalesce(sum(gross_amount), 0)
         from public.payment_allocations
         where payment_record_id = v_payment.id)
        <> round(v_booking.remaining_balance, 2) then
    raise exception 'CASH_ALLOCATION_TOTAL_MISMATCH';
  end if;

  raise log '[TourisTrike payment] group cash prepared booking=%, payment=%, drivers=%',
    p_booking_id, v_payment.id, v_roster_count;
  return v_payment;
end;
$$;

revoke all on function public.prepare_group_cash_remaining_balance(uuid, text)
  from public, anon;
grant execute on function public.prepare_group_cash_remaining_balance(uuid, text)
  to authenticated;

-- PostgreSQL cannot remove an existing argument DEFAULT with
-- CREATE OR REPLACE FUNCTION. Drop both legacy overloads first so the
-- explicit-item overload can require p_itinerary_item_id without leaving an
-- ambiguous one-argument RPC call.
drop function if exists public.complete_current_itinerary_item(uuid, text);
drop function if exists public.complete_current_itinerary_item(uuid, uuid, text);

create or replace function public.complete_current_itinerary_item(
  p_activity_id uuid,
  p_itinerary_item_id uuid,
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
  v_assignment public.booking_drivers;
  v_item public.booking_itinerary_items;
  v_item_index integer;
  v_total_items integer := 0;
  v_completed_items integer := 0;
  v_stage_progress jsonb;
  v_missing_arrivals integer := 0;
  v_latest_arrival timestamptz;
  v_is_test_booking boolean := false;
  v_remaining_payment_satisfied boolean := false;
  v_changed_driver record;
  v_spot_status_list jsonb := '[]'::jsonb;
begin
  if v_driver_id is null then raise exception 'UNAUTHENTICATED'; end if;

  select * into v_activity
  from public.package_activities
  where id = p_activity_id;
  if not found then raise exception 'ACTIVITY_NOT_FOUND'; end if;

  select * into v_booking
  from public.package_bookings
  where id = v_activity.booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  v_is_test_booking := public.is_developer_test_booking(v_booking.id);

  select * into v_assignment
  from public.booking_drivers bd
  where bd.booking_id = v_booking.id
    and bd.driver_id = v_driver_id
    and bd.status in ('accepted', 'completed')
  for update;
  if not found then raise exception 'NOT_ASSIGNED_DRIVER'; end if;

  if p_itinerary_item_id is null then
    select item.* into v_item
    from public.booking_itinerary_items item
    where item.booking_id = v_booking.id
      and lower(coalesce(item.spot_status, 'pending')) <> 'completed'
    order by coalesce(item.order_number, 2147483647),
             coalesce(item.destination_order, 2147483647),
             item.arrival_time nulls last, item.created_at, item.id
    limit 1
    for update;
  else
    select item.* into v_item
    from public.booking_itinerary_items item
    where item.id = p_itinerary_item_id
      and item.booking_id = v_booking.id
    for update;
  end if;
  if not found then raise exception 'ITINERARY_ITEM_NOT_FOUND'; end if;

  select ordered.item_index into v_item_index
  from (
    select bii.id,
           (row_number() over (
             order by coalesce(bii.order_number, 2147483647),
                      coalesce(bii.destination_order, 2147483647),
                      bii.arrival_time nulls last, bii.created_at, bii.id
           ))::integer - 1 as item_index
    from public.booking_itinerary_items bii
    where bii.booking_id = v_booking.id
  ) ordered
  where ordered.id = v_item.id;

  select count(*) into v_total_items
  from public.booking_itinerary_items
  where booking_id = v_booking.id;

  if lower(coalesce(v_item.spot_status, 'pending')) = 'completed' then
    select count(*) into v_completed_items
    from public.booking_itinerary_items
    where booking_id = v_booking.id
      and lower(coalesce(spot_status, 'pending')) = 'completed';

    return jsonb_build_object(
      'success', true,
      'already_completed', true,
      'booking_id', v_booking.id,
      'activity_id', v_activity.id,
      'current_itinerary_item_id', v_item.id,
      'current_spot_index', v_item_index,
      'completed_items', v_completed_items,
      'total_items', v_total_items,
      'tour_completed', v_completed_items = v_total_items,
      'convoy_progress', public.compute_convoy_stage_progress(
        v_booking.id, 'stop_done', v_item_index
      )
    );
  end if;

  if v_assignment.journey_state <> 'at_stop' then
    raise exception 'INVALID_TRANSITION: % -> stop_done', v_assignment.journey_state;
  end if;

  if v_assignment.current_stop_index <> v_item_index then
    raise exception 'STALE_ITINERARY_STOP';
  end if;

  v_stage_progress := public.compute_convoy_stage_progress(
    v_booking.id, 'at_stop', v_item_index
  );
  if not coalesce((v_stage_progress->>'all_satisfied')::boolean, false) then
    raise exception 'BARRIER_NOT_MET';
  end if;

  select count(*) filter (where bda.booking_driver_id is null),
         max(bda.arrived_at)
  into v_missing_arrivals, v_latest_arrival
  from public.booking_drivers bd
  left join public.booking_driver_arrivals bda
    on bda.booking_driver_id = bd.id
   and bda.itinerary_item_id = v_item.id
  where bd.booking_id = v_booking.id
    and bd.status = 'accepted';
  if v_missing_arrivals > 0 then
    raise exception 'CONVOY_ARRIVAL_NOT_RECORDED';
  end if;

  if not v_is_test_booking
     and coalesce(v_item.estimated_stay_duration_minutes, 0) > 0
     and now() < v_latest_arrival
       + make_interval(mins => v_item.estimated_stay_duration_minutes) then
    raise exception 'STOP_DWELL_TIME_NOT_MET';
  end if;

  update public.booking_itinerary_items
  set spot_status = 'completed',
      actual_departure_time = coalesce(actual_departure_time, now()),
      updated_at = now()
  where id = v_item.id;

  for v_changed_driver in
    update public.booking_drivers
    set journey_state = 'stop_done',
        state_updated_at = now()
    where booking_id = v_booking.id
      and status = 'accepted'
      and current_stop_index = v_item_index
      and journey_state = 'at_stop'
    returning driver_id
  loop
    insert into public.trip_status_logs(
      activity_id, booking_id, driver_id, status, previous_state, new_state,
      spot_index, logged_at, notes
    ) values (
      v_activity.id, v_booking.id, v_changed_driver.driver_id, 'on_tour',
      'at_stop', 'stop_done', v_item_index, now(),
      'Atomic shared itinerary stop completion'
    );
  end loop;

  select count(*) into v_completed_items
  from public.booking_itinerary_items
  where booking_id = v_booking.id
    and lower(coalesce(spot_status, 'pending')) = 'completed';

  v_remaining_payment_satisfied :=
    public.is_booking_remaining_payment_satisfied(v_booking.id);

  perform set_config('touristrike.validated_transition', 'true', true);
  update public.package_activities
  set status = 'ongoing',
      tour_status = case
        when v_completed_items = v_total_items
             and not v_remaining_payment_satisfied
          then 'awaiting_remaining_payment'
        else 'on_tour'
      end,
      current_spot_index = v_item_index, updated_at = now()
  where id = v_activity.id;
  update public.package_bookings
  set booking_status = case
        when v_completed_items = v_total_items
             and not v_remaining_payment_satisfied
          then 'awaiting_remaining_payment'
        else 'on_tour'
      end,
      current_spot_index = v_item_index,
      updated_at = now()
  where id = v_booking.id;

  select coalesce(jsonb_agg(
    jsonb_build_object('id', id, 'order_number', order_number,
      'destination_order', destination_order, 'spot_status', spot_status)
    order by coalesce(order_number, 2147483647),
      coalesce(destination_order, 2147483647), arrival_time nulls last,
      created_at, id
  ), '[]'::jsonb)
  into v_spot_status_list
  from public.booking_itinerary_items
  where booking_id = v_booking.id;

  return jsonb_build_object(
    'success', true,
    'already_completed', false,
    'booking_id', v_booking.id,
    'activity_id', v_activity.id,
    'current_itinerary_item_id', v_item.id,
    'current_spot_index', v_item_index,
    'completed_items', v_completed_items,
    'total_items', v_total_items,
    'tour_completed', v_completed_items = v_total_items,
    'awaiting_remaining_payment', v_completed_items = v_total_items
      and not v_remaining_payment_satisfied,
    'convoy_state', 'stop_done',
    'convoy_progress', public.compute_convoy_stage_progress(
      v_booking.id, 'stop_done', v_item_index
    ),
    'spot_status_list', v_spot_status_list
  );
end;
$$;

create or replace function public.complete_current_itinerary_item(
  p_activity_id uuid,
  p_remaining_payment_method text default null
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.complete_current_itinerary_item(
    p_activity_id, null::uuid, p_remaining_payment_method
  );
$$;

grant execute on function public.complete_current_itinerary_item(uuid, uuid, text)
  to authenticated;
grant execute on function public.complete_current_itinerary_item(uuid, text)
  to authenticated;

create or replace function public.advance_driver_journey_state(
  p_booking_id uuid,
  p_target_state text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_booking public.package_bookings;
  v_current text;
  v_stop_index integer;
  v_is_gated boolean := false;
  v_new_stop_index integer;
  v_all_cleared boolean;
  v_slowest_state text;
  v_legacy_status text;
  v_activity_id uuid;
  v_accepted_count integer;
  v_total_items integer;
  v_completed_items integer;
  v_is_test_booking boolean := false;
  v_debug_bypass boolean := false;
  v_finalization jsonb;
  v_stage_progress jsonb;
begin
  if v_driver_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if public.journey_state_order(p_target_state) is null then
    raise exception 'INVALID_STATE: %', p_target_state;
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
     in ('cancelled', 'rejected') then
    raise exception 'CANCELLED_BOOKING_CANNOT_ADVANCE';
  end if;

  v_is_test_booking := public.is_developer_test_booking(p_booking_id);
  v_debug_bypass := v_is_test_booking and coalesce(
    current_setting('touristrike.debug_progression_bypass', true), ''
  ) = 'true';

  select journey_state, current_stop_index into v_current, v_stop_index
  from public.booking_drivers
  where booking_id = p_booking_id
    and driver_id = v_driver_id
    and status in ('accepted', 'completed')
  for update;
  if not found then raise exception 'NOT_IN_CONVOY'; end if;

  if v_current = p_target_state then
    v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);
    return jsonb_build_object(
      'success', true, 'no_op', true,
      'journey_state', v_current, 'current_stop_index', v_stop_index,
      'overall_completed', coalesce((v_finalization->>'overall_completed')::boolean, false),
      'awaiting_final_payment', coalesce((v_finalization->>'awaiting_final_payment')::boolean, false)
    );
  end if;

  if v_current = 'completed' then
    v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);
    return jsonb_build_object(
      'success', true, 'no_op', true,
      'journey_state', v_current, 'current_stop_index', v_stop_index,
      'assignment_completed', true,
      'overall_completed', coalesce((v_finalization->>'overall_completed')::boolean, false),
      'awaiting_final_payment', coalesce((v_finalization->>'awaiting_final_payment')::boolean, false)
    );
  end if;

  v_new_stop_index := v_stop_index;
  if v_current = 'assigned' and p_target_state = 'en_route_pickup' then
    v_is_gated := false;
  elsif v_current = 'en_route_pickup' and p_target_state = 'at_pickup' then
    v_is_gated := false;
  elsif v_current = 'at_pickup' and p_target_state = 'boarded' then
    v_is_gated := false;
  elsif v_current = 'boarded' and p_target_state in ('en_route_stop', 'en_route_dropoff') then
    v_is_gated := true;
    if p_target_state = 'en_route_stop' then v_new_stop_index := 0; end if;
  elsif v_current = 'en_route_stop' and p_target_state = 'at_stop' then
    v_is_gated := false;
  elsif v_current = 'stop_done' and p_target_state in ('en_route_stop', 'en_route_dropoff') then
    v_is_gated := true;
    if p_target_state = 'en_route_stop' then v_new_stop_index := v_stop_index + 1; end if;
  elsif v_current = 'en_route_dropoff' and p_target_state = 'at_dropoff' then
    v_is_gated := false;
  elsif v_current = 'at_dropoff' and p_target_state = 'completed' then
    v_is_gated := true;
  else
    if public.journey_state_order(v_current)
       > public.journey_state_order(p_target_state) then
      v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);
      return jsonb_build_object(
        'success', true, 'no_op', true, 'already_progressed', true,
        'journey_state', v_current, 'current_stop_index', v_stop_index,
        'overall_completed', coalesce((v_finalization->>'overall_completed')::boolean, false),
        'awaiting_final_payment', coalesce((v_finalization->>'awaiting_final_payment')::boolean, false)
      );
    end if;
    raise exception 'INVALID_TRANSITION: % -> %', v_current, p_target_state;
  end if;

  if v_current = 'assigned' and p_target_state = 'en_route_pickup' then
    select count(*) into v_accepted_count
    from public.booking_drivers
    where booking_id = p_booking_id and status in ('accepted', 'completed');
    if v_accepted_count < greatest(coalesce(v_booking.required_drivers, 1), 1) then
      raise exception 'DRIVER_SLOTS_NOT_FILLED';
    end if;
    if not v_debug_bypass
       and now() < lower(public.package_booking_schedule_window(v_booking)) then
      raise exception 'BOOKING_START_TOO_EARLY';
    end if;
    if not v_debug_bypass
       and not public.is_booking_downpayment_confirmed(p_booking_id) then
      raise exception 'DOWNPAYMENT_NOT_CONFIRMED';
    end if;
  end if;

  if v_current = 'at_dropoff' and p_target_state = 'completed' then
    select count(*), count(*) filter (
      where lower(coalesce(spot_status, 'pending')) = 'completed'
    ) into v_total_items, v_completed_items
    from public.booking_itinerary_items
    where booking_id = p_booking_id;
    if v_total_items = 0 or v_completed_items < v_total_items then
      raise exception 'INCOMPLETE_ITINERARY';
    end if;
  end if;

  -- Payment is a server-enforced precondition of the final navigation leg.
  -- Test Mode intentionally does not bypass transaction/payment sequencing.
  if v_current = 'stop_done' and p_target_state = 'en_route_dropoff' then
    select count(*), count(*) filter (
      where lower(coalesce(spot_status, 'pending')) = 'completed'
    ) into v_total_items, v_completed_items
    from public.booking_itinerary_items
    where booking_id = p_booking_id;
    if v_total_items = 0 or v_completed_items < v_total_items then
      raise exception 'INCOMPLETE_ITINERARY';
    end if;
    if not public.is_booking_remaining_payment_satisfied(p_booking_id) then
      raise exception 'REMAINING_BALANCE_NOT_CONFIRMED';
    end if;
  end if;

  if v_is_gated then
    if v_current = 'boarded' then
      v_stage_progress := public.compute_convoy_stage_progress(
        p_booking_id, 'boarded', null
      );
    elsif v_current = 'stop_done' then
      v_stage_progress := public.compute_convoy_stage_progress(
        p_booking_id, 'stop_done', v_stop_index
      );
    elsif v_current = 'at_dropoff' then
      v_stage_progress := public.compute_convoy_stage_progress(
        p_booking_id, 'at_dropoff', null
      );
    end if;
    v_all_cleared := coalesce(
      (v_stage_progress->>'all_satisfied')::boolean, false
    );
    if not coalesce(v_all_cleared, false) then raise exception 'BARRIER_NOT_MET'; end if;
  end if;

  update public.booking_drivers
  set journey_state = p_target_state,
      current_stop_index = v_new_stop_index,
      state_updated_at = now(),
      status = case when p_target_state = 'completed' then 'completed' else status end,
      completed_at = case when p_target_state = 'completed'
        then coalesce(completed_at, now()) else completed_at end
  where booking_id = p_booking_id and driver_id = v_driver_id;

  select (array_agg(journey_state
    order by public.journey_state_order(journey_state), current_stop_index))[1]
  into v_slowest_state
  from public.booking_drivers
  where booking_id = p_booking_id and status in ('accepted', 'completed');

  v_legacy_status := case v_slowest_state
    when 'assigned' then 'driver_accepted'
    when 'en_route_pickup' then 'driver_en_route'
    when 'at_pickup' then 'driver_arrived'
    when 'boarded' then 'picked_up'
    when 'en_route_stop' then 'en_route_to_spot'
    when 'at_stop' then 'at_spot'
    when 'stop_done' then 'on_tour'
    when 'en_route_dropoff' then 'en_route_to_dropoff'
    when 'at_dropoff' then 'ready_to_complete'
    when 'completed' then 'ready_to_complete'
    else 'driver_accepted'
  end;

  select id into v_activity_id
  from public.package_activities where booking_id = p_booking_id limit 1;

  perform set_config('touristrike.validated_transition', 'true', true);
  if v_activity_id is not null then
    update public.package_activities
    set tour_status = v_legacy_status,
        status = case when v_legacy_status = 'driver_accepted'
          then 'accepted' else 'ongoing' end,
        current_spot_index = greatest(v_new_stop_index, current_spot_index),
        dropped_off_at = case when p_target_state = 'completed'
          then coalesce(dropped_off_at, now()) else dropped_off_at end,
        updated_at = now()
    where id = v_activity_id;

    insert into public.trip_status_logs(
      activity_id, booking_id, driver_id, status, previous_state, new_state,
      spot_index, logged_at, notes
    ) values (
      v_activity_id, p_booking_id, v_driver_id,
      case when p_target_state = 'completed' then 'assignment_completed'
           else v_legacy_status end,
      v_current, p_target_state, v_new_stop_index, now(),
      case when v_debug_bypass
        then 'Developer test booking journey transition; operational validations bypassed'
        else 'Server-validated journey transition' end
    );
  end if;

  update public.package_bookings
  set booking_status = case
        when v_legacy_status in ('driver_accepted', 'driver_en_route', 'driver_arrived')
          then 'driver_on_the_way'
        else 'on_tour'
      end,
      current_spot_index = greatest(v_new_stop_index, current_spot_index),
      updated_at = now()
  where id = p_booking_id;

  v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);

  return jsonb_build_object(
    'success', true, 'no_op', false,
    'journey_state', p_target_state,
    'current_stop_index', v_new_stop_index,
    'legacy_tour_status', v_legacy_status,
    'assignment_completed', p_target_state = 'completed',
    'convoy_progress', case
      when p_target_state = 'boarded' then public.compute_convoy_stage_progress(
        p_booking_id, 'boarded', null
      )
      when p_target_state = 'stop_done' then public.compute_convoy_stage_progress(
        p_booking_id, 'stop_done', v_new_stop_index
      )
      when p_target_state in ('at_dropoff', 'completed') then
        public.compute_convoy_stage_progress(p_booking_id, 'at_dropoff', null)
      else null
    end,
    'overall_completed', coalesce((v_finalization->>'overall_completed')::boolean, false),
    'awaiting_final_payment', coalesce((v_finalization->>'awaiting_final_payment')::boolean, false),
    'debug_bypass', v_debug_bypass
  );
end;
$$;

grant execute on function public.advance_driver_journey_state(uuid, text)
  to authenticated;

create or replace function public.debug_advance_driver_journey_state(
  p_booking_id uuid,
  p_target_state text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.debug_test_driver_assignment(p_booking_id);
  perform set_config('touristrike.debug_progression_bypass', 'true', true);
  return public.advance_driver_journey_state(p_booking_id, p_target_state);
end;
$$;

revoke all on function public.debug_advance_driver_journey_state(uuid, text)
  from public, anon;
grant execute on function public.debug_advance_driver_journey_state(uuid, text)
  to authenticated;

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
  v_booking_id uuid;
begin
  if v_driver_id is null then raise exception 'UNAUTHENTICATED'; end if;
  select booking_id into v_booking_id
  from public.package_activities
  where id = p_activity_id;
  if not found then raise exception 'ACTIVITY_NOT_FOUND'; end if;
  if not exists (
    select 1 from public.booking_drivers
    where booking_id = v_booking_id and driver_id = v_driver_id
      and status in ('accepted', 'completed')
  ) then raise exception 'NOT_ASSIGNED_DRIVER'; end if;
  return public.finalize_package_booking_if_eligible(v_booking_id);
end;
$$;

grant execute on function public.complete_package_tour(uuid, text)
  to authenticated;

create or replace function public.debug_complete_package_tour(
  p_activity_id uuid,
  p_remaining_payment_method text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_booking_id uuid;
begin
  select booking_id into v_booking_id
  from public.package_activities where id = p_activity_id;
  if not found then raise exception 'ACTIVITY_NOT_FOUND'; end if;
  perform public.debug_test_driver_assignment(v_booking_id);
  return public.complete_package_tour(p_activity_id, p_remaining_payment_method);
end;
$$;

revoke all on function public.debug_complete_package_tour(uuid, text)
  from public, anon;
grant execute on function public.debug_complete_package_tour(uuid, text)
  to authenticated;

create or replace function public.debug_force_complete_test_trip(
  p_booking_id uuid,
  p_force_all_assignments boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_assignment_id uuid;
  v_total_items integer;
  v_completed_items integer;
  v_invalid_assignments integer;
  v_result jsonb;
begin
  v_assignment_id := public.debug_test_driver_assignment(p_booking_id);

  if p_force_all_assignments then
    raise exception 'TEST_FORCE_ALL_ASSIGNMENTS_NOT_ALLOWED';
  end if;

  select count(*), count(*) filter (
    where lower(coalesce(spot_status, 'pending')) = 'completed'
  ) into v_total_items, v_completed_items
  from public.booking_itinerary_items
  where booking_id = p_booking_id;
  if v_total_items = 0 or v_completed_items < v_total_items then
    raise exception 'INCOMPLETE_ITINERARY';
  end if;

  select count(*) into v_invalid_assignments
  from public.booking_drivers
  where booking_id = p_booking_id
    and status in ('accepted', 'completed')
    and journey_state not in ('at_dropoff', 'completed');
  if v_invalid_assignments > 0 then raise exception 'BARRIER_NOT_MET'; end if;

  if not exists (
    select 1 from public.booking_drivers
    where id = v_assignment_id and journey_state in ('at_dropoff', 'completed')
  ) then raise exception 'ASSIGNMENT_NOT_AT_DROPOFF'; end if;

  if not public.is_booking_remaining_payment_satisfied(p_booking_id) then
    raise exception 'REMAINING_BALANCE_NOT_CONFIRMED';
  end if;

  update public.booking_drivers
  set journey_state = 'completed', status = 'completed',
      current_stop_index = v_total_items, state_updated_at = now(),
      completed_at = coalesce(completed_at, now())
  where id = v_assignment_id;

  v_result := public.finalize_package_booking_if_eligible(p_booking_id);
  return v_result || jsonb_build_object(
    'debug_bypass', true,
    'forced_all_assignments', false,
    'payments_modified', false
  );
end;
$$;

revoke all on function public.debug_force_complete_test_trip(uuid, boolean)
  from public, anon;
grant execute on function public.debug_force_complete_test_trip(uuid, boolean)
  to authenticated;

create or replace function public.debug_mark_remaining_balance_paid(
  p_booking_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_booking public.package_bookings;
  v_payment public.payment_records;
  v_driver_count integer;
  v_result jsonb;
begin
  if v_user_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if not public.is_developer_test_booking(p_booking_id) then
    raise exception 'TEST_BOOKING_NOT_REGISTERED';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if v_booking.tourist_id <> v_user_id and not exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = p_booking_id and bd.driver_id = v_user_id
      and bd.status in ('accepted', 'completed')
  ) then raise exception 'NOT_TEST_BOOKING_PARTICIPANT'; end if;

  if coalesce(v_booking.remaining_balance, 0) <= 0 then
    return jsonb_build_object(
      'success', true, 'already_paid', true,
      'booking_id', p_booking_id, 'payment_required', false
    );
  end if;

  if not public.is_booking_itinerary_complete(p_booking_id) then
    raise exception 'REMAINING_PAYMENT_NOT_DUE';
  end if;

  perform public.ensure_booking_payment_requirements(p_booking_id);

  select * into v_payment
  from public.payment_records
  where booking_id = p_booking_id
    and payment_stage = 'remaining_balance'
    and status = 'confirmed'
    and amount >= v_booking.remaining_balance
  order by created_at desc limit 1;
  if found then
    update public.booking_payment_requirements
    set status = 'satisfied', satisfied_at = coalesce(satisfied_at, now()),
        satisfied_by_payment_record_id = coalesce(
          satisfied_by_payment_record_id, v_payment.id)
    where booking_id = p_booking_id and payment_stage = 'remaining_balance';
    v_result := public.finalize_package_booking_if_eligible(p_booking_id);
    return v_result || jsonb_build_object(
      'debug_bypass', true, 'already_paid', true,
      'payment_record_id', v_payment.id
    );
  end if;

  if exists (
    select 1 from public.payment_records
    where booking_id = p_booking_id
      and payment_stage = 'remaining_balance'
      and status <> 'cancelled'
  ) then raise exception 'PAYMENT_STAGE_ALREADY_STARTED'; end if;

  select count(*) into v_driver_count
  from public.required_booking_driver_roster(p_booking_id);
  if not public.is_booking_driver_roster_full(p_booking_id) then
    raise exception 'DRIVER_SLOTS_NOT_FILLED';
  end if;

  perform set_config('touristrike.trusted_group_cash', 'true', true);
  insert into public.payment_records(
    booking_id, payer_id, payee_id, amount, payment_method, payment_stage,
    status, provider, currency, provider_status, idempotency_key,
    service_description, notes, paid_at
  ) values (
    p_booking_id, v_booking.tourist_id, null,
    round(v_booking.remaining_balance, 2), 'cash', 'remaining_balance',
    'pending_confirmation', 'manual', 'PHP', 'awaiting_cash_receipt',
    'debug-test-remaining-' || p_booking_id::text,
    'TEST MODE remaining balance settlement',
    'Developer test payment simulation; no real funds transferred', null
  ) returning * into v_payment;

  insert into public.payment_allocations(
    payment_record_id, booking_id, booking_driver_id, driver_id,
    gross_amount, platform_fee, driver_amount, split_basis_points,
    currency, status
  )
  with ranked as (
    select bd.*,
      (row_number() over (order by bd.accepted_at, bd.id))::integer as position
    from public.required_booking_driver_roster(p_booking_id) bd
  )
  select v_payment.id, p_booking_id, bd.id, bd.driver_id,
         split.amount_centavos / 100.0, 0, split.amount_centavos / 100.0,
         split.basis_points, 'PHP', 'cash_confirmed'
  from ranked bd
  join public.compute_equal_split_centavos(
    (round(v_booking.remaining_balance, 2) * 100)::bigint, v_driver_count
  ) split on split.recipient_position = bd.position;

  if (select count(*) from public.payment_allocations
      where payment_record_id = v_payment.id) <> v_driver_count
     or (select coalesce(sum(gross_amount), 0)
         from public.payment_allocations
         where payment_record_id = v_payment.id)
        <> round(v_booking.remaining_balance, 2) then
    raise exception 'TEST_PAYMENT_ALLOCATION_TOTAL_MISMATCH';
  end if;

  update public.payment_records
  set status = 'confirmed', provider_status = 'cash_received', paid_at = now()
  where id = v_payment.id
  returning * into v_payment;

  update public.booking_payment_requirements
  set status = 'satisfied', satisfied_at = coalesce(satisfied_at, now()),
      satisfied_by_payment_record_id = v_payment.id
  where booking_id = p_booking_id
    and payment_stage = 'remaining_balance'
    and amount <= v_payment.amount;

  v_result := public.finalize_package_booking_if_eligible(p_booking_id);
  return v_result || jsonb_build_object(
    'debug_bypass', true, 'already_paid', false,
    'payment_record_id', v_payment.id,
    'payments_modified', true
  );
end;
$$;

revoke all on function public.debug_mark_remaining_balance_paid(uuid)
  from public, anon;
grant execute on function public.debug_mark_remaining_balance_paid(uuid)
  to authenticated;

create or replace function public.finalize_booking_after_payment_requirement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('satisfied', 'waived') then
    if new.payment_stage = 'remaining_balance' then
      perform set_config('touristrike.validated_transition', 'true', true);

      update public.package_bookings
      set remaining_balance = 0,
          booking_status = case
            when booking_status = 'awaiting_remaining_payment' then 'on_tour'
            else booking_status
          end,
          updated_at = now()
      where id = new.booking_id;

      update public.package_activities
      set tour_status = case
            when tour_status = 'awaiting_remaining_payment' then 'on_tour'
            else tour_status
          end,
          updated_at = now()
      where booking_id = new.booking_id;
    end if;

    if tg_op = 'INSERT' then
      perform public.finalize_package_booking_if_eligible(new.booking_id);
    elsif new.status is distinct from old.status
          or new.satisfied_by_payment_record_id
             is distinct from old.satisfied_by_payment_record_id then
      perform public.finalize_package_booking_if_eligible(new.booking_id);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_finalize_booking_after_payment_requirement
  on public.booking_payment_requirements;
create trigger trg_finalize_booking_after_payment_requirement
after insert or update on public.booking_payment_requirements
for each row execute function public.finalize_booking_after_payment_requirement();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'booking_payment_requirements'
  ) then
    alter publication supabase_realtime
      add table public.booking_payment_requirements;
  end if;
end;
$$;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'booking_drivers', 'booking_itinerary_items',
    'package_activities', 'package_bookings'
  ] loop
    if exists (
      select 1 from information_schema.tables
      where table_schema = 'public' and table_name = v_table
    ) and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I', v_table
      );
    end if;
  end loop;
end;
$$;

notify pgrst, 'reload schema';

commit;
