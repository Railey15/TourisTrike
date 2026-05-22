-- Shared Trip Links: tourists share a secure URL+code with companions who have
-- no TourisTrike account. Guests validate the code and see limited trip info.

-- ── 1. Tables ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.shared_trip_links (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id       uuid        NOT NULL REFERENCES public.package_bookings(id) ON DELETE CASCADE,
  tourist_id       uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  public_token     text        NOT NULL UNIQUE,
  access_code      text        NOT NULL,
  is_active        boolean     NOT NULL DEFAULT true,
  expires_at       timestamptz NOT NULL,
  revoked_at       timestamptz,
  regenerated_from uuid        REFERENCES public.shared_trip_links(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.shared_trip_access_logs (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  shared_link_id uuid        NOT NULL REFERENCES public.shared_trip_links(id) ON DELETE CASCADE,
  booking_id     uuid        NOT NULL REFERENCES public.package_bookings(id) ON DELETE CASCADE,
  device_info    text,
  ip_address     text,
  user_agent     text,
  access_status  text        NOT NULL DEFAULT 'pending'
                             CHECK (access_status IN ('pending', 'allowed', 'denied')),
  accessed_at    timestamptz NOT NULL DEFAULT now()
);

-- ── 2. Indexes ───────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_shared_trip_links_token   ON public.shared_trip_links(public_token);
CREATE INDEX IF NOT EXISTS idx_shared_trip_links_booking ON public.shared_trip_links(booking_id);
CREATE INDEX IF NOT EXISTS idx_shared_trip_links_tourist ON public.shared_trip_links(tourist_id);

-- ── 3. Updated-at trigger ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_shared_trip_links_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_shared_trip_links_updated_at ON public.shared_trip_links;
CREATE TRIGGER trg_shared_trip_links_updated_at
  BEFORE UPDATE ON public.shared_trip_links
  FOR EACH ROW EXECUTE FUNCTION public.set_shared_trip_links_updated_at();

-- ── 4. RLS ───────────────────────────────────────────────────────────────────

ALTER TABLE public.shared_trip_links      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shared_trip_access_logs ENABLE ROW LEVEL SECURITY;

-- Tourists manage their own links
DROP POLICY IF EXISTS stl_tourist_select ON public.shared_trip_links;
CREATE POLICY stl_tourist_select ON public.shared_trip_links
  FOR SELECT TO authenticated
  USING (tourist_id = auth.uid());

DROP POLICY IF EXISTS stl_tourist_insert ON public.shared_trip_links;
CREATE POLICY stl_tourist_insert ON public.shared_trip_links
  FOR INSERT TO authenticated
  WITH CHECK (tourist_id = auth.uid());

DROP POLICY IF EXISTS stl_tourist_update ON public.shared_trip_links;
CREATE POLICY stl_tourist_update ON public.shared_trip_links
  FOR UPDATE TO authenticated
  USING   (tourist_id = auth.uid())
  WITH CHECK (tourist_id = auth.uid());

-- Tourists read access logs for their own links
DROP POLICY IF EXISTS stal_tourist_select ON public.shared_trip_access_logs;
CREATE POLICY stal_tourist_select ON public.shared_trip_access_logs
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shared_trip_links stl
      WHERE stl.id = shared_link_id AND stl.tourist_id = auth.uid()
    )
  );

-- ── 5. Guest RPC: validate token + code and return limited trip details ───────

CREATE OR REPLACE FUNCTION public.get_shared_trip_details(
  p_public_token text,
  p_access_code  text,
  p_device_info  text DEFAULT NULL,
  p_user_agent   text DEFAULT NULL
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
  -- Look up the link
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
    INSERT INTO public.shared_trip_access_logs
      (shared_link_id, booking_id, device_info, user_agent, access_status)
    VALUES
      (v_link.id, v_link.booking_id, p_device_info, p_user_agent, 'denied');

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

  -- Fetch latest activity
  SELECT tour_status, driver_id, driver_latitude, driver_longitude
  INTO   v_tour_status, v_driver_id, v_driver_lat, v_driver_lng
  FROM   public.package_activities
  WHERE  booking_id = v_link.booking_id
  ORDER  BY created_at DESC
  LIMIT  1;

  -- Mask driver phone (keep first 2 + last 3 digits)
  IF v_driver_id IS NOT NULL THEN
    SELECT mobile INTO v_driver_phone
    FROM   public.profiles
    WHERE  id = v_driver_id
    LIMIT  1;

    SELECT plate_number INTO v_plate_num
    FROM   public.driver_details
    WHERE  driver_id = v_driver_id
    LIMIT  1;
  END IF;

  IF v_driver_phone IS NOT NULL AND length(v_driver_phone) >= 7 THEN
    v_masked_phone := left(v_driver_phone, 2)
                   || repeat('*', length(v_driver_phone) - 5)
                   || right(v_driver_phone, 3);
  END IF;

  -- Pickup: show only 2nd comma-segment as landmark, not full address
  v_pickup_text := btrim(split_part(v_booking.pickup_address, ',', 2));
  IF v_pickup_text = '' THEN
    v_pickup_text := btrim(split_part(v_booking.pickup_address, ',', 1));
  END IF;

  -- Itinerary: name, status, order only
  SELECT jsonb_agg(
    jsonb_build_object(
      'name',         spot_name,
      'status',       spot_status,
      'order',        spot_order,
      'arrived_at',   actual_arrival_at,
      'departed_at',  actual_departure_at
    ) ORDER BY spot_order ASC
  )
  INTO v_itinerary
  FROM public.booking_itinerary_items
  WHERE booking_id = v_link.booking_id;

  -- Log successful access
  INSERT INTO public.shared_trip_access_logs
    (shared_link_id, booking_id, device_info, user_agent, access_status)
  VALUES
    (v_link.id, v_link.booking_id, p_device_info, p_user_agent, 'allowed');

  -- Notify main tourist
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

  RETURN jsonb_build_object(
    'success',          true,
    'booking_status',   v_booking.status,
    'tour_status',      COALESCE(v_tour_status, 'not_started'),
    'booking_status_detail', v_booking.booking_status,
    'driver_phone_masked', v_masked_phone,
    'driver_code',      COALESCE(v_plate_num, ''),
    'tricycle_number',  COALESCE(v_plate_num, ''),
    'pickup_landmark',  v_pickup_text,
    'itinerary_items',  COALESCE(v_itinerary, '[]'::jsonb),
    'driver_latitude',  v_driver_lat,
    'driver_longitude', v_driver_lng
  );
END;
$$;

-- Allow unauthenticated (anon) guests to call this function
GRANT EXECUTE ON FUNCTION public.get_shared_trip_details(text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_shared_trip_details(text, text, text, text) TO authenticated;
