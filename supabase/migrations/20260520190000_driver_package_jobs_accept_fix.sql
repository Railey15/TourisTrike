-- ── 1. Mark completed booking_drivers rows as completed ──────────────────────
-- booking_drivers.status stays 'accepted' forever — no code updated it after
-- a tour finished, permanently blocking the driver from accepting new jobs.
UPDATE public.booking_drivers bd
SET status = 'completed'
WHERE bd.status = 'accepted'
  AND EXISTS (
    SELECT 1 FROM public.package_bookings pb
    WHERE pb.id = bd.booking_id
      AND LOWER(pb.booking_status) IN ('completed', 'done', 'cancelled')
  );

-- ── 2. Normalize completed package_activities ─────────────────────────────────
-- Any activity whose tour_status is terminal should also have status=completed.
UPDATE public.package_activities
SET status     = 'completed',
    updated_at = now()
WHERE status NOT IN ('completed', 'cancelled')
  AND LOWER(tour_status) IN ('completed', 'done', 'dropped_off');

-- ── 3. Fix itinerary ordering ─────────────────────────────────────────────────
-- Back-fill order_number from destination_order where order_number is 0/null
-- so spot indexing (markSpotActual* uses order_number + 1) is consistent.
UPDATE public.booking_itinerary_items
SET order_number = destination_order
WHERE (order_number IS NULL OR order_number = 0)
  AND destination_order IS NOT NULL
  AND destination_order > 0;

-- ── 4. Trigger: keep booking_drivers in sync when booking completes ───────────
CREATE OR REPLACE FUNCTION public.sync_booking_drivers_on_complete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.booking_status IN ('completed', 'done', 'cancelled') THEN
    UPDATE public.booking_drivers
    SET status = CASE
          WHEN NEW.booking_status = 'cancelled' THEN 'rejected'
          ELSE 'completed'
        END
    WHERE booking_id = NEW.id
      AND status = 'accepted';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_booking_drivers ON public.package_bookings;
CREATE TRIGGER trg_sync_booking_drivers
  AFTER UPDATE OF booking_status ON public.package_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_booking_drivers_on_complete();
