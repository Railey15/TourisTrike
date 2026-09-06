-- One radius source for pickup, itinerary stops, drop-off, and corroborated
-- fallback. The Driver Tour Navigation screen loads this before starting GPS.
begin;

create or replace function public.driver_arrival_radius_meters()
returns double precision
language sql
immutable
set search_path = public
as $$ select 150::double precision $$;

revoke all on function public.driver_arrival_radius_meters() from public, anon;
grant execute on function public.driver_arrival_radius_meters() to authenticated;

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
  v_allowed_radius_meters constant double precision := public.driver_arrival_radius_meters();
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

create or replace function public.confirm_driver_arrival_fallback(p_booking_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_booking public.package_bookings; v_driver public.booking_drivers;
  v_lat double precision; v_lng double precision; v_target text; v_result jsonb;
begin
  if auth.uid() is null or length(trim(coalesce(p_reason, ''))) < 10 or length(p_reason) > 500 then
    raise exception 'ARRIVAL_FALLBACK_REASON_REQUIRED';
  end if;
  select * into v_booking from public.package_bookings where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  select * into v_driver from public.booking_drivers where booking_id = p_booking_id
    and driver_id = auth.uid() and status = 'accepted' for update;
  if not found then raise exception 'NOT_ACTIVE_BOOKING_DRIVER'; end if;
  if v_driver.journey_state in ('at_pickup', 'at_stop', 'at_dropoff') then
    return jsonb_build_object('success', true, 'no_op', true);
  end if;
  if v_driver.journey_state = 'en_route_pickup' then
    v_target := 'at_pickup'; v_lat := v_booking.pickup_latitude; v_lng := v_booking.pickup_longitude;
  elsif v_driver.journey_state = 'en_route_dropoff' then
    v_target := 'at_dropoff'; v_lat := v_booking.dropoff_latitude; v_lng := v_booking.dropoff_longitude;
  elsif v_driver.journey_state = 'en_route_stop' then
    v_target := 'at_stop';
    select latitude, longitude into v_lat, v_lng from public.booking_itinerary_items where booking_id = p_booking_id
    order by coalesce(order_number, 2147483647), coalesce(destination_order, 2147483647), arrival_time nulls last, created_at, id
    offset v_driver.current_stop_index limit 1;
  else raise exception 'NOT_EN_ROUTE'; end if;
  if v_lat is null or v_lng is null then raise exception 'TARGET_LOCATION_REQUIRED'; end if;
  if exists (
    select 1 from public.booking_participant_live_locations l
    where l.booking_id = p_booking_id and l.user_id = v_booking.tourist_id
      and l.updated_at >= now() - interval '2 minutes' and l.accuracy_meters <= 50
      and 6371000 * 2 * asin(sqrt(least(1, greatest(0,
        power(sin(radians(l.latitude - v_lat) / 2), 2) + cos(radians(v_lat)) * cos(radians(l.latitude))
        * power(sin(radians(l.longitude - v_lng) / 2), 2))))) <= public.driver_arrival_radius_meters()
  ) then
    perform set_config('touristrike.arrival_fallback_verified', 'true', true);
  end if;
  -- Otherwise the usual fresh driver-location guard applies.
  v_result := public.advance_driver_journey_state(p_booking_id, v_target);
  perform set_config('touristrike.arrival_fallback_verified', 'false', true);
  insert into public.trip_status_logs(activity_id, booking_id, driver_id, status, previous_state, new_state, spot_index, notes)
  select id, p_booking_id, auth.uid(), 'arrival_manual_fallback', v_driver.journey_state, v_target,
    v_driver.current_stop_index, trim(p_reason) from public.package_activities where booking_id = p_booking_id;
  return v_result;
end;
$$;

commit;
