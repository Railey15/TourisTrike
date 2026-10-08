-- Keep the configured grace interval and rate snapshot authoritative.
-- The previous grace migration replaced the snapshot trigger with a version
-- that populated rate_per_interval but left hourly_rate NULL. The active and
-- final charge functions still multiplied hourly_rate, producing zero.
begin;
create or replace function public.snapshot_booking_stop_waiting_charge()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  b public.package_bookings;
  v_subtenant uuid;
  v_hourly numeric;
  v_interval integer;
  v_rate numeric;
begin
  if new.actual_arrival_time is null or old.actual_arrival_time is not null then
    return new;
  end if;
  select * into b from public.package_bookings where id = new.booking_id;
  v_subtenant := b.tour_waiting_subtenant_id;
  v_hourly := b.tour_waiting_hourly_rate_snapshot;
  v_interval := coalesce(b.tour_waiting_interval_snapshot,
                         b.tour_waiting_interval_minutes_snapshot);
  v_rate := b.tour_waiting_rate_snapshot;
  if v_rate is null then
    select p.subtenant_id, p.hourly_rate, p.interval_minutes,
           p.rate_per_interval
      into v_subtenant, v_hourly, v_interval, v_rate
    from public.resolve_tour_waiting_policy(b.municipality, b.province) p;
  end if;
  v_interval := coalesce(v_interval, 15);
  -- Existing accrual functions multiply hourly_rate by the interval length.
  -- Derive it from the booking's authoritative rate per interval.
  v_hourly := case when v_rate is null then null
    else v_rate * 60.0 / v_interval end;
  insert into public.booking_stop_waiting_charges (
    booking_id, itinerary_item_id, municipality, subtenant_id,
    included_minutes, arrived_at, paid_until, interval_minutes,
    hourly_rate, rate_per_interval
  ) values (
    new.booking_id, new.id, b.municipality, v_subtenant,
    new.estimated_stay_duration_minutes, new.actual_arrival_time,
    new.actual_arrival_time +
      make_interval(mins => new.estimated_stay_duration_minutes),
    v_interval, v_hourly, v_rate
  ) on conflict (booking_id, itinerary_item_id) do nothing;
  return new;
end $$;
-- Reconcile only open ledgers. Finalized fees and confirmed payments remain
-- exactly as recorded, including historical zero-amount rows.
with repaired as (
  select c.id, c.rate_per_interval * 60.0 / c.interval_minutes as hourly,
    greatest(0, floor(extract(epoch from clock_timestamp() -
      coalesce(c.test_deadline_override, c.paid_until))))::integer as seconds,
    c.interval_minutes, c.rate_per_interval,
    c.test_rate_per_interval_override
  from public.booking_stop_waiting_charges c
  where c.status = 'active' and c.rate_per_interval is not null
)
update public.booking_stop_waiting_charges c
set hourly_rate = r.hourly,
    overtime_seconds = r.seconds,
    chargeable_intervals = public.tour_waiting_chargeable_intervals(
      r.seconds, r.interval_minutes),
    additional_amount = round(
      public.tour_waiting_chargeable_intervals(r.seconds, r.interval_minutes)
      * coalesce(r.test_rate_per_interval_override, r.rate_per_interval), 2),
    updated_at = clock_timestamp()
from repaired r where c.id = r.id;
-- Reads calculate open-stop accrual from server time. A delayed cron refresh
-- must not leave the Tourist and Driver displaying an old zero amount.
create or replace function public.get_booking_waiting_summary(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare b public.package_bookings; v_rate numeric; v_subtenant uuid;
  v_interval integer := 15; v_finalized numeric; v_accrued numeric;
  v_now timestamptz := clock_timestamp();
begin
  select * into b from public.package_bookings where id=p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if not public.can_read_tour_booking(b.id) then raise exception 'BOOKING_ACCESS_DENIED'; end if;
  v_subtenant := b.tour_waiting_subtenant_id;
  v_rate := b.tour_waiting_rate_snapshot;
  if v_rate is null then
    select r.subtenant_id,r.rate into v_subtenant,v_rate
    from public.resolve_tour_waiting_rate(b.municipality,b.province) r;
  end if;
  v_interval := coalesce(b.tour_waiting_interval_snapshot,15);
  select coalesce(sum(c.additional_amount) filter(where c.status='finalized'),0),
    coalesce(sum(round(
      public.tour_waiting_chargeable_intervals(
        greatest(0,floor(extract(epoch from v_now-
          coalesce(c.test_deadline_override,c.paid_until))))::integer,
        c.interval_minutes)
      * coalesce(c.test_rate_per_interval_override,c.rate_per_interval,
          c.hourly_rate * c.interval_minutes / 60.0,0),2
    )) filter(where c.status='active'),0)
  into v_finalized,v_accrued from public.booking_stop_waiting_charges c
  where c.booking_id=b.id;
  return jsonb_build_object(
    'booking_id',b.id,'municipality',b.municipality,'subtenant_id',v_subtenant,
    'current_rate_per_15_minutes',v_rate,'current_interval_minutes',v_interval,
    'server_time',v_now,
    'package_remaining',greatest(0,coalesce(b.remaining_balance,0)-v_finalized),
    'finalized_waiting',v_finalized,'accrued_waiting',v_accrued,
    'total_remaining',greatest(0,coalesce(b.remaining_balance,0))+v_accrued,
    'charges',coalesce((select jsonb_agg(jsonb_build_object(
      'itinerary_item_id',c.itinerary_item_id,'destination_name',i.destination_name,
      'arrived_at',c.arrived_at,
      'paid_until',coalesce(c.test_deadline_override,c.paid_until),
      'configured_paid_until',c.paid_until,'departed_at',c.departed_at,
      'included_minutes',c.included_minutes,'interval_minutes',c.interval_minutes,
      'rate_per_interval',coalesce(c.test_rate_per_interval_override,c.rate_per_interval),
      'configured_rate_per_interval',c.rate_per_interval,
      'overtime_seconds',case when c.status='active' then
        greatest(0,floor(extract(epoch from v_now-
          coalesce(c.test_deadline_override,c.paid_until))))::integer
        else c.overtime_seconds end,
      'chargeable_intervals',case when c.status='active' then
        public.tour_waiting_chargeable_intervals(
          greatest(0,floor(extract(epoch from v_now-
            coalesce(c.test_deadline_override,c.paid_until))))::integer,
          c.interval_minutes) else c.chargeable_intervals end,
      'additional_amount',case when c.status='active' then round(
        public.tour_waiting_chargeable_intervals(
          greatest(0,floor(extract(epoch from v_now-
            coalesce(c.test_deadline_override,c.paid_until))))::integer,
          c.interval_minutes)
        * coalesce(c.test_rate_per_interval_override,c.rate_per_interval,
            c.hourly_rate * c.interval_minutes / 60.0,0),2)
        else c.additional_amount end,'status',c.status,
      'test_override_active',c.test_deadline_override is not null
        or c.test_rate_per_interval_override is not null,
      'test_override_kind',c.test_override_kind
    ) order by c.arrived_at) from public.booking_stop_waiting_charges c
      join public.booking_itinerary_items i on i.id=c.itinerary_item_id
      where c.booking_id=b.id),'[]'::jsonb)
  );
end $$;
revoke all on function public.get_booking_waiting_summary(uuid)
  from public, anon;
grant execute on function public.get_booking_waiting_summary(uuid)
  to authenticated;
commit;
