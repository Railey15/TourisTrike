-- Explicit allow-list and narrowly scoped reset helper for DEBUG test trips.
--
-- This table intentionally has no authenticated write policy. Register a
-- disposable booking from a trusted SQL/service-role session before using the
-- Flutter "Reset Test Trip" control:
--
--   insert into public.developer_test_bookings (booking_id, label)
--   values ('00000000-0000-0000-0000-000000000000', 'Convoy QA');
--
-- Never register a real customer booking. Removing or disabling the row makes
-- reset unavailable immediately. The RPC also requires the caller to be the
-- booking tourist or one of its real assigned drivers.

create table if not exists public.developer_test_bookings (
  booking_id uuid primary key
    references public.package_bookings(id) on delete cascade,
  label text not null default '',
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

alter table public.developer_test_bookings enable row level security;
revoke all on table public.developer_test_bookings from public, anon, authenticated;

create or replace function public.debug_reset_test_trip(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_booking public.package_bookings;
  v_activity_id uuid;
  v_driver_count integer;
  v_itinerary_count integer;
begin
  if v_user_id is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'BOOKING_NOT_FOUND';
  end if;

  if not exists (
    select 1 from public.developer_test_bookings dtb
    where dtb.booking_id = p_booking_id and dtb.enabled
  ) then
    raise exception 'TEST_BOOKING_NOT_REGISTERED';
  end if;

  if v_booking.tourist_id <> v_user_id
     and not exists (
       select 1 from public.booking_drivers bd
       where bd.booking_id = p_booking_id
         and bd.driver_id = v_user_id
         and bd.status in ('accepted', 'completed')
     ) then
    raise exception 'NOT_TEST_BOOKING_PARTICIPANT';
  end if;

  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
       in ('cancelled', 'rejected')
     or v_booking.cancelled_at is not null then
    raise exception 'CANCELLED_BOOKING_CANNOT_RESET';
  end if;

  select id into v_activity_id
  from public.package_activities
  where booking_id = p_booking_id
  limit 1;

  if v_activity_id is null then
    raise exception 'ACTIVITY_NOT_FOUND';
  end if;

  -- Preserve the assignment rows and identities; reset each driver's own
  -- lifecycle independently to the known initial convoy state.
  update public.booking_drivers
  set status = 'accepted',
      journey_state = 'assigned',
      current_stop_index = 0,
      state_updated_at = now(),
      completed_at = null
  where booking_id = p_booking_id
    and status in ('accepted', 'completed');

  get diagnostics v_driver_count = row_count;

  if v_driver_count = 0 then
    raise exception 'NO_DRIVER_ASSIGNMENTS';
  end if;

  update public.booking_itinerary_items
  set spot_status = 'pending',
      actual_arrival_time = null,
      actual_departure_time = null
  where booking_id = p_booking_id;

  get diagnostics v_itinerary_count = row_count;

  -- The normal integrity trigger accepts lifecycle changes only from validated
  -- server workflows. This scoped RPC is the sole reset workflow.
  perform set_config('touristrike.validated_transition', 'true', true);

  update public.package_activities
  set status = 'accepted',
      tour_status = 'driver_accepted',
      current_spot_index = 0,
      driver_latitude = null,
      driver_longitude = null,
      driver_last_seen = null,
      picked_up_at = null,
      dropped_off_at = null,
      updated_at = now()
  where id = v_activity_id;

  update public.package_bookings
  set status = 'accepted',
      booking_status = 'accepted',
      accepted_drivers_count = v_driver_count,
      current_spot_index = 0,
      driver_latitude = null,
      driver_longitude = null,
      arrived_at = null,
      picked_up_at = null,
      completed_at = null,
      updated_at = now()
  where id = p_booking_id;

  delete from public.driver_live_locations dll
  using public.booking_drivers bd
  where bd.booking_id = p_booking_id
    and dll.driver_id = bd.driver_id;

  -- Financial and communication data is deliberately untouched. Provider
  -- confirmations remain authoritative and group-chat history remains real.
  return jsonb_build_object(
    'success', true,
    'booking_id', p_booking_id,
    'activity_id', v_activity_id,
    'driver_assignments_reset', v_driver_count,
    'itinerary_items_reset', v_itinerary_count,
    'payments_preserved', true,
    'payment_allocations_preserved', true,
    'group_chat_preserved', true
  );
end;
$$;

revoke all on function public.debug_reset_test_trip(uuid)
  from public, anon;
grant execute on function public.debug_reset_test_trip(uuid)
  to authenticated;
