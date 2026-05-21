-- ── 1. Fix package_bookings SELECT policy ────────────────────────────────────
-- Allow accepted drivers (via booking_drivers) to read bookings, not just
-- assigned_driver_id. Group-booking drivers could not read the booking at all.
DROP POLICY IF EXISTS package_bookings_select ON public.package_bookings;
CREATE POLICY package_bookings_select ON public.package_bookings
FOR SELECT TO authenticated USING (
  tourist_id = auth.uid()
  OR assigned_driver_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.booking_drivers bd
    WHERE bd.booking_id = id
      AND bd.driver_id = auth.uid()
      AND bd.status = 'accepted'
  )
  OR public.current_profile_role() = 'admin'
  OR EXISTS (
    SELECT 1 FROM public.tour_packages p
    WHERE p.id = package_id
      AND p.city = public.current_profile_city()
  )
);

-- ── 2. Fix booking_itinerary_items SELECT policy ──────────────────────────────
-- Allow any accepted driver (via booking_drivers) to read itinerary items, not
-- just assigned_driver_id. Group-booking drivers were blocked before this.
DROP POLICY IF EXISTS booking_itinerary_items_select ON public.booking_itinerary_items;
CREATE POLICY booking_itinerary_items_select ON public.booking_itinerary_items
FOR SELECT TO authenticated USING (
  tourist_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.package_bookings b
    WHERE b.id = booking_id
      AND b.assigned_driver_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.booking_drivers bd
    WHERE bd.booking_id = booking_id
      AND bd.driver_id = auth.uid()
      AND bd.status = 'accepted'
  )
  OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'
  )
  OR (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'subtenant'
    )
    AND EXISTS (
      SELECT 1
      FROM public.package_bookings b
      JOIN public.tour_packages pkg ON pkg.id = b.package_id
      WHERE b.id = booking_id
        AND pkg.city = public.current_profile_city()
    )
  )
);

-- ── 2. ensure_booking_itinerary(p_booking_id) ─────────────────────────────────
-- Auto-populates booking_itinerary_items when a booking has none.
-- Falls back: customized_package_spots -> tour_package_spots.
-- Safe to call multiple times (uses ON CONFLICT DO NOTHING).
CREATE OR REPLACE FUNCTION public.ensure_booking_itinerary(p_booking_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count   integer;
  v_booking public.package_bookings;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM public.booking_itinerary_items
  WHERE booking_id = p_booking_id;

  IF v_count > 0 THEN
    RETURN v_count;
  END IF;

  SELECT * INTO v_booking
  FROM public.package_bookings
  WHERE id = p_booking_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  -- Try customized_package_spots first
  INSERT INTO public.booking_itinerary_items (
    booking_id, tourist_id, spot_id, destination_name, destination_address,
    order_number, destination_order,
    latitude, longitude, google_place_id,
    source_type, itinerary_source, municipality, barangay, image_url
  )
  SELECT
    p_booking_id,
    v_booking.tourist_id,
    cps.spot_id,
    COALESCE(NULLIF(TRIM(cps.spot_title), ''), 'Unnamed Spot'),
    COALESCE(NULLIF(TRIM(cps.spot_address), ''), ''),
    (cps.sort_order + 1),
    (cps.sort_order + 1),
    cps.latitude,
    cps.longitude,
    cps.google_place_id,
    COALESCE(cps.source_type, 'manual'),
    COALESCE(cps.source_type, 'manual'),
    cps.municipality,
    cps.barangay,
    cps.image_url
  FROM public.customized_package_spots cps
  WHERE cps.booking_id = p_booking_id
    AND cps.action_type IN ('kept', 'added')
  ORDER BY cps.sort_order
  ON CONFLICT (booking_id, destination_order) DO NOTHING;

  SELECT COUNT(*) INTO v_count
  FROM public.booking_itinerary_items
  WHERE booking_id = p_booking_id;

  IF v_count > 0 THEN
    RETURN v_count;
  END IF;

  -- Fall back to tour_package_spots
  INSERT INTO public.booking_itinerary_items (
    booking_id, tourist_id, spot_id, destination_name, destination_address,
    order_number, destination_order,
    latitude, longitude, source_type, itinerary_source, municipality, barangay
  )
  SELECT
    p_booking_id,
    v_booking.tourist_id,
    tps.spot_id,
    COALESCE(NULLIF(TRIM(ts.title), ''), 'Unnamed Spot'),
    COALESCE(NULLIF(TRIM(ts.address), ''), ''),
    ROW_NUMBER() OVER (ORDER BY tps.sort_order, tps.spot_id),
    ROW_NUMBER() OVER (ORDER BY tps.sort_order, tps.spot_id),
    ts.latitude,
    ts.longitude,
    'package',
    'package',
    ts.municipality,
    ts.barangay
  FROM public.tour_package_spots tps
  LEFT JOIN public.tourist_spots ts ON ts.id = tps.spot_id
  WHERE tps.package_id = v_booking.package_id
  ORDER BY tps.sort_order
  ON CONFLICT (booking_id, destination_order) DO NOTHING;

  SELECT COUNT(*) INTO v_count
  FROM public.booking_itinerary_items
  WHERE booking_id = p_booking_id;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_booking_itinerary(uuid) TO authenticated;
