-- Transaction-only developer bookings using existing identities. No auth,
-- profile, Driver-detail, approved fare, or historical-payment row is changed.
create temporary table tour_gate_context(booking_id uuid,foreign_booking_id uuid,item_id uuid,
  tourist_id uuid,driver_id uuid,subtenant_id uuid,main_id uuid,administrator_id uuid,
  old_payment_id uuid,old_payment jsonb,old_allocations jsonb,new_payment_id uuid) on commit drop;
create temporary table tour_gate_results(name text primary key) on commit drop;
create function pg_temp.tour_check(p_ok boolean,p_name text) returns void language plpgsql as $$
begin
 if p_ok is distinct from true then raise exception 'TOUR_GATE_FAILED: %',p_name; end if;
 insert into tour_gate_results values(p_name);
end $$;
grant select,update on tour_gate_context to authenticated;
grant select,insert on tour_gate_results to authenticated;

do $$
declare b public.package_bookings; i public.booking_itinerary_items;
  v_tourist uuid; v_other uuid; v_driver uuid; v_sub uuid; v_main uuid; v_admin uuid;
  v_booking uuid:=gen_random_uuid();v_foreign uuid:=gen_random_uuid();v_item uuid:=gen_random_uuid();
  v_roster uuid:=gen_random_uuid();v_down uuid:=gen_random_uuid();v_payment public.payment_records;
  v_data jsonb;v_now timestamptz:=clock_timestamp();
begin
  select * into strict b from public.package_bookings
    where municipality='Baliwag' and province='Bulacan' order by id limit 1;
  select item.* into strict i from public.booking_itinerary_items item
    join public.package_bookings original on original.id=item.booking_id
    where original.municipality='Baliwag' and original.province='Bulacan'
    order by item.id limit 1;
  select id into strict v_tourist from public.profiles
    where role='tourist' and not public.has_active_tour(id) order by id limit 1;
  select id into strict v_other from public.profiles
    where role='tourist' and id<>v_tourist and not public.has_active_tour(id) order by id limit 1;
  select id into strict v_driver from public.profiles where role='driver'
    and left(id::text,8) not in ('59a7c2c3','a1b8f8e3','a912c958') order by id limit 1;
  select id into strict v_sub from public.subtenant_details where is_active
    and city='Baliwag' and province='Bulacan' order by id limit 1;
  select id into strict v_main from public.profiles where role='main_tenant'
    and province='Bulacan' order by id limit 1;
  select id into strict v_admin from public.profiles where role='administrator' order by id limit 1;
  perform set_config('touristrike.validated_transition','true',true);
  perform set_config('touristrike.journey_rpc','true',true);
  perform set_config('touristrike.manual_lifecycle_reason','Rollback-only tour payment fixture',true);
  v_data := to_jsonb(b)||jsonb_build_object('id',v_booking,'tourist_id',v_tourist,
    'status','pending','booking_status','waiting_for_drivers','test_mode',true,
    'assigned_driver_id',null,'accepted_drivers_count',0,'required_drivers',1,'total_passengers',1,
    'total_amount',1500,'downpayment_amount',750,'remaining_balance',750,
    'completed_at',null,'booking_type','advanced','payment_method','gcash',
    'scheduled_start_at',v_now+interval '1 day','estimated_end_at',v_now+interval '2 days',
    'travel_date',((v_now+interval '1 day') at time zone 'Asia/Manila')::date);
  perform set_config('request.jwt.claim.sub',v_tourist::text,true);
  insert into public.package_bookings select (jsonb_populate_record(null::public.package_bookings,v_data)).*;
  perform set_config('request.jwt.claim.sub',v_other::text,true);
  insert into public.package_bookings select (jsonb_populate_record(null::public.package_bookings,
    v_data||jsonb_build_object('id',v_foreign,'tourist_id',v_other,'province','Another Province'))).*;
  perform set_config('request.jwt.claim.sub',v_tourist::text,true);
  insert into public.booking_drivers(id,booking_id,driver_id,status,journey_state,current_stop_index)
    values(v_roster,v_booking,v_driver,'accepted','en_route_stop',0);
  update public.package_bookings set booking_status='on_tour',status='ongoing' where id=v_booking;
  v_data:=to_jsonb(i)||jsonb_build_object('id',v_item,'booking_id',v_booking,
    'order_number',1,'destination_order',1,'spot_status','completed',
    'estimated_stay_duration_minutes',60,'actual_arrival_time',v_now-interval '61 minutes',
    'actual_departure_time',null);
  insert into public.booking_itinerary_items select (jsonb_populate_record(null::public.booking_itinerary_items,v_data)).*;
  perform public.ensure_booking_payment_requirements(v_booking);
  perform set_config('request.jwt.claim.sub',v_tourist::text,true);
  insert into public.payment_records(id,booking_id,payer_id,payee_id,amount,payment_method,payment_stage,status,provider,provider_livemode,provider_status)
    values(v_down,v_booking,v_tourist,null,750,'gcash','down_payment','confirmed','paymongo',false,'paid');
  update public.booking_payment_requirements set status='satisfied',satisfied_by_payment_record_id=v_down
    where booking_id=v_booking and payment_stage='down_payment';
  select * into v_payment from public.prepare_group_cash_remaining_balance(v_booking,'rollback-original-'||v_booking::text);
  perform set_config('request.jwt.claim.sub',v_driver::text,true);
  perform public.confirm_group_cash_share(v_payment.id);
  perform set_config('request.jwt.claim.sub','',true);
  insert into tour_gate_context values(v_booking,v_foreign,v_item,v_tourist,v_driver,v_sub,v_main,v_admin,
    v_payment.id,(select to_jsonb(p) from public.payment_records p where id=v_payment.id),
    (select jsonb_agg(to_jsonb(a) order by id) from public.payment_allocations a where payment_record_id=v_payment.id),null);
  perform pg_temp.tour_check((select remaining_balance=0 from public.package_bookings where id=v_booking),'original 750 confirmed and credited');
end $$;
