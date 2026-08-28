-- TourisTrike P0 booking integrity
--
-- This migration keeps the existing package-tour model and RPC signatures.
-- It adds authoritative schedule windows, serializes acceptance per driver,
-- makes payment stages/confirmation idempotent, and closes the convoy
-- completion bypass left in complete_package_tour().

-- ---------------------------------------------------------------------------
-- 1. Authoritative schedule window
-- ---------------------------------------------------------------------------

alter table public.package_bookings
  add column if not exists scheduled_start_at timestamptz,
  add column if not exists estimated_end_at timestamptz;

alter table public.package_bookings
  drop constraint if exists package_bookings_schedule_window_check;
alter table public.package_bookings
  add constraint package_bookings_schedule_window_check
  check (
    (scheduled_start_at is null and estimated_end_at is null)
    or
    (scheduled_start_at is not null and estimated_end_at is not null
      and estimated_end_at > scheduled_start_at)
  );

create index if not exists package_bookings_schedule_idx
  on public.package_bookings (scheduled_start_at, estimated_end_at)
  where scheduled_start_at is not null;

create index if not exists booking_drivers_driver_active_idx
  on public.booking_drivers (driver_id, booking_id)
  where status = 'accepted';

-- Old bookings only have travel_date. Treat those as occupying that complete
-- calendar day in Asia/Manila. This is deliberately conservative: it fixes the
-- old "any future booking" bug without inventing pickup times or durations.
create or replace function public.package_booking_schedule_window(
  p_booking public.package_bookings
)
returns tstzrange
language sql
stable
set search_path = public
as $$
  select case
    when p_booking.scheduled_start_at is not null then
      tstzrange(p_booking.scheduled_start_at, p_booking.estimated_end_at, '[)')
    else
      tstzrange(
        p_booking.travel_date::timestamp at time zone 'Asia/Manila',
        (p_booking.travel_date + 1)::timestamp at time zone 'Asia/Manila',
        '[)'
      )
  end;
$$;

-- package_bookings is still created directly by Flutter. Validate the payment
-- contract on INSERT and prevent a tourist from rewriting assignment/payment
-- invariants after creation through a direct PostgREST UPDATE.
create or replace function public.guard_package_booking_client_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_profile_role() <> 'tourist' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if auth.uid() is null or new.tourist_id <> auth.uid() then
      raise exception 'NOT_BOOKING_TOURIST';
    end if;
    if lower(coalesce(new.status, 'pending')) <> 'pending'
       or lower(coalesce(new.booking_status, 'pending')) <> 'pending'
       or new.assigned_driver_id is not null
       or coalesce(new.accepted_drivers_count, 0) <> 0
       or greatest(coalesce(new.required_drivers, 1), 1) <> new.required_drivers then
      raise exception 'INVALID_INITIAL_BOOKING_STATE';
    end if;
    if lower(coalesce(new.booking_type, 'advanced')) = 'advanced' then
      if lower(coalesce(new.payment_method, '')) <> 'gcash' then
        raise exception 'ADVANCED_BOOKING_REQUIRES_GCASH';
      end if;
      if new.downpayment_amount <> round(new.total_amount * 0.50, 2)
         or new.remaining_balance <> new.total_amount - new.downpayment_amount then
        raise exception 'INVALID_ADVANCED_PAYMENT_SPLIT';
      end if;
    end if;
    return new;
  end if;

  -- The cancellation RPC legitimately changes these fields together. Its
  -- existing guards/refund workflow remains the sanctioned tourist transition.
  if lower(coalesce(new.booking_status, new.status, '')) = 'cancelled' then
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

drop trigger if exists trg_guard_package_booking_client_write
  on public.package_bookings;
create trigger trg_guard_package_booking_client_write
before insert or update on public.package_bookings
for each row execute function public.guard_package_booking_client_write();

-- ---------------------------------------------------------------------------
-- 2. Explicit, idempotent payment requirements
-- ---------------------------------------------------------------------------

create table if not exists public.booking_payment_requirements (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.package_bookings(id) on delete cascade,
  payment_stage text not null
    check (payment_stage in ('down_payment', 'remaining_balance')),
  amount numeric not null check (amount > 0),
  status text not null default 'required'
    check (status in ('required', 'satisfied', 'waived')),
  required_at timestamptz not null default now(),
  satisfied_at timestamptz,
  satisfied_by_payment_record_id uuid references public.payment_records(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (booking_id, payment_stage)
);

create index if not exists booking_payment_requirements_booking_idx
  on public.booking_payment_requirements (booking_id, payment_stage);

drop trigger if exists set_booking_payment_requirements_updated_at
  on public.booking_payment_requirements;
create trigger set_booking_payment_requirements_updated_at
before update on public.booking_payment_requirements
for each row execute function public.set_updated_at();

alter table public.booking_payment_requirements enable row level security;

drop policy if exists booking_payment_requirements_select_participants
  on public.booking_payment_requirements;
create policy booking_payment_requirements_select_participants
on public.booking_payment_requirements
for select
using (
  exists (
    select 1
    from public.package_bookings pb
    where pb.id = booking_payment_requirements.booking_id
      and (
        pb.tourist_id = auth.uid()
        or exists (
          select 1 from public.booking_drivers bd
          where bd.booking_id = pb.id
            and bd.driver_id = auth.uid()
            and bd.status in ('accepted', 'completed')
        )
        or public.current_profile_role() in ('admin', 'subtenant')
      )
  )
);

-- No client INSERT/UPDATE/DELETE policy. Requirements are maintained only by
-- SECURITY DEFINER functions after the booking roster is fully assigned.

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
  v_accepted_count integer;
  v_written integer := 0;
begin
  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'BOOKING_NOT_FOUND';
  end if;

  select count(*) into v_accepted_count
  from public.booking_drivers
  where booking_id = p_booking_id and status = 'accepted';

  if v_accepted_count < greatest(coalesce(v_booking.required_drivers, 1), 1) then
    return 0;
  end if;

  if lower(coalesce(v_booking.booking_type, 'same_day')) <> 'advanced' then
    return 0;
  end if;

  if coalesce(v_booking.downpayment_amount, 0) > 0 then
    insert into public.booking_payment_requirements
      (booking_id, payment_stage, amount)
    values
      (p_booking_id, 'down_payment', v_booking.downpayment_amount)
    on conflict (booking_id, payment_stage) do update
      set amount = excluded.amount,
          status = case
            when booking_payment_requirements.status = 'satisfied'
              then booking_payment_requirements.status
            else 'required'
          end;
    v_written := v_written + 1;
  end if;

  if coalesce(v_booking.remaining_balance, 0) > 0 then
    insert into public.booking_payment_requirements
      (booking_id, payment_stage, amount)
    values
      (p_booking_id, 'remaining_balance', v_booking.remaining_balance)
    on conflict (booking_id, payment_stage) do update
      set amount = excluded.amount,
          status = case
            when booking_payment_requirements.status = 'satisfied'
              then booking_payment_requirements.status
            else 'required'
          end;
    v_written := v_written + 1;
  end if;

  return v_written;
end;
$$;

revoke all on function public.ensure_booking_payment_requirements(uuid) from public;

-- Reconcile old duplicate active submissions before enforcing the invariant.
-- Confirmed evidence wins; otherwise the earliest submission is canonical.
with ranked as (
  select id,
         row_number() over (
           partition by booking_id, payment_stage
           order by case when status = 'confirmed' then 0 else 1 end,
                    payer_submitted_at asc,
                    created_at asc,
                    id
         ) as position
  from public.payment_records
  where booking_id is not null and status <> 'cancelled'
)
update public.payment_records pr
set status = 'cancelled',
    notes = concat_ws(E'\n', nullif(pr.notes, ''),
      'Automatically reconciled as a duplicate payment-stage submission.')
from ranked r
where r.id = pr.id and r.position > 1;

create unique index if not exists payment_records_one_active_booking_stage_idx
  on public.payment_records (booking_id, payment_stage)
  where booking_id is not null and status <> 'cancelled';

-- Validate package payment submissions even when a caller bypasses Flutter and
-- inserts directly through PostgREST.
create or replace function public.validate_booking_payment_submission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_required_amount numeric;
begin
  if new.booking_id is null then
    return new;
  end if;

  select * into v_booking
  from public.package_bookings
  where id = new.booking_id
  for key share;

  if not found then
    raise exception 'BOOKING_NOT_FOUND';
  end if;

  if auth.uid() is null or new.payer_id <> auth.uid()
     or new.payer_id <> v_booking.tourist_id then
    raise exception 'NOT_BOOKING_TOURIST';
  end if;

  if lower(coalesce(v_booking.booking_status, v_booking.status, 'pending'))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_PAYABLE';
  end if;

  if not exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = new.booking_id
      and bd.driver_id = new.payee_id
      and bd.status = 'accepted'
  ) then
    raise exception 'PAYEE_NOT_ASSIGNED_DRIVER';
  end if;

  if lower(coalesce(v_booking.booking_type, 'same_day')) = 'advanced' then
    if new.payment_method <> 'gcash' then
      raise exception 'ADVANCED_BOOKING_REQUIRES_GCASH';
    end if;

    if new.payment_stage = 'down_payment' then
      v_required_amount := v_booking.downpayment_amount;
    elsif new.payment_stage = 'remaining_balance' then
      v_required_amount := v_booking.remaining_balance;
    else
      raise exception 'INVALID_ADVANCED_PAYMENT_STAGE';
    end if;

    if coalesce(v_required_amount, 0) <= 0 or new.amount <> v_required_amount then
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
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_booking_payment_submission
  on public.payment_records;
create trigger trg_validate_booking_payment_submission
before insert on public.payment_records
for each row execute function public.validate_booking_payment_submission();

create or replace function public.confirm_payment_record(
  p_payment_record_id uuid
)
returns public.payment_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record public.payment_records;
  v_role text;
begin
  select * into v_record
  from public.payment_records
  where id = p_payment_record_id
  for update;

  if not found then
    raise exception 'PAYMENT_RECORD_NOT_FOUND';
  end if;

  v_role := public.current_profile_role();
  if auth.uid() is null
     or (auth.uid() <> v_record.payee_id and v_role not in ('admin', 'subtenant')) then
    raise exception 'NOT_PAYMENT_PAYEE';
  end if;

  if v_record.status = 'confirmed' then
    return v_record;
  end if;

  if v_record.status <> 'pending_confirmation' then
    raise exception 'PAYMENT_NOT_CONFIRMABLE';
  end if;

  update public.payment_records
  set status = 'confirmed'
  where id = p_payment_record_id
  returning * into v_record;

  if v_record.booking_id is not null then
    update public.booking_payment_requirements
    set status = 'satisfied',
        satisfied_at = coalesce(satisfied_at, now()),
        satisfied_by_payment_record_id = coalesce(
          satisfied_by_payment_record_id,
          v_record.id
        )
    where booking_id = v_record.booking_id
      and payment_stage = v_record.payment_stage
      and amount <= v_record.amount
      and status = 'required';
  end if;

  return v_record;
end;
$$;

grant execute on function public.confirm_payment_record(uuid) to authenticated;

-- Confirmation now has a narrow RPC. Direct UPDATE is intentionally closed;
-- attachment/dispute/admin workflows already use SECURITY DEFINER RPCs.
drop policy if exists payment_records_update on public.payment_records;

-- ---------------------------------------------------------------------------
-- 3. Atomic driver acceptance with schedule conflict protection
-- ---------------------------------------------------------------------------

create or replace function public.accept_package_booking(
  p_booking_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_driver public.profiles;
  v_booking public.package_bookings;
  v_activity_id uuid;
  v_live_count integer;
  v_new_count integer;
  v_driver_status text;
  v_driver_approved_at timestamptz;
  v_application_status text;
begin
  if v_driver_id is null then raise exception 'UNAUTHENTICATED'; end if;

  select * into v_driver from public.profiles where id = v_driver_id;
  if not found then raise exception 'DRIVER_NOT_FOUND'; end if;
  if v_driver.role <> 'driver' then raise exception 'DRIVER_ROLE_REQUIRED'; end if;
  if not (coalesce(v_driver.is_online, false) or coalesce(v_driver.is_available, false)) then
    raise exception 'DRIVER_NOT_AVAILABLE';
  end if;

  select lower(coalesce(status, '')), approved_at
    into v_driver_status, v_driver_approved_at
  from public.driver_details where driver_id = v_driver_id;

  select lower(coalesce(status, '')) into v_application_status
  from public.driver_applications
  where driver_id = v_driver_id
  order by submitted_at desc limit 1;

  if coalesce(v_driver_status, '') in ('disabled', 'inactive', 'rejected', 'suspended')
     or (
       coalesce(v_driver_status, '') not in ('active', 'approved', 'verified')
       and not (coalesce(v_driver_status, '') = '' and v_driver_approved_at is not null)
       and coalesce(v_application_status, '') not in ('active', 'approved', 'verified')
     ) then
    raise exception 'DRIVER_NOT_APPROVED';
  end if;

  -- A transaction-scoped lock keyed by driver serializes acceptance across
  -- different bookings. Booking-row locks alone cannot prevent that race.
  perform pg_advisory_xact_lock(hashtextextended(v_driver_id::text, 0));

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;

  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking.booking_status not in ('pending', 'waiting_for_drivers') then
    raise exception 'BOOKING_NOT_AVAILABLE';
  end if;

  if v_booking.municipality is not null and trim(v_booking.municipality) <> ''
     and trim(lower(coalesce(v_driver.city, ''))) <>
         trim(lower(v_booking.municipality)) then
    raise exception 'MUNICIPALITY_MISMATCH: Booking is for % only.',
      v_booking.municipality;
  end if;

  if exists (
    select 1
    from public.booking_drivers bd
    join public.package_bookings other_booking on other_booking.id = bd.booking_id
    where bd.driver_id = v_driver_id
      and bd.booking_id <> p_booking_id
      and bd.status = 'accepted'
      and lower(coalesce(other_booking.booking_status, other_booking.status, ''))
            not in ('cancelled', 'completed', 'rejected', 'done')
      and public.package_booking_schedule_window(other_booking)
            && public.package_booking_schedule_window(v_booking)
  ) then
    raise exception 'DRIVER_SCHEDULE_CONFLICT';
  end if;

  select count(*) into v_live_count
  from public.booking_drivers
  where booking_id = p_booking_id and status = 'accepted';

  if v_live_count >= greatest(coalesce(v_booking.required_drivers, 1), 1) then
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
  values (p_booking_id, v_driver_id, 'accepted', now());

  v_new_count := v_live_count + 1;

  if v_new_count >= greatest(coalesce(v_booking.required_drivers, 1), 1) then
    if v_activity_id is not null then
      update public.package_activities
      set driver_id = v_driver_id,
          status = 'accepted',
          tour_status = 'driver_accepted',
          accepted_at = now(),
          updated_at = now()
      where id = v_activity_id;
    end if;

    update public.package_bookings
    set assigned_driver_id = v_driver_id,
        accepted_drivers_count = v_new_count,
        status = 'confirmed',
        booking_status = 'accepted',
        accepted_at = now(),
        updated_at = now()
    where id = p_booking_id;

    update public.booking_drivers bd
    set assigned_passengers = split.passenger_count
    from public.compute_passenger_split(
      p_booking_id,
      case when coalesce(v_booking.total_passengers, 0) > 0
        then v_booking.total_passengers
        else v_booking.adults + coalesce(v_booking.children, 0)
      end
    ) as split
    where bd.booking_id = p_booking_id and bd.driver_id = split.driver_id;

    perform public.ensure_booking_payment_requirements(p_booking_id);
    raise log '[TourisTrike booking] driver accepted booking=%, accepted=%/%, fully_assigned=true, payment_requirements=active',
      p_booking_id, v_new_count,
      greatest(coalesce(v_booking.required_drivers, 1), 1);
  else
    update public.package_bookings
    set accepted_drivers_count = v_new_count,
        booking_status = 'waiting_for_drivers',
        updated_at = now()
    where id = p_booking_id;
    raise log '[TourisTrike booking] driver accepted booking=%, accepted=%/%, fully_assigned=false',
      p_booking_id, v_new_count,
      greatest(coalesce(v_booking.required_drivers, 1), 1);
  end if;

  return jsonb_build_object(
    'success', true,
    'booking_id', p_booking_id,
    'accepted_count', v_new_count,
    'required_count', greatest(coalesce(v_booking.required_drivers, 1), 1),
    'all_filled', v_new_count >= greatest(coalesce(v_booking.required_drivers, 1), 1)
  );
end;
$$;

grant execute on function public.accept_package_booking(uuid) to authenticated;

-- Direct roster writes bypass capacity, approval and schedule checks. All
-- authenticated mutations must go through accept_package_booking,
-- cancel_driver_slot, or an administrative SECURITY DEFINER workflow.
drop policy if exists "booking_drivers_driver_insert" on public.booking_drivers;
drop policy if exists "booking_drivers_driver_update" on public.booking_drivers;

-- ---------------------------------------------------------------------------
-- 4. Journey gates, convoy barrier, and authoritative audit logging
-- ---------------------------------------------------------------------------

alter table public.trip_status_logs
  add column if not exists driver_id uuid references public.profiles(id),
  add column if not exists previous_state text,
  add column if not exists new_state text;

create index if not exists trip_status_logs_booking_logged_idx
  on public.trip_status_logs (booking_id, logged_at desc);

create or replace function public.stamp_trip_status_log_driver()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and public.current_profile_role() = 'driver' then
    new.driver_id := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_stamp_trip_status_log_driver on public.trip_status_logs;
create trigger trg_stamp_trip_status_log_driver
before insert on public.trip_status_logs
for each row execute function public.stamp_trip_status_log_driver();

drop policy if exists "trip_logs_read_all" on public.trip_status_logs;
drop policy if exists trip_logs_select_participants on public.trip_status_logs;
create policy trip_logs_select_participants
on public.trip_status_logs
for select
using (
  exists (
    select 1 from public.package_bookings pb
    where pb.id = trip_status_logs.booking_id
      and (
        pb.tourist_id = auth.uid()
        or exists (
          select 1 from public.booking_drivers bd
          where bd.booking_id = pb.id and bd.driver_id = auth.uid()
        )
        or public.current_profile_role() in ('admin', 'subtenant')
      )
  )
);

drop policy if exists "trip_logs_insert_any" on public.trip_status_logs;
drop policy if exists trip_logs_insert_assigned_driver on public.trip_status_logs;
create policy trip_logs_insert_assigned_driver
on public.trip_status_logs
for insert
with check (
  driver_id = auth.uid()
  and exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = trip_status_logs.booking_id
      and bd.driver_id = auth.uid()
      and bd.status in ('accepted', 'completed')
  )
);

-- The legacy activity UPDATE policy is still needed for the designated
-- driver's location mirror. Prevent that narrow write path from being abused
-- to start or complete a tour outside the validated journey RPC.
create or replace function public.guard_direct_package_activity_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_profile_role() = 'driver'
     and coalesce(current_setting('touristrike.validated_transition', true), '') <> 'true'
     and (
       (old.tour_status in ('waiting_driver', 'driver_accepted')
         and new.tour_status not in ('waiting_driver', 'driver_accepted'))
       or (new.tour_status in ('completed', 'dropped_off')
         and new.tour_status is distinct from old.tour_status)
       or (new.status = 'completed' and new.status is distinct from old.status)
     ) then
    raise exception 'JOURNEY_RPC_REQUIRED';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_direct_package_activity_transition
  on public.package_activities;
create trigger trg_guard_direct_package_activity_transition
before update of status, tour_status on public.package_activities
for each row execute function public.guard_direct_package_activity_transition();

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

  select journey_state, current_stop_index into v_current, v_stop_index
  from public.booking_drivers
  where booking_id = p_booking_id
    and driver_id = v_driver_id
    and status = 'accepted'
  for update;
  if not found then raise exception 'NOT_IN_CONVOY'; end if;

  if v_current = p_target_state then
    return jsonb_build_object(
      'success', true, 'no_op', true,
      'journey_state', v_current, 'current_stop_index', v_stop_index
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
  elsif v_current = 'at_stop' and p_target_state = 'stop_done' then
    v_is_gated := false;
  elsif v_current = 'stop_done' and p_target_state in ('en_route_stop', 'en_route_dropoff') then
    v_is_gated := true;
    if p_target_state = 'en_route_stop' then v_new_stop_index := v_stop_index + 1; end if;
  elsif v_current = 'en_route_dropoff' and p_target_state = 'at_dropoff' then
    v_is_gated := false;
  elsif v_current = 'at_dropoff' and p_target_state = 'completed' then
    v_is_gated := true;
  else
    raise exception 'INVALID_TRANSITION: % -> %', v_current, p_target_state;
  end if;

  if v_current = 'assigned' and p_target_state = 'en_route_pickup' then
    select count(*) into v_accepted_count
    from public.booking_drivers
    where booking_id = p_booking_id and status = 'accepted';

    if v_accepted_count < greatest(coalesce(v_booking.required_drivers, 1), 1) then
      raise exception 'DRIVER_SLOTS_NOT_FILLED';
    end if;

    if now() < lower(public.package_booking_schedule_window(v_booking)) then
      raise exception 'BOOKING_START_TOO_EARLY';
    end if;

    if lower(coalesce(v_booking.booking_type, 'same_day')) = 'advanced'
       and coalesce(v_booking.downpayment_amount, 0) > 0
       and not exists (
         select 1 from public.payment_records pr
         where pr.booking_id = p_booking_id
           and pr.payment_stage = 'down_payment'
           and pr.status = 'confirmed'
           and pr.amount >= v_booking.downpayment_amount
       ) then
      raise exception 'DOWNPAYMENT_NOT_CONFIRMED';
    end if;
  end if;

  if v_current = 'at_dropoff' and p_target_state = 'completed' then
    select count(*), count(*) filter (where lower(coalesce(spot_status, 'pending')) = 'completed')
      into v_total_items, v_completed_items
    from public.booking_itinerary_items
    where booking_id = p_booking_id;

    if v_total_items = 0 or v_completed_items < v_total_items then
      raise exception 'INCOMPLETE_ITINERARY';
    end if;

    if lower(coalesce(v_booking.booking_type, 'same_day')) = 'advanced'
       and coalesce(v_booking.remaining_balance, 0) > 0
       and not exists (
         select 1 from public.payment_records pr
         where pr.booking_id = p_booking_id
           and pr.payment_stage = 'remaining_balance'
           and pr.status = 'confirmed'
           and pr.amount >= v_booking.remaining_balance
       ) then
      raise exception 'REMAINING_BALANCE_NOT_CONFIRMED';
    end if;
  end if;

  if v_is_gated then
    if v_current = 'boarded' then
      select bool_and(public.journey_state_order(journey_state) >=
                      public.journey_state_order('boarded'))
        into v_all_cleared
      from public.booking_drivers
      where booking_id = p_booking_id and status = 'accepted';
    elsif v_current = 'stop_done' then
      select bool_and(
        current_stop_index > v_stop_index
        or (current_stop_index = v_stop_index and journey_state = 'stop_done')
      ) into v_all_cleared
      from public.booking_drivers
      where booking_id = p_booking_id and status = 'accepted';
    elsif v_current = 'at_dropoff' then
      select bool_and(public.journey_state_order(journey_state) >=
                      public.journey_state_order('at_dropoff'))
        into v_all_cleared
      from public.booking_drivers
      where booking_id = p_booking_id and status = 'accepted';
    end if;

    if not coalesce(v_all_cleared, false) then
      raise exception 'BARRIER_NOT_MET';
    end if;
  end if;

  update public.booking_drivers
  set journey_state = p_target_state,
      current_stop_index = v_new_stop_index
  where booking_id = p_booking_id and driver_id = v_driver_id;

  select (array_agg(journey_state order by public.journey_state_order(journey_state)))[1]
    into v_slowest_state
  from public.booking_drivers
  where booking_id = p_booking_id and status = 'accepted';

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
    when 'completed' then 'completed'
    else 'driver_accepted'
  end;

  select id into v_activity_id
  from public.package_activities where booking_id = p_booking_id limit 1;

  if v_activity_id is not null then
    perform set_config('touristrike.validated_transition', 'true', true);
    update public.package_activities
    set tour_status = v_legacy_status,
        status = case
          when v_legacy_status = 'completed' then 'completed'
          when v_legacy_status = 'driver_accepted' then 'accepted'
          else 'ongoing'
        end,
        current_spot_index = greatest(v_new_stop_index, current_spot_index),
        updated_at = now()
    where id = v_activity_id;

    insert into public.trip_status_logs
      (activity_id, booking_id, driver_id, status, previous_state, new_state,
       spot_index, logged_at, notes)
    values
      (v_activity_id, p_booking_id, v_driver_id, v_legacy_status, v_current,
       p_target_state, v_new_stop_index, now(), 'Server-validated journey transition');
  end if;

  update public.package_bookings
  set booking_status = case v_legacy_status
        when 'driver_accepted' then 'driver_on_the_way'
        when 'driver_en_route' then 'driver_on_the_way'
        when 'driver_arrived' then 'driver_on_the_way'
        when 'picked_up' then 'on_tour'
        when 'en_route_to_spot' then 'on_tour'
        when 'at_spot' then 'on_tour'
        when 'en_route_to_dropoff' then 'on_tour'
        when 'ready_to_complete' then 'on_tour'
        when 'completed' then 'completed'
        else 'accepted'
      end,
      status = case when v_legacy_status = 'completed' then 'completed' else status end,
      completed_at = case
        when v_legacy_status = 'completed' then coalesce(completed_at, now())
        else completed_at
      end,
      updated_at = now()
  where id = p_booking_id;

  return jsonb_build_object(
    'success', true, 'no_op', false,
    'journey_state', p_target_state,
    'current_stop_index', v_new_stop_index,
    'legacy_tour_status', v_legacy_status,
    'overall_completed', v_legacy_status = 'completed'
  );
end;
$$;

grant execute on function public.advance_driver_journey_state(uuid, text) to authenticated;

-- Compatibility finalizer called by the current Flutter screen after the
-- per-driver journey RPC. It may finalize only after every active convoy member
-- has reached completed; otherwise it returns a harmless pending result.
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
  v_total_items integer;
  v_completed_items integer;
  v_active_slots integer;
  v_completed_slots integer;
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

  if not exists (
    select 1 from public.booking_drivers
    where booking_id = v_booking.id
      and driver_id = v_driver_id
      and status in ('accepted', 'completed')
  ) then
    raise exception 'NOT_ASSIGNED_DRIVER';
  end if;

  select count(*), count(*) filter (where journey_state = 'completed')
    into v_active_slots, v_completed_slots
  from public.booking_drivers
  where booking_id = v_booking.id
    and status in ('accepted', 'completed');

  if v_active_slots < greatest(coalesce(v_booking.required_drivers, 1), 1)
     or v_completed_slots < v_active_slots then
    return jsonb_build_object(
      'success', true,
      'overall_completed', false,
      'completed_slots', v_completed_slots,
      'required_slots', greatest(coalesce(v_booking.required_drivers, 1), 1)
    );
  end if;

  select count(*), count(*) filter (where lower(coalesce(spot_status, 'pending')) = 'completed')
    into v_total_items, v_completed_items
  from public.booking_itinerary_items
  where booking_id = v_booking.id;

  if v_total_items = 0 or v_completed_items < v_total_items then
    raise exception 'INCOMPLETE_ITINERARY';
  end if;

  if lower(coalesce(v_booking.booking_type, 'same_day')) = 'advanced'
     and coalesce(v_booking.remaining_balance, 0) > 0
     and not exists (
       select 1 from public.payment_records
       where booking_id = v_booking.id
         and payment_stage = 'remaining_balance'
         and status = 'confirmed'
         and amount >= v_booking.remaining_balance
     ) then
    raise exception 'REMAINING_BALANCE_NOT_CONFIRMED';
  end if;

  perform set_config('touristrike.validated_transition', 'true', true);
  update public.package_activities
  set status = 'completed', tour_status = 'completed',
      current_spot_index = v_total_items,
      dropped_off_at = coalesce(dropped_off_at, now()), updated_at = now()
  where id = p_activity_id;

  update public.package_bookings
  set status = 'completed', booking_status = 'completed',
      current_spot_index = v_total_items,
      completed_at = coalesce(completed_at, now()), updated_at = now()
  where id = v_booking.id;

  update public.booking_drivers
  set status = 'completed', completed_at = coalesce(completed_at, now())
  where booking_id = v_booking.id
    and status = 'accepted'
    and journey_state = 'completed';

  return jsonb_build_object(
    'success', true,
    'overall_completed', true,
    'completed_slots', v_completed_slots,
    'required_slots', greatest(coalesce(v_booking.required_drivers, 1), 1)
  );
end;
$$;

grant execute on function public.complete_package_tour(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Current-location privacy after a package tour ends
-- ---------------------------------------------------------------------------

drop policy if exists "live_loc_read_all" on public.driver_live_locations;
drop policy if exists live_loc_select_active_trip on public.driver_live_locations;
create policy live_loc_select_active_trip
on public.driver_live_locations
for select
using (
  auth.uid() = driver_id
  or public.current_profile_role() in ('admin', 'subtenant')
  or exists (
    select 1
    from public.package_activities pa
    join public.package_bookings pb on pb.id = pa.booking_id
    where pa.id = driver_live_locations.activity_id
      and lower(coalesce(pb.booking_status, pb.status, ''))
            not in ('cancelled', 'completed', 'rejected', 'done')
      and exists (
        select 1 from public.booking_drivers target_driver
        where target_driver.booking_id = pb.id
          and target_driver.driver_id = driver_live_locations.driver_id
          and target_driver.status = 'accepted'
      )
      and (
        pb.tourist_id = auth.uid()
        or exists (
          select 1 from public.booking_drivers requesting_driver
          where requesting_driver.booking_id = pb.id
            and requesting_driver.driver_id = auth.uid()
            and requesting_driver.status = 'accepted'
        )
      )
  )
);

-- The existing guest RPC is SECURITY DEFINER and therefore does not inherit
-- the table RLS above. Keep its link/access-code validation intact, but wrap it
-- so terminal bookings never return either cached or fallback current GPS.
do $$
begin
  -- This migration may be retried from the SQL editor. Preserve the first
  -- backup and do not try to rename the wrapper over an existing backup.
  if to_regprocedure(
    'public.get_shared_trip_details_before_p0_location_guard(text,text,text,text,boolean)'
  ) is null then
    if to_regprocedure(
      'public.get_shared_trip_details(text,text,text,text,boolean)'
    ) is null then
      raise exception 'GET_SHARED_TRIP_DETAILS_NOT_FOUND';
    end if;

    execute
      'alter function public.get_shared_trip_details(text, text, text, text, boolean) '
      'rename to get_shared_trip_details_before_p0_location_guard';
  end if;
end;
$$;

revoke all on function
  public.get_shared_trip_details_before_p0_location_guard(text, text, text, text, boolean)
  from public, anon, authenticated;

create or replace function public.get_shared_trip_details(
  p_public_token text,
  p_access_code text,
  p_device_info text default null,
  p_ip_address text default null,
  p_log_access boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_booking_status text;
  v_tour_status text;
begin
  v_result := public.get_shared_trip_details_before_p0_location_guard(
    p_public_token,
    p_access_code,
    p_device_info,
    p_ip_address,
    p_log_access
  );

  if coalesce(v_result->>'success', 'false') <> 'true' then
    return v_result;
  end if;

  v_booking_status := lower(coalesce(
    v_result->>'booking_status_detail',
    v_result->>'booking_status',
    ''
  ));
  v_tour_status := lower(coalesce(v_result->>'tour_status', ''));

  if v_booking_status in ('cancelled', 'completed', 'rejected', 'done')
     or v_tour_status in ('cancelled', 'completed', 'dropped_off') then
    v_result := jsonb_set(v_result, '{driver_latitude}', 'null'::jsonb, true);
    v_result := jsonb_set(v_result, '{driver_longitude}', 'null'::jsonb, true);
  end if;

  return v_result;
end;
$$;

grant execute on function public.get_shared_trip_details(text, text, text, text, boolean)
  to anon, authenticated;

-- Existing fully assigned advanced bookings receive requirements too.
do $$
declare
  v_booking_id uuid;
begin
  for v_booking_id in
    select pb.id
    from public.package_bookings pb
    where lower(coalesce(pb.booking_type, 'same_day')) = 'advanced'
      and lower(coalesce(pb.booking_status, pb.status, ''))
            not in ('cancelled', 'completed', 'rejected', 'done')
      and (
        select count(*) from public.booking_drivers bd
        where bd.booking_id = pb.id and bd.status = 'accepted'
      ) >= greatest(coalesce(pb.required_drivers, 1), 1)
  loop
    perform public.ensure_booking_payment_requirements(v_booking_id);
  end loop;
end;
$$;
