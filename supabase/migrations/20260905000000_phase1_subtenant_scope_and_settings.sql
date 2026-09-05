-- Phase 1: make subtenant_details the authoritative municipality assignment,
-- close cross-municipality RLS gaps, and guarantee Settings storage columns.
-- Depends on the current UUID booking/payment schema through
-- 20260902000000_live_transaction_audit.sql.

begin;

-- Fail before changing policies when the target is still on the older bigint
-- booking/ride baseline. Phase 1 depends on the current UUID transaction
-- schema established by the migrations named above.
do $$
declare
  expected record;
  actual_type text;
begin
  for expected in
    select *
    from (values
      ('package_bookings', 'id'),
      ('booking_driver_assignments', 'booking_id'),
      ('booking_itinerary_items', 'booking_id'),
      ('booking_drivers', 'booking_id'),
      ('package_activities', 'booking_id'),
      ('package_reviews', 'booking_id'),
      ('booking_payment_requirements', 'booking_id'),
      ('trip_status_logs', 'booking_id'),
      ('emergency_alerts', 'booking_id'),
      ('conversations', 'booking_id'),
      ('rides', 'id'),
      ('payment_records', 'id'),
      ('payment_records', 'booking_id'),
      ('payment_records', 'ride_id'),
      ('payment_disputes', 'payment_record_id'),
      ('payment_disputes', 'booking_id'),
      ('payment_provider_events', 'payment_record_id'),
      ('payment_allocations', 'booking_id'),
      ('payout_records', 'booking_id'),
      ('refund_requests', 'booking_id')
    ) as required_type(table_name, column_name)
  loop
    select columns.data_type
    into actual_type
    from information_schema.columns columns
    where columns.table_schema = 'public'
      and columns.table_name = expected.table_name
      and columns.column_name = expected.column_name;

    if actual_type is distinct from 'uuid' then
      raise exception
        'PHASE1_SCHEMA_DEPENDENCY: %.% must be uuid (found %)',
        expected.table_name,
        expected.column_name,
        coalesce(actual_type, 'missing');
    end if;
  end loop;

  if to_regprocedure(
    'public.is_package_booking_participant(uuid)'
  ) is null then
    raise exception
      'PHASE1_SCHEMA_DEPENDENCY: is_package_booking_participant(uuid) is missing';
  end if;
  if to_regprocedure(
    'public.compute_convoy_stage_progress(uuid,text,integer)'
  ) is null then
    raise exception
      'PHASE1_SCHEMA_DEPENDENCY: compute_convoy_stage_progress is missing';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Canonical staff scope helpers
-- ---------------------------------------------------------------------------

create or replace function public.cities_match(p_left text, p_right text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select nullif(trim(coalesce(p_left, '')), '') is not null
     and nullif(trim(coalesce(p_right, '')), '') is not null
     and lower(trim(p_left)) = lower(trim(p_right));
$$;

create or replace function public.is_provincial_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  );
$$;

create or replace function public.current_subtenant_city()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select sd.city
  from public.subtenant_details sd
  join public.profiles p on p.id = sd.id
  where sd.id = auth.uid()
    and p.role = 'subtenant'
    and sd.is_active = true
    and nullif(trim(sd.city), '') is not null
  limit 1;
$$;

create or replace function public.subtenant_can_access_driver(p_driver_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_subtenant_city() is not null
     and exists (
       select 1 from public.profiles p
       where p.id = p_driver_id
         and p.role = 'driver'
         and public.cities_match(p.city, public.current_subtenant_city())
     );
$$;

create or replace function public.subtenant_can_access_booking(p_booking_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_subtenant_city() is not null
     and exists (
       select 1
       from public.package_bookings pb
       join public.tour_packages tp on tp.id = pb.package_id
       where pb.id = p_booking_id
         and public.cities_match(tp.city, public.current_subtenant_city())
     );
$$;

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
             select 1 from public.rides r
             where r.id = pr.ride_id
               and public.subtenant_can_access_driver(r.driver_id)
           )
           else false
         end
     );
$$;

create or replace function public.subtenant_city_storage_slug()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(trim(both '-' from regexp_replace(
      lower(public.current_subtenant_city()), '[^a-z0-9]+', '-', 'g'
    )), ''),
    'city'
  );
$$;

revoke all on function public.is_provincial_admin() from public, anon;
revoke all on function public.current_subtenant_city() from public, anon;
revoke all on function public.subtenant_can_access_driver(uuid) from public, anon;
revoke all on function public.subtenant_can_access_booking(uuid) from public, anon;
revoke all on function public.subtenant_can_access_payment_record(uuid) from public, anon;
revoke all on function public.subtenant_city_storage_slug() from public, anon;
grant execute on function public.is_provincial_admin() to authenticated;
grant execute on function public.current_subtenant_city() to authenticated;
grant execute on function public.is_provincial_admin() to anon;
grant execute on function public.current_subtenant_city() to anon;
grant execute on function public.subtenant_can_access_driver(uuid) to authenticated;
grant execute on function public.subtenant_can_access_booking(uuid) to authenticated;
grant execute on function public.subtenant_can_access_payment_record(uuid) to authenticated;
grant execute on function public.subtenant_city_storage_slug() to authenticated;

-- Repair the duplicated profile city once. Future authorization reads the
-- assignment row, not this denormalized display copy.
update public.profiles p
set city = sd.city,
    province = sd.province
from public.subtenant_details sd
where p.id = sd.id
  and p.role = 'subtenant'
  and (p.city is distinct from sd.city or p.province is distinct from sd.province);

create or replace function public.guard_subtenant_profile_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() = old.id
     and old.role = 'subtenant'
     and not public.is_provincial_admin()
     and (
       new.role is distinct from old.role
       or new.city is distinct from old.city
       or new.province is distinct from old.province
     ) then
    raise exception 'SUBTENANT_SCOPE_IS_ADMIN_MANAGED' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_subtenant_profile_scope on public.profiles;
create trigger guard_subtenant_profile_scope
before update on public.profiles
for each row execute function public.guard_subtenant_profile_scope();

create or replace function public.guard_subtenant_assignment_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if auth.uid() = old.id and not public.is_provincial_admin() then
      raise exception 'SUBTENANT_ASSIGNMENT_IS_ADMIN_MANAGED'
        using errcode = '42501';
    end if;
    return old;
  end if;

  if auth.uid() = old.id
     and not public.is_provincial_admin()
     and (
       new.id is distinct from old.id
       or new.city is distinct from old.city
       or new.province is distinct from old.province
       or new.verification_status is distinct from old.verification_status
       or new.is_active is distinct from old.is_active
       or new.approved_by is distinct from old.approved_by
       or new.approved_at is distinct from old.approved_at
       or new.created_at is distinct from old.created_at
     ) then
    raise exception 'SUBTENANT_ASSIGNMENT_IS_ADMIN_MANAGED' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_subtenant_assignment_scope
  on public.subtenant_details;
create trigger guard_subtenant_assignment_scope
before update or delete on public.subtenant_details
for each row execute function public.guard_subtenant_assignment_scope();

create or replace function public.sync_subtenant_assignment_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set city = new.city, province = new.province
  where id = new.id and role = 'subtenant';
  return new;
end;
$$;

drop trigger if exists sync_subtenant_assignment_profile
  on public.subtenant_details;
create trigger sync_subtenant_assignment_profile
after insert or update of city, province on public.subtenant_details
for each row execute function public.sync_subtenant_assignment_profile();

-- ---------------------------------------------------------------------------
-- Settings schema and ownership
-- ---------------------------------------------------------------------------

alter table public.admin_settings
  add column if not exists default_package_visibility text not null default 'visible',
  add column if not exists default_spot_status text not null default 'active',
  add column if not exists allow_cancellation boolean not null default true,
  add column if not exists driver_auto_approval boolean not null default false,
  add column if not exists require_driver_documents boolean not null default true,
  add column if not exists require_toda_verification boolean not null default true,
  add column if not exists require_spot_verification boolean not null default true,
  add column if not exists require_map_pin boolean not null default true,
  add column if not exists require_cover_image boolean not null default true,
  add column if not exists enable_ai_suggestions boolean not null default true,
  add column if not exists diverse_place_types boolean not null default true,
  add column if not exists prioritize_popular boolean not null default true,
  add column if not exists prioritize_nearby boolean not null default true,
  add column if not exists prioritize_food boolean not null default true,
  add column if not exists prioritize_nature boolean not null default true,
  add column if not exists prioritize_historical boolean not null default true,
  add column if not exists booking_notifications boolean not null default true,
  add column if not exists driver_notifications boolean not null default true,
  add column if not exists review_notifications boolean not null default true,
  add column if not exists email_notifications boolean not null default true,
  add column if not exists revenue_tracking boolean not null default true,
  add column if not exists spot_popularity_tracking boolean not null default true,
  add column if not exists driver_analytics boolean not null default true,
  add column if not exists monthly_reports boolean not null default true;

drop policy if exists own_settings on public.admin_settings;
create policy own_settings on public.admin_settings
for all to authenticated
using (user_id = auth.uid() or public.is_provincial_admin())
with check (user_id = auth.uid() or public.is_provincial_admin());

drop policy if exists subtenant_fare_settings_owner_city
  on public.subtenant_fare_settings;
create policy subtenant_fare_settings_owner_city
on public.subtenant_fare_settings for all to authenticated
using (
  public.is_provincial_admin()
  or (
    subtenant_id = auth.uid()
    and public.cities_match(city, public.current_subtenant_city())
  )
)
with check (
  public.is_provincial_admin()
  or (
    subtenant_id = auth.uid()
    and public.cities_match(city, public.current_subtenant_city())
  )
);

-- ---------------------------------------------------------------------------
-- Tenant identity, content, package, booking, and driver policies
-- ---------------------------------------------------------------------------

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
using (
  id = auth.uid()
  or public.is_provincial_admin()
  or (
    public.current_subtenant_city() is not null
    and public.cities_match(city, public.current_subtenant_city())
  )
);

drop policy if exists profiles_update_self on public.profiles;
drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
using (id = auth.uid())
with check (
  id = auth.uid()
  and role = public.current_profile_role()
  and (
    role <> 'subtenant'
    or public.cities_match(city, public.current_subtenant_city())
  )
);
create policy profiles_update_admin on public.profiles for update to authenticated
using (public.is_provincial_admin())
with check (public.is_provincial_admin());

drop policy if exists subtenant_details_select on public.subtenant_details;
create policy subtenant_details_select on public.subtenant_details
for select to authenticated
using (
  id = auth.uid()
  or public.is_provincial_admin()
  or (
    public.current_subtenant_city() is not null
    and public.cities_match(city, public.current_subtenant_city())
  )
  or (
    public.current_subtenant_city() is null
    and is_active = true
  )
);

drop policy if exists subtenant_details_write on public.subtenant_details;
create policy subtenant_details_write on public.subtenant_details
for all to authenticated
using (
  public.is_provincial_admin()
  or (
    id = auth.uid()
    and public.cities_match(city, public.current_subtenant_city())
  )
)
with check (
  public.is_provincial_admin()
  or (
    id = auth.uid()
    and public.cities_match(city, public.current_subtenant_city())
  )
);

drop policy if exists spots_write_admin_subtenant on public.tourist_spots;
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

create policy spots_write_admin_subtenant on public.tourist_spots
for all to authenticated
using (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
)
with check (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
);

drop policy if exists spot_images_read on public.tourist_spot_images;
create policy spot_images_read on public.tourist_spot_images
for select to authenticated
using (
  exists (
    select 1 from public.tourist_spots s
    where s.id = spot_id
      and (
        public.is_provincial_admin()
        or public.cities_match(s.city, public.current_subtenant_city())
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and s.status <> 'archived'
        )
      )
  )
);

drop policy if exists spot_images_write_admin_subtenant
  on public.tourist_spot_images;
create policy spot_images_write_admin_subtenant on public.tourist_spot_images
for all to authenticated
using (
  public.is_provincial_admin()
  or exists (
    select 1 from public.tourist_spots s
    where s.id = spot_id
      and public.cities_match(s.city, public.current_subtenant_city())
  )
)
with check (
  public.is_provincial_admin()
  or exists (
    select 1 from public.tourist_spots s
    where s.id = spot_id
      and public.cities_match(s.city, public.current_subtenant_city())
  )
);

drop policy if exists spot_views_select_admin_subtenant
  on public.tourist_spot_views;
create policy spot_views_select_admin_subtenant on public.tourist_spot_views
for select to authenticated
using (
  public.is_provincial_admin()
  or exists (
    select 1 from public.tourist_spots s
    where s.id = spot_id
      and public.cities_match(s.city, public.current_subtenant_city())
  )
);

drop policy if exists packages_write_admin_subtenant on public.tour_packages;
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

create policy packages_write_admin_subtenant on public.tour_packages
for all to authenticated
using (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
)
with check (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
);

drop policy if exists package_children_read on public.tour_package_days;
create policy package_children_read on public.tour_package_days
for select to authenticated
using (
  exists (
    select 1 from public.tour_packages p
    where p.id = package_id
      and (
        public.is_provincial_admin()
        or public.cities_match(p.city, public.current_subtenant_city())
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and p.status = 'published'
          and p.visibility_status = 'visible'
        )
      )
  )
);

drop policy if exists package_days_write_admin_subtenant
  on public.tour_package_days;
create policy package_days_write_admin_subtenant on public.tour_package_days
for all to authenticated
using (
  public.is_provincial_admin()
  or exists (
    select 1 from public.tour_packages p
    where p.id = package_id
      and public.cities_match(p.city, public.current_subtenant_city())
  )
)
with check (
  public.is_provincial_admin()
  or exists (
    select 1 from public.tour_packages p
    where p.id = package_id
      and public.cities_match(p.city, public.current_subtenant_city())
  )
);

drop policy if exists package_day_items_read on public.tour_package_day_items;
create policy package_day_items_read on public.tour_package_day_items
for select to authenticated
using (
  exists (
    select 1
    from public.tour_package_days d
    join public.tour_packages p on p.id = d.package_id
    where d.id = day_id
      and (
        public.is_provincial_admin()
        or public.cities_match(p.city, public.current_subtenant_city())
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and p.status = 'published'
          and p.visibility_status = 'visible'
        )
      )
  )
);

drop policy if exists package_day_items_write_admin_subtenant
  on public.tour_package_day_items;
create policy package_day_items_write_admin_subtenant
on public.tour_package_day_items for all to authenticated
using (
  public.is_provincial_admin()
  or exists (
    select 1
    from public.tour_package_days d
    join public.tour_packages p on p.id = d.package_id
    where d.id = day_id
      and public.cities_match(p.city, public.current_subtenant_city())
  )
)
with check (
  public.is_provincial_admin()
  or exists (
    select 1
    from public.tour_package_days d
    join public.tour_packages p on p.id = d.package_id
    where d.id = day_id
      and public.cities_match(p.city, public.current_subtenant_city())
  )
);

drop policy if exists package_spots_read on public.tour_package_spots;
create policy package_spots_read on public.tour_package_spots
for select to authenticated
using (
  exists (
    select 1 from public.tour_packages p
    where p.id = package_id
      and (
        public.is_provincial_admin()
        or public.cities_match(p.city, public.current_subtenant_city())
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and p.status = 'published'
          and p.visibility_status = 'visible'
        )
      )
  )
);

drop policy if exists package_spots_write_admin_subtenant
  on public.tour_package_spots;
create policy package_spots_write_admin_subtenant on public.tour_package_spots
for all to authenticated
using (
  public.is_provincial_admin()
  or exists (
    select 1 from public.tour_packages p
    where p.id = package_id
      and public.cities_match(p.city, public.current_subtenant_city())
  )
)
with check (
  public.is_provincial_admin()
  or exists (
    select 1 from public.tour_packages p
    where p.id = package_id
      and public.cities_match(p.city, public.current_subtenant_city())
  )
);

drop policy if exists package_views_select_admin_subtenant
  on public.tour_package_views;
create policy package_views_select_admin_subtenant on public.tour_package_views
for select to authenticated
using (
  public.is_provincial_admin()
  or exists (
    select 1 from public.tour_packages p
    where p.id = package_id
      and public.cities_match(p.city, public.current_subtenant_city())
  )
);

drop policy if exists package_bookings_select on public.package_bookings;
create policy package_bookings_select on public.package_bookings
for select to authenticated
using (public.is_package_booking_participant(id));

drop policy if exists booking_itinerary_items_select
  on public.booking_itinerary_items;
create policy booking_itinerary_items_select on public.booking_itinerary_items
for select to authenticated
using (
  tourist_id = auth.uid()
  or exists (
    select 1 from public.package_bookings b
    where b.id = booking_id and b.assigned_driver_id = auth.uid()
  )
  or exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = booking_id
      and bd.driver_id = auth.uid()
      and bd.status in ('accepted', 'completed')
  )
  or public.is_provincial_admin()
  or public.subtenant_can_access_booking(booking_id)
);

drop policy if exists customized_package_spots_select
  on public.customized_package_spots;
create policy customized_package_spots_select
on public.customized_package_spots for select to authenticated
using (
  tourist_id = auth.uid()
  or public.is_provincial_admin()
  or exists (
    select 1 from public.tour_packages p
    where p.id = package_id
      and public.cities_match(p.city, public.current_subtenant_city())
  )
);

drop policy if exists customized_package_spots_insert
  on public.customized_package_spots;
create policy customized_package_spots_insert
on public.customized_package_spots for insert to authenticated
with check (
  tourist_id = auth.uid()
  or public.is_provincial_admin()
  or exists (
    select 1 from public.tour_packages p
    where p.id = package_id
      and public.cities_match(p.city, public.current_subtenant_city())
  )
);

drop policy if exists customized_package_spots_update
  on public.customized_package_spots;
create policy customized_package_spots_update
on public.customized_package_spots for update to authenticated
using (
  tourist_id = auth.uid()
  or public.is_provincial_admin()
  or exists (
    select 1 from public.tour_packages p
    where p.id = package_id
      and public.cities_match(p.city, public.current_subtenant_city())
  )
)
with check (
  tourist_id = auth.uid()
  or public.is_provincial_admin()
  or exists (
    select 1 from public.tour_packages p
    where p.id = package_id
      and public.cities_match(p.city, public.current_subtenant_city())
  )
);

drop policy if exists package_bookings_update_staff_or_owner
  on public.package_bookings;
create policy package_bookings_update_staff_or_owner on public.package_bookings
for update to authenticated
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

drop policy if exists assignments_select on public.booking_driver_assignments;
create policy assignments_select on public.booking_driver_assignments
for select to authenticated
using (
  driver_id = auth.uid()
  or assigned_by = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_booking(booking_id)
);

drop policy if exists assignments_write_staff
  on public.booking_driver_assignments;
create policy assignments_write_staff on public.booking_driver_assignments
for all to authenticated
using (
  public.is_provincial_admin()
  or public.subtenant_can_access_booking(booking_id)
)
with check (
  public.is_provincial_admin()
  or public.subtenant_can_access_booking(booking_id)
);

drop policy if exists "booking_drivers_read_all" on public.booking_drivers;
drop policy if exists booking_drivers_read_participants
  on public.booking_drivers;
create policy booking_drivers_read_participants on public.booking_drivers
for select to authenticated
using (public.is_package_booking_participant(booking_id));

drop policy if exists driver_profiles_select_staff_or_owner
  on public.driver_details;
create policy driver_profiles_select_staff_or_owner on public.driver_details
for select to authenticated
using (
  driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
);

drop policy if exists driver_details_write on public.driver_details;
create policy driver_details_write on public.driver_details
for all to authenticated
using (
  driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
)
with check (
  driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
);

drop policy if exists driver_documents_select_staff_or_owner
  on public.driver_documents;
create policy driver_documents_select_staff_or_owner on public.driver_documents
for select to authenticated
using (
  driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
);

drop policy if exists driver_documents_write_owner on public.driver_documents;
create policy driver_documents_write_owner on public.driver_documents
for all to authenticated
using (
  driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
)
with check (
  driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
);

drop policy if exists driver_applications_select on public.driver_applications;
create policy driver_applications_select on public.driver_applications
for select to authenticated
using (
  driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
);

drop policy if exists driver_applications_write on public.driver_applications;
create policy driver_applications_write on public.driver_applications
for all to authenticated
using (
  driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
)
with check (
  driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
);

drop policy if exists rides_select_participants_staff on public.rides;
create policy rides_select_participants_staff on public.rides
for select to authenticated
using (
  tourist_id = auth.uid()
  or driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
);

drop policy if exists "Admins can manage all activities"
  on public.package_activities;
drop policy if exists "Admins and local subtenants manage activities"
  on public.package_activities;
create policy "Admins and local subtenants manage activities"
on public.package_activities for all to authenticated
using (
  public.is_provincial_admin()
  or public.subtenant_can_access_booking(booking_id)
)
with check (
  public.is_provincial_admin()
  or public.subtenant_can_access_booking(booking_id)
);

-- ---------------------------------------------------------------------------
-- Reviews, announcements, alerts, audit, and trip-detail policies
-- ---------------------------------------------------------------------------

create or replace function public.subtenant_can_view_review_tourist(
  p_tourist_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.driver_reviews dr
    where dr.tourist_id = p_tourist_id
      and public.subtenant_can_access_driver(dr.driver_id)
  );
$$;

revoke all on function public.subtenant_can_view_review_tourist(uuid)
  from public, anon;
grant execute on function public.subtenant_can_view_review_tourist(uuid)
  to authenticated;

drop policy if exists driver_reviews_select on public.driver_reviews;
create policy driver_reviews_select on public.driver_reviews
for select to authenticated
using (
  tourist_id = auth.uid()
  or driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
);

drop policy if exists ride_reviews_select_staff_or_participants
  on public.ride_reviews;
create policy ride_reviews_select_staff_or_participants on public.ride_reviews
for select to authenticated
using (
  tourist_id = auth.uid()
  or driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
);

drop policy if exists ride_feedback_select_staff_or_participants
  on public.ride_feedback;
create policy ride_feedback_select_staff_or_participants on public.ride_feedback
for select to authenticated
using (
  tourist_id = auth.uid()
  or driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
);

drop policy if exists package_reviews_select_local_staff
  on public.package_reviews;
create policy package_reviews_select_local_staff on public.package_reviews
for select to authenticated
using (
  public.is_provincial_admin()
  or public.subtenant_can_access_booking(booking_id)
);

drop policy if exists announcements_write_subtenant_admin
  on public.city_announcements;
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

create policy announcements_write_subtenant_admin on public.city_announcements
for all to authenticated
using (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
)
with check (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
);

drop policy if exists notifications_insert_staff on public.notifications;
create policy notifications_insert_staff on public.notifications
for insert to authenticated
with check (
  public.is_provincial_admin()
  or (
    public.current_subtenant_city() is not null
    and exists (
      select 1 from public.profiles recipient
      where recipient.id = user_id
        and public.cities_match(
          recipient.city,
          public.current_subtenant_city()
        )
    )
  )
);

drop policy if exists audit_select_admin_subtenant on public.audit_logs;
create policy audit_select_admin_subtenant on public.audit_logs
for select to authenticated
using (public.is_provincial_admin() or actor_id = auth.uid());

drop policy if exists audit_insert_authenticated on public.audit_logs;
create policy audit_insert_authenticated on public.audit_logs
for insert to authenticated
with check (actor_id = auth.uid() or public.is_provincial_admin());

drop policy if exists booking_payment_requirements_select_participants
  on public.booking_payment_requirements;
create policy booking_payment_requirements_select_participants
on public.booking_payment_requirements for select to authenticated
using (
  exists (
    select 1 from public.package_bookings pb
    where pb.id = booking_id
      and (
        pb.tourist_id = auth.uid()
        or exists (
          select 1 from public.booking_drivers bd
          where bd.booking_id = pb.id
            and bd.driver_id = auth.uid()
            and bd.status in ('accepted', 'completed')
        )
        or public.is_provincial_admin()
        or public.subtenant_can_access_booking(pb.id)
      )
  )
);

drop policy if exists trip_logs_select_participants on public.trip_status_logs;
create policy trip_logs_select_participants on public.trip_status_logs
for select to authenticated
using (
  exists (
    select 1 from public.package_bookings pb
    where pb.id = booking_id
      and (
        pb.tourist_id = auth.uid()
        or exists (
          select 1 from public.booking_drivers bd
          where bd.booking_id = pb.id and bd.driver_id = auth.uid()
        )
        or public.is_provincial_admin()
        or public.subtenant_can_access_booking(pb.id)
      )
  )
);

drop policy if exists live_loc_select_active_trip
  on public.driver_live_locations;
create policy live_loc_select_active_trip on public.driver_live_locations
for select to authenticated
using (
  auth.uid() = driver_id
  or public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
  or exists (
    select 1
    from public.package_activities pa
    join public.package_bookings pb on pb.id = pa.booking_id
    where pa.id = activity_id
      and lower(coalesce(pb.booking_status, pb.status, ''))
            not in ('cancelled', 'completed', 'rejected', 'done')
      and exists (
        select 1 from public.booking_drivers target_driver
        where target_driver.booking_id = pb.id
          and target_driver.driver_id = driver_live_locations.driver_id
          and target_driver.status = 'accepted'
      )
      and (
        pb.tourist_id = auth.uid()
        or exists (
          select 1 from public.booking_drivers requesting_driver
          where requesting_driver.booking_id = pb.id
            and requesting_driver.driver_id = auth.uid()
            and requesting_driver.status = 'accepted'
        )
      )
  )
);

drop policy if exists booking_driver_arrivals_participant_read
  on public.booking_driver_arrivals;
create policy booking_driver_arrivals_participant_read
on public.booking_driver_arrivals for select to authenticated
using (
  exists (
    select 1
    from public.booking_drivers bd
    join public.package_bookings pb on pb.id = bd.booking_id
    where bd.id = booking_driver_id
      and (
        bd.driver_id = auth.uid()
        or pb.tourist_id = auth.uid()
        or public.is_provincial_admin()
        or public.subtenant_can_access_booking(pb.id)
      )
  )
);

drop policy if exists "admin_full_emergency_access"
  on public.emergency_alerts;
drop policy if exists "admin_or_local_subtenant_emergency_access"
  on public.emergency_alerts;
create policy "admin_or_local_subtenant_emergency_access"
on public.emergency_alerts for all to authenticated
using (
  public.is_provincial_admin()
  or (
    booking_id is not null
    and public.subtenant_can_access_booking(booking_id)
  )
  or (
    booking_id is null
    and public.subtenant_can_access_driver(driver_id)
  )
)
with check (
  public.is_provincial_admin()
  or (
    booking_id is not null
    and public.subtenant_can_access_booking(booking_id)
  )
  or (
    booking_id is null
    and public.subtenant_can_access_driver(driver_id)
  )
);

drop policy if exists cancellation_policy_staff_update
  on public.package_cancellation_policy;
drop policy if exists cancellation_policy_admin_update
  on public.package_cancellation_policy;
create policy cancellation_policy_admin_update
on public.package_cancellation_policy for update to authenticated
using (public.is_provincial_admin())
with check (public.is_provincial_admin());

-- ---------------------------------------------------------------------------
-- Current and archived payment data
-- ---------------------------------------------------------------------------

drop policy if exists payment_records_select on public.payment_records;
create policy payment_records_select on public.payment_records
for select to authenticated
using (
  payer_id = auth.uid()
  or payee_id = auth.uid()
  or exists (
    select 1 from public.payment_allocations pa
    where pa.payment_record_id = payment_records.id
      and pa.driver_id = auth.uid()
  )
  or public.is_provincial_admin()
  or public.subtenant_can_access_payment_record(id)
);

drop policy if exists payment_records_update on public.payment_records;
create policy payment_records_update on public.payment_records
for update to authenticated
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

drop policy if exists payment_disputes_select on public.payment_disputes;
create policy payment_disputes_select on public.payment_disputes
for select to authenticated
using (
  raised_by = auth.uid()
  or exists (
    select 1 from public.payment_records pr
    where pr.id = payment_record_id
      and (pr.payer_id = auth.uid() or pr.payee_id = auth.uid())
  )
  or public.is_provincial_admin()
  or public.subtenant_can_access_payment_record(payment_record_id)
);

drop policy if exists payment_provider_events_staff_read
  on public.payment_provider_events;
create policy payment_provider_events_staff_read
on public.payment_provider_events for select to authenticated
using (
  public.is_provincial_admin()
  or (
    payment_record_id is not null
    and public.subtenant_can_access_payment_record(payment_record_id)
  )
);

drop policy if exists driver_payout_accounts_owner_or_staff_read
  on public.driver_payout_accounts;
create policy driver_payout_accounts_owner_or_staff_read
on public.driver_payout_accounts for select to authenticated
using (
  driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
);

drop policy if exists payment_allocations_participant_read
  on public.payment_allocations;
create policy payment_allocations_participant_read
on public.payment_allocations for select to authenticated
using (
  driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_booking(booking_id)
);

drop policy if exists payout_records_select on public.payout_records;
create policy payout_records_select on public.payout_records
for select to authenticated
using (
  driver_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_booking(booking_id)
);

create or replace view public.payment_allocation_summaries
with (security_barrier = true, security_invoker = true)
as
select pa.id, pa.payment_record_id, pa.booking_id, pa.driver_id,
       pa.gross_amount, pa.platform_fee, pa.driver_amount,
       pa.split_basis_points, pa.currency,
       pa.status, pa.provider_transfer_status, pa.created_at, pa.updated_at
from public.payment_allocations pa
where pa.driver_id = auth.uid()
   or exists (
     select 1 from public.package_bookings pb
     where pb.id = pa.booking_id and pb.tourist_id = auth.uid()
   )
   or public.is_provincial_admin()
   or public.subtenant_can_access_booking(pa.booking_id);

do $$
begin
  if to_regclass('public._deprecated_payments') is not null then
    execute 'alter table public._deprecated_payments enable row level security';
    execute 'drop policy if exists payments_select on public._deprecated_payments';
    execute 'drop policy if exists payments_insert_owner on public._deprecated_payments';
    execute 'drop policy if exists "Tourists can insert own payments" on public._deprecated_payments';
    execute 'drop policy if exists "Tourists can view own payments" on public._deprecated_payments';
    execute 'drop policy if exists "Admins and subtenants can view all payments" on public._deprecated_payments';
    execute 'drop policy if exists "Admins can update payments" on public._deprecated_payments';
    execute 'drop policy if exists deprecated_payments_read on public._deprecated_payments';
    execute $policy$
      create policy deprecated_payments_read on public._deprecated_payments
      for select to authenticated
      using (
        user_id = auth.uid()
        or public.is_provincial_admin()
        or (
          booking_id is not null
          and public.subtenant_can_access_booking(booking_id)
        )
      )
    $policy$;
    execute 'revoke all on public._deprecated_payments from anon';
    execute 'revoke all on public._deprecated_payments from authenticated';
    execute 'grant select on public._deprecated_payments to authenticated';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Storage scope
-- ---------------------------------------------------------------------------

drop policy if exists payment_proofs_select on storage.objects;
create policy payment_proofs_select on storage.objects
for select to authenticated
using (
  bucket_id = 'payment-proofs'
  and (
    public.is_provincial_admin()
    or exists (
      select 1 from public.payment_records pr
      where pr.id::text = (storage.foldername(name))[1]
        and (
          pr.payer_id = auth.uid()
          or pr.payee_id = auth.uid()
          or public.subtenant_can_access_payment_record(pr.id)
        )
    )
  )
);

drop policy if exists public_assets_subtenant_insert on storage.objects;
create policy public_assets_subtenant_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'public-assets'
  and (
    public.is_provincial_admin()
    or (
      public.current_subtenant_city() is not null
      and (storage.foldername(name))[1] in ('tour-packages', 'tourist-spots')
      and (storage.foldername(name))[2] = public.subtenant_city_storage_slug()
    )
  )
);

drop policy if exists public_assets_subtenant_update on storage.objects;
create policy public_assets_subtenant_update on storage.objects
for update to authenticated
using (
  bucket_id = 'public-assets'
  and (
    public.is_provincial_admin()
    or (
      public.current_subtenant_city() is not null
      and (storage.foldername(name))[1] in ('tour-packages', 'tourist-spots')
      and (storage.foldername(name))[2] = public.subtenant_city_storage_slug()
    )
  )
)
with check (
  bucket_id = 'public-assets'
  and (
    public.is_provincial_admin()
    or (
      public.current_subtenant_city() is not null
      and (storage.foldername(name))[1] in ('tour-packages', 'tourist-spots')
      and (storage.foldername(name))[2] = public.subtenant_city_storage_slug()
    )
  )
);

-- ---------------------------------------------------------------------------
-- SECURITY DEFINER entry points must enforce the same municipality boundary.
-- ---------------------------------------------------------------------------

create or replace function public.is_package_booking_participant(
  p_booking_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and (
    exists (
      select 1 from public.package_bookings pb
      where pb.id = p_booking_id and pb.tourist_id = auth.uid()
    )
    or exists (
      select 1 from public.booking_drivers bd
      where bd.booking_id = p_booking_id
        and bd.driver_id = auth.uid()
        and bd.status in ('accepted', 'completed')
    )
    or public.is_provincial_admin()
    or public.subtenant_can_access_booking(p_booking_id)
  );
$$;

create or replace function public.confirm_payment_record(
  p_payment_record_id uuid
)
returns public.payment_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record public.payment_records;
begin
  select * into v_record
  from public.payment_records
  where id = p_payment_record_id
  for update;
  if not found then raise exception 'PAYMENT_RECORD_NOT_FOUND'; end if;
  if v_record.provider = 'paymongo' then
    raise exception 'PROVIDER_WEBHOOK_REQUIRED';
  end if;
  if auth.uid() is null or not (
    auth.uid() = v_record.payee_id
    or public.is_provincial_admin()
    or public.subtenant_can_access_payment_record(v_record.id)
  ) then
    raise exception 'NOT_PAYMENT_PAYEE';
  end if;
  if v_record.status = 'confirmed' then return v_record; end if;
  if v_record.status <> 'pending_confirmation' then
    raise exception 'PAYMENT_NOT_CONFIRMABLE';
  end if;

  update public.payment_records
  set status = 'confirmed'
  where id = p_payment_record_id
  returning * into v_record;

  if v_record.booking_id is not null then
    update public.booking_payment_requirements
    set status = 'satisfied',
        satisfied_at = coalesce(satisfied_at, now()),
        satisfied_by_payment_record_id = coalesce(
          satisfied_by_payment_record_id,
          v_record.id
        )
    where booking_id = v_record.booking_id
      and payment_stage = v_record.payment_stage
      and amount <= v_record.amount
      and status = 'required';
  end if;
  return v_record;
end;
$$;

create or replace function public.resolve_payment_dispute(
  p_dispute_id uuid,
  p_new_status text,
  p_resolution_note text default null
)
returns public.payment_disputes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dispute public.payment_disputes;
begin
  select * into v_dispute
  from public.payment_disputes
  where id = p_dispute_id
  for update;
  if not found then raise exception 'DISPUTE_NOT_FOUND'; end if;

  if auth.uid() is null or not (
    public.is_provincial_admin()
    or public.subtenant_can_access_payment_record(v_dispute.payment_record_id)
  ) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_new_status not in (
    'under_review', 'resolved_valid', 'resolved_refund_arranged', 'rejected'
  ) then
    raise exception 'INVALID_STATUS';
  end if;

  update public.payment_disputes
  set status = p_new_status,
      resolution_note = coalesce(p_resolution_note, resolution_note),
      resolved_by = auth.uid(),
      resolved_at = case
        when p_new_status in (
          'resolved_valid', 'resolved_refund_arranged', 'rejected'
        ) then now()
        else resolved_at
      end
  where id = p_dispute_id
  returning * into v_dispute;

  update public.payment_records
  set status = case
    when p_new_status = 'resolved_valid' then 'confirmed'
    when p_new_status = 'resolved_refund_arranged' then 'cancelled'
    when p_new_status = 'rejected' then 'confirmed'
    else 'disputed'
  end
  where id = v_dispute.payment_record_id;

  insert into public.audit_logs (
    actor_id, action, table_name, record_id, description
  ) values (
    auth.uid(),
    'resolve_payment_dispute',
    'payment_disputes',
    v_dispute.id::text,
    'Dispute resolved: ' || p_new_status
      || coalesce(' | note=' || p_resolution_note, '')
  );
  return v_dispute;
end;
$$;

create or replace function public.get_payment_reconciliation(
  p_booking_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not (
    public.is_provincial_admin()
    or public.subtenant_can_access_booking(p_booking_id)
  ) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if not exists (
    select 1 from public.package_bookings pb where pb.id = p_booking_id
  ) then
    raise exception 'BOOKING_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'booking', (select to_jsonb(pb) from public.package_bookings pb
      where pb.id = p_booking_id),
    'payments', coalesce((select jsonb_agg(to_jsonb(pr) order by pr.created_at)
      from public.payment_records pr where pr.booking_id = p_booking_id), '[]'::jsonb),
    'allocations', coalesce((select jsonb_agg(to_jsonb(pa) order by pa.created_at)
      from public.payment_allocations pa where pa.booking_id = p_booking_id), '[]'::jsonb),
    'payouts', coalesce((select jsonb_agg(to_jsonb(po) order by po.created_at)
      from public.payout_records po where po.booking_id = p_booking_id), '[]'::jsonb),
    'disputes', coalesce((select jsonb_agg(to_jsonb(pd) order by pd.created_at)
      from public.payment_disputes pd where pd.booking_id = p_booking_id), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(to_jsonb(rr) order by rr.created_at)
      from public.refund_requests rr where rr.booking_id = p_booking_id), '[]'::jsonb)
  );
end;
$$;

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

create or replace function public.get_convoy_stage_progress(
  p_booking_id uuid,
  p_stage text,
  p_stop_index integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if not public.is_package_booking_participant(p_booking_id) then
    raise exception 'NOT_BOOKING_PARTICIPANT';
  end if;
  return public.compute_convoy_stage_progress(
    p_booking_id,
    p_stage,
    p_stop_index
  );
end;
$$;

revoke all on function public.confirm_payment_record(uuid)
  from public, anon;
revoke all on function public.resolve_payment_dispute(uuid, text, text)
  from public, anon;
revoke all on function public.get_payment_reconciliation(uuid)
  from public, anon;
revoke all on function public.is_package_booking_participant(uuid)
  from public, anon;
revoke all on function public.ensure_booking_group_conversation(uuid)
  from public, anon;
revoke all on function public.get_convoy_stage_progress(uuid, text, integer)
  from public, anon;
grant execute on function public.confirm_payment_record(uuid) to authenticated;
grant execute on function public.resolve_payment_dispute(uuid, text, text)
  to authenticated;
grant execute on function public.get_payment_reconciliation(uuid)
  to authenticated;
grant execute on function public.is_package_booking_participant(uuid)
  to authenticated;
grant execute on function public.ensure_booking_group_conversation(uuid)
  to authenticated;
grant execute on function public.get_convoy_stage_progress(uuid, text, integer)
  to authenticated;

commit;
