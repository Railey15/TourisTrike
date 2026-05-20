create table if not exists public.booking_itinerary_items (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.package_bookings(id) on delete cascade,
  tourist_id uuid not null references auth.users(id) on delete cascade,
  spot_id bigint references public.tourist_spots(id) on delete set null,
  destination_name text not null,
  destination_address text,
  destination_order integer not null,
  arrival_time time without time zone,
  estimated_stay_duration_minutes integer not null default 0,
  departure_time time without time zone,
  activity_note text,
  source_type text not null default 'ai_suggested'
    check (source_type in ('ai_suggested', 'customized')),
  google_place_id text,
  municipality text,
  barangay text,
  latitude double precision,
  longitude double precision,
  image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists booking_itinerary_items_booking_idx
  on public.booking_itinerary_items(booking_id, destination_order);

create index if not exists booking_itinerary_items_tourist_idx
  on public.booking_itinerary_items(tourist_id, created_at desc);

create unique index if not exists booking_itinerary_items_booking_order_unique
  on public.booking_itinerary_items(booking_id, destination_order);

drop trigger if exists set_booking_itinerary_items_updated_at on public.booking_itinerary_items;
create trigger set_booking_itinerary_items_updated_at
before update on public.booking_itinerary_items
for each row execute function public.set_updated_at();

alter table public.booking_itinerary_items enable row level security;

drop policy if exists booking_itinerary_items_select on public.booking_itinerary_items;
create policy booking_itinerary_items_select on public.booking_itinerary_items
for select to authenticated using (
  tourist_id = auth.uid()
  or exists (
    select 1
    from public.package_bookings b
    where b.id = booking_id
      and b.assigned_driver_id = auth.uid()
  )
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
  or (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid() and p.role = 'subtenant'
    )
    and exists (
      select 1
      from public.package_bookings b
      join public.tour_packages pkg on pkg.id = b.package_id
      where b.id = booking_id
        and pkg.city = public.current_profile_city()
    )
  )
);

drop policy if exists booking_itinerary_items_insert on public.booking_itinerary_items;
create policy booking_itinerary_items_insert on public.booking_itinerary_items
for insert to authenticated with check (
  tourist_id = auth.uid()
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

drop policy if exists booking_itinerary_items_update on public.booking_itinerary_items;
create policy booking_itinerary_items_update on public.booking_itinerary_items
for update to authenticated
using (
  tourist_id = auth.uid()
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
)
with check (
  tourist_id = auth.uid()
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

drop policy if exists booking_itinerary_items_delete on public.booking_itinerary_items;
create policy booking_itinerary_items_delete on public.booking_itinerary_items
for delete to authenticated using (
  tourist_id = auth.uid()
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);
