-- Final Developer Testing cutover.
-- Participants retain one read-only authorization surface. System
-- Administrators are the sole writers and the only actors allowed to reset a
-- reversible test journey.
begin;

-- Retire the legacy allowlists and every client-callable debug mutation. Keep
-- the historical objects in place for migration compatibility, but make them
-- inaccessible to application roles and empty their obsolete authorization
-- data.
delete from public.developer_test_bookings;
delete from public.developer_test_users;
revoke all on table public.developer_test_bookings from public, anon, authenticated;
revoke all on table public.developer_test_users from public, anon, authenticated;

create or replace function public.is_developer_test_booking(p_booking_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select false $$;
revoke all on function public.is_developer_test_booking(uuid)
  from public, anon, authenticated;

do $retire_legacy_debug_rpcs$
declare
  v_function record;
begin
  for v_function in
    select p.oid::regprocedure as signature
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in (
        'debug_reset_test_trip',
        'debug_advance_driver_journey_state',
        'debug_mark_itinerary_stop_arrived',
        'debug_complete_package_tour',
        'debug_force_complete_test_trip',
        'debug_get_test_booking_state',
        'debug_set_test_booking_mode',
        'debug_test_driver_assignment',
        'debug_mark_remaining_balance_paid',
        'debug_get_test_mode_diagnostics'
      )
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      v_function.signature
    );
  end loop;
end;
$retire_legacy_debug_rpcs$;

-- Test bookings now follow the same notification rules as every other booking.
create or replace function public.emit_tour_notification(
  p_user uuid,
  p_booking uuid,
  p_key text,
  p_type text,
  p_title text,
  p_body text,
  p_push boolean default true,
  p_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_created integer;
begin
  if p_user is null then return; end if;
  insert into public.notifications(
    user_id, booking_id, dedupe_key, type, title, body, is_read,
    push_enabled, in_app_enabled, channel, data
  ) values (
    p_user, p_booking, 'tour:' || p_key || ':' || p_user, p_type, p_title,
    p_body, false,
    p_push and public.notification_push_allowed(p_user, p_type), p_push,
    case
      when p_type = 'emergency_alert' then 'emergency_alerts'
      when p_type like '%payment%' or p_type = 'cash_confirmation_required'
        then 'payment_updates'
      else 'tour_updates'
    end,
    p_data
  )
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
  get diagnostics v_created = row_count;
  if v_created > 0 then
    raise log '[NOTIFICATION] Event created: %', p_type;
  end if;
end;
$$;

create or replace function public.normalize_tour_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking uuid;
begin
  if new.type = 'itinerary_arrival'
    or (new.type = 'booking_cancelled' and new.dedupe_key is null)
    or (new.type = 'emergency' and new.dedupe_key is null) then
    return null;
  end if;
  if new.type = 'available_package_job'
     and new.dedupe_key like 'available_job:%' then
    v_booking := split_part(new.dedupe_key, ':', 2)::uuid;
    new.booking_id := v_booking;
    new.title := 'New Tour Request';
    new.body := 'A new tour request is available.';
    new.push_enabled := public.notification_push_allowed(new.user_id, new.type);
    new.in_app_enabled := true;
  end if;
  return new;
end;
$$;

create or replace function public.notify_drivers_of_available_booking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications(
    user_id, title, body, type, is_read, dedupe_key
  )
  select
    p.id, 'New Tour Request', 'A new tour request is available.',
    'available_package_job', false,
    'available_job:' || new.id::text || ':' || p.id::text
  from public.profiles p
  where p.role = 'driver'
    and (coalesce(p.is_online, false) or coalesce(p.is_available, false))
    and lower(trim(coalesce(p.city, ''))) =
        lower(trim(coalesce(new.municipality, '')))
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
  return new;
exception when others then
  raise warning 'Job notification failed [%]', sqlstate;
  return new;
end;
$$;

revoke all on function public.emit_tour_notification(
  uuid, uuid, text, text, text, text, boolean, jsonb
) from public, anon, authenticated;
revoke all on function public.normalize_tour_notification()
  from public, anon, authenticated;
revoke all on function public.notify_drivers_of_available_booking()
  from public, anon, authenticated;

create or replace function public.administrator_reset_developer_test_trip(
  p_booking_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_booking public.package_bookings;
  v_session public.developer_test_sessions;
  v_activity_id uuid;
  v_driver_count integer;
  v_itinerary_count integer;
begin
  if v_actor is null or not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  select session.* into v_session
  from public.developer_test_sessions session
  join public.system_settings settings on settings.singleton
  where session.booking_id = p_booking_id
    and session.status = 'active'
    and session.expires_at > now()
    and settings.developer_testing_enabled
  order by session.activated_at desc
  limit 1
  for update of session;
  if not found then
    raise exception 'ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED';
  end if;

  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
       in ('cancelled', 'rejected', 'completed', 'done', 'expired')
     or v_booking.cancelled_at is not null
     or v_booking.completed_at is not null then
    raise exception 'RESET_BLOCKED_BY_TERMINAL_BOOKING_STATE';
  end if;

  if exists (
    select 1 from public.payout_records payout
    where payout.booking_id = p_booking_id
      and payout.status in ('processing', 'paid')
  ) then
    raise exception 'RESET_BLOCKED_BY_PAYOUT_STATE';
  end if;

  if exists (
    select 1 from public.payment_disputes dispute
    where dispute.booking_id = p_booking_id
  ) then
    raise exception 'RESET_BLOCKED_BY_PAYMENT_DISPUTE';
  end if;

  if exists (
    select 1 from public.refund_requests refund
    where refund.booking_id = p_booking_id
      and refund.status in ('pending', 'approved', 'completed')
  ) then
    raise exception 'RESET_BLOCKED_BY_REFUND_STATE';
  end if;

  if exists (
    select 1 from public.booking_stop_waiting_charges charge
    where charge.booking_id = p_booking_id
      and (charge.status = 'finalized' or charge.additional_amount > 0)
  ) then
    raise exception 'RESET_BLOCKED_BY_FINALIZED_WAITING_CHARGE';
  end if;

  select activity.id into v_activity_id
  from public.package_activities activity
  where activity.booking_id = p_booking_id
  order by activity.updated_at desc nulls last, activity.created_at desc
  limit 1;
  if v_activity_id is null then raise exception 'ACTIVITY_NOT_FOUND'; end if;

  perform set_config('touristrike.validated_transition', 'true', true);
  perform set_config('touristrike.journey_rpc', 'true', true);
  perform set_config('touristrike.tracking_reconcile', 'true', true);
  perform set_config('touristrike.gps_transition_verified', 'true', true);
  perform set_config('touristrike.driver_slide', 'true', true);

  delete from public.driver_journey_evidence evidence
  using public.booking_drivers driver
  where evidence.booking_driver_id = driver.id
    and driver.booking_id = p_booking_id;

  delete from public.booking_driver_arrivals arrival
  using public.booking_drivers driver
  where arrival.booking_driver_id = driver.id
    and driver.booking_id = p_booking_id;

  delete from public.booking_stop_waiting_charges charge
  where charge.booking_id = p_booking_id and charge.status = 'active';

  update public.booking_drivers
  set status = 'accepted',
      journey_state = 'assigned',
      current_stop_index = 0,
      state_updated_at = now(),
      completed_at = null
  where booking_id = p_booking_id
    and status in ('accepted', 'completed');
  get diagnostics v_driver_count = row_count;
  if v_driver_count = 0 then raise exception 'NO_DRIVER_ASSIGNMENTS'; end if;

  update public.booking_itinerary_items
  set spot_status = 'pending',
      actual_arrival_time = null,
      actual_departure_time = null
  where booking_id = p_booking_id;
  get diagnostics v_itinerary_count = row_count;

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
      tracking_interrupted_at = null,
      updated_at = now()
  where id = p_booking_id;

  insert into public.trip_status_logs(
    activity_id, booking_id, status, spot_index, notes
  ) values (
    v_activity_id, p_booking_id, 'developer_test_reset', 0,
    jsonb_build_object(
      'reset_by', v_actor,
      'developer_test_session_id', v_session.id
    )::text
  );

  insert into public.audit_logs(
    actor_id, action, table_name, record_id, description
  ) values (
    v_actor, 'DEVELOPER_TEST_TRIP_RESET', 'package_bookings',
    p_booking_id::text,
    jsonb_build_object(
      'booking_id', p_booking_id,
      'developer_test_session_id', v_session.id,
      'activity_id', v_activity_id,
      'driver_assignments_reset', v_driver_count,
      'itinerary_items_reset', v_itinerary_count,
      'payments_preserved', true,
      'payment_allocations_preserved', true,
      'payouts_preserved', true,
      'disputes_preserved', true,
      'session_preserved', true,
      'global_switch_preserved', true
    )::text
  );

  return jsonb_build_object(
    'success', true,
    'booking_id', p_booking_id,
    'developer_test_session_id', v_session.id,
    'driver_assignments_reset', v_driver_count,
    'itinerary_items_reset', v_itinerary_count,
    'financial_records_preserved', true,
    'test_session_preserved', true
  );
end;
$$;

revoke all on function public.administrator_reset_developer_test_trip(uuid)
  from public, anon, authenticated;
grant execute on function public.administrator_reset_developer_test_trip(uuid)
  to authenticated;

commit;
