-- ============================================================
-- Convoy Sync — Phase 2b: server-side barrier enforcement.
--
-- RLS note (Adjustment 1): booking_drivers already has
-- `for select using (true)` (20260520160000_group_booking_and_live_tracking.sql:67-69,
-- reaffirmed in 20260520180000_accept_booking_rpc_fix.sql:13-18) and so
-- does driver_live_locations (same file, lines 79-82). Every authenticated
-- driver can already read every driver's roster row and live location for
-- any booking — no RLS change needed here.
--
-- This migration adds:
--   1. journey_state_order() — tiny helper mirroring
--      ConvoyJourneyState.order in lib/core/models/convoy_state.dart.
--      Keep both in sync if states are ever added/reordered.
--   2. advance_driver_journey_state() — the ONLY sanctioned way to move
--      a driver's journey_state forward. Validates the transition is
--      legal, enforces the barrier server-side (never trusts the
--      client's belief that a gate is open), and is race-safe:
--      row-locks package_bookings first (single well-known lock order
--      per booking, so two drivers on the same booking can't deadlock
--      against each other) then the caller's own booking_drivers row.
--      Idempotent: re-requesting the state you're already in is a no-op
--      success, not an error (covers double-tap / retry).
--   3. A one-time backfill of booking_drivers for any package_bookings
--      that have assigned_driver_id set but no matching booking_drivers
--      row — i.e. bookings accepted before booking_drivers existed, or
--      through an older accept RPC that never wrote it. Idempotent
--      (ON CONFLICT DO NOTHING), safe to re-run.
-- ============================================================

-- ── 1. Pipeline order helper ──────────────────────────────────
create or replace function public.journey_state_order(p_state text)
returns integer
language sql
immutable
as $$
  select array_position(
    array['assigned', 'en_route_pickup', 'at_pickup', 'boarded',
          'en_route_stop', 'at_stop', 'stop_done',
          'en_route_dropoff', 'at_dropoff', 'completed'],
    p_state
  );
$$;

-- ── 2. Backfill booking_drivers for pre-existing single-driver bookings ──
-- Best-effort reverse mapping from the legacy package_activities.tour_status
-- vocabulary back into a journey_state, so a booking already mid-tour
-- doesn't get reset to square one. 'on_tour' is a lossy guess (the legacy
-- vocabulary had no per-stop granularity) — documented, not perfect.
insert into public.booking_drivers
  (booking_id, driver_id, status, accepted_at, journey_state, current_stop_index)
select
  pb.id,
  pb.assigned_driver_id,
  'accepted',
  coalesce(pb.accepted_at, pb.created_at, now()),
  case coalesce(pa.tour_status, 'driver_accepted')
    when 'driver_accepted' then 'assigned'
    when 'driver_en_route' then 'en_route_pickup'
    when 'driver_arrived' then 'at_pickup'
    when 'picked_up' then 'boarded'
    when 'en_route_to_spot' then 'en_route_stop'
    when 'at_spot' then 'at_stop'
    when 'on_tour' then 'stop_done'
    when 'en_route_to_dropoff' then 'en_route_dropoff'
    when 'ready_to_complete' then 'at_dropoff'
    when 'completed' then 'completed'
    when 'dropped_off' then 'completed'
    else 'assigned'
  end,
  coalesce(pa.current_spot_index, 0)
from public.package_bookings pb
left join public.package_activities pa on pa.booking_id = pb.id
where pb.assigned_driver_id is not null
  and not exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = pb.id and bd.driver_id = pb.assigned_driver_id
  )
on conflict (booking_id, driver_id) do nothing;

-- ── 3. advance_driver_journey_state RPC ──────────────────────
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
      -- Stop-index-aware: a driver already past stop N (working on a
      -- later stop) counts as cleared, same as one sitting at stop N
      -- with stop_done reached. Mirrors
      -- ConvoyBarrierService._hasClearedStop in the Dart client.
      select bool_and(
               bd.current_stop_index > v_stop_index
               or (bd.current_stop_index = v_stop_index
                   and bd.journey_state = 'stop_done')
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
