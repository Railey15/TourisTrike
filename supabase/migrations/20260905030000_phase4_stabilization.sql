-- Phase 4: regression hardening for Phase 1-3 authorization paths.
-- Depends on 20260905020000_phase3_admin_classification_review.sql.

begin;

-- A payment linked to a package booking is scoped by that package. A local
-- payee must not make a payment from another municipality visible.
create or replace function public.subtenant_can_access_payment_record(
  p_payment_record_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_subtenant_city() is not null
     and exists (
       select 1
       from public.payment_records pr
       where pr.id = p_payment_record_id
         and case
           when pr.booking_id is not null then
             public.subtenant_can_access_booking(pr.booking_id)
           when pr.ride_id is not null then exists (
             select 1
             from public.rides r
             where r.id = pr.ride_id
               and public.subtenant_can_access_driver(r.driver_id)
           )
           else false
         end
     );
$$;

revoke all on function public.subtenant_can_access_payment_record(uuid)
  from public, anon, authenticated;
grant execute on function public.subtenant_can_access_payment_record(uuid)
  to authenticated;

-- Public discovery remains available to Tourists, Drivers, and anonymous
-- users. A Subtenant, however, must not inherit that branch to inspect another
-- LGU's content through its staff session.
drop policy if exists spots_read on public.tourist_spots;
create policy spots_read on public.tourist_spots
for select
using (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
  or (
    public.current_profile_role() is distinct from 'subtenant'
    and status <> 'archived'
  )
);

drop policy if exists spot_images_read on public.tourist_spot_images;
create policy spot_images_read on public.tourist_spot_images
for select to authenticated
using (
  exists (
    select 1
    from public.tourist_spots spot
    where spot.id = spot_id
      and (
        public.is_provincial_admin()
        or public.cities_match(
          spot.city,
          public.current_subtenant_city()
        )
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and spot.status <> 'archived'
        )
      )
  )
);

drop policy if exists packages_read on public.tour_packages;
create policy packages_read on public.tour_packages
for select
using (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
  or (
    public.current_profile_role() is distinct from 'subtenant'
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
        or (
          public.current_profile_role() is distinct from 'subtenant'
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
        or (
          public.current_profile_role() is distinct from 'subtenant'
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
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and package.status = 'published'
          and package.visibility_status = 'visible'
        )
      )
  )
);

drop policy if exists announcements_select on public.city_announcements;
create policy announcements_select on public.city_announcements
for select
using (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
  or (
    public.current_profile_role() is distinct from 'subtenant'
    and status = 'published'
  )
);

-- WITH CHECK must inspect the proposed ownership keys directly. Depending on
-- a helper that re-reads the row by id can evaluate the pre-update row.
drop policy if exists package_bookings_update_staff_or_owner
  on public.package_bookings;
create policy package_bookings_update_staff_or_owner
on public.package_bookings for update to authenticated
using (
  tourist_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_booking(id)
)
with check (
  tourist_id = auth.uid()
  or public.is_provincial_admin()
  or exists (
    select 1
    from public.tour_packages package
    where package.id = package_bookings.package_id
      and public.cities_match(
        package.city,
        public.current_subtenant_city()
      )
  )
);

drop policy if exists payment_records_update on public.payment_records;
create policy payment_records_update
on public.payment_records for update to authenticated
using (
  payee_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_payment_record(id)
)
with check (
  payee_id = auth.uid()
  or public.is_provincial_admin()
  or (
    booking_id is not null
    and public.subtenant_can_access_booking(booking_id)
  )
  or (
    booking_id is null
    and ride_id is not null
    and exists (
      select 1
      from public.rides ride
      where ride.id = payment_records.ride_id
        and public.subtenant_can_access_driver(ride.driver_id)
    )
  )
);

-- The function is exposed only to authenticated users, but an explicit null
-- check also protects internal/database invocation paths.
create or replace function public.ensure_booking_group_conversation(
  p_booking_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_conversation_id uuid;
  v_package_name text;
  v_tourist_name text;
  v_title text;
begin
  if auth.uid() is null then
    raise exception 'UNAUTHENTICATED' using errcode = '42501';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if not public.is_package_booking_participant(p_booking_id) then
    raise exception 'NOT_BOOKING_PARTICIPANT' using errcode = '42501';
  end if;

  select coalesce(nullif(trim(tp.title), ''), 'Tour Package')
  into v_package_name
  from public.tour_packages tp
  where tp.id = v_booking.package_id;
  v_package_name := coalesce(v_package_name, 'Tour Package');

  select coalesce(
    nullif(trim(p.full_name), ''),
    nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Tourist'
  )
  into v_tourist_name
  from public.profiles p
  where p.id = v_booking.tourist_id;
  v_tourist_name := coalesce(v_tourist_name, 'Tourist');
  v_title := v_package_name || ' - ' || v_tourist_name;

  perform set_config('touristrike.system_conversation_write', 'true', true);
  insert into public.conversations (
    tourist_id, driver_id, booking_id, conversation_type, title
  ) values (
    v_booking.tourist_id, null, p_booking_id, 'booking_group', v_title
  )
  on conflict (booking_id)
    where conversation_type = 'booking_group' and booking_id is not null
  do update set tourist_id = excluded.tourist_id, title = excluded.title
  returning id into v_conversation_id;

  insert into public.conversation_members (
    conversation_id, user_id, member_role
  ) values (
    v_conversation_id, v_booking.tourist_id, 'tourist'
  )
  on conflict do nothing;

  insert into public.conversation_members (
    conversation_id, user_id, member_role
  )
  select v_conversation_id, bd.driver_id, 'driver'
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id
    and bd.status in ('accepted', 'completed')
  on conflict do nothing;
  return v_conversation_id;
end;
$$;

revoke all on function public.ensure_booking_group_conversation(uuid)
  from public, anon, authenticated;
grant execute on function public.ensure_booking_group_conversation(uuid)
  to authenticated;

-- Trigger functions do not need direct API execution privileges.
revoke all on function public.guard_subtenant_profile_scope()
  from public, anon, authenticated;
revoke all on function public.guard_subtenant_assignment_scope()
  from public, anon, authenticated;
revoke all on function public.sync_subtenant_assignment_profile()
  from public, anon, authenticated;
revoke all on function public.set_subtenant_local_government_type()
  from public, anon, authenticated;

-- Supporting indexes for RLS EXISTS checks and participant lookups.
create index if not exists tourist_spot_images_spot_idx
  on public.tourist_spot_images(spot_id);
create index if not exists tour_package_day_items_day_idx
  on public.tour_package_day_items(day_id);
create index if not exists booking_itinerary_items_booking_idx
  on public.booking_itinerary_items(booking_id);
create index if not exists payment_disputes_booking_idx
  on public.payment_disputes(booking_id);

commit;
