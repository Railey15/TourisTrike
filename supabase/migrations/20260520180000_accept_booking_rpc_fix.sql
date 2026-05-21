-- ── 1. Drop activity_id from booking_drivers (was causing FK insert failures) ─
ALTER TABLE public.booking_drivers
  DROP COLUMN IF EXISTS activity_id;

-- ── 2. Add is_verified to profiles ───────────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_verified boolean NOT NULL DEFAULT false;

-- ── 3. Recreate RLS policies on booking_drivers ───────────────────────────────
-- SECURITY DEFINER RPCs bypass RLS, but direct client queries need these.
ALTER TABLE public.booking_drivers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "booking_drivers_read_all"      ON public.booking_drivers;
DROP POLICY IF EXISTS "booking_drivers_driver_insert" ON public.booking_drivers;
DROP POLICY IF EXISTS "booking_drivers_driver_update" ON public.booking_drivers;

CREATE POLICY "booking_drivers_read_all" ON public.booking_drivers
  FOR SELECT USING (true);

CREATE POLICY "booking_drivers_driver_insert" ON public.booking_drivers
  FOR INSERT WITH CHECK (auth.uid() = driver_id);

CREATE POLICY "booking_drivers_driver_update" ON public.booking_drivers
  FOR UPDATE USING (auth.uid() = driver_id);

-- ── 4. accept_package_booking(p_booking_id) — single-param RPC ───────────────
-- Replaces driver_accept_group_booking. Looks up the activity internally.
-- Uses is_online OR is_available so either flag suffices.
-- Recounts actual booking_drivers rows (avoids stale counter bugs).
CREATE OR REPLACE FUNCTION public.accept_package_booking(
  p_booking_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_id     uuid := auth.uid();
  v_driver        public.profiles;
  v_booking       public.package_bookings;
  v_activity_id   uuid;
  v_live_count    integer;
  v_new_count     integer;
  v_wallet_amount numeric := 0;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────────────────────
  IF v_driver_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED';
  END IF;

  SELECT * INTO v_driver FROM public.profiles WHERE id = v_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'DRIVER_NOT_FOUND';
  END IF;
  IF v_driver.role <> 'driver' THEN
    RAISE EXCEPTION 'DRIVER_ROLE_REQUIRED';
  END IF;
  -- Accept if online OR available (either flag suffices)
  IF NOT (COALESCE(v_driver.is_online, false) OR COALESCE(v_driver.is_available, false)) THEN
    RAISE EXCEPTION 'DRIVER_NOT_AVAILABLE';
  END IF;

  -- ── Load & lock booking ───────────────────────────────────────────────────
  SELECT * INTO v_booking
  FROM public.package_bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;

  -- Only accept bookings that are pending or waiting for drivers
  IF v_booking.booking_status NOT IN ('pending', 'waiting_for_drivers') THEN
    RAISE EXCEPTION 'BOOKING_NOT_AVAILABLE';
  END IF;

  -- Municipality check — only if booking has a municipality set
  IF v_booking.municipality IS NOT NULL
     AND TRIM(v_booking.municipality) <> ''
  THEN
    IF TRIM(LOWER(COALESCE(v_driver.city, ''))) <> TRIM(LOWER(v_booking.municipality)) THEN
      RAISE EXCEPTION 'MUNICIPALITY_MISMATCH: Booking is for % only.', v_booking.municipality;
    END IF;
  END IF;

  -- ── Live recount (avoids stale counter bugs) ──────────────────────────────
  SELECT COUNT(*) INTO v_live_count
  FROM public.booking_drivers
  WHERE booking_id = p_booking_id AND status = 'accepted';

  IF v_live_count >= COALESCE(v_booking.required_drivers, 1) THEN
    RAISE EXCEPTION 'BOOKING_ALREADY_FULL';
  END IF;

  -- Duplicate acceptance guard
  IF EXISTS (
    SELECT 1 FROM public.booking_drivers
    WHERE booking_id = p_booking_id AND driver_id = v_driver_id
  ) THEN
    RAISE EXCEPTION 'ALREADY_ACCEPTED';
  END IF;

  -- ── Look up activity for this booking (may be NULL for legacy bookings) ───
  SELECT id INTO v_activity_id
  FROM public.package_activities
  WHERE booking_id = p_booking_id
  LIMIT 1;

  -- ── Record driver slot ────────────────────────────────────────────────────
  INSERT INTO public.booking_drivers
    (booking_id, driver_id, status, accepted_at)
  VALUES
    (p_booking_id, v_driver_id, 'accepted', now());

  v_new_count := v_live_count + 1;

  -- ── Branch: all slots filled vs. still waiting ────────────────────────────
  IF v_new_count >= COALESCE(v_booking.required_drivers, 1) THEN
    -- Activate tour
    IF v_activity_id IS NOT NULL THEN
      UPDATE public.package_activities
      SET driver_id   = v_driver_id,
          status      = 'accepted',
          tour_status = 'driver_accepted',
          accepted_at = now(),
          updated_at  = now()
      WHERE id = v_activity_id;
    END IF;

    UPDATE public.package_bookings
    SET assigned_driver_id     = v_driver_id,
        accepted_drivers_count = v_new_count,
        status                 = 'confirmed',
        booking_status         = 'accepted',
        accepted_at            = now(),
        updated_at             = now()
    WHERE id = p_booking_id;

    -- Credit wallet payment if applicable
    SELECT COALESCE(SUM(amount), 0)
    INTO v_wallet_amount
    FROM public.payments
    WHERE booking_id     = p_booking_id
      AND payment_method = 'wallet'
      AND payment_type   IN ('full_payment', 'down_payment')
      AND payment_status IN ('paid', 'completed', 'fully_paid', 'dp_paid');

    IF v_wallet_amount > 0 THEN
      BEGIN
        PERFORM public.credit_driver_wallet(
          v_driver_id,
          v_wallet_amount,
          p_booking_id,
          'Initial wallet payment for booking ' || p_booking_id,
          'initial_wallet_payment'
        );
      EXCEPTION WHEN OTHERS THEN
        -- Non-fatal: wallet credit failure should not block booking acceptance
        NULL;
      END;
    END IF;
  ELSE
    -- Still waiting for more drivers
    UPDATE public.package_bookings
    SET accepted_drivers_count = v_new_count,
        booking_status         = 'waiting_for_drivers',
        updated_at             = now()
    WHERE id = p_booking_id;
  END IF;

  RETURN jsonb_build_object(
    'success',        true,
    'booking_id',     p_booking_id,
    'accepted_count', v_new_count,
    'required_count', COALESCE(v_booking.required_drivers, 1),
    'all_filled',     v_new_count >= COALESCE(v_booking.required_drivers, 1)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_package_booking TO authenticated;
