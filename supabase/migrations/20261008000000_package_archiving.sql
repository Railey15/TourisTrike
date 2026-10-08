-- Keep package archival independent from publication and visibility.
alter table public.tour_packages
  add column if not exists archived_at timestamptz;

comment on column public.tour_packages.archived_at is
  'Soft-archive timestamp. NULL means the package is in the active library.';

create index if not exists tour_packages_city_archived_created_idx
  on public.tour_packages (city, archived_at, created_at desc);

create or replace function public.can_access_package_history(
  p_package_id bigint
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.package_bookings booking
    where booking.package_id = p_package_id
      and public.is_package_booking_participant(booking.id)
  );
$$;

revoke all on function public.can_access_package_history(bigint) from public;
grant execute on function public.can_access_package_history(bigint)
  to anon, authenticated;

-- City administrators must be able to manage archived packages, while
-- tourist-facing reads must never expose an archived package or its itinerary.
drop policy if exists packages_read on public.tour_packages;
create policy packages_read on public.tour_packages
for select
using (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
  or public.can_access_package_history(id)
  or (
    public.current_profile_role() is distinct from 'subtenant'
    and archived_at is null
    and status = 'published'
    and visibility_status = 'visible'
  )
);

drop policy if exists package_children_read on public.tour_package_days;
create policy package_children_read on public.tour_package_days
for select to authenticated
using (
  exists (
    select 1
    from public.tour_packages package
    where package.id = package_id
      and (
        public.is_provincial_admin()
        or public.cities_match(
          package.city,
          public.current_subtenant_city()
        )
        or public.can_access_package_history(package.id)
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and package.archived_at is null
          and package.status = 'published'
          and package.visibility_status = 'visible'
        )
      )
  )
);

drop policy if exists package_day_items_read
  on public.tour_package_day_items;
create policy package_day_items_read on public.tour_package_day_items
for select to authenticated
using (
  exists (
    select 1
    from public.tour_package_days day
    join public.tour_packages package on package.id = day.package_id
    where day.id = day_id
      and (
        public.is_provincial_admin()
        or public.cities_match(
          package.city,
          public.current_subtenant_city()
        )
        or public.can_access_package_history(package.id)
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and package.archived_at is null
          and package.status = 'published'
          and package.visibility_status = 'visible'
        )
      )
  )
);

drop policy if exists package_spots_read on public.tour_package_spots;
create policy package_spots_read on public.tour_package_spots
for select to authenticated
using (
  exists (
    select 1
    from public.tour_packages package
    where package.id = package_id
      and (
        public.is_provincial_admin()
        or public.cities_match(
          package.city,
          public.current_subtenant_city()
        )
        or public.can_access_package_history(package.id)
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and package.archived_at is null
          and package.status = 'published'
          and package.visibility_status = 'visible'
        )
      )
  )
);
