-- Booking-scoped tour Developer Tools. Package itinerary and municipal fare
-- configuration remain immutable; only the active booking stop is overridden.
begin;

alter table public.booking_stop_waiting_charges
  add column if not exists test_deadline_override timestamptz,
  add column if not exists test_rate_per_interval_override numeric(14,2)
    check (test_rate_per_interval_override >= 0),
  add column if not exists test_hourly_rate_override numeric(14,2)
    check (test_hourly_rate_override >= 0),
  add column if not exists test_override_kind text
    check (test_override_kind in ('remaining', 'overtime')),
  add column if not exists test_override_updated_by uuid
    references public.profiles(id) on delete set null,
  add column if not exists test_override_updated_at timestamptz;

do $constraints$
declare item record;
begin
  for item in
    select conname from pg_constraint
    where conrelid = 'public.booking_stop_waiting_charges'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%additional_amount =%hourly_rate%'
  loop
    execute format(
      'alter table public.booking_stop_waiting_charges drop constraint %I',
      item.conname
    );
  end loop;
end
$constraints$;

alter table public.booking_stop_waiting_charges
  add constraint booking_stop_waiting_effective_amount_check
  check (
    additional_amount = case
      when test_rate_per_interval_override is not null then round(
        chargeable_intervals * test_rate_per_interval_override,
        2
      )
      else round(
        chargeable_intervals * coalesce(hourly_rate, 0)
          * interval_minutes / 60.0,
        2
      )
    end
  );

create or replace function public.system_administrator_booking_test_authorized(
  p_booking_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and public.is_system_administrator()
    and exists (
      select 1 from public.package_bookings booking
      where booking.id = p_booking_id
    );
$$;

revoke all on function public.system_administrator_booking_test_authorized(uuid)
  from public, anon, authenticated;

create or replace function public.booking_test_session_active(
  p_booking_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select settings.developer_testing_enabled
    from public.system_settings settings
    where settings.singleton
  ), false) and exists (
    select 1
    from public.developer_test_sessions session
    where session.booking_id = p_booking_id
      and session.status = 'active'
      and session.expires_at > now()
  );
$$;

revoke all on function public.booking_test_session_active(uuid)
  from public, anon, authenticated;

create or replace function public.administrator_get_booking_developer_state(
  p_booking_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_booking public.package_bookings;
  v_driver public.booking_drivers;
  v_item public.booking_itinerary_items;
  v_charge public.booking_stop_waiting_charges;
  v_activity public.package_activities;
  v_deadline timestamptz;
  v_now timestamptz := clock_timestamp();
  v_remaining integer := 0;
  v_overtime integer := 0;
  v_intervals integer := 0;
  v_rate numeric := 0;
  v_fee numeric := 0;
  v_finalized numeric := 0;
begin
  if not public.system_administrator_booking_test_authorized(p_booking_id) then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  select * into v_driver
  from public.booking_drivers
  where booking_id = p_booking_id
    and status in ('accepted', 'completed')
  order by public.journey_state_order(journey_state), current_stop_index
  limit 1;

  if v_driver.id is not null then
    select * into v_item
    from public.booking_itinerary_items
    where booking_id = p_booking_id
    order by coalesce(order_number, 2147483647),
      coalesce(destination_order, 2147483647),
      arrival_time nulls last, created_at, id
    offset greatest(v_driver.current_stop_index, 0)
    limit 1;
  end if;

  if v_item.id is not null then
    select * into v_charge
    from public.booking_stop_waiting_charges
    where booking_id = p_booking_id
      and itinerary_item_id = v_item.id
    limit 1;
  end if;

  select * into v_activity
  from public.package_activities
  where booking_id = p_booking_id
  order by updated_at desc nulls last, created_at desc
  limit 1;

  v_deadline := coalesce(v_charge.test_deadline_override, v_charge.paid_until);
  v_rate := coalesce(
    v_charge.test_rate_per_interval_override,
    v_charge.rate_per_interval,
    v_booking.tour_waiting_rate_snapshot,
    0
  );
  if v_deadline is not null then
    v_remaining := greatest(
      0,
      ceil(extract(epoch from v_deadline - v_now) / 60.0)::integer
    );
    v_overtime := greatest(
      0,
      floor(extract(epoch from v_now - v_deadline) / 60.0)::integer
    );
  end if;
  v_intervals := public.tour_waiting_chargeable_intervals(
    v_overtime * 60,
    coalesce(v_charge.interval_minutes, v_booking.tour_waiting_interval_snapshot, 15)
  );
  v_fee := case when v_charge.test_rate_per_interval_override is not null
    then round(v_intervals * v_charge.test_rate_per_interval_override, 2)
    else round(v_intervals * coalesce(v_charge.hourly_rate, 0)
      * coalesce(
        v_charge.interval_minutes,
        v_booking.tour_waiting_interval_snapshot,
        15
      ) / 60.0, 2)
  end;

  select coalesce(sum(additional_amount), 0) into v_finalized
  from public.booking_stop_waiting_charges
  where booking_id = p_booking_id and status = 'finalized';

  return jsonb_build_object(
    'booking_id', v_booking.id,
    'controls_enabled', public.booking_test_session_active(p_booking_id),
    'booking_status', lower(coalesce(v_booking.booking_status, v_booking.status, 'unknown')),
    'tour_status', coalesce(v_activity.tour_status, v_activity.status, 'not_started'),
    'journey_state', coalesce(v_driver.journey_state, 'unassigned'),
    'current_stop_index', coalesce(v_driver.current_stop_index, 0),
    'current_stop_id', v_item.id,
    'current_stop_name', coalesce(v_item.destination_name, 'No active stop'),
    'arrival_status', case when v_item.actual_arrival_time is null then 'pending' else 'arrived' end,
    'departure_status', case when v_item.actual_departure_time is null then 'pending' else 'departed' end,
    'included_minutes', coalesce(v_item.estimated_stay_duration_minutes, 0),
    'elapsed_minutes', case when v_item.actual_arrival_time is null then 0 else
      greatest(0, floor(extract(epoch from v_now - v_item.actual_arrival_time) / 60.0)::integer) end,
    'effective_deadline', v_deadline,
    'server_time', v_now,
    'remaining_minutes', v_remaining,
    'overtime_minutes', v_overtime,
    'overtime_active', v_deadline is not null and v_now >= v_deadline,
    'interval_minutes', coalesce(v_charge.interval_minutes, v_booking.tour_waiting_interval_snapshot, 15),
    'configured_rate', coalesce(v_charge.rate_per_interval, v_booking.tour_waiting_rate_snapshot, 0),
    'custom_rate', v_charge.test_rate_per_interval_override,
    'effective_rate', v_rate,
    'chargeable_intervals', v_intervals,
    'additional_fee', v_fee,
    'booking_total', coalesce(v_booking.total_amount, 0) + v_finalized +
      case when v_charge.status = 'active' then v_fee else 0 end,
    'recent_test_actions', coalesce((
      select jsonb_agg(to_jsonb(recent_action) order by recent_action.created_at desc)
      from (
        select log.id, log.action, log.actor_id,
          coalesce(nullif(trim(actor.full_name), ''), actor.email, log.actor_id::text)
            as actor_name,
          log.description, log.created_at
        from public.audit_logs log
        left join public.profiles actor on actor.id = log.actor_id
        where log.table_name = 'package_bookings'
          and log.record_id = p_booking_id::text
          and log.action in (
            'remaining_time_override', 'overtime_triggered',
            'overtime_duration_override', 'overtime_rate_override',
            'arrival_simulated', 'departure_simulated', 'stop_completed',
            'previous_stop', 'next_stop', 'force_start', 'force_complete',
            'reset_stay_timer_override', 'reset_overtime_test'
          )
        order by log.created_at desc
        limit 12
      ) recent_action
    ), '[]'::jsonb),
    'override_active', v_charge.test_deadline_override is not null
      or v_charge.test_rate_per_interval_override is not null,
    'override_kind', v_charge.test_override_kind,
    'override_updated_at', v_charge.test_override_updated_at,
    'override_updated_by', v_charge.test_override_updated_by
  );
end;
$$;

revoke all on function public.administrator_get_booking_developer_state(uuid)
  from public, anon;
grant execute on function public.administrator_get_booking_developer_state(uuid)
  to authenticated;

create or replace function public.administrator_apply_booking_timing_test(
  p_booking_id uuid,
  p_mode text,
  p_minutes integer,
  p_custom_rate numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_charge public.booking_stop_waiting_charges;
  v_deadline timestamptz;
  v_seconds integer;
  v_intervals integer;
  v_rate numeric;
  v_hourly numeric;
  v_amount numeric(14,2);
  v_previous jsonb;
begin
  if not public.system_administrator_booking_test_authorized(p_booking_id) then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if not public.booking_test_session_active(p_booking_id) then
    raise exception 'ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED';
  end if;
  if p_mode not in ('remaining', 'overtime') then
    raise exception 'INVALID_TIMING_TEST_MODE';
  end if;
  if p_minutes is null or p_minutes < 0 or p_minutes > 1440 then
    raise exception 'INVALID_TEST_MINUTES';
  end if;
  if p_custom_rate is not null and (p_custom_rate < 0 or p_custom_rate > 1000000) then
    raise exception 'INVALID_TEST_RATE';
  end if;

  select charge.* into v_charge
  from public.booking_stop_waiting_charges charge
  join public.booking_itinerary_items item on item.id = charge.itinerary_item_id
  join public.booking_drivers driver on driver.booking_id = charge.booking_id
  where charge.booking_id = p_booking_id
    and charge.status = 'active'
    and item.actual_arrival_time is not null
    and item.actual_departure_time is null
    and driver.status = 'accepted'
    and driver.journey_state = 'at_stop'
    and item.id = (
      select current_item.id
      from public.booking_itinerary_items current_item
      where current_item.booking_id = p_booking_id
      order by coalesce(current_item.order_number, 2147483647),
        coalesce(current_item.destination_order, 2147483647),
        current_item.arrival_time nulls last,
        current_item.created_at,
        current_item.id
      offset driver.current_stop_index
      limit 1
    )
  order by charge.created_at desc
  limit 1
  for update of charge;
  if not found then raise exception 'ACTIVE_STOP_WAITING_LEDGER_REQUIRED'; end if;

  v_previous := jsonb_build_object(
    'deadline', v_charge.test_deadline_override,
    'rate', v_charge.test_rate_per_interval_override,
    'overtime_seconds', v_charge.overtime_seconds,
    'additional_amount', v_charge.additional_amount
  );
  v_deadline := case when p_mode = 'remaining'
    then clock_timestamp() + make_interval(mins => p_minutes)
    else clock_timestamp() - make_interval(mins => p_minutes)
  end;
  v_rate := coalesce(p_custom_rate, v_charge.rate_per_interval, 0);
  v_hourly := case when p_custom_rate is null then null else
    p_custom_rate * 60.0 / greatest(v_charge.interval_minutes, 1) end;
  v_seconds := greatest(0, floor(extract(epoch from clock_timestamp() - v_deadline))::integer);
  v_intervals := public.tour_waiting_chargeable_intervals(
    v_seconds,
    v_charge.interval_minutes
  );
  v_amount := case when p_custom_rate is not null
    then round(v_intervals * p_custom_rate, 2)
    else round(v_intervals * coalesce(v_charge.hourly_rate, 0)
      * v_charge.interval_minutes / 60.0, 2)
  end;

  update public.booking_stop_waiting_charges
  set test_deadline_override = v_deadline,
      test_rate_per_interval_override = p_custom_rate,
      test_hourly_rate_override = v_hourly,
      test_override_kind = p_mode,
      test_override_updated_by = v_actor,
      test_override_updated_at = clock_timestamp(),
      overtime_seconds = v_seconds,
      chargeable_intervals = v_intervals,
      additional_amount = v_amount,
      updated_at = clock_timestamp()
  where id = v_charge.id;

  insert into public.audit_logs(actor_id, action, table_name, record_id, description)
  values (
    v_actor,
    case
      when p_mode = 'remaining' then 'remaining_time_override'
      when p_minutes = 0 then 'overtime_triggered'
      else 'overtime_duration_override'
    end,
    'package_bookings',
    p_booking_id::text,
    jsonb_build_object(
      'booking_id', p_booking_id,
      'itinerary_item_id', v_charge.itinerary_item_id,
      'previous', v_previous,
      'new', jsonb_build_object(
        'mode', p_mode,
        'minutes', p_minutes,
        'deadline', v_deadline,
        'custom_rate', p_custom_rate,
        'effective_rate', v_rate,
        'intervals', v_intervals,
        'additional_amount', v_amount
      )
    )::text
  );

  if p_custom_rate is not null then
    insert into public.audit_logs(
      actor_id,
      action,
      table_name,
      record_id,
      description
    )
    values (
      v_actor,
      'overtime_rate_override',
      'package_bookings',
      p_booking_id::text,
      jsonb_build_object(
        'booking_id', p_booking_id,
        'itinerary_item_id', v_charge.itinerary_item_id,
        'previous', jsonb_build_object(
          'configured_rate', v_charge.rate_per_interval,
          'test_rate', v_charge.test_rate_per_interval_override
        ),
        'new', jsonb_build_object(
          'custom_rate', p_custom_rate,
          'interval_minutes', v_charge.interval_minutes
        )
      )::text
    );
  end if;

  return public.administrator_get_booking_developer_state(p_booking_id);
end;
$$;

revoke all on function public.administrator_apply_booking_timing_test(
  uuid, text, integer, numeric
) from public, anon;
grant execute on function public.administrator_apply_booking_timing_test(
  uuid, text, integer, numeric
) to authenticated;

create or replace function public.administrator_reset_booking_timing_test(
  p_booking_id uuid,
  p_scope text default 'all'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_charge public.booking_stop_waiting_charges;
  v_deadline timestamptz;
  v_seconds integer;
  v_intervals integer;
  v_rate numeric;
  v_amount numeric(14,2);
  v_previous jsonb;
begin
  if not public.system_administrator_booking_test_authorized(p_booking_id) then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if not public.booking_test_session_active(p_booking_id) then
    raise exception 'ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED';
  end if;
  if p_scope not in ('stay', 'overtime', 'all') then
    raise exception 'INVALID_RESET_SCOPE';
  end if;

  select * into v_charge
  from public.booking_stop_waiting_charges
  where booking_id = p_booking_id and status = 'active'
  order by created_at desc limit 1
  for update;
  if not found then raise exception 'ACTIVE_STOP_WAITING_LEDGER_REQUIRED'; end if;

  v_previous := jsonb_build_object(
    'deadline', v_charge.test_deadline_override,
    'rate', v_charge.test_rate_per_interval_override,
    'kind', v_charge.test_override_kind
  );
  v_deadline := case when p_scope in ('stay', 'overtime', 'all')
    then v_charge.paid_until else coalesce(v_charge.test_deadline_override, v_charge.paid_until) end;
  v_seconds := greatest(0, floor(extract(epoch from clock_timestamp() - v_deadline))::integer);
  v_intervals := public.tour_waiting_chargeable_intervals(v_seconds, v_charge.interval_minutes);
  v_rate := case when p_scope = 'stay'
    then v_charge.test_rate_per_interval_override
    else null
  end;
  v_amount := case when v_rate is not null
    then round(v_intervals * v_rate, 2)
    else round(v_intervals * coalesce(v_charge.hourly_rate, 0)
      * v_charge.interval_minutes / 60.0, 2)
  end;

  update public.booking_stop_waiting_charges
  set test_deadline_override = null,
      test_rate_per_interval_override = case when p_scope = 'stay'
        then test_rate_per_interval_override else null end,
      test_hourly_rate_override = case when p_scope = 'stay'
        then test_hourly_rate_override else null end,
      test_override_kind = case when p_scope = 'stay'
        and test_rate_per_interval_override is not null then 'overtime' else null end,
      test_override_updated_by = case when p_scope = 'stay'
        and test_rate_per_interval_override is not null then v_actor else null end,
      test_override_updated_at = case when p_scope = 'stay'
        and test_rate_per_interval_override is not null then clock_timestamp() else null end,
      overtime_seconds = v_seconds,
      chargeable_intervals = v_intervals,
      additional_amount = v_amount,
      updated_at = clock_timestamp()
  where id = v_charge.id;

  insert into public.audit_logs(actor_id, action, table_name, record_id, description)
  values (
    v_actor,
    case when p_scope = 'stay' then 'reset_stay_timer_override'
      else 'reset_overtime_test' end,
    'package_bookings',
    p_booking_id::text,
    jsonb_build_object(
      'booking_id', p_booking_id,
      'itinerary_item_id', v_charge.itinerary_item_id,
      'scope', p_scope,
      'previous', v_previous,
      'new', jsonb_build_object(
        'restored_deadline', v_charge.paid_until,
        'restored_rate', v_charge.rate_per_interval
      )
    )::text
  );

  return public.administrator_get_booking_developer_state(p_booking_id);
end;
$$;

revoke all on function public.administrator_reset_booking_timing_test(uuid, text)
  from public, anon;
grant execute on function public.administrator_reset_booking_timing_test(uuid, text)
  to authenticated;

-- All progression writes are booking scoped, session gated and audited. The
-- action still follows the canonical milestone tables so existing realtime,
-- waiting-charge and completion triggers continue to run.
create or replace function public.administrator_progress_booking_test(
  p_booking_id uuid,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_booking public.package_bookings;
  v_driver public.booking_drivers;
  v_item public.booking_itinerary_items;
  v_target public.booking_itinerary_items;
  v_count integer;
  v_activity uuid;
  v_previous jsonb;
  v_new_index integer;
  v_finalization jsonb;
begin
  if not public.system_administrator_booking_test_authorized(p_booking_id) then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if not public.booking_test_session_active(p_booking_id) then
    raise exception 'ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED';
  end if;
  if p_action not in (
    'force_start', 'simulate_arrival', 'simulate_departure',
    'complete_stop', 'previous_stop', 'next_stop', 'force_complete'
  ) then raise exception 'INVALID_BOOKING_TEST_ACTION'; end if;

  select * into v_booking from public.package_bookings
  where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
      in ('cancelled', 'rejected', 'expired', 'completed', 'done') then
    raise exception 'TERMINAL_BOOKING_CANNOT_BE_TESTED';
  end if;

  select * into v_driver from public.booking_drivers
  where booking_id = p_booking_id and status = 'accepted'
  order by public.journey_state_order(journey_state), current_stop_index
  limit 1 for update;
  if not found then raise exception 'ACCEPTED_DRIVER_REQUIRED'; end if;

  select count(*) into v_count from public.booking_itinerary_items
  where booking_id = p_booking_id;
  if v_count = 0 then raise exception 'ITINERARY_REQUIRED'; end if;

  select * into v_item from public.booking_itinerary_items
  where booking_id = p_booking_id
  order by coalesce(order_number, 2147483647),
    coalesce(destination_order, 2147483647), arrival_time nulls last,
    created_at, id
  offset greatest(v_driver.current_stop_index, 0) limit 1;

  select id into v_activity from public.package_activities
  where booking_id = p_booking_id order by updated_at desc nulls last limit 1;
  if v_activity is null then raise exception 'ACTIVITY_NOT_FOUND'; end if;

  v_previous := jsonb_build_object(
    'booking_status', v_booking.booking_status,
    'journey_state', v_driver.journey_state,
    'current_stop_index', v_driver.current_stop_index,
    'itinerary_item_id', v_item.id,
    'arrival', v_item.actual_arrival_time,
    'departure', v_item.actual_departure_time
  );

  perform set_config('touristrike.journey_rpc', 'true', true);
  perform set_config('touristrike.gps_transition_verified', 'true', true);
  perform set_config('touristrike.validated_transition', 'true', true);
  perform set_config('touristrike.manual_lifecycle_reason',
    'Administrator booking-scoped Developer Tools override', true);

  if p_action = 'force_start' then
    if v_driver.journey_state not in ('assigned', 'en_route_pickup', 'at_pickup', 'boarded') then
      raise exception 'FORCE_START_NOT_ALLOWED_FROM_CURRENT_STATE';
    end if;
    update public.booking_drivers
    set journey_state = 'en_route_stop', current_stop_index = 0,
      state_updated_at = clock_timestamp()
    where booking_id = p_booking_id and status = 'accepted';
    update public.package_bookings
    set booking_status = 'on_tour',
      current_spot_index = 0, updated_at = clock_timestamp()
    where id = p_booking_id;
    update public.package_activities
    set status = 'ongoing', tour_status = 'en_route_to_spot',
      current_spot_index = 0, updated_at = clock_timestamp()
    where id = v_activity;

  elsif p_action = 'simulate_arrival' then
    if v_driver.journey_state <> 'en_route_stop' then
      raise exception 'ARRIVAL_REQUIRES_EN_ROUTE_STOP';
    end if;
    insert into public.booking_driver_arrivals(
      booking_driver_id, itinerary_item_id, arrived_at, latitude, longitude
    )
    select driver.id, v_item.id, clock_timestamp(), location.latitude, location.longitude
    from public.booking_drivers driver
    left join public.driver_live_locations location on location.driver_id = driver.driver_id
    where driver.booking_id = p_booking_id and driver.status = 'accepted'
    on conflict (booking_driver_id, itinerary_item_id) do update
      set arrived_at = excluded.arrived_at;
    update public.booking_itinerary_items
    set actual_arrival_time = clock_timestamp(), spot_status = 'at_spot'
    where id = v_item.id;
    update public.booking_drivers
    set journey_state = 'at_stop', state_updated_at = clock_timestamp()
    where booking_id = p_booking_id and status = 'accepted';
    update public.package_activities
    set status = 'ongoing', tour_status = 'at_spot',
      current_spot_index = v_driver.current_stop_index,
      updated_at = clock_timestamp()
    where id = v_activity;

  elsif p_action in ('simulate_departure', 'complete_stop') then
    if v_driver.journey_state <> 'at_stop' then
      raise exception 'DEPARTURE_REQUIRES_AT_STOP';
    end if;
    update public.booking_driver_arrivals
    set departed_at = coalesce(departed_at, clock_timestamp())
    where itinerary_item_id = v_item.id
      and booking_driver_id in (
        select id from public.booking_drivers
        where booking_id = p_booking_id and status = 'accepted'
      );
    update public.booking_itinerary_items
    set actual_departure_time = coalesce(actual_departure_time, clock_timestamp()),
      spot_status = 'completed'
    where id = v_item.id;
    update public.booking_drivers
    set journey_state = 'stop_done', state_updated_at = clock_timestamp()
    where booking_id = p_booking_id and status = 'accepted';
    update public.package_activities
    set status = 'ongoing', tour_status = 'on_tour',
      updated_at = clock_timestamp()
    where id = v_activity;

  elsif p_action = 'next_stop' then
    if v_driver.journey_state <> 'stop_done' then
      raise exception 'NEXT_STOP_REQUIRES_COMPLETED_STOP';
    end if;
    v_new_index := v_driver.current_stop_index + 1;
    if v_new_index >= v_count then raise exception 'ALREADY_AT_LAST_STOP'; end if;
    update public.booking_drivers
    set journey_state = 'en_route_stop', current_stop_index = v_new_index,
      state_updated_at = clock_timestamp()
    where booking_id = p_booking_id and status = 'accepted';
    update public.package_bookings set current_spot_index = v_new_index,
      updated_at = clock_timestamp() where id = p_booking_id;
    update public.package_activities set tour_status = 'en_route_to_spot',
      current_spot_index = v_new_index, updated_at = clock_timestamp()
    where id = v_activity;

  elsif p_action = 'previous_stop' then
    if v_driver.current_stop_index <= 0 then raise exception 'ALREADY_AT_FIRST_STOP'; end if;
    if v_driver.journey_state not in ('en_route_stop', 'stop_done') then
      raise exception 'PREVIOUS_STOP_NOT_SAFE_FROM_CURRENT_STATE';
    end if;
    v_new_index := v_driver.current_stop_index - 1;
    select * into v_target from public.booking_itinerary_items
    where booking_id = p_booking_id
    order by coalesce(order_number, 2147483647),
      coalesce(destination_order, 2147483647), arrival_time nulls last,
      created_at, id offset v_new_index limit 1;
    if exists (
      select 1 from public.booking_stop_waiting_charges
      where itinerary_item_id = v_target.id
        and (status = 'finalized' or additional_amount > 0)
    ) then raise exception 'PREVIOUS_STOP_BLOCKED_BY_FINANCIAL_HISTORY'; end if;
    delete from public.booking_stop_waiting_charges
    where itinerary_item_id = v_target.id and status = 'active';
    delete from public.booking_driver_arrivals where itinerary_item_id = v_target.id;
    update public.booking_itinerary_items
    set actual_arrival_time = null, actual_departure_time = null,
      spot_status = 'pending' where id = v_target.id;
    update public.booking_drivers
    set journey_state = 'en_route_stop', current_stop_index = v_new_index,
      state_updated_at = clock_timestamp()
    where booking_id = p_booking_id and status = 'accepted';
    update public.package_bookings set current_spot_index = v_new_index,
      updated_at = clock_timestamp() where id = p_booking_id;
    update public.package_activities set tour_status = 'en_route_to_spot',
      current_spot_index = v_new_index, updated_at = clock_timestamp()
    where id = v_activity;

  elsif p_action = 'force_complete' then
    if exists (
      select 1 from public.booking_itinerary_items
      where booking_id = p_booking_id
        and lower(coalesce(spot_status, 'pending')) <> 'completed'
    ) then raise exception 'FORCE_COMPLETE_REQUIRES_COMPLETED_ITINERARY'; end if;
    if exists (
      select 1 from public.booking_stop_waiting_charges
      where booking_id = p_booking_id and status = 'active'
    ) then raise exception 'FORCE_COMPLETE_REQUIRES_NO_ACTIVE_WAITING_LEDGER'; end if;
    if not public.is_booking_remaining_payment_satisfied(p_booking_id) then
      raise exception 'FORCE_COMPLETE_REQUIRES_SETTLED_PAYMENT';
    end if;
    update public.booking_drivers
    set journey_state = 'completed', status = 'completed',
      completed_at = coalesce(completed_at, clock_timestamp()),
      state_updated_at = clock_timestamp()
    where booking_id = p_booking_id and status = 'accepted';
    update public.package_activities
    set tour_status = 'ready_to_complete', updated_at = clock_timestamp()
    where id = v_activity;
    v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);
    if not coalesce((v_finalization->>'overall_completed')::boolean, false) then
      raise exception 'BOOKING_COMPLETION_VALIDATION_FAILED';
    end if;
  end if;

  select * into v_booking from public.package_bookings
  where id = p_booking_id;
  select * into v_driver from public.booking_drivers
  where booking_id = p_booking_id and status in ('accepted', 'completed')
  order by public.journey_state_order(journey_state), current_stop_index
  limit 1;

  insert into public.trip_status_logs(
    activity_id, booking_id, status, spot_index, logged_at, notes
  ) values (
    v_activity, p_booking_id, 'developer_test_' || p_action,
    coalesce(v_new_index, v_driver.current_stop_index), clock_timestamp(),
    jsonb_build_object('actor_id', v_actor, 'previous', v_previous)::text
  );
  insert into public.audit_logs(actor_id, action, table_name, record_id, description)
  values (
    v_actor,
    case p_action
      when 'simulate_arrival' then 'arrival_simulated'
      when 'simulate_departure' then 'departure_simulated'
      when 'complete_stop' then 'stop_completed'
      when 'force_start' then 'force_start'
      when 'force_complete' then 'force_complete'
      else p_action
    end,
    'package_bookings', p_booking_id::text,
    jsonb_build_object('booking_id', p_booking_id, 'previous', v_previous,
      'action', p_action, 'new', jsonb_build_object(
        'booking_status', v_booking.booking_status,
        'journey_state', v_driver.journey_state,
        'current_stop_index', v_driver.current_stop_index
      ))::text
  );

  return public.administrator_get_booking_developer_state(p_booking_id);
end;
$$;

revoke all on function public.administrator_progress_booking_test(uuid, text)
  from public, anon;
grant execute on function public.administrator_progress_booking_test(uuid, text)
  to authenticated;

-- Production waiting logic reads the booking-stop override when present. The
-- original paid_until, included_minutes and fare snapshots are never changed.
create or replace function public.finalize_booking_stop_waiting_charge()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_charge public.booking_stop_waiting_charges; v_seconds integer;
  v_intervals integer; v_amount numeric(14,2); v_outstanding numeric;
  v_activity uuid; v_deadline timestamptz;
begin
  if new.actual_departure_time is null or old.actual_departure_time is not null then return new; end if;
  select * into v_charge from public.booking_stop_waiting_charges
    where booking_id=new.booking_id and itinerary_item_id=new.id for update;
  if not found or v_charge.status='finalized' then return new; end if;
  v_deadline := coalesce(v_charge.test_deadline_override, v_charge.paid_until);
  v_seconds := greatest(0,floor(extract(epoch from new.actual_departure_time-v_deadline))::integer);
  v_intervals := public.tour_waiting_chargeable_intervals(v_seconds, v_charge.interval_minutes);
  v_amount := case when v_charge.test_rate_per_interval_override is not null
    then round(v_intervals * v_charge.test_rate_per_interval_override, 2)
    else round(v_intervals * coalesce(v_charge.hourly_rate, 0)
      * v_charge.interval_minutes / 60.0, 2)
  end;
  update public.booking_stop_waiting_charges set
    departed_at=new.actual_departure_time,overtime_seconds=v_seconds,
    chargeable_intervals=v_intervals,additional_amount=v_amount,
    status='finalized',finalized_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=v_charge.id and status='active';
  if v_amount > 0 then
    update public.package_bookings
      set remaining_balance=coalesce(remaining_balance,0)+v_amount,
        updated_at=clock_timestamp() where id=new.booking_id
      returning remaining_balance into v_outstanding;
    update public.booking_payment_requirements set amount=v_outstanding,
      status='required',satisfied_at=null,satisfied_by_payment_record_id=null,
      updated_at=clock_timestamp()
      where booking_id=new.booking_id and payment_stage='remaining_balance';
    if not found then
      insert into public.booking_payment_requirements(booking_id,payment_stage,amount)
      values(new.booking_id,'remaining_balance',v_outstanding);
    end if;
  end if;
  select id into v_activity from public.package_activities where booking_id=new.booking_id limit 1;
  insert into public.trip_status_logs(activity_id,booking_id,status,notes,logged_at)
  values(v_activity,new.booking_id,'waiting_charge_finalized',
    jsonb_build_object('itinerary_item_id',new.id,'municipality',v_charge.municipality,
      'rate',coalesce(v_charge.test_rate_per_interval_override,v_charge.rate_per_interval),
      'intervals',v_intervals,'amount',v_amount,
      'test_override_used',v_charge.test_deadline_override is not null
        or v_charge.test_rate_per_interval_override is not null)::text,
    clock_timestamp());
  return new;
end $$;

create or replace function public.refresh_active_tour_waiting()
returns integer language plpgsql security definer set search_path = '' as $$
declare c public.booking_stop_waiting_charges; v_now timestamptz := clock_timestamp();
  v_seconds integer; v_intervals integer; v_count integer := 0; v_user uuid;
  v_deadline timestamptz; v_hourly numeric; v_amount numeric;
  v_rate_configured boolean;
begin
  for c in select charge.* from public.booking_stop_waiting_charges charge
    join public.package_bookings b on b.id=charge.booking_id
    where charge.status='active'
      and lower(coalesce(b.booking_status,b.status,''))
        not in ('cancelled','rejected','expired','completed','done')
      and coalesce(charge.test_deadline_override,charge.paid_until)
        <= v_now + make_interval(mins => charge.interval_minutes)
    for update of charge skip locked loop
    v_deadline := coalesce(c.test_deadline_override,c.paid_until);
    v_rate_configured := coalesce(
      c.test_hourly_rate_override,
      c.hourly_rate
    ) is not null;
    v_hourly := coalesce(c.test_hourly_rate_override,c.hourly_rate,0);
    for v_user in
      select b.tourist_id from public.package_bookings b where b.id=c.booking_id
      union select d.driver_id from public.booking_drivers d
        where d.booking_id=c.booking_id and d.status='accepted'
    loop
      if v_now >= v_deadline - interval '15 minutes'
          and v_now < v_deadline - interval '5 minutes' then
        perform public.emit_tour_notification(v_user,c.booking_id,
          'stay:15:'||c.itinerary_item_id,'paid_stay_ending',
          'Paid stay ending soon','Included waiting at '
          ||(select destination_name from public.booking_itinerary_items
             where id=c.itinerary_item_id)||' ends at '
          ||to_char(v_deadline at time zone 'Asia/Manila','HH12:MI AM')
          ||case when not v_rate_configured
            then '. No additional fee will be assessed for this stop because the municipality rate was not configured at arrival.'
            else '. One configured interval after the included stay is free.' end,true);
      end if;
      if v_now >= v_deadline - interval '5 minutes' and v_now < v_deadline then
        perform public.emit_tour_notification(v_user,c.booking_id,
          'stay:5:'||c.itinerary_item_id,'paid_stay_ending',
          'Paid stay ending soon','Included waiting at '
          ||(select destination_name from public.booking_itinerary_items
             where id=c.itinerary_item_id)||' ends at '
          ||to_char(v_deadline at time zone 'Asia/Manila','HH12:MI AM')
          ||case when not v_rate_configured
            then '. No additional fee will be assessed for this stop because the municipality rate was not configured at arrival.'
            else '. One configured interval after the included stay is free.' end,true);
      end if;
      if v_now >= v_deadline + make_interval(mins => c.interval_minutes) then
        perform public.emit_tour_notification(v_user,c.booking_id,
          'stay:overtime:'||c.itinerary_item_id,'additional_waiting',
          case when not v_rate_configured
            then 'Included stay ended' else 'Additional waiting' end,
          'Included waiting has ended at '
          ||(select destination_name from public.booking_itinerary_items
             where id=c.itinerary_item_id)
          ||case when not v_rate_configured
            then '. No additional fee will be assessed for this stop because the municipality rate was not configured at arrival.'
            else '. The free grace interval has ended; additional charges now apply.' end,true);
      end if;
    end loop;
    v_seconds := greatest(0,floor(extract(epoch from v_now-v_deadline))::integer);
    v_intervals := public.tour_waiting_chargeable_intervals(v_seconds,c.interval_minutes);
    v_amount := case when c.test_rate_per_interval_override is not null
      then round(v_intervals*c.test_rate_per_interval_override,2)
      else round(v_intervals*v_hourly*c.interval_minutes/60.0,2)
    end;
    if v_intervals <> c.chargeable_intervals or v_amount <> c.additional_amount then
      update public.booking_stop_waiting_charges set overtime_seconds=v_seconds,
        chargeable_intervals=v_intervals,additional_amount=v_amount,
        updated_at=v_now where id=c.id and status='active';
      v_count := v_count+1;
    end if;
  end loop;
  return v_count;
end $$;
revoke all on function public.refresh_active_tour_waiting()
  from public,anon,authenticated;

create or replace function public.get_booking_waiting_summary(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare b public.package_bookings; v_rate numeric; v_subtenant uuid;
  v_interval integer := 15; v_finalized numeric; v_accrued numeric;
  v_now timestamptz := clock_timestamp();
begin
  select * into b from public.package_bookings where id=p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if not public.can_read_tour_booking(b.id) then raise exception 'BOOKING_ACCESS_DENIED'; end if;
  v_subtenant := b.tour_waiting_subtenant_id;
  v_rate := b.tour_waiting_rate_snapshot;
  if v_rate is null then
    select r.subtenant_id,r.rate into v_subtenant,v_rate
    from public.resolve_tour_waiting_rate(b.municipality,b.province) r;
  end if;
  v_interval := coalesce(b.tour_waiting_interval_snapshot,15);
  select coalesce(sum(additional_amount) filter(where status='finalized'),0),
    coalesce(sum(additional_amount) filter(where status='active'),0)
  into v_finalized,v_accrued from public.booking_stop_waiting_charges
  where booking_id=b.id;
  return jsonb_build_object(
    'booking_id',b.id,'municipality',b.municipality,'subtenant_id',v_subtenant,
    'current_rate_per_15_minutes',v_rate,'current_interval_minutes',v_interval,
    'server_time',v_now,
    'package_remaining',greatest(0,coalesce(b.remaining_balance,0)-v_finalized),
    'finalized_waiting',v_finalized,'accrued_waiting',v_accrued,
    'total_remaining',greatest(0,coalesce(b.remaining_balance,0))+v_accrued,
    'charges',coalesce((select jsonb_agg(jsonb_build_object(
      'itinerary_item_id',c.itinerary_item_id,'destination_name',i.destination_name,
      'arrived_at',c.arrived_at,
      'paid_until',coalesce(c.test_deadline_override,c.paid_until),
      'configured_paid_until',c.paid_until,'departed_at',c.departed_at,
      'included_minutes',c.included_minutes,'interval_minutes',c.interval_minutes,
      'rate_per_interval',coalesce(c.test_rate_per_interval_override,c.rate_per_interval),
      'configured_rate_per_interval',c.rate_per_interval,
      'overtime_seconds',c.overtime_seconds,
      'chargeable_intervals',c.chargeable_intervals,
      'additional_amount',c.additional_amount,'status',c.status,
      'test_override_active',c.test_deadline_override is not null
        or c.test_rate_per_interval_override is not null,
      'test_override_kind',c.test_override_kind
    ) order by c.arrived_at) from public.booking_stop_waiting_charges c
      join public.booking_itinerary_items i on i.id=c.itinerary_item_id
      where c.booking_id=b.id),'[]'::jsonb)
  );
end $$;

commit;
