-- Extend the existing convoy lifecycle. Store one evidence window per driver,
-- and retain only milestone evidence in the existing audit log.
begin;

alter table public.package_bookings add column if not exists tracking_interrupted_at timestamptz;
create table public.driver_journey_evidence (
  booking_driver_id uuid primary key references public.booking_drivers(id) on delete cascade,
  expected_state text not null,
  stop_index integer not null,
  phase text not null default 'navigating',
  sample_count integer not null default 0,
  first_sample_at timestamptz,
  first_received_at timestamptz,
  last_sample_at timestamptz,
  last_received_at timestamptz,
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision,
  speed_mps double precision,
  blocked_reason text
);
alter table public.driver_journey_evidence enable row level security;
-- RPC-only: a client cannot manufacture a qualified evidence window with CRUD.
revoke all on public.driver_journey_evidence from public, anon, authenticated;

create or replace function public.guard_tour_automation_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.tracking_interrupted_at is distinct from old.tracking_interrupted_at
     and coalesce(current_setting('touristrike.tracking_reconcile', true), '') <> 'true' then
    raise exception 'TRACKING_STATUS_SERVER_ONLY';
  end if;
  return new;
end;
$$;
create trigger guard_tour_automation_fields before update on public.package_bookings
for each row execute function public.guard_tour_automation_fields();

create or replace function public.reconcile_stale_tour_tracking(p_booking_id uuid default null)
returns integer language plpgsql security definer set search_path = public as $$
declare b public.package_bookings; v_count integer := 0; v_stale boolean;
begin
  -- Lock bookings first, matching the canonical lifecycle's lock order.
  for b in select * from public.package_bookings
    where (p_booking_id is null or id = p_booking_id)
      and lower(coalesce(booking_status, status, '')) not in ('completed','done','cancelled','rejected','expired')
      and exists (select 1 from public.booking_drivers d where d.booking_id = package_bookings.id
        and d.status = 'accepted' and d.journey_state <> 'assigned')
    order by id for update skip locked
  loop
    v_stale := coalesce(b.estimated_end_at, b.scheduled_start_at + interval '12 hours',
      (select min(coalesce(accepted_at,state_updated_at)) + interval '12 hours'
       from public.booking_drivers where booking_id=b.id))
        < now() - interval '2 hours'
      and exists (select 1 from public.booking_drivers d
        left join public.driver_journey_evidence e on e.booking_driver_id = d.id
        where d.booking_id = b.id and d.status = 'accepted' and d.journey_state <> 'assigned'
          and greatest(d.state_updated_at, e.last_received_at) < now() - interval '30 minutes');
    if v_stale and b.tracking_interrupted_at is null then
      perform set_config('touristrike.tracking_reconcile', 'true', true);
      update public.package_bookings set tracking_interrupted_at = now() where id = b.id;
      perform set_config('touristrike.tracking_reconcile', 'false', true);
      insert into public.trip_status_logs(activity_id,booking_id,status,notes)
      select id,b.id,'tracking_interrupted',
        'Overdue by 2 hours with no verified GPS/progress for 30 minutes. Completion NOT inferred.'
      from public.package_activities where booking_id = b.id;
      v_count := v_count + 1;
    elsif not v_stale and b.tracking_interrupted_at is not null then
      perform set_config('touristrike.tracking_reconcile', 'true', true);
      update public.package_bookings set tracking_interrupted_at = null where id = b.id;
      perform set_config('touristrike.tracking_reconcile', 'false', true);
      insert into public.trip_status_logs(activity_id,booking_id,status,notes)
      select id,b.id,'tracking_resumed','Tracking/progress resumed; persisted expected stop preserved.'
      from public.package_activities where booking_id = b.id;
    end if;
  end loop;
  return v_count;
end;
$$;

create or replace function public.get_tour_tracking_status(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_package_booking_participant(p_booking_id) then
    raise exception 'NOT_BOOKING_PARTICIPANT';
  end if;
  perform public.reconcile_stale_tour_tracking(p_booking_id);
  return (select jsonb_build_object('interrupted_at', b.tracking_interrupted_at,
    'journey_state', d.journey_state, 'current_stop_index', d.current_stop_index,
    'phase', coalesce(e.phase, 'navigating'), 'blocked_reason', e.blocked_reason)
    from public.package_bookings b
    left join public.booking_drivers d on d.booking_id=b.id and d.driver_id=auth.uid()
    left join public.driver_journey_evidence e on e.booking_driver_id=d.id
    where b.id=p_booking_id);
end;
$$;

create or replace function public.guard_verified_journey_transition()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.journey_state is distinct from old.journey_state or new.current_stop_index is distinct from old.current_stop_index)
    and coalesce(current_setting('touristrike.gps_transition_verified',true),'') <> 'true'
    and coalesce(current_setting('touristrike.journey_rpc',true),'') <> 'true'
    and length(coalesce(current_setting('touristrike.manual_lifecycle_reason',true),'')) < 10 then
    raise exception 'JOURNEY_RPC_REQUIRED';
  end if;
  if new.journey_state is not distinct from old.journey_state then return new; end if;
  if new.journey_state in ('at_pickup','boarded','at_stop','stop_done','at_dropoff','completed')
    and coalesce(current_setting('touristrike.gps_transition_verified', true),'') <> 'true'
    and length(coalesce(current_setting('touristrike.manual_lifecycle_reason', true),'')) < 10 then
    raise exception 'VERIFIED_GPS_OR_AUDITED_RECOVERY_REQUIRED';
  end if;
  return new;
end;
$$;
create trigger guard_verified_journey_transition before update of journey_state,current_stop_index on public.booking_drivers
for each row execute function public.guard_verified_journey_transition();

create or replace function public.observe_driver_journey_location(
  p_booking_id uuid, p_latitude double precision, p_longitude double precision,
  p_accuracy_meters double precision, p_speed_mps double precision, p_sampled_at timestamptz
)
returns jsonb language plpgsql security definer set search_path = public as $$
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
      -- A stable, verified final destination completes through the canonical payment/convoy gates.
      if v_target='at_dropoff' then
        begin
          perform public.advance_driver_journey_state(b.id,'completed'); v_phase:='completed';
        exception when raise_exception then
          get stacked diagnostics v_error = message_text;
          if v_error not like '%REMAINING_BALANCE%' then raise; end if;
          v_phase := 'completion_pending';
        end;
      end if;
    elsif d.journey_state='at_pickup' then
      perform public.advance_driver_journey_state(b.id,'boarded');
      v_phase := 'departure_detected'; v_transition := true;
    elsif d.journey_state='at_stop' then
      perform public.complete_current_itinerary_item(v_activity,v_item,null);
      update public.booking_driver_arrivals set departed_at=coalesce(departed_at,v_now)
        where booking_driver_id=d.id and itinerary_item_id=v_item;
      update public.booking_itinerary_items set actual_departure_time=(
        select max(departed_at) from public.booking_driver_arrivals where itinerary_item_id=v_item)
        where id=v_item and spot_status='completed';
      v_phase := 'departure_detected'; v_transition := true;
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
  -- Retry existing convoy/payment barriers on the next streamed fix. A blocked
  -- transition must not roll back already verified arrival/departure evidence.
  select * into d from public.booking_drivers where id=d.id;
  if d.journey_state in ('boarded','stop_done') then
    select count(*) into v_count from public.booking_itinerary_items where booking_id=b.id;
    v_target := case when d.journey_state='boarded' and v_count>0 then 'en_route_stop'
      when d.journey_state='stop_done' and d.current_stop_index+1<v_count then 'en_route_stop'
      else 'en_route_dropoff' end;
    begin
      perform public.advance_driver_journey_state(b.id,v_target);
      v_transition:=true; v_phase:='next_stop';
    exception when raise_exception then
      get stacked diagnostics v_error = message_text;
      if v_error not like '%BARRIER_NOT_MET%' and v_error not like '%REMAINING_BALANCE_NOT_CONFIRMED%'
        and v_error not like '%INCOMPLETE_ITINERARY%' then raise; end if;
      v_phase:='waiting_for_convoy_or_payment';
    end;
  end if;
  update public.driver_journey_evidence set phase=v_phase,blocked_reason=v_error where booking_driver_id=d.id;
  return jsonb_build_object('changed',v_transition,'phase',v_phase,'blocked_reason',v_error,
    'interrupted_at',(select tracking_interrupted_at from public.package_bookings where id=b.id),
    'journey_state',(select journey_state from public.booking_drivers where id=d.id),
    'current_stop_index',(select current_stop_index from public.booking_drivers where id=d.id));
end;
$$;

create or replace function public.recover_driver_journey(p_booking_id uuid,p_expected_state text,p_stop_index integer,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d public.booking_drivers; v_activity uuid; v_item uuid; v_result jsonb; v_phase text;
begin
  if auth.uid() is null or public.current_profile_role() is distinct from 'driver' then raise exception 'DRIVER_ROLE_REQUIRED'; end if;
  if length(trim(coalesce(p_reason,''))) not between 10 and 500 then raise exception 'RECOVERY_REASON_REQUIRED'; end if;
  perform 1 from public.package_bookings where id=p_booking_id for update;
  select * into d from public.booking_drivers where booking_id=p_booking_id and driver_id=auth.uid() and status in ('accepted','completed') for update;
  if not found then raise exception 'NOT_ASSIGNED_DRIVER'; end if;
  if d.journey_state is distinct from p_expected_state or d.current_stop_index is distinct from p_stop_index then
    return jsonb_build_object('no_op',true,'journey_state',d.journey_state);
  end if;
  select id into v_activity from public.package_activities where booking_id=p_booking_id limit 1;
  perform set_config('touristrike.manual_lifecycle_reason',trim(p_reason),true);
  if d.journey_state in ('en_route_pickup','en_route_stop','en_route_dropoff') then
    v_result := public.confirm_driver_arrival_fallback(p_booking_id,p_reason);
  elsif d.journey_state='at_pickup' then
    v_result := public.advance_driver_journey_state(p_booking_id,'boarded');
  elsif d.journey_state='at_stop' then
    select id into v_item from public.booking_itinerary_items where booking_id=p_booking_id
    order by coalesce(order_number,2147483647),coalesce(destination_order,2147483647),arrival_time nulls last,created_at,id
    offset d.current_stop_index limit 1;
    v_result := public.complete_current_itinerary_item(v_activity,v_item,null);
  elsif d.journey_state='at_dropoff' then
    v_result := public.advance_driver_journey_state(p_booking_id,'completed');
  else raise exception 'RECOVERY_NOT_AVAILABLE_FOR_STATE'; end if;
  perform set_config('touristrike.manual_lifecycle_reason','',true);
  insert into public.trip_status_logs(activity_id,booking_id,driver_id,status,previous_state,new_state,spot_index,notes)
  select v_activity,p_booking_id,auth.uid(),'manual_journey_recovery',d.journey_state,journey_state,d.current_stop_index,trim(p_reason)
  from public.booking_drivers where id=d.id;
  select case when journey_state='completed' then 'completed'
    when journey_state in ('at_pickup','at_stop','at_dropoff') then 'arrived'
    else 'departure_detected' end into v_phase from public.booking_drivers where id=d.id;
  update public.driver_journey_evidence set phase=v_phase,sample_count=0,
    first_sample_at=null,first_received_at=null,blocked_reason=null where booking_driver_id=d.id;
  perform public.reconcile_stale_tour_tracking(p_booking_id);
  return v_result || jsonb_build_object('phase',v_phase,'changed',true,
    'interrupted_at',(select tracking_interrupted_at from public.package_bookings where id=p_booking_id));
end;
$$;

revoke all on function public.reconcile_stale_tour_tracking(uuid), public.get_tour_tracking_status(uuid),
  public.observe_driver_journey_location(uuid,double precision,double precision,double precision,double precision,timestamptz),
  public.recover_driver_journey(uuid,text,integer,text) from public,anon,authenticated;
grant execute on function public.get_tour_tracking_status(uuid),
  public.observe_driver_journey_location(uuid,double precision,double precision,double precision,double precision,timestamptz),
  public.recover_driver_journey(uuid,text,integer,text) to authenticated;

-- Supabase Cron runs without an app being open. Explicit notice if the local
-- database lacks pg_cron; deployment must install/verify this scheduled job.
do $$ begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    perform cron.schedule('touristrike-stale-tours','*/5 * * * *','select public.reconcile_stale_tour_tracking()');
  else raise notice 'pg_cron unavailable: enable Cron and schedule reconcile_stale_tour_tracking every 5 minutes';
  end if;
end $$;

-- Canonical function refinements follow; no parallel state machine is added.

create or replace function public.complete_current_itinerary_item(
  p_activity_id uuid,
  p_itinerary_item_id uuid,
  p_remaining_payment_method text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
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

  if not v_is_test_booking
     and coalesce(current_setting('touristrike.gps_transition_verified', true),'') <> 'true'
     and coalesce(v_item.estimated_stay_duration_minutes, 0) > 0
     and now() < v_latest_arrival
       + make_interval(mins => v_item.estimated_stay_duration_minutes) then
    raise exception 'STOP_DWELL_TIME_NOT_MET';
  end if;

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
create or replace function public.confirm_driver_arrival_fallback(p_booking_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_booking public.package_bookings; v_driver public.booking_drivers;
  v_lat double precision; v_lng double precision; v_target text; v_result jsonb;
begin
  if auth.uid() is null or length(trim(coalesce(p_reason, ''))) < 10 or length(p_reason) > 500 then
    raise exception 'ARRIVAL_FALLBACK_REASON_REQUIRED';
  end if;
  select * into v_booking from public.package_bookings where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  select * into v_driver from public.booking_drivers where booking_id = p_booking_id
    and driver_id = auth.uid() and status = 'accepted' for update;
  if not found then raise exception 'NOT_ACTIVE_BOOKING_DRIVER'; end if;
  if v_driver.journey_state in ('at_pickup', 'at_stop', 'at_dropoff') then
    return jsonb_build_object('success', true, 'no_op', true);
  end if;
  if v_driver.journey_state = 'en_route_pickup' then
    v_target := 'at_pickup'; v_lat := v_booking.pickup_latitude; v_lng := v_booking.pickup_longitude;
  elsif v_driver.journey_state = 'en_route_dropoff' then
    v_target := 'at_dropoff'; v_lat := v_booking.dropoff_latitude; v_lng := v_booking.dropoff_longitude;
  elsif v_driver.journey_state = 'en_route_stop' then
    v_target := 'at_stop';
    select latitude, longitude into v_lat, v_lng from public.booking_itinerary_items where booking_id = p_booking_id
    order by coalesce(order_number, 2147483647), coalesce(destination_order, 2147483647), arrival_time nulls last, created_at, id
    offset v_driver.current_stop_index limit 1;
  else raise exception 'NOT_EN_ROUTE'; end if;
  if v_lat is null or v_lng is null then raise exception 'TARGET_LOCATION_REQUIRED'; end if;
  if exists (
    select 1 from public.booking_participant_live_locations l
    where l.booking_id = p_booking_id and l.user_id = v_booking.tourist_id
      and l.updated_at >= now() - interval '2 minutes' and l.accuracy_meters <= 50
      and 6371000 * 2 * asin(sqrt(least(1, greatest(0,
        power(sin(radians(l.latitude - v_lat) / 2), 2) + cos(radians(v_lat)) * cos(radians(l.latitude))
        * power(sin(radians(l.longitude - v_lng) / 2), 2))))) <= public.driver_arrival_radius_meters()
  ) then
    perform set_config('touristrike.arrival_fallback_verified', 'true', true);
  end if;
  -- Otherwise the usual fresh driver-location guard applies.
  perform set_config('touristrike.manual_lifecycle_reason', trim(p_reason), true);
  v_result := public.advance_driver_journey_state(p_booking_id, v_target);
  perform set_config('touristrike.arrival_fallback_verified', 'false', true);
  perform set_config('touristrike.manual_lifecycle_reason', '', true);
  insert into public.trip_status_logs(activity_id, booking_id, driver_id, status, previous_state, new_state, spot_index, notes)
  select id, p_booking_id, auth.uid(), 'arrival_manual_fallback', v_driver.journey_state, v_target,
    v_driver.current_stop_index, trim(p_reason) from public.package_activities where booking_id = p_booking_id;
  return v_result;
end;
$$;
create or replace function public.advance_driver_journey_state(
  p_booking_id uuid,
  p_target_state text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_booking public.package_bookings;
  v_current text;
  v_stop_index integer;
  v_is_gated boolean := false;
  v_new_stop_index integer;
  v_all_cleared boolean;
  v_slowest_state text;
  v_legacy_status text;
  v_activity_id uuid;
  v_accepted_count integer;
  v_total_items integer;
  v_completed_items integer;
  v_is_test_booking boolean := false;
  v_debug_bypass boolean := false;
  v_finalization jsonb;
  v_stage_progress jsonb;
begin
  if v_driver_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if public.journey_state_order(p_target_state) is null then
    raise exception 'INVALID_STATE: %', p_target_state;
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
     in ('cancelled', 'rejected') then
    raise exception 'CANCELLED_BOOKING_CANNOT_ADVANCE';
  end if;

  v_is_test_booking := public.is_developer_test_booking(p_booking_id);
  v_debug_bypass := v_is_test_booking and coalesce(
    current_setting('touristrike.debug_progression_bypass', true), ''
  ) = 'true';

  select journey_state, current_stop_index into v_current, v_stop_index
  from public.booking_drivers
  where booking_id = p_booking_id
    and driver_id = v_driver_id
    and status in ('accepted', 'completed')
  for update;
  if not found then raise exception 'NOT_IN_CONVOY'; end if;

  if v_current = p_target_state then
    v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);
    return jsonb_build_object(
      'success', true, 'no_op', true,
      'journey_state', v_current, 'current_stop_index', v_stop_index,
      'overall_completed', coalesce((v_finalization->>'overall_completed')::boolean, false),
      'awaiting_final_payment', coalesce((v_finalization->>'awaiting_final_payment')::boolean, false)
    );
  end if;

  if v_current = 'completed' then
    v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);
    return jsonb_build_object(
      'success', true, 'no_op', true,
      'journey_state', v_current, 'current_stop_index', v_stop_index,
      'assignment_completed', true,
      'overall_completed', coalesce((v_finalization->>'overall_completed')::boolean, false),
      'awaiting_final_payment', coalesce((v_finalization->>'awaiting_final_payment')::boolean, false)
    );
  end if;

  v_new_stop_index := v_stop_index;
  if v_current = 'assigned' and p_target_state = 'en_route_pickup' then
    v_is_gated := false;
  elsif v_current = 'en_route_pickup' and p_target_state = 'at_pickup' then
    v_is_gated := false;
  elsif v_current = 'at_pickup' and p_target_state = 'boarded' then
    v_is_gated := false;
  elsif v_current = 'boarded' and p_target_state in ('en_route_stop', 'en_route_dropoff') then
    v_is_gated := true;
    if p_target_state = 'en_route_stop' then v_new_stop_index := 0; end if;
  elsif v_current = 'en_route_stop' and p_target_state = 'at_stop' then
    v_is_gated := false;
  elsif v_current = 'stop_done' and p_target_state in ('en_route_stop', 'en_route_dropoff') then
    v_is_gated := true;
    if p_target_state = 'en_route_stop' then v_new_stop_index := v_stop_index + 1; end if;
  elsif v_current = 'en_route_dropoff' and p_target_state = 'at_dropoff' then
    v_is_gated := false;
  elsif v_current = 'at_dropoff' and p_target_state = 'completed' then
    v_is_gated := false;
  else
    if public.journey_state_order(v_current)
       > public.journey_state_order(p_target_state) then
      v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);
      return jsonb_build_object(
        'success', true, 'no_op', true, 'already_progressed', true,
        'journey_state', v_current, 'current_stop_index', v_stop_index,
        'overall_completed', coalesce((v_finalization->>'overall_completed')::boolean, false),
        'awaiting_final_payment', coalesce((v_finalization->>'awaiting_final_payment')::boolean, false)
      );
    end if;
    raise exception 'INVALID_TRANSITION: % -> %', v_current, p_target_state;
  end if;

  if p_target_state = 'en_route_stop' then
    select count(*) into v_total_items from public.booking_itinerary_items where booking_id = p_booking_id;
    if v_new_stop_index < 0 or v_new_stop_index >= v_total_items then
      raise exception 'ITINERARY_STOP_OUT_OF_RANGE';
    end if;
  end if;

  if v_current = 'assigned' and p_target_state = 'en_route_pickup' then
    select count(*) into v_accepted_count
    from public.booking_drivers
    where booking_id = p_booking_id and status in ('accepted', 'completed');
    if v_accepted_count < greatest(coalesce(v_booking.required_drivers, 1), 1) then
      raise exception 'DRIVER_SLOTS_NOT_FILLED';
    end if;
    if not v_debug_bypass
       and now() < lower(public.package_booking_schedule_window(v_booking)) then
      raise exception 'BOOKING_START_TOO_EARLY';
    end if;
    if not v_debug_bypass
       and not public.is_booking_downpayment_confirmed(p_booking_id) then
      raise exception 'DOWNPAYMENT_NOT_CONFIRMED';
    end if;
  end if;

  if v_current = 'at_dropoff' and p_target_state = 'completed' then
    select count(*), count(*) filter (
      where lower(coalesce(spot_status, 'pending')) = 'completed'
    ) into v_total_items, v_completed_items
    from public.booking_itinerary_items
    where booking_id = p_booking_id;
    if v_total_items = 0 or v_completed_items < v_total_items then
      raise exception 'INCOMPLETE_ITINERARY';
    end if;
  end if;

  -- Payment is a server-enforced precondition of the final navigation leg.
  -- Only the allowlisted debug RPC can bypass this payment check.
  if p_target_state = 'en_route_dropoff' then
    select count(*), count(*) filter (
      where lower(coalesce(spot_status, 'pending')) = 'completed'
    ) into v_total_items, v_completed_items
    from public.booking_itinerary_items
    where booking_id = p_booking_id;
    if v_total_items = 0 or v_completed_items < v_total_items then
      raise exception 'INCOMPLETE_ITINERARY';
    end if;
    if not v_debug_bypass and not public.is_booking_remaining_payment_satisfied(p_booking_id) then
      raise exception 'REMAINING_BALANCE_NOT_CONFIRMED';
    end if;
  end if;

  if v_is_gated and not v_debug_bypass then
    if v_current = 'boarded' then
      v_stage_progress := public.compute_convoy_stage_progress(
        p_booking_id, 'boarded', null
      );
    elsif v_current = 'stop_done' then
      v_stage_progress := public.compute_convoy_stage_progress(
        p_booking_id, 'stop_done', v_stop_index
      );
    elsif v_current = 'at_dropoff' then
      v_stage_progress := public.compute_convoy_stage_progress(
        p_booking_id, 'at_dropoff', null
      );
    end if;
    v_all_cleared := coalesce(
      (v_stage_progress->>'all_satisfied')::boolean, false
    );
    if not coalesce(v_all_cleared, false) then raise exception 'BARRIER_NOT_MET'; end if;
  end if;

  perform set_config('touristrike.journey_rpc', 'true', true);
  update public.booking_drivers
  set journey_state = p_target_state,
      current_stop_index = v_new_stop_index,
      state_updated_at = now(),
      status = case when p_target_state = 'completed' then 'completed' else status end,
      completed_at = case when p_target_state = 'completed'
        then coalesce(completed_at, now()) else completed_at end
  where booking_id = p_booking_id and driver_id = v_driver_id;
  perform set_config('touristrike.journey_rpc', 'false', true);

  select (array_agg(journey_state
    order by public.journey_state_order(journey_state), current_stop_index))[1]
  into v_slowest_state
  from public.booking_drivers
  where booking_id = p_booking_id and status in ('accepted', 'completed');

  v_legacy_status := case v_slowest_state
    when 'assigned' then 'driver_accepted'
    when 'en_route_pickup' then 'driver_en_route'
    when 'at_pickup' then 'driver_arrived'
    when 'boarded' then 'picked_up'
    when 'en_route_stop' then 'en_route_to_spot'
    when 'at_stop' then 'at_spot'
    when 'stop_done' then 'on_tour'
    when 'en_route_dropoff' then 'en_route_to_dropoff'
    when 'at_dropoff' then 'ready_to_complete'
    when 'completed' then 'ready_to_complete'
    else 'driver_accepted'
  end;

  select id into v_activity_id
  from public.package_activities where booking_id = p_booking_id limit 1;

  perform set_config('touristrike.validated_transition', 'true', true);
  if v_activity_id is not null then
    update public.package_activities
    set tour_status = v_legacy_status,
        status = case when v_legacy_status = 'driver_accepted'
          then 'accepted' else 'ongoing' end,
        current_spot_index = greatest(v_new_stop_index, current_spot_index),
        dropped_off_at = case when p_target_state = 'completed'
          then coalesce(dropped_off_at, now()) else dropped_off_at end,
        updated_at = now()
    where id = v_activity_id;

    insert into public.trip_status_logs(
      activity_id, booking_id, driver_id, status, previous_state, new_state,
      spot_index, logged_at, notes
    ) values (
      v_activity_id, p_booking_id, v_driver_id,
      case when p_target_state = 'completed' then 'assignment_completed'
           else v_legacy_status end,
      v_current, p_target_state, v_new_stop_index, now(),
      case when v_debug_bypass
        then 'Developer test booking journey transition; operational validations bypassed'
        else 'Server-validated journey transition' end
    );
  end if;

  update public.package_bookings
  set booking_status = case
        when v_legacy_status in ('driver_accepted', 'driver_en_route', 'driver_arrived')
          then 'driver_on_the_way'
        else 'on_tour'
      end,
      current_spot_index = greatest(v_new_stop_index, current_spot_index),
      updated_at = now()
  where id = p_booking_id;

  v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);

  return jsonb_build_object(
    'success', true, 'no_op', false,
    'journey_state', p_target_state,
    'current_stop_index', v_new_stop_index,
    'legacy_tour_status', v_legacy_status,
    'assignment_completed', p_target_state = 'completed',
    'convoy_progress', case
      when p_target_state = 'boarded' then public.compute_convoy_stage_progress(
        p_booking_id, 'boarded', null
      )
      when p_target_state = 'stop_done' then public.compute_convoy_stage_progress(
        p_booking_id, 'stop_done', v_new_stop_index
      )
      when p_target_state in ('at_dropoff', 'completed') then
        public.compute_convoy_stage_progress(p_booking_id, 'at_dropoff', null)
      else null
    end,
    'overall_completed', coalesce((v_finalization->>'overall_completed')::boolean, false),
    'awaiting_final_payment', coalesce((v_finalization->>'awaiting_final_payment')::boolean, false),
    'debug_bypass', v_debug_bypass
  );
end;
$$;
create or replace function public.persist_driver_stop_milestones()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_item uuid;
begin
  if new.journey_state is not distinct from old.journey_state then return new; end if;
  if new.journey_state = 'at_stop' or (old.journey_state = 'stop_done' and new.journey_state in ('en_route_stop', 'en_route_dropoff')) then
    select id into v_item from public.booking_itinerary_items
    where booking_id = new.booking_id
    order by coalesce(order_number, 2147483647), coalesce(destination_order, 2147483647), arrival_time nulls last, created_at, id
    offset (case when new.journey_state = 'at_stop' then new.current_stop_index else old.current_stop_index end) limit 1;
    if v_item is null then raise exception 'ITINERARY_ITEM_NOT_FOUND'; end if;
    if new.journey_state = 'at_stop' then
      insert into public.booking_driver_arrivals(booking_driver_id, itinerary_item_id, arrived_at, latitude, longitude)
      select new.id, v_item, new.state_updated_at, dll.latitude, dll.longitude
      from (select 1) seed left join public.driver_live_locations dll on dll.driver_id = new.driver_id
      on conflict do nothing;
      update public.booking_itinerary_items set actual_arrival_time = coalesce(actual_arrival_time, new.state_updated_at),
        spot_status = case when spot_status = 'completed' then spot_status else 'at_spot' end where id = v_item;
      -- Preserve the existing arrival notification and its deduplication key.
      insert into public.notifications(user_id, title, body, type, is_read, dedupe_key)
      select recipient.user_id, 'Destination arrival',
        'Arrived at ' || bii.destination_name, 'itinerary_arrival', false,
        'arrival:' || new.id::text || ':' || v_item::text || ':' || recipient.user_id::text
      from public.booking_itinerary_items bii
      join public.package_bookings pb on pb.id = bii.booking_id
      cross join lateral (
        select pb.tourist_id as user_id
        union
        select bd.driver_id from public.booking_drivers bd
        where bd.booking_id = pb.id and bd.status = 'accepted'
      ) recipient
      where bii.id = v_item
      on conflict (dedupe_key) where dedupe_key is not null do nothing;
    else
      update public.booking_driver_arrivals set departed_at = coalesce(departed_at, new.state_updated_at)
      where booking_driver_id = new.id and itinerary_item_id = v_item;
      update public.booking_itinerary_items set actual_departure_time = (select max(departed_at) from public.booking_driver_arrivals where itinerary_item_id=v_item) where id = v_item;
    end if;
  end if;
  return new;
end;
$$;
create or replace function public.get_driver_home_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_driver uuid := auth.uid(); v_start timestamptz;
begin
  if v_driver is null or public.current_profile_role() is distinct from 'driver' then raise exception 'DRIVER_ROLE_REQUIRED'; end if;
  v_start := date_trunc('day', now() at time zone 'Asia/Manila') at time zone 'Asia/Manila';
  return jsonb_build_object(
    'completed_tours', (select count(*) from public.booking_drivers where driver_id = v_driver and status = 'completed'),
    'today_trips', (select count(*) from public.booking_drivers where driver_id = v_driver and status = 'completed'
      and completed_at >= v_start and completed_at < v_start + interval '1 day'),
    'active_trips', (select count(*) from public.booking_drivers bd join public.package_bookings pb on pb.id = bd.booking_id
      where bd.driver_id = v_driver and bd.status = 'accepted' and pb.status not in ('completed', 'cancelled', 'rejected')
        and pb.tracking_interrupted_at is null
        and (pb.scheduled_start_at <= now() or bd.journey_state <> 'assigned')),
    'interrupted_trips', (select count(*) from public.booking_drivers bd join public.package_bookings pb on pb.id=bd.booking_id
      where bd.driver_id=v_driver and bd.status='accepted' and pb.tracking_interrupted_at is not null
        and pb.status not in ('completed','cancelled','rejected')),
    'upcoming_trips', (select count(*) from public.booking_drivers bd join public.package_bookings pb on pb.id = bd.booking_id
      where bd.driver_id = v_driver and bd.status = 'accepted' and pb.status not in ('completed', 'cancelled', 'rejected')
        and pb.scheduled_start_at > now() and bd.journey_state = 'assigned'),
    'average_rating', (select coalesce(round(avg(rating), 2), 0) from public.driver_reviews where driver_id = v_driver and rating between 1 and 5),
    'review_count', (select count(*) from public.driver_reviews where driver_id = v_driver and rating between 1 and 5),
    'recent_reviews', coalesce((select jsonb_agg(r order by r.created_at desc) from (
      select booking_id, rating, review_text, created_at from public.driver_reviews
      where driver_id = v_driver and rating between 1 and 5 order by created_at desc limit 5
    ) r), '[]'::jsonb),
    'today_earnings', (select coalesce(sum(pa.driver_amount), 0) from public.payment_allocations pa
      join public.payment_records pr on pr.id = pa.payment_record_id
      where pa.driver_id = v_driver and pr.status = 'confirmed' and pa.status not in ('cancelled', 'manual_review')
        and coalesce(pr.paid_at, pa.paid_at) >= v_start and coalesce(pr.paid_at, pa.paid_at) < v_start + interval '1 day'),
    'assignments', coalesce((select jsonb_agg(a order by a.scheduled_start_at) from (
      select bd.booking_id, bd.journey_state, pb.scheduled_start_at, pb.tracking_interrupted_at, tp.title,
        (select id from public.package_activities where booking_id = pb.id limit 1) as activity_id
      from public.booking_drivers bd join public.package_bookings pb on pb.id = bd.booking_id
      join public.tour_packages tp on tp.id = pb.package_id
      where bd.driver_id = v_driver and bd.status = 'accepted' and pb.status not in ('completed', 'cancelled', 'rejected')
      order by pb.scheduled_start_at limit 10
    ) a), '[]'::jsonb)
  );
end;
$$;

commit;
