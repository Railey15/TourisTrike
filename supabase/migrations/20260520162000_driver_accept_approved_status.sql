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
  v_driver_status text;
  v_driver_approved_at timestamptz;
  v_application_status text;
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

  SELECT lower(coalesce(status, '')), approved_at
  INTO v_driver_status, v_driver_approved_at
  FROM public.driver_details
  WHERE driver_id = v_driver_id;

  SELECT lower(coalesce(status, ''))
  INTO v_application_status
  FROM public.driver_applications
  WHERE driver_id = v_driver_id
  ORDER BY submitted_at DESC
  LIMIT 1;

  IF coalesce(v_driver_status, '') IN ('disabled', 'inactive', 'rejected', 'suspended') THEN
    RAISE EXCEPTION 'DRIVER_NOT_APPROVED';
  END IF;

  IF coalesce(v_driver_status, '') NOT IN ('active', 'approved', 'verified')
     AND NOT (coalesce(v_driver_status, '') = '' AND v_driver_approved_at IS NOT NULL)
     AND coalesce(v_application_status, '') NOT IN ('active', 'approved', 'verified') THEN
    RAISE EXCEPTION 'DRIVER_NOT_APPROVED';
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
