BEGIN;
-- Guest-only projection of the Tourist convoy roster. No table/schema or
-- journey/payment write changes. Deploy after 20260907010000.
-- Restore named RPC arguments used by the app; replace the incompatible P0 wrapper.
DROP FUNCTION IF EXISTS public.get_shared_trip_details(text, text, text, text, boolean);

CREATE OR REPLACE FUNCTION public.get_shared_trip_details(
  p_public_token  text,
  p_access_code   text,
  p_device_info   text    DEFAULT NULL,
  p_user_agent    text    DEFAULT NULL,
  p_silent        boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link          public.shared_trip_links%ROWTYPE;
  v_booking       public.package_bookings%ROWTYPE;
  v_tour_status   text;
  v_driver_id     uuid;
  v_driver_lat    double precision;
  v_driver_lng    double precision;
  v_pickup_text   text;
  v_dropoff_text  text;
  v_itinerary     jsonb;
  v_drivers jsonb;
  v_terminal boolean;
BEGIN

  -- ── 1. Validate shared link ─────────────────────────────────────────────────
  SELECT *
    INTO v_link
    FROM public.shared_trip_links
   WHERE public_token = p_public_token
     AND is_active    = true
     AND revoked_at   IS NULL
     AND expires_at   > now()
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'error',   'invalid_or_expired',
      'message', 'Trip link is invalid, expired, or disabled.'
    );
  END IF;

  -- ── 2. Validate access code ─────────────────────────────────────────────────
  IF v_link.access_code IS DISTINCT FROM p_access_code THEN
    IF NOT p_silent THEN
      INSERT INTO public.shared_trip_access_logs (
        shared_link_id, booking_id, device_info, user_agent, access_status
      ) VALUES (
        v_link.id, v_link.booking_id, p_device_info, p_user_agent, 'denied'
      );
    END IF;
    RETURN jsonb_build_object(
      'error',   'invalid_code',
      'message', 'Incorrect access code.'
    );
  END IF;

  -- ── 3. Fetch booking ────────────────────────────────────────────────────────
  SELECT *
    INTO v_booking
    FROM public.package_bookings
   WHERE id = v_link.booking_id
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'error',   'not_found',
      'message', 'Booking not found.'
    );
  END IF;

  -- ── 4. Fetch activity (tour status + live coords) ───────────────────────────
  SELECT tour_status, driver_id, driver_latitude, driver_longitude
    INTO v_tour_status, v_driver_id, v_driver_lat, v_driver_lng
    FROM public.package_activities
   WHERE booking_id = v_link.booking_id
   ORDER BY created_at DESC
   LIMIT 1;

  -- Fall back to booking's assigned driver when activity has none
  IF v_driver_id IS NULL THEN
    v_driver_id := v_booking.assigned_driver_id;
  END IF;

  -- Read the same persisted activity and assignment states as Tourist tracking.
  -- No guest status columns and no anonymous table access are required.
  v_terminal := lower(coalesce(v_booking.status, '')) in ('completed','cancelled','rejected','done')
    or lower(coalesce(v_booking.booking_status, '')) in ('completed','cancelled','rejected','done')
    or lower(coalesce(v_tour_status, '')) in ('completed','cancelled','dropped_off');

  with roster as (
    select bd.driver_id, bd.status, bd.journey_state, bd.current_stop_index,
           bd.state_updated_at, bd.accepted_at
    from public.booking_drivers bd
    where bd.booking_id = v_link.booking_id and bd.status in ('accepted','completed')
    union all
    select v_driver_id, 'accepted', 'assigned', 0, null::timestamptz, null::timestamptz
    where v_driver_id is not null and not exists (
      select 1 from public.booking_drivers where booking_id = v_link.booking_id
    )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'driver_id', r.driver_id, 'status', r.status,
    'journey_state', r.journey_state, 'current_stop_index', r.current_stop_index,
    'state_updated_at', r.state_updated_at,
    'driver_name', coalesce(nullif(p.full_name, ''),
      nullif(concat_ws(' ', nullif(p.first_name, ''), nullif(p.middle_name, ''), nullif(p.last_name, '')), ''), 'Driver'),
    'plate_number', coalesce(dd.plate_number, ''),
    'toda_name', coalesce(dd.toda_name, ''),
    'latitude', loc.latitude, 'longitude', loc.longitude,
    'heading', loc.heading, 'updated_at', loc.updated_at
  ) order by r.accepted_at nulls last, r.driver_id), '[]'::jsonb)
  into v_drivers
  from roster r
  left join public.profiles p on p.id = r.driver_id
  left join public.driver_details dd on dd.driver_id = r.driver_id
  left join lateral (
    select dll.latitude, dll.longitude, dll.heading, dll.updated_at
    from public.driver_live_locations dll
    -- Same per-driver location row as fetchConvoyRoster. activity_id is
    -- nullable; a missing activity reference must not discard a live driver.
    -- An explicit different booking is never exposed through this share link.
    where dll.driver_id = r.driver_id
      and ((dll.activity_id is null and dll.updated_at >= coalesce(r.accepted_at, '-infinity'::timestamptz)) or exists (
        select 1 from public.package_activities pa
        where pa.id = dll.activity_id and pa.booking_id = v_link.booking_id
      ))
      and not v_terminal and r.status = 'accepted' and r.journey_state <> 'completed'
      and dll.latitude between -90 and 90 and dll.longitude between -180 and 180
      and not (dll.latitude = 0 and dll.longitude = 0)
  ) loc on true;

  -- Route origin must come from this booking's current roster, never cached
  -- activity GPS or a driver's present-day location on a different booking.
  v_driver_lat := null;
  v_driver_lng := null;
  select (d->>'latitude')::double precision, (d->>'longitude')::double precision
    into v_driver_lat, v_driver_lng
    from jsonb_array_elements(v_drivers) d
    where d->>'latitude' is not null and d->>'longitude' is not null
    order by (d->>'driver_id' = v_driver_id::text) desc
    limit 1;

  -- ── 8. Pickup landmark (second CSV segment, or first if only one) ───────────
  v_pickup_text := btrim(split_part(COALESCE(v_booking.pickup_address, ''), ',', 2));
  IF v_pickup_text = '' THEN
    v_pickup_text := btrim(split_part(COALESCE(v_booking.pickup_address, ''), ',', 1));
  END IF;

  -- ── 9. Dropoff landmark ─────────────────────────────────────────────────────
  v_dropoff_text := btrim(split_part(COALESCE(v_booking.dropoff_address, ''), ',', 2));
  IF v_dropoff_text = '' THEN
    v_dropoff_text := btrim(split_part(COALESCE(v_booking.dropoff_address, ''), ',', 1));
  END IF;

  -- ── 10. Itinerary with full coords + schedule ───────────────────────────────
  SELECT jsonb_agg(
    jsonb_build_object(
      'name',                          destination_name,
      'status',                        spot_status,
      'order',                         destination_order,
      'arrived_at',                    actual_arrival_time,
      'departed_at',                   actual_departure_time,
      'latitude',                      latitude,
      'longitude',                     longitude,
      'arrival_time',                  to_char(arrival_time,  'HH24:MI:SS'),
      'departure_time',                to_char(departure_time,'HH24:MI:SS'),
      'estimated_stay_duration_minutes', estimated_stay_duration_minutes
    )
    ORDER BY order_number ASC NULLS LAST, destination_order ASC NULLS LAST, arrival_time ASC NULLS LAST
  )
    INTO v_itinerary
    FROM public.booking_itinerary_items
   WHERE booking_id = v_link.booking_id;

  -- ── 11. Log access ──────────────────────────────────────────────────────────
  IF NOT p_silent THEN
    INSERT INTO public.shared_trip_access_logs (
      shared_link_id, booking_id, device_info, user_agent, access_status
    ) VALUES (
      v_link.id, v_link.booking_id, p_device_info, p_user_agent, 'allowed'
    );

    INSERT INTO public.notifications (
      user_id, title, body, type, is_read
    ) VALUES (
      v_link.tourist_id,
      'Shared Trip Link Accessed',
      format(
        'Someone accessed your shared trip link. Device: %s. Time: %s.',
        COALESCE(p_device_info, 'Unknown device'),
        to_char(now() AT TIME ZONE 'Asia/Manila', 'HH12:MI AM')
      ),
      'shared_link_access',
      false
    );
  END IF;

  -- ── 12. Return safe payload ─────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',              true,
    'booking_id',           v_link.booking_id::text,
    'driver_id',            COALESCE(v_driver_id::text, ''),
    'driver_name',          '',
    'drivers',              v_drivers,
    'booking_status',       v_booking.status,
    'tour_status',          COALESCE(v_tour_status, 'not_started'),
    'booking_status_detail',v_booking.booking_status,
    'driver_phone_masked',  null,
    'driver_code',          '',
    'tricycle_number',      '',
    'pickup_landmark',      COALESCE(v_pickup_text, ''),
    'dropoff_landmark',     COALESCE(v_dropoff_text, ''),
    'pickup_latitude',      v_booking.pickup_latitude,
    'pickup_longitude',     v_booking.pickup_longitude,
    'dropoff_latitude',     v_booking.dropoff_latitude,
    'dropoff_longitude',    v_booking.dropoff_longitude,
    'itinerary_items',      COALESCE(v_itinerary, '[]'::jsonb),
    'driver_latitude',      v_driver_lat,
    'driver_longitude',     v_driver_lng
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_shared_trip_details(text, text, text, text, boolean) TO anon;
GRANT EXECUTE ON FUNCTION public.get_shared_trip_details(text, text, text, text, boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Earlier policies tested only link existence, not possession of its token/code.
-- Preserve authenticated Tourist/Driver policies; guests use the validated RPC.
DROP POLICY IF EXISTS anon_shared_booking_select ON public.package_bookings;
DROP POLICY IF EXISTS anon_shared_itinerary_select ON public.booking_itinerary_items;
REVOKE ALL ON FUNCTION public.get_shared_trip_details(text,text,text,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_shared_trip_details(text,text,text,text,boolean) TO anon, authenticated;
COMMIT;
