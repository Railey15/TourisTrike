-- Create a package booking and its immutable booking-time snapshots in one
-- PostgreSQL transaction. package_activities remains owned by
-- trg_sync_package_activity; this RPC deliberately does not duplicate it.

create or replace function public.create_package_booking(
  p_booking jsonb,
  p_customized_spots jsonb default '[]'::jsonb,
  p_itinerary_items jsonb default '[]'::jsonb
)
returns public.package_bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tourist_id uuid := auth.uid();
  v_booking public.package_bookings;
  v_package_id bigint;
begin
  if v_tourist_id is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if public.current_profile_role() <> 'tourist' then
    raise exception 'TOURIST_ROLE_REQUIRED';
  end if;
  -- Serialize the existing single-active-tour trigger for concurrent submits.
  perform pg_advisory_xact_lock(hashtextextended(v_tourist_id::text, 0));
  if jsonb_typeof(coalesce(p_booking, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_customized_spots, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_itinerary_items, '[]'::jsonb)) <> 'array' then
    raise exception 'INVALID_BOOKING_PAYLOAD';
  end if;

  v_package_id := nullif(p_booking->>'package_id', '')::bigint;
  if v_package_id is null or not exists (
    select 1 from public.tour_packages where id = v_package_id
  ) then
    raise exception 'PACKAGE_NOT_FOUND';
  end if;

  insert into public.package_bookings (
    package_id, tourist_id, travel_date, adults, children, payment_method,
    notes, total_amount, downpayment_amount, remaining_balance, booking_type,
    pickup_address, pickup_latitude, pickup_longitude, pickup_province,
    pickup_locality, pickup_country_code, dropoff_address, dropoff_latitude,
    dropoff_longitude, dropoff_province, dropoff_locality,
    dropoff_country_code, required_drivers, municipality, province,
    total_passengers, booking_status, status
  ) values (
    v_package_id,
    v_tourist_id,
    (p_booking->>'travel_date')::date,
    coalesce(nullif(p_booking->>'adults', '')::integer, 1),
    coalesce(nullif(p_booking->>'children', '')::integer, 0),
    coalesce(nullif(p_booking->>'payment_method', ''), 'cash'),
    nullif(btrim(p_booking->>'notes'), ''),
    coalesce(nullif(p_booking->>'total_amount', '')::numeric, 0),
    coalesce(nullif(p_booking->>'downpayment_amount', '')::numeric, 0),
    coalesce(nullif(p_booking->>'remaining_balance', '')::numeric, 0),
    coalesce(nullif(p_booking->>'booking_type', ''), 'advanced'),
    nullif(btrim(p_booking->>'pickup_address'), ''),
    nullif(p_booking->>'pickup_latitude', '')::double precision,
    nullif(p_booking->>'pickup_longitude', '')::double precision,
    nullif(btrim(p_booking->>'pickup_province'), ''),
    nullif(btrim(p_booking->>'pickup_locality'), ''),
    coalesce(nullif(btrim(p_booking->>'pickup_country_code'), ''), 'PH'),
    nullif(btrim(p_booking->>'dropoff_address'), ''),
    nullif(p_booking->>'dropoff_latitude', '')::double precision,
    nullif(p_booking->>'dropoff_longitude', '')::double precision,
    nullif(btrim(p_booking->>'dropoff_province'), ''),
    nullif(btrim(p_booking->>'dropoff_locality'), ''),
    coalesce(nullif(btrim(p_booking->>'dropoff_country_code'), ''), 'PH'),
    coalesce(nullif(p_booking->>'required_drivers', '')::integer, 1),
    nullif(btrim(p_booking->>'municipality'), ''),
    nullif(btrim(p_booking->>'province'), ''),
    coalesce(
      nullif(p_booking->>'total_passengers', '')::integer,
      coalesce(nullif(p_booking->>'adults', '')::integer, 1)
        + coalesce(nullif(p_booking->>'children', '')::integer, 0)
    ),
    'waiting_for_drivers',
    'pending'
  )
  returning * into v_booking;

  insert into public.customized_package_spots (
    booking_id, tourist_id, package_id, spot_id, action_type, source_type,
    google_place_id, spot_title, spot_address, municipality, barangay,
    latitude, longitude, image_url, additional_fee, sort_order, opening_time,
    closing_time, estimated_arrival_time, estimated_duration_minutes,
    recommended_visit_duration_minutes
  )
  select
    v_booking.id, v_tourist_id, v_package_id,
    nullif(item->>'spot_id', '')::bigint,
    coalesce(nullif(item->>'action_type', ''), 'kept'),
    coalesce(nullif(item->>'source_type', ''), 'manual'),
    nullif(item->>'google_place_id', ''),
    item->>'spot_title', nullif(item->>'spot_address', ''),
    item->>'municipality', nullif(item->>'barangay', ''),
    nullif(item->>'latitude', '')::double precision,
    nullif(item->>'longitude', '')::double precision,
    nullif(item->>'image_url', ''),
    coalesce(nullif(item->>'additional_fee', '')::numeric, 0),
    nullif(item->>'sort_order', '')::integer,
    nullif(item->>'opening_time', '')::time,
    nullif(item->>'closing_time', '')::time,
    nullif(item->>'estimated_arrival_time', '')::time,
    nullif(item->>'estimated_duration_minutes', '')::integer,
    nullif(item->>'recommended_visit_duration_minutes', '')::integer
  from jsonb_array_elements(coalesce(p_customized_spots, '[]'::jsonb)) item;

  insert into public.booking_itinerary_items (
    booking_id, tourist_id, spot_id, destination_name, destination_address,
    order_number, destination_order, arrival_time,
    estimated_stay_duration_minutes, departure_time, activity_note,
    itinerary_source, source_type, google_place_id, municipality, barangay,
    latitude, longitude, image_url
  )
  select
    v_booking.id, v_tourist_id, nullif(item->>'spot_id', '')::bigint,
    item->>'destination_name', nullif(item->>'destination_address', ''),
    coalesce(
      nullif(item->>'order_number', '')::integer,
      nullif(item->>'destination_order', '')::integer,
      ordinal::integer
    ),
    coalesce(nullif(item->>'destination_order', '')::integer, ordinal::integer),
    nullif(item->>'arrival_time', '')::time,
    coalesce(nullif(item->>'estimated_stay_duration_minutes', '')::integer, 0),
    nullif(item->>'departure_time', '')::time,
    nullif(item->>'activity_note', ''),
    coalesce(
      nullif(item->>'itinerary_source', ''),
      nullif(item->>'source_type', ''),
      'ai_suggested'
    ),
    coalesce(nullif(item->>'source_type', ''), 'ai_suggested'),
    nullif(item->>'google_place_id', ''),
    nullif(item->>'municipality', ''), nullif(item->>'barangay', ''),
    nullif(item->>'latitude', '')::double precision,
    nullif(item->>'longitude', '')::double precision,
    nullif(item->>'image_url', '')
  from jsonb_array_elements(coalesce(p_itinerary_items, '[]'::jsonb))
    with ordinality as rows(item, ordinal);

  return v_booking;
end;
$$;

revoke all on function public.create_package_booking(jsonb, jsonb, jsonb)
  from public;
grant execute on function public.create_package_booking(jsonb, jsonb, jsonb)
  to authenticated;
