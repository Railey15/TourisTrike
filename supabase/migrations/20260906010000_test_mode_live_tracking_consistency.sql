-- Reassert the matching debug wrapper and canonical transition together.
-- Debug adds operational bypass; automatic arrivals still use real proximity.
begin;

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
  -- Only the allowlisted debug RPC can bypass this payment check.
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

create or replace function public.debug_advance_driver_journey_state(
  p_booking_id uuid,
  p_target_state text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_result jsonb;
begin
  perform public.debug_test_driver_assignment(p_booking_id);
  perform set_config('touristrike.debug_progression_bypass', 'true', true);
  v_result := public.advance_driver_journey_state(p_booking_id, p_target_state);
  perform set_config('touristrike.debug_progression_bypass', 'false', true);
  return v_result;
end;
$$;

create or replace function public.guard_live_driver_journey_proximity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_latitude double precision;
  v_target_longitude double precision;
  v_driver_latitude double precision;
  v_driver_longitude double precision;
  v_location_updated_at timestamptz;
  v_distance_meters double precision;
  v_allowed_radius_meters constant double precision := 150;
begin
  if new.journey_state is not distinct from old.journey_state then
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
end;
$$;

revoke all on function public.debug_advance_driver_journey_state(uuid,text) from public, anon;
grant execute on function public.debug_advance_driver_journey_state(uuid,text) to authenticated;
commit;
