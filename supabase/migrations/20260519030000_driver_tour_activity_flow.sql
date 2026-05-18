-- Driver tour activity flow, booking sync, and wallet-credit safeguards.

-- Booking lifecycle mirrors activity tracking for simpler realtime reads.
ALTER TABLE public.package_bookings
  ADD COLUMN IF NOT EXISTS booking_status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS current_spot_index integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS driver_latitude double precision,
  ADD COLUMN IF NOT EXISTS driver_longitude double precision,
  ADD COLUMN IF NOT EXISTS accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS arrived_at timestamptz,
  ADD COLUMN IF NOT EXISTS picked_up_at timestamptz;

ALTER TABLE public.package_activities
  ADD COLUMN IF NOT EXISTS arrived_at timestamptz;

ALTER TABLE public.wallet_transactions
  ADD COLUMN IF NOT EXISTS reference_key text;

CREATE UNIQUE INDEX IF NOT EXISTS wallet_transactions_booking_ref_unique
  ON public.wallet_transactions (user_id, booking_id, type, COALESCE(reference_key, ''))
  WHERE booking_id IS NOT NULL AND status = 'completed';

-- Allow tourists to read driver details for drivers assigned to their own bookings.
DROP POLICY IF EXISTS "Tourists can view assigned driver details" ON public.driver_details;
CREATE POLICY "Tourists can view assigned driver details"
  ON public.driver_details
  FOR SELECT
  TO authenticated
  USING (
    driver_id = auth.uid()
    OR EXISTS (
      SELECT 1
      FROM public.package_bookings b
      WHERE b.assigned_driver_id = driver_details.driver_id
        AND b.tourist_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role IN ('admin', 'subtenant')
    )
  );

CREATE OR REPLACE FUNCTION public.deduct_wallet_balance(
  p_user_id uuid,
  p_role text,
  p_amount numeric,
  p_booking_id uuid,
  p_transaction_type text,
  p_description text DEFAULT '',
  p_reference_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet_id uuid;
  v_current_balance numeric;
  v_transaction_id uuid;
BEGIN
  SELECT id, balance
  INTO v_wallet_id, v_current_balance
  FROM public.wallets
  WHERE user_id = p_user_id AND role = p_role
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'WALLET_NOT_FOUND';
  END IF;

  IF v_current_balance < p_amount THEN
    RAISE EXCEPTION 'INSUFFICIENT_BALANCE: balance=%, required=%',
      v_current_balance, p_amount;
  END IF;

  IF p_booking_id IS NOT NULL AND p_reference_key IS NOT NULL THEN
    SELECT id
    INTO v_transaction_id
    FROM public.wallet_transactions
    WHERE user_id = p_user_id
      AND booking_id = p_booking_id
      AND type = p_transaction_type
      AND COALESCE(reference_key, '') = COALESCE(p_reference_key, '')
      AND status = 'completed'
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_transaction_id,
        'new_balance', v_current_balance,
        'duplicate', true
      );
    END IF;
  END IF;

  UPDATE public.wallets
  SET balance = balance - p_amount,
      updated_at = now()
  WHERE id = v_wallet_id;

  INSERT INTO public.wallet_transactions
    (wallet_id, user_id, role, type, amount, status,
     payment_method, booking_id, description, reference_key)
  VALUES
    (v_wallet_id, p_user_id, p_role, p_transaction_type, p_amount,
     'completed', 'wallet', p_booking_id, p_description, p_reference_key)
  RETURNING id INTO v_transaction_id;

  RETURN jsonb_build_object(
    'success', true,
    'transaction_id', v_transaction_id,
    'new_balance', v_current_balance - p_amount
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.credit_driver_wallet(
  p_driver_id uuid,
  p_amount numeric,
  p_booking_id uuid,
  p_description text DEFAULT '',
  p_reference_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet_id uuid;
  v_transaction_id uuid;
  v_existing_balance numeric;
BEGIN
  INSERT INTO public.wallets (user_id, role, balance)
  VALUES (p_driver_id, 'driver', 0)
  ON CONFLICT (user_id, role) DO NOTHING;

  SELECT id, balance
  INTO v_wallet_id, v_existing_balance
  FROM public.wallets
  WHERE user_id = p_driver_id AND role = 'driver'
  FOR UPDATE;

  IF p_booking_id IS NOT NULL AND p_reference_key IS NOT NULL THEN
    SELECT id
    INTO v_transaction_id
    FROM public.wallet_transactions
    WHERE user_id = p_driver_id
      AND booking_id = p_booking_id
      AND type = 'driver_earning'
      AND COALESCE(reference_key, '') = COALESCE(p_reference_key, '')
      AND status = 'completed'
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_transaction_id,
        'new_balance', v_existing_balance,
        'duplicate', true
      );
    END IF;
  END IF;

  UPDATE public.wallets
  SET balance = balance + p_amount,
      updated_at = now()
  WHERE id = v_wallet_id;

  INSERT INTO public.wallet_transactions
    (wallet_id, user_id, role, type, amount, status,
     payment_method, booking_id, description, reference_key)
  VALUES
    (v_wallet_id, p_driver_id, 'driver', 'driver_earning', p_amount,
     'completed', 'wallet', p_booking_id, p_description, p_reference_key)
  RETURNING id INTO v_transaction_id;

  RETURN jsonb_build_object(
    'success', true,
    'transaction_id', v_transaction_id,
    'new_balance', v_existing_balance + p_amount
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.driver_accept_package_activity(
  p_activity_id uuid
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
  v_initial_wallet_amount numeric := 0;
BEGIN
  IF v_driver_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = v_driver_id AND role = 'driver'
  ) THEN
    RAISE EXCEPTION 'DRIVER_ROLE_REQUIRED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.package_activities a
    WHERE a.driver_id = v_driver_id
      AND a.id <> p_activity_id
      AND a.status IN ('accepted', 'ongoing')
      AND a.tour_status NOT IN ('completed', 'dropped_off')
  ) THEN
    RAISE EXCEPTION 'ACTIVE_TOUR_EXISTS';
  END IF;

  SELECT *
  INTO v_activity
  FROM public.package_activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACTIVITY_NOT_FOUND';
  END IF;

  IF v_activity.driver_id IS NOT NULL THEN
    RAISE EXCEPTION 'BOOKING_ALREADY_ASSIGNED';
  END IF;

  SELECT *
  INTO v_booking
  FROM public.package_bookings
  WHERE id = v_activity.booking_id
  FOR UPDATE;

  UPDATE public.package_activities
  SET driver_id = v_driver_id,
      status = 'accepted',
      tour_status = 'driver_accepted',
      accepted_at = now(),
      updated_at = now()
  WHERE id = p_activity_id;

  UPDATE public.package_bookings
  SET assigned_driver_id = v_driver_id,
      status = 'confirmed',
      booking_status = 'accepted',
      accepted_at = now(),
      updated_at = now()
  WHERE id = v_activity.booking_id;

  SELECT COALESCE(SUM(amount), 0)
  INTO v_initial_wallet_amount
  FROM public.payments
  WHERE booking_id = v_activity.booking_id
    AND payment_method = 'wallet'
    AND payment_type IN ('full_payment', 'down_payment')
    AND payment_status IN ('paid', 'completed', 'fully_paid', 'dp_paid');

  IF v_initial_wallet_amount > 0 THEN
    PERFORM public.credit_driver_wallet(
      v_driver_id,
      v_initial_wallet_amount,
      v_activity.booking_id,
      'Initial wallet payment for booking ' || v_activity.booking_id,
      'initial_wallet_payment'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'activity_id', v_activity.id,
    'booking_id', v_activity.booking_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.driver_accept_package_activity TO authenticated;

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
      dropped_off_at = now(),
      updated_at = now()
  WHERE id = p_activity_id;

  UPDATE public.package_bookings
  SET status = 'completed',
      booking_status = 'completed',
      completed_at = now(),
      updated_at = now()
  WHERE id = v_booking.id;

  RETURN jsonb_build_object(
    'success', true,
    'activity_id', v_activity.id,
    'booking_id', v_booking.id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_package_tour TO authenticated;
