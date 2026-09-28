-- Additional server verification inside the same rollback-only fixture.
do $$
declare c tour_gate_context;i public.booking_itinerary_items;v_item uuid:=gen_random_uuid();
  v_data jsonb;v_now timestamptz:=clock_timestamp();
begin
 select * into strict c from tour_gate_context;
 select * into strict i from public.booking_itinerary_items where id=c.item_id;
 v_data:=to_jsonb(i)||jsonb_build_object('id',v_item,'order_number',2,'destination_order',2,
   'estimated_stay_duration_minutes',90,'actual_arrival_time',null,'actual_departure_time',null);
 insert into public.booking_itinerary_items select (jsonb_populate_record(null::public.booking_itinerary_items,v_data)).*;
 insert into public.booking_driver_arrivals(booking_driver_id,itinerary_item_id,arrived_at,latitude,longitude)
   select id,v_item,v_now-interval '91 minutes',i.latitude,i.longitude
   from public.booking_drivers where booking_id=c.booking_id and driver_id=c.driver_id;
 update public.booking_itinerary_items set actual_arrival_time=v_now-interval '91 minutes' where id=v_item;
 perform pg_temp.tour_check((select included_minutes=90 and paid_until=arrived_at+interval '90 minutes'
   from public.booking_stop_waiting_charges where itinerary_item_id=v_item),'booked stay 90 is authoritative at actual arrival');
 perform pg_temp.tour_check((select rate_per_interval is null from public.booking_stop_waiting_charges where itinerary_item_id=v_item),'legacy arrival snapshots explicit missing rate; no hourly fallback');
 update public.booking_itinerary_items set actual_departure_time=v_now where id=v_item;
 perform pg_temp.tour_check((select chargeable_intervals=1 and additional_amount=0 and rate_per_interval is null and status='finalized'
   from public.booking_stop_waiting_charges where itinerary_item_id=v_item),'legacy missing-rate departure remains available and unbilled');
 perform pg_temp.tour_check((select remaining_balance=0 from public.package_bookings where id=c.booking_id),'missing-rate legacy stop does not fabricate debt');
end $$;

set local role authenticated;
do $$
declare c tour_gate_context;v_rejected boolean:=false;v_data jsonb;v_actor uuid;
begin
 select * into strict c from tour_gate_context;
 perform set_config('request.jwt.claim.sub',c.tourist_id::text,true);
 select to_jsonb(b)||jsonb_build_object('id',gen_random_uuid(),'status','pending',
   'booking_status','waiting_for_drivers','assigned_driver_id',null,'accepted_drivers_count',0,
   'remaining_balance',750,'tour_waiting_subtenant_id',null,'tour_waiting_rate_snapshot',null)
   into v_data from public.package_bookings b where id=c.booking_id;
 begin
   insert into public.package_bookings select (jsonb_populate_record(null::public.package_bookings,v_data)).*;
 exception when raise_exception then
   if sqlerrm like '%TOUR_WAITING_RATE_NOT_CONFIGURED%' then v_rejected:=true;else raise;end if;
 end;
 perform pg_temp.tour_check(v_rejected,'new booking fails clearly without approved rate');
 foreach v_actor in array array[c.tourist_id,c.driver_id,c.subtenant_id,c.main_id,c.administrator_id] loop
   perform set_config('request.jwt.claim.sub',v_actor::text,true);
   v_rejected:=false;
   begin update public.booking_stop_waiting_charges set additional_amount=0 where itinerary_item_id=c.item_id;
   exception when insufficient_privilege then v_rejected:=true;end;
   perform pg_temp.tour_check(v_rejected,'direct financial ledger writes denied '||v_actor::text);
 end loop;
 perform set_config('request.jwt.claim.sub',c.driver_id::text,true);
 v_rejected:=false;
 begin perform public.submit_tourist_review(c.booking_id,4::smallint,null);
 exception when raise_exception then
   if sqlerrm like '%COMPLETED_BOOKING_REQUIRED%' then v_rejected:=true;else raise;end if;
 end;
 perform pg_temp.tour_check(v_rejected,'review before completion rejected');
end $$;
reset role;

-- Fixture completion is a trusted backend write, not a claim that the real
-- Driver drop-off UI/slide was exercised. Any queued side effects roll back.
do $$
declare c tour_gate_context;
begin
 select * into strict c from tour_gate_context;
 perform set_config('request.jwt.claim.sub',c.driver_id::text,true);
 update public.package_bookings set booking_status='completed',status='completed',completed_at=clock_timestamp()
   where id=c.booking_id;
end $$;
set local role authenticated;
do $$
declare c tour_gate_context;v_rejected boolean;v_review public.tourist_reviews;v_report jsonb;
begin
 select * into strict c from tour_gate_context;
 perform set_config('request.jwt.claim.sub',c.driver_id::text,true);
 v_rejected:=false;
 begin perform public.submit_tourist_review(c.booking_id,0::smallint,null);
 exception when raise_exception then
   if sqlerrm like '%INVALID_RATING%' then v_rejected:=true;else raise;end if;
 end;
 perform pg_temp.tour_check(v_rejected,'rating outside 1-5 rejected');
 select * into v_review from public.submit_tourist_review(c.booking_id,4::smallint,'Rollback-only developer review');
 perform pg_temp.tour_check(v_review.tourist_id=c.tourist_id and v_review.driver_id=c.driver_id,'participating completed Driver review accepted');
 v_rejected:=false;
 begin perform public.submit_tourist_review(c.booking_id,5::smallint,null);
 exception when unique_violation then v_rejected:=true;end;
 perform pg_temp.tour_check(v_rejected,'duplicate review rejected');
 perform set_config('request.jwt.claim.sub',c.tourist_id::text,true);
 perform pg_temp.tour_check((public.get_tourist_rating_summary(c.tourist_id)->>'total_reviews')::integer>=1,'tourist reads separate reputation summary');
 perform set_config('request.jwt.claim.sub',c.subtenant_id::text,true);
 v_report:=public.get_tour_operations_report('2026-09-28 00:00+00','2026-09-29 00:00+00','Baliwag');
 perform pg_temp.tour_check((v_report->>'tourist_reviews')::integer>=1,'municipal report includes Driver-to-Tourist review');
 perform pg_temp.tour_check((v_report->>'additional_waiting_fees')::numeric=40,'municipal report retains finalized obligation 40 after settlement');
 perform set_config('request.jwt.claim.sub',c.main_id::text,true);
 v_report:=public.get_tour_operations_report('2026-09-28 00:00+00','2026-09-29 00:00+00','Baliwag');
 perform pg_temp.tour_check((v_report->>'additional_waiting_fees')::numeric=40,'provincial municipality breakdown retains finalized 40');
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
select jsonb_build_object('status','PASS','checks',(select count(*) from tour_gate_results),
 'ui_gps_slide_dropoff','NOT_LIVE_TESTED','notifications_delivery','NOT_LIVE_TESTED',
 'pdf_export','NOT_LIVE_TESTED') as tour_feature_postdeploy_gate;
