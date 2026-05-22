-- ============================================================
-- Migration: package_reviews table + driver itinerary RLS fix
-- Date: 2026-05-23
-- ============================================================

-- ── 1. package_reviews table ─────────────────────────────────

CREATE TABLE IF NOT EXISTS public.package_reviews (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id    uuid NOT NULL REFERENCES public.package_bookings(id) ON DELETE CASCADE,
  package_id    bigint REFERENCES public.tour_packages(id) ON DELETE SET NULL,
  tourist_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating        smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review_text   text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Unique: one package review per tourist per booking
CREATE UNIQUE INDEX IF NOT EXISTS package_reviews_booking_tourist_idx
  ON public.package_reviews (booking_id, tourist_id);

-- RLS
ALTER TABLE public.package_reviews ENABLE ROW LEVEL SECURITY;

-- Tourist can insert their own review
DROP POLICY IF EXISTS "tourist_insert_own_package_review" ON public.package_reviews;
CREATE POLICY "tourist_insert_own_package_review"
  ON public.package_reviews FOR INSERT
  WITH CHECK (tourist_id = auth.uid());

-- Tourist can read their own reviews
DROP POLICY IF EXISTS "tourist_read_own_package_review" ON public.package_reviews;
CREATE POLICY "tourist_read_own_package_review"
  ON public.package_reviews FOR SELECT
  USING (tourist_id = auth.uid());

-- Tourist can update their own review (used by idempotent upserts)
DROP POLICY IF EXISTS "tourist_update_own_package_review" ON public.package_reviews;
CREATE POLICY "tourist_update_own_package_review"
  ON public.package_reviews FOR UPDATE
  USING (tourist_id = auth.uid())
  WITH CHECK (tourist_id = auth.uid());

-- Admins can read all (for reporting)
DROP POLICY IF EXISTS "admin_read_all_package_reviews" ON public.package_reviews;
CREATE POLICY "admin_read_all_package_reviews"
  ON public.package_reviews FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('admin', 'super_admin', 'operator')
    )
  );

-- ── 2. Allow drivers to read booking_itinerary_items for pending jobs ────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'booking_itinerary_items'
      AND policyname = 'driver_read_pending_itinerary_items'
  ) THEN
    CREATE POLICY "driver_read_pending_itinerary_items"
      ON public.booking_itinerary_items FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.package_activities pa
          WHERE pa.booking_id = booking_itinerary_items.booking_id
            AND pa.status IN ('pending', 'accepted', 'ongoing')
        )
        AND
        EXISTS (
          SELECT 1 FROM public.profiles
          WHERE id = auth.uid() AND role = 'driver'
        )
      );
  END IF;
END$$;

-- ── 3. Trigger to keep package_reviews.updated_at current ───

CREATE OR REPLACE FUNCTION public.touch_package_reviews_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS package_reviews_updated_at ON public.package_reviews;
CREATE TRIGGER package_reviews_updated_at
  BEFORE UPDATE ON public.package_reviews
  FOR EACH ROW EXECUTE FUNCTION public.touch_package_reviews_updated_at();

-- ── 4. Function to check if tourist has reviewed (both driver + package) ───

CREATE OR REPLACE FUNCTION public.tourist_has_reviewed_booking(p_booking_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.driver_reviews
    WHERE booking_id = p_booking_id AND tourist_id = auth.uid()
  )
  AND
  EXISTS (
    SELECT 1 FROM public.package_reviews
    WHERE booking_id = p_booking_id AND tourist_id = auth.uid()
  );
$$;
