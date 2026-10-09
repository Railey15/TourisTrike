-- Keep the Driver Home earnings summary aligned with the authoritative
-- allocation earning lifecycle. Refund-pending and refunded allocations stay
-- visible in the ledger, but must never be counted as completed earnings.

create or replace function public.get_driver_home_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_driver uuid := auth.uid();
  v_start timestamptz;
begin
  if v_driver is null or public.current_profile_role() is distinct from 'driver' then
    raise exception 'DRIVER_ROLE_REQUIRED';
  end if;

  v_start := date_trunc('day', now() at time zone 'Asia/Manila') at time zone 'Asia/Manila';

  return jsonb_build_object(
    'completed_tours', (
      select count(*)
      from public.booking_drivers
      where driver_id = v_driver and status = 'completed'
    ),
    'today_trips', (
      select count(*)
      from public.booking_drivers
      where driver_id = v_driver
        and status = 'completed'
        and completed_at >= v_start
        and completed_at < v_start + interval '1 day'
    ),
    'active_trips', (
      select count(*)
      from public.booking_drivers bd
      join public.package_bookings pb on pb.id = bd.booking_id
      where bd.driver_id = v_driver
        and bd.status = 'accepted'
        and pb.status not in ('completed', 'cancelled', 'rejected')
        and pb.tracking_interrupted_at is null
        and (pb.scheduled_start_at <= now() or bd.journey_state <> 'assigned')
    ),
    'interrupted_trips', (
      select count(*)
      from public.booking_drivers bd
      join public.package_bookings pb on pb.id = bd.booking_id
      where bd.driver_id = v_driver
        and bd.status = 'accepted'
        and pb.tracking_interrupted_at is not null
        and pb.status not in ('completed', 'cancelled', 'rejected')
    ),
    'upcoming_trips', (
      select count(*)
      from public.booking_drivers bd
      join public.package_bookings pb on pb.id = bd.booking_id
      where bd.driver_id = v_driver
        and bd.status = 'accepted'
        and pb.status not in ('completed', 'cancelled', 'rejected')
        and pb.scheduled_start_at > now()
        and bd.journey_state = 'assigned'
    ),
    'average_rating', (
      select coalesce(round(avg(rating), 2), 0)
      from public.driver_reviews
      where driver_id = v_driver and rating between 1 and 5
    ),
    'review_count', (
      select count(*)
      from public.driver_reviews
      where driver_id = v_driver and rating between 1 and 5
    ),
    'recent_reviews', coalesce((
      select jsonb_agg(r order by r.created_at desc)
      from (
        select booking_id, rating, review_text, created_at
        from public.driver_reviews
        where driver_id = v_driver and rating between 1 and 5
        order by created_at desc
        limit 5
      ) r
    ), '[]'::jsonb),
    'today_earnings', (
      select coalesce(sum(pa.driver_amount), 0)
      from public.payment_allocations pa
      join public.payment_records pr on pr.id = pa.payment_record_id
      where pa.driver_id = v_driver
        and pr.status = 'confirmed'
        and pa.earning_status = 'completed'
        and coalesce(pr.paid_at, pa.paid_at) >= v_start
        and coalesce(pr.paid_at, pa.paid_at) < v_start + interval '1 day'
    ),
    'assignments', coalesce((
      select jsonb_agg(a order by a.scheduled_start_at)
      from (
        select
          bd.booking_id,
          bd.journey_state,
          pb.scheduled_start_at,
          pb.tracking_interrupted_at,
          tp.title,
          (select id from public.package_activities where booking_id = pb.id limit 1) as activity_id
        from public.booking_drivers bd
        join public.package_bookings pb on pb.id = bd.booking_id
        join public.tour_packages tp on tp.id = pb.package_id
        where bd.driver_id = v_driver
          and bd.status = 'accepted'
          and pb.status not in ('completed', 'cancelled', 'rejected')
        order by pb.scheduled_start_at
        limit 10
      ) a
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_driver_home_overview() from public, anon;
grant execute on function public.get_driver_home_overview() to authenticated;

