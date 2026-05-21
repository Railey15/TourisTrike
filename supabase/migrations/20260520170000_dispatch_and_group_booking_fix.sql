-- ── 1. Municipality, province, total_passengers on bookings ──────────────────
ALTER TABLE public.package_bookings
  ADD COLUMN IF NOT EXISTS municipality    text,
  ADD COLUMN IF NOT EXISTS province        text,
  ADD COLUMN IF NOT EXISTS total_passengers integer NOT NULL DEFAULT 0;

-- ── 2. Ensure booking_status has waiting_for_drivers path ────────────────────
-- Drop and recreate the constraint to include the new status value.
ALTER TABLE public.package_bookings
  DROP CONSTRAINT IF EXISTS package_bookings_booking_status_check;
ALTER TABLE public.package_bookings
  DROP CONSTRAINT IF EXISTS package_bookings_status_check;

-- ── 3. is_available on profiles (driver availability separate from is_online) ─
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_available boolean NOT NULL DEFAULT false;

-- Back-fill: drivers who are online are also available
UPDATE public.profiles SET is_available = true WHERE role = 'driver' AND is_online = true;

-- ── 4. Enable Realtime on package_bookings and booking_drivers ────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'package_bookings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.package_bookings;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'booking_drivers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.booking_drivers;
  END IF;
END $$;

-- ── 5. driver_accept_group_booking RPC ───────────────────────────────────────
-- Replaces driver_accept_package_activity for all bookings.
-- Handles group bookings: validates municipality, prevents over-acceptance,
-- keeps booking as waiting_for_drivers until all slots are filled.
CREATE OR REPLACE FUNCTION public.driver_accept_group_booking(
  p_activity_id uuid,
  p_booking_id  uuid
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
  v_activity      public.package_activities;
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
  IF NOT COALESCE(v_driver.is_online, false) THEN
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

  -- Municipality check: only if booking has municipality set
  IF v_booking.municipality IS NOT NULL
     AND TRIM(v_booking.municipality) <> ''
     AND TRIM(LOWER(v_driver.city)) <> TRIM(LOWER(v_booking.municipality))
  THEN
    RAISE EXCEPTION 'MUNICIPALITY_MISMATCH: Booking is for % only.', v_booking.municipality;
  END IF;

  -- Over-acceptance guard
  IF v_booking.accepted_drivers_count >= v_booking.required_drivers THEN
    RAISE EXCEPTION 'BOOKING_ALREADY_FULL';
  END IF;

  -- Duplicate acceptance guard
  IF EXISTS (
    SELECT 1 FROM public.booking_drivers
    WHERE booking_id = p_booking_id AND driver_id = v_driver_id
  ) THEN
    RAISE EXCEPTION 'ALREADY_ACCEPTED';
  END IF;

  -- ── Load activity ─────────────────────────────────────────────────────────
  SELECT * INTO v_activity
  FROM public.package_activities
  WHERE id = p_activity_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACTIVITY_NOT_FOUND';
  END IF;

  -- ── Record driver slot ────────────────────────────────────────────────────
  INSERT INTO public.booking_drivers
    (booking_id, driver_id, activity_id, status, accepted_at)
  VALUES
    (p_booking_id, v_driver_id, p_activity_id, 'accepted', now());

  v_new_count := v_booking.accepted_drivers_count + 1;

  -- ── Branch: all slots filled vs. still waiting ────────────────────────────
  IF v_new_count >= v_booking.required_drivers THEN
    -- All drivers confirmed — activate tour
    UPDATE public.package_activities
    SET driver_id    = v_driver_id,
        status       = 'accepted',
        tour_status  = 'driver_accepted',
        accepted_at  = now(),
        updated_at   = now()
    WHERE id = p_activity_id;

    UPDATE public.package_bookings
    SET assigned_driver_id    = v_driver_id,
        accepted_drivers_count = v_new_count,
        status                = 'confirmed',
        booking_status        = 'accepted',
        accepted_at           = now(),
        updated_at            = now()
    WHERE id = p_booking_id;

    -- Credit wallet down-payment to driver if applicable
    SELECT COALESCE(SUM(amount), 0)
    INTO v_wallet_amount
    FROM public.payments
    WHERE booking_id     = p_booking_id
      AND payment_method = 'wallet'
      AND payment_type   IN ('full_payment', 'down_payment')
      AND payment_status IN ('paid', 'completed', 'fully_paid', 'dp_paid');

    IF v_wallet_amount > 0 THEN
      PERFORM public.credit_driver_wallet(
        v_driver_id,
        v_wallet_amount,
        p_booking_id,
        'Initial wallet payment for booking ' || p_booking_id,
        'initial_wallet_payment'
      );
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
    'activity_id',    p_activity_id,
    'booking_id',     p_booking_id,
    'accepted_count', v_new_count,
    'required_count', v_booking.required_drivers,
    'all_filled',     v_new_count >= v_booking.required_drivers
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.driver_accept_group_booking TO authenticated;
