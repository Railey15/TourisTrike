begin;

-- The existing tour rate column is named per_15_minutes. Its value is now
-- interpreted per configured interval; the legacy name is kept for clients.
alter table public.subtenant_fare_settings
  add column if not exists tour_waiting_interval_minutes integer not null default 15
  check (tour_waiting_interval_minutes between 1 and 120);
alter table public.package_bookings
  add column if not exists tour_waiting_interval_snapshot integer
  check (tour_waiting_interval_snapshot between 1 and 120);
create or replace function public.snapshot_booking_waiting_interval()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  select s.tour_waiting_interval_minutes into new.tour_waiting_interval_snapshot
    from public.subtenant_fare_settings s
    where s.subtenant_id=new.tour_waiting_subtenant_id
      and public.cities_match(s.city,new.municipality) and s.is_active
    order by s.updated_at desc limit 1;
  new.tour_waiting_interval_snapshot := coalesce(new.tour_waiting_interval_snapshot,15);
  return new;
end $$;
drop trigger if exists zz_snapshot_booking_waiting_interval on public.package_bookings;
create trigger zz_snapshot_booking_waiting_interval before insert on public.package_bookings
for each row execute function public.snapshot_booking_waiting_interval();
alter table public.booking_stop_waiting_charges
  drop constraint if exists booking_stop_waiting_charges_interval_minutes_check;
alter table public.booking_stop_waiting_charges
  add constraint booking_stop_waiting_charges_interval_minutes_check
  check (interval_minutes between 1 and 120);

create or replace function public.tour_waiting_chargeable_intervals(
  p_overtime_seconds numeric, p_interval_minutes integer)
returns integer language sql immutable set search_path = '' as $$
  select case when p_overtime_seconds is null or p_overtime_seconds < 0
      or p_interval_minutes is null or p_interval_minutes < 1 then 0
    else floor(p_overtime_seconds / (p_interval_minutes * 60))::integer end;
$$;

create or replace function public.get_municipal_tour_waiting_policy(
  p_municipality text,p_province text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_subtenant uuid; v_rate numeric; v_interval integer;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  select r.subtenant_id,r.rate into v_subtenant,v_rate
    from public.resolve_tour_waiting_rate(p_municipality,p_province) r;
  if v_rate is null then return null; end if;
  select s.tour_waiting_interval_minutes into v_interval
    from public.subtenant_fare_settings s
    where s.subtenant_id=v_subtenant and s.is_active
      and public.cities_match(s.city,p_municipality)
    order by s.updated_at desc limit 1;
  return jsonb_build_object('rate',v_rate,'interval_minutes',coalesce(v_interval,15));
end $$;
revoke all on function public.get_municipal_tour_waiting_policy(text,text)
from public,anon;
grant execute on function public.get_municipal_tour_waiting_policy(text,text)
to authenticated;

create or replace function public.snapshot_booking_stop_waiting_charge()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_booking public.package_bookings; v_subtenant uuid; v_rate numeric;
  v_interval integer := 15;
begin
  if new.actual_arrival_time is null or old.actual_arrival_time is not null then return new; end if;
  select * into v_booking from public.package_bookings where id = new.booking_id;
  v_subtenant := v_booking.tour_waiting_subtenant_id;
  v_rate := v_booking.tour_waiting_rate_snapshot;
  if v_rate is null then
    select r.subtenant_id,r.rate into v_subtenant,v_rate
      from public.resolve_tour_waiting_rate(v_booking.municipality,v_booking.province) r;
  end if;
  v_interval := coalesce(v_booking.tour_waiting_interval_snapshot,15);
  insert into public.booking_stop_waiting_charges(
    booking_id,itinerary_item_id,municipality,subtenant_id,included_minutes,
    arrived_at,paid_until,rate_per_interval,interval_minutes)
  values (new.booking_id,new.id,v_booking.municipality,v_subtenant,
    new.estimated_stay_duration_minutes,new.actual_arrival_time,
    new.actual_arrival_time + make_interval(mins => new.estimated_stay_duration_minutes),
    v_rate,coalesce(v_interval,15))
  on conflict (booking_id,itinerary_item_id) do nothing;
  return new;
end $$;

-- Keep the existing payment reconciliation, idempotency, and notification
-- implementations. Replace only the accrued interval arithmetic and wording.
do $waiting_patch$
declare v_definition text; v_name text; v_old text; v_new text;
begin
  foreach v_name in array array[
    'public.finalize_booking_stop_waiting_charge()',
    'public.refresh_active_tour_waiting()'] loop
    v_definition := pg_get_functiondef(v_name::regprocedure);
    v_old := 'v_intervals := ceil(v_seconds / 900.0)::integer;';
    v_new := case when v_name like '%finalize%'
      then 'v_intervals := public.tour_waiting_chargeable_intervals(v_seconds, v_charge.interval_minutes);'
      else 'v_intervals := public.tour_waiting_chargeable_intervals(v_seconds, c.interval_minutes);' end;
    if (length(v_definition)-length(replace(v_definition,v_old,''))) / length(v_old) <> 1 then
      raise exception 'UNEXPECTED_WAITING_INTERVAL_CONTRACT: %',v_name;
    end if;
    v_definition := replace(v_definition,v_old,v_new);
    v_old := 'greatest(0,ceil(extract(epoch from';
    v_new := 'greatest(0,floor(extract(epoch from';
    if (length(v_definition)-length(replace(v_definition,v_old,''))) / length(v_old) <> 1 then
      raise exception 'UNEXPECTED_WAITING_SECONDS_CONTRACT: %',v_name;
    end if;
    v_definition := replace(v_definition,v_old,v_new);
    if v_name like '%refresh%' then
      v_definition := replace(v_definition,
        'if v_now >= c.paid_until then',
        'if v_now >= c.paid_until + make_interval(mins => c.interval_minutes) then');
      v_definition := replace(v_definition,
        '. Additional waiting charges apply after that.',
        '. One configured interval after the included stay is free.');
      v_definition := replace(v_definition,
        '. Additional waiting charges now apply.',
        '. The free grace interval has ended; additional charges now apply.');
    end if;
    execute v_definition;
  end loop;
end $waiting_patch$;

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
  select coalesce(sum(additional_amount) filter(where status='finalized'),0),
    coalesce(sum(additional_amount) filter(where status='active'),0)
    into v_finalized,v_accrued from public.booking_stop_waiting_charges
    where booking_id=b.id;
  return jsonb_build_object('booking_id',b.id,'municipality',b.municipality,
    'subtenant_id',v_subtenant,'current_rate_per_15_minutes',v_rate,
    'current_interval_minutes',coalesce(v_interval,15),
    'server_time',v_now,
    'package_remaining',greatest(0,coalesce(b.remaining_balance,0)-v_finalized),
    'finalized_waiting',v_finalized,'accrued_waiting',v_accrued,
    'total_remaining',greatest(0,coalesce(b.remaining_balance,0))+v_accrued,
    'charges',coalesce((select jsonb_agg(jsonb_build_object(
      'itinerary_item_id',c.itinerary_item_id,'destination_name',i.destination_name,
      'arrived_at',c.arrived_at,'paid_until',c.paid_until,'departed_at',c.departed_at,
      'included_minutes',c.included_minutes,'interval_minutes',c.interval_minutes,
      'rate_per_interval',c.rate_per_interval,'overtime_seconds',c.overtime_seconds,
      'chargeable_intervals',c.chargeable_intervals,
      'additional_amount',c.additional_amount,'status',c.status)
      order by c.arrived_at) from public.booking_stop_waiting_charges c
      join public.booking_itinerary_items i on i.id=c.itinerary_item_id
      where c.booking_id=b.id),'[]'::jsonb));
end $$;

commit;
