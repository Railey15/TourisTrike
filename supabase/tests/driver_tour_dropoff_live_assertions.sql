-- Run only within a rollback transaction after tour_payment_live_fixture.sql
-- and tour_payment_live_assertions.sql. All writes target disposable fixture
-- bookings; no real Driver records, rates, receipts, or ledger rows are edited.
reset role;
select set_config('request.jwt.claim.sub','',true);

do $$
declare c tour_gate_context; v_assignment uuid;
begin
  select * into strict c from tour_gate_context;
  select id into strict v_assignment from public.booking_drivers
    where booking_id=c.booking_id and driver_id=c.driver_id;
  perform set_config('touristrike.journey_rpc','true',true);
  perform set_config('touristrike.driver_slide','true',true);
  perform set_config('touristrike.manual_lifecycle_reason','Rollback-only drop-off gate fixture',true);
  perform set_config('request.jwt.claim.sub',c.driver_id::text,true);
  update public.booking_drivers set journey_state='stop_done' where id=v_assignment;
end $$;

select set_config('request.jwt.claim.role','authenticated',true);
set local role authenticated;
do $$
declare c tour_gate_context; v_gate jsonb; v_denied boolean;
begin
  select * into strict c from tour_gate_context;
  perform set_config('request.jwt.claim.sub',c.driver_id::text,true);
  v_gate:=public.get_driver_tour_payment_gate(c.booking_id);
  perform pg_temp.tour_check((v_gate->>'total_remaining')::numeric=0
    and (v_gate->>'payment_satisfied')::boolean,'confirmed 40 unlocks authoritative drop-off gate');
  perform pg_temp.tour_check((v_gate->>'finalized_waiting')::numeric=40,'gate preserves finalized waiting history');
  v_denied:=false;
  begin perform public.get_driver_tour_payment_gate(c.foreign_booking_id);
  exception when insufficient_privilege then v_denied:=true;end;
  perform pg_temp.tour_check(v_denied,'drop-off payment RPC rejects foreign booking');
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);

-- Exercise current positive debt plus a previously confirmed proof. These are
-- synthetic contradictory states in this transaction, never real submissions.
do $$
declare c tour_gate_context; v_amount numeric; v_denied boolean; v_gate jsonb;
begin
  select * into strict c from tour_gate_context;
  foreach v_amount in array array[750::numeric,40,1390] loop
    update public.package_bookings set remaining_balance=v_amount where id=c.booking_id;
    perform set_config('request.jwt.claim.sub',c.driver_id::text,true);
    v_gate:=public.get_driver_tour_payment_gate(c.booking_id);
    perform pg_temp.tour_check(not (v_gate->>'payment_satisfied')::boolean,
      'positive debt locks gate '||v_amount);
    v_denied:=false;
    begin perform public.advance_driver_journey_state(c.booking_id,'en_route_dropoff');
    exception when raise_exception then
      if sqlerrm like '%REMAINING_BALANCE_NOT_CONFIRMED%' then v_denied:=true;else raise;end if;
    end;
    perform pg_temp.tour_check(v_denied,'direct RPC rejects stale confirmed proof with debt '||v_amount);
    perform pg_temp.tour_check((select journey_state='stop_done' from public.booking_drivers
      where booking_id=c.booking_id and driver_id=c.driver_id),'denied drop-off keeps state '||v_amount);
    perform set_config('request.jwt.claim.sub','',true);
  end loop;
  update public.package_bookings set remaining_balance=0 where id=c.booking_id;
end $$;

-- A zero in the booking is insufficient while a positive requirement remains
-- pending. Do not fabricate confirmed provider/cash receipts to pass this gate.
do $$
declare c tour_gate_context; v_denied boolean;
begin
  select * into strict c from tour_gate_context;
  update public.booking_payment_requirements set status='required',satisfied_by_payment_record_id=null
    where booking_id=c.booking_id and payment_stage='remaining_balance';
  perform set_config('request.jwt.claim.sub',c.driver_id::text,true);
  perform pg_temp.tour_check(not (public.get_driver_tour_payment_gate(c.booking_id)->>'payment_satisfied')::boolean,
    'zero balance with unsatisfied positive requirement stays locked');
  v_denied:=false;
  begin perform public.advance_driver_journey_state(c.booking_id,'en_route_dropoff');
  exception when raise_exception then
    if sqlerrm like '%REMAINING_BALANCE_NOT_CONFIRMED%' then v_denied:=true;else raise;end if;
  end;
  perform pg_temp.tour_check(v_denied,'zero-balance stale client cannot bypass requirement');
  perform set_config('request.jwt.claim.sub',c.driver_id::text,true);
  update public.booking_payment_requirements set status='satisfied',satisfied_by_payment_record_id=c.new_payment_id
    where booking_id=c.booking_id and payment_stage='remaining_balance';
end $$;

set local role authenticated;
do $$
declare c tour_gate_context; v_result jsonb;
begin
  select * into strict c from tour_gate_context;
  perform set_config('request.jwt.claim.sub',c.driver_id::text,true);
  v_result:=public.advance_driver_tour_action(c.booking_id,'stop_done',0);
  perform pg_temp.tour_check(v_result->>'journey_state'='en_route_dropoff','settled deliberate slide starts drop-off');
  v_result:=public.advance_driver_tour_action(c.booking_id,'stop_done',0);
  perform pg_temp.tour_check((v_result->>'no_op')::boolean,'duplicate drop-off slide is idempotent');
  perform pg_temp.tour_check((select status<>'completed' from public.package_bookings where id=c.booking_id),'drop-off navigation does not complete tour');
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
do $$
declare c tour_gate_context;
begin
  select * into strict c from tour_gate_context;
  perform pg_temp.tour_check((select to_jsonb(p)=c.old_payment from public.payment_records p where id=c.old_payment_id),
    'drop-off gate keeps historical receipt unchanged');
  perform pg_temp.tour_check((select additional_amount=40 and status='finalized' from public.booking_stop_waiting_charges
    where itinerary_item_id=c.item_id),'drop-off gate keeps finalized waiting ledger unchanged');
end $$;
select set_config('tour.gate.booking',(select booking_id::text from tour_gate_context),true);
set local role anon;
do $$
declare denied boolean:=false;
begin
  begin perform public.get_driver_tour_payment_gate(current_setting('tour.gate.booking')::uuid);
  exception when insufficient_privilege then denied:=true;end;
  if not denied then raise exception 'TOUR_GATE_FAILED: anonymous drop-off payment RPC';end if;
end $$;
reset role;
select jsonb_build_object('status','PASS','checks',(select count(*) from tour_gate_results),
  'physical_gps','NOT_LIVE_TESTED','real_payment_provider','NOT_LIVE_TESTED') as driver_tour_dropoff_gate;
