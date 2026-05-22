-- Enable anon (guest) Realtime access for shared trip pages.
-- Adds SELECT policies for the anon role on the three tables guests need,
-- adds booking_itinerary_items to the Realtime publication, and updates
-- get_shared_trip_details to return booking_id + driver_id and accept a
-- p_silent flag so refresh calls don't re-log/re-notify the tourist.

-- ── 1. Anon SELECT policies ───────────────────────────────────────────────────

-- package_bookings: visible to anon only when an active shared link exists
DROP POLICY IF EXISTS anon_shared_booking_select ON public.package_bookings;
CREATE POLICY anon_shared_booking_select ON public.package_bookings
  FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.shared_trip_links stl
      WHERE stl.booking_id = public.package_bookings.id
        AND stl.is_active  = true
        AND stl.revoked_at IS NULL
        AND stl.expires_at > now()
    )
  );

-- booking_itinerary_items: visible to anon only when a shared link is active
DROP POLICY IF EXISTS anon_shared_itinerary_select ON public.booking_itinerary_items;
CREATE POLICY anon_shared_itinerary_select ON public.booking_itinerary_items
  FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.shared_trip_links stl
      WHERE stl.booking_id = public.booking_itinerary_items.booking_id
        AND stl.is_active  = true
        AND stl.revoked_at IS NULL
        AND stl.expires_at > now()
    )
  );

-- driver_live_locations already has USING(true) for all roles — no change needed.

-- ── 2. Add booking_itinerary_items to Realtime publication ───────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname   = 'supabase_realtime'
      AND tablename = 'booking_itinerary_items'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.booking_itinerary_items;
  END IF;
END $$;

-- ── 3. Replace RPC: add booking_id, driver_id output + p_silent flag ─────────

-- Drop old 4-arg overload so we don't accumulate overloads
DROP FUNCTION IF EXISTS public.get_shared_trip_details(text, text, text, text);

CREATE OR REPLACE FUNCTION public.get_shared_trip_details(
  p_public_token text,
  p_access_code  text,
  p_device_info  text    DEFAULT NULL,
  p_user_agent   text    DEFAULT NULL,
  p_silent       boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link         public.shared_trip_links%ROWTYPE;
  v_booking      public.package_bookings%ROWTYPE;
  v_tour_status  text;
  v_driver_id    uuid;
  v_driver_lat   double precision;
  v_driver_lng   double precision;
  v_driver_phone text;
  v_masked_phone text;
  v_plate_num    text;
  v_pickup_text  text;
  v_itinerary    jsonb;
BEGIN
  -- Look up active link
  SELECT * INTO v_link
  FROM   public.shared_trip_links
  WHERE  public_token = p_public_token
    AND  is_active    = true
    AND  revoked_at   IS NULL
    AND  expires_at   > now()
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'error',   'invalid_or_expired',
      'message', 'Trip link is invalid, expired, or disabled.'
    );
  END IF;

  -- Validate access code
  IF v_link.access_code IS DISTINCT FROM p_access_code THEN
    IF NOT p_silent THEN
      INSERT INTO public.shared_trip_access_logs
        (shared_link_id, booking_id, device_info, user_agent, access_status)
      VALUES (v_link.id, v_link.booking_id, p_device_info, p_user_agent, 'denied');
    END IF;
    RETURN jsonb_build_object(
      'error',   'invalid_code',
      'message', 'Incorrect access code.'
    );
  END IF;

  -- Fetch booking
  SELECT * INTO v_booking
  FROM   public.package_bookings
  WHERE  id = v_link.booking_id
  LIMIT  1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'error',   'not_found',
      'message', 'Booking not found.'
    );
  END IF;

  -- Fetch latest activity (driver position + status)
  SELECT tour_status, driver_id, driver_latitude, driver_longitude
  INTO   v_tour_status, v_driver_id, v_driver_lat, v_driver_lng
  FROM   public.package_activities
  WHERE  booking_id = v_link.booking_id
  ORDER  BY created_at DESC
  LIMIT  1;

  -- Masked driver contact info
  IF v_driver_id IS NOT NULL THEN
    SELECT mobile      INTO v_driver_phone FROM public.profiles      WHERE id = v_driver_id LIMIT 1;
    SELECT plate_number INTO v_plate_num   FROM public.driver_details WHERE driver_id = v_driver_id LIMIT 1;
  END IF;

  IF v_driver_phone IS NOT NULL AND length(v_driver_phone) >= 7 THEN
    v_masked_phone := left(v_driver_phone, 2)
                   || repeat('*', length(v_driver_phone) - 5)
                   || right(v_driver_phone, 3);
  END IF;

  -- Pickup: show only the area/landmark, not the full address
  v_pickup_text := btrim(split_part(v_booking.pickup_address, ',', 2));
  IF v_pickup_text = '' THEN
    v_pickup_text := btrim(split_part(v_booking.pickup_address, ',', 1));
  END IF;

  -- Itinerary: name + status only, no precise coordinates
  SELECT jsonb_agg(
    jsonb_build_object(
      'name',        spot_name,
      'status',      spot_status,
      'order',       spot_order,
      'arrived_at',  actual_arrival_at,
      'departed_at', actual_departure_at
    ) ORDER BY spot_order ASC
  )
  INTO v_itinerary
  FROM public.booking_itinerary_items
  WHERE booking_id = v_link.booking_id;

  -- Log access and notify tourist (skipped on silent refresh calls)
  IF NOT p_silent THEN
    INSERT INTO public.shared_trip_access_logs
      (shared_link_id, booking_id, device_info, user_agent, access_status)
    VALUES (v_link.id, v_link.booking_id, p_device_info, p_user_agent, 'allowed');

    INSERT INTO public.notifications (user_id, title, body, type, is_read)
    VALUES (
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

  RETURN jsonb_build_object(
    'success',               true,
    'booking_id',            v_link.booking_id::text,
    'driver_id',             v_driver_id::text,
    'booking_status',        v_booking.status,
    'tour_status',           COALESCE(v_tour_status, 'not_started'),
    'booking_status_detail', v_booking.booking_status,
    'driver_phone_masked',   v_masked_phone,
    'driver_code',           COALESCE(v_plate_num, ''),
    'tricycle_number',       COALESCE(v_plate_num, ''),
    'pickup_landmark',       v_pickup_text,
    'itinerary_items',       COALESCE(v_itinerary, '[]'::jsonb),
    'driver_latitude',       v_driver_lat,
    'driver_longitude',      v_driver_lng
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_shared_trip_details(text, text, text, text, boolean) TO anon;
GRANT EXECUTE ON FUNCTION public.get_shared_trip_details(text, text, text, text, boolean) TO authenticated;
