begin;

-- Shared server radius for pickup, current itinerary stop, and drop-off.
create or replace function public.driver_arrival_radius_meters()
returns double precision language sql immutable set search_path = public
as $$ select 50::double precision $$;

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
  v_arriving := d.journey_state in ('en_route_pickup','en_route_stop','en_route_dropoff','at_dropoff');
  v_qualifies := case when v_arriving then
    v_distance <= public.driver_arrival_radius_meters() and p_speed_mps <= 2
    else v_distance-p_accuracy_meters >= public.driver_arrival_radius_meters()+200 and p_speed_mps >= 1 end;
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
  if (v_arriving and v_qualifies) or (e.sample_count >= 4 and p_sampled_at-e.first_sample_at >= make_interval(secs=>v_required_seconds)
      and v_now-e.first_received_at >= make_interval(secs=>v_required_seconds)) then
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

create or replace function public.administrator_delete_test_booking(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_booking public.package_bookings;
  v_activity_ids uuid[];
begin
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  select * into v_booking from public.package_bookings
  where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  -- Match the unfiltered Developer Tools list scope, independent of whether
  -- this booking ever had a test session or its session has expired.
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
      in ('cancelled', 'rejected', 'completed', 'expired') then
    raise exception 'BOOKING_NOT_ELIGIBLE_FOR_DEVELOPER_CLEANUP';
  end if;

  -- Lock financial rows while classifying them. The booking row lock also blocks
  -- new booking-scoped FK inserts until this transaction finishes.
  perform 1 from public.payment_records where booking_id=p_booking_id for update;
  perform 1 from public.payment_allocations where booking_id=p_booking_id for update;
  perform 1 from public.payment_provider_events e where exists (
    select 1 from public.payment_records p where p.booking_id=p_booking_id
      and (e.payment_record_id=p.id
        or (e.payment_record_id is null and e.provider=p.provider and p.provider_checkout_id is not null and e.provider_checkout_id=p.provider_checkout_id)
        or (e.payment_record_id is null and e.provider=p.provider and p.provider_payment_id is not null and e.provider_payment_id=p.provider_payment_id))
  ) for update;

  if exists(select 1 from public.refund_requests where booking_id=p_booking_id) then
    raise exception 'BOOKING_HAS_REFUND';
  end if;
  if exists(select 1 from public.payment_disputes where booking_id=p_booking_id) then
    raise exception 'BOOKING_HAS_DISPUTE';
  end if;
  if exists(select 1 from public.booking_payment_requirements r
      join public.payment_records p on p.id=r.satisfied_by_payment_record_id
      where r.booking_id=p_booking_id and p.booking_id is distinct from p_booking_id)
     or exists(select 1 from public.payment_allocations a
      join public.payment_records p on p.id=a.payment_record_id
      where a.booking_id=p_booking_id and p.booking_id is distinct from p_booking_id) then
    raise exception 'BOOKING_HAS_PAYMENT_EVIDENCE';
  end if;
  if exists(select 1 from public.payout_records where booking_id=p_booking_id) then
    raise exception 'BOOKING_HAS_PAYOUT';
  end if;
  if exists(select 1 from public.payment_allocations where booking_id=p_booking_id
      and (coalesce(status,'') not in ('held','eligible','failed','cancelled')
        or provider_transfer_id is not null or provider_transfer_status is not null
        or paid_at is not null)) then
    raise exception 'BOOKING_HAS_TRANSFER';
  end if;
  -- A PayMongo receipt is disposable only when both the payment and every
  -- associated provider event explicitly identify the sandbox environment.
  if exists(select 1 from public.payment_provider_events e where e.provider_livemode is distinct from false
      and exists(select 1 from public.payment_records p where p.booking_id=p_booking_id
        and (e.payment_record_id=p.id
          or (e.payment_record_id is null and e.provider=p.provider and p.provider_checkout_id is not null and e.provider_checkout_id=p.provider_checkout_id)
          or (e.payment_record_id is null and e.provider=p.provider and p.provider_payment_id is not null and e.provider_payment_id=p.provider_payment_id))))
     or exists(select 1 from public.payment_records p where p.booking_id=p_booking_id
      and coalesce(p.provider,'manual') <> 'manual' and p.provider_livemode is distinct from false) then
    raise exception 'BOOKING_HAS_LIVE_PROVIDER_PAYMENT';
  end if;
  if exists(select 1 from public.payment_records p where p.booking_id=p_booking_id
      and not ((p.provider='paymongo' and p.provider_livemode is false)
        or (coalesce(p.provider,'manual')='manual'
          and p.status in ('pending_confirmation','cancelled')
          and p.provider_livemode is null and p.paid_at is null
          and p.payee_confirmed_at is null and p.receipt_no is null
          and p.external_reference_no is null and p.proof_image_url is null
          and p.provider_payment_id is null and p.provider_checkout_id is null
          and p.provider_reference is null))) then
    raise exception 'BOOKING_HAS_PAYMENT_EVIDENCE';
  end if;
  if exists(select 1 from public.emergency_alerts where booking_id=p_booking_id) then
    raise exception 'BOOKING_HAS_EMERGENCY_RECORD';
  end if;
  if exists(select 1 from public.driver_reviews where booking_id=p_booking_id)
     or exists(select 1 from public.package_reviews where booking_id=p_booking_id)
     or exists(select 1 from public.tourist_reviews where booking_id=p_booking_id) then
    raise exception 'BOOKING_HAS_REVIEW';
  end if;

  insert into public.audit_logs(actor_id,action,table_name,record_id,description)
  values(auth.uid(),'DEVELOPER_TEST_BOOKING_DELETE','package_bookings',
    p_booking_id::text,jsonb_build_object('booking_id',p_booking_id,
    'scope','developer_tools_booking_cleanup')::text);

  select array_agg(id) into v_activity_ids from public.package_activities
  where booking_id=p_booking_id;
  -- These are shared Driver rows; remove only the link to this booking's activity.
  update public.driver_live_locations set activity_id=null
  where activity_id=any(coalesce(v_activity_ids,array[]::uuid[]));
  -- Notification delivery rows have a text identifier rather than an FK.
  delete from public.notification_deliveries delivery
  using public.notifications notice
  where delivery.notification_id=notice.id::text
    and notice.booking_id=p_booking_id;
  delete from public.notifications where booking_id=p_booking_id;
  -- Booking conversations have SET NULL on booking deletion; remove their
  -- messages and members through the conversation's own declared cascades.
  delete from public.conversations where booking_id=p_booking_id;
  -- Test trip events can be removed; the separate administrator audit stays.
  delete from public.trip_status_logs where booking_id=p_booking_id;
  -- Requirements and allocations reference payment records without cascade.
  -- Delete sandbox events before their payment FK would otherwise become null.
  delete from public.booking_payment_requirements where booking_id=p_booking_id;
  delete from public.payment_allocations where booking_id=p_booking_id;
  delete from public.payment_provider_events e where exists (
    select 1 from public.payment_records p where p.booking_id=p_booking_id
      and (e.payment_record_id=p.id
        or (e.payment_record_id is null and e.provider=p.provider and p.provider_checkout_id is not null and e.provider_checkout_id=p.provider_checkout_id)
        or (e.payment_record_id is null and e.provider=p.provider and p.provider_payment_id is not null and e.provider_payment_id=p.provider_payment_id))
  );
  delete from public.payment_records where booking_id=p_booking_id;
  delete from public.booking_stop_waiting_charges where booking_id=p_booking_id;
  delete from public.booking_custom_fare_quotes where booking_id=p_booking_id;
  -- Other dependent test rows use their declared FK cascades. Assignment rows
  -- must go first because they also reference package_activities without cascade.
  delete from public.booking_drivers where booking_id=p_booking_id;
  delete from public.package_bookings where id=p_booking_id;
  return jsonb_build_object('success',true,'booking_id',p_booking_id);
exception when foreign_key_violation then
  raise exception 'BOOKING_HAS_OTHER_REFERENCE';
end;
$$;
revoke all on function public.administrator_delete_test_booking(uuid)
  from public, anon;
grant execute on function public.administrator_delete_test_booking(uuid)
  to authenticated;

commit;

