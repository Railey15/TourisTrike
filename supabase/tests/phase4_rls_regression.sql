-- Phase 4 live RLS regression script.
-- Run in Supabase SQL Editor as a database administrator after all four phases.
-- All mutation checks are wrapped in a transaction and rolled back.

begin;

create temporary table phase4_context on commit drop as
with subtenants as (
  select id, city, row_number() over (order by city, id) as position
  from public.subtenant_details
  where is_active = true
    and nullif(trim(city), '') is not null
), participant_booking as (
  select booking.id as booking_id,
         booking.tourist_id,
         driver.driver_id
  from public.package_bookings booking
  join public.booking_drivers driver on driver.booking_id = booking.id
  where driver.status in ('accepted', 'completed')
  order by booking.created_at desc
  limit 1
)
select
  (select id from subtenants where position = 1) as subtenant_a,
  (select city from subtenants where position = 1) as city_a,
  (select id from subtenants where position = 2) as subtenant_b,
  (select city from subtenants where position = 2) as city_b,
  (select id from public.profiles where role = 'admin' order by created_at limit 1)
    as admin_id,
  (select booking_id from participant_booking) as booking_id,
  (select tourist_id from participant_booking) as tourist_id,
  (select driver_id from participant_booking) as driver_id,
  (select id from public.tourist_spots order by created_at limit 1) as spot_id,
  (select id from public.tourist_spots
   where public.cities_match(
     city,
     (select city from subtenants where position = 2)
   )
   order by created_at desc
   limit 1) as cross_city_spot_id,
  (select id from public.tour_packages
   where public.cities_match(
     city,
     (select city from subtenants where position = 2)
   )
   order by created_at desc
   limit 1) as cross_city_package_id,
  (select booking.id
   from public.package_bookings booking
   join public.tour_packages package on package.id = booking.package_id
   where public.cities_match(
     package.city,
     (select city from subtenants where position = 2)
   )
   order by booking.created_at desc
   limit 1) as cross_city_booking_id,
  (select payment.id
   from public.payment_records payment
   join public.package_bookings booking on booking.id = payment.booking_id
   join public.tour_packages package on package.id = booking.package_id
   where public.cities_match(
     package.city,
     (select city from subtenants where position = 2)
   )
   order by payment.created_at desc
   limit 1) as cross_city_payment_id,
  (select dispute.id
   from public.payment_disputes dispute
   join public.payment_records payment
     on payment.id = dispute.payment_record_id
   join public.package_bookings booking on booking.id = payment.booking_id
   join public.tour_packages package on package.id = booking.package_id
   where public.cities_match(
     package.city,
     (select city from subtenants where position = 2)
   )
   order by dispute.created_at desc
   limit 1) as cross_city_dispute_id;

grant select on phase4_context to authenticated;

-- Stop here and create fixtures if this row contains null IDs, or if city_a and
-- city_b are equal. Two active municipality assignments and one accepted or
-- completed booking are required for a meaningful test.
table phase4_context;

-- -------------------------------------------------------------------------
-- Subtenant A: every cross-city count must be zero.
-- -------------------------------------------------------------------------
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  (select subtenant_a::text from phase4_context),
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select 'cross_city_spots' as check_name, count(*) as must_be_zero
from public.tourist_spots
where public.cities_match(
  city,
  (select city_b from phase4_context)
);

select 'cross_city_packages' as check_name, count(*) as must_be_zero
from public.tour_packages
where public.cities_match(
  city,
  (select city_b from phase4_context)
);

select 'cross_city_drivers' as check_name, count(*) as must_be_zero
from public.profiles
where role = 'driver'
  and public.cities_match(
    city,
    (select city_b from phase4_context)
  );

select 'cross_city_bookings' as check_name, count(*) as must_be_zero
from public.package_bookings
where id = (select cross_city_booking_id from phase4_context);

select 'cross_city_payments' as check_name, count(*) as must_be_zero
from public.payment_records
where id = (select cross_city_payment_id from phase4_context);

select 'cross_city_disputes' as check_name, count(*) as must_be_zero
from public.payment_disputes
where id = (select cross_city_dispute_id from phase4_context);

do $$
declare
  changed integer;
begin
  update public.tourist_spots
  set status = status
  where id = (select cross_city_spot_id from phase4_context);
  get diagnostics changed = row_count;
  if changed > 0 then
    raise exception 'FAILED: subtenant updated a cross-city spot';
  end if;
  raise notice 'PASS: cross-city spot update was blocked';
end;
$$;

do $$
declare
  changed integer;
begin
  update public.tour_packages
  set status = status
  where id = (select cross_city_package_id from phase4_context);
  get diagnostics changed = row_count;
  if changed > 0 then
    raise exception 'FAILED: subtenant updated a cross-city package';
  end if;
  raise notice 'PASS: cross-city package update was blocked';
end;
$$;

do $$
declare
  changed integer;
begin
  update public.subtenant_details
  set city = (select city_b from phase4_context)
  where id = (select subtenant_a from phase4_context);
  get diagnostics changed = row_count;
  if changed > 0 then
    raise exception 'FAILED: subtenant changed its assignment';
  end if;
exception
  when insufficient_privilege then
    raise notice 'PASS: municipality assignment change was blocked';
end;
$$;

do $$
declare
  changed integer;
begin
  update public.subtenant_details
  set local_government_type = case
    when local_government_type = 'city' then 'municipality'
    else 'city'
  end
  where id = (select subtenant_a from phase4_context);
  get diagnostics changed = row_count;
  if changed > 0 then
    raise exception 'FAILED: subtenant changed its LGU classification';
  end if;
exception
  when insufficient_privilege then
    raise notice 'PASS: LGU classification change was blocked';
end;
$$;

reset role;

-- -------------------------------------------------------------------------
-- Provincial Admin: all expected counts should be nonzero when fixtures exist.
-- Updates are rolled back at the end.
-- -------------------------------------------------------------------------
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  (select admin_id::text from phase4_context),
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select 'admin_subtenants' as check_name, count(*) as visible_rows
from public.subtenant_details;
select 'admin_spots' as check_name, count(*) as visible_rows
from public.tourist_spots;
select 'admin_packages' as check_name, count(*) as visible_rows
from public.tour_packages;
select 'admin_drivers' as check_name, count(*) as visible_rows
from public.profiles where role = 'driver';
select 'admin_bookings' as check_name, count(*) as visible_rows
from public.package_bookings;
select 'admin_notifications' as check_name, count(*) as own_rows
from public.notifications
where user_id = (select admin_id from phase4_context);

do $$
declare
  changed integer;
begin
  update public.tourist_spots
  set verification_status = 'verified'
  where id = (select spot_id from phase4_context);
  get diagnostics changed = row_count;
  if changed <> 1 then
    raise exception 'FAILED: admin could not moderate a spot';
  end if;
  raise notice 'PASS: admin spot moderation allowed';
end;
$$;

do $$
declare
  changed integer;
begin
  update public.subtenant_details
  set local_government_type_reviewed = true
  where id = (select subtenant_a from phase4_context);
  get diagnostics changed = row_count;
  if changed <> 1 then
    raise exception 'FAILED: admin could not review LGU classification';
  end if;
  raise notice 'PASS: admin LGU classification review allowed';
end;
$$;

reset role;

-- -------------------------------------------------------------------------
-- Tourist and accepted/completed driver: booking visibility must be one.
-- Related payment/trip counts may be zero only when the fixture has no rows.
-- -------------------------------------------------------------------------
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  (select tourist_id::text from phase4_context),
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select 'tourist_booking' as check_name, count(*) as must_be_one
from public.package_bookings
where id = (select booking_id from phase4_context);
select 'tourist_payments' as check_name, count(*) as participant_rows
from public.payment_records
where booking_id = (select booking_id from phase4_context);
select 'tourist_trip_logs' as check_name, count(*) as participant_rows
from public.trip_status_logs
where booking_id = (select booking_id from phase4_context);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  (select driver_id::text from phase4_context),
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select 'driver_booking' as check_name, count(*) as must_be_one
from public.package_bookings
where id = (select booking_id from phase4_context);
select 'driver_payment_allocations' as check_name, count(*) as participant_rows
from public.payment_allocations
where booking_id = (select booking_id from phase4_context)
  and driver_id = (select driver_id from phase4_context);
select 'driver_trip_logs' as check_name, count(*) as participant_rows
from public.trip_status_logs
where booking_id = (select booking_id from phase4_context);

reset role;
rollback;
