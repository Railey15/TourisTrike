-- Extend get_shared_trip_details to return full safe data needed by guest map:
--  • driver_name (from profiles.full_name)
--  • dropoff_landmark (same extraction as pickup_landmark)
--  • pickup_latitude / pickup_longitude
--  • dropoff_latitude / dropoff_longitude
--  • itinerary items with latitude / longitude / scheduled times
--  • live driver location fallback from driver_live_locations
--  • assigned_driver_id fallback when package_activities has no driver

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
  v_driver_name   text;
  v_driver_phone  text;
  v_masked_phone  text;
  v_plate_num     text;
  v_operator_code text;
  v_pickup_text   text;
  v_dropoff_text  text;
  v_itinerary     jsonb;
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

  -- ── 5. Fetch driver profile & vehicle details ────────────────────────────────
  IF v_driver_id IS NOT NULL THEN
    SELECT full_name, mobile
      INTO v_driver_name, v_driver_phone
      FROM public.profiles
     WHERE id = v_driver_id
     LIMIT 1;

    SELECT plate_number, operator_code
      INTO v_plate_num, v_operator_code
      FROM public.driver_details
     WHERE driver_id = v_driver_id
     LIMIT 1;
  END IF;

  -- ── 6. Mask phone (keep first 3 + last 3, mask middle) ─────────────────────
  IF v_driver_phone IS NOT NULL AND length(v_driver_phone) >= 7 THEN
    v_masked_phone :=
      left(v_driver_phone, 3)
      || repeat('*', length(v_driver_phone) - 6)
      || right(v_driver_phone, 3);
  END IF;

  -- ── 7. Live location fallback from driver_live_locations ────────────────────
  IF (v_driver_lat IS NULL OR v_driver_lng IS NULL) AND v_driver_id IS NOT NULL THEN
    SELECT latitude, longitude
      INTO v_driver_lat, v_driver_lng
      FROM public.driver_live_locations
     WHERE driver_id = v_driver_id
     LIMIT 1;
  END IF;

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
    ORDER BY destination_order ASC
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
    'driver_name',          COALESCE(v_driver_name, ''),
    'booking_status',       v_booking.status,
    'tour_status',          COALESCE(v_tour_status, 'not_started'),
    'booking_status_detail',v_booking.booking_status,
    'driver_phone_masked',  v_masked_phone,
    'driver_code',          COALESCE(v_operator_code, v_plate_num, ''),
    'tricycle_number',      COALESCE(v_plate_num, ''),
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
