-- ============================================================
-- Convoy Sync — Phase 3/5: wire the passenger auto-split that was built
-- (but deliberately left unconnected) in Phase 0, and add the missing
-- "driver cancels after accepting" slot-release path flagged back in
-- Open Question 3 / Adjustment 5's deadlock-protection concern — a
-- barrier with no way to drop a member is a barrier with no exit path.
-- ============================================================

-- ── 1. Wire compute_passenger_split into accept_package_booking ──
-- Only fires once the group is fully accepted (mirrors the existing
-- "all filled" branch) — recomputes and writes assigned_passengers for
-- every accepted driver in one pass. Everything else in this RPC is
-- byte-for-byte the version from 20260725000000_gcash_payment_trail.sql;
-- only the new block right after the package_bookings UPDATE in the
-- "all filled" branch is added.
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

    -- NEW: passenger auto-split, now that the roster is final. Single
    -- source of truth stays compute_passenger_split() (Phase 0) — this
    -- is the only place it's actually called from.
    update public.booking_drivers bd
    set assigned_passengers = split.passenger_count
    from public.compute_passenger_split(
      p_booking_id,
      case when coalesce(v_booking.total_passengers, 0) > 0
           then v_booking.total_passengers
           else v_booking.adults + coalesce(v_booking.children, 0)
      end
    ) as split
    where bd.booking_id = p_booking_id
      and bd.driver_id = split.driver_id;
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

-- ── 2. cancel_driver_slot: release a slot after accepting ──────
-- Fills the deadlock-protection gap: without this, a driver who accepted
-- and then goes AWOL leaves the barrier permanently unsatisfiable for
-- everyone else in the convoy. Only usable BEFORE the group is fully
-- underway (booking_status still 'accepted' or 'waiting_for_drivers') —
-- once the tour is on_tour, this isn't a "didn't show up" situation
-- anymore and needs human (admin) intervention instead, not a self-serve
-- cancel (see the deadlock >20min "Report Issue" path noted in
-- ConvoyBarrierService — the admin-override RPC itself is still open,
-- flagged in the report).
create or replace function public.cancel_driver_slot(
  p_booking_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_booking   public.package_bookings;
  v_row       public.booking_drivers;
  v_remaining_count integer;
begin
  if v_driver_id is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'BOOKING_NOT_FOUND';
  end if;

  if v_booking.booking_status not in ('accepted', 'waiting_for_drivers') then
    raise exception 'CANNOT_CANCEL_AFTER_TOUR_STARTED';
  end if;

  select * into v_row
  from public.booking_drivers
  where booking_id = p_booking_id
    and driver_id = v_driver_id
    and status = 'accepted'
  for update;

  if not found then
    raise exception 'NOT_IN_CONVOY';
  end if;

  update public.booking_drivers
  set status = 'rejected'
  where booking_id = p_booking_id and driver_id = v_driver_id;

  select count(*) into v_remaining_count
  from public.booking_drivers
  where booking_id = p_booking_id and status = 'accepted';

  update public.package_bookings
  set accepted_drivers_count = v_remaining_count,
      booking_status         = 'waiting_for_drivers',
      status                 = 'pending',
      assigned_driver_id     = null,
      updated_at             = now()
  where id = p_booking_id;

  -- Re-open the shared activity row for other drivers to see again, if
  -- it had already been claimed by this same driver (only possible if
  -- they were the one who completed the group, then cancelled).
  update public.package_activities
  set driver_id   = null,
      status      = 'pending',
      tour_status = 'waiting_driver',
      updated_at  = now()
  where booking_id = p_booking_id
    and driver_id = v_driver_id;

  return jsonb_build_object(
    'success', true,
    'remaining_count', v_remaining_count,
    'required_count', coalesce(v_booking.required_drivers, 1)
  );
end;
$$;

grant execute on function public.cancel_driver_slot(uuid) to authenticated;
