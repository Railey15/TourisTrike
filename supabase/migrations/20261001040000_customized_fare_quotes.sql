begin;

-- Only the server route-quote function can insert a quote. The booking RPC
-- consumes it atomically after checking user, route, package, and price.
create table public.booking_custom_fare_quotes (
  id uuid primary key default gen_random_uuid(),
  tourist_id uuid not null references public.profiles(id),
  package_id bigint not null references public.tour_packages(id),
  route_points jsonb not null check (jsonb_typeof(route_points) = 'array'),
  route_distance_meters integer not null check (route_distance_meters >= 0),
  original_distance_meters integer not null check (original_distance_meters >= 0),
  base_unit_price numeric(14,2) not null check (base_unit_price >= 0),
  route_surcharge numeric(14,2) not null check (route_surcharge >= 0),
  unit_price numeric(14,2) not null check (unit_price = base_unit_price + route_surcharge),
  fare_settings_updated_at timestamptz not null,
  package_updated_at timestamptz not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  used_at timestamptz,
  booking_id uuid references public.package_bookings(id)
);
create index booking_custom_fare_quotes_owner_idx
on public.booking_custom_fare_quotes(tourist_id,created_at desc);
alter table public.booking_custom_fare_quotes enable row level security;
revoke all on public.booking_custom_fare_quotes from public,anon,authenticated;
grant select on public.booking_custom_fare_quotes to authenticated;
grant all on public.booking_custom_fare_quotes to service_role;
-- The server-side quote function calls the existing service-area helpers.
grant execute on function public.resolve_booking_service_area(bigint),
  public.service_area_covers(jsonb,double precision,double precision)
  to service_role;
create policy booking_custom_fare_quotes_owner_read
on public.booking_custom_fare_quotes for select to authenticated
using (tourist_id = auth.uid());

create or replace function public.create_package_booking(
  p_booking jsonb, p_customized_spots jsonb default '[]'::jsonb,
  p_itinerary_items jsonb default '[]'::jsonb
) returns public.package_bookings language plpgsql security definer set search_path = '' as $$
declare v_booking public.package_bookings; v_quote public.booking_custom_fare_quotes;
  v_custom boolean; v_points jsonb; v_passengers integer; v_total numeric;
  v_downpayment numeric; v_remaining numeric; v_same_day boolean;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_booking->>'terms_version' is distinct from '1.1' then
    raise exception 'BOOKING_TERMS_REQUIRED';
  end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p_customized_spots,'[]'::jsonb)) s
    where coalesce((s->>'additional_fee')::numeric,0) <> 0) then
    raise exception 'CUSTOM_FARE_AMOUNT_MISMATCH';
  end if;
  v_custom := exists(select 1 from jsonb_array_elements(coalesce(p_customized_spots,'[]'::jsonb)) s
    where s->>'action_type' in ('added','removed'))
    or exists(select 1 from jsonb_array_elements(coalesce(p_itinerary_items,'[]'::jsonb)) item
      where coalesce(item->>'itinerary_source',item->>'source_type')='customized')
    or jsonb_array_length(coalesce(p_itinerary_items,'[]'::jsonb)) <>
      (select count(*) from public.tour_package_spots
        where package_id=(p_booking->>'package_id')::bigint)
    or exists(select 1 from jsonb_array_elements(coalesce(p_itinerary_items,'[]'::jsonb)) item
      where nullif(item->>'spot_id','') is null
        or not exists(select 1 from public.tour_package_spots s
          join public.tourist_spots spot on spot.id=s.spot_id
          where s.package_id=(p_booking->>'package_id')::bigint
            and s.spot_id=(item->>'spot_id')::bigint
            and spot.latitude::numeric=(item->>'latitude')::numeric
            and spot.longitude::numeric=(item->>'longitude')::numeric));
  if v_custom then
    if nullif(p_booking->>'fare_quote_id','') is null then
      raise exception 'CUSTOM_FARE_QUOTE_REQUIRED'; end if;
    select * into v_quote from public.booking_custom_fare_quotes
      where id=(p_booking->>'fare_quote_id')::uuid for update;
    if not found or v_quote.tourist_id is distinct from auth.uid()
       or v_quote.package_id is distinct from (p_booking->>'package_id')::bigint
       or v_quote.used_at is not null or v_quote.expires_at <= now() then
      raise exception 'CUSTOM_FARE_QUOTE_INVALID';
    end if;
    if not exists(select 1 from public.tour_packages p
      join public.subtenant_fare_settings f on f.subtenant_id=p.submitted_by
        and public.cities_match(f.city,p.city) and f.is_active
      where p.id=v_quote.package_id
        and p.updated_at=v_quote.package_updated_at
        and f.updated_at=v_quote.fare_settings_updated_at) then
      raise exception 'CUSTOM_FARE_QUOTE_STALE';
    end if;
    v_points := jsonb_build_array(jsonb_build_array(
      (p_booking->>'pickup_latitude')::numeric,
      (p_booking->>'pickup_longitude')::numeric));
    select v_points || coalesce(jsonb_agg(jsonb_build_array(
      (item->>'latitude')::numeric,(item->>'longitude')::numeric) order by ord),'[]'::jsonb)
      into v_points from jsonb_array_elements(p_itinerary_items) with ordinality x(item,ord);
    v_points := v_points || jsonb_build_array(jsonb_build_array(
      (p_booking->>'dropoff_latitude')::numeric,
      (p_booking->>'dropoff_longitude')::numeric));
    if v_quote.route_points is distinct from v_points then
      raise exception 'CUSTOM_FARE_ROUTE_CHANGED'; end if;
    v_passengers := coalesce((p_booking->>'total_passengers')::integer,
      (p_booking->>'adults')::integer + coalesce((p_booking->>'children')::integer,0));
    if v_passengers < 1 then raise exception 'INVALID_PASSENGER_COUNT'; end if;
    v_total := round(v_quote.unit_price*v_passengers,2);
    v_same_day := ((p_booking->>'scheduled_start_at')::timestamptz
      at time zone 'Asia/Manila')::date = (now() at time zone 'Asia/Manila')::date;
    v_downpayment := case when v_same_day then 0 else round(v_total*0.5,2) end;
    v_remaining := v_total-v_downpayment;
    if (p_booking->>'total_amount')::numeric is distinct from v_total
       or (p_booking->>'downpayment_amount')::numeric is distinct from v_downpayment
       or (p_booking->>'remaining_balance')::numeric is distinct from v_remaining then
      raise exception 'CUSTOM_FARE_AMOUNT_MISMATCH';
    end if;
  end if;
  perform set_config('touristrike.booking_terms_version', '1.1', true);
  select * into v_booking from public.create_package_booking_accepted_terms_impl(
    p_booking,p_customized_spots,p_itinerary_items);
  if v_custom then
    update public.booking_custom_fare_quotes set used_at=now(),booking_id=v_booking.id
      where id=v_quote.id;
  end if;
  return v_booking;
end $$;
revoke all on function public.create_package_booking(jsonb,jsonb,jsonb) from public,anon;
grant execute on function public.create_package_booking(jsonb,jsonb,jsonb) to authenticated;

commit;
