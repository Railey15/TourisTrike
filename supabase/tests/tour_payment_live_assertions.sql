-- Apply inside a rollback transaction after the feature migration. This tests
-- actual backend/RLS calls with existing identities and synthetic booking rows.
do $$
declare c tour_gate_context;i public.booking_itinerary_items;v_depart timestamptz;
begin
 select * into strict c from tour_gate_context;
 select * into strict i from public.booking_itinerary_items where id=c.item_id;
 v_depart:=i.actual_arrival_time+interval '61 minutes';
 insert into public.booking_stop_waiting_charges(booking_id,itinerary_item_id,municipality,
   subtenant_id,included_minutes,arrived_at,paid_until,rate_per_interval)
 values(c.booking_id,c.item_id,'Baliwag',c.subtenant_id,60,i.actual_arrival_time,i.actual_arrival_time+interval '60 minutes',40);
 update public.booking_itinerary_items set actual_departure_time=v_depart where id=c.item_id;
 perform pg_temp.tour_check((select remaining_balance=40 and total_amount=1500 from public.package_bookings where id=c.booking_id),'net outstanding 40; package price unchanged');
 perform pg_temp.tour_check((select amount=40 and status='required' and satisfied_by_payment_record_id is null from public.booking_payment_requirements where booking_id=c.booking_id and payment_stage='remaining_balance'),'requirement 40 with old proof cleared');
 update public.booking_itinerary_items set actual_departure_time=v_depart where id=c.item_id;
 perform pg_temp.tour_check((select remaining_balance=40 from public.package_bookings where id=c.booking_id),'duplicate departure is financially idempotent');
 perform pg_temp.tour_check(not public.is_booking_remaining_payment_satisfied(c.booking_id),'old receipt cannot satisfy new waiting');
end $$;

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
set local role authenticated;
do $$
declare c tour_gate_context;v_id uuid;v_payment public.payment_records;v_retry public.payment_records;
  v_summary jsonb;v_report jsonb;v_rejected boolean;v_amount numeric;
begin
 select * into strict c from tour_gate_context;
 foreach v_id in array array[c.tourist_id,c.driver_id,c.subtenant_id,c.main_id] loop
   perform set_config('request.jwt.claim.sub',v_id::text,true);
   perform pg_temp.tour_check(public.can_read_tour_booking(c.booking_id),'legitimate actor access '||v_id::text);
   perform pg_temp.tour_check(not public.can_read_tour_booking(c.foreign_booking_id),'foreign booking denied '||v_id::text);
   perform pg_temp.tour_check((select count(*)=1 from public.booking_stop_waiting_charges where booking_id=c.booking_id),'waiting RLS authorized actor '||v_id::text);
   v_summary:=public.get_booking_waiting_summary(c.booking_id);
   perform pg_temp.tour_check((v_summary->>'total_remaining')::numeric=40,'summary net remaining 40 '||v_id::text);
 end loop;
 perform set_config('request.jwt.claim.sub',c.subtenant_id::text,true);
 v_report:=public.get_tour_operations_report(clock_timestamp()-interval '1 day',clock_timestamp()+interval '1 day','Baliwag');
 perform pg_temp.tour_check((v_report->>'additional_waiting_fees')::numeric>=40,'municipal finalized-obligation report');
 perform set_config('request.jwt.claim.sub',c.main_id::text,true);
 v_report:=public.get_tour_operations_report(clock_timestamp()-interval '1 day',clock_timestamp()+interval '1 day',null);
 perform pg_temp.tour_check((v_report->>'additional_waiting_fees')::numeric>=40,'provincial finalized-obligation report');
 perform set_config('request.jwt.claim.sub',c.administrator_id::text,true);
 perform pg_temp.tour_check(not public.can_read_tour_booking(c.booking_id),'administrator follows scoped oversight; no implicit participant access');
 perform set_config('request.jwt.claim.sub',c.tourist_id::text,true);
 perform pg_temp.tour_check(public.get_municipal_tour_waiting_rate('Baliwag','Bulacan') is null,'missing approved municipality rate has no fallback');
 foreach v_amount in array array[0::numeric,-1,20,790] loop
   v_rejected:=false;
   begin
     insert into public.payment_records(booking_id,payer_id,payee_id,amount,payment_method,payment_stage,status,provider)
       values(c.booking_id,c.tourist_id,c.driver_id,v_amount,'cash','remaining_balance','pending_confirmation','manual');
   exception when raise_exception then
     if sqlerrm like '%INVALID_PAYMENT_AMOUNT%' then v_rejected:=true;else raise;end if;
   end;
   perform pg_temp.tour_check(v_rejected,'incorrect amount rejected '||v_amount::text);
 end loop;
 select * into v_payment from public.prepare_group_cash_remaining_balance(c.booking_id,'rollback-waiting-'||c.booking_id::text);
 perform pg_temp.tour_check(v_payment.amount=40 and v_payment.id<>c.old_payment_id,'legitimate 40 submission accepted as new receipt');
 select * into v_retry from public.prepare_group_cash_remaining_balance(c.booking_id,'rollback-waiting-'||c.booking_id::text);
 perform pg_temp.tour_check(v_retry.id=v_payment.id,'preparation retry reuses receipt');
 update tour_gate_context set new_payment_id=v_payment.id;
 perform set_config('request.jwt.claim.sub',c.driver_id::text,true);
 perform pg_temp.tour_check((select sum(gross_amount)=40 from public.payment_allocations where payment_record_id=v_payment.id),'new allocation totals only 40');
 perform public.confirm_group_cash_share(v_payment.id);
 perform public.confirm_group_cash_share(v_payment.id);
 perform pg_temp.tour_check((select remaining_balance=0 and total_amount=1500 from public.package_bookings where id=c.booking_id),'40 confirmation leaves zero outstanding');
 perform pg_temp.tour_check((select amount=40 and status='satisfied' and satisfied_by_payment_record_id=v_payment.id from public.booking_payment_requirements where booking_id=c.booking_id and payment_stage='remaining_balance'),'new receipt satisfies current stage');
 perform pg_temp.tour_check((select sum(amount)=790 from public.payment_records where booking_id=c.booking_id and payment_stage='remaining_balance' and status='confirmed'),'confirmed remaining collections total 790');
 perform pg_temp.tour_check((select additional_amount=40 and status='finalized' from public.booking_stop_waiting_charges where itinerary_item_id=c.item_id),'waiting ledger 40 survives collection');
 perform pg_temp.tour_check((select to_jsonb(p)=c.old_payment from public.payment_records p where id=c.old_payment_id),'historical synthetic 750 receipt unchanged');
 perform pg_temp.tour_check((select jsonb_agg(to_jsonb(a) order by id)=c.old_allocations from public.payment_allocations a where payment_record_id=c.old_payment_id),'historical synthetic allocations unchanged');
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
select set_config('tour.gate.booking',(select booking_id::text from tour_gate_context),true);
set local role anon;
do $$
declare denied boolean:=false;
begin
 begin perform public.get_booking_waiting_summary(current_setting('tour.gate.booking')::uuid);
 exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'TOUR_GATE_FAILED: anonymous feature RPC access';end if;
end $$;
reset role;
select jsonb_build_object('status','PASS','checks',(select count(*) from tour_gate_results),
 'original_obligation',750,'original_confirmed',750,'new_waiting',40,
 'required_payment',40,'legitimate_payment','ACCEPTED','final_outstanding',0,
 'auth_users_mutated',false,'municipality_rates_configured',false) as tour_payment_live_gate;
