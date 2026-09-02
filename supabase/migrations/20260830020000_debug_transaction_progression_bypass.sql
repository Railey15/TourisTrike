-- DEBUG transaction-progression RPCs for explicitly allowlisted disposable
-- bookings. These functions preserve real booking, itinerary, activity,
-- assignment, realtime, and audit writes while bypassing only progression
-- gates. They never create, confirm, or modify payment records/allocations.

begin;

create or replace function public.debug_test_driver_assignment(
  p_booking_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_assignment_id uuid;
  v_booking_status text;
begin
  if v_driver_id is null then raise exception 'UNAUTHENTICATED'; end if;

  if not exists (
    select 1 from public.developer_test_bookings dtb
    where dtb.booking_id = p_booking_id and dtb.enabled
  ) then
    raise exception 'TEST_BOOKING_NOT_REGISTERED';
  end if;

  select lower(coalesce(pb.booking_status, pb.status, ''))
  into v_booking_status
  from public.package_bookings pb
  where pb.id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking_status in ('cancelled', 'rejected') then
    raise exception 'CANCELLED_BOOKING_CANNOT_ADVANCE';
  end if;

  select bd.id into v_assignment_id
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id
    and bd.driver_id = v_driver_id
    and bd.status in ('accepted', 'completed')
  for update;
  if not found then raise exception 'NOT_TEST_BOOKING_DRIVER'; end if;

  return v_assignment_id;
end;
$$;

revoke all on function public.debug_test_driver_assignment(uuid)
  from public, anon, authenticated;

create or replace function public.debug_advance_driver_journey_state(
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
  v_assignment_id uuid;
  v_current text;
  v_stop_index integer;
  v_new_stop_index integer;
  v_total_items integer;
  v_slowest_state text;
  v_legacy_status text;
  v_activity_id uuid;
  v_all_completed boolean;
begin
  v_assignment_id := public.debug_test_driver_assignment(p_booking_id);

  if public.journey_state_order(p_target_state) is null then
    raise exception 'INVALID_STATE: %', p_target_state;
  end if;

  select bd.journey_state, bd.current_stop_index
  into v_current, v_stop_index
  from public.booking_drivers bd
  where bd.id = v_assignment_id
  for update;

  if v_current = p_target_state then
    return jsonb_build_object(
      'success', true, 'no_op', true, 'debug_bypass', true,
      'journey_state', v_current, 'current_stop_index', v_stop_index
    );
  end if;

  select count(*) into v_total_items
  from public.booking_itinerary_items
  where booking_id = p_booking_id;

  -- The screen normally walks the production sequence. This debug endpoint is
  -- intentionally also able to recover a stale test row by moving directly to
  -- the requested state; no schedule, payment, convoy, timer, or prior-state
  -- gate is evaluated.
  v_new_stop_index := greatest(coalesce(v_stop_index, 0), 0);
  if p_target_state = 'en_route_stop' and v_current = 'stop_done' then
    v_new_stop_index := least(v_new_stop_index + 1, greatest(v_total_items - 1, 0));
  elsif p_target_state = 'completed' then
    v_new_stop_index := v_total_items;
  end if;

  update public.booking_drivers
  set status = case when status = 'completed' then 'accepted' else status end,
      journey_state = p_target_state,
      current_stop_index = v_new_stop_index,
      state_updated_at = now(),
      completed_at = case when p_target_state = 'completed' then completed_at else null end
  where id = v_assignment_id;

  select bool_and(bd.journey_state = 'completed')
  into v_all_completed
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id
    and bd.status in ('accepted', 'completed');

  select (array_agg(
    bd.journey_state
    order by public.journey_state_order(bd.journey_state), bd.current_stop_index
  ))[1]
  into v_slowest_state
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id
    and bd.status in ('accepted', 'completed');

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

  select pa.id into v_activity_id
  from public.package_activities pa
  where pa.booking_id = p_booking_id
  limit 1;

  perform set_config('touristrike.validated_transition', 'true', true);
  if v_activity_id is not null then
    update public.package_activities
    set tour_status = case when coalesce(v_all_completed, false)
          then 'completed' else v_legacy_status end,
        status = case
          when coalesce(v_all_completed, false) then 'completed'
          when v_legacy_status = 'driver_accepted' then 'accepted'
          else 'ongoing'
        end,
        current_spot_index = greatest(v_new_stop_index, current_spot_index),
        dropped_off_at = case when coalesce(v_all_completed, false)
          then coalesce(dropped_off_at, now()) else dropped_off_at end,
        updated_at = now()
    where id = v_activity_id;

    insert into public.trip_status_logs
      (activity_id, booking_id, driver_id, status, previous_state, new_state,
       spot_index, logged_at, notes)
    values
      (v_activity_id, p_booking_id, v_driver_id, v_legacy_status, v_current,
       p_target_state, v_new_stop_index, now(),
       'DEBUG allowlisted journey transition; progression validations bypassed');
  end if;

  update public.package_bookings
  set booking_status = case
        when coalesce(v_all_completed, false) then 'completed'
        when v_legacy_status in ('driver_accepted', 'driver_en_route', 'driver_arrived')
          then 'driver_on_the_way'
        else 'on_tour'
      end,
      status = case when coalesce(v_all_completed, false) then 'completed' else status end,
      current_spot_index = greatest(v_new_stop_index, current_spot_index),
      completed_at = case when coalesce(v_all_completed, false)
        then coalesce(completed_at, now()) else completed_at end,
      updated_at = now()
  where id = p_booking_id;

  return jsonb_build_object(
    'success', true, 'no_op', false, 'debug_bypass', true,
    'journey_state', p_target_state,
    'current_stop_index', v_new_stop_index,
    'legacy_tour_status', v_legacy_status,
    'overall_completed', coalesce(v_all_completed, false),
    'payments_modified', false
  );
end;
$$;

revoke all on function public.debug_advance_driver_journey_state(uuid, text)
  from public, anon;
grant execute on function public.debug_advance_driver_journey_state(uuid, text)
  to authenticated;

create or replace function public.debug_mark_itinerary_stop_arrived(
  p_booking_id uuid,
  p_itinerary_item_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_booking_driver_id uuid;
  v_inserted integer;
  v_latitude double precision;
  v_longitude double precision;
begin
  v_booking_driver_id := public.debug_test_driver_assignment(p_booking_id);

  if not exists (
    select 1 from public.booking_itinerary_items bii
    where bii.id = p_itinerary_item_id and bii.booking_id = p_booking_id
  ) then raise exception 'ITINERARY_ITEM_NOT_FOUND'; end if;

  if exists (
    select 1 from public.booking_driver_arrivals bda
    where bda.booking_driver_id = v_booking_driver_id
      and bda.itinerary_item_id = p_itinerary_item_id
  ) then return false; end if;

  -- Preserve a real/simulated location when one exists, but deliberately do
  -- not require freshness or proximity for this allowlisted debug booking.
  select dll.latitude, dll.longitude into v_latitude, v_longitude
  from public.driver_live_locations dll
  where dll.driver_id = v_driver_id;

  insert into public.booking_driver_arrivals(
    booking_driver_id, itinerary_item_id, arrived_at, latitude, longitude
  ) values (
    v_booking_driver_id, p_itinerary_item_id, now(), v_latitude, v_longitude
  ) on conflict do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then return false; end if;

  update public.booking_itinerary_items
  set actual_arrival_time = coalesce(actual_arrival_time, now()),
      spot_status = case when spot_status = 'completed' then spot_status else 'at_spot' end,
      updated_at = now()
  where id = p_itinerary_item_id;

  return true;
end;
$$;

revoke all on function public.debug_mark_itinerary_stop_arrived(uuid, uuid)
  from public, anon;
grant execute on function public.debug_mark_itinerary_stop_arrived(uuid, uuid)
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
declare
  v_activity public.package_activities;
  v_booking_id uuid;
  v_total_items integer;
  v_active_slots integer;
  v_completed_slots integer;
begin
  select * into v_activity
  from public.package_activities
  where id = p_activity_id
  for update;
  if not found then raise exception 'ACTIVITY_NOT_FOUND'; end if;

  v_booking_id := v_activity.booking_id;
  perform public.debug_test_driver_assignment(v_booking_id);

  select count(*) into v_total_items
  from public.booking_itinerary_items
  where booking_id = v_booking_id;

  select count(*), count(*) filter (where journey_state = 'completed')
  into v_active_slots, v_completed_slots
  from public.booking_drivers
  where booking_id = v_booking_id and status in ('accepted', 'completed');

  if v_active_slots = 0 or v_completed_slots < v_active_slots then
    return jsonb_build_object(
      'success', true, 'debug_bypass', true, 'overall_completed', false,
      'completed_slots', v_completed_slots, 'required_slots', v_active_slots,
      'payments_modified', false
    );
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
  where id = v_booking_id;

  update public.booking_drivers
  set status = 'completed', completed_at = coalesce(completed_at, now())
  where booking_id = v_booking_id and journey_state = 'completed';

  return jsonb_build_object(
    'success', true, 'debug_bypass', true, 'overall_completed', true,
    'completed_slots', v_completed_slots, 'required_slots', v_active_slots,
    'payments_modified', false
  );
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
  v_activity_id uuid;
  v_total_items integer;
  v_active_slots integer;
  v_completed_slots integer;
  v_overall_completed boolean;
begin
  v_assignment_id := public.debug_test_driver_assignment(p_booking_id);

  update public.booking_itinerary_items
  set spot_status = 'completed',
      actual_arrival_time = coalesce(actual_arrival_time, now()),
      actual_departure_time = coalesce(actual_departure_time, now()),
      updated_at = now()
  where booking_id = p_booking_id;
  get diagnostics v_total_items = row_count;

  if p_force_all_assignments then
    update public.booking_drivers
    set journey_state = 'completed', status = 'completed',
        current_stop_index = v_total_items, state_updated_at = now(),
        completed_at = coalesce(completed_at, now())
    where booking_id = p_booking_id and status in ('accepted', 'completed');
  else
    update public.booking_drivers
    set journey_state = 'completed', status = 'completed',
        current_stop_index = v_total_items, state_updated_at = now(),
        completed_at = coalesce(completed_at, now())
    where id = v_assignment_id;
  end if;

  select count(*), count(*) filter (where journey_state = 'completed')
  into v_active_slots, v_completed_slots
  from public.booking_drivers
  where booking_id = p_booking_id and status in ('accepted', 'completed');
  v_overall_completed := v_active_slots > 0 and v_completed_slots = v_active_slots;

  select id into v_activity_id
  from public.package_activities where booking_id = p_booking_id limit 1;
  if v_activity_id is null then raise exception 'ACTIVITY_NOT_FOUND'; end if;

  perform set_config('touristrike.validated_transition', 'true', true);
  update public.package_activities
  set status = case when v_overall_completed then 'completed' else 'ongoing' end,
      tour_status = case when v_overall_completed then 'completed' else 'on_tour' end,
      current_spot_index = v_total_items,
      dropped_off_at = case when v_overall_completed
        then coalesce(dropped_off_at, now()) else dropped_off_at end,
      updated_at = now()
  where id = v_activity_id;

  update public.package_bookings
  set status = case when v_overall_completed then 'completed' else status end,
      booking_status = case when v_overall_completed then 'completed' else 'on_tour' end,
      current_spot_index = v_total_items,
      completed_at = case when v_overall_completed
        then coalesce(completed_at, now()) else completed_at end,
      updated_at = now()
  where id = p_booking_id;

  insert into public.trip_status_logs
    (activity_id, booking_id, driver_id, status, previous_state, new_state,
     spot_index, logged_at, notes)
  values
    (v_activity_id, p_booking_id, v_driver_id,
     case when v_overall_completed then 'completed' else 'on_tour' end,
     null, 'completed', v_total_items, now(),
     case when p_force_all_assignments
       then 'DEBUG force-completed all allowlisted convoy assignments'
       else 'DEBUG force-completed authenticated driver assignment' end);

  return jsonb_build_object(
    'success', true, 'debug_bypass', true,
    'forced_all_assignments', p_force_all_assignments,
    'overall_completed', v_overall_completed,
    'completed_slots', v_completed_slots, 'active_slots', v_active_slots,
    'itinerary_items_completed', v_total_items,
    'payments_modified', false
  );
end;
$$;

revoke all on function public.debug_force_complete_test_trip(uuid, boolean)
  from public, anon;
grant execute on function public.debug_force_complete_test_trip(uuid, boolean)
  to authenticated;

commit;
