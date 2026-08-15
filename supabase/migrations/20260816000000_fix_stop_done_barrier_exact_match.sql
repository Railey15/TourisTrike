-- ============================================================
-- Fix barrier deadlock at the last stop -> drop-off transition.
--
-- Root cause (confirmed live via booking_drivers): the `stop_done`
-- branch of advance_driver_journey_state checked
-- `bd.journey_state = 'stop_done'` (EXACT match) instead of an
-- "at least" comparison, unlike the `boarded` and `at_dropoff`
-- branches in this same function, which both correctly use
-- `journey_state_order(bd.journey_state) >= journey_state_order(...)`.
--
-- current_stop_index only increments on a transition INTO
-- 'en_route_stop' (heading to the NEXT stop) — it does NOT increment
-- on the 'stop_done' -> 'en_route_dropoff' transition (no next stop to
-- point at). So a driver who raced ahead past the last stop into
-- en_route_dropoff/at_dropoff/completed keeps the SAME
-- current_stop_index as a driver still sitting at stop_done on that
-- stop — but their journey_state is no longer literally 'stop_done',
-- so the exact-match check stopped counting them as "cleared" and
-- permanently blocked everyone else at that stop. Observed live:
-- both drivers at current_stop_index = 1, one at 'stop_done' (trying
-- to depart), one already at 'at_dropoff' (having raced ahead) —
-- BARRIER_NOT_MET forever.
--
-- The Dart client (ConvoyBarrierService._hasClearedStop,
-- lib/core/services/convoy_barrier_service.dart) already used the
-- correct "at least" comparison via journeyState.isAtLeast(stopDone) —
-- this migration brings the SQL in line with it. Byte-for-byte the
-- version from 20260805020000_convoy_phase2b_advance_state_rpc.sql,
-- with only the `stop_done` branch's condition changed.
-- ============================================================

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
  v_current text;
  v_stop_index integer;
  v_is_gated boolean := false;
  v_new_stop_index integer;
  v_all_cleared boolean;
  v_slowest_state text;
  v_legacy_status text;
  v_activity_id uuid;
begin
  if v_driver_id is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  if public.journey_state_order(p_target_state) is null then
    raise exception 'INVALID_STATE: %', p_target_state;
  end if;

  -- Single, well-known lock order (booking row, then own driver row) so
  -- two drivers advancing on the same booking concurrently can't deadlock.
  perform 1 from public.package_bookings where id = p_booking_id for update;

  select journey_state, current_stop_index
    into v_current, v_stop_index
  from public.booking_drivers
  where booking_id = p_booking_id
    and driver_id = v_driver_id
    and status = 'accepted'
  for update;

  if not found then
    raise exception 'NOT_IN_CONVOY';
  end if;

  -- Idempotent no-op — covers double-tap / client retry.
  if v_current = p_target_state then
    return jsonb_build_object(
      'success', true, 'no_op', true,
      'journey_state', v_current, 'current_stop_index', v_stop_index
    );
  end if;

  v_new_stop_index := v_stop_index;

  -- ── Transition table: every legal (current -> target) pair, and
  --    whether it's barrier-gated. Anything not listed here is rejected.
  if v_current = 'assigned' and p_target_state = 'en_route_pickup' then
    v_is_gated := false;
  elsif v_current = 'en_route_pickup' and p_target_state = 'at_pickup' then
    v_is_gated := false;
  elsif v_current = 'at_pickup' and p_target_state = 'boarded' then
    v_is_gated := false;
  elsif v_current = 'boarded' and p_target_state in ('en_route_stop', 'en_route_dropoff') then
    v_is_gated := true; -- "Depart from Pickup"
    if p_target_state = 'en_route_stop' then v_new_stop_index := 0; end if;
  elsif v_current = 'en_route_stop' and p_target_state = 'at_stop' then
    v_is_gated := false;
  elsif v_current = 'at_stop' and p_target_state = 'stop_done' then
    v_is_gated := false;
  elsif v_current = 'stop_done' and p_target_state in ('en_route_stop', 'en_route_dropoff') then
    v_is_gated := true; -- "Depart from Stop N"
    if p_target_state = 'en_route_stop' then v_new_stop_index := v_stop_index + 1; end if;
  elsif v_current = 'en_route_dropoff' and p_target_state = 'at_dropoff' then
    v_is_gated := false;
  elsif v_current = 'at_dropoff' and p_target_state = 'completed' then
    v_is_gated := true; -- "Complete Tour"
  else
    raise exception 'INVALID_TRANSITION: % -> %', v_current, p_target_state;
  end if;

  if v_is_gated then
    if v_current = 'boarded' then
      select bool_and(
               public.journey_state_order(bd.journey_state)
                 >= public.journey_state_order('boarded')
             )
        into v_all_cleared
      from public.booking_drivers bd
      where bd.booking_id = p_booking_id and bd.status = 'accepted';
    elsif v_current = 'stop_done' then
      -- FIX: was `bd.journey_state = 'stop_done'` (exact match), which
      -- stopped counting a driver as "cleared" the instant they moved
      -- past stop_done into en_route_dropoff/at_dropoff/completed while
      -- sitting on the same current_stop_index. Now mirrors the
      -- boarded/at_dropoff branches: order-based "at least", combined
      -- with the stop-index check (still needed since en_route_stop/
      -- at_stop/stop_done recur per stop). Mirrors
      -- ConvoyBarrierService._hasClearedStop in the Dart client exactly.
      select bool_and(
               bd.current_stop_index > v_stop_index
               or (bd.current_stop_index = v_stop_index
                   and public.journey_state_order(bd.journey_state)
                         >= public.journey_state_order('stop_done'))
             )
        into v_all_cleared
      from public.booking_drivers bd
      where bd.booking_id = p_booking_id and bd.status = 'accepted';
    elsif v_current = 'at_dropoff' then
      select bool_and(
               public.journey_state_order(bd.journey_state)
                 >= public.journey_state_order('at_dropoff')
             )
        into v_all_cleared
      from public.booking_drivers bd
      where bd.booking_id = p_booking_id and bd.status = 'accepted';
    end if;

    if not coalesce(v_all_cleared, false) then
      raise exception 'BARRIER_NOT_MET';
    end if;
  end if;

  update public.booking_drivers
  set journey_state = p_target_state,
      current_stop_index = v_new_stop_index
  where booking_id = p_booking_id and driver_id = v_driver_id;

  -- ── Legacy mirror write — derived from the SLOWEST driver in the
  -- convoy (Open Question 4). Re-read AFTER the update above so this
  -- reflects the caller's own just-committed change too. Mirrors
  -- ConvoyBarrierService.deriveOverallState in the Dart client — keep
  -- both in sync if the rule changes.
  select
    (array_agg(bd.journey_state
               order by public.journey_state_order(bd.journey_state)))[1]
    into v_slowest_state
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id and bd.status = 'accepted';

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
  from public.package_activities
  where booking_id = p_booking_id
  limit 1;

  -- package_activities.status / package_bookings.booking_status derivation
  -- mirrors TourisTrikeRepository._bookingStatusFromTourStatus exactly
  -- (lib/core/supabase/touristrike_repository.dart) — keep both in sync.
  if v_activity_id is not null then
    update public.package_activities
    set tour_status = v_legacy_status,
        status = case
          when v_legacy_status = 'completed' then 'completed'
          when v_legacy_status in ('driver_accepted') then 'accepted'
          else 'ongoing'
        end,
        current_spot_index = greatest(
          v_new_stop_index,
          coalesce((select current_spot_index from public.package_activities where id = v_activity_id), 0)
        ),
        updated_at = now()
    where id = v_activity_id;
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
      updated_at = now()
  where id = p_booking_id;

  return jsonb_build_object(
    'success', true,
    'no_op', false,
    'journey_state', p_target_state,
    'current_stop_index', v_new_stop_index,
    'legacy_tour_status', v_legacy_status
  );
end;
$$;

grant execute on function public.advance_driver_journey_state(uuid, text) to authenticated;
