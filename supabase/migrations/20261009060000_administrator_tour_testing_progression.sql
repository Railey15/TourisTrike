-- Administrator-only, booking-scoped tour testing. Existing timing RPCs keep
-- their behavior; the authorization helper now rejects every operational role.
begin;
create or replace function public.booking_test_admin_authorized(p_booking_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
    and public.is_system_administrator()
    and exists (select 1 from public.package_bookings b where b.id = p_booking_id);
$$;
revoke all on function public.booking_test_admin_authorized(uuid)
  from public, anon, authenticated;
create function public.booking_test_financially_safe(p_booking_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.package_bookings b
    where b.id = p_booking_id
      and lower(coalesce(b.booking_status,b.status,'')) not in
        ('cancelled','rejected','expired','completed','done')
      and b.cancelled_at is null and b.completed_at is null)
    and not exists (select 1 from public.payment_records p
      where p.booking_id = p_booking_id
        and p.provider_livemode is true)
    and not exists (select 1 from public.payout_records p
      where p.booking_id = p_booking_id
        and p.status in ('processing','paid'))
    and not exists (select 1 from public.payment_disputes p
      where p.booking_id = p_booking_id)
    and not exists (select 1 from public.refund_requests r
      where r.booking_id = p_booking_id
        and r.status in ('pending','approved','completed'));
$$;
revoke all on function public.booking_test_financially_safe(uuid)
  from public, anon, authenticated;
create or replace function public.booking_test_session_active(p_booking_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.booking_test_financially_safe(p_booking_id)
    and coalesce((select s.developer_testing_enabled
      from public.system_settings s where s.singleton),false)
    and exists (select 1 from public.developer_test_sessions d
      where d.booking_id = p_booking_id and d.status = 'active'
        and d.expires_at > now());
$$;
revoke all on function public.booking_test_session_active(uuid)
  from public, anon, authenticated;
-- Keep the existing audited implementations, adding a prerequisite before
-- they can authorize or delete a booking. The renamed versions have no API
-- privilege; only these administrator-gated entry points are callable.
alter function public.administrator_activate_developer_test_session(uuid,text,timestamptz)
  rename to administrator_activate_developer_test_session_legacy;
revoke all on function public.administrator_activate_developer_test_session_legacy(uuid,text,timestamptz)
  from public, anon, authenticated;
create function public.administrator_activate_developer_test_session(
  p_booking_id uuid,p_reason text,p_expires_at timestamptz
) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.booking_test_admin_authorized(p_booking_id) then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if not public.booking_test_financially_safe(p_booking_id) then
    raise exception 'BOOKING_HAS_PRODUCTION_FINANCIAL_HISTORY';
  end if;
  return public.administrator_activate_developer_test_session_legacy(
    p_booking_id,p_reason,p_expires_at);
end $$;
revoke all on function public.administrator_activate_developer_test_session(uuid,text,timestamptz)
  from public, anon;
grant execute on function public.administrator_activate_developer_test_session(uuid,text,timestamptz)
  to authenticated;
alter function public.administrator_reset_developer_test_trip(uuid)
  rename to administrator_reset_developer_test_trip_legacy;
revoke all on function public.administrator_reset_developer_test_trip_legacy(uuid)
  from public, anon, authenticated;
create function public.administrator_reset_developer_test_trip(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.booking_test_admin_authorized(p_booking_id) then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if not public.booking_test_session_active(p_booking_id) then
    raise exception 'ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED';
  end if;
  return public.administrator_reset_developer_test_trip_legacy(p_booking_id);
end $$;
revoke all on function public.administrator_reset_developer_test_trip(uuid)
  from public, anon;
grant execute on function public.administrator_reset_developer_test_trip(uuid)
  to authenticated;
alter function public.administrator_delete_test_booking(uuid)
  rename to administrator_delete_test_booking_legacy;
revoke all on function public.administrator_delete_test_booking_legacy(uuid)
  from public, anon, authenticated;
create function public.administrator_delete_test_booking(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.booking_test_admin_authorized(p_booking_id) then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if not public.booking_test_session_active(p_booking_id) then
    raise exception 'ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED';
  end if;
  return public.administrator_delete_test_booking_legacy(p_booking_id);
end $$;
revoke all on function public.administrator_delete_test_booking(uuid)
  from public, anon;
grant execute on function public.administrator_delete_test_booking(uuid)
  to authenticated;
-- Expose the same persisted milestones that control the actions, together with
-- payment eligibility and the actual audit trail. No financial row is changed.
create function public.administrator_get_booking_developer_state_v2(p_booking_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s jsonb; b public.package_bookings; v_count integer;
begin
  if not public.booking_test_admin_authorized(p_booking_id) then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  s := public.administrator_get_booking_developer_state(p_booking_id);
  select * into b from public.package_bookings where id = p_booking_id;
  select count(*) into v_count from public.booking_itinerary_items
    where booking_id = p_booking_id;
  return s || jsonb_build_object(
    'stop_count', v_count,
    'financially_safe', public.booking_test_financially_safe(p_booking_id),
    'accepted_driver_count', (select count(*) from public.booking_drivers d
      where d.booking_id = p_booking_id and d.status = 'accepted'),
    'required_driver_count', greatest(coalesce(b.required_drivers,1),1),
    'convoy_aligned', not exists (select 1 from public.booking_drivers d
      where d.booking_id = p_booking_id and d.status = 'accepted'
        and (d.journey_state is distinct from (s->>'journey_state')
          or d.current_stop_index is distinct from
            (s->>'current_stop_index')::integer)),
    'downpayment_ready', public.is_booking_downpayment_confirmed(p_booking_id),
    'remaining_payment_ready', public.is_booking_remaining_payment_satisfied(p_booking_id),
    'dropoff_payment_ready', public.is_booking_dropoff_payment_satisfied(p_booking_id),
    'current_stop_completed', exists (
      select 1 from public.booking_itinerary_items i
      where i.id = (s->>'current_stop_id')::uuid
        and i.spot_status = 'completed'),
    'current_stop_departed', exists (
      select 1 from public.booking_itinerary_items i
      where i.id = (s->>'current_stop_id')::uuid
        and i.actual_departure_time is not null),
    'all_stops_completed', v_count > 0 and not exists (
      select 1 from public.booking_itinerary_items i
      where i.booking_id = p_booking_id
        and (i.spot_status <> 'completed' or i.actual_departure_time is null)),
    'active_waiting_charge', exists (
      select 1 from public.booking_stop_waiting_charges c
      where c.booking_id = p_booking_id and c.status = 'active'),
    'active_stop_waiting_ledger', exists (
      select 1 from public.booking_stop_waiting_charges c
      where c.booking_id = p_booking_id and c.status = 'active'
        and c.itinerary_item_id = (s->>'current_stop_id')::uuid),
    'previous_stop_available', (s->>'current_stop_index')::integer > 0
      and not exists (
        select 1 from public.booking_stop_waiting_charges c
        where c.itinerary_item_id = (
          select item.id from public.booking_itinerary_items item
          where item.booking_id = p_booking_id
          order by coalesce(item.order_number,2147483647),
            coalesce(item.destination_order,2147483647),
            item.arrival_time nulls last,item.created_at,item.id
          offset greatest((s->>'current_stop_index')::integer - 1,0)
          limit 1)
          and coalesce(c.additional_amount,0) > 0)
      and not exists (select 1 from public.payment_records p
        where p.booking_id = p_booking_id
          and p.payment_stage = 'remaining_balance'
          and p.status = 'confirmed'),
    'recent_test_actions', coalesce((
      select jsonb_agg(jsonb_build_object('action', x.action,
        'actor_id', x.actor_id, 'created_at', x.created_at,
        'description', x.description) order by x.created_at desc)
      from (select log.action, log.actor_id, log.created_at, log.description
        from public.audit_logs log
        where log.table_name = 'package_bookings'
          and log.record_id = p_booking_id::text
        order by log.created_at desc limit 10) x), '[]'::jsonb),
    'booking_completed', b.completed_at is not null
  );
end $$;
revoke all on function public.administrator_get_booking_developer_state_v2(uuid)
  from public, anon;
grant execute on function public.administrator_get_booking_developer_state_v2(uuid)
  to authenticated;
-- The old RPC permitted payment and pickup bypasses and could not navigate
-- from the final stop to drop-off. Retire its authenticated endpoint.
revoke all on function public.administrator_progress_booking_test(uuid, text)
  from public, anon, authenticated;
create function public.administrator_progress_booking_test_v2(
  p_booking_id uuid, p_action text, p_expected_state text,
  p_expected_stop_index integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  b public.package_bookings;
  d public.booking_drivers;
  i public.booking_itinerary_items;
  target public.booking_itinerary_items;
  v_activity uuid;
  v_count integer;
  v_driver_count integer;
  v_new_index integer;
  v_new_state text;
  v_tour_status text;
  v_previous jsonb;
  v_finalization jsonb;
  v_old_journey text := coalesce(current_setting('touristrike.journey_rpc',true),'');
  v_old_gps text := coalesce(current_setting('touristrike.gps_transition_verified',true),'');
  v_old_validated text := coalesce(current_setting('touristrike.validated_transition',true),'');
  v_old_reason text := coalesce(current_setting('touristrike.manual_lifecycle_reason',true),'');
  v_old_arrival text := coalesce(current_setting('touristrike.administrator_arrival_simulation',true),'');
begin
  if not public.booking_test_admin_authorized(p_booking_id) then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if not public.booking_test_session_active(p_booking_id) then
    raise exception 'ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED';
  end if;
  if p_action not in ('force_start','simulate_arrival','complete_stop',
      'simulate_departure','next_stop','previous_stop','force_complete') then
    raise exception 'INVALID_BOOKING_TEST_ACTION';
  end if;
  select * into b from public.package_bookings
    where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if lower(coalesce(b.booking_status,b.status,'')) in
      ('cancelled','rejected','expired','completed','done')
      or b.cancelled_at is not null or b.completed_at is not null then
    raise exception 'TERMINAL_BOOKING_CANNOT_BE_TESTED';
  end if;
  -- A test session is an explicit booking authorization. Reject bookings with
  -- real provider receipts or irreversible financial records even if a session
  -- was mistakenly activated for one.
  if exists (select 1 from public.payment_records p
      where p.booking_id = p_booking_id
        and p.provider_livemode is true)
    or exists (select 1 from public.payout_records p
      where p.booking_id = p_booking_id
        and p.status in ('processing','paid'))
    or exists (select 1 from public.payment_disputes p
      where p.booking_id = p_booking_id)
    or exists (select 1 from public.refund_requests r
      where r.booking_id = p_booking_id
        and r.status in ('pending','approved','completed')) then
    raise exception 'BOOKING_HAS_PRODUCTION_FINANCIAL_HISTORY';
  end if;
  select * into d from public.booking_drivers
    where booking_id = p_booking_id and status = 'accepted'
    order by public.journey_state_order(journey_state), current_stop_index
    limit 1 for update;
  if not found then raise exception 'ACCEPTED_DRIVER_REQUIRED'; end if;
  select count(*) into v_driver_count from public.booking_drivers
    where booking_id = p_booking_id and status = 'accepted';
  if v_driver_count < greatest(coalesce(b.required_drivers,1),1) then
    raise exception 'DRIVER_SLOTS_NOT_FILLED';
  end if;
  if exists (select 1 from public.booking_drivers bd
      where bd.booking_id = p_booking_id and bd.status = 'accepted'
        and (bd.journey_state is distinct from d.journey_state
          or bd.current_stop_index is distinct from d.current_stop_index)) then
    raise exception 'CONVOY_STATE_NOT_ALIGNED';
  end if;
  if d.journey_state is distinct from p_expected_state
      or d.current_stop_index is distinct from p_expected_stop_index then
    raise exception 'STALE_BOOKING_TEST_STATE';
  end if;
  select count(*) into v_count from public.booking_itinerary_items
    where booking_id = p_booking_id;
  if v_count = 0 then raise exception 'ITINERARY_REQUIRED'; end if;
  select * into i from public.booking_itinerary_items
    where booking_id = p_booking_id
    order by coalesce(order_number,2147483647),
      coalesce(destination_order,2147483647), arrival_time nulls last,
      created_at,id offset greatest(d.current_stop_index,0) limit 1;
  if not found then raise exception 'ITINERARY_ITEM_NOT_FOUND'; end if;
  select id into v_activity from public.package_activities
    where booking_id = p_booking_id
    order by updated_at desc nulls last, created_at desc limit 1;
  if v_activity is null then raise exception 'ACTIVITY_NOT_FOUND'; end if;
  v_previous := jsonb_build_object('booking_status',b.booking_status,
    'journey_state',d.journey_state,'stop_index',d.current_stop_index,
    'itinerary_item_id',i.id,'spot_status',i.spot_status);
  v_new_state := d.journey_state;
  v_new_index := d.current_stop_index;
  perform set_config('touristrike.journey_rpc','true',true);
  perform set_config('touristrike.gps_transition_verified','true',true);
  perform set_config('touristrike.validated_transition','true',true);
  perform set_config('touristrike.manual_lifecycle_reason',
    'Administrator booking-scoped test progression',true);

  if p_action = 'force_start' then
    if d.journey_state not in ('assigned','en_route_pickup','at_pickup','boarded') then
      raise exception 'FORCE_START_NOT_ALLOWED_FROM_CURRENT_STATE';
    end if;
    if not public.is_booking_downpayment_confirmed(p_booking_id) then
      raise exception 'DOWNPAYMENT_NOT_CONFIRMED';
    end if;
    v_new_state := 'en_route_stop';
    v_new_index := 0;
    v_tour_status := 'en_route_to_spot';
  elsif p_action = 'simulate_arrival' then
    perform set_config('touristrike.administrator_arrival_simulation','true',true);
    if d.journey_state = 'en_route_dropoff' then
      if not public.is_booking_dropoff_payment_satisfied(p_booking_id) then
        raise exception 'REMAINING_BALANCE_NOT_CONFIRMED';
      end if;
      v_new_state := 'at_dropoff';
      v_tour_status := 'ready_to_complete';
    elsif d.journey_state = 'en_route_stop' then
      insert into public.booking_driver_arrivals(
        booking_driver_id,itinerary_item_id,arrived_at,latitude,longitude)
      select bd.id,i.id,clock_timestamp(),loc.latitude,loc.longitude
        from public.booking_drivers bd
        left join public.driver_live_locations loc on loc.driver_id = bd.driver_id
        where bd.booking_id = p_booking_id and bd.status = 'accepted'
      on conflict (booking_driver_id,itinerary_item_id) do nothing;
      update public.booking_itinerary_items
        set actual_arrival_time = clock_timestamp(),spot_status = 'at_spot'
        where id = i.id and actual_arrival_time is null;
      v_new_state := 'at_stop';
      v_tour_status := 'at_spot';
    else
      raise exception 'ARRIVAL_REQUIRES_EN_ROUTE_STOP';
    end if;
  elsif p_action = 'complete_stop' then
    if d.journey_state <> 'at_stop' or i.actual_arrival_time is null then
      raise exception 'COMPLETE_REQUIRES_ARRIVAL';
    end if;
    update public.booking_itinerary_items set spot_status = 'completed'
      where id = i.id and spot_status = 'at_spot';
    if not found then raise exception 'STOP_NOT_READY_TO_COMPLETE'; end if;
    v_tour_status := 'at_spot';
  elsif p_action = 'simulate_departure' then
    if d.journey_state <> 'at_stop' then
      raise exception 'DEPARTURE_REQUIRES_AT_STOP';
    end if;
    if i.spot_status <> 'completed' then
      raise exception 'DEPARTURE_REQUIRES_COMPLETED_STOP';
    end if;
    update public.booking_driver_arrivals
      set departed_at = coalesce(departed_at,clock_timestamp())
      where itinerary_item_id = i.id and booking_driver_id in (
        select id from public.booking_drivers
        where booking_id = p_booking_id and status = 'accepted');
    update public.booking_itinerary_items
      set actual_departure_time = coalesce(actual_departure_time,clock_timestamp())
      where id = i.id;
    v_new_state := 'stop_done';
    v_tour_status := 'on_tour';
  elsif p_action = 'next_stop' then
    if d.journey_state <> 'stop_done' or i.spot_status <> 'completed'
        or i.actual_departure_time is null then
      raise exception 'NEXT_STOP_REQUIRES_COMPLETED_STOP';
    end if;
    if d.current_stop_index + 1 < v_count then
      v_new_index := d.current_stop_index + 1;
      v_new_state := 'en_route_stop';
      v_tour_status := 'en_route_to_spot';
    else
      if not public.is_booking_dropoff_payment_satisfied(p_booking_id)
          or not public.is_booking_remaining_payment_satisfied(p_booking_id) then
        raise exception 'REMAINING_BALANCE_NOT_CONFIRMED';
      end if;
      v_new_state := 'en_route_dropoff';
      v_tour_status := 'en_route_to_dropoff';
    end if;
  elsif p_action = 'previous_stop' then
    if d.current_stop_index <= 0 then raise exception 'ALREADY_AT_FIRST_STOP'; end if;
    if d.journey_state <> 'en_route_stop' or i.actual_arrival_time is not null then
      raise exception 'PREVIOUS_STOP_NOT_SAFE_FROM_CURRENT_STATE';
    end if;
    v_new_index := d.current_stop_index - 1;
    select * into target from public.booking_itinerary_items
      where booking_id = p_booking_id
      order by coalesce(order_number,2147483647),
        coalesce(destination_order,2147483647),arrival_time nulls last,
        created_at,id offset v_new_index limit 1;
    if exists (select 1 from public.booking_stop_waiting_charges c
        where c.itinerary_item_id = target.id
          and coalesce(c.additional_amount,0) > 0)
      or exists (select 1 from public.payment_records p
        where p.booking_id = p_booking_id
          and p.payment_stage = 'remaining_balance'
          and p.status = 'confirmed') then
      raise exception 'PREVIOUS_STOP_BLOCKED_BY_FINANCIAL_HISTORY';
    end if;
    delete from public.booking_stop_waiting_charges c
      where c.itinerary_item_id = target.id
        and coalesce(c.additional_amount,0) = 0;
    delete from public.booking_driver_arrivals a
      where a.itinerary_item_id = target.id;
    update public.booking_itinerary_items
      set actual_arrival_time = null, actual_departure_time = null,
        spot_status = 'pending' where id = target.id;
    v_new_state := 'en_route_stop';
    v_tour_status := 'en_route_to_spot';
  elsif p_action = 'force_complete' then
    if d.journey_state <> 'at_dropoff' then
      raise exception 'DROPOFF_REQUIRED_BEFORE_COMPLETION';
    end if;
    if exists (select 1 from public.booking_itinerary_items item
        where item.booking_id = p_booking_id
          and (item.spot_status <> 'completed'
            or item.actual_departure_time is null)) then
      raise exception 'FORCE_COMPLETE_REQUIRES_COMPLETED_ITINERARY';
    end if;
    if exists (select 1 from public.booking_stop_waiting_charges c
        where c.booking_id = p_booking_id and c.status = 'active') then
      raise exception 'FORCE_COMPLETE_REQUIRES_NO_ACTIVE_WAITING_LEDGER';
    end if;
    if not public.is_booking_dropoff_payment_satisfied(p_booking_id)
        or not public.is_booking_remaining_payment_satisfied(p_booking_id) then
      raise exception 'FORCE_COMPLETE_REQUIRES_SETTLED_PAYMENT';
    end if;
    v_new_state := 'completed';
    v_tour_status := 'ready_to_complete';
  end if;

  if v_new_state is distinct from d.journey_state
      or v_new_index is distinct from d.current_stop_index then
    update public.booking_drivers set journey_state = v_new_state,
      current_stop_index = v_new_index, state_updated_at = clock_timestamp(),
      status = case when v_new_state = 'completed' then 'completed' else status end,
      completed_at = case when v_new_state = 'completed'
        then coalesce(completed_at,clock_timestamp()) else completed_at end
      where booking_id = p_booking_id and status = 'accepted';
  end if;
  update public.package_bookings set
    booking_status = case when v_new_state = 'completed'
      then booking_status else 'on_tour' end,
    current_spot_index = v_new_index,
    updated_at = clock_timestamp() where id = p_booking_id;
  update public.package_activities set
    status = case when v_new_state = 'completed' then status else 'ongoing' end,
    tour_status = v_tour_status,
    current_spot_index = v_new_index,
    dropped_off_at = case when v_new_state = 'completed'
      then coalesce(dropped_off_at,clock_timestamp()) else dropped_off_at end,
    updated_at = clock_timestamp() where id = v_activity;
  if v_new_state = 'completed' then
    v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);
    if not coalesce((v_finalization->>'overall_completed')::boolean,false) then
      raise exception 'BOOKING_COMPLETION_VALIDATION_FAILED';
    end if;
  end if;
  insert into public.trip_status_logs(activity_id,booking_id,status,
    spot_index,logged_at,notes)
  values(v_activity,p_booking_id,'developer_test_' || p_action,
    v_new_index,clock_timestamp(),jsonb_build_object(
      'actor_id',v_actor,'previous',v_previous)::text);
  insert into public.audit_logs(actor_id,action,table_name,record_id,description)
  values(v_actor,p_action,'package_bookings',p_booking_id::text,
    jsonb_build_object('booking_id',p_booking_id,'previous',v_previous,
      'new',jsonb_build_object('journey_state',v_new_state,
        'current_stop_index',v_new_index,'tour_status',v_tour_status))::text);
  perform set_config('touristrike.journey_rpc',v_old_journey,true);
  perform set_config('touristrike.gps_transition_verified',v_old_gps,true);
  perform set_config('touristrike.validated_transition',v_old_validated,true);
  perform set_config('touristrike.manual_lifecycle_reason',v_old_reason,true);
  perform set_config('touristrike.administrator_arrival_simulation',v_old_arrival,true);
  return public.administrator_get_booking_developer_state_v2(p_booking_id);
end $$;
revoke all on function public.administrator_progress_booking_test_v2(uuid,text,text,integer)
  from public, anon;
grant execute on function public.administrator_progress_booking_test_v2(uuid,text,text,integer)
  to authenticated;
-- The production GPS trigger has no path for administrator simulations. The
-- exception below is effective only inside the authenticated arrival RPC for
-- an active, financially safe booking test session. Ordinary Driver arrivals
-- retain the existing fresh-location and radius checks verbatim.
create or replace function public.guard_live_driver_journey_proximity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_target_latitude double precision;
  v_target_longitude double precision;
  v_driver_latitude double precision;
  v_driver_longitude double precision;
  v_location_updated_at timestamptz;
  v_distance_meters double precision;
  v_allowed_radius_meters constant double precision := public.driver_arrival_radius_meters();
begin
  if new.journey_state is not distinct from old.journey_state then
    return new;
  end if;
  if new.journey_state in ('at_stop','at_dropoff')
     and current_setting('touristrike.administrator_arrival_simulation',true) = 'true'
     and public.booking_test_admin_authorized(new.booking_id)
     and public.booking_test_session_active(new.booking_id) then
    return new;
  end if;
  if auth.uid() = new.driver_id and current_setting('touristrike.arrival_fallback_verified', true) = 'true' then
    return new;
  end if;
  if public.is_developer_test_booking(new.booking_id)
     and auth.uid() = new.driver_id
     and current_setting('touristrike.debug_progression_bypass', true) = 'true' then
    return new;
  end if;

  if new.journey_state = 'at_pickup' then
    select pb.pickup_latitude, pb.pickup_longitude
    into v_target_latitude, v_target_longitude
    from public.package_bookings pb where pb.id = new.booking_id;
  elsif new.journey_state = 'at_stop' then
    select ordered.latitude, ordered.longitude
    into v_target_latitude, v_target_longitude
    from (
      select bii.latitude, bii.longitude,
        (row_number() over (
          order by coalesce(bii.order_number, 2147483647),
                   coalesce(bii.destination_order, 2147483647),
                   bii.arrival_time nulls last, bii.created_at, bii.id
        ))::integer - 1 as stop_index
      from public.booking_itinerary_items bii
      where bii.booking_id = new.booking_id
    ) ordered
    where ordered.stop_index = new.current_stop_index;
  elsif new.journey_state = 'at_dropoff' then
    select pb.dropoff_latitude, pb.dropoff_longitude
    into v_target_latitude, v_target_longitude
    from public.package_bookings pb where pb.id = new.booking_id;
  else
    return new;
  end if;

  if v_target_latitude is null or v_target_longitude is null then
    raise exception 'TARGET_LOCATION_REQUIRED';
  end if;

  select dll.latitude, dll.longitude, dll.updated_at
  into v_driver_latitude, v_driver_longitude, v_location_updated_at
  from public.driver_live_locations dll
  where dll.driver_id = new.driver_id;
  if not found or v_location_updated_at is null
     or v_location_updated_at < now() - interval '2 minutes' then
    raise exception 'DRIVER_LOCATION_STALE';
  end if;

  v_distance_meters := 6371000 * 2 * asin(sqrt(least(1, greatest(0,
    power(sin(radians(v_driver_latitude - v_target_latitude) / 2), 2)
    + cos(radians(v_target_latitude)) * cos(radians(v_driver_latitude))
      * power(sin(radians(v_driver_longitude - v_target_longitude) / 2), 2)
  ))));
  if v_distance_meters > v_allowed_radius_meters then
    raise exception 'NOT_WITHIN_ARRIVAL_RADIUS: % m > % m',
      round(v_distance_meters), round(v_allowed_radius_meters);
  end if;
  return new;
end $$;
revoke all on function public.guard_live_driver_journey_proximity()
  from public, anon, authenticated;
notify pgrst, 'reload schema';
commit;
