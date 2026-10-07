begin;

-- One authoritative inclusive radius for the current pickup, itinerary stop, and drop-off.
create or replace function public.driver_arrival_radius_meters()
returns double precision language sql immutable set search_path = public
as $$ select 150::double precision $$;

-- A fresh valid fix inside the current target transitions on this observer call.
create or replace function public.observe_driver_journey_location(
  p_booking_id uuid, p_latitude double precision, p_longitude double precision,
  p_accuracy_meters double precision, p_speed_mps double precision, p_sampled_at timestamptz
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  b public.package_bookings; d public.booking_drivers; e public.driver_journey_evidence;
  v_activity uuid; v_item uuid; v_lat double precision; v_lng double precision;
  v_distance double precision; v_phase text; v_qualifies boolean; v_transition boolean := false;
  v_arriving boolean; v_target text;
  v_now timestamptz := clock_timestamp(); v_evidence jsonb;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  select * into b from public.package_bookings where id=p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  select * into d from public.booking_drivers where booking_id=b.id and driver_id=auth.uid()
    and status = 'accepted' for update;
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
  v_arriving := d.journey_state in ('en_route_pickup','en_route_stop','en_route_dropoff');
  v_qualifies := case when v_arriving then
    v_distance <= public.driver_arrival_radius_meters()
    else v_distance-p_accuracy_meters >= public.driver_arrival_radius_meters()+200 and p_speed_mps >= 1 end;
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
  if v_arriving and v_qualifies then
    perform set_config('touristrike.gps_transition_verified','true',true);
    v_target := case d.journey_state when 'en_route_pickup' then 'at_pickup'
      when 'en_route_stop' then 'at_stop' when 'en_route_dropoff' then 'at_dropoff' end;
    perform public.advance_driver_journey_state(b.id,v_target);
    v_phase := 'arrived';
    v_transition := true;
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
  update public.driver_journey_evidence set phase=v_phase,blocked_reason=null where booking_driver_id=d.id;
  return jsonb_build_object('changed',v_transition,'phase',v_phase,'blocked_reason',null,
    'interrupted_at',(select tracking_interrupted_at from public.package_bookings where id=b.id),
    'journey_state',(select journey_state from public.booking_drivers where id=d.id),
    'current_stop_index',(select current_stop_index from public.booking_drivers where id=d.id));
end;
$$;

commit;
