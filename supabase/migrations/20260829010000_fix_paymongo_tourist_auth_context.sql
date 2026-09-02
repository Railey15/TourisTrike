-- Keep tourist checkout preparation in the caller's JWT context. The Edge
-- Function authenticates the bearer token and invokes this RPC with the same
-- token, so auth.uid() remains the booking tourist during the guarded insert.

alter function public.prepare_paymongo_payment(uuid, text, text, uuid, boolean)
  rename to prepare_paymongo_payment_authenticated_impl;

revoke all on function public.prepare_paymongo_payment_authenticated_impl(
  uuid, text, text, uuid, boolean
) from public, anon, authenticated, service_role;

create function public.prepare_paymongo_payment(
  p_booking_id uuid,
  p_payment_stage text,
  p_idempotency_key text,
  p_tourist_id uuid,
  p_provider_livemode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_authenticated_tourist_id uuid := auth.uid();
begin
  if v_authenticated_tourist_id is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_tourist_id is distinct from v_authenticated_tourist_id then
    raise exception 'NOT_BOOKING_TOURIST';
  end if;

  return public.prepare_paymongo_payment_authenticated_impl(
    p_booking_id,
    p_payment_stage,
    p_idempotency_key,
    v_authenticated_tourist_id,
    p_provider_livemode
  );
end;
$$;

revoke all on function public.prepare_paymongo_payment(
  uuid, text, text, uuid, boolean
) from public, anon, service_role;
grant execute on function public.prepare_paymongo_payment(
  uuid, text, text, uuid, boolean
) to authenticated;

create or replace function public.validate_booking_payment_submission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_required_amount numeric;
  v_trusted_group_cash boolean :=
    coalesce(current_setting('touristrike.trusted_group_cash', true), '') = 'true';
begin
  if new.booking_id is null then return new; end if;

  select * into v_booking from public.package_bookings
  where id = new.booking_id for key share;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if new.provider = 'paymongo' then
    if auth.uid() is null or new.payer_id <> auth.uid()
       or new.payer_id <> v_booking.tourist_id then
      raise exception 'NOT_BOOKING_TOURIST';
    end if;
    if new.payee_id is not null then
      raise exception 'PAYMONGO_PAYEE_MUST_BE_NULL';
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
