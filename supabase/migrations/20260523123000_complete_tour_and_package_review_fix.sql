-- Completes the package review setup and tightens package tour completion.

CREATE TABLE IF NOT EXISTS public.package_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES public.package_bookings(id) ON DELETE CASCADE,
  package_id bigint REFERENCES public.tour_packages(id) ON DELETE SET NULL,
  tourist_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review_text text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'package_reviews'
      AND column_name = 'package_id'
      AND data_type = 'uuid'
  ) THEN
    ALTER TABLE public.package_reviews
      DROP CONSTRAINT IF EXISTS package_reviews_package_id_fkey;
    ALTER TABLE public.package_reviews
      ALTER COLUMN package_id TYPE bigint USING NULL;
    ALTER TABLE public.package_reviews
      ADD CONSTRAINT package_reviews_package_id_fkey
      FOREIGN KEY (package_id) REFERENCES public.tour_packages(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS package_reviews_booking_tourist_idx
  ON public.package_reviews (booking_id, tourist_id);

CREATE INDEX IF NOT EXISTS package_reviews_package_idx
  ON public.package_reviews (package_id);

CREATE INDEX IF NOT EXISTS package_reviews_tourist_idx
  ON public.package_reviews (tourist_id);

ALTER TABLE public.package_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS package_reviews_select_own ON public.package_reviews;
CREATE POLICY package_reviews_select_own ON public.package_reviews
  FOR SELECT TO authenticated
  USING (
    tourist_id = auth.uid()
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('admin', 'super_admin', 'operator')
    )
  );

DROP POLICY IF EXISTS package_reviews_insert_own ON public.package_reviews;
CREATE POLICY package_reviews_insert_own ON public.package_reviews
  FOR INSERT TO authenticated
  WITH CHECK (tourist_id = auth.uid());

DROP POLICY IF EXISTS package_reviews_update_own ON public.package_reviews;
CREATE POLICY package_reviews_update_own ON public.package_reviews
  FOR UPDATE TO authenticated
  USING (tourist_id = auth.uid())
  WITH CHECK (tourist_id = auth.uid());

CREATE OR REPLACE FUNCTION public.touch_package_reviews_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS package_reviews_updated_at ON public.package_reviews;
CREATE TRIGGER package_reviews_updated_at
BEFORE UPDATE ON public.package_reviews
FOR EACH ROW EXECUTE FUNCTION public.touch_package_reviews_updated_at();

CREATE OR REPLACE FUNCTION public.tourist_has_reviewed_booking(p_booking_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.driver_reviews
    WHERE booking_id = p_booking_id
      AND tourist_id = auth.uid()
  )
  AND EXISTS (
    SELECT 1
    FROM public.package_reviews
    WHERE booking_id = p_booking_id
      AND tourist_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.complete_package_tour(
  p_activity_id uuid,
  p_remaining_payment_method text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_id uuid := auth.uid();
  v_activity public.package_activities;
  v_booking public.package_bookings;
  v_total_items integer := 0;
  v_completed_items integer := 0;
BEGIN
  IF v_driver_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED';
  END IF;

  SELECT *
  INTO v_activity
  FROM public.package_activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACTIVITY_NOT_FOUND';
  END IF;

  IF v_activity.driver_id <> v_driver_id THEN
    RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER';
  END IF;

  SELECT *
  INTO v_booking
  FROM public.package_bookings
  WHERE id = v_activity.booking_id
  FOR UPDATE;

  SELECT COUNT(*)
  INTO v_total_items
  FROM public.booking_itinerary_items
  WHERE booking_id = v_booking.id;

  SELECT COUNT(*)
  INTO v_completed_items
  FROM public.booking_itinerary_items
  WHERE booking_id = v_booking.id
    AND LOWER(COALESCE(spot_status, 'pending')) = 'completed';

  IF v_total_items = 0 OR v_completed_items < v_total_items THEN
    RAISE EXCEPTION 'INCOMPLETE_ITINERARY';
  END IF;

  IF v_activity.dropped_off_at IS NULL
     AND LOWER(COALESCE(v_activity.tour_status, '')) <> 'ready_to_complete' THEN
    RAISE EXCEPTION 'DROPOFF_NOT_COMPLETED';
  END IF;

  IF COALESCE(v_booking.remaining_balance, 0) > 0
     AND v_booking.booking_type = 'advanced'
     AND COALESCE(p_remaining_payment_method, '') = 'cash' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.payments
      WHERE booking_id = v_booking.id
        AND payment_type = 'remaining_balance'
        AND payment_status IN ('paid', 'completed')
    ) THEN
      INSERT INTO public.payments (
        booking_id,
        user_id,
        amount,
        payment_method,
        payment_status,
        payment_type,
        paid_at
      ) VALUES (
        v_booking.id,
        v_booking.tourist_id,
        v_booking.remaining_balance,
        'cash',
        'paid',
        'remaining_balance',
        now()
      );
    END IF;

    PERFORM public.credit_driver_wallet(
      v_driver_id,
      v_booking.remaining_balance,
      v_booking.id,
      'Remaining cash balance for booking ' || v_booking.id,
      'remaining_cash_payment'
    );
  END IF;

  UPDATE public.package_activities
  SET status = 'completed',
      tour_status = 'completed',
      current_spot_index = v_total_items,
      dropped_off_at = COALESCE(dropped_off_at, now()),
      updated_at = now()
  WHERE id = p_activity_id;

  UPDATE public.package_bookings
  SET status = 'completed',
      booking_status = 'completed',
      current_spot_index = v_total_items,
      completed_at = COALESCE(completed_at, now()),
      updated_at = now()
  WHERE id = v_booking.id;

  UPDATE public.package_activities
  SET dropped_off_at = COALESCE(dropped_off_at, now())
  WHERE id = p_activity_id;

  UPDATE public.booking_drivers
  SET status = 'completed',
      completed_at = COALESCE(completed_at, now())
  WHERE booking_id = v_booking.id
    AND driver_id = v_driver_id
    AND status = 'accepted';

  RETURN jsonb_build_object(
    'success', true,
    'activity_id', v_activity.id,
    'booking_id', v_booking.id,
    'completed_items', v_completed_items,
    'total_items', v_total_items
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_package_tour(uuid, text) TO authenticated;
