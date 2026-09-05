-- Isolated PostgreSQL fixture for the migration regression runner. This is
-- never applied to an application database; unrelated services are stubbed.
create role anon; create role authenticated;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
create table profiles(id uuid primary key, full_name text, first_name text, last_name text, profile_image_url text, role text,
  average_rating numeric default 0, total_reviews integer default 0, updated_at timestamptz);
create function current_profile_role() returns text language sql stable as $$ select role from profiles where id = auth.uid() $$;
create table tour_packages(id bigint primary key, title text);
create table package_bookings(id uuid primary key, tourist_id uuid, package_id bigint, booking_status text, status text,
  required_drivers integer default 2, scheduled_start_at timestamptz default now(), estimated_end_at timestamptz default now() + interval '1 day',
  pickup_latitude double precision default 15, pickup_longitude double precision default 121,
  dropoff_latitude double precision default 15, dropoff_longitude double precision default 121,
  current_spot_index integer default 0, updated_at timestamptz, arrived_at timestamptz, picked_up_at timestamptz,
  test_mode boolean default false, remaining_balance numeric default 3600, completed_at timestamptz);
create table package_activities(id uuid primary key, booking_id uuid references package_bookings, tour_status text, status text,
  current_spot_index integer default 0, dropped_off_at timestamptz, arrived_at timestamptz, picked_up_at timestamptz, updated_at timestamptz);
create table booking_drivers(id uuid primary key, booking_id uuid references package_bookings, driver_id uuid references profiles,
  status text, journey_state text, current_stop_index integer default 0, state_updated_at timestamptz default now(),
  accepted_at timestamptz default now(), completed_at timestamptz, unique(booking_id, driver_id));
create table booking_itinerary_items(id uuid primary key, booking_id uuid references package_bookings,
  destination_name text, order_number integer, destination_order integer, arrival_time time, departure_time time,
  estimated_stay_duration_minutes integer default 10, latitude double precision default 15, longitude double precision default 121,
  created_at timestamptz default now(), updated_at timestamptz, spot_status text default 'pending', actual_arrival_time timestamptz, actual_departure_time timestamptz);
create table booking_driver_arrivals(booking_driver_id uuid references booking_drivers, itinerary_item_id uuid references booking_itinerary_items,
  arrived_at timestamptz default now(), latitude double precision, longitude double precision, primary key(booking_driver_id, itinerary_item_id));
create table driver_live_locations(driver_id uuid primary key, latitude double precision, longitude double precision, updated_at timestamptz default now());
create table booking_participant_live_locations(booking_id uuid, user_id uuid, latitude double precision, longitude double precision,
  accuracy_meters double precision, updated_at timestamptz default now());
create table package_reviews(id uuid default gen_random_uuid(), booking_id uuid references package_bookings, tourist_id uuid references profiles,
  package_id bigint references tour_packages, rating integer check(rating between 1 and 5), review_text text, created_at timestamptz default now(), unique(booking_id, tourist_id));
create table driver_reviews(id uuid default gen_random_uuid(), booking_id uuid references package_bookings, tourist_id uuid references profiles,
  driver_id uuid references profiles, rating integer check(rating between 1 and 5), review_text text, created_at timestamptz default now(), unique(booking_id, driver_id, tourist_id));
create table payment_records(id uuid primary key, booking_id uuid, status text, payment_stage text, paid_at timestamptz, amount numeric);
create table payment_allocations(id uuid primary key default gen_random_uuid(), payment_record_id uuid references payment_records,
  driver_id uuid, driver_amount numeric, status text, paid_at timestamptz);
create table trip_status_logs(activity_id uuid, booking_id uuid, driver_id uuid, status text, previous_state text, new_state text,
  spot_index integer, logged_at timestamptz default now(), notes text);
create publication supabase_realtime;
create function is_package_booking_participant(uuid) returns boolean language sql stable as $$
 select exists(select 1 from package_bookings where id = $1 and tourist_id = auth.uid()) or
 exists(select 1 from booking_drivers where booking_id = $1 and driver_id = auth.uid()) $$;
create function is_developer_test_booking(uuid) returns boolean language sql stable as $$ select test_mode from package_bookings where id = $1 $$;
create function journey_state_order(text) returns integer language sql immutable as $$ select array_position(
 array['assigned','en_route_pickup','at_pickup','boarded','en_route_stop','at_stop','stop_done','en_route_dropoff','at_dropoff','completed'], $1) $$;
create function package_booking_schedule_window(package_bookings) returns tstzrange language sql stable as $$ select tstzrange($1.scheduled_start_at, $1.estimated_end_at) $$;
create function is_booking_downpayment_confirmed(uuid) returns boolean language sql stable as $$ select exists(select 1 from payment_records
 where booking_id = $1 and status = 'confirmed' and payment_stage in ('down_payment','full')) $$;
create function is_booking_remaining_payment_satisfied(uuid) returns boolean language sql stable as $$ select exists(select 1 from payment_records
 where booking_id = $1 and status = 'confirmed' and payment_stage in ('remaining_balance','full')) $$;
create function is_booking_itinerary_complete(uuid) returns boolean language sql stable as $$ select not exists(select 1 from booking_itinerary_items
 where booking_id = $1 and spot_status <> 'completed') $$;
create function finalize_package_booking_if_eligible(uuid) returns jsonb language plpgsql as $$
begin
 if not exists(select 1 from booking_drivers where booking_id = $1 and status <> 'completed') and is_booking_remaining_payment_satisfied($1) then
   update package_bookings set status = 'completed', booking_status = 'completed' where id = $1;
   return '{"overall_completed":true}'::jsonb;
 end if;
 return '{"overall_completed":false}'::jsonb;
end $$;
create function insert_booking_system_message(uuid,text,text) returns void language sql as $$ select $$;

create table public.notifications(user_id uuid, title text, body text, type text, is_read boolean, dedupe_key text);
create unique index notifications_dedupe on public.notifications(dedupe_key) where dedupe_key is not null;

create table booking_payment_requirements(booking_id uuid, payment_stage text, status text, amount numeric, satisfied_by_payment_record_id uuid);
