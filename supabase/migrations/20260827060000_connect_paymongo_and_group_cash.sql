-- Connect the trusted provider workflow to an explicit group-cash state model.
-- A PayMongo or group-cash stage is one tourist-facing payment record. Driver
-- shares live in payment_allocations and are never treated as paid-out merely
-- because the tourist payment was collected.

alter table public.payment_allocations
  drop constraint if exists payment_allocations_status_check;
alter table public.payment_allocations
  add constraint payment_allocations_status_check check (status in (
    'held', 'eligible', 'processing', 'paid', 'failed', 'cancelled',
    'manual_review', 'awaiting_cash', 'cash_confirmed'
  ));

alter table public.payment_records
  drop constraint if exists payment_records_provider_party_check;
alter table public.payment_records
  add constraint payment_records_provider_party_check check (
    (provider = 'manual' and (
      payee_id is not null
      or (booking_id is not null and payment_method = 'cash'
          and provider_status in ('awaiting_cash_receipt', 'cash_received'))
    ))
    or (provider = 'paymongo' and booking_id is not null and payee_id is null)
  );

create or replace function public.validate_booking_payment_submission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_required_amount numeric;
  v_is_service_role boolean := coalesce(auth.jwt()->>'role', '') = 'service_role';
  v_trusted_group_cash boolean :=
    coalesce(current_setting('touristrike.trusted_group_cash', true), '') = 'true';
begin
  if new.booking_id is null then return new; end if;

  select * into v_booking from public.package_bookings
  where id = new.booking_id for key share;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if new.provider = 'paymongo' then
    if not v_is_service_role or new.payer_id <> v_booking.tourist_id
       or new.payee_id is not null then
      raise exception 'TRUSTED_PAYMENT_BACKEND_REQUIRED';
    end if;
    if new.payment_method <> 'gcash' then
      raise exception 'PAYMONGO_GCASH_REQUIRED';
    end if;
  elsif new.payee_id is null then
    if not v_trusted_group_cash or new.payer_id <> v_booking.tourist_id
       or new.payment_method <> 'cash'
       or new.payment_stage <> 'remaining_balance'
       or new.provider_status <> 'awaiting_cash_receipt' then
      raise exception 'TRUSTED_GROUP_CASH_BACKEND_REQUIRED';
    end if;
  elsif auth.uid() is null or new.payer_id <> auth.uid()
        or new.payer_id <> v_booking.tourist_id then
    raise exception 'NOT_BOOKING_TOURIST';
  elsif not exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = new.booking_id
      and bd.driver_id = new.payee_id and bd.status = 'accepted'
  ) then
    raise exception 'PAYEE_NOT_ASSIGNED_DRIVER';
  end if;

  if lower(coalesce(v_booking.booking_status, v_booking.status, 'pending'))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_PAYABLE';
  end if;

  if lower(coalesce(v_booking.booking_type, 'same_day')) = 'advanced' then
    if new.payment_stage = 'down_payment' then
      v_required_amount := v_booking.downpayment_amount;
      if new.provider <> 'paymongo' or new.payment_method <> 'gcash' then
        raise exception 'DOWN_PAYMENT_REQUIRES_PAYMONGO_GCASH';
      end if;
    elsif new.payment_stage = 'remaining_balance' then
      v_required_amount := v_booking.remaining_balance;
      if not (
        (new.provider = 'paymongo' and new.payment_method = 'gcash')
        or (new.provider = 'manual' and new.payment_method = 'cash')
      ) then
        raise exception 'INVALID_REMAINING_PAYMENT_ROUTE';
      end if;
    else
      raise exception 'INVALID_ADVANCED_PAYMENT_STAGE';
    end if;
    if coalesce(v_required_amount, 0) <= 0 or new.amount <> v_required_amount then
      raise exception 'INVALID_PAYMENT_AMOUNT';
    end if;
    if not exists (
      select 1 from public.booking_payment_requirements bpr
      where bpr.booking_id = new.booking_id
        and bpr.payment_stage = new.payment_stage
        and bpr.status <> 'waived' and bpr.amount = new.amount
    ) then
      raise exception 'PAYMENT_STAGE_NOT_REQUIRED';
    end if;
  elsif new.provider = 'paymongo'
        and (new.payment_stage <> 'full' or new.amount <> v_booking.total_amount) then
    raise exception 'INVALID_PAYMENT_AMOUNT';
  end if;

  return new;
end;
$$;

create or replace function public.prepare_group_cash_remaining_balance(
  p_booking_id uuid,
  p_idempotency_key text
)
returns public.payment_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_payment public.payment_records;
  v_required_count integer;
  v_accepted_count integer;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 16
     or length(p_idempotency_key) > 255 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  select * into v_booking from public.package_bookings
  where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking.tourist_id <> auth.uid() then raise exception 'NOT_BOOKING_TOURIST'; end if;
  if lower(coalesce(v_booking.booking_type, '')) <> 'advanced' then
    raise exception 'CASH_REMAINING_BALANCE_ONLY';
  end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_PAYABLE';
  end if;

  v_required_count := greatest(coalesce(v_booking.required_drivers, 1), 1);
  select count(*) into v_accepted_count from public.booking_drivers
  where booking_id = p_booking_id and status = 'accepted';
  if v_accepted_count <> v_required_count then raise exception 'DRIVER_ROSTER_NOT_FULL'; end if;

  perform public.ensure_booking_payment_requirements(p_booking_id);
  if not exists (
    select 1 from public.booking_payment_requirements
    where booking_id = p_booking_id and payment_stage = 'down_payment'
      and status = 'satisfied'
  ) then raise exception 'DOWNPAYMENT_NOT_CONFIRMED'; end if;
  if not exists (
    select 1 from public.booking_payment_requirements
    where booking_id = p_booking_id and payment_stage = 'remaining_balance'
      and status = 'required' and amount = v_booking.remaining_balance
  ) then raise exception 'PAYMENT_STAGE_NOT_DUE'; end if;

  select * into v_payment from public.payment_records
  where booking_id = p_booking_id and payment_stage = 'remaining_balance'
    and status <> 'cancelled'
  order by created_at desc limit 1 for update;
  if found then
    if v_payment.provider = 'manual' and v_payment.payment_method = 'cash'
       and v_payment.payee_id is null then
      return v_payment;
    end if;
    raise exception 'PAYMENT_STAGE_ALREADY_STARTED';
  end if;

  perform set_config('touristrike.trusted_group_cash', 'true', true);
  insert into public.payment_records (
    booking_id, payer_id, payee_id, amount, payment_method, payment_stage,
    status, provider, currency, provider_status, idempotency_key,
    service_description
  ) values (
    p_booking_id, auth.uid(), null, round(v_booking.remaining_balance, 2),
    'cash', 'remaining_balance', 'pending_confirmation', 'manual', 'PHP',
    'awaiting_cash_receipt', p_idempotency_key,
    'Cash remaining balance for TourisTrike package booking'
  ) returning * into v_payment;

  insert into public.payment_allocations (
    payment_record_id, booking_id, booking_driver_id, driver_id,
    gross_amount, platform_fee, driver_amount, split_basis_points,
    currency, status
  )
  with ranked as (
    select bd.*,
      (row_number() over (order by bd.accepted_at, bd.id))::integer
        as recipient_position
    from public.booking_drivers bd
    where bd.booking_id = p_booking_id and bd.status = 'accepted'
  )
  select v_payment.id, p_booking_id, bd.id, bd.driver_id,
         split.amount_centavos / 100.0, 0, split.amount_centavos / 100.0,
         split.basis_points, 'PHP', 'awaiting_cash'
  from ranked bd
  join public.compute_equal_split_centavos(
    (round(v_booking.remaining_balance, 2) * 100)::bigint, v_accepted_count
  ) split on split.recipient_position = bd.recipient_position;

  if (select count(*) from public.payment_allocations
      where payment_record_id = v_payment.id) <> v_accepted_count
     or (select coalesce(sum(gross_amount), 0) from public.payment_allocations
         where payment_record_id = v_payment.id) <> round(v_booking.remaining_balance, 2) then
    raise exception 'CASH_ALLOCATION_TOTAL_MISMATCH';
  end if;

  raise log '[TourisTrike payment] group cash prepared booking=%, payment=%, drivers=%',
    p_booking_id, v_payment.id, v_accepted_count;
  return v_payment;
end;
$$;

revoke all on function public.prepare_group_cash_remaining_balance(uuid, text)
  from public, anon;
grant execute on function public.prepare_group_cash_remaining_balance(uuid, text)
  to authenticated;

create or replace function public.confirm_group_cash_share(
  p_payment_record_id uuid
)
returns public.payment_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payment_records;
  v_allocation public.payment_allocations;
  v_booking public.package_bookings;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  select * into v_payment from public.payment_records
  where id = p_payment_record_id for update;
  if not found then raise exception 'PAYMENT_RECORD_NOT_FOUND'; end if;
  if v_payment.provider <> 'manual' or v_payment.payment_method <> 'cash'
     or v_payment.payment_stage <> 'remaining_balance'
     or v_payment.payee_id is not null then
    raise exception 'GROUP_CASH_PAYMENT_REQUIRED';
  end if;

  select * into v_booking from public.package_bookings
  where id = v_payment.booking_id for key share;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_ACTIVE';
  end if;

  select * into v_allocation from public.payment_allocations
  where payment_record_id = v_payment.id and driver_id = auth.uid()
  for update;
  if not found then raise exception 'NOT_ASSIGNED_PAYMENT_DRIVER'; end if;
  if v_allocation.status = 'cash_confirmed' then return v_payment; end if;
  if v_allocation.status <> 'awaiting_cash' then
    raise exception 'CASH_SHARE_NOT_CONFIRMABLE';
  end if;

  update public.payment_allocations
  set status = 'cash_confirmed', paid_at = now(), last_error = null
  where id = v_allocation.id;

  if not exists (
    select 1 from public.payment_allocations
    where payment_record_id = v_payment.id and status <> 'cash_confirmed'
  ) then
    update public.payment_records
    set status = 'confirmed', provider_status = 'cash_received', paid_at = now()
    where id = v_payment.id returning * into v_payment;
    update public.booking_payment_requirements
    set status = 'satisfied', satisfied_at = coalesce(satisfied_at, now()),
        satisfied_by_payment_record_id = coalesce(
          satisfied_by_payment_record_id, v_payment.id)
    where booking_id = v_payment.booking_id
      and payment_stage = 'remaining_balance'
      and amount = v_payment.amount and status = 'required';
  end if;

  raise log '[TourisTrike payment] cash share confirmed payment=%, driver=%, complete=%',
    v_payment.id, auth.uid(), v_payment.status = 'confirmed';
  return v_payment;
end;
$$;

revoke all on function public.confirm_group_cash_share(uuid) from public, anon;
grant execute on function public.confirm_group_cash_share(uuid) to authenticated;
