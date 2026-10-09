-- Count every participant toward vehicle capacity while requiring at least
-- one accompanying adult whenever children are included.
begin;

create or replace function public.validate_booking_schedule_and_capacity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_capacity integer := public.tricycle_passenger_capacity();
  v_minimum integer;
begin
  if tg_op = 'INSERT'
     or new.scheduled_start_at is distinct from old.scheduled_start_at
     or new.estimated_end_at is distinct from old.estimated_end_at
     or new.travel_date is distinct from old.travel_date then
    if new.scheduled_start_at is null or new.estimated_end_at is null
       or new.estimated_end_at <= new.scheduled_start_at then
      raise exception 'INVALID_BOOKING_SCHEDULE_WINDOW';
    end if;
    if new.travel_date <>
       (new.scheduled_start_at at time zone 'Asia/Manila')::date then
      raise exception 'PICKUP_DATE_TIME_MISMATCH';
    end if;
  end if;

  if tg_op = 'INSERT'
     or new.total_passengers is distinct from old.total_passengers
     or new.required_drivers is distinct from old.required_drivers
     or new.adults is distinct from old.adults
     or new.children is distinct from old.children then
    if coalesce(new.children, 0) > 0 and coalesce(new.adults, 0) = 0 then
      raise exception 'CHILDREN_REQUIRE_ADULT';
    end if;
    if new.adults < 1 or new.children < 0 or new.total_passengers < 1
       or new.total_passengers is distinct from new.adults + new.children then
      raise exception 'INVALID_PASSENGER_COUNT';
    end if;

    v_minimum := public.minimum_required_tricycles(new.total_passengers);
    if coalesce(new.additional_tricycle_count, 0) > 0 then
      -- Preserve already-approved historical additional-tricycle requests.
      if new.required_drivers is distinct from
          v_minimum + coalesce(new.additional_tricycle_approved_count, 0) then
        raise exception 'TRICYCLE_COUNT_MUST_MATCH_APPROVED_REQUIREMENT';
      end if;
    elsif new.required_drivers < v_minimum
       or new.required_drivers > new.total_passengers
       or new.total_passengers > new.required_drivers * v_capacity then
      raise exception 'INVALID_SELECTED_TRICYCLE_COUNT';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.validate_booking_schedule_and_capacity()
  from public, anon, authenticated;

-- Preserve the municipal and account restriction gates from the current
-- booking wrapper; only replace its selected-vehicle validation.
create or replace function public.create_package_booking(
  p_booking jsonb,
  p_customized_spots jsonb default '[]'::jsonb,
  p_itinerary_items jsonb default '[]'::jsonb
) returns public.package_bookings language plpgsql security definer
set search_path = '' as $$
declare
  v_until timestamptz;
  v_selected integer;
  v_adults integer;
  v_children integer;
  v_total integer;
  v_capacity integer := public.tricycle_passenger_capacity();
  v_city text;
  v_province text;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  select restricted_until into v_until
  from public.tourist_booking_restrictions
  where tourist_id = auth.uid() and status = 'active'
    and restricted_until > clock_timestamp();
  if v_until is not null then
    raise exception 'NEW_BOOKINGS_TEMPORARILY_RESTRICTED until %', v_until;
  end if;

  if p_booking ? 'selected_total_tricycles' then
    v_selected := (p_booking->>'selected_total_tricycles')::integer;
    v_adults := (p_booking->>'adults')::integer;
    v_children := coalesce((p_booking->>'children')::integer, 0);
    v_total := v_adults + v_children;
    if v_children > 0 and coalesce(v_adults, 0) = 0 then
      raise exception 'CHILDREN_REQUIRE_ADULT';
    end if;
    if v_adults is null or v_adults < 1 or v_children < 0
       or v_selected is null
       or v_selected < public.minimum_required_tricycles(v_total)
       or v_selected > v_total
       or v_total > v_selected * v_capacity
       or (p_booking->>'total_passengers')::integer is distinct from v_total
       or (p_booking->>'required_drivers')::integer is distinct from v_selected
       or coalesce((p_booking->>'additional_tricycle_count')::integer, 0) <> 0 then
      raise exception 'INVALID_SELECTED_TRICYCLE_COUNT';
    end if;
  elsif coalesce((p_booking->>'additional_tricycle_count')::integer, 0) > 0 then
    raise exception 'ADDITIONAL_TRICYCLE_REQUEST_RETIRED';
  end if;

  select p.city, office.province into v_city, v_province
  from public.tour_packages p
  join public.subtenant_details office on office.id = p.submitted_by
  where p.id = (p_booking->>'package_id')::bigint;
  if v_city is null or v_province is null then
    raise exception 'PACKAGE_MUNICIPAL_OWNER_REQUIRED' using errcode = '42501';
  end if;
  if public.municipal_restriction_active(auth.uid(), v_city, v_province) then
    raise exception 'MUNICIPAL_TOURIST_BOOKING_RESTRICTED'
      using errcode = '42501';
  end if;

  return public.create_package_booking_restriction_impl(
    p_booking, p_customized_spots, p_itinerary_items);
end $$;
revoke all on function public.create_package_booking(jsonb, jsonb, jsonb)
  from public, anon;
grant execute on function public.create_package_booking(jsonb, jsonb, jsonb)
  to authenticated;

commit;
