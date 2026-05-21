-- ── Group booking fields ─────────────────────────────────────────────────────
alter table public.package_bookings
  add column if not exists required_drivers integer not null default 1,
  add column if not exists accepted_drivers_count integer not null default 0;

-- ── Actual times + spot status on itinerary items ────────────────────────────
alter table public.booking_itinerary_items
  add column if not exists actual_arrival_time timestamptz,
  add column if not exists actual_departure_time timestamptz,
  add column if not exists spot_status text not null default 'pending';

alter table public.booking_itinerary_items
  drop constraint if exists booking_itinerary_items_spot_status_check;
alter table public.booking_itinerary_items
  add constraint booking_itinerary_items_spot_status_check
  check (spot_status in ('pending', 'travelling', 'at_spot', 'completed'));

-- ── booking_drivers (multi-driver group bookings) ────────────────────────────
create table if not exists public.booking_drivers (
  id            uuid primary key default gen_random_uuid(),
  booking_id    uuid not null references public.package_bookings(id) on delete cascade,
  driver_id     uuid not null references public.profiles(id),
  activity_id   uuid references public.package_activities(id),
  status        text not null default 'accepted',
  accepted_at   timestamptz default now(),
  completed_at  timestamptz,
  created_at    timestamptz default now(),
  unique (booking_id, driver_id)
);

alter table public.booking_drivers
  drop constraint if exists booking_drivers_status_check;
alter table public.booking_drivers
  add constraint booking_drivers_status_check
  check (status in ('pending', 'accepted', 'rejected', 'completed'));

-- ── driver_live_locations (high-frequency position table) ────────────────────
create table if not exists public.driver_live_locations (
  driver_id   uuid primary key references public.profiles(id),
  activity_id uuid references public.package_activities(id),
  latitude    double precision not null default 0,
  longitude   double precision not null default 0,
  heading     float not null default 0,
  speed       float not null default 0,
  updated_at  timestamptz default now()
);

-- ── trip_status_logs (audit trail for every status change) ───────────────────
create table if not exists public.trip_status_logs (
  id          uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.package_activities(id) on delete cascade,
  booking_id  uuid references public.package_bookings(id),
  status      text not null,
  spot_index  integer,
  latitude    double precision,
  longitude   double precision,
  logged_at   timestamptz default now(),
  notes       text
);

-- ── RLS ───────────────────────────────────────────────────────────────────────
alter table public.booking_drivers enable row level security;
alter table public.driver_live_locations enable row level security;
alter table public.trip_status_logs enable row level security;

-- booking_drivers policies
drop policy if exists "booking_drivers_read_all" on public.booking_drivers;
create policy "booking_drivers_read_all" on public.booking_drivers
  for select using (true);

drop policy if exists "booking_drivers_driver_insert" on public.booking_drivers;
create policy "booking_drivers_driver_insert" on public.booking_drivers
  for insert with check (auth.uid() = driver_id);

drop policy if exists "booking_drivers_driver_update" on public.booking_drivers;
create policy "booking_drivers_driver_update" on public.booking_drivers
  for update using (auth.uid() = driver_id);

-- driver_live_locations policies
drop policy if exists "live_loc_read_all" on public.driver_live_locations;
create policy "live_loc_read_all" on public.driver_live_locations
  for select using (true);

drop policy if exists "live_loc_driver_upsert" on public.driver_live_locations;
create policy "live_loc_driver_upsert" on public.driver_live_locations
  for insert with check (auth.uid() = driver_id);

drop policy if exists "live_loc_driver_update" on public.driver_live_locations;
create policy "live_loc_driver_update" on public.driver_live_locations
  for update using (auth.uid() = driver_id);

-- trip_status_logs policies
drop policy if exists "trip_logs_read_all" on public.trip_status_logs;
create policy "trip_logs_read_all" on public.trip_status_logs
  for select using (true);

drop policy if exists "trip_logs_insert_any" on public.trip_status_logs;
create policy "trip_logs_insert_any" on public.trip_status_logs
  for insert with check (true);

-- ── Enable realtime on the new live-location table ───────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and tablename = 'driver_live_locations'
  ) then
    alter publication supabase_realtime add table public.driver_live_locations;
  end if;
end $$;
