CREATE OR REPLACE FUNCTION public.complete_current_itinerary_item(
  p_activity_id uuid,
  p_itinerary_item_id uuid DEFAULT NULL,
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
  v_next_index integer := 0;
  v_current_item_id uuid;
  v_current_order_number integer := 0;
  v_next_item_id uuid;
  v_spot_status_list jsonb := '[]'::jsonb;
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

  IF v_total_items = 0 THEN
    RAISE EXCEPTION 'NO_ITINERARY_ITEMS';
  END IF;

  IF p_itinerary_item_id IS NOT NULL THEN
    SELECT bii.id,
           COALESCE(bii.order_number, bii.destination_order, 0)
    INTO v_current_item_id, v_current_order_number
    FROM public.booking_itinerary_items bii
    WHERE bii.id = p_itinerary_item_id
      AND bii.booking_id = v_booking.id
      AND LOWER(COALESCE(bii.spot_status, 'pending')) <> 'completed'
    FOR UPDATE;
  END IF;

  IF v_current_item_id IS NULL THEN
    SELECT item.id,
           COALESCE(item.order_number, item.destination_order, 0)
    INTO v_current_item_id, v_current_order_number
    FROM (
      SELECT bii.id,
             bii.order_number,
             bii.destination_order,
             row_number() OVER (
               ORDER BY
                 COALESCE(bii.order_number, 2147483647),
                 COALESCE(bii.destination_order, 2147483647),
                 bii.arrival_time NULLS LAST,
                 bii.created_at,
                 bii.id
             ) - 1 AS item_index
      FROM public.booking_itinerary_items bii
      WHERE bii.booking_id = v_booking.id
        AND LOWER(COALESCE(bii.spot_status, 'pending')) <> 'completed'
    ) AS item
    ORDER BY item.item_index
    LIMIT 1;
  END IF;

  IF v_current_item_id IS NULL THEN
    RAISE EXCEPTION 'CURRENT_ITINERARY_ITEM_NOT_FOUND';
  END IF;

  UPDATE public.booking_itinerary_items
  SET spot_status = 'completed',
      actual_departure_time = now(),
      updated_at = now()
  WHERE id = v_current_item_id;

  SELECT COUNT(*)
  INTO v_completed_items
  FROM public.booking_itinerary_items
  WHERE booking_id = v_booking.id
    AND LOWER(spot_status) = 'completed';

  SELECT COALESCE(
           MIN(item_index),
           v_total_items
         )
  INTO v_next_index
  FROM (
    SELECT row_number() OVER (
             ORDER BY
               COALESCE(bii.order_number, 2147483647),
               COALESCE(bii.destination_order, 2147483647),
               bii.arrival_time NULLS LAST,
               bii.created_at,
               bii.id
           ) - 1 AS item_index
    FROM public.booking_itinerary_items bii
    WHERE bii.booking_id = v_booking.id
      AND LOWER(COALESCE(bii.spot_status, 'pending')) <> 'completed'
  ) AS remaining_items;

  IF v_completed_items < v_total_items THEN
    SELECT item.id
    INTO v_next_item_id
    FROM (
      SELECT bii.id,
             row_number() OVER (
               ORDER BY
                 COALESCE(bii.order_number, 2147483647),
                 COALESCE(bii.destination_order, 2147483647),
                 bii.arrival_time NULLS LAST,
                 bii.created_at,
                 bii.id
             ) - 1 AS item_index
      FROM public.booking_itinerary_items bii
      WHERE bii.booking_id = v_booking.id
        AND LOWER(COALESCE(bii.spot_status, 'pending')) <> 'completed'
    ) AS item
    ORDER BY item.item_index
    LIMIT 1;

    IF v_next_item_id IS NOT NULL THEN
      UPDATE public.booking_itinerary_items
      SET spot_status = 'travelling',
          updated_at = now()
      WHERE id = v_next_item_id
        AND spot_status = 'pending';
    END IF;

    UPDATE public.package_activities
    SET status = 'ongoing',
        tour_status = 'on_tour',
        current_spot_index = v_next_index,
        updated_at = now()
    WHERE id = v_activity.id;

    UPDATE public.package_bookings
    SET booking_status = 'on_tour',
        current_spot_index = v_next_index,
        updated_at = now()
    WHERE id = v_booking.id;
  ELSE
    UPDATE public.package_activities
    SET status = 'ongoing',
        tour_status = 'on_tour',
        current_spot_index = v_total_items,
        updated_at = now()
    WHERE id = v_activity.id;

    UPDATE public.package_bookings
    SET booking_status = 'on_tour',
        current_spot_index = v_total_items,
        updated_at = now()
    WHERE id = v_booking.id;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'order_number', order_number,
        'destination_order', destination_order,
        'spot_status', spot_status
      )
      ORDER BY
        COALESCE(order_number, 2147483647),
        COALESCE(destination_order, 2147483647),
        arrival_time NULLS LAST,
        created_at,
        id
    ),
    '[]'::jsonb
  )
  INTO v_spot_status_list
  FROM public.booking_itinerary_items
  WHERE booking_id = v_booking.id;

  RETURN jsonb_build_object(
    'success', true,
    'booking_id', v_booking.id,
    'activity_id', v_activity.id,
    'completed_items', v_completed_items,
    'total_items', v_total_items,
    'current_spot_index', v_next_index,
    'current_itinerary_item_id', v_current_item_id,
    'current_order_number', v_current_order_number,
    'tour_completed', false,
    'package_activities_status',
      'ongoing',
    'package_bookings_status',
      COALESCE(v_booking.status, 'confirmed'),
    'package_bookings_booking_status',
      'on_tour',
    'spot_status_list', v_spot_status_list
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_current_itinerary_item(
  p_activity_id uuid,
  p_remaining_payment_method text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.complete_current_itinerary_item(
    p_activity_id,
    NULL,
    p_remaining_payment_method
  );
$$;

GRANT EXECUTE ON FUNCTION public.complete_current_itinerary_item(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_current_itinerary_item(uuid, uuid, text) TO authenticated;

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
    AND LOWER(spot_status) = 'completed';

  IF v_total_items = 0 OR v_completed_items < v_total_items THEN
    RAISE EXCEPTION 'INCOMPLETE_ITINERARY';
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
