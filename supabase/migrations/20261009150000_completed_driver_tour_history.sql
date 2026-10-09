-- Completed drivers remain booking participants for historical reads, while
-- live tracking itself stays restricted to accepted/active assignments.
begin;

create or replace function public.get_live_tour_tracking_eligibility(
  p_booking_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_booking public.package_bookings;
  v_participant boolean;
  v_can_access boolean;
  v_test_bypass boolean := false;
  v_reason text;
begin
  if v_actor is null then raise exception 'UNAUTHENTICATED'; end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  v_participant := v_booking.tourist_id = v_actor or exists (
    select 1
    from public.booking_drivers bd
    where bd.booking_id = p_booking_id
      and bd.driver_id = v_actor
      and bd.status in ('accepted', 'completed')
  );
  if not v_participant then raise exception 'NOT_BOOKING_PARTICIPANT'; end if;

  v_test_bypass := now() < v_booking.scheduled_start_at
    and public.developer_test_schedule_bypass_authorized(p_booking_id, v_actor);
  v_can_access := public.can_access_live_tour_tracking(p_booking_id, v_actor);
  v_reason := case
    when lower(coalesce(v_booking.booking_status, v_booking.status, '')) in (
      'cancelled', 'completed', 'done', 'rejected', 'expired', 'failed',
      'closed', 'refunded', 'tourist_no_show'
    ) then 'BOOKING_NOT_TRACKABLE'
    when v_booking.scheduled_start_at is null then 'SCHEDULE_UNAVAILABLE'
    when v_test_bypass and v_can_access then 'TEST_MODE_SCHEDULE_BYPASS'
    when now() < v_booking.scheduled_start_at then 'BEFORE_SCHEDULED_START'
    when v_can_access then 'ELIGIBLE'
    else 'NOT_ACTIVE_PARTICIPANT'
  end;

  return jsonb_build_object(
    'can_access', v_can_access,
    'reason_code', v_reason,
    'server_now', now(),
    'scheduled_start_at', v_booking.scheduled_start_at,
    'test_mode_schedule_bypass', v_test_bypass and v_can_access
  );
end;
$$;

revoke all on function public.get_live_tour_tracking_eligibility(uuid)
  from public, anon;
grant execute on function public.get_live_tour_tracking_eligibility(uuid)
  to authenticated;

commit;
