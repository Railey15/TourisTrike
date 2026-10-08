-- Tourist payment-history visibility, unified 50% down payment, and permanent
-- booking-scoped driver withdrawal eligibility. PayMongo remains TEST MODE.
begin;

-- The payer must be able to see a refund even when a trusted server workflow
-- created it on their behalf. The payment_record_id remains the authoritative
-- refund-to-original-payment relationship.
drop policy if exists refund_requests_read_involved on public.refund_requests;
create policy refund_requests_read_involved on public.refund_requests
for select to authenticated using (
  requested_by = auth.uid()
  or payee_id = auth.uid()
  or exists (
    select 1 from public.payment_records original_payment
    where original_payment.id = refund_requests.payment_record_id
      and original_payment.payer_id = auth.uid()
  )
  or public.current_profile_role() = 'admin'
);

-- Undo the obsolete same-day exception added by the booking-notices migration.
-- Use the authoritative guard body instead of rewriting pg_get_functiondef
-- output, whose formatting and qualification are not a stable API.
create or replace function public.guard_package_booking_client_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Security-definer lifecycle/payment RPCs set this transaction-local flag.
  -- Direct tourist PostgREST writes never can.
  if coalesce(current_setting('touristrike.validated_transition', true), '') = 'true' then
    return new;
  end if;

  if public.current_profile_role() <> 'tourist' then return new; end if;

  if tg_op = 'INSERT' then
    if auth.uid() is null or new.tourist_id is distinct from auth.uid() then
      raise exception 'NOT_BOOKING_TOURIST';
    end if;
    if new.assigned_driver_id is not null then
      raise exception 'INVALID_INITIAL_ASSIGNED_DRIVER';
    end if;
    if coalesce(new.accepted_drivers_count, 0) <> 0 then
      raise exception 'INVALID_INITIAL_ACCEPTED_DRIVER_COUNT';
    end if;
    if new.required_drivers is null or new.required_drivers < 1 then
      raise exception 'INVALID_REQUIRED_DRIVERS';
    end if;
    if lower(coalesce(nullif(trim(new.status), ''), 'pending')) <> 'pending' then
      raise exception 'INVALID_INITIAL_STATUS';
    end if;
    if lower(coalesce(nullif(trim(new.booking_status), ''), 'waiting_for_drivers'))
       not in ('pending', 'waiting_for_drivers') then
      raise exception 'INVALID_INITIAL_BOOKING_STATE';
    end if;
    new.status := 'pending';
    new.booking_status := 'waiting_for_drivers';
    new.accepted_drivers_count := 0;

    -- Same-day and advance bookings share one staged PayMongo payment rule.
    if lower(coalesce(nullif(trim(new.payment_method), ''), '')) <> 'gcash' then
      raise exception 'PACKAGE_BOOKING_REQUIRES_GCASH';
    end if;
    if new.total_amount is null or new.downpayment_amount is null
       or new.remaining_balance is null then
      raise exception 'MISSING_PACKAGE_PAYMENT_AMOUNTS';
    end if;
    if new.downpayment_amount <> round(new.total_amount * 0.50, 2)
       or new.remaining_balance <> new.total_amount - new.downpayment_amount then
      raise exception 'INVALID_PACKAGE_PAYMENT_SPLIT';
    end if;
    return new;
  end if;

  if lower(coalesce(nullif(trim(new.booking_status), ''),
                    nullif(trim(new.status), ''), '')) = 'cancelled' then
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

-- The current public create_package_booking function is the optional-
-- tricycle wrapper installed by 20261007050000. The customized-fare booking
-- implementation containing the amount calculation was renamed to this
-- internal function by 20261007040000. Replace that authoritative body while
-- leaving the current public wrapper and all unrelated behavior unchanged.
create or replace function public.create_package_booking_additional_request_impl(
  p_booking jsonb,
  p_customized_spots jsonb default '[]'::jsonb,
  p_itinerary_items jsonb default '[]'::jsonb
)
returns public.package_bookings
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking public.package_bookings;
  v_quote public.booking_custom_fare_quotes;
  v_custom boolean;
  v_points jsonb;
  v_passengers integer;
  v_total numeric;
  v_downpayment numeric;
  v_remaining numeric;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_booking->>'terms_version' is distinct from '1.1' then
    raise exception 'BOOKING_TERMS_REQUIRED';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_customized_spots, '[]'::jsonb)) s
    where coalesce((s->>'additional_fee')::numeric, 0) <> 0
  ) then
    raise exception 'CUSTOM_FARE_AMOUNT_MISMATCH';
  end if;
  v_custom := exists (
      select 1
      from jsonb_array_elements(coalesce(p_customized_spots, '[]'::jsonb)) s
      where s->>'action_type' in ('added', 'removed')
    )
    or exists (
      select 1
      from jsonb_array_elements(coalesce(p_itinerary_items, '[]'::jsonb)) item
      where coalesce(item->>'itinerary_source', item->>'source_type') = 'customized'
    )
    or jsonb_array_length(coalesce(p_itinerary_items, '[]'::jsonb)) <>
      (
        select count(*)
        from public.tour_package_spots
        where package_id = (p_booking->>'package_id')::bigint
      )
    or exists (
      select 1
      from jsonb_array_elements(coalesce(p_itinerary_items, '[]'::jsonb)) item
      where nullif(item->>'spot_id', '') is null
        or not exists (
          select 1
          from public.tour_package_spots s
          join public.tourist_spots spot on spot.id = s.spot_id
          where s.package_id = (p_booking->>'package_id')::bigint
            and s.spot_id = (item->>'spot_id')::bigint
            and spot.latitude::numeric = (item->>'latitude')::numeric
            and spot.longitude::numeric = (item->>'longitude')::numeric
        )
    );
  if v_custom then
    if nullif(p_booking->>'fare_quote_id', '') is null then
      raise exception 'CUSTOM_FARE_QUOTE_REQUIRED';
    end if;
    select * into v_quote
    from public.booking_custom_fare_quotes
    where id = (p_booking->>'fare_quote_id')::uuid
    for update;
    if not found
       or v_quote.tourist_id is distinct from auth.uid()
       or v_quote.package_id is distinct from (p_booking->>'package_id')::bigint
       or v_quote.used_at is not null
       or v_quote.expires_at <= now() then
      raise exception 'CUSTOM_FARE_QUOTE_INVALID';
    end if;
    if not exists (
      select 1
      from public.tour_packages p
      join public.subtenant_fare_settings f
        on f.subtenant_id = p.submitted_by
       and public.cities_match(f.city, p.city)
       and f.is_active
      where p.id = v_quote.package_id
        and p.updated_at = v_quote.package_updated_at
        and f.updated_at = v_quote.fare_settings_updated_at
    ) then
      raise exception 'CUSTOM_FARE_QUOTE_STALE';
    end if;
    v_points := jsonb_build_array(jsonb_build_array(
      (p_booking->>'pickup_latitude')::numeric,
      (p_booking->>'pickup_longitude')::numeric
    ));
    select v_points || coalesce(
      jsonb_agg(
        jsonb_build_array(
          (item->>'latitude')::numeric,
          (item->>'longitude')::numeric
        ) order by ord
      ),
      '[]'::jsonb
    )
    into v_points
    from jsonb_array_elements(p_itinerary_items) with ordinality x(item, ord);
    v_points := v_points || jsonb_build_array(jsonb_build_array(
      (p_booking->>'dropoff_latitude')::numeric,
      (p_booking->>'dropoff_longitude')::numeric
    ));
    if v_quote.route_points is distinct from v_points then
      raise exception 'CUSTOM_FARE_ROUTE_CHANGED';
    end if;
    v_passengers := coalesce(
      (p_booking->>'total_passengers')::integer,
      (p_booking->>'adults')::integer
        + coalesce((p_booking->>'children')::integer, 0)
    );
    if v_passengers < 1 then raise exception 'INVALID_PASSENGER_COUNT'; end if;
    v_total := round(v_quote.unit_price * v_passengers, 2);
    v_downpayment := round(v_total * 0.5, 2);
    v_remaining := v_total - v_downpayment;
    if (p_booking->>'total_amount')::numeric is distinct from v_total
       or (p_booking->>'downpayment_amount')::numeric is distinct from v_downpayment
       or (p_booking->>'remaining_balance')::numeric is distinct from v_remaining then
      raise exception 'CUSTOM_FARE_AMOUNT_MISMATCH';
    end if;
  end if;
  perform set_config('touristrike.booking_terms_version', '1.1', true);
  select * into v_booking
  from public.create_package_booking_accepted_terms_impl(
    p_booking, p_customized_spots, p_itinerary_items
  );
  if v_custom then
    update public.booking_custom_fare_quotes
    set used_at = now(), booking_id = v_booking.id
    where id = v_quote.id;
  end if;
  return v_booking;
end;
$$;
revoke all on function public.create_package_booking_additional_request_impl(
  jsonb, jsonb, jsonb
) from public, anon, authenticated;

create or replace function public.is_booking_downpayment_confirmed(
  p_booking_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare b public.package_bookings;
begin
  select * into b from public.package_bookings where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if coalesce(b.downpayment_amount, 0) <= 0 then return true; end if;
  return exists (
    select 1 from public.payment_records pr
    where pr.booking_id = p_booking_id
      and pr.payment_stage in ('down_payment', 'full')
      and pr.status = 'confirmed'
      and pr.amount >= b.downpayment_amount
  );
end;
$$;
revoke all on function public.is_booking_downpayment_confirmed(uuid)
  from public, anon, authenticated;

-- Repair only unpaid, active, pre-tour legacy same-day rows. Completed or
-- already-paid records retain their historical amounts and audit evidence.
select set_config('touristrike.validated_transition', 'true', true);
update public.package_bookings b
set downpayment_amount = round(b.total_amount * 0.50, 2),
    remaining_balance = b.total_amount - round(b.total_amount * 0.50, 2),
    updated_at = now()
where lower(coalesce(b.booking_type, '')) = 'same_day'
  and coalesce(b.downpayment_amount, 0) = 0
  and lower(coalesce(b.booking_status, b.status, ''))
      in ('pending', 'waiting_for_drivers', 'accepted', 'confirmed')
  and b.picked_up_at is null
  and not exists (
    select 1 from public.payment_records pr
    where pr.booking_id = b.id and pr.status <> 'cancelled'
  );
select set_config('touristrike.validated_transition', '', true);

do $$
declare v_booking_id uuid;
begin
  for v_booking_id in
    select b.id from public.package_bookings b
    where lower(coalesce(b.booking_type, '')) = 'same_day'
      and b.downpayment_amount = round(b.total_amount * 0.50, 2)
      and public.is_booking_driver_roster_full(b.id)
      and lower(coalesce(b.booking_status, b.status, ''))
          in ('accepted', 'confirmed')
  loop
    perform public.ensure_booking_payment_requirements(v_booking_id);
  end loop;
end;
$$;

-- A booking_drivers row is retained as immutable booking-scoped participation
-- history. Any prior row (accepted, cancelled, rejected, or completed) makes
-- the driver ineligible for that same replacement search. The existing
-- accept_package_booking RPC also rejects reinsertion when any row exists.
create or replace function public.can_inspect_available_tour_assignment(
  p_booking_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.package_bookings b
    join public.profiles actor on actor.id = auth.uid()
    where b.id = p_booking_id
      and actor.role = 'driver'
      and lower(coalesce(b.booking_status, b.status, ''))
          in ('pending', 'waiting_for_drivers')
      and public.cities_match(b.municipality, actor.city)
      and nullif(trim(actor.province), '') is not null
      and public.cities_match(b.province, actor.province)
      and not exists (
        select 1 from public.booking_drivers prior_assignment
        where prior_assignment.booking_id = b.id
          and prior_assignment.driver_id = actor.id
      )
      and (
        select count(*) from public.booking_drivers active_assignment
        where active_assignment.booking_id = b.id
          and active_assignment.status in ('accepted', 'completed')
      ) < greatest(coalesce(b.required_drivers, 1), 1)
      and not exists (
        select 1 from public.driver_details details
        where details.driver_id = actor.id
          and lower(coalesce(details.status, ''))
              in ('disabled', 'inactive', 'rejected', 'suspended')
      )
      and (
        exists (
          select 1 from public.driver_details details
          where details.driver_id = actor.id
            and (
              lower(coalesce(details.status, ''))
                  in ('active', 'approved', 'verified')
              or (coalesce(details.status, '') = ''
                  and details.approved_at is not null)
            )
        )
        or (
          select lower(application.status)
          from public.driver_applications application
          where application.driver_id = actor.id
          order by application.submitted_at desc
          limit 1
        ) in ('active', 'approved', 'verified')
      )
  );
$$;
revoke all on function public.can_inspect_available_tour_assignment(uuid)
  from public, anon, authenticated;

commit;
