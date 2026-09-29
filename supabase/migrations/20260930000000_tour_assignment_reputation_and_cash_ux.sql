begin;

-- Reuse the acceptance approval and municipality boundary for pre-acceptance reads.
create or replace function public.can_inspect_available_tour_assignment(p_booking_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.package_bookings b join public.profiles actor on actor.id = auth.uid()
    where b.id = p_booking_id and actor.role = 'driver'
      and lower(coalesce(b.booking_status, b.status, '')) in ('pending', 'waiting_for_drivers')
      and public.cities_match(b.municipality, actor.city)
      and nullif(trim(actor.province), '') is not null
      and public.cities_match(b.province, actor.province)
      and (select count(*) from public.booking_drivers d where d.booking_id = b.id
        and d.status in ('accepted', 'completed')) < greatest(coalesce(b.required_drivers, 1), 1)
      and not exists (select 1 from public.driver_details d where d.driver_id = actor.id
        and lower(coalesce(d.status, '')) in ('disabled', 'inactive', 'rejected', 'suspended'))
      and (
        exists (select 1 from public.driver_details d where d.driver_id = actor.id
          and (lower(coalesce(d.status, '')) in ('active', 'approved', 'verified')
            or (coalesce(d.status, '') = '' and d.approved_at is not null)))
        or (select lower(a.status) from public.driver_applications a where a.driver_id = actor.id
          order by a.submitted_at desc limit 1) in ('active', 'approved', 'verified')
      )
  );
$$;
revoke all on function public.can_inspect_available_tour_assignment(uuid) from public, anon, authenticated;

-- The activity's nested booking select is masked by participant RLS before
-- acceptance. Provide just the decision-making snapshot through this vetted RPC.
create or replace function public.get_available_tour_assignments(p_limit integer default 30)
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or public.current_profile_role() is distinct from 'driver' then
    raise exception 'DRIVER_ROLE_REQUIRED' using errcode = '42501'; end if;
  return query
  select jsonb_build_object('id', a.id, 'booking_id', b.id,
    'tourist_id', b.tourist_id, 'package_id', b.package_id, 'status', 'pending', 'price', b.total_amount,
    'tour_packages', jsonb_build_object('title', p.title, 'city', p.city),
    'package_bookings', jsonb_build_object('id', b.id, 'travel_date', b.travel_date,
      'scheduled_start_at', b.scheduled_start_at, 'estimated_end_at', b.estimated_end_at,
      'adults', b.adults, 'children', b.children, 'total_passengers', b.total_passengers,
      'booking_type', b.booking_type, 'booking_status', b.booking_status, 'status', b.status,
      'pickup_address', b.pickup_address, 'dropoff_address', b.dropoff_address,
      'required_drivers', b.required_drivers, 'accepted_drivers_count', b.accepted_drivers_count,
      'municipality', b.municipality, 'province', b.province, 'total_amount', b.total_amount),
    'itinerary_items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id,
      'booking_id', i.booking_id, 'destination_name', i.destination_name,
      'destination_address', i.destination_address, 'arrival_time', i.arrival_time,
      'departure_time', i.departure_time, 'order_number', i.order_number,
      'destination_order', i.destination_order, 'source_type', i.source_type, 'spot_status', i.spot_status)
      order by i.order_number, i.destination_order) from public.booking_itinerary_items i
      where i.booking_id = b.id), '[]'::jsonb))
  from public.package_bookings b join public.tour_packages p on p.id = b.package_id
  join lateral (select activity.id from public.package_activities activity
    where activity.booking_id = b.id order by activity.created_at limit 1) a on true
  where public.can_inspect_available_tour_assignment(b.id)
  order by b.created_at, b.id limit greatest(1, least(coalesce(p_limit, 30), 60));
end $$;
revoke all on function public.get_available_tour_assignments(integer) from public, anon;
grant execute on function public.get_available_tour_assignments(integer) to authenticated;

-- A booking-scoped, minimal projection for participating/eligible drivers.
-- No profile policy changes and no driver identities in returned reviews.
create or replace function public.get_booking_tourist_reputation(p_booking_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  b public.package_bookings;
  actor public.profiles;
  v_average numeric;
  v_count bigint;
  v_distribution jsonb;
  v_reviews jsonb;
  v_name text;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED' using errcode = '42501'; end if;
  select * into actor from public.profiles where id = auth.uid();
  if actor.role is distinct from 'driver' then
    raise exception 'DRIVER_ROLE_REQUIRED' using errcode = '42501';
  end if;
  select * into b from public.package_bookings where id = p_booking_id;
  if not found then raise exception 'BOOKING_ACCESS_DENIED' using errcode = '42501'; end if;
  if not (
    exists (select 1 from public.booking_drivers d where d.booking_id = b.id
      and d.driver_id = actor.id and d.status in ('accepted', 'completed'))
    or (b.assigned_driver_id = actor.id and public.can_read_tour_booking(b.id))
    or public.can_inspect_available_tour_assignment(b.id)
  ) then raise exception 'BOOKING_ACCESS_DENIED' using errcode = '42501'; end if;

  select coalesce(nullif(trim(p.full_name), ''), nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''))
    into v_name from public.profiles p where p.id = b.tourist_id;
  select round(avg(r.rating), 2), count(*) into v_average, v_count
    from public.tourist_reviews r where r.tourist_id = b.tourist_id;
  select jsonb_object_agg(star::text, n) into v_distribution from (
    select star, count(r.id) as n from generate_series(1, 5) star
    left join public.tourist_reviews r on r.rating = star and r.tourist_id = b.tourist_id
    group by star
  ) distribution;
  select coalesce(jsonb_agg(jsonb_build_object('rating', r.rating,
    'review_text', r.review_text, 'created_at', r.created_at) order by r.created_at desc, r.id), '[]'::jsonb)
    into v_reviews from (select id, rating, review_text, created_at from public.tourist_reviews
      where tourist_id = b.tourist_id order by created_at desc, id limit 20) r;
  return jsonb_build_object('display_name', v_name, 'average_rating', v_average,
    'total_reviews', v_count, 'distribution', v_distribution, 'reviews', v_reviews);
end $$;
revoke all on function public.get_booking_tourist_reputation(uuid) from public, anon;
grant execute on function public.get_booking_tourist_reputation(uuid) to authenticated;

-- Applies to RPC, service and direct writes, including changes in passenger mix.
-- Existing minimum-capacity and schedule validation remains in place.
create or replace function public.guard_single_passenger_tricycle_quantity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (new.total_passengers = 1 or coalesce(new.adults, 0) + coalesce(new.children, 0) = 1)
     and new.required_drivers > 1 then
    raise exception 'SINGLE_PASSENGER_ONE_TRICYCLE_REQUIRED' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger guard_single_passenger_tricycle_quantity
before insert or update of adults, children, total_passengers, required_drivers
on public.package_bookings for each row
execute function public.guard_single_passenger_tricycle_quantity();
revoke all on function public.guard_single_passenger_tricycle_quantity() from public, anon, authenticated;

-- Keep the existing cash ledger and settlement trigger. Serialize with preparation
-- (booking before payment), and make an authorized retry safe after completion.
create or replace function public.confirm_group_cash_share(p_payment_record_id uuid)
returns public.payment_records language plpgsql security definer set search_path = '' as $$
declare
  v_payment public.payment_records;
  v_allocation public.payment_allocations;
  v_booking public.package_bookings;
  v_booking_id uuid;
begin
  if auth.uid() is null or public.current_profile_role() is distinct from 'driver' then
    raise exception 'DRIVER_ROLE_REQUIRED' using errcode = '42501'; end if;
  select booking_id into v_booking_id from public.payment_records where id = p_payment_record_id;
  if not found then raise exception 'PAYMENT_RECORD_NOT_FOUND'; end if;
  select * into v_booking from public.package_bookings where id = v_booking_id for update;
  select * into v_payment from public.payment_records where id = p_payment_record_id for update;
  if v_payment.provider <> 'manual' or v_payment.payment_method <> 'cash'
     or v_payment.payment_stage <> 'remaining_balance' or v_payment.payee_id is not null then
    raise exception 'GROUP_CASH_PAYMENT_REQUIRED'; end if;
  select * into v_allocation from public.payment_allocations
    where payment_record_id = v_payment.id and driver_id = auth.uid() for update;
  if not found or not exists (select 1 from public.booking_drivers d
    where d.id = v_allocation.booking_driver_id and d.booking_id = v_booking.id
      and d.driver_id = auth.uid() and d.status in ('accepted', 'completed')) then
    raise exception 'NOT_ASSIGNED_PAYMENT_DRIVER' using errcode = '42501'; end if;
  if v_allocation.status = 'cash_confirmed' then return v_payment; end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
       in ('cancelled', 'completed', 'rejected', 'done', 'expired') then
    raise exception 'BOOKING_NOT_ACTIVE'; end if;
  if v_payment.status <> 'pending_confirmation' or v_allocation.status <> 'awaiting_cash' then
    raise exception 'CASH_SHARE_NOT_CONFIRMABLE'; end if;
  if v_payment.amount <> round(v_booking.remaining_balance, 2) or not exists (
    select 1 from public.booking_payment_requirements r where r.booking_id = v_booking.id
      and r.payment_stage = 'remaining_balance' and r.status = 'required' and r.amount = v_payment.amount
  ) then raise exception 'CASH_PAYMENT_STATE_CHANGED'; end if;

  update public.payment_allocations set status = 'cash_confirmed', paid_at = now(), last_error = null
    where id = v_allocation.id;
  if not exists (select 1 from public.payment_allocations
      where payment_record_id = v_payment.id and status <> 'cash_confirmed') then
    update public.payment_records set status = 'confirmed', provider_status = 'cash_received', paid_at = now()
      where id = v_payment.id returning * into v_payment;
    update public.booking_payment_requirements set status = 'satisfied',
      satisfied_at = coalesce(satisfied_at, now()),
      satisfied_by_payment_record_id = coalesce(satisfied_by_payment_record_id, v_payment.id)
      where booking_id = v_payment.booking_id and payment_stage = 'remaining_balance'
        and amount = v_payment.amount and status = 'required';
  end if;
  return v_payment;
end $$;
revoke all on function public.confirm_group_cash_share(uuid) from public, anon;
grant execute on function public.confirm_group_cash_share(uuid) to authenticated;

commit;
