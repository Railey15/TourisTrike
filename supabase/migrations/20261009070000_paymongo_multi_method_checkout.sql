-- Extend the existing PayMongo Checkout Session lifecycle to the four methods
-- exposed by TourisTrike. Amounts and payment stages remain authoritative in
-- PostgreSQL; Flutter never supplies a payable amount.

begin;

alter table public.payment_records
  drop constraint if exists payment_records_payment_method_check;
alter table public.payment_records
  add constraint payment_records_payment_method_check
  check (payment_method in (
    'cash', 'gcash', 'maya', 'paymaya', 'qrph', 'card'
  ));

alter table public.payment_email_verifications
  drop constraint if exists payment_email_verifications_payment_stage_check;
alter table public.payment_email_verifications
  add constraint payment_email_verifications_payment_stage_check
  check (payment_stage in ('down_payment', 'remaining_balance', 'full_payment'));

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
    if new.payment_method not in ('gcash', 'paymaya', 'qrph', 'card') then
      raise exception 'INVALID_PAYMONGO_PAYMENT_METHOD';
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
    if new.provider <> 'paymongo'
       or new.payment_method not in ('gcash', 'paymaya', 'qrph', 'card') then
      raise exception 'DOWN_PAYMENT_REQUIRES_PAYMONGO';
    end if;
  elsif new.payment_stage = 'remaining_balance' then
    v_required_amount := v_booking.remaining_balance;
    if not (
      (new.provider = 'paymongo'
        and new.payment_method in ('gcash', 'paymaya', 'qrph', 'card'))
      or (new.provider = 'manual' and new.payment_method = 'cash')
    ) then
      raise exception 'INVALID_REMAINING_PAYMENT_ROUTE';
    end if;
  elsif new.payment_stage = 'full' then
    v_required_amount := v_booking.total_amount;
    if new.provider <> 'paymongo'
       or new.payment_method not in ('gcash', 'paymaya', 'qrph', 'card') then
      raise exception 'FULL_PAYMENT_REQUIRES_PAYMONGO';
    end if;
    if not exists (
      select 1 from public.booking_payment_requirements bpr
      where bpr.booking_id = new.booking_id
        and bpr.payment_stage = 'down_payment'
        and bpr.status = 'required'
    ) or not exists (
      select 1 from public.booking_payment_requirements bpr
      where bpr.booking_id = new.booking_id
        and bpr.payment_stage = 'remaining_balance'
        and bpr.status = 'required'
    ) then
      raise exception 'PAYMENT_STAGE_NOT_REQUIRED';
    end if;
  else
    raise exception 'INVALID_PACKAGE_PAYMENT_STAGE';
  end if;

  if coalesce(v_required_amount, 0) <= 0
     or new.amount <> round(v_required_amount, 2) then
    raise exception 'INVALID_PAYMENT_AMOUNT';
  end if;
  if new.payment_stage <> 'full' and not exists (
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
$$;

revoke all on function public.validate_booking_payment_submission()
  from public, anon, authenticated;

create or replace function public.prepare_paymongo_payment_authenticated_impl(
  p_booking_id uuid,
  p_payment_stage text,
  p_idempotency_key text,
  p_tourist_id uuid,
  p_provider_livemode boolean,
  p_payment_method text
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
  v_method text := lower(coalesce(trim(p_payment_method), ''));
  v_amount numeric(14,2);
  v_roster_count integer;
begin
  if p_tourist_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if v_method not in ('gcash', 'paymaya', 'qrph', 'card') then
    raise exception 'INVALID_PAYMENT_METHOD';
  end if;
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
       or v_payment.payer_id <> p_tourist_id
       or v_payment.payment_method <> v_method then
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
  elsif v_stage = 'full' then
    if public.is_booking_downpayment_confirmed(p_booking_id) then
      raise exception 'PAYMENT_STAGE_NOT_DUE';
    end if;
    if not exists (
      select 1 from public.booking_payment_requirements
      where booking_id = p_booking_id and payment_stage = 'down_payment'
        and status = 'required' and amount = v_booking.downpayment_amount
    ) or not exists (
      select 1 from public.booking_payment_requirements
      where booking_id = p_booking_id and payment_stage = 'remaining_balance'
        and status = 'required' and amount = v_booking.remaining_balance
    ) then
      raise exception 'PAYMENT_STAGE_NOT_DUE';
    end if;
    v_amount := v_booking.total_amount;
  else
    raise exception 'INVALID_PACKAGE_PAYMENT_STAGE';
  end if;
  if v_stage <> 'full' and not exists (
    select 1 from public.booking_payment_requirements
    where booking_id = p_booking_id and payment_stage = v_stage
      and status = 'required' and amount = v_amount
  ) then
    raise exception 'PAYMENT_STAGE_NOT_DUE';
  end if;
  v_amount := round(v_amount, 2);
  if coalesce(v_amount, 0) <= 0 then raise exception 'INVALID_PAYMENT_AMOUNT'; end if;

  if v_stage in ('down_payment', 'full') then
    select * into v_payment from public.payment_records
    where booking_id = p_booking_id
      and payment_stage in ('down_payment', 'full')
      and status <> 'cancelled'
    order by created_at desc limit 1 for update;
  else
    select * into v_payment from public.payment_records
    where booking_id = p_booking_id and payment_stage = v_stage
      and status <> 'cancelled'
      and (payment_stage <> 'remaining_balance' or status <> 'confirmed')
    order by created_at desc limit 1 for update;
  end if;
  if found then
    if v_payment.payment_stage <> v_stage then
      raise exception 'PAYMENT_STAGE_IN_PROGRESS';
    end if;
    if v_payment.provider = 'paymongo'
       and v_payment.payment_method <> v_method then
      raise exception 'PAYMENT_METHOD_CHANGE_REQUIRES_CHECKOUT_EXPIRY';
    end if;
    if v_stage = 'remaining_balance' and v_payment.provider = 'manual'
       and v_payment.payment_method = 'cash' and v_payment.payee_id is null
       and v_payment.status = 'pending_confirmation' then
      if exists(select 1 from public.payment_allocations a
          where a.payment_record_id = v_payment.id
            and (a.status <> 'awaiting_cash' or a.paid_at is not null)) then
        raise exception 'CASH_PAYMENT_IN_PROGRESS';
      end if;
      update public.payment_records
      set status = 'cancelled', provider_status = 'cash_replaced_by_paymongo'
      where id = v_payment.id;
      update public.payment_allocations set status = 'cancelled'
      where payment_record_id = v_payment.id and status = 'awaiting_cash';
    elsif v_payment.provider = 'paymongo'
          and v_payment.status = 'pending_confirmation' then
      if v_payment.provider_livemode is distinct from p_provider_livemode then
        raise exception 'PAYMONGO_PAYMENT_ENVIRONMENT_MISMATCH';
      end if;
      if v_payment.amount <> v_amount then
        raise exception 'PAYMENT_AMOUNT_CHANGED_REQUIRES_CHECKOUT_EXPIRY';
      end if;
      if v_payment.provider_status = 'checkout_failed'
         and v_payment.provider_checkout_id is null
         and v_payment.provider_payment_id is null
         and v_payment.paid_at is null
         and not exists(select 1 from public.payment_provider_events e
           where e.payment_record_id = v_payment.id) then
        update public.payment_records
        set status = 'cancelled', provider_status = 'checkout_failed_replaced'
        where id = v_payment.id;
        update public.payment_allocations set status = 'cancelled'
        where payment_record_id = v_payment.id and status in ('held', 'eligible');
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
    p_booking_id, p_tourist_id, null, v_amount, v_method, v_stage,
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

revoke all on function public.prepare_paymongo_payment_authenticated_impl(
  uuid, text, text, uuid, boolean, text
) from public, anon, authenticated, service_role;

create or replace function public.prepare_paymongo_payment(
  p_booking_id uuid,
  p_payment_stage text,
  p_idempotency_key text,
  p_tourist_id uuid,
  p_provider_livemode boolean,
  p_payment_method text
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
    p_booking_id, p_payment_stage, p_idempotency_key,
    v_authenticated_tourist_id, p_provider_livemode, p_payment_method
  );
end;
$$;

revoke all on function public.prepare_paymongo_payment(
  uuid, text, text, uuid, boolean, text
) from public, anon, service_role;
grant execute on function public.prepare_paymongo_payment(
  uuid, text, text, uuid, boolean, text
) to authenticated;

create or replace function public.request_payment_email_verification(
  p_tourist_id uuid, p_booking_id uuid, p_payment_stage text, p_code_hash text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  v_amount numeric(14,2);
  v_previous public.payment_email_verifications;
begin
  if auth.role() <> 'service_role' then raise exception 'FORBIDDEN'; end if;
  if p_payment_stage not in ('down_payment', 'remaining_balance', 'full_payment')
     or p_code_hash !~ '^[0-9a-f]{64}$' then raise exception 'INVALID_REQUEST'; end if;
  if not exists (select 1 from public.package_bookings b
                 where b.id = p_booking_id and b.tourist_id = p_tourist_id) then
    raise exception 'NOT_BOOKING_TOURIST';
  end if;
  perform public.ensure_booking_payment_requirements(p_booking_id);
  if p_payment_stage = 'full_payment' then
    select b.total_amount into v_amount from public.package_bookings b
    where b.id = p_booking_id
      and exists (select 1 from public.booking_payment_requirements r
        where r.booking_id = b.id and r.payment_stage = 'down_payment'
          and r.status = 'required')
      and exists (select 1 from public.booking_payment_requirements r
        where r.booking_id = b.id and r.payment_stage = 'remaining_balance'
          and r.status = 'required');
  else
    select r.amount into v_amount from public.booking_payment_requirements r
    where r.booking_id = p_booking_id and r.payment_stage = p_payment_stage
      and r.status = 'required';
  end if;
  if v_amount is null or v_amount <= 0 then raise exception 'PAYMENT_STAGE_NOT_DUE'; end if;
  if p_payment_stage = 'remaining_balance' and
     (not public.is_booking_itinerary_complete(p_booking_id) or
      not public.is_booking_downpayment_confirmed(p_booking_id)) then
    raise exception 'PAYMENT_STAGE_NOT_DUE';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_tourist_id::text || p_booking_id::text || p_payment_stage, 0));
  select * into v_previous from public.payment_email_verifications
  where tourist_id = p_tourist_id and booking_id = p_booking_id
    and payment_stage = p_payment_stage for update;
  if found and v_previous.sent_at > now() - interval '30 seconds' then
    raise exception 'RATE_LIMITED';
  end if;
  insert into public.payment_email_verifications
    (tourist_id, booking_id, payment_stage, amount, code_hash, expires_at)
  values (p_tourist_id, p_booking_id, p_payment_stage, v_amount,
          p_code_hash, now() + interval '10 minutes')
  on conflict (tourist_id, booking_id, payment_stage) do update
  set amount = excluded.amount, code_hash = excluded.code_hash,
      sent_at = now(), expires_at = excluded.expires_at, attempts = 0,
      verified_until = null, consumed_at = null;
  return 'SENT';
end;
$$;

create or replace function public.consume_payment_email_verification(
  p_tourist_id uuid, p_booking_id uuid, p_payment_stage text
) returns boolean language plpgsql security definer set search_path = '' as $$
declare v_amount numeric(14,2);
begin
  if auth.role() <> 'service_role' then raise exception 'FORBIDDEN'; end if;
  if p_payment_stage = 'full_payment' then
    select b.total_amount into v_amount from public.package_bookings b
    where b.id = p_booking_id
      and exists (select 1 from public.booking_payment_requirements r
        where r.booking_id = b.id and r.payment_stage = 'down_payment'
          and r.status = 'required')
      and exists (select 1 from public.booking_payment_requirements r
        where r.booking_id = b.id and r.payment_stage = 'remaining_balance'
          and r.status = 'required');
  else
    select amount into v_amount from public.booking_payment_requirements
    where booking_id = p_booking_id and payment_stage = p_payment_stage
      and status = 'required';
  end if;
  if v_amount is null then return false; end if;
  update public.payment_email_verifications set consumed_at = now()
  where tourist_id = p_tourist_id and booking_id = p_booking_id
    and payment_stage = p_payment_stage and amount = v_amount
    and verified_until > now() and consumed_at is null;
  return found;
end;
$$;

revoke all on function public.request_payment_email_verification(
  uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.request_payment_email_verification(
  uuid, uuid, text, text
) to service_role;
revoke all on function public.consume_payment_email_verification(
  uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.consume_payment_email_verification(
  uuid, uuid, text
) to service_role;

create or replace function public.satisfy_full_payment_requirements()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.booking_id is not null and new.provider = 'paymongo'
     and new.payment_stage = 'full' and new.status = 'confirmed'
     and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    update public.booking_payment_requirements
    set status = 'satisfied',
        satisfied_at = coalesce(satisfied_at, new.paid_at, now()),
        satisfied_by_payment_record_id = coalesce(
          satisfied_by_payment_record_id, new.id
        )
    where booking_id = new.booking_id
      and payment_stage in ('down_payment', 'remaining_balance')
      and status = 'required';
  end if;
  return new;
end;
$$;

revoke all on function public.satisfy_full_payment_requirements()
  from public, anon, authenticated;
drop trigger if exists trg_satisfy_full_payment_requirements
  on public.payment_records;
create trigger trg_satisfy_full_payment_requirements
after insert or update of status on public.payment_records
for each row execute function public.satisfy_full_payment_requirements();

commit;
