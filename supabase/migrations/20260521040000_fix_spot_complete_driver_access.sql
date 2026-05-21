-- Fix complete_current_itinerary_item to allow ALL assigned drivers, not just
-- package_activities.driver_id. The old check blocked group-booking drivers
-- (who are in booking_drivers but not the single driver_id on the activity)
-- and any booking where driver_id was never set on the activity row.

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
  v_driver_id           uuid := auth.uid();
  v_activity            public.package_activities;
  v_booking             public.package_bookings;
  v_total_items         integer := 0;
  v_completed_items     integer := 0;
  v_next_index          integer := 0;
  v_current_item_id     uuid;
  v_current_order_number integer := 0;
  v_next_item_id        uuid;
  v_spot_status_list    jsonb := '[]'::jsonb;
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

  -- Allow: the direct driver_id on activity, or the booking's assigned_driver_id,
  -- or any driver accepted via booking_drivers. This covers single-driver and
  -- group-booking flows without requiring package_activities.driver_id to be set.
  IF NOT (
    v_activity.driver_id = v_driver_id
    OR EXISTS (
      SELECT 1 FROM public.package_bookings pb
      WHERE pb.id = v_activity.booking_id
        AND pb.assigned_driver_id = v_driver_id
    )
    OR EXISTS (
      SELECT 1 FROM public.booking_drivers bd
      WHERE bd.booking_id = v_activity.booking_id
        AND bd.driver_id = v_driver_id
        AND bd.status = 'accepted'
    )
  ) THEN
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

  -- Resolve which item to complete: use the provided ID if given and not yet done.
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

  -- Fall back to the first incomplete item ordered by sequence.
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

  -- Mark the current item as completed.
  UPDATE public.booking_itinerary_items
  SET spot_status          = 'completed',
      actual_departure_time = COALESCE(actual_departure_time, now()),
      updated_at            = now()
  WHERE id = v_current_item_id;

  SELECT COUNT(*)
  INTO v_completed_items
  FROM public.booking_itinerary_items
  WHERE booking_id = v_booking.id
    AND LOWER(spot_status) = 'completed';

  -- Determine the next spot index for activity/booking state.
  SELECT COALESCE(MIN(item_index), v_total_items)
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
    -- Mark the next pending item as travelling so the driver UI advances.
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
          updated_at  = now()
      WHERE id         = v_next_item_id
        AND spot_status = 'pending';
    END IF;

    UPDATE public.package_activities
    SET status              = 'ongoing',
        tour_status         = 'on_tour',
        current_spot_index  = v_next_index,
        updated_at          = now()
    WHERE id = v_activity.id;

    UPDATE public.package_bookings
    SET booking_status     = 'on_tour',
        current_spot_index = v_next_index,
        updated_at         = now()
    WHERE id = v_booking.id;
  ELSE
    UPDATE public.package_activities
    SET status             = 'ongoing',
        tour_status        = 'on_tour',
        current_spot_index = v_total_items,
        updated_at         = now()
    WHERE id = v_activity.id;

    UPDATE public.package_bookings
    SET booking_status     = 'on_tour',
        current_spot_index = v_total_items,
        updated_at         = now()
    WHERE id = v_booking.id;
  END IF;

  -- Return current state of all itinerary items for client-side sync.
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id',               id,
        'order_number',     order_number,
        'destination_order', destination_order,
        'spot_status',      spot_status
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
    'success',                      true,
    'booking_id',                   v_booking.id,
    'activity_id',                  v_activity.id,
    'completed_items',              v_completed_items,
    'total_items',                  v_total_items,
    'current_spot_index',           v_next_index,
    'current_itinerary_item_id',    v_current_item_id,
    'current_order_number',         v_current_order_number,
    'tour_completed',               v_completed_items >= v_total_items,
    'package_activities_status',    'ongoing',
    'package_bookings_status',      COALESCE(v_booking.status, 'confirmed'),
    'package_bookings_booking_status', 'on_tour',
    'spot_status_list',             v_spot_status_list
  );
END;
$$;

-- Keep the 2-arg overload so old callers still work.
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
    NULL::uuid,
    p_remaining_payment_method
  );
$$;

GRANT EXECUTE ON FUNCTION
  public.complete_current_itinerary_item(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION
  public.complete_current_itinerary_item(uuid, uuid, text)
  TO authenticated;

-- Also tighten the UPDATE RLS so drivers can always update itinerary items
-- directly (belt-and-suspenders alongside the RPC path).
DROP POLICY IF EXISTS booking_itinerary_items_update ON public.booking_itinerary_items;
CREATE POLICY booking_itinerary_items_update ON public.booking_itinerary_items
FOR UPDATE TO authenticated
USING (
  tourist_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.package_bookings b
    WHERE b.id = booking_id
      AND b.assigned_driver_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.booking_drivers bd
    WHERE bd.booking_id = booking_id
      AND bd.driver_id  = auth.uid()
      AND bd.status     = 'accepted'
  )
  OR EXISTS (
    SELECT 1 FROM public.package_activities pa
    WHERE pa.booking_id = booking_id
      AND pa.driver_id  = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'
  )
)
WITH CHECK (
  tourist_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.package_bookings b
    WHERE b.id = booking_id
      AND b.assigned_driver_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.booking_drivers bd
    WHERE bd.booking_id = booking_id
      AND bd.driver_id  = auth.uid()
      AND bd.status     = 'accepted'
  )
  OR EXISTS (
    SELECT 1 FROM public.package_activities pa
    WHERE pa.booking_id = booking_id
      AND pa.driver_id  = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'
  )
);
