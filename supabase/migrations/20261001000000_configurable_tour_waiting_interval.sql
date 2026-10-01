begin;

-- The hourly waiting fee and this interval are the only configurable values.
-- The legacy per-15-minute column remains as a derived compatibility value.
alter table public.subtenant_fare_settings
  add column if not exists additional_waiting_interval_minutes integer
    not null default 15;
alter table public.subtenant_fare_settings
  add constraint subtenant_fare_additional_waiting_interval_check
  check (additional_waiting_interval_minutes between 1 and 60);

drop trigger if exists guard_municipal_tour_waiting_rate
  on public.subtenant_fare_settings;

update public.subtenant_fare_settings
set tour_waiting_fee_per_15_minutes = round(
  waiting_fee * additional_waiting_interval_minutes / 60.0,
  2
);

create or replace function public.guard_municipal_tour_waiting_rate()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT'
      or new.waiting_fee is distinct from old.waiting_fee
      or new.additional_waiting_interval_minutes
        is distinct from old.additional_waiting_interval_minutes
      or new.tour_waiting_fee_per_15_minutes
        is distinct from old.tour_waiting_fee_per_15_minutes then
    if auth.uid() is not null and not (
      auth.uid() = new.subtenant_id
      and public.current_profile_role() = 'subtenant'
      and exists(select 1 from public.subtenant_details office
        where office.id=auth.uid() and office.is_active
          and nullif(trim(office.province),'') is not null
          and public.cities_match(new.city,office.city))) then
      raise exception 'MUNICIPAL_TOUR_RATE_OWNER_REQUIRED';
    end if;
    new.tour_waiting_fee_per_15_minutes := round(
      new.waiting_fee * new.additional_waiting_interval_minutes / 60.0,
      2
    );
    insert into public.audit_logs(actor_id,action,table_name,record_id,description)
      values(auth.uid(),'tour_waiting_policy_changed','subtenant_fare_settings',
        new.id::text,'Municipality '||new.city||'; hourly PHP rate: '
        ||new.waiting_fee::text||'; interval minutes: '
        ||new.additional_waiting_interval_minutes::text);
  end if;
  return new;
end $$;

create trigger guard_municipal_tour_waiting_rate
before insert or update on public.subtenant_fare_settings
for each row execute function public.guard_municipal_tour_waiting_rate();

create or replace function public.resolve_tour_waiting_policy(
  p_municipality text,
  p_province text default null
)
returns table(
  subtenant_id uuid,
  hourly_rate numeric,
  interval_minutes integer,
  rate_per_interval numeric
) language plpgsql stable security definer set search_path = '' as $$
declare v_count integer;
begin
  select count(*) into v_count
  from public.subtenant_fare_settings s
  join public.subtenant_details sd on sd.id=s.subtenant_id
  join public.profiles p on p.id=s.subtenant_id
  where s.is_active and sd.is_active and p.role='subtenant'
    and public.cities_match(s.city,p_municipality)
    and public.cities_match(sd.city,p_municipality)
    and nullif(trim(sd.province),'') is not null
    and (p_province is null or public.cities_match(sd.province,p_province));
  if v_count > 1 then raise exception 'AMBIGUOUS_MUNICIPAL_TOUR_RATE'; end if;
  return query
    select s.subtenant_id,s.waiting_fee,
      s.additional_waiting_interval_minutes,
      round(s.waiting_fee * s.additional_waiting_interval_minutes / 60.0,2)
    from public.subtenant_fare_settings s
    join public.subtenant_details sd on sd.id=s.subtenant_id
    join public.profiles p on p.id=s.subtenant_id
    where s.is_active and sd.is_active and p.role='subtenant'
      and public.cities_match(s.city,p_municipality)
      and public.cities_match(sd.city,p_municipality)
      and nullif(trim(sd.province),'') is not null
      and (p_province is null or public.cities_match(sd.province,p_province));
end;
$$;
revoke all on function public.resolve_tour_waiting_policy(text,text)
  from public,anon,authenticated;

alter table public.package_bookings
  add column if not exists tour_waiting_hourly_rate_snapshot numeric(14,2),
  add column if not exists tour_waiting_interval_minutes_snapshot integer;

update public.package_bookings
set tour_waiting_hourly_rate_snapshot = tour_waiting_rate_snapshot * 4,
    tour_waiting_interval_minutes_snapshot = 15
where tour_waiting_rate_snapshot is not null
  and (tour_waiting_hourly_rate_snapshot is null
    or tour_waiting_interval_minutes_snapshot is null);

alter table public.package_bookings
  add constraint package_bookings_tour_waiting_hourly_rate_check
    check (tour_waiting_hourly_rate_snapshot >= 0),
  add constraint package_bookings_tour_waiting_interval_check
    check (tour_waiting_interval_minutes_snapshot between 1 and 60);

create or replace function public.snapshot_booking_tour_waiting_rate()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  select p.subtenant_id,p.hourly_rate,p.interval_minutes,p.rate_per_interval
    into new.tour_waiting_subtenant_id,
      new.tour_waiting_hourly_rate_snapshot,
      new.tour_waiting_interval_minutes_snapshot,
      new.tour_waiting_rate_snapshot
  from public.resolve_tour_waiting_policy(new.municipality,new.province) p;
  if new.tour_waiting_hourly_rate_snapshot is null
      or new.tour_waiting_interval_minutes_snapshot is null then
    raise exception 'TOUR_WAITING_RATE_NOT_CONFIGURED';
  end if;
  return new;
end $$;

create or replace function public.guard_booking_tour_waiting_snapshot()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.tour_waiting_subtenant_id is distinct from old.tour_waiting_subtenant_id
    or new.tour_waiting_rate_snapshot is distinct from old.tour_waiting_rate_snapshot
    or new.tour_waiting_hourly_rate_snapshot
      is distinct from old.tour_waiting_hourly_rate_snapshot
    or new.tour_waiting_interval_minutes_snapshot
      is distinct from old.tour_waiting_interval_minutes_snapshot then
    raise exception 'TOUR_WAITING_RATE_SNAPSHOT_IMMUTABLE';
  end if;
  return new;
end $$;

drop trigger if exists guard_booking_tour_waiting_snapshot
  on public.package_bookings;
create trigger guard_booking_tour_waiting_snapshot
before update of tour_waiting_subtenant_id,tour_waiting_rate_snapshot,
  tour_waiting_hourly_rate_snapshot,tour_waiting_interval_minutes_snapshot
on public.package_bookings
for each row execute function public.guard_booking_tour_waiting_snapshot();

alter table public.booking_stop_waiting_charges
  add column if not exists hourly_rate numeric(14,2);

update public.booking_stop_waiting_charges
set hourly_rate = rate_per_interval * 4
where hourly_rate is null and rate_per_interval is not null;

do $constraints$
declare item record;
begin
  for item in
    select conname from pg_constraint
    where conrelid='public.booking_stop_waiting_charges'::regclass
      and contype='c'
      and (pg_get_constraintdef(oid) like '%interval_minutes = 15%'
        or pg_get_constraintdef(oid) like '%additional_amount =%rate_per_interval%')
  loop
    execute format('alter table public.booking_stop_waiting_charges drop constraint %I',
      item.conname);
  end loop;
end
$constraints$;

alter table public.booking_stop_waiting_charges
  add constraint booking_stop_waiting_interval_range_check
    check (interval_minutes between 1 and 60),
  add constraint booking_stop_waiting_hourly_rate_check
    check (hourly_rate >= 0),
  add constraint booking_stop_waiting_aggregate_amount_check
    check (additional_amount = round(
      chargeable_intervals * coalesce(hourly_rate,0) * interval_minutes / 60.0,
      2
    ));

create or replace function public.get_municipal_tour_waiting_rate(
  p_municipality text,
  p_province text default null
)
returns numeric language sql stable security definer set search_path = '' as $$
  select p.rate_per_interval
  from public.resolve_tour_waiting_policy(p_municipality,p_province) p;
$$;
revoke all on function public.get_municipal_tour_waiting_rate(text,text)
  from public,anon;
grant execute on function public.get_municipal_tour_waiting_rate(text,text)
  to authenticated;

create or replace function public.get_municipal_tour_waiting_policy(
  p_municipality text,
  p_province text default null
)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'hourly_rate',p.hourly_rate,
    'interval_minutes',p.interval_minutes,
    'rate_per_interval',p.rate_per_interval
  )
  from public.resolve_tour_waiting_policy(p_municipality,p_province) p;
$$;
revoke all on function public.get_municipal_tour_waiting_policy(text,text)
  from public,anon;
grant execute on function public.get_municipal_tour_waiting_policy(text,text)
  to authenticated;

create or replace function public.snapshot_booking_stop_waiting_charge()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_booking public.package_bookings; v_subtenant uuid;
  v_hourly numeric; v_interval integer; v_rate numeric;
begin
  if new.actual_arrival_time is null or old.actual_arrival_time is not null then
    return new;
  end if;
  select * into v_booking from public.package_bookings where id=new.booking_id;
  v_subtenant := v_booking.tour_waiting_subtenant_id;
  v_hourly := v_booking.tour_waiting_hourly_rate_snapshot;
  v_interval := v_booking.tour_waiting_interval_minutes_snapshot;
  v_rate := v_booking.tour_waiting_rate_snapshot;
  if v_hourly is null or v_interval is null then
    select p.subtenant_id,p.hourly_rate,p.interval_minutes,p.rate_per_interval
      into v_subtenant,v_hourly,v_interval,v_rate
    from public.resolve_tour_waiting_policy(
      v_booking.municipality,
      v_booking.province
    ) p;
  end if;
  insert into public.booking_stop_waiting_charges(
    booking_id,itinerary_item_id,municipality,subtenant_id,included_minutes,
    arrived_at,paid_until,interval_minutes,hourly_rate,rate_per_interval)
  values (new.booking_id,new.id,v_booking.municipality,v_subtenant,
    new.estimated_stay_duration_minutes,new.actual_arrival_time,
    new.actual_arrival_time
      + make_interval(mins => new.estimated_stay_duration_minutes),
    coalesce(v_interval,15),v_hourly,v_rate)
  on conflict (booking_id,itinerary_item_id) do nothing;
  return new;
end $$;

create or replace function public.finalize_booking_stop_waiting_charge()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_charge public.booking_stop_waiting_charges; v_seconds integer;
  v_intervals integer; v_amount numeric(14,2); v_outstanding numeric;
  v_activity uuid;
begin
  if new.actual_departure_time is null or old.actual_departure_time is not null then
    return new;
  end if;
  select * into v_charge from public.booking_stop_waiting_charges
    where booking_id=new.booking_id and itinerary_item_id=new.id for update;
  if not found or v_charge.status='finalized' then return new; end if;
  v_seconds := greatest(0,ceil(extract(epoch from
    (new.actual_departure_time-v_charge.paid_until)))::integer);
  v_intervals := ceil(
    v_seconds::numeric / (v_charge.interval_minutes * 60)
  )::integer;
  v_amount := round(
    v_intervals * coalesce(v_charge.hourly_rate,0)
      * v_charge.interval_minutes / 60.0,
    2
  );
  update public.booking_stop_waiting_charges set
    departed_at=new.actual_departure_time,overtime_seconds=v_seconds,
    chargeable_intervals=v_intervals,additional_amount=v_amount,
    status='finalized',finalized_at=clock_timestamp(),
    updated_at=clock_timestamp()
  where id=v_charge.id and status='active';
  if v_amount > 0 then
    update public.package_bookings
      set remaining_balance=coalesce(remaining_balance,0)+v_amount,
        updated_at=clock_timestamp() where id=new.booking_id
      returning remaining_balance into v_outstanding;
    update public.booking_payment_requirements set amount=v_outstanding,
      status='required',satisfied_at=null,
      satisfied_by_payment_record_id=null,updated_at=clock_timestamp()
      where booking_id=new.booking_id and payment_stage='remaining_balance';
    if not found then
      insert into public.booking_payment_requirements(
        booking_id,payment_stage,amount
      ) values (new.booking_id,'remaining_balance',v_outstanding);
    end if;
  end if;
  select id into v_activity from public.package_activities
    where booking_id=new.booking_id limit 1;
  insert into public.trip_status_logs(
    activity_id,booking_id,status,notes,logged_at
  ) values(v_activity,new.booking_id,'waiting_charge_finalized',
    jsonb_build_object('itinerary_item_id',new.id,
      'municipality',v_charge.municipality,
      'hourly_rate',v_charge.hourly_rate,
      'interval_minutes',v_charge.interval_minutes,
      'rate',v_charge.rate_per_interval,
      'rate_unconfigured_at_arrival',v_charge.hourly_rate is null,
      'intervals',v_intervals,'amount',v_amount)::text,
    clock_timestamp());
  return new;
end $$;

create or replace function public.refresh_active_tour_waiting()
returns integer language plpgsql security definer set search_path = '' as $$
declare c public.booking_stop_waiting_charges;
  v_now timestamptz := clock_timestamp(); v_seconds integer;
  v_intervals integer; v_count integer := 0; v_user uuid;
begin
  for c in select charge.* from public.booking_stop_waiting_charges charge
    join public.package_bookings b on b.id=charge.booking_id
    where charge.status='active'
      and lower(coalesce(b.booking_status,b.status,''))
        not in ('cancelled','rejected','expired','completed','done')
      and charge.paid_until <= v_now + interval '15 minutes'
    for update skip locked loop
    for v_user in
      select b.tourist_id from public.package_bookings b where b.id=c.booking_id
      union
      select d.driver_id from public.booking_drivers d
        where d.booking_id=c.booking_id and d.status='accepted'
    loop
      if v_now >= c.paid_until-interval '15 minutes'
          and v_now < c.paid_until-interval '5 minutes' then
        perform public.emit_tour_notification(v_user,c.booking_id,
          'stay:15:'||c.itinerary_item_id,'paid_stay_ending',
          'Paid stay ending soon','Included waiting at '
          ||(select destination_name from public.booking_itinerary_items
             where id=c.itinerary_item_id)||' ends at '
          ||to_char(c.paid_until at time zone 'Asia/Manila','HH12:MI AM')
          ||case when c.hourly_rate is null
            then '. No additional fee will be assessed for this stop because the municipality rate was not configured at arrival.'
            else '. Additional waiting charges apply after that.' end,true);
      end if;
      if v_now >= c.paid_until-interval '5 minutes' and v_now < c.paid_until then
        perform public.emit_tour_notification(v_user,c.booking_id,
          'stay:5:'||c.itinerary_item_id,'paid_stay_ending',
          'Paid stay ending soon','Included waiting at '
          ||(select destination_name from public.booking_itinerary_items
             where id=c.itinerary_item_id)||' ends at '
          ||to_char(c.paid_until at time zone 'Asia/Manila','HH12:MI AM')
          ||case when c.hourly_rate is null
            then '. No additional fee will be assessed for this stop because the municipality rate was not configured at arrival.'
            else '. Additional waiting charges apply after that.' end,true);
      end if;
      if v_now >= c.paid_until then
        perform public.emit_tour_notification(v_user,c.booking_id,
          'stay:overtime:'||c.itinerary_item_id,'additional_waiting',
          case when c.hourly_rate is null
            then 'Included stay ended' else 'Additional waiting' end,
          'Included waiting has ended at '
          ||(select destination_name from public.booking_itinerary_items
             where id=c.itinerary_item_id)
          ||case when c.hourly_rate is null
            then '. No additional fee will be assessed for this stop because the municipality rate was not configured at arrival.'
            else '. Additional waiting charges now apply.' end,true);
      end if;
    end loop;
    v_seconds := greatest(0,ceil(extract(epoch from v_now-c.paid_until))::integer);
    v_intervals := ceil(
      v_seconds::numeric / (c.interval_minutes * 60)
    )::integer;
    if v_intervals <> c.chargeable_intervals then
      update public.booking_stop_waiting_charges set
        overtime_seconds=v_seconds,chargeable_intervals=v_intervals,
        additional_amount=round(
          v_intervals * coalesce(c.hourly_rate,0) * c.interval_minutes / 60.0,
          2
        ),updated_at=v_now
      where id=c.id and status='active';
      v_count := v_count+1;
    end if;
  end loop;
  return v_count;
end $$;
revoke all on function public.refresh_active_tour_waiting()
  from public,anon,authenticated;

create or replace function public.get_booking_waiting_summary(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare b public.package_bookings; v_rate numeric; v_hourly numeric;
  v_interval integer; v_subtenant uuid; v_finalized numeric;
  v_accrued numeric; v_now timestamptz := clock_timestamp();
begin
  select * into b from public.package_bookings where id=p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if not public.can_read_tour_booking(b.id) then
    raise exception 'BOOKING_ACCESS_DENIED';
  end if;
  v_subtenant := b.tour_waiting_subtenant_id;
  v_hourly := b.tour_waiting_hourly_rate_snapshot;
  v_interval := b.tour_waiting_interval_minutes_snapshot;
  v_rate := b.tour_waiting_rate_snapshot;
  if v_hourly is null or v_interval is null then
    select p.subtenant_id,p.hourly_rate,p.interval_minutes,p.rate_per_interval
      into v_subtenant,v_hourly,v_interval,v_rate
    from public.resolve_tour_waiting_policy(b.municipality,b.province) p;
  end if;
  select coalesce(sum(additional_amount) filter(where status='finalized'),0),
    coalesce(sum(additional_amount) filter(where status='active'),0)
    into v_finalized,v_accrued from public.booking_stop_waiting_charges
    where booking_id=b.id;
  return jsonb_build_object('booking_id',b.id,'municipality',b.municipality,
    'subtenant_id',v_subtenant,'current_hourly_rate',v_hourly,
    'current_interval_minutes',v_interval,'current_rate_per_interval',v_rate,
    'current_rate_per_15_minutes',
      case when v_hourly is null then null else round(v_hourly/4.0,2) end,
    'server_time',v_now,
    'package_remaining',greatest(0,coalesce(b.remaining_balance,0)-v_finalized),
    'finalized_waiting',v_finalized,'accrued_waiting',v_accrued,
    'total_remaining',greatest(0,coalesce(b.remaining_balance,0))+v_accrued,
    'charges',coalesce((select jsonb_agg(jsonb_build_object(
      'itinerary_item_id',c.itinerary_item_id,
      'destination_name',i.destination_name,'arrived_at',c.arrived_at,
      'paid_until',c.paid_until,'departed_at',c.departed_at,
      'included_minutes',c.included_minutes,
      'hourly_rate',c.hourly_rate,'interval_minutes',c.interval_minutes,
      'rate_per_interval',c.rate_per_interval,
      'overtime_seconds',c.overtime_seconds,
      'chargeable_intervals',c.chargeable_intervals,
      'additional_amount',c.additional_amount,'status',c.status)
      order by c.arrived_at) from public.booking_stop_waiting_charges c
      join public.booking_itinerary_items i on i.id=c.itinerary_item_id
      where c.booking_id=b.id),'[]'::jsonb));
end $$;
revoke all on function public.get_booking_waiting_summary(uuid)
  from public,anon;
grant execute on function public.get_booking_waiting_summary(uuid)
  to authenticated;

commit;
