-- Emergency assistance belongs only to an active tour. Enforce this both in
-- the tourist INSERT policy and before any alert row can be persisted so a
-- stale or modified client cannot raise an alert for terminal history.

create or replace function public.validate_active_tour_emergency_alert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking_status text;
  v_refund_status text;
  v_picked_up_at timestamptz;
  v_tourist_id uuid;
  v_tour_status text;
begin
  if new.booking_id is null then
    raise exception using
      errcode = '23514',
      message = 'EMERGENCY_ALERT_REQUIRES_ACTIVE_TOUR';
  end if;

  select
    lower(coalesce(pb.booking_status, pb.status, '')),
    lower(coalesce(pb.refund_status, '')),
    pb.picked_up_at,
    pb.tourist_id
  into v_booking_status, v_refund_status, v_picked_up_at, v_tourist_id
  from public.package_bookings pb
  where pb.id = new.booking_id;

  if not found or v_tourist_id is distinct from new.tourist_id then
    raise exception using
      errcode = '23514',
      message = 'EMERGENCY_ALERT_BOOKING_MISMATCH';
  end if;

  select lower(coalesce(pa.tour_status, pa.status, ''))
  into v_tour_status
  from public.package_activities pa
  where pa.booking_id = new.booking_id
  order by pa.updated_at desc nulls last
  limit 1;

  if v_booking_status in (
      'completed', 'done', 'cancelled', 'refunded', 'rejected', 'failed', 'expired'
    )
    or v_refund_status = 'refunded'
    or coalesce(v_tour_status, '') in (
      'completed', 'done', 'cancelled', 'refunded', 'rejected', 'failed',
      'expired', 'dropped_off'
    ) then
    raise exception using
      errcode = '23514',
      message = 'EMERGENCY_ALERT_NOT_ALLOWED_FOR_TERMINAL_TOUR';
  end if;

  if v_picked_up_at is null
    and coalesce(v_tour_status, '') not in (
      'picked_up', 'on_tour', 'en_route_to_spot', 'at_spot',
      'en_route_to_dropoff', 'ready_to_complete'
    ) then
    raise exception using
      errcode = '23514',
      message = 'EMERGENCY_ALERT_REQUIRES_ACTIVE_TOUR';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_active_tour_emergency_alert() from public;

drop trigger if exists validate_active_tour_emergency_alert
  on public.emergency_alerts;
create trigger validate_active_tour_emergency_alert
before insert on public.emergency_alerts
for each row execute function public.validate_active_tour_emergency_alert();

drop policy if exists "tourist_insert_own_emergency"
  on public.emergency_alerts;
create policy "tourist_insert_own_emergency"
on public.emergency_alerts
for insert to authenticated
with check (
  auth.uid() = tourist_id
  and booking_id is not null
  and exists (
    select 1
    from public.package_bookings pb
    where pb.id = booking_id
      and pb.tourist_id = auth.uid()
      and lower(coalesce(pb.booking_status, pb.status, '')) not in (
        'completed', 'done', 'cancelled', 'refunded', 'rejected', 'failed', 'expired'
      )
      and lower(coalesce(pb.refund_status, '')) <> 'refunded'
      and (
        pb.picked_up_at is not null
        or exists (
          select 1
          from public.package_activities pa
          where pa.booking_id = pb.id
            and lower(coalesce(pa.tour_status, pa.status, '')) in (
              'picked_up', 'on_tour', 'en_route_to_spot', 'at_spot',
              'en_route_to_dropoff', 'ready_to_complete'
            )
        )
      )
  )
);
