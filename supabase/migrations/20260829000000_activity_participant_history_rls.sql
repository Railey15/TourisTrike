-- Activity persistence for convoy participants.
--
-- booking_drivers is the authoritative one-row-per-driver assignment table.
-- Keep both active and completed members able to reconstruct Activity history,
-- regardless of which driver is stored in the legacy single-driver columns.

drop policy if exists package_bookings_select on public.package_bookings;
create policy package_bookings_select on public.package_bookings
for select to authenticated using (
  tourist_id = auth.uid()
  or assigned_driver_id = auth.uid()
  or exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = id
      and bd.driver_id = auth.uid()
      and bd.status in ('accepted', 'completed')
  )
  or public.current_profile_role() = 'admin'
  or exists (
    select 1 from public.tour_packages p
    where p.id = package_id
      and p.city = public.current_profile_city()
  )
);

drop policy if exists "Drivers can view relevant activities"
  on public.package_activities;
create policy "Drivers can view relevant activities"
on public.package_activities for select to authenticated using (
  driver_id = auth.uid()
  or (
    driver_id is null
    and status = 'pending'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'driver'
    )
  )
  or exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = package_activities.booking_id
      and bd.driver_id = auth.uid()
      and bd.status in ('accepted', 'completed')
  )
);
