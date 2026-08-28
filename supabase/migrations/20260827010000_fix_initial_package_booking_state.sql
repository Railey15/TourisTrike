-- Fix the package-booking INSERT guard introduced by the P0 integrity pass.
-- The convoy architecture's canonical unassigned state is
-- waiting_for_drivers, not pending. package_bookings.status remains pending;
-- package_activities is created by trg_sync_package_activity with status
-- pending and tour_status waiting_driver.

alter table public.package_bookings
  alter column booking_status set default 'waiting_for_drivers';

create or replace function public.guard_package_booking_client_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_profile_role() <> 'tourist' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if auth.uid() is null or new.tourist_id <> auth.uid() then
      raise exception 'NOT_BOOKING_TOURIST';
    end if;

    -- `pending` is accepted only as a legacy/default input and normalized to
    -- the current convoy vocabulary before the row is stored.
    if lower(coalesce(new.status, 'pending')) <> 'pending'
       or lower(coalesce(new.booking_status, 'waiting_for_drivers'))
            not in ('pending', 'waiting_for_drivers')
       or new.assigned_driver_id is not null
       or coalesce(new.accepted_drivers_count, 0) <> 0
       or new.required_drivers is null
       or new.required_drivers < 1 then
      raise exception 'INVALID_INITIAL_BOOKING_STATE';
    end if;

    new.status := 'pending';
    new.booking_status := 'waiting_for_drivers';
    new.accepted_drivers_count := 0;

    if lower(coalesce(new.booking_type, 'advanced')) = 'advanced' then
      if lower(coalesce(new.payment_method, '')) <> 'gcash' then
        raise exception 'ADVANCED_BOOKING_REQUIRES_GCASH';
      end if;
      if new.downpayment_amount <> round(new.total_amount * 0.50, 2)
         or new.remaining_balance <> new.total_amount - new.downpayment_amount then
        raise exception 'INVALID_ADVANCED_PAYMENT_SPLIT';
      end if;
    end if;

    return new;
  end if;

  -- Preserve the existing cancellation RPC compatibility.
  if lower(coalesce(new.booking_status, new.status, '')) = 'cancelled' then
    return new;
  end if;

  if new.status is distinct from old.status
     or new.booking_status is distinct from old.booking_status
     or new.assigned_driver_id is distinct from old.assigned_driver_id
     or new.accepted_drivers_count is distinct from old.accepted_drivers_count
     or new.required_drivers is distinct from old.required_drivers
     or new.booking_type is distinct from old.booking_type
     or new.payment_method is distinct from old.payment_method
     or new.total_amount is distinct from old.total_amount
     or new.downpayment_amount is distinct from old.downpayment_amount
     or new.remaining_balance is distinct from old.remaining_balance
     or new.travel_date is distinct from old.travel_date
     or new.scheduled_start_at is distinct from old.scheduled_start_at
     or new.estimated_end_at is distinct from old.estimated_end_at then
    raise exception 'BOOKING_UPDATE_RPC_REQUIRED';
  end if;

  return new;
end;
$$;

