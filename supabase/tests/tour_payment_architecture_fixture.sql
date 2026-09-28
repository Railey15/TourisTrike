-- Isolated test dependencies captured from the current linked backend on 2026-09-28.
-- Never run this fixture against production. Nonfinancial services are stubbed
-- by the runner; submission, preparation, allocation and settlement are real bodies.

CREATE OR REPLACE FUNCTION public.validate_booking_payment_submission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      and bd.driver_id = new.payee_id
      and bd.status in ('accepted', 'completed')
  ) then
    raise exception 'PAYEE_NOT_ASSIGNED_DRIVER';
  end if;

  if lower(coalesce(v_booking.booking_status, v_booking.status, 'pending'))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_PAYABLE';
  end if;

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
    raise exception 'INVALID_PACKAGE_PAYMENT_STAGE';
  end if;

  if coalesce(v_required_amount, 0) <= 0
     or new.amount <> round(v_required_amount, 2) then
    raise exception 'INVALID_PAYMENT_AMOUNT';
  end if;
  if not exists (
    select 1 from public.booking_payment_requirements bpr
    where bpr.booking_id = new.booking_id
      and bpr.payment_stage = new.payment_stage
      and bpr.status <> 'waived'
      and bpr.amount = new.amount
  ) then
    raise exception 'PAYMENT_STAGE_NOT_REQUIRED';
  end if;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.confirm_payment_record(p_payment_record_id uuid)
 RETURNS payment_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_record public.payment_records;
begin
  select * into v_record
  from public.payment_records
  where id = p_payment_record_id
  for update;
  if not found then raise exception 'PAYMENT_RECORD_NOT_FOUND'; end if;
  if v_record.provider = 'paymongo' then
    raise exception 'PROVIDER_WEBHOOK_REQUIRED';
  end if;
  if auth.uid() is null or not (
    auth.uid() = v_record.payee_id
    or public.is_provincial_admin()
    or public.subtenant_can_access_payment_record(v_record.id)
  ) then
    raise exception 'NOT_PAYMENT_PAYEE';
  end if;
  if v_record.status = 'confirmed' then return v_record; end if;
  if v_record.status <> 'pending_confirmation' then
    raise exception 'PAYMENT_NOT_CONFIRMABLE';
  end if;

  update public.payment_records
  set status = 'confirmed'
  where id = p_payment_record_id
  returning * into v_record;

  if v_record.booking_id is not null then
    update public.booking_payment_requirements
    set status = 'satisfied',
        satisfied_at = coalesce(satisfied_at, now()),
        satisfied_by_payment_record_id = coalesce(
          satisfied_by_payment_record_id,
          v_record.id
        )
    where booking_id = v_record.booking_id
      and payment_stage = v_record.payment_stage
      and amount <= v_record.amount
      and status = 'required';
  end if;
  return v_record;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.ensure_booking_payment_requirements(p_booking_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_booking public.package_bookings;
  v_written integer := 0;
begin
  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if not public.is_booking_driver_roster_full(p_booking_id) then
    return 0;
  end if;
  if coalesce(v_booking.downpayment_amount, 0) > 0 then
    insert into public.booking_payment_requirements(
      booking_id, payment_stage, amount
    ) values (
      p_booking_id, 'down_payment', round(v_booking.downpayment_amount, 2)
    )
    on conflict (booking_id, payment_stage) do update
    set amount = excluded.amount,
        status = case
          when booking_payment_requirements.status in ('satisfied', 'waived')
            then booking_payment_requirements.status
          else 'required'
        end;
    v_written := v_written + 1;
  end if;

  if coalesce(v_booking.remaining_balance, 0) > 0 then
    insert into public.booking_payment_requirements(
      booking_id, payment_stage, amount
    ) values (
      p_booking_id, 'remaining_balance', round(v_booking.remaining_balance, 2)
    )
    on conflict (booking_id, payment_stage) do update
    set amount = excluded.amount,
        status = case
          when booking_payment_requirements.status in ('satisfied', 'waived')
            then booking_payment_requirements.status
          else 'required'
        end;
    v_written := v_written + 1;
  end if;

  return v_written;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.is_booking_remaining_payment_satisfied(p_booking_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_booking public.package_bookings;
begin
  select * into v_booking
  from public.package_bookings
  where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if coalesce(v_booking.remaining_balance, 0) <= 0 then
    return true;
  end if;

  return exists (
    select 1
    from public.booking_payment_requirements bpr
    where bpr.booking_id = p_booking_id
      and bpr.payment_stage = 'remaining_balance'
      and (
        bpr.status = 'waived'
        or (
          bpr.status = 'satisfied'
          and exists (
            select 1
            from public.payment_records pr
            where pr.id = bpr.satisfied_by_payment_record_id
              and pr.booking_id = p_booking_id
              and pr.payment_stage = 'remaining_balance'
              and pr.status = 'confirmed'
              and pr.amount >= bpr.amount
          )
        )
      )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.prepare_paymongo_payment_authenticated_impl(p_booking_id uuid, p_payment_stage text, p_idempotency_key text, p_tourist_id uuid, p_provider_livemode boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    and status <> 'cancelled' for update;
  if found then
    if v_payment.provider <> 'paymongo' then
      raise exception 'PAYMENT_STAGE_ALREADY_HAS_MANUAL_RECORD';
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
$function$
;

CREATE OR REPLACE FUNCTION public.prepare_group_cash_remaining_balance(p_booking_id uuid, p_idempotency_key text)
 RETURNS payment_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_booking public.package_bookings;
  v_payment public.payment_records;
  v_roster_count integer;
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
  insert into public.payment_records(
    booking_id, payer_id, payee_id, amount, payment_method, payment_stage,
    status, provider, currency, provider_status, idempotency_key,
    service_description
  ) values (
    p_booking_id, auth.uid(), null, round(v_booking.remaining_balance, 2),
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
    (round(v_booking.remaining_balance, 2) * 100)::bigint, v_roster_count
  ) split on split.recipient_position = bd.recipient_position;

  if (select count(*) from public.payment_allocations
      where payment_record_id = v_payment.id) <> v_roster_count
     or (select coalesce(sum(gross_amount), 0)
         from public.payment_allocations
         where payment_record_id = v_payment.id)
        <> round(v_booking.remaining_balance, 2) then
    raise exception 'CASH_ALLOCATION_TOTAL_MISMATCH';
  end if;

  raise log '[TourisTrike payment] group cash prepared booking=%, payment=%, drivers=%',
    p_booking_id, v_payment.id, v_roster_count;
  return v_payment;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.confirm_group_cash_share(p_payment_record_id uuid)
 RETURNS payment_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.compute_equal_split_centavos(p_total_centavos bigint, p_recipient_count integer)
 RETURNS TABLE(recipient_position integer, amount_centavos bigint, basis_points integer)
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
declare
  v_amount_base bigint;
  v_amount_remainder bigint;
  v_bps_base integer;
  v_bps_remainder integer;
begin
  if p_total_centavos <= 0 or p_recipient_count <= 0 then
    raise exception 'INVALID_SPLIT_INPUT';
  end if;

  v_amount_base := p_total_centavos / p_recipient_count;
  v_amount_remainder := p_total_centavos % p_recipient_count;
  v_bps_base := 10000 / p_recipient_count;
  v_bps_remainder := 10000 % p_recipient_count;

  return query
  select series,
    v_amount_base + case when series <= v_amount_remainder then 1 else 0 end,
    v_bps_base + case when series <= v_bps_remainder then 1 else 0 end
  from generate_series(1, p_recipient_count) series;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.assert_payment_allocation_total(p_payment_record_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_expected numeric(14,2);
  v_allocated numeric(14,2);
  v_basis_points integer;
begin
  select amount into v_expected
  from public.payment_records
  where id = p_payment_record_id and provider = 'paymongo';
  if not found then raise exception 'PAYMONGO_PAYMENT_NOT_FOUND'; end if;

  select coalesce(sum(driver_amount + platform_fee), 0)
    into v_allocated
  from public.payment_allocations
  where payment_record_id = p_payment_record_id
    and status <> 'cancelled';

  if v_allocated <> v_expected then
    raise exception 'PAYMENT_ALLOCATION_TOTAL_MISMATCH: expected %, got %',
      v_expected, v_allocated;
  end if;
  select coalesce(sum(split_basis_points), 0) into v_basis_points
  from public.payment_allocations
  where payment_record_id = p_payment_record_id and status <> 'cancelled';
  if v_basis_points <> 10000 then
    raise exception 'PAYMENT_ALLOCATION_BASIS_POINTS_MISMATCH: got %',
      v_basis_points;
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.required_booking_driver_roster(p_booking_id uuid)
 RETURNS SETOF booking_drivers
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select bd.*
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id
    and bd.status in ('accepted', 'completed')
  order by bd.accepted_at, bd.id;
$function$
;

CREATE OR REPLACE FUNCTION public.is_booking_driver_roster_full(p_booking_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_required_count integer;
  v_roster_count integer;
begin
  select greatest(coalesce(pb.required_drivers, 1), 1)
  into v_required_count
  from public.package_bookings pb
  where pb.id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  select count(*) into v_roster_count
  from public.required_booking_driver_roster(p_booking_id);
  return v_roster_count = v_required_count;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.is_booking_itinerary_complete(p_booking_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*) > 0
    and count(*) filter (
      where lower(coalesce(bii.spot_status, 'pending')) = 'completed'
    ) = count(*)
  from public.booking_itinerary_items bii
  where bii.booking_id = p_booking_id;
$function$
;

CREATE OR REPLACE FUNCTION public.is_booking_downpayment_confirmed(p_booking_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_required_amount numeric(14,2);
begin
  select round(
    case
      when coalesce(pb.downpayment_amount, 0) > 0
        then pb.downpayment_amount
      else coalesce(pb.total_amount, 0) * 0.50
    end,
    2
  )
  into v_required_amount
  from public.package_bookings pb
  where pb.id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if v_required_amount <= 0 then return true; end if;

  return exists (
    select 1
    from public.payment_records pr
    where pr.booking_id = p_booking_id
      and pr.payment_stage in ('down_payment', 'full')
      and pr.status = 'confirmed'
      and pr.amount >= v_required_amount
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.process_paymongo_webhook_event(p_provider_event_id text, p_event_type text, p_provider_livemode boolean, p_provider_payment_id text, p_provider_payment_intent_id text, p_provider_checkout_id text, p_provider_reference text, p_provider_status text, p_amount_centavos bigint, p_fee_centavos bigint, p_net_centavos bigint, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_event_id uuid;
  v_payment public.payment_records;
  v_is_paid boolean;
  v_is_failed boolean;
  v_cancelled_booking boolean;
begin
  insert into public.payment_provider_events (
    provider, provider_event_id, event_type, provider_livemode,
    provider_payment_id, provider_checkout_id, payload
  ) values (
    'paymongo', p_provider_event_id, p_event_type, p_provider_livemode,
    p_provider_payment_id, p_provider_checkout_id, p_payload
  ) on conflict (provider, provider_event_id) do nothing
  returning id into v_event_id;

  if v_event_id is null then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end if;

  select * into v_payment from public.payment_records
  where provider = 'paymongo' and (
    (p_provider_checkout_id is not null and provider_checkout_id = p_provider_checkout_id)
    or (p_provider_payment_id is not null and provider_payment_id = p_provider_payment_id)
    or (p_provider_reference is not null and provider_reference = p_provider_reference)
    or (p_provider_reference is not null and id::text = p_provider_reference)
  ) order by created_at desc limit 1 for update;

  if not found then
    update public.payment_provider_events set processing_status = 'rejected',
      process_error = 'UNKNOWN_PAYMENT_REFERENCE', processed_at = now()
    where id = v_event_id;
    return jsonb_build_object('ok', false, 'rejected', true,
      'reason', 'UNKNOWN_PAYMENT_REFERENCE');
  end if;

  update public.payment_provider_events set payment_record_id = v_payment.id
  where id = v_event_id;

  if v_payment.provider_livemode is distinct from p_provider_livemode then
    update public.payment_provider_events set processing_status = 'rejected',
      process_error = 'PROVIDER_MODE_MISMATCH', processed_at = now()
    where id = v_event_id;
    return jsonb_build_object('ok', false, 'rejected', true,
      'reason', 'PROVIDER_MODE_MISMATCH');
  end if;

  v_is_paid := p_event_type in ('payment.paid', 'checkout_session.payment.paid')
    and lower(coalesce(p_provider_status, 'paid')) = 'paid';
  v_is_failed := p_event_type in (
    'payment.failed', 'checkout_session.payment.failed', 'payment_intent.payment_failed'
  ) or lower(coalesce(p_provider_status, '')) in ('failed', 'cancelled', 'expired');

  if not v_is_paid and not v_is_failed then
    update public.payment_provider_events set processing_status = 'ignored',
      processed_at = now() where id = v_event_id;
    return jsonb_build_object('ok', true, 'ignored', true);
  end if;

  if v_is_failed then
    if v_payment.status = 'confirmed' then
      update public.payment_provider_events set processing_status = 'ignored',
        process_error = 'STALE_FAILURE_AFTER_CONFIRMATION', processed_at = now()
      where id = v_event_id;
      return jsonb_build_object('ok', true, 'ignored', true,
        'reason', 'STALE_FAILURE_AFTER_CONFIRMATION');
    end if;
    update public.payment_records set
      provider_payment_id = coalesce(provider_payment_id, p_provider_payment_id),
      provider_payment_intent_id = coalesce(
        provider_payment_intent_id, p_provider_payment_intent_id),
      provider_status = coalesce(p_provider_status, 'failed'),
      provider_payload = p_payload,
      status = 'cancelled'
    where id = v_payment.id;
    update public.payment_allocations set status = 'cancelled'
    where payment_record_id = v_payment.id and status in ('held', 'eligible');
    update public.payment_provider_events set processing_status = 'processed',
      processed_at = now() where id = v_event_id;
    return jsonb_build_object('ok', true, 'confirmed', false);
  end if;

  if p_amount_centavos is null
     or p_amount_centavos <> (v_payment.amount * 100)::bigint then
    update public.payment_records set provider_status = 'amount_mismatch_manual_review',
      provider_payload = p_payload,
      provider_payment_id = coalesce(provider_payment_id, p_provider_payment_id)
    where id = v_payment.id;
    update public.payment_allocations set status = 'manual_review'
    where payment_record_id = v_payment.id and status <> 'paid';
    update public.payment_provider_events set processing_status = 'rejected',
      process_error = 'PAYMENT_AMOUNT_MISMATCH', processed_at = now()
    where id = v_event_id;
    return jsonb_build_object('ok', false, 'rejected', true,
      'reason', 'PAYMENT_AMOUNT_MISMATCH');
  end if;

  -- A checkout previously reported failed may still produce a late paid event.
  -- A newer attempt can already exist because cancelled attempts do not occupy
  -- the one-active-stage index. Preserve the provider truth, but never choose a
  -- winner or pay drivers silently: support must reconcile/refund it.
  if v_payment.status = 'cancelled' then
    update public.payment_records set
      provider_payment_id = coalesce(provider_payment_id, p_provider_payment_id),
      provider_payment_intent_id = coalesce(
        provider_payment_intent_id, p_provider_payment_intent_id),
      provider_status = 'late_paid_attempt_manual_review',
      provider_payload = p_payload,
      provider_fee_amount = case when p_fee_centavos is null then null
        else p_fee_centavos / 100.0 end,
      provider_net_amount = case when p_net_centavos is null then null
        else p_net_centavos / 100.0 end,
      paid_at = now()
    where id = v_payment.id;
    update public.payment_allocations set status = 'manual_review',
      last_error = 'Provider paid an attempt already recorded as failed.'
    where payment_record_id = v_payment.id and status <> 'paid';
    update public.payment_provider_events set processing_status = 'processed',
      process_error = 'LATE_PAID_ATTEMPT_MANUAL_REVIEW', processed_at = now()
    where id = v_event_id;
    return jsonb_build_object('ok', true, 'confirmed', false,
      'manual_review', true, 'reason', 'LATE_PAID_ATTEMPT_MANUAL_REVIEW');
  end if;

  select exists (
    select 1 from public.package_bookings pb where pb.id = v_payment.booking_id
      and lower(coalesce(pb.booking_status, pb.status, '')) = 'cancelled'
  ) into v_cancelled_booking;

  if v_cancelled_booking then
    update public.payment_records set
      provider_payment_id = coalesce(provider_payment_id, p_provider_payment_id),
      provider_payment_intent_id = coalesce(
        provider_payment_intent_id, p_provider_payment_intent_id),
      provider_status = 'paid_after_booking_cancelled_manual_review',
      provider_payload = p_payload, provider_fee_amount = p_fee_centavos / 100.0,
      provider_net_amount = p_net_centavos / 100.0, paid_at = now(),
      status = 'disputed'
    where id = v_payment.id;
    update public.payment_allocations set status = 'manual_review'
    where payment_record_id = v_payment.id and status <> 'paid';
  else
    perform public.assert_payment_allocation_total(v_payment.id);
    update public.payment_records set
      provider_payment_id = coalesce(provider_payment_id, p_provider_payment_id),
      provider_payment_intent_id = coalesce(
        provider_payment_intent_id, p_provider_payment_intent_id),
      provider_status = 'paid', provider_payload = p_payload,
      provider_fee_amount = case when p_fee_centavos is null then null
        else p_fee_centavos / 100.0 end,
      provider_net_amount = case when p_net_centavos is null then null
        else p_net_centavos / 100.0 end,
      paid_at = now(), status = 'confirmed'
    where id = v_payment.id;
    update public.booking_payment_requirements set status = 'satisfied',
      satisfied_at = coalesce(satisfied_at, now()),
      satisfied_by_payment_record_id = coalesce(
        satisfied_by_payment_record_id, v_payment.id)
    where booking_id = v_payment.booking_id
      and payment_stage = v_payment.payment_stage
      and amount = v_payment.amount and status = 'required';
    update public.payment_allocations set status = case
      when v_payment.provider_status = 'checkout_created_split_requested'
        then 'processing' else 'held' end
    where payment_record_id = v_payment.id and status = 'held';
  end if;

  update public.payment_provider_events set processing_status = 'processed',
    processed_at = now() where id = v_event_id;
  return jsonb_build_object('ok', true, 'confirmed', not v_cancelled_booking,
    'manual_review', v_cancelled_booking, 'payment_record_id', v_payment.id);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.finalize_booking_after_payment_requirement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status in ('satisfied', 'waived') then
    if new.payment_stage = 'remaining_balance' then
      perform set_config('touristrike.validated_transition', 'true', true);

      update public.package_bookings
      set remaining_balance = 0,
          booking_status = case
            when booking_status = 'awaiting_remaining_payment' then 'on_tour'
            else booking_status
          end,
          updated_at = now()
      where id = new.booking_id;

      update public.package_activities
      set tour_status = case
            when tour_status = 'awaiting_remaining_payment' then 'on_tour'
            else tour_status
          end,
          updated_at = now()
      where booking_id = new.booking_id;
    end if;

    if tg_op = 'INSERT' then
      perform public.finalize_package_booking_if_eligible(new.booking_id);
    elsif new.status is distinct from old.status
          or new.satisfied_by_payment_record_id
             is distinct from old.satisfied_by_payment_record_id then
      perform public.finalize_package_booking_if_eligible(new.booking_id);
    end if;
  end if;
  return new;
end;
$function$
;
