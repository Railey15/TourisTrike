-- Driver reviews table and profile rating columns.
-- Tourists rate drivers after tour completion. Unique per (booking, tourist).
-- A trigger keeps profiles.average_rating and profiles.total_reviews in sync.

CREATE TABLE IF NOT EXISTS public.driver_reviews (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id  uuid        NOT NULL REFERENCES public.package_bookings(id) ON DELETE CASCADE,
  driver_id   uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tourist_id  uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating      smallint    NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review_text text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (booking_id, tourist_id)
);

CREATE INDEX IF NOT EXISTS driver_reviews_driver_idx  ON public.driver_reviews(driver_id);
CREATE INDEX IF NOT EXISTS driver_reviews_tourist_idx ON public.driver_reviews(tourist_id);
CREATE INDEX IF NOT EXISTS driver_reviews_booking_idx ON public.driver_reviews(booking_id);

-- Add rating columns to profiles (safe to run multiple times)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS average_rating numeric(3,2) DEFAULT 0 NOT NULL,
  ADD COLUMN IF NOT EXISTS total_reviews  integer      DEFAULT 0 NOT NULL;

-- Trigger function: recalculate a driver's aggregate rating after any change
CREATE OR REPLACE FUNCTION public.update_driver_average_rating()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_driver_id uuid;
BEGIN
  v_driver_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.driver_id ELSE NEW.driver_id END;

  UPDATE public.profiles
  SET
    average_rating = COALESCE(
      (SELECT ROUND(AVG(rating)::numeric, 2) FROM public.driver_reviews WHERE driver_id = v_driver_id),
      0
    ),
    total_reviews = (SELECT COUNT(*) FROM public.driver_reviews WHERE driver_id = v_driver_id),
    updated_at    = now()
  WHERE id = v_driver_id;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_driver_rating ON public.driver_reviews;
CREATE TRIGGER trg_update_driver_rating
  AFTER INSERT OR UPDATE OR DELETE ON public.driver_reviews
  FOR EACH ROW EXECUTE FUNCTION public.update_driver_average_rating();

-- RLS
ALTER TABLE public.driver_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS driver_reviews_select ON public.driver_reviews;
CREATE POLICY driver_reviews_select ON public.driver_reviews
  FOR SELECT TO authenticated
  USING (
    tourist_id = auth.uid()
    OR driver_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

DROP POLICY IF EXISTS driver_reviews_insert ON public.driver_reviews;
CREATE POLICY driver_reviews_insert ON public.driver_reviews
  FOR INSERT TO authenticated
  WITH CHECK (tourist_id = auth.uid());

DROP POLICY IF EXISTS driver_reviews_update ON public.driver_reviews;
CREATE POLICY driver_reviews_update ON public.driver_reviews
  FOR UPDATE TO authenticated
  USING   (tourist_id = auth.uid())
  WITH CHECK (tourist_id = auth.uid());
