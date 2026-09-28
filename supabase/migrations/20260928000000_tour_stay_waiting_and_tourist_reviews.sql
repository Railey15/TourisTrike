-- Forward migration only. The historical migration queue must be reconciled before deployment.
begin;

-- The existing waiting_fee is an hourly ride fare. Tour overtime has its own unit.
alter table public.subtenant_fare_settings
  add column if not exists tour_waiting_fee_per_15_minutes numeric(14,2);
alter table public.subtenant_fare_settings
  add constraint tour_waiting_fee_nonnegative
  check (tour_waiting_fee_per_15_minutes >= 0);

create or replace function public.guard_municipal_tour_waiting_rate()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.tour_waiting_fee_per_15_minutes
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
    insert into public.audit_logs(actor_id,action,table_name,record_id,description)
      values(auth.uid(),'tour_waiting_rate_changed','subtenant_fare_settings',new.id::text,
        'Municipality '||new.city||'; new PHP rate per 15 minutes: '||
        coalesce(new.tour_waiting_fee_per_15_minutes::text,'unset'));
  end if;
  return new;
end $$;
create trigger guard_municipal_tour_waiting_rate
before insert or update on public.subtenant_fare_settings
for each row execute function public.guard_municipal_tour_waiting_rate();

create table public.booking_stop_waiting_charges (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.package_bookings(id) on delete cascade,
  itinerary_item_id uuid not null references public.booking_itinerary_items(id) on delete cascade,
  municipality text not null,
  subtenant_id uuid references public.profiles(id),
  included_minutes integer not null check (included_minutes >= 0),
  arrived_at timestamptz not null,
  paid_until timestamptz not null,
  departed_at timestamptz,
  interval_minutes integer not null default 15 check (interval_minutes = 15),
  overtime_seconds integer not null default 0 check (overtime_seconds >= 0),
  chargeable_intervals integer not null default 0 check (chargeable_intervals >= 0),
  rate_per_interval numeric(14,2) check (rate_per_interval >= 0),
  additional_amount numeric(14,2) not null default 0 check (additional_amount >= 0),
  status text not null default 'active' check (status in ('active','finalized')),
  finalized_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (booking_id,itinerary_item_id),
  check ((status = 'active' and finalized_at is null and departed_at is null)
      or (status = 'finalized' and finalized_at is not null and departed_at is not null)),
  check (paid_until = arrived_at + make_interval(mins => included_minutes)),
  check (additional_amount = chargeable_intervals * coalesce(rate_per_interval,0))
);
create index booking_stop_waiting_charges_booking_idx
  on public.booking_stop_waiting_charges(booking_id, status);
create index booking_stop_waiting_charges_report_idx
  on public.booking_stop_waiting_charges(municipality, finalized_at)
  where status = 'finalized';
create or replace function public.main_tenant_can_read_booking(p_booking_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_main_tenant() and exists(
    select 1 from public.package_bookings b
    join public.profiles p on p.id=auth.uid()
    where b.id=p_booking_id and nullif(trim(p.province),'') is not null
      and trim(p.province) ~ '^[[:alpha:]][[:alpha:] .''-]*$'
      and public.cities_match(b.province,p.province));
$$;
revoke all on function public.main_tenant_can_read_booking(uuid) from public,anon;
grant execute on function public.main_tenant_can_read_booking(uuid) to authenticated;
create or replace function public.can_read_tour_booking(p_booking_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from public.package_bookings b
    join public.profiles actor on actor.id=auth.uid()
    left join public.subtenant_details office on office.id=actor.id
    where b.id=p_booking_id and (
      (actor.role='tourist' and b.tourist_id=actor.id)
      or (actor.role='driver' and (b.assigned_driver_id=actor.id or exists (
        select 1 from public.booking_drivers d where d.booking_id=b.id
          and d.driver_id=actor.id and d.status in ('accepted','completed'))))
      or (actor.role='subtenant' and office.is_active
        and nullif(trim(office.city),'') is not null
        and nullif(trim(office.province),'') is not null
        and public.cities_match(b.municipality,office.city)
        and public.cities_match(b.province,office.province))
      or public.main_tenant_can_read_booking(b.id)
    )
  );
$$;
revoke all on function public.can_read_tour_booking(uuid) from public,anon;
grant execute on function public.can_read_tour_booking(uuid) to authenticated;
-- Cap provincial fare visibility without changing any ride fare arithmetic.
create policy tour_fare_province_read_scope on public.subtenant_fare_settings
as restrictive for select to authenticated using (
  not public.is_main_tenant() or exists (
    select 1 from public.profiles actor
    join public.subtenant_details office on office.id=subtenant_fare_settings.subtenant_id
    where actor.id=auth.uid() and nullif(trim(actor.province),'') is not null
      and public.cities_match(office.province,actor.province)
  )
);
alter table public.booking_stop_waiting_charges enable row level security;
revoke all on public.booking_stop_waiting_charges from public, anon, authenticated;
grant select on public.booking_stop_waiting_charges to authenticated;
create policy waiting_charge_participants_read
on public.booking_stop_waiting_charges for select to authenticated using (
  public.can_read_tour_booking(booking_stop_waiting_charges.booking_id)
);

-- One source of truth for the municipality's active tour rate. No rate fallback.
create or replace function public.resolve_tour_waiting_rate(p_municipality text,p_province text default null)
returns table(subtenant_id uuid, rate numeric) language plpgsql stable security definer
set search_path = '' as $$
declare v_count integer;
begin
  select count(*) into v_count
  from public.subtenant_fare_settings s
  join public.subtenant_details sd on sd.id = s.subtenant_id
  join public.profiles p on p.id = s.subtenant_id
  where s.is_active and sd.is_active and p.role = 'subtenant'
    and public.cities_match(s.city,p_municipality)
    and public.cities_match(sd.city,p_municipality)
    and nullif(trim(sd.province),'') is not null
    and (p_province is null or public.cities_match(sd.province,p_province))
    and s.tour_waiting_fee_per_15_minutes is not null;
  if v_count > 1 then raise exception 'AMBIGUOUS_MUNICIPAL_TOUR_RATE'; end if;
  return query select s.subtenant_id,s.tour_waiting_fee_per_15_minutes
    from public.subtenant_fare_settings s
    join public.subtenant_details sd on sd.id=s.subtenant_id
    join public.profiles p on p.id=s.subtenant_id
    where s.is_active and sd.is_active and p.role='subtenant'
      and public.cities_match(s.city,p_municipality)
      and public.cities_match(sd.city,p_municipality)
      and nullif(trim(sd.province),'') is not null
      and (p_province is null or public.cities_match(sd.province,p_province))
      and s.tour_waiting_fee_per_15_minutes is not null;
end;
$$;
revoke all on function public.resolve_tour_waiting_rate(text,text) from public, anon, authenticated;

alter table public.package_bookings
  add column if not exists tour_waiting_subtenant_id uuid references public.profiles(id),
  add column if not exists tour_waiting_rate_snapshot numeric(14,2)
    check (tour_waiting_rate_snapshot >= 0);

create or replace function public.snapshot_booking_tour_waiting_rate()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  select r.subtenant_id,r.rate into new.tour_waiting_subtenant_id,new.tour_waiting_rate_snapshot
    from public.resolve_tour_waiting_rate(new.municipality,new.province) r;
  if new.tour_waiting_rate_snapshot is null then
    raise exception 'TOUR_WAITING_RATE_NOT_CONFIGURED';
  end if;
  return new;
end $$;
create trigger snapshot_booking_tour_waiting_rate
before insert on public.package_bookings
for each row execute function public.snapshot_booking_tour_waiting_rate();

create or replace function public.guard_booking_tour_waiting_snapshot()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.tour_waiting_subtenant_id is distinct from old.tour_waiting_subtenant_id
    or new.tour_waiting_rate_snapshot is distinct from old.tour_waiting_rate_snapshot then
    raise exception 'TOUR_WAITING_RATE_SNAPSHOT_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger guard_booking_tour_waiting_snapshot
before update of tour_waiting_subtenant_id,tour_waiting_rate_snapshot on public.package_bookings
for each row execute function public.guard_booking_tour_waiting_snapshot();

create or replace function public.guard_booked_stay_financial_fields()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_trusted boolean :=
  coalesce(current_setting('touristrike.gps_transition_verified',true),'')='true'
  or coalesce(current_setting('touristrike.driver_slide',true),'')='true'
  or coalesce(current_setting('touristrike.journey_rpc',true),'')='true'
  or length(coalesce(current_setting('touristrike.manual_lifecycle_reason',true),''))>=10;
begin
  if auth.uid() is null then return new; end if;
  if new.estimated_stay_duration_minutes is distinct from old.estimated_stay_duration_minutes then
    raise exception 'BOOKED_STAY_IMMUTABLE';
  end if;
  if not v_trusted and (
    new.actual_arrival_time is distinct from old.actual_arrival_time
    or new.actual_departure_time is distinct from old.actual_departure_time
    or new.spot_status is distinct from old.spot_status) then
    raise exception 'TOUR_MILESTONE_RPC_REQUIRED';
  end if;
  return new;
end $$;
create trigger guard_booked_stay_financial_fields
before update on public.booking_itinerary_items
for each row execute function public.guard_booked_stay_financial_fields();

-- The shared included stay starts when every required convoy driver has arrived.
create or replace function public.align_convoy_stop_arrival()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_required integer; v_arrived integer; v_latest timestamptz;
begin
  if old.actual_arrival_time is not null or new.actual_arrival_time is null then return new; end if;
  select count(*) into v_required from public.required_booking_driver_roster(new.booking_id);
  select count(*),max(a.arrived_at) into v_arrived,v_latest
    from public.booking_driver_arrivals a
    join public.required_booking_driver_roster(new.booking_id) d
      on d.id=a.booking_driver_id
    where a.itinerary_item_id=new.id;
  if v_required=0 or v_arrived<v_required then
    new.actual_arrival_time := null;
  else
    new.actual_arrival_time := v_latest;
  end if;
  return new;
end $$;
create trigger align_convoy_stop_arrival
before update of actual_arrival_time on public.booking_itinerary_items
for each row execute function public.align_convoy_stop_arrival();

create or replace function public.get_municipal_tour_waiting_rate(p_municipality text,p_province text default null)
returns numeric language sql stable security definer set search_path = '' as $$
  select r.rate from public.resolve_tour_waiting_rate(p_municipality,p_province) r;
$$;
revoke all on function public.get_municipal_tour_waiting_rate(text,text) from public,anon;
grant execute on function public.get_municipal_tour_waiting_rate(text,text) to authenticated;

create or replace function public.snapshot_booking_stop_waiting_charge()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_booking public.package_bookings; v_subtenant uuid; v_rate numeric;
begin
  if new.actual_arrival_time is null or old.actual_arrival_time is not null then return new; end if;
  select * into v_booking from public.package_bookings where id = new.booking_id;
  v_subtenant := v_booking.tour_waiting_subtenant_id;
  v_rate := v_booking.tour_waiting_rate_snapshot;
  if v_rate is null then
    select r.subtenant_id,r.rate into v_subtenant,v_rate
      from public.resolve_tour_waiting_rate(v_booking.municipality,v_booking.province) r;
  end if;
  insert into public.booking_stop_waiting_charges(
    booking_id,itinerary_item_id,municipality,subtenant_id,included_minutes,
    arrived_at,paid_until,rate_per_interval)
  values (new.booking_id,new.id,v_booking.municipality,v_subtenant,
    new.estimated_stay_duration_minutes,new.actual_arrival_time,
    new.actual_arrival_time + make_interval(mins => new.estimated_stay_duration_minutes),v_rate)
  on conflict (booking_id,itinerary_item_id) do nothing;
  return new;
end $$;
create trigger snapshot_booking_stop_waiting_charge
after update of actual_arrival_time on public.booking_itinerary_items
for each row execute function public.snapshot_booking_stop_waiting_charge();

-- The trigger runs on the canonical itinerary departure write. The unique row and
-- finalized guard make repeated convoy callbacks financially idempotent.
create or replace function public.finalize_booking_stop_waiting_charge()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_charge public.booking_stop_waiting_charges; v_seconds integer; v_intervals integer;
  v_amount numeric(14,2); v_outstanding numeric; v_activity uuid;
begin
  if new.actual_departure_time is null or old.actual_departure_time is not null then return new; end if;
  select * into v_charge from public.booking_stop_waiting_charges
    where booking_id = new.booking_id and itinerary_item_id = new.id for update;
  if not found or v_charge.status = 'finalized' then return new; end if;
  v_seconds := greatest(0,ceil(extract(epoch from
    (new.actual_departure_time-v_charge.paid_until)))::integer);
  -- Existing bookings may predate the new rate snapshot. Preserve departure
  -- when no municipal rate existed at arrival; NULL records the unavailable
  -- rate and no undefined fee is assessed for this stop.
  v_intervals := ceil(v_seconds / 900.0)::integer;
  v_amount := v_intervals * coalesce(v_charge.rate_per_interval,0);
  update public.booking_stop_waiting_charges set
    departed_at = new.actual_departure_time, overtime_seconds = v_seconds,
    chargeable_intervals = v_intervals, additional_amount = v_amount,
    status = 'finalized', finalized_at = clock_timestamp(), updated_at = clock_timestamp()
  where id = v_charge.id and status = 'active';
  if v_amount > 0 then
    update public.package_bookings
      set remaining_balance = coalesce(remaining_balance,0) + v_amount,
        updated_at = clock_timestamp() where id = new.booking_id
      returning remaining_balance into v_outstanding;
    -- A satisfied requirement retains its historical stage target. Reopen the
    -- single remaining stage for NET debt, already credited by the existing
    -- confirmation workflow. Never add to the old target or subtract receipts
    -- again; confirmed payments and their allocations remain immutable.
    update public.booking_payment_requirements set amount = v_outstanding,
      status = 'required', satisfied_at = null,
      satisfied_by_payment_record_id = null, updated_at = clock_timestamp()
      where booking_id = new.booking_id and payment_stage = 'remaining_balance';
    if not found then
      insert into public.booking_payment_requirements(booking_id,payment_stage,amount)
      values (new.booking_id,'remaining_balance',v_outstanding);
    end if;
  end if;
  select id into v_activity from public.package_activities where booking_id = new.booking_id limit 1;
  insert into public.trip_status_logs(activity_id,booking_id,status,notes,logged_at)
    values(v_activity,new.booking_id,'waiting_charge_finalized',
      jsonb_build_object('itinerary_item_id',new.id,'municipality',v_charge.municipality,
        'rate',v_charge.rate_per_interval,'rate_unconfigured_at_arrival',
        v_charge.rate_per_interval is null,'intervals',v_intervals,'amount',v_amount)::text,
      clock_timestamp());
  return new;
end $$;
create trigger finalize_booking_stop_waiting_charge
after update of actual_departure_time on public.booking_itinerary_items
for each row execute function public.finalize_booking_stop_waiting_charge();

-- A later waiting obligation can require a second remaining-stage collection.
-- Keep one unresolved submission per stage; retain every confirmed receipt.
-- Downpayment/full-stage uniqueness is unchanged.
drop index public.payment_records_one_active_booking_stage_idx;
create unique index payment_records_one_active_booking_stage_idx
on public.payment_records(booking_id,payment_stage)
where booking_id is not null and status <> 'cancelled'
  and (payment_stage <> 'remaining_balance' or status <> 'confirmed');

-- Preserve the current trusted preparation workflows and all their guards,
-- splits, ownership and ACLs. Only their stage-level reuse lookup must exclude
-- historical confirmed remaining payments. Provider idempotency-key reuse
-- continues to return its original receipt, never a new collection.
do $waiting_payment_reuse$
declare v_identity text; v_definition text; v_lookup text := 'and status <> ''cancelled''';
begin
  foreach v_identity in array array[
    'public.prepare_group_cash_remaining_balance(uuid,text)',
    'public.prepare_paymongo_payment_authenticated_impl(uuid,text,text,uuid,boolean)'
  ] loop
    v_definition := pg_get_functiondef(v_identity::regprocedure);
    if (length(v_definition)-length(replace(v_definition,v_lookup,''))) / length(v_lookup) <> 1 then
      raise exception 'UNEXPECTED_WAITING_PAYMENT_REUSE_CONTRACT: %',v_identity;
    end if;
    execute replace(v_definition,v_lookup,
      v_lookup || ' and (payment_stage <> ''remaining_balance'' or status <> ''confirmed'')');
  end loop;
  -- A second paid event for an already confirmed remaining receipt must never
  -- satisfy a later waiting requirement (even when the amounts happen to match).
  -- Keep provider event deduplication and mode/reference checks intact; record
  -- this additional event without rewriting receipts or their allocations.
  v_identity := 'public.process_paymongo_webhook_event(text,text,boolean,text,text,text,text,text,bigint,bigint,bigint,jsonb)';
  v_definition := pg_get_functiondef(v_identity::regprocedure);
  v_lookup := '  if v_is_failed then';
  if (length(v_definition)-length(replace(v_definition,v_lookup,''))) / length(v_lookup) <> 1 then
    raise exception 'UNEXPECTED_WAITING_WEBHOOK_CONTRACT';
  end if;
  execute replace(v_definition,v_lookup,$webhook_guard$
  if v_is_paid and v_payment.payment_stage = 'remaining_balance'
     and v_payment.status = 'confirmed' then
    update public.payment_provider_events set processing_status = 'ignored',
      process_error = 'REMAINING_PAYMENT_ALREADY_CONFIRMED', processed_at = now()
    where id = v_event_id;
    return jsonb_build_object('ok',true,'duplicate',true,'confirmed',true);
  end if;
  if v_is_failed then$webhook_guard$);
end $waiting_payment_reuse$;

create or replace function public.refresh_active_tour_waiting()
returns integer language plpgsql security definer set search_path = '' as $$
declare c public.booking_stop_waiting_charges; v_now timestamptz := clock_timestamp();
  v_seconds integer; v_intervals integer; v_count integer := 0; v_user uuid;
begin
  for c in select charge.* from public.booking_stop_waiting_charges charge
    join public.package_bookings b on b.id=charge.booking_id
    where charge.status = 'active'
      and lower(coalesce(b.booking_status,b.status,'')) not in ('cancelled','rejected','expired','completed','done')
      and charge.paid_until <= v_now + interval '15 minutes'
    for update skip locked loop
    for v_user in select b.tourist_id from public.package_bookings b where b.id = c.booking_id
      union select d.driver_id from public.booking_drivers d
        where d.booking_id = c.booking_id and d.status = 'accepted' loop
      if v_now >= c.paid_until - interval '15 minutes' and v_now < c.paid_until - interval '5 minutes' then
        perform public.emit_tour_notification(v_user,c.booking_id,
          'stay:15:'||c.itinerary_item_id,'paid_stay_ending','Paid stay ending soon',
          'Included waiting at '||(select destination_name from public.booking_itinerary_items where id=c.itinerary_item_id)||
          ' ends at '||to_char(c.paid_until at time zone 'Asia/Manila','HH12:MI AM')||
          case when c.rate_per_interval is null
            then '. No additional fee will be assessed for this stop because the municipality rate was not configured at arrival.'
            else '. Additional waiting charges apply after that.' end,true);
      end if;
      if v_now >= c.paid_until - interval '5 minutes' and v_now < c.paid_until then
        perform public.emit_tour_notification(v_user,c.booking_id,
          'stay:5:'||c.itinerary_item_id,'paid_stay_ending','Paid stay ending soon',
          'Included waiting at '||(select destination_name from public.booking_itinerary_items where id=c.itinerary_item_id)||
          ' ends at '||to_char(c.paid_until at time zone 'Asia/Manila','HH12:MI AM')||
          case when c.rate_per_interval is null
            then '. No additional fee will be assessed for this stop because the municipality rate was not configured at arrival.'
            else '. Additional waiting charges apply after that.' end,true);
      end if;
      if v_now >= c.paid_until then
        perform public.emit_tour_notification(v_user,c.booking_id,
          'stay:overtime:'||c.itinerary_item_id,'additional_waiting',
          case when c.rate_per_interval is null then 'Included stay ended' else 'Additional waiting' end,
          'Included waiting has ended at '||(select destination_name from public.booking_itinerary_items where id=c.itinerary_item_id)||
          case when c.rate_per_interval is null
            then '. No additional fee will be assessed for this stop because the municipality rate was not configured at arrival.'
            else '. Additional waiting charges now apply.' end,true);
      end if;
    end loop;
    v_seconds := greatest(0,ceil(extract(epoch from v_now-c.paid_until))::integer);
    v_intervals := ceil(v_seconds / 900.0)::integer;
    if v_intervals <> c.chargeable_intervals then
      update public.booking_stop_waiting_charges set overtime_seconds = v_seconds,
        chargeable_intervals = v_intervals,
        additional_amount = v_intervals * coalesce(c.rate_per_interval,0),
        updated_at = v_now where id = c.id and status = 'active';
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end $$;
revoke all on function public.refresh_active_tour_waiting() from public, anon, authenticated;
do $$ begin
  if to_regnamespace('cron') is not null then
    perform cron.schedule('touristrike-waiting-notices','* * * * *',
      'select public.refresh_active_tour_waiting()');
  end if;
end $$;

create table public.tourist_reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.package_bookings(id) on delete cascade,
  driver_id uuid not null references public.profiles(id) on delete cascade,
  tourist_id uuid not null references public.profiles(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  review_text text check (char_length(review_text) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (booking_id,driver_id,tourist_id)
);
create index tourist_reviews_tourist_idx on public.tourist_reviews(tourist_id);
create index tourist_reviews_booking_idx on public.tourist_reviews(booking_id);
alter table public.tourist_reviews enable row level security;
revoke all on public.tourist_reviews from public, anon, authenticated;
grant select on public.tourist_reviews to authenticated;
create policy tourist_reviews_operational_read on public.tourist_reviews
for select to authenticated using (
  driver_id = auth.uid() or tourist_id = auth.uid()
  or public.can_read_tour_booking(tourist_reviews.booking_id)
);

create or replace function public.submit_tourist_review(
  p_booking_id uuid,p_rating smallint,p_review_text text default null)
returns public.tourist_reviews language plpgsql security definer set search_path = '' as $$
declare v_booking public.package_bookings; v_review public.tourist_reviews;
begin
  if auth.uid() is null or public.current_profile_role() is distinct from 'driver' then
    raise exception 'DRIVER_ROLE_REQUIRED'; end if;
  if p_rating not between 1 and 5 then raise exception 'INVALID_RATING'; end if;
  if char_length(coalesce(p_review_text,'')) > 2000 then raise exception 'REVIEW_TOO_LONG'; end if;
  select * into v_booking from public.package_bookings where id = p_booking_id;
  if not found or lower(coalesce(v_booking.booking_status,v_booking.status,'')) <> 'completed' then
    raise exception 'COMPLETED_BOOKING_REQUIRED'; end if;
  if v_booking.tourist_id = auth.uid() or not exists (
    select 1 from public.booking_drivers d where d.booking_id = p_booking_id
      and d.driver_id = auth.uid() and d.status = 'completed') then
    raise exception 'NOT_COMPLETED_BOOKING_DRIVER'; end if;
  insert into public.tourist_reviews(booking_id,driver_id,tourist_id,rating,review_text)
  values(p_booking_id,auth.uid(),v_booking.tourist_id,p_rating,nullif(trim(p_review_text),''))
  returning * into v_review;
  return v_review;
end $$;
revoke all on function public.submit_tourist_review(uuid,smallint,text) from public,anon;
grant execute on function public.submit_tourist_review(uuid,smallint,text) to authenticated;

create or replace function public.get_tourist_rating_summary(p_tourist_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('average_rating',coalesce(round(avg(r.rating),2),0),
    'total_reviews',count(*)) from public.tourist_reviews r where r.tourist_id=p_tourist_id
    and (auth.uid()=p_tourist_id or exists(select 1 from public.booking_drivers d
      join public.package_bookings b on b.id=d.booking_id
      where d.driver_id=auth.uid() and d.status in ('accepted','completed')
        and public.current_profile_role()='driver' and b.tourist_id=p_tourist_id));
$$;
revoke all on function public.get_tourist_rating_summary(uuid) from public,anon;
grant execute on function public.get_tourist_rating_summary(uuid) to authenticated;

create or replace function public.get_booking_waiting_summary(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare b public.package_bookings; v_rate numeric; v_subtenant uuid;
  v_finalized numeric; v_accrued numeric; v_now timestamptz := clock_timestamp();
begin
  select * into b from public.package_bookings where id=p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if not public.can_read_tour_booking(b.id) then
    raise exception 'BOOKING_ACCESS_DENIED'; end if;
  v_subtenant := b.tour_waiting_subtenant_id;
  v_rate := b.tour_waiting_rate_snapshot;
  if v_rate is null then
    select r.subtenant_id,r.rate into v_subtenant,v_rate
      from public.resolve_tour_waiting_rate(b.municipality,b.province) r;
  end if;
  select coalesce(sum(additional_amount) filter(where status='finalized'),0),
    coalesce(sum(additional_amount) filter(where status='active'),0)
    into v_finalized,v_accrued from public.booking_stop_waiting_charges
    where booking_id=b.id;
  return jsonb_build_object('booking_id',b.id,'municipality',b.municipality,
    'subtenant_id',v_subtenant,'current_rate_per_15_minutes',v_rate,
    'server_time',v_now,
    'package_remaining',greatest(0,coalesce(b.remaining_balance,0)-v_finalized),
    'finalized_waiting',v_finalized,'accrued_waiting',v_accrued,
    'total_remaining',greatest(0,coalesce(b.remaining_balance,0))+v_accrued,
    'charges',coalesce((select jsonb_agg(jsonb_build_object(
      'itinerary_item_id',c.itinerary_item_id,'destination_name',i.destination_name,
      'arrived_at',c.arrived_at,'paid_until',c.paid_until,'departed_at',c.departed_at,
      'included_minutes',c.included_minutes,'rate_per_interval',c.rate_per_interval,
      'overtime_seconds',c.overtime_seconds,'chargeable_intervals',c.chargeable_intervals,
      'additional_amount',c.additional_amount,'status',c.status)
      order by c.arrived_at) from public.booking_stop_waiting_charges c
      join public.booking_itinerary_items i on i.id=c.itinerary_item_id
      where c.booking_id=b.id),'[]'::jsonb));
end $$;
revoke all on function public.get_booking_waiting_summary(uuid) from public,anon;
grant execute on function public.get_booking_waiting_summary(uuid) to authenticated;

create or replace function public.get_tour_operations_report(
  p_start timestamptz,p_end timestamptz,p_city text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_role text := public.current_profile_role(); v_city text; v_province text;
  v_completed integer; v_affected integer; v_minutes numeric; v_intervals integer;
  v_amount numeric; v_collected numeric; v_reviewed integer; v_review_count integer; v_rating numeric;
  v_distribution jsonb; v_destinations jsonb; v_municipalities jsonb;
begin
  if auth.uid() is null or p_start is null or p_end is null or p_end <= p_start
    or p_end > p_start + interval '5 years' then raise exception 'INVALID_REPORT_RANGE'; end if;
  if v_role='subtenant' then
    v_city := public.current_subtenant_city();
    if v_city is null then raise exception 'SUBTENANT_CITY_REQUIRED'; end if;
    select province into v_province from public.subtenant_details
      where id=auth.uid() and is_active;
    if nullif(trim(v_province),'') is null then raise exception 'PROVINCE_REQUIRED'; end if;
    if p_city is not null and not public.cities_match(p_city,v_city) then
      raise exception 'REPORT_CITY_ACCESS_DENIED'; end if;
  elsif v_role in ('main_tenant','admin') then
    select province into v_province from public.profiles where id=auth.uid();
    if nullif(trim(v_province),'') is null then raise exception 'PROVINCE_REQUIRED'; end if;
    v_city := nullif(trim(p_city),'');
  else
    raise exception 'REPORT_ACCESS_DENIED';
  end if;

  select count(*) into v_completed from public.package_bookings b
  where (v_city is null or public.cities_match(b.municipality,v_city))
    and (v_province is null or public.cities_match(b.province,v_province))
    and lower(coalesce(b.booking_status,b.status,''))='completed'
    and b.completed_at >= p_start and b.completed_at < p_end;

  select count(distinct c.booking_id),
    coalesce(sum(c.overtime_seconds),0)/60.0,
    coalesce(sum(c.chargeable_intervals),0),
    coalesce(sum(c.additional_amount),0)
    into v_affected,v_minutes,v_intervals,v_amount
  from public.booking_stop_waiting_charges c
  join public.package_bookings b on b.id=c.booking_id
  where c.status='finalized' and c.overtime_seconds>0
    and c.finalized_at>=p_start and c.finalized_at<p_end
    and (v_city is null or public.cities_match(b.municipality,v_city))
    and (v_province is null or public.cities_match(b.province,v_province));

  select count(distinct r.tourist_id),count(*),coalesce(round(avg(r.rating),2),0)
    into v_reviewed,v_review_count,v_rating
  from public.tourist_reviews r join public.package_bookings b on b.id=r.booking_id
  where r.created_at>=p_start and r.created_at<p_end
    and (v_city is null or public.cities_match(b.municipality,v_city))
    and (v_province is null or public.cities_match(b.province,v_province));

  select coalesce(sum(pr.amount),0) into v_collected
  from public.payment_records pr join public.package_bookings b on b.id=pr.booking_id
  where pr.status='confirmed'
    and coalesce(pr.paid_at,pr.created_at)>=p_start
    and coalesce(pr.paid_at,pr.created_at)<p_end
    and (v_city is null or public.cities_match(b.municipality,v_city))
    and (v_province is null or public.cities_match(b.province,v_province));

  select coalesce(jsonb_object_agg(star,n), '{}'::jsonb) into v_distribution
  from (select s.star,count(r.id) as n from generate_series(1,5) s(star)
    left join public.tourist_reviews r on r.rating=s.star and r.created_at>=p_start and r.created_at<p_end
      and exists(select 1 from public.package_bookings b where b.id=r.booking_id
        and (v_city is null or public.cities_match(b.municipality,v_city))
        and (v_province is null or public.cities_match(b.province,v_province)))
    group by s.star) x;

  select coalesce(jsonb_agg(jsonb_build_object('destination',destination_name,
    'overtime_minutes',minutes,'additional_amount',amount)
    order by amount desc),'[]'::jsonb) into v_destinations
  from (select i.destination_name,
      round(sum(c.overtime_seconds)/60.0,1) as minutes,
      sum(c.additional_amount) as amount
    from public.booking_stop_waiting_charges c
    join public.booking_itinerary_items i on i.id=c.itinerary_item_id
    join public.package_bookings b on b.id=c.booking_id
    where c.status='finalized' and c.overtime_seconds>0
      and c.finalized_at>=p_start and c.finalized_at<p_end
      and (v_city is null or public.cities_match(b.municipality,v_city))
      and (v_province is null or public.cities_match(b.province,v_province))
    group by i.destination_name order by amount desc limit 10) x;

  select coalesce(jsonb_agg(jsonb_build_object('municipality',municipality,
    'affected_bookings',bookings,'overtime_minutes',minutes,
    'intervals',intervals,'additional_amount',amount)
    order by amount desc),'[]'::jsonb) into v_municipalities
  from (select b.municipality,count(distinct c.booking_id) as bookings,
      round(sum(c.overtime_seconds)/60.0,1) as minutes,
      sum(c.chargeable_intervals) as intervals,
      sum(c.additional_amount) as amount
    from public.booking_stop_waiting_charges c
    join public.package_bookings b on b.id=c.booking_id
    where c.status='finalized' and c.overtime_seconds>0
      and c.finalized_at>=p_start and c.finalized_at<p_end
      and (v_city is null or public.cities_match(b.municipality,v_city))
      and (v_province is null or public.cities_match(b.province,v_province))
    group by b.municipality order by amount desc) x;

  return jsonb_build_object('completed_tours',v_completed,
    'tours_with_overtime',v_affected,'total_overtime_minutes',round(v_minutes,1),
    'chargeable_intervals',v_intervals,'additional_waiting_fees',v_amount,
    'confirmed_collections',v_collected,
    'average_overtime_per_affected_tour',case when v_affected>0
      then round(v_minutes/v_affected,1) else 0 end,
    'tourists_reviewed',v_reviewed,'tourist_reviews',v_review_count,
    'average_tourist_rating',v_rating,'rating_distribution',v_distribution,
    'destinations',v_destinations,'municipalities',v_municipalities);
end $$;
revoke all on function public.get_tour_operations_report(timestamptz,timestamptz,text)
  from public,anon;
grant execute on function public.get_tour_operations_report(timestamptz,timestamptz,text)
  to authenticated;

do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
    and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
      and schemaname='public' and tablename='booking_stop_waiting_charges') then
    alter publication supabase_realtime add table public.booking_stop_waiting_charges;
  end if;
end $$;

create or replace function public.observe_driver_journey_location(
  p_booking_id uuid, p_latitude double precision, p_longitude double precision,
  p_accuracy_meters double precision, p_speed_mps double precision, p_sampled_at timestamptz
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  b public.package_bookings; d public.booking_drivers; e public.driver_journey_evidence;
  v_activity uuid; v_item uuid; v_lat double precision; v_lng double precision;
  v_distance double precision; v_phase text; v_qualifies boolean; v_transition boolean := false;
  v_arriving boolean; v_target text; v_count integer; v_required_seconds integer;
  v_now timestamptz := clock_timestamp(); v_error text; v_evidence jsonb;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  select * into b from public.package_bookings where id=p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  select * into d from public.booking_drivers where booking_id=b.id and driver_id=auth.uid()
    and status in ('accepted','completed') for update;
  if not found or public.current_profile_role() is distinct from 'driver' then
    raise exception 'NOT_ASSIGNED_DRIVER';
  end if;
  if lower(coalesce(b.booking_status,b.status,'')) in ('cancelled','rejected','expired','completed','done')
     or d.journey_state in ('assigned','completed') then
    return jsonb_build_object('changed',false,'phase',d.journey_state);
  end if;
  insert into public.driver_journey_evidence(booking_driver_id,expected_state,stop_index)
    values(d.id,d.journey_state,d.current_stop_index) on conflict do nothing;
  select * into e from public.driver_journey_evidence where booking_driver_id=d.id for update;
  -- Explicit ranges reject infinities and NaN as well as absent/stale fixes.
  if p_latitude is null or not (p_latitude between -90 and 90)
    or p_longitude is null or not (p_longitude between -180 and 180)
    or p_accuracy_meters is null or not (p_accuracy_meters between 0 and 50)
    or p_speed_mps is null or not (p_speed_mps between 0 and 80)
    or p_sampled_at is null or p_sampled_at < v_now-interval '20 seconds'
    or p_sampled_at > v_now+interval '2 seconds' then
    update public.driver_journey_evidence set sample_count=0,first_sample_at=null,
      first_received_at=null,phase='gps_interrupted' where booking_driver_id=d.id;
    return jsonb_build_object('changed',false,'phase','gps_interrupted');
  end if;
  if p_sampled_at <= e.last_sample_at then
    return jsonb_build_object('changed',false,'phase',e.phase,'duplicate',true);
  end if;
  if e.expected_state <> d.journey_state or e.stop_index <> d.current_stop_index
     or v_now-e.last_received_at > interval '20 seconds'
     or p_sampled_at-e.last_sample_at > interval '20 seconds' then
    e.sample_count := 0; e.first_sample_at := null; e.first_received_at := null;
  end if;
  select id into v_activity from public.package_activities where booking_id=b.id limit 1;
  if v_activity is null then raise exception 'ACTIVITY_NOT_FOUND'; end if;
  if d.journey_state in ('en_route_pickup','at_pickup','boarded') then
    v_lat := b.pickup_latitude; v_lng := b.pickup_longitude;
  elsif d.journey_state in ('en_route_dropoff','at_dropoff') then
    v_lat := b.dropoff_latitude; v_lng := b.dropoff_longitude;
  else
    select id,latitude,longitude into v_item,v_lat,v_lng from public.booking_itinerary_items
    where booking_id=b.id order by coalesce(order_number,2147483647),
      coalesce(destination_order,2147483647),arrival_time nulls last,created_at,id
    offset d.current_stop_index limit 1;
  end if;
  if v_lat is null or v_lng is null then raise exception 'TARGET_LOCATION_REQUIRED'; end if;
  v_distance := 6371000*2*asin(sqrt(least(1,greatest(0,
    power(sin(radians(p_latitude-v_lat)/2),2)+cos(radians(v_lat))*cos(radians(p_latitude))
      *power(sin(radians(p_longitude-v_lng)/2),2)))));
  v_arriving := d.journey_state in ('en_route_pickup','en_route_stop','en_route_dropoff','at_dropoff');
  v_qualifies := case when v_arriving then
    v_distance+p_accuracy_meters <= public.driver_arrival_radius_meters() and p_speed_mps <= 2
    else v_distance-p_accuracy_meters >= public.driver_arrival_radius_meters()+100 and p_speed_mps >= 1 end;
  v_required_seconds := case when v_arriving then 15 else 12 end;
  if v_qualifies then
    e.sample_count := e.sample_count+1;
    e.first_sample_at := coalesce(e.first_sample_at,p_sampled_at);
    e.first_received_at := coalesce(e.first_received_at,v_now);
  else
    e.sample_count := 0; e.first_sample_at := null; e.first_received_at := null;
  end if;
  v_phase := case when v_arriving then case when v_qualifies then 'detecting_arrival' else 'navigating' end
    else case when v_qualifies then 'detecting_departure' else 'stop_in_progress' end end;
  update public.driver_journey_evidence set expected_state=d.journey_state,stop_index=d.current_stop_index,
    sample_count=e.sample_count,first_sample_at=e.first_sample_at,first_received_at=e.first_received_at,
    last_sample_at=p_sampled_at,last_received_at=v_now,latitude=p_latitude,longitude=p_longitude,
    accuracy_meters=p_accuracy_meters,speed_mps=p_speed_mps,phase=v_phase,blocked_reason=null
  where booking_driver_id=d.id;
  insert into public.driver_live_locations(driver_id,activity_id,latitude,longitude,speed,updated_at)
  values(d.driver_id,v_activity,p_latitude,p_longitude,p_speed_mps,v_now)
  on conflict(driver_id) do update set activity_id=excluded.activity_id,latitude=excluded.latitude,
    longitude=excluded.longitude,speed=excluded.speed,updated_at=excluded.updated_at;
  perform public.reconcile_stale_tour_tracking(b.id);
  -- Arrival stays GPS verified; departure and completion require an explicit slide.
  if d.journey_state in ('at_pickup','at_stop','at_dropoff') then
    update public.driver_journey_evidence set phase='arrived',sample_count=0,
      first_sample_at=null,first_received_at=null where booking_driver_id=d.id;
    return jsonb_build_object('changed',false,'phase','arrived',
      'journey_state',d.journey_state,'current_stop_index',d.current_stop_index);
  end if;

  v_evidence := jsonb_build_object('sample_count',e.sample_count,'first_sample_at',e.first_sample_at,
    'sampled_at',p_sampled_at,'received_at',v_now,'latitude',p_latitude,'longitude',p_longitude,
    'accuracy_meters',p_accuracy_meters,'speed_mps',p_speed_mps,'distance_meters',round(v_distance::numeric,1));
  if e.sample_count >= 4 and p_sampled_at-e.first_sample_at >= make_interval(secs=>v_required_seconds)
      and v_now-e.first_received_at >= make_interval(secs=>v_required_seconds) then
    perform set_config('touristrike.gps_transition_verified','true',true);
    if v_arriving then
      v_target := case d.journey_state when 'en_route_pickup' then 'at_pickup'
        when 'en_route_stop' then 'at_stop' when 'en_route_dropoff' then 'at_dropoff' else 'completed' end;
      begin
        perform public.advance_driver_journey_state(b.id,v_target);
        v_phase := case when v_target='completed' then 'completed' else 'arrived' end;
        v_transition := true;
      exception when raise_exception then
        get stacked diagnostics v_error = message_text;
        if v_target <> 'completed' or v_error not like '%REMAINING_BALANCE%' then raise; end if;
        v_phase := 'completion_pending';
      end;
    end if;
    perform set_config('touristrike.gps_transition_verified','false',true);
  end if;
  if v_transition then
    insert into public.trip_status_logs(activity_id,booking_id,driver_id,status,previous_state,new_state,spot_index,notes)
    select v_activity,b.id,d.driver_id,'gps_'||v_phase,d.journey_state,journey_state,d.current_stop_index,v_evidence::text
    from public.booking_drivers where id=d.id;
    update public.driver_journey_evidence set sample_count=0,first_sample_at=null,first_received_at=null
    where booking_driver_id=d.id;
  end if;
  -- Navigation and final completion now wait for a driver slide.
  update public.driver_journey_evidence set phase=v_phase,blocked_reason=v_error where booking_driver_id=d.id;
  return jsonb_build_object('changed',v_transition,'phase',v_phase,'blocked_reason',v_error,
    'interrupted_at',(select tracking_interrupted_at from public.package_bookings where id=b.id),
    'journey_state',(select journey_state from public.booking_drivers where id=d.id),
    'current_stop_index',(select current_stop_index from public.booking_drivers where id=d.id));
end;
$$;

create or replace function public.complete_current_itinerary_item(
  p_activity_id uuid,
  p_itinerary_item_id uuid,
  p_remaining_payment_method text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver_id uuid := auth.uid();
  v_activity public.package_activities;
  v_booking public.package_bookings;
  v_assignment public.booking_drivers;
  v_item public.booking_itinerary_items;
  v_item_index integer;
  v_total_items integer := 0;
  v_completed_items integer := 0;
  v_stage_progress jsonb;
  v_latest_arrival timestamptz;
  v_is_test_booking boolean := false;
  v_remaining_payment_satisfied boolean := false;
  v_spot_status_list jsonb := '[]'::jsonb;
begin
  if v_driver_id is null then raise exception 'UNAUTHENTICATED'; end if;

  select * into v_activity
  from public.package_activities
  where id = p_activity_id;
  if not found then raise exception 'ACTIVITY_NOT_FOUND'; end if;

  select * into v_booking
  from public.package_bookings
  where id = v_activity.booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  v_is_test_booking := public.is_developer_test_booking(v_booking.id);
  if lower(coalesce(v_booking.booking_status, v_booking.status)) in ('cancelled', 'rejected', 'expired') then
    raise exception 'BOOKING_CLOSED';
  end if;

  select * into v_assignment
  from public.booking_drivers bd
  where bd.booking_id = v_booking.id
    and bd.driver_id = v_driver_id
    and bd.status in ('accepted', 'completed')
  for update;
  if not found then raise exception 'NOT_ASSIGNED_DRIVER'; end if;

  if p_itinerary_item_id is null then
    select item.* into v_item
    from public.booking_itinerary_items item
    where item.booking_id = v_booking.id
      and lower(coalesce(item.spot_status, 'pending')) <> 'completed'
    order by coalesce(item.order_number, 2147483647),
             coalesce(item.destination_order, 2147483647),
             item.arrival_time nulls last, item.created_at, item.id
    limit 1
    for update;
  else
    select item.* into v_item
    from public.booking_itinerary_items item
    where item.id = p_itinerary_item_id
      and item.booking_id = v_booking.id
    for update;
  end if;
  if not found then raise exception 'ITINERARY_ITEM_NOT_FOUND'; end if;

  select ordered.item_index into v_item_index
  from (
    select bii.id,
           (row_number() over (
             order by coalesce(bii.order_number, 2147483647),
                      coalesce(bii.destination_order, 2147483647),
                      bii.arrival_time nulls last, bii.created_at, bii.id
           ))::integer - 1 as item_index
    from public.booking_itinerary_items bii
    where bii.booking_id = v_booking.id
  ) ordered
  where ordered.id = v_item.id;

  select count(*) into v_total_items
  from public.booking_itinerary_items
  where booking_id = v_booking.id;

  if lower(coalesce(v_item.spot_status, 'pending')) = 'completed' then
    select count(*) into v_completed_items
    from public.booking_itinerary_items
    where booking_id = v_booking.id
      and lower(coalesce(spot_status, 'pending')) = 'completed';

    return jsonb_build_object(
      'success', true,
      'already_completed', true,
      'booking_id', v_booking.id,
      'activity_id', v_activity.id,
      'current_itinerary_item_id', v_item.id,
      'current_spot_index', v_item_index,
      'completed_items', v_completed_items,
      'total_items', v_total_items,
      'tour_completed', v_completed_items = v_total_items,
      'convoy_progress', public.compute_convoy_stage_progress(
        v_booking.id, 'stop_done', v_item_index
      )
    );
  end if;

  if v_assignment.journey_state = 'stop_done' and v_assignment.current_stop_index = v_item_index then
    return jsonb_build_object('success', true, 'driver_ready', true, 'already_completed', false);
  end if;
  if v_assignment.journey_state <> 'at_stop' then
    raise exception 'INVALID_TRANSITION: % -> stop_done', v_assignment.journey_state;
  end if;

  if v_assignment.current_stop_index <> v_item_index then
    raise exception 'STALE_ITINERARY_STOP';
  end if;

  select arrived_at into v_latest_arrival from public.booking_driver_arrivals
  where booking_driver_id = v_assignment.id and itinerary_item_id = v_item.id;
  if v_latest_arrival is null then raise exception 'DRIVER_ARRIVAL_NOT_RECORDED'; end if;

  -- Booked stay is included time, not a minimum visit duration.
  -- Each driver's ready confirmation changes only that assignment.
  update public.booking_drivers set journey_state = 'stop_done', state_updated_at = now()
  where id = v_assignment.id;
  insert into public.trip_status_logs(activity_id, booking_id, driver_id, status,
    previous_state, new_state, spot_index, logged_at, notes)
  values (v_activity.id, v_booking.id, v_driver_id, 'on_tour', 'at_stop', 'stop_done',
    v_item_index, now(), case when current_setting('touristrike.gps_transition_verified', true) = 'true' then 'GPS verified departure after confirmed arrival' else 'Audited driver recovery after actual stay' end);
  v_stage_progress := public.compute_convoy_stage_progress(v_booking.id, 'stop_done', v_item_index);
  if not coalesce((v_stage_progress->>'all_satisfied')::boolean, false) then
    return jsonb_build_object('success', true, 'driver_ready', true, 'already_completed', false,
      'convoy_progress', v_stage_progress, 'total_items', v_total_items);
  end if;
  -- The shared stop is complete only after every required driver is ready.
  update public.booking_itinerary_items set spot_status = 'completed', updated_at = now()
  where id = v_item.id;

  select count(*) into v_completed_items
  from public.booking_itinerary_items
  where booking_id = v_booking.id
    and lower(coalesce(spot_status, 'pending')) = 'completed';

  v_remaining_payment_satisfied :=
    public.is_booking_remaining_payment_satisfied(v_booking.id);

  perform set_config('touristrike.validated_transition', 'true', true);
  update public.package_activities
  set status = 'ongoing',
      tour_status = case
        when v_completed_items = v_total_items
             and not v_remaining_payment_satisfied
          then 'awaiting_remaining_payment'
        else 'on_tour'
      end,
      current_spot_index = v_item_index, updated_at = now()
  where id = v_activity.id;
  update public.package_bookings
  set booking_status = case
        when v_completed_items = v_total_items
             and not v_remaining_payment_satisfied
          then 'awaiting_remaining_payment'
        else 'on_tour'
      end,
      current_spot_index = v_item_index,
      updated_at = now()
  where id = v_booking.id;

  select coalesce(jsonb_agg(
    jsonb_build_object('id', id, 'order_number', order_number,
      'destination_order', destination_order, 'spot_status', spot_status)
    order by coalesce(order_number, 2147483647),
      coalesce(destination_order, 2147483647), arrival_time nulls last,
      created_at, id
  ), '[]'::jsonb)
  into v_spot_status_list
  from public.booking_itinerary_items
  where booking_id = v_booking.id;

  return jsonb_build_object(
    'success', true,
    'already_completed', false,
    'booking_id', v_booking.id,
    'activity_id', v_activity.id,
    'current_itinerary_item_id', v_item.id,
    'current_spot_index', v_item_index,
    'completed_items', v_completed_items,
    'total_items', v_total_items,
    'tour_completed', v_completed_items = v_total_items,
    'awaiting_remaining_payment', v_completed_items = v_total_items
      and not v_remaining_payment_satisfied,
    'convoy_state', 'stop_done',
    'convoy_progress', public.compute_convoy_stage_progress(
      v_booking.id, 'stop_done', v_item_index
    ),
    'spot_status_list', v_spot_status_list
  );
end;
$$;

-- A slide authorizes only departures and explicit pickup/completion actions.
-- Physical arrivals still require the existing GPS verification or audited recovery.
create or replace function public.guard_verified_journey_transition()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_slide boolean := coalesce(current_setting('touristrike.driver_slide',true),'')='true';
begin
  if (new.journey_state is distinct from old.journey_state or new.current_stop_index is distinct from old.current_stop_index)
    and coalesce(current_setting('touristrike.gps_transition_verified',true),'') <> 'true'
    and coalesce(current_setting('touristrike.journey_rpc',true),'') <> 'true'
    and not v_slide
    and length(coalesce(current_setting('touristrike.manual_lifecycle_reason',true),'')) < 10 then
    raise exception 'JOURNEY_RPC_REQUIRED';
  end if;
  if new.journey_state is not distinct from old.journey_state then return new; end if;
  if new.journey_state in ('at_pickup','at_stop','at_dropoff')
    and coalesce(current_setting('touristrike.gps_transition_verified',true),'') <> 'true'
    and length(coalesce(current_setting('touristrike.manual_lifecycle_reason',true),'')) < 10 then
    raise exception 'VERIFIED_GPS_OR_AUDITED_RECOVERY_REQUIRED';
  end if;
  if new.journey_state in ('boarded','stop_done','completed')
    and not v_slide
    and coalesce(current_setting('touristrike.gps_transition_verified',true),'') <> 'true'
    and length(coalesce(current_setting('touristrike.manual_lifecycle_reason',true),'')) < 10 then
    raise exception 'DRIVER_SLIDE_REQUIRED';
  end if;
  return new;
end $$;

create or replace function public.advance_driver_tour_action(
  p_booking_id uuid,p_expected_state text,p_stop_index integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d public.booking_drivers; v_activity uuid; v_item uuid;
  v_count integer; v_result jsonb; v_target text;
begin
  if auth.uid() is null or public.current_profile_role() is distinct from 'driver' then
    raise exception 'DRIVER_ROLE_REQUIRED'; end if;
  perform 1 from public.package_bookings where id=p_booking_id for update;
  select * into d from public.booking_drivers where booking_id=p_booking_id
    and driver_id=auth.uid() and status in ('accepted','completed') for update;
  if not found then raise exception 'NOT_ASSIGNED_DRIVER'; end if;
  if d.journey_state is distinct from p_expected_state or d.current_stop_index is distinct from p_stop_index then
    return jsonb_build_object('no_op',true,'journey_state',d.journey_state,
      'current_stop_index',d.current_stop_index);
  end if;
  select id into v_activity from public.package_activities where booking_id=p_booking_id limit 1;
  perform set_config('touristrike.driver_slide','true',true);
  if d.journey_state='at_pickup' then
    v_result := public.advance_driver_journey_state(p_booking_id,'boarded');
  elsif d.journey_state='boarded' then
    select count(*) into v_count from public.booking_itinerary_items where booking_id=p_booking_id;
    v_result := public.advance_driver_journey_state(p_booking_id,
      case when v_count>0 then 'en_route_stop' else 'en_route_dropoff' end);
  elsif d.journey_state in ('at_stop','stop_done') then
    select id into v_item from public.booking_itinerary_items where booking_id=p_booking_id
      order by coalesce(order_number,2147483647),coalesce(destination_order,2147483647),
        arrival_time nulls last,created_at,id offset d.current_stop_index limit 1;
    if v_item is null then raise exception 'ITINERARY_ITEM_NOT_FOUND'; end if;
    if d.journey_state='at_stop' then
      v_result := public.complete_current_itinerary_item(v_activity,v_item,null);
    end if;
    update public.booking_driver_arrivals
      set departed_at=coalesce(departed_at,clock_timestamp())
      where booking_driver_id=d.id and itinerary_item_id=v_item;
    -- Finalize the shared stop when every required driver has slid. This must
    -- precede the remaining-payment gate on the final navigation leg.
    update public.booking_itinerary_items i
      set actual_departure_time=(select max(a.departed_at)
        from public.booking_driver_arrivals a where a.itinerary_item_id=v_item)
      where i.id=v_item and i.spot_status='completed'
        and i.actual_departure_time is null;
    select journey_state into d.journey_state from public.booking_drivers where id=d.id;
    if d.journey_state='stop_done' then
      select count(*) into v_count from public.booking_itinerary_items where booking_id=p_booking_id;
      v_target := case when d.current_stop_index+1<v_count then 'en_route_stop'
        else 'en_route_dropoff' end;
      begin
        v_result := public.advance_driver_journey_state(p_booking_id,v_target);
      exception when raise_exception then
        if sqlerrm like '%BARRIER_NOT_MET%' or sqlerrm like '%REMAINING_BALANCE_NOT_CONFIRMED%' then
          return jsonb_build_object('success',true,'waiting_for_convoy_or_payment',true,
            'journey_state','stop_done','current_stop_index',d.current_stop_index);
        end if;
        raise;
      end;
    end if;
  elsif d.journey_state='at_dropoff' then
    v_result := public.advance_driver_journey_state(p_booking_id,'completed');
  else
    raise exception 'SLIDE_NOT_AVAILABLE_IN_STATE: %',d.journey_state;
  end if;
  return v_result;
end $$;
revoke all on function public.advance_driver_tour_action(uuid,text,integer) from public,anon;
grant execute on function public.advance_driver_tour_action(uuid,text,integer) to authenticated;


-- Explicit execution boundaries for this feature's definers, including the
-- existing completion overload which delegates to the replaced implementation.
do $feature_grants$
declare f record;
begin
 for f in select p.oid::regprocedure as signature,p.proname
   from pg_proc p where p.pronamespace='public'::regnamespace
     and p.proname in ('guard_municipal_tour_waiting_rate','main_tenant_can_read_booking','can_read_tour_booking','resolve_tour_waiting_rate','snapshot_booking_tour_waiting_rate','guard_booking_tour_waiting_snapshot','guard_booked_stay_financial_fields','align_convoy_stop_arrival','get_municipal_tour_waiting_rate','snapshot_booking_stop_waiting_charge','finalize_booking_stop_waiting_charge','refresh_active_tour_waiting','submit_tourist_review','get_tourist_rating_summary','get_booking_waiting_summary','get_tour_operations_report','observe_driver_journey_location','complete_current_itinerary_item','guard_verified_journey_transition','advance_driver_tour_action') loop
   execute format('revoke all on function %s from public, anon, authenticated',f.signature);
   if f.proname in ('main_tenant_can_read_booking','can_read_tour_booking','get_municipal_tour_waiting_rate','submit_tourist_review','get_tourist_rating_summary','get_booking_waiting_summary','get_tour_operations_report','observe_driver_journey_location','complete_current_itinerary_item','advance_driver_tour_action') then
     execute format('grant execute on function %s to authenticated',f.signature);
   end if;
 end loop;
end;
$feature_grants$;

commit;
