-- Fix get_shared_trip_details RPC.
--
-- Problems in prior versions:
--   - Wrong column names: spot_name/spot_order/actual_arrival_at/actual_departure_at
--     (correct names: destination_name/destination_order/actual_arrival_time/actual_departure_time)
--   - Referenced public.notifications which was never created (runtime crash)
--   - 5-param overload made PostgREST unable to resolve the 2-param Flutter call
--
-- This migration drops all overloads and creates a clean 2-param function.

-- ── 1. Drop all existing overloads ───────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_shared_trip_details(text, text);
DROP FUNCTION IF EXISTS public.get_shared_trip_details(text, text, text, text);
DROP FUNCTION IF EXISTS public.get_shared_trip_details(text, text, text, text, boolean);

-- ── 2. Create correct function ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_shared_trip_details(
  p_public_token text,
  p_access_code  text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link          public.shared_trip_links%ROWTYPE;
  v_booking       public.package_bookings%ROWTYPE;
  v_can_track     boolean := false;
  v_itinerary     jsonb;
  v_drivers       jsonb;
  v_live_location jsonb;
  v_municipality  text;
  v_province      text;
BEGIN
  -- 1. Find an active, unexpired link matching the token
  SELECT * INTO v_link
  FROM   public.shared_trip_links
  WHERE  public_token = p_public_token
    AND  is_active    = true
    AND  revoked_at   IS NULL
    AND  expires_at   > now()
  LIMIT 1;

  -- 2. Validate: link must exist and access code must match
  IF NOT FOUND OR v_link.access_code IS DISTINCT FROM p_access_code THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Trip link is invalid, expired, or disabled.'
    );
  END IF;

  -- 3. Fetch the linked booking
  SELECT * INTO v_booking
  FROM   public.package_bookings
  WHERE  id = v_link.booking_id
  LIMIT  1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Trip link is invalid, expired, or disabled.'
    );
  END IF;

  -- 4. Determine if live tracking is available
  --    (true only while trip is actively in progress, not yet completed)
  v_can_track := COALESCE(v_booking.booking_status, v_booking.status, '')
                   = ANY (ARRAY['accepted', 'on_tour']);

  -- 5. Location context: municipality from first itinerary stop, province from package
  SELECT bii.municipality
  INTO   v_municipality
  FROM   public.booking_itinerary_items bii
  WHERE  bii.booking_id = v_link.booking_id
  ORDER  BY bii.destination_order ASC
  LIMIT  1;

  SELECT tp.province
  INTO   v_province
  FROM   public.tour_packages tp
  WHERE  tp.id = v_booking.package_id
  LIMIT  1;

  -- 6. Build itinerary — using correct column names
  SELECT jsonb_agg(
    jsonb_build_object(
      'destination_name',      bii.destination_name,
      'destination_address',   bii.destination_address,
      'order_number',          bii.destination_order,
      'arrival_time',          bii.arrival_time,
      'departure_time',        bii.departure_time,
      'spot_status',           bii.spot_status,
      'actual_arrival_time',   bii.actual_arrival_time,
      'actual_departure_time', bii.actual_departure_time,
      'latitude',              bii.latitude,
      'longitude',             bii.longitude
    ) ORDER BY bii.destination_order ASC
  )
  INTO v_itinerary
  FROM public.booking_itinerary_items bii
  WHERE bii.booking_id = v_link.booking_id;

  -- 7. Build driver list from booking_drivers — masked phone, no financials
  SELECT jsonb_agg(
    jsonb_build_object(
      'driver_id',      bd.driver_id::text,
      'full_name',      p.full_name,
      'mobile_masked',  CASE
                          WHEN p.mobile IS NOT NULL AND length(p.mobile) >= 7
                          THEN left(p.mobile, 2)
                               || repeat('*', length(p.mobile) - 5)
                               || right(p.mobile, 3)
                          ELSE NULL
                        END,
      'plate_number',   dd.plate_number,
      'operator_code',  dd.operator_code,
      'average_rating', p.average_rating,
      'total_reviews',  p.total_reviews
    )
  )
  INTO v_drivers
  FROM public.booking_drivers bd
  JOIN public.profiles        p  ON p.id          = bd.driver_id
  LEFT JOIN public.driver_details dd ON dd.driver_id = bd.driver_id
  WHERE bd.booking_id = v_link.booking_id
    AND bd.status     IN ('accepted', 'completed');

  -- 8. Latest driver live location (only exposed when tracking is active)
  IF v_can_track THEN
    SELECT jsonb_build_object(
      'driver_id',  dll.driver_id::text,
      'latitude',   dll.latitude,
      'longitude',  dll.longitude,
      'heading',    dll.heading,
      'speed',      dll.speed,
      'updated_at', dll.updated_at
    )
    INTO v_live_location
    FROM public.driver_live_locations dll
    JOIN public.booking_drivers       bd  ON bd.driver_id = dll.driver_id
    WHERE bd.booking_id = v_link.booking_id
      AND bd.status     IN ('accepted', 'completed')
    ORDER BY dll.updated_at DESC
    LIMIT 1;
  END IF;

  -- 9. Log this successful access
  INSERT INTO public.shared_trip_access_logs
    (shared_link_id, booking_id, access_status)
  VALUES
    (v_link.id, v_link.booking_id, 'allowed');

  -- 10. Return safe guest payload (no financials, no full phone, no passenger PII)
  RETURN jsonb_build_object(
    'success',                true,
    'booking_id',             v_link.booking_id::text,
    'trip_status',            COALESCE(v_booking.booking_status, v_booking.status, 'pending'),
    'booking_type',           v_booking.booking_type,
    'travel_date',            v_booking.travel_date,
    'municipality',           v_municipality,
    'province',               COALESCE(v_province, 'Bulacan'),
    'can_view_live_tracking', v_can_track,
    'itinerary',              COALESCE(v_itinerary, '[]'::jsonb),
    'drivers',                COALESCE(v_drivers,   '[]'::jsonb),
    'driver_live_location',   v_live_location
  );
END;
$$;

-- ── 3. Grant execute to guests (anon) and logged-in users ─────────────────────

GRANT EXECUTE ON FUNCTION public.get_shared_trip_details(text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_shared_trip_details(text, text) TO authenticated;
