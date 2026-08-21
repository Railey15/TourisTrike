-- ============================================================
-- Convoy Sync — Phase 1: stop the "Null check operator used on a null
-- value" crash on DriverPackageTrackingScreen for group bookings.
--
-- Root cause (see chat report): "Drivers can view relevant activities"
-- only grants SELECT on package_activities via driver_id = auth.uid()
-- OR (driver_id IS NULL AND status = 'pending'). The instant the LAST
-- driver in a group booking accepts, driver_id gets set to THAT driver
-- and status flips to 'accepted' — every driver who accepted earlier
-- fails both branches and loses read access to a row they already have
-- a legitimate interest in. Their next realtime-triggered refetch
-- (lib/screens/driver/driver_package_tracking_screen.dart:351-375)
-- returns null with no accompanying error state, and the next rebuild
-- crashes at the `_activity!` null-check on line 1135.
--
-- Fix: widen the SELECT policy with an additional OR branch keyed off
-- booking_drivers (the actual one-row-per-driver table) so any driver
-- who has an accepted row for this booking keeps read access to the
-- booking's package_activities row, regardless of who driver_id points
-- to. Purely additive — the two existing branches are untouched, so
-- solo bookings (required_drivers = 1, no booking_drivers dependency
-- for them yet) see no behavior change.
-- ============================================================

drop policy if exists "Drivers can view relevant activities" on public.package_activities;
create policy "Drivers can view relevant activities"
  on public.package_activities for select to authenticated
  using (
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
        and bd.status = 'accepted'
    )
  );

-- Note: the parallel "Drivers can update relevant activities" policy
-- (same file, tour_tracking.sql:66-80) has the identical structural gap,
-- but nothing currently attempts that write path for non-final drivers
-- (accept_package_booking only writes package_activities in the
-- all-slots-filled branch), so it's left untouched here — one concern
-- per migration. Phase 2 will revisit if a per-driver write path to
-- package_activities turns out to be needed.
