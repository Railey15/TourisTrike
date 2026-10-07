begin;

-- Recover unresolved payment attempts without reopening confirmed receipts.
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
  v_roster_count integer;
  v_amount numeric(14,2);
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 16
     or length(p_idempotency_key) > 255 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  select * into v_booking from public.package_bookings
  where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking.tourist_id <> auth.uid() then
    raise exception 'NOT_BOOKING_TOURIST';
  end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_PAYABLE';
  end if;

  select count(*) into v_roster_count
  from public.required_booking_driver_roster(p_booking_id);
  if not public.is_booking_driver_roster_full(p_booking_id) then
    raise exception 'DRIVER_ROSTER_NOT_FULL';
  end if;

  perform public.ensure_booking_payment_requirements(p_booking_id);
  if not public.is_booking_itinerary_complete(p_booking_id) then
    raise exception 'REMAINING_PAYMENT_NOT_DUE';
  end if;
  if not public.is_booking_downpayment_confirmed(p_booking_id) then
    raise exception 'DOWNPAYMENT_NOT_CONFIRMED';
  end if;
  if not exists (
    select 1 from public.booking_payment_requirements
    where booking_id = p_booking_id and payment_stage = 'remaining_balance'
      and status = 'required' and amount = v_booking.remaining_balance
  ) then raise exception 'PAYMENT_STAGE_NOT_DUE'; end if;
  v_amount := round(v_booking.remaining_balance, 2);
  if v_amount <= 0 then raise exception 'PAYMENT_STAGE_NOT_DUE'; end if;

  select * into v_payment from public.payment_records
  where booking_id = p_booking_id and payment_stage = 'remaining_balance'
    and status <> 'cancelled' and (payment_stage <> 'remaining_balance' or status <> 'confirmed')
  order by created_at desc limit 1 for update;
  if found then
    if v_payment.provider = 'manual' and v_payment.payment_method = 'cash'
       and v_payment.payee_id is null and v_payment.status = 'pending_confirmation' then
      if exists(select 1 from public.payment_allocations a
          where a.payment_record_id=v_payment.id
            and (a.status <> 'awaiting_cash' or a.paid_at is not null)) then
        raise exception 'CASH_PAYMENT_IN_PROGRESS';
      end if;
      if v_payment.amount = v_amount
         and (select count(*) from public.payment_allocations a
              where a.payment_record_id=v_payment.id) = v_roster_count
         and (select coalesce(sum(a.gross_amount),0) from public.payment_allocations a
              where a.payment_record_id=v_payment.id) = v_amount then
        return v_payment;
      end if;
      -- No driver has confirmed this abandoned or outdated cash preparation.
      update public.payment_records set status='cancelled',provider_status='cash_replaced'
        where id=v_payment.id;
      update public.payment_allocations set status='cancelled'
        where payment_record_id=v_payment.id and status='awaiting_cash';
    elsif v_payment.provider = 'paymongo' and v_payment.status = 'pending_confirmation' then
      if v_payment.provider_status = 'checkout_failed'
         and v_payment.provider_checkout_id is null
         and v_payment.provider_payment_id is null and v_payment.paid_at is null
         and not exists(select 1 from public.payment_provider_events e
           where e.payment_record_id=v_payment.id) then
        update public.payment_records set status='cancelled',provider_status='checkout_failed_replaced'
          where id=v_payment.id;
        update public.payment_allocations set status='cancelled'
          where payment_record_id=v_payment.id and status in ('held','eligible');
      else
        raise exception 'PAYMENT_STAGE_HAS_ACTIVE_CHECKOUT';
      end if;
    else
      raise exception 'PAYMENT_STAGE_IN_PROGRESS';
    end if;
  end if;

  perform set_config('touristrike.trusted_group_cash', 'true', true);
  insert into public.payment_records(
    booking_id, payer_id, payee_id, amount, payment_method, payment_stage,
    status, provider, currency, provider_status, idempotency_key,
    service_description
  ) values (
    p_booking_id, auth.uid(), null, v_amount,
    'cash', 'remaining_balance', 'pending_confirmation', 'manual', 'PHP',
    'awaiting_cash_receipt', p_idempotency_key,
    'Cash remaining balance for TourisTrike package booking'
  ) returning * into v_payment;

  insert into public.payment_allocations(
    payment_record_id, booking_id, booking_driver_id, driver_id,
    gross_amount, platform_fee, driver_amount, split_basis_points,
    currency, status
  )
  with ranked as (
    select bd.*,
      (row_number() over (order by bd.accepted_at, bd.id))::integer
        as recipient_position
    from public.required_booking_driver_roster(p_booking_id) bd
  )
  select v_payment.id, p_booking_id, bd.id, bd.driver_id,
         split.amount_centavos / 100.0, 0, split.amount_centavos / 100.0,
         split.basis_points, 'PHP', 'awaiting_cash'
  from ranked bd
  join public.compute_equal_split_centavos(
    (v_amount * 100)::bigint, v_roster_count
  ) split on split.recipient_position = bd.recipient_position;

  if (select count(*) from public.payment_allocations
      where payment_record_id = v_payment.id) <> v_roster_count
     or (select coalesce(sum(gross_amount), 0)
         from public.payment_allocations
         where payment_record_id = v_payment.id)
        <> v_amount then
    raise exception 'CASH_ALLOCATION_TOTAL_MISMATCH';
  end if;

  raise log '[TourisTrike payment] group cash prepared booking=%, payment=%, drivers=%',
    p_booking_id, v_payment.id, v_roster_count;
  return v_payment;
end;
$$;

create or replace function public.prepare_paymongo_payment_authenticated_impl(
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
  v_booking public.package_bookings;
  v_payment public.payment_records;
  v_stage text := case when p_payment_stage = 'full_payment'
    then 'full' else p_payment_stage end;
  v_amount numeric(14,2);
  v_roster_count integer;
begin
  if p_tourist_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 16
     or length(p_idempotency_key) > 255 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  select * into v_booking from public.package_bookings
  where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking.tourist_id <> p_tourist_id then
    raise exception 'NOT_BOOKING_TOURIST';
  end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_PAYABLE';
  end if;

  select * into v_payment from public.payment_records
  where provider = 'paymongo' and idempotency_key = p_idempotency_key;
  if found then
    if v_payment.booking_id <> p_booking_id
       or v_payment.payment_stage <> v_stage
       or v_payment.payer_id <> p_tourist_id then
      raise exception 'IDEMPOTENCY_KEY_REUSED';
    end if;
    return jsonb_build_object(
      'payment', to_jsonb(v_payment),
      'amount_centavos', (v_payment.amount * 100)::bigint,
      'allocations', coalesce((
        select jsonb_agg(to_jsonb(a) order by a.created_at, a.id)
        from public.payment_allocations a
        where a.payment_record_id = v_payment.id
      ), '[]'::jsonb),
      'reused', true
    );
  end if;

  select count(*) into v_roster_count
  from public.required_booking_driver_roster(p_booking_id);
  if not public.is_booking_driver_roster_full(p_booking_id) then
    raise exception 'DRIVER_ROSTER_NOT_FULL';
  end if;

  perform public.ensure_booking_payment_requirements(p_booking_id);
  if v_stage = 'down_payment' then
    v_amount := v_booking.downpayment_amount;
  elsif v_stage = 'remaining_balance' then
    if not public.is_booking_itinerary_complete(p_booking_id) then
      raise exception 'REMAINING_PAYMENT_NOT_DUE';
    end if;
    if not public.is_booking_downpayment_confirmed(p_booking_id) then
      raise exception 'DOWNPAYMENT_NOT_CONFIRMED';
    end if;
    v_amount := v_booking.remaining_balance;
  else
    raise exception 'INVALID_PACKAGE_PAYMENT_STAGE';
  end if;
  if not exists (
    select 1 from public.booking_payment_requirements
    where booking_id = p_booking_id and payment_stage = v_stage
      and status = 'required' and amount = v_amount
  ) then
    raise exception 'PAYMENT_STAGE_NOT_DUE';
  end if;
  v_amount := round(v_amount, 2);
  if coalesce(v_amount, 0) <= 0 then raise exception 'INVALID_PAYMENT_AMOUNT'; end if;

  select * into v_payment from public.payment_records
  where booking_id = p_booking_id and payment_stage = v_stage
    and status <> 'cancelled' and (payment_stage <> 'remaining_balance' or status <> 'confirmed') for update;
  if found then
    if v_stage='remaining_balance' and v_payment.provider='manual'
       and v_payment.payment_method='cash' and v_payment.payee_id is null
       and v_payment.status='pending_confirmation' then
      if exists(select 1 from public.payment_allocations a
          where a.payment_record_id=v_payment.id
            and (a.status <> 'awaiting_cash' or a.paid_at is not null)) then
        raise exception 'CASH_PAYMENT_IN_PROGRESS';
      end if;
      update public.payment_records set status='cancelled',provider_status='cash_replaced_by_gcash'
        where id=v_payment.id;
      update public.payment_allocations set status='cancelled'
        where payment_record_id=v_payment.id and status='awaiting_cash';
    elsif v_payment.provider='paymongo' and v_payment.status='pending_confirmation' then
      if v_payment.provider_livemode is distinct from p_provider_livemode then
        raise exception 'PAYMONGO_PAYMENT_ENVIRONMENT_MISMATCH';
      end if;
      if v_payment.amount <> v_amount then
        raise exception 'PAYMENT_AMOUNT_CHANGED_REQUIRES_CHECKOUT_EXPIRY';
      end if;
      if v_payment.provider_status='checkout_failed'
         and v_payment.provider_checkout_id is null
         and v_payment.provider_payment_id is null and v_payment.paid_at is null
         and not exists(select 1 from public.payment_provider_events e
           where e.payment_record_id=v_payment.id) then
        update public.payment_records set status='cancelled',provider_status='checkout_failed_replaced'
          where id=v_payment.id;
        update public.payment_allocations set status='cancelled'
          where payment_record_id=v_payment.id and status in ('held','eligible');
      else
        return jsonb_build_object(
          'payment', to_jsonb(v_payment),
          'amount_centavos', (v_payment.amount * 100)::bigint,
          'allocations', coalesce((
            select jsonb_agg(to_jsonb(a) order by a.created_at, a.id)
            from public.payment_allocations a
            where a.payment_record_id = v_payment.id
          ), '[]'::jsonb),
          'reused', true
        );
      end if;
    else
      raise exception 'PAYMENT_STAGE_IN_PROGRESS';
    end if;
  end if;

  insert into public.payment_records(
    booking_id, payer_id, payee_id, amount, payment_method, payment_stage,
    status, provider, currency, provider_reference, provider_status,
    provider_livemode, idempotency_key, service_description
  ) values (
    p_booking_id, p_tourist_id, null, v_amount, 'gcash', v_stage,
    'pending_confirmation', 'paymongo', 'PHP', gen_random_uuid()::text,
    'preparing_checkout', p_provider_livemode, p_idempotency_key,
    'TourisTrike package booking payment'
  ) returning * into v_payment;

  insert into public.payment_allocations(
    payment_record_id, booking_id, booking_driver_id, driver_id,
    gross_amount, platform_fee, driver_amount, split_basis_points,
    currency, status, provider_recipient_id
  )
  with ranked as (
    select bd.*,
      (row_number() over (order by bd.accepted_at, bd.id))::integer
        as recipient_position
    from public.required_booking_driver_roster(p_booking_id) bd
  )
  select v_payment.id, p_booking_id, bd.id, bd.driver_id,
         split.amount_centavos / 100.0, 0, split.amount_centavos / 100.0,
         split.basis_points, 'PHP', 'held', dpa.provider_recipient_id
  from ranked bd
  join public.compute_equal_split_centavos(
    (v_amount * 100)::bigint, v_roster_count
  ) split on split.recipient_position = bd.recipient_position
  left join lateral (
    select account.provider_recipient_id
    from public.driver_payout_accounts account
    where account.driver_id = bd.driver_id
      and account.provider = 'paymongo'
      and account.destination_type = 'linked_account'
      and account.verification_status = 'verified'
      and account.is_default
      and account.provider_livemode = p_provider_livemode
    order by account.updated_at desc limit 1
  ) dpa on true;

  perform public.assert_payment_allocation_total(v_payment.id);

  return jsonb_build_object(
    'payment', to_jsonb(v_payment),
    'amount_centavos', (v_amount * 100)::bigint,
    'allocations', (
      select jsonb_agg(
        ranked.allocation || jsonb_build_object(
          'split_basis_points', ranked.allocation->'split_basis_points'
        ) order by ranked.recipient_position
      )
      from (
        select to_jsonb(a) as allocation,
          row_number() over (order by bd.accepted_at, bd.id)
            as recipient_position
        from public.payment_allocations a
        join public.booking_drivers bd on bd.id = a.booking_driver_id
        where a.payment_record_id = v_payment.id
      ) ranked
    ),
    'reused', false
  );
end;
$$;

-- Called only after the server has verified that PayMongo has expired this
-- exact checkout and that the provider reports no payments for it.
create or replace function public.mark_paymongo_checkout_expired(
  p_payment_record_id uuid, p_provider_checkout_id text
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_payment public.payment_records;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  select * into v_payment from public.payment_records where id=p_payment_record_id;
  if not found then raise exception 'PAYMENT_RECORD_NOT_FOUND'; end if;
  perform 1 from public.package_bookings where id=v_payment.booking_id for update;
  select * into v_payment from public.payment_records where id=p_payment_record_id for update;
  if v_payment.status='cancelled' and v_payment.provider_status='checkout_expired' then
    return true;
  end if;
  if v_payment.provider <> 'paymongo' or v_payment.payment_stage <> 'remaining_balance'
     or v_payment.status <> 'pending_confirmation'
     or v_payment.provider_checkout_id is distinct from p_provider_checkout_id
     or p_provider_checkout_id is null or v_payment.provider_payment_id is not null
     or v_payment.paid_at is not null
     or exists(select 1 from public.payment_provider_events e
       where e.payment_record_id=v_payment.id
         and e.event_type in ('payment.paid','checkout_session.payment.paid')) then
    raise exception 'PAYMENT_STAGE_IN_PROGRESS';
  end if;
  update public.payment_records set status='cancelled',provider_status='checkout_expired'
    where id=v_payment.id;
  update public.payment_allocations set status='cancelled'
    where payment_record_id=v_payment.id and status in ('held','eligible');
  return true;
end;
$$;
revoke all on function public.mark_paymongo_checkout_expired(uuid,text)
  from public, anon, authenticated;
grant execute on function public.mark_paymongo_checkout_expired(uuid,text)
  to service_role;

commit;
