-- Allow accepted drivers (via booking_drivers OR assigned_driver_id) to UPDATE
-- booking_itinerary_items rows for their booking.
-- Without this policy, markSpotActualArrival/Departure fail silently (no rows
-- updated) because only SELECT was previously covered for group-booking drivers.

DROP POLICY IF EXISTS booking_itinerary_items_update ON public.booking_itinerary_items;
CREATE POLICY booking_itinerary_items_update ON public.booking_itinerary_items
FOR UPDATE TO authenticated USING (
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
);
