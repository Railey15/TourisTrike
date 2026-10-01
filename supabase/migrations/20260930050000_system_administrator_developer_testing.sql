-- Administrator-controlled, booking-scoped developer testing authorization.
-- The legacy developer-test system remains intact for comparison and rollback.

begin;

alter table public.system_settings
  add column if not exists developer_testing_enabled boolean not null default false,
  add column if not exists developer_testing_updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists developer_testing_updated_at timestamptz;

create table if not exists public.developer_test_sessions (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.package_bookings(id) on delete cascade,
  status text not null default 'active'
    check (status in ('active', 'deactivated', 'expired')),
  activated_by uuid not null references public.profiles(id) on delete restrict,
  activated_at timestamptz not null default now(),
  expires_at timestamptz not null,
  deactivated_by uuid references public.profiles(id) on delete restrict,
  deactivated_at timestamptz,
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  bypass_scheduled_start boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint developer_test_sessions_expiry_check check (expires_at > activated_at),
  constraint developer_test_sessions_deactivation_check check (
    (status = 'deactivated' and deactivated_by is not null and deactivated_at is not null)
    or (status <> 'deactivated' and deactivated_by is null and deactivated_at is null)
  )
);

create unique index if not exists developer_test_sessions_one_active_booking_idx
  on public.developer_test_sessions (booking_id)
  where status = 'active';
create index if not exists developer_test_sessions_active_expiry_idx
  on public.developer_test_sessions (expires_at)
  where status = 'active';

alter table public.developer_test_sessions enable row level security;
revoke all on table public.developer_test_sessions from public, anon, authenticated;

create or replace function public.developer_test_schedule_bypass_authorized(
  p_booking_id uuid,
  p_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_actor_id is not null
    and coalesce((
      select s.developer_testing_enabled
      from public.system_settings s
      where s.singleton
      limit 1
    ), false)
    and exists (
      select 1
      from public.developer_test_sessions dts
      where dts.booking_id = p_booking_id
        and dts.status = 'active'
        and dts.expires_at > now()
        and dts.bypass_scheduled_start
    )
    and (
      exists (
        select 1
        from public.package_bookings b
        where b.id = p_booking_id
          and b.tourist_id = p_actor_id
      )
      or exists (
        select 1
        from public.booking_drivers bd
        where bd.booking_id = p_booking_id
          and bd.driver_id = p_actor_id
          and bd.status in ('accepted', 'completed')
      )
    );
$$;
revoke all on function public.developer_test_schedule_bypass_authorized(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.get_my_booking_test_authorization(p_booking_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_is_participant boolean := false;
  v_enabled boolean := false;
  v_session public.developer_test_sessions;
begin
  if v_actor is null then
    raise exception 'UNAUTHENTICATED' using errcode = '42501';
  end if;

  select exists (
    select 1 from public.package_bookings b
    where b.id = p_booking_id and b.tourist_id = v_actor
  ) or exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = p_booking_id
      and bd.driver_id = v_actor
      and bd.status in ('accepted', 'completed')
  ) into v_is_participant;

  if not v_is_participant then
    return jsonb_build_object(
      'authorized', false,
      'booking_id', null,
      'session_id', null,
      'expires_at', null,
      'bypass_scheduled_start', false
    );
  end if;

  select coalesce(s.developer_testing_enabled, false)
  into v_enabled
  from public.system_settings s
  where s.singleton
  limit 1;

  select * into v_session
  from public.developer_test_sessions dts
  where dts.booking_id = p_booking_id
    and dts.status = 'active'
    and dts.expires_at > now()
  order by dts.activated_at desc
  limit 1;

  return jsonb_build_object(
    'authorized', coalesce(v_enabled, false)
      and v_session.id is not null
      and v_session.bypass_scheduled_start,
    'booking_id', p_booking_id,
    'session_id', v_session.id,
    'expires_at', v_session.expires_at,
    'bypass_scheduled_start', coalesce(v_session.bypass_scheduled_start, false)
  );
end;
$$;
revoke all on function public.get_my_booking_test_authorization(uuid)
  from public, anon;
grant execute on function public.get_my_booking_test_authorization(uuid)
  to authenticated;

create or replace function public.administrator_get_developer_testing_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'enabled', coalesce(s.developer_testing_enabled, false),
    'updated_by', s.developer_testing_updated_by,
    'updated_at', s.developer_testing_updated_at,
    'eligible_bookings', (
      select count(*)
      from public.package_bookings b
      where lower(coalesce(b.booking_status, b.status, ''))
          not in ('cancelled', 'rejected', 'completed', 'expired')
        and exists (
          select 1 from public.profiles tourist
          where tourist.id = b.tourist_id and tourist.role = 'tourist'
        )
        and (
          select count(*) from public.booking_drivers bd
          join public.profiles driver on driver.id = bd.driver_id and driver.role = 'driver'
          where bd.booking_id = b.id and bd.status in ('accepted', 'completed')
        ) >= greatest(coalesce(b.required_drivers, 1), 1)
    ),
    'active_sessions', (
      select count(*) from public.developer_test_sessions dts
      where dts.status = 'active' and dts.expires_at > now()
    ),
    'upcoming_bookings', (
      select count(*) from public.package_bookings b
      where b.scheduled_start_at > now()
        and lower(coalesce(b.booking_status, b.status, ''))
          not in ('cancelled', 'rejected', 'completed', 'expired')
    ),
    'expiring_soon', (
      select count(*) from public.developer_test_sessions dts
      where dts.status = 'active'
        and dts.expires_at > now()
        and dts.expires_at <= now() + interval '3 hours'
    )
  ) into v_result
  from public.system_settings s
  where s.singleton
  limit 1;

  return coalesce(v_result, jsonb_build_object(
    'enabled', false,
    'updated_by', null,
    'updated_at', null,
    'eligible_bookings', 0,
    'active_sessions', 0,
    'upcoming_bookings', 0,
    'expiring_soon', 0
  ));
end;
$$;
revoke all on function public.administrator_get_developer_testing_overview()
  from public, anon;
grant execute on function public.administrator_get_developer_testing_overview()
  to authenticated;

create or replace function public.administrator_list_testable_bookings(
  p_search text default null,
  p_booking_filter text default 'all',
  p_test_filter text default 'all',
  p_limit integer default 25,
  p_offset integer default 0
)
returns table (
  booking_id uuid,
  booking_reference text,
  tourist_id uuid,
  tourist_name text,
  package_id bigint,
  package_name text,
  municipality text,
  scheduled_start_at timestamptz,
  estimated_end_at timestamptz,
  booking_status text,
  tour_status text,
  drivers jsonb,
  required_drivers integer,
  assigned_driver_count integer,
  downpayment_ready boolean,
  remaining_payment_ready boolean,
  valid_tourist boolean,
  drivers_ready boolean,
  booking_state_valid boolean,
  eligible boolean,
  eligibility_reason text,
  test_session_id uuid,
  test_session_active boolean,
  activated_by uuid,
  activated_by_name text,
  activated_at timestamptz,
  expires_at timestamptz,
  reason text,
  bypass_scheduled_start boolean,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if p_booking_filter not in ('all', 'upcoming', 'active', 'completed', 'cancelled')
     or p_test_filter not in ('all', 'active', 'inactive')
     or p_limit not between 1 and 100
     or p_offset < 0 then
    raise exception 'INVALID_DEVELOPER_BOOKING_FILTERS' using errcode = '22023';
  end if;

  return query
  with booking_rows as (
    select
      b.id as row_booking_id,
      '#' || upper(substr(b.id::text, 1, 8)) as row_booking_reference,
      b.tourist_id as row_tourist_id,
      coalesce(nullif(btrim(t.full_name), ''),
        nullif(btrim(concat_ws(' ', t.first_name, t.last_name)), ''),
        'Unnamed tourist') as row_tourist_name,
      b.package_id as row_package_id,
      coalesce(nullif(btrim(tp.title), ''), 'Untitled package') as row_package_name,
      coalesce(nullif(btrim(b.municipality), ''), nullif(btrim(tp.city), ''), '') as row_municipality,
      b.scheduled_start_at,
      b.estimated_end_at,
      lower(coalesce(b.booking_status, b.status, 'unknown')) as row_booking_status,
      coalesce(activity.tour_status, activity.status, 'pending') as row_tour_status,
      coalesce(driver_info.drivers, '[]'::jsonb) as row_drivers,
      greatest(coalesce(b.required_drivers, 1), 1) as row_required_drivers,
      coalesce(driver_info.driver_count, 0)::integer as row_driver_count,
      public.is_booking_downpayment_confirmed(b.id) as row_downpayment_ready,
      public.is_booking_remaining_payment_satisfied(b.id) as row_remaining_payment_ready,
      t.id is not null and t.role = 'tourist' as row_valid_tourist,
      coalesce(driver_info.driver_count, 0) >= greatest(coalesce(b.required_drivers, 1), 1)
        as row_drivers_ready,
      lower(coalesce(b.booking_status, b.status, ''))
        not in ('cancelled', 'rejected', 'completed', 'expired')
        as row_booking_state_valid,
      t.id is not null
        and t.role = 'tourist'
        and lower(coalesce(b.booking_status, b.status, ''))
          not in ('cancelled', 'rejected', 'completed', 'expired')
        and coalesce(driver_info.driver_count, 0) >= greatest(coalesce(b.required_drivers, 1), 1)
        as row_eligible,
      case
        when t.id is null or t.role is distinct from 'tourist' then 'A valid Tourist is required.'
        when lower(coalesce(b.booking_status, b.status, ''))
          in ('cancelled', 'rejected', 'completed', 'expired') then 'The booking is in a terminal state.'
        when coalesce(driver_info.driver_count, 0) < greatest(coalesce(b.required_drivers, 1), 1)
          then 'All required Driver slots must be accepted.'
        else ''
      end as row_eligibility_reason,
      session_info.id as row_session_id,
      session_info.id is not null as row_session_active,
      session_info.activated_by as row_activated_by,
      coalesce(nullif(btrim(admin_profile.full_name), ''),
        nullif(btrim(concat_ws(' ', admin_profile.first_name, admin_profile.last_name)), ''),
        '') as row_activated_by_name,
      session_info.activated_at as row_activated_at,
      session_info.expires_at as row_expires_at,
      session_info.reason as row_reason,
      coalesce(session_info.bypass_scheduled_start, false) as row_bypass_scheduled_start,
      concat_ws(' ', b.id::text, t.full_name, t.first_name, t.last_name,
        tp.title, b.municipality, tp.city, driver_info.search_names) as search_text
    from public.package_bookings b
    left join public.profiles t on t.id = b.tourist_id
    left join public.tour_packages tp on tp.id = b.package_id
    left join lateral (
      select pa.status, pa.tour_status
      from public.package_activities pa
      where pa.booking_id = b.id
      order by pa.updated_at desc nulls last, pa.created_at desc nulls last
      limit 1
    ) activity on true
    left join lateral (
      select
        count(*)::integer as driver_count,
        jsonb_agg(jsonb_build_object(
          'id', driver.id,
          'name', coalesce(nullif(btrim(driver.full_name), ''),
            nullif(btrim(concat_ws(' ', driver.first_name, driver.last_name)), ''),
            'Unnamed driver')
        ) order by coalesce(driver.full_name, driver.first_name, driver.id::text)) as drivers,
        string_agg(concat_ws(' ', driver.full_name, driver.first_name, driver.last_name), ' ') as search_names
      from public.booking_drivers bd
      join public.profiles driver on driver.id = bd.driver_id
      where bd.booking_id = b.id and bd.status in ('accepted', 'completed')
    ) driver_info on true
    left join lateral (
      select dts.*
      from public.developer_test_sessions dts
      where dts.booking_id = b.id
        and dts.status = 'active'
        and dts.expires_at > now()
      order by dts.activated_at desc
      limit 1
    ) session_info on true
    left join public.profiles admin_profile on admin_profile.id = session_info.activated_by
  ), filtered as (
    select * from booking_rows br
    where (nullif(btrim(coalesce(p_search, '')), '') is null
      or br.search_text ilike '%' || btrim(p_search) || '%')
      and case p_booking_filter
        when 'upcoming' then br.scheduled_start_at > now()
          and br.row_booking_status not in ('cancelled', 'rejected', 'completed', 'expired')
        when 'active' then br.row_booking_status in (
          'confirmed', 'driver_accepted', 'driver_on_the_way', 'ongoing', 'on_tour'
        )
        when 'completed' then br.row_booking_status = 'completed'
        when 'cancelled' then br.row_booking_status in ('cancelled', 'rejected', 'expired')
        else true
      end
      and case p_test_filter
        when 'active' then br.row_session_active
        when 'inactive' then not br.row_session_active
        else true
      end
  )
  select
    f.row_booking_id, f.row_booking_reference, f.row_tourist_id,
    f.row_tourist_name, f.row_package_id, f.row_package_name,
    f.row_municipality, f.scheduled_start_at, f.estimated_end_at,
    f.row_booking_status, f.row_tour_status, f.row_drivers,
    f.row_required_drivers, f.row_driver_count, f.row_downpayment_ready,
    f.row_remaining_payment_ready, f.row_valid_tourist, f.row_drivers_ready,
    f.row_booking_state_valid, f.row_eligible, f.row_eligibility_reason,
    f.row_session_id, f.row_session_active, f.row_activated_by,
    f.row_activated_by_name, f.row_activated_at, f.row_expires_at,
    f.row_reason, f.row_bypass_scheduled_start,
    count(*) over ()
  from filtered f
  order by f.row_session_active desc,
    (f.scheduled_start_at >= now()) desc,
    f.scheduled_start_at asc nulls last,
    f.row_booking_id
  limit p_limit offset p_offset;
end;
$$;
revoke all on function public.administrator_list_testable_bookings(text, text, text, integer, integer)
  from public, anon;
grant execute on function public.administrator_list_testable_bookings(text, text, text, integer, integer)
  to authenticated;

create or replace function public.administrator_set_developer_testing(p_enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := now();
begin
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if p_enabled is null then
    raise exception 'DEVELOPER_TESTING_STATE_REQUIRED' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(20260930, 50000);
  insert into public.system_settings (singleton)
  values (true)
  on conflict (singleton) do nothing;

  update public.system_settings
  set developer_testing_enabled = p_enabled,
      developer_testing_updated_by = auth.uid(),
      developer_testing_updated_at = v_now
  where singleton;

  insert into public.audit_logs(actor_id, action, table_name, record_id, description)
  values (
    auth.uid(),
    case when p_enabled then 'DEVELOPER_TESTING_ENABLED' else 'DEVELOPER_TESTING_DISABLED' end,
    'system_settings',
    'developer_testing',
    jsonb_build_object(
      'enabled', p_enabled,
      'existing_sessions_preserved', true,
      'updated_at', v_now
    )::text
  );

  return jsonb_build_object(
    'enabled', p_enabled,
    'updated_by', auth.uid(),
    'updated_at', v_now
  );
end;
$$;
revoke all on function public.administrator_set_developer_testing(boolean)
  from public, anon;
grant execute on function public.administrator_set_developer_testing(boolean)
  to authenticated;

create or replace function public.administrator_activate_developer_test_session(
  p_booking_id uuid,
  p_reason text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking public.package_bookings;
  v_session public.developer_test_sessions;
  v_driver_count integer;
  v_now timestamptz := now();
begin
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 3 and 500 then
    raise exception 'DEVELOPER_TEST_REASON_REQUIRED' using errcode = '22023';
  end if;
  if p_expires_at is null or p_expires_at <= v_now then
    raise exception 'DEVELOPER_TEST_EXPIRY_MUST_BE_FUTURE' using errcode = '22023';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if not coalesce((
    select s.developer_testing_enabled from public.system_settings s
    where s.singleton limit 1
  ), false) then
    raise exception 'DEVELOPER_TESTING_DISABLED';
  end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
      in ('cancelled', 'rejected', 'completed', 'expired') then
    raise exception 'BOOKING_NOT_ELIGIBLE_FOR_DEVELOPER_TESTING';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_booking.tourist_id and p.role = 'tourist'
  ) then
    raise exception 'VALID_TOURIST_REQUIRED';
  end if;

  select count(*) into v_driver_count
  from public.booking_drivers bd
  join public.profiles p on p.id = bd.driver_id and p.role = 'driver'
  where bd.booking_id = p_booking_id and bd.status in ('accepted', 'completed');
  if v_driver_count < greatest(coalesce(v_booking.required_drivers, 1), 1) then
    raise exception 'DRIVER_SLOTS_NOT_FILLED';
  end if;

  update public.developer_test_sessions
  set status = 'expired', updated_at = v_now
  where booking_id = p_booking_id
    and status = 'active'
    and expires_at <= v_now;

  if exists (
    select 1 from public.developer_test_sessions dts
    where dts.booking_id = p_booking_id and dts.status = 'active'
  ) then
    raise exception 'DEVELOPER_TEST_SESSION_ALREADY_ACTIVE';
  end if;

  insert into public.developer_test_sessions(
    booking_id, activated_by, activated_at, expires_at, reason,
    bypass_scheduled_start, created_at, updated_at
  ) values (
    p_booking_id, auth.uid(), v_now, p_expires_at, btrim(p_reason),
    true, v_now, v_now
  ) returning * into v_session;

  insert into public.audit_logs(actor_id, action, table_name, record_id, description)
  values (
    auth.uid(), 'DEVELOPER_TEST_SESSION_ACTIVATED', 'developer_test_sessions',
    v_session.id::text,
    jsonb_build_object(
      'booking_id', p_booking_id,
      'expires_at', p_expires_at,
      'reason', btrim(p_reason),
      'bypass_scheduled_start', true
    )::text
  );

  return to_jsonb(v_session);
end;
$$;
revoke all on function public.administrator_activate_developer_test_session(uuid, text, timestamptz)
  from public, anon;
grant execute on function public.administrator_activate_developer_test_session(uuid, text, timestamptz)
  to authenticated;

create or replace function public.administrator_deactivate_developer_test_session(
  p_session_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.developer_test_sessions;
  v_now timestamptz := now();
begin
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if p_reason is not null and char_length(btrim(p_reason)) > 500 then
    raise exception 'DEACTIVATION_REASON_TOO_LONG' using errcode = '22023';
  end if;

  select * into v_session
  from public.developer_test_sessions
  where id = p_session_id
  for update;
  if not found then raise exception 'DEVELOPER_TEST_SESSION_NOT_FOUND'; end if;
  if v_session.status <> 'active' then
    raise exception 'DEVELOPER_TEST_SESSION_NOT_ACTIVE';
  end if;

  update public.developer_test_sessions
  set status = 'deactivated',
      deactivated_by = auth.uid(),
      deactivated_at = v_now,
      updated_at = v_now
  where id = p_session_id
  returning * into v_session;

  insert into public.audit_logs(actor_id, action, table_name, record_id, description)
  values (
    auth.uid(), 'DEVELOPER_TEST_SESSION_DEACTIVATED', 'developer_test_sessions',
    v_session.id::text,
    jsonb_build_object(
      'booking_id', v_session.booking_id,
      'activation_reason', v_session.reason,
      'deactivation_reason', nullif(btrim(coalesce(p_reason, '')), ''),
      'deactivated_at', v_now
    )::text
  );

  return to_jsonb(v_session);
end;
$$;
revoke all on function public.administrator_deactivate_developer_test_session(uuid, text)
  from public, anon;
grant execute on function public.administrator_deactivate_developer_test_session(uuid, text)
  to authenticated;

-- Integrate the new authorization into exactly one canonical guard. The old
-- debug wrapper remains the only path capable of bypassing payment/convoy gates.
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
  v_schedule_bypass boolean := false;
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

  v_schedule_bypass := public.developer_test_schedule_bypass_authorized(
    p_booking_id, v_driver_id
  );

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
    v_is_gated := false;
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

  if p_target_state = 'en_route_stop' then
    select count(*) into v_total_items from public.booking_itinerary_items where booking_id = p_booking_id;
    if v_new_stop_index < 0 or v_new_stop_index >= v_total_items then
      raise exception 'ITINERARY_STOP_OUT_OF_RANGE';
    end if;
  end if;

  if v_current = 'assigned' and p_target_state = 'en_route_pickup' then
    select count(*) into v_accepted_count
    from public.booking_drivers
    where booking_id = p_booking_id and status in ('accepted', 'completed');
    if v_accepted_count < greatest(coalesce(v_booking.required_drivers, 1), 1) then
      raise exception 'DRIVER_SLOTS_NOT_FILLED';
    end if;
    if not v_debug_bypass
       and not v_schedule_bypass
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

  if p_target_state = 'en_route_dropoff' then
    select count(*), count(*) filter (
      where lower(coalesce(spot_status, 'pending')) = 'completed'
    ) into v_total_items, v_completed_items
    from public.booking_itinerary_items
    where booking_id = p_booking_id;
    if v_total_items = 0 or v_completed_items < v_total_items then
      raise exception 'INCOMPLETE_ITINERARY';
    end if;
    if not v_debug_bypass and not public.is_booking_remaining_payment_satisfied(p_booking_id) then
      raise exception 'REMAINING_BALANCE_NOT_CONFIRMED';
    end if;
  end if;

  if v_is_gated and not v_debug_bypass then
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

  perform set_config('touristrike.journey_rpc', 'true', true);
  update public.booking_drivers
  set journey_state = p_target_state,
      current_stop_index = v_new_stop_index,
      state_updated_at = now(),
      status = case when p_target_state = 'completed' then 'completed' else status end,
      completed_at = case when p_target_state = 'completed'
        then coalesce(completed_at, now()) else completed_at end
  where booking_id = p_booking_id and driver_id = v_driver_id;
  perform set_config('touristrike.journey_rpc', 'false', true);

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
        when v_schedule_bypass and v_current = 'assigned' and p_target_state = 'en_route_pickup'
        then 'Administrator-authorized scheduled start override; all other validations enforced'
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
    'debug_bypass', v_debug_bypass,
    'scheduled_start_bypass', v_schedule_bypass
      and v_current = 'assigned' and p_target_state = 'en_route_pickup'
  );
end;
$$;
revoke all on function public.advance_driver_journey_state(uuid, text) from public, anon;
grant execute on function public.advance_driver_journey_state(uuid, text) to authenticated;

commit;
