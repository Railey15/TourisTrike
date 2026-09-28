// Isolated PostgreSQL journey/payment guard tests; never touches live records.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const read = p => readFileSync(new URL(p, import.meta.url), 'utf8').replaceAll('\r\n','\n');
const extract = (source,name) => {
  const start=source.indexOf(`create or replace function public.${name}(`);
  const end=source.indexOf('$$;',start);
  assert(start>=0 && end>start,name);
  return source.slice(start,end+3);
};
const feature=read('../migrations/20260928000000_tour_stay_waiting_and_tourist_reviews.sql');
const forward=read('../migrations/20260928010000_driver_tour_dropoff_payment_gate.sql');
const uuid=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const driver=uuid(1),tourist=uuid(2),outsider=uuid(3);
let serial=100, checks=0;
const check=(actual,expected,label)=>{assert.deepEqual(actual,expected,label);checks++;};
const scalar=async(sql,params=[])=>Object.values((await db.query(sql,params)).rows[0])[0];
const login=user=>db.query("select set_config('test.uid',$1,false)",[user]);
const denied=async(sql,params,pattern='REMAINING_BALANCE_NOT_CONFIRMED')=>{
  await assert.rejects(()=>db.query(sql,params),new RegExp(pattern));checks++;
};
const state=b=>scalar('select journey_state from booking_drivers where booking_id=$1',[b.bid]);
const debt=b=>scalar('select remaining_balance from package_bookings where id=$1',[b.bid]).then(Number);
const slide=(b,expected,index=0)=>scalar('select advance_driver_tour_action($1,$2,$3)',[b.bid,expected,index]);
const gate=b=>scalar('select get_driver_tour_payment_gate($1)',[b.bid]);
const direct=b=>db.query("select advance_driver_journey_state($1,'en_route_dropoff')",[b.bid]);

try {
  await db.exec(read('./event_driven_trip_fixture.sql'));
  await db.exec('alter table driver_live_locations add column activity_id uuid, add column speed double precision');
  const base=read('../migrations/20260831010000_transaction_lifecycle_consistency.sql');
  for(const name of ['compute_convoy_stage_progress','finalize_package_booking_if_eligible',
    'is_booking_remaining_payment_satisfied','is_booking_itinerary_complete'])
    await db.exec(extract(base,name));
  for(const file of ['20260906020000_restore_booking_downpayment_check.sql',
    '20260906000000_event_driven_trip_feedback.sql',
    '20260906010000_test_mode_live_tracking_consistency.sql',
    '20260906030000_keep_debug_arrivals_gps_verified.sql',
    '20260906040000_centralize_driver_arrival_radius.sql',
    '20260906050000_guard_remaining_payment_completion.sql']) await db.exec(read('../migrations/'+file));
  await db.exec(`create trigger proximity before update of journey_state on booking_drivers
    for each row execute function guard_live_driver_journey_proximity();
    create trigger milestones after update of journey_state on booking_drivers
    for each row execute function sync_driver_journey_milestones();`);
  await db.exec(read('../migrations/20260927000000_automatic_tour_progression.sql'));
  await db.exec(`create function public.required_booking_driver_roster(uuid)
    returns setof booking_drivers language sql stable as $$
    select * from public.booking_drivers where booking_id=$1 and status in ('accepted','completed') $$;
    alter function public.is_package_booking_participant(uuid) set search_path=public;
    alter table package_bookings add column municipality text default 'Fixture City',
      add column province text default 'Bulacan',add column tour_waiting_subtenant_id uuid,
      add column tour_waiting_rate_snapshot numeric;
    alter table booking_payment_requirements add column satisfied_at timestamptz,
      add column updated_at timestamptz;
    create function public.can_read_tour_booking(uuid) returns boolean language sql stable as $$
      select public.is_package_booking_participant($1) $$;
    create function public.resolve_tour_waiting_rate(text,text)
      returns table(subtenant_id uuid,rate numeric) language sql as $$ select null::uuid,null::numeric $$;
    create table booking_stop_waiting_charges(id uuid default gen_random_uuid(),booking_id uuid,
      itinerary_item_id uuid,municipality text,arrived_at timestamptz,included_minutes integer,
      paid_until timestamptz,departed_at timestamptz,rate_per_interval numeric,
      overtime_seconds integer default 0,chargeable_intervals integer default 0,
      additional_amount numeric default 0,status text default 'active',finalized_at timestamptz,
      updated_at timestamptz,unique(booking_id,itinerary_item_id));`);
  for(const name of ['guard_verified_journey_transition','observe_driver_journey_location',
    'complete_current_itinerary_item','advance_driver_tour_action','align_convoy_stop_arrival',
    'finalize_booking_stop_waiting_charge','get_booking_waiting_summary']) await db.exec(extract(feature,name));
  await db.exec(`create trigger waiting_finalize after update of actual_departure_time
    on booking_itinerary_items for each row execute function finalize_booking_stop_waiting_charge()`);
  await db.exec(forward);
  await db.query("insert into profiles(id,role) values($1,'driver'),($2,'tourist'),($3,'driver')",[driver,tourist,outsider]);
  await db.exec("insert into tour_packages values(1,'Payment-gated tour')");

  const seed=async({balance=750,waiting=0,receiptStatus=null,requirementStatus='required',proofAmount=balance}={})=>{
    const bid=uuid(serial++),assignment=uuid(serial++),item=uuid(serial++),activity=uuid(serial++),receipt=uuid(serial++);
    await login('');
    await db.query(`insert into package_bookings(id,tourist_id,package_id,status,booking_status,
      required_drivers,scheduled_start_at,remaining_balance,downpayment_amount,total_amount)
      values($1,$2,1,'ongoing','on_tour',1,now()-interval '1 hour',$3,0,1500)`,[bid,tourist,balance]);
    await db.query('insert into package_activities(id,booking_id) values($1,$2)',[activity,bid]);
    await db.query(`insert into booking_drivers(id,booking_id,driver_id,status,journey_state)
      values($1,$2,$3,'accepted','at_stop')`,[assignment,bid,driver]);
    await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,order_number,
      actual_arrival_time,estimated_stay_duration_minutes,latitude,longitude)
      values($1,$2,'Final tourist destination',1,clock_timestamp()-interval '61 minutes',60,15,121)`,[item,bid]);
    await db.query(`insert into booking_driver_arrivals(booking_driver_id,itinerary_item_id,arrived_at)
      values($1,$2,clock_timestamp()-interval '61 minutes')`,[assignment,item]);
    await db.query(`insert into booking_stop_waiting_charges(booking_id,itinerary_item_id,
      municipality,arrived_at,paid_until,included_minutes,rate_per_interval)
      values($1,$2,'Fixture City',clock_timestamp()-interval '61 minutes',
        clock_timestamp()-interval '1 minute',60,$3)`,[bid,item,waiting]);
    await db.query(`insert into booking_payment_requirements(booking_id,payment_stage,amount,status,satisfied_by_payment_record_id)
      values($1,'remaining_balance',$2,$3,$4)`,[bid,proofAmount,requirementStatus,receiptStatus?receipt:null]);
    if(receiptStatus) await db.query(`insert into payment_records(id,booking_id,payment_stage,status,amount)
      values($1,$2,'remaining_balance',$3,$4)`,[receipt,bid,receiptStatus,proofAmount]);
    await login(driver);
    return {bid,assignment,item,receipt};
  };

  for(const [name,input,expected] of [
    ['package only',{balance:750},750],
    ['waiting only',{balance:0,waiting:40},40],
    ['package and waiting',{balance:1350,waiting:40},1390],
    ['pending payment',{balance:750,receiptStatus:'pending_confirmation'},750],
    ['failed payment',{balance:750,receiptStatus:'failed'},750],
    ['confirmed history with residual debt',{balance:10,receiptStatus:'confirmed',requirementStatus:'satisfied',proofAmount:750},10],
  ]) {
    const b=await seed(input);
    const result=await slide(b,'at_stop');
    check(result.final_stop_finalized,true,name+' leaves final stop separately');
    check(await state(b),'stop_done',name+' remains before drop-off');
    check(await debt(b),expected,name+' authoritative debt includes finalized waiting');
    check((await gate(b)).payment_satisfied,false,name+' RPC gate locked');
    await denied("select advance_driver_journey_state($1,'en_route_dropoff')",[b.bid]);
    const attempt=await slide(b,'stop_done');
    check(attempt.waiting_for_convoy_or_payment,true,name+' slide cannot bypass unpaid gate');
    check(await state(b),'stop_done',name+' denied slide keeps driver state');
    check((await slide(b,'at_stop')).no_op,true,name+' duplicate departure does not advance');
    check(await debt(b),expected,name+' duplicate finalization leaves debt intact');
  }
  const b=await seed({balance:0,waiting:40,receiptStatus:'confirmed',requirementStatus:'satisfied',proofAmount:750});
  const oldReceipt=await scalar('select to_jsonb(p) from payment_records p where id=$1',[b.receipt]);
  await slide(b,'at_stop');
  check(await debt(b),40,'paid 750 plus new waiting 40 only owes 40');
  const waiting=await scalar('select to_jsonb(c) from booking_stop_waiting_charges c where booking_id=$1',[b.bid]);
  await denied("select advance_driver_journey_state($1,'en_route_dropoff')",[b.bid]);
  // Emulate a committed backend confirmation in this isolated journey fixture.
  // Actual cash/provider collection functions are exercised in the separate
  // financial suite and rollback-only linked preflight, never as a real payment.
  const newReceipt=uuid(serial++);
  await db.query(`insert into payment_records(id,booking_id,payment_stage,status,amount)
    values($1,$2,'remaining_balance','confirmed',40)`,[newReceipt,b.bid]);
  await db.query('update package_bookings set remaining_balance=0 where id=$1',[b.bid]);
  await db.query(`update booking_payment_requirements set status='satisfied',
    satisfied_by_payment_record_id=$2 where booking_id=$1`,[b.bid,newReceipt]);
  check((await gate(b)).payment_satisfied,true,'authoritative confirmation unlocks read RPC');
  check((await gate(b)).total_remaining,0,'current obligation is zero');
  await slide(b,'stop_done');
  check(await state(b),'en_route_dropoff','separate paid slide begins drop-off');
  check((await slide(b,'stop_done')).no_op,true,'duplicate drop-off slide makes one transition');
  check(await scalar('select to_jsonb(p) from payment_records p where id=$1',[b.receipt]),oldReceipt,'historical payment unchanged');
  check(await scalar('select to_jsonb(c) from booking_stop_waiting_charges c where booking_id=$1',[b.bid]),waiting,'waiting ledger unchanged after settlement/drop-off');
  check(Number(await scalar('select total_amount from package_bookings where id=$1',[b.bid])),1500,'package price unchanged');

  const zero=await seed({balance:0});
  await slide(zero,'at_stop');
  check(await state(zero),'stop_done','zero debt still needs a separate deliberate drop-off slide');
  check((await gate(zero)).payment_satisfied,true,'no positive payment obligation can drop off');
  await direct(zero);
  check(await state(zero),'en_route_dropoff','direct RPC allowed only with current settlement');

  const inconsistent=await seed({balance:0,proofAmount:750,receiptStatus:'pending_confirmation'});
  await slide(inconsistent,'at_stop');
  check((await gate(inconsistent)).payment_satisfied,false,'local zero with pending requirement cannot unlock');
  await denied("select advance_driver_journey_state($1,'en_route_dropoff')",[inconsistent.bid]);
  // The existing predicate accepts this stale satisfied proof, while the new
  // transition guard independently rejects the positive current obligation.
  const stale=await seed({balance:10,receiptStatus:'confirmed',requirementStatus:'satisfied',proofAmount:750});
  await slide(stale,'at_stop');
  check(await scalar('select is_booking_remaining_payment_satisfied($1)',[stale.bid]),true,'legacy proof alone can be stale');
  await denied("select advance_driver_journey_state($1,'en_route_dropoff')",[stale.bid]);
  await db.query("select set_config('touristrike.debug_progression_bypass','true',false)");
  await db.query('update package_bookings set test_mode=true where id=$1',[stale.bid]);
  await denied("select advance_driver_journey_state($1,'en_route_dropoff')",[stale.bid]);
  await db.query("select set_config('touristrike.debug_progression_bypass','false',false)");
  await login(outsider);
  await denied('select get_driver_tour_payment_gate($1)',[b.bid],'BOOKING_ACCESS_DENIED');
  await denied("select advance_driver_tour_action($1,'stop_done',0)",[b.bid],'NOT_ASSIGNED_DRIVER');
  await db.exec('set role anon');
  await denied('select get_driver_tour_payment_gate($1)',[b.bid],'permission denied');
  await db.exec('reset role');

  // End-to-end state transitions with synthetic GPS evidence and fixture time.
  // This verifies the actual arrival RPC, not physical GPS/geofence behavior.
  await login(driver);
  const flow=await seed({balance:750,waiting:40});
  await db.query("select set_config('touristrike.journey_rpc','true',false)");
  await db.query("update booking_drivers set journey_state='en_route_pickup' where id=$1",[flow.assignment]);
  await db.query("update booking_itinerary_items set spot_status='pending',actual_arrival_time=null where id=$1",[flow.item]);
  await db.query('delete from booking_driver_arrivals where booking_driver_id=$1',[flow.assignment]);
  await db.query("select set_config('touristrike.journey_rpc','false',false)");
  const arrive=async()=>{
    for(let i=0;i<4;i++) {
      await db.exec(`update driver_journey_evidence set first_sample_at=first_sample_at-interval '5 seconds',
        first_received_at=first_received_at-interval '5 seconds',last_sample_at=last_sample_at-interval '5 seconds',
        last_received_at=last_received_at-interval '5 seconds'`);
      await db.query('select observe_driver_journey_location($1,15,121,10,0,clock_timestamp())',[flow.bid]);
    }
  };
  await arrive();
  check(await state(flow),'at_pickup','mocked GPS confirms pickup arrival');
  await slide(flow,'at_pickup');
  check(await state(flow),'boarded','pickup slide confirms existing boarded transition');
  check((await slide(flow,'at_pickup')).no_op,true,'duplicate pickup cannot confirm twice');
  await slide(flow,'boarded');
  check(await state(flow),'en_route_stop','start slide begins first destination');
  check((await slide(flow,'boarded')).no_op,true,'duplicate start cannot start twice');
  await arrive();
  check(await state(flow),'at_stop','mocked GPS automatically arrives at destination');
  check(Number(await scalar('select estimated_stay_duration_minutes from booking_itinerary_items where id=$1',[flow.item])),60,'booked stay survives GPS arrival');
  await slide(flow,'at_stop');
  check(await state(flow),'stop_done','final departure slide preserves final phase');
  check(await debt(flow),790,'full flow finalizes exact package 750 plus waiting 40');
  await denied("select advance_driver_journey_state($1,'en_route_dropoff')",[flow.bid]);
  const flowPayment=uuid(serial++);
  await db.query(`insert into payment_records(id,booking_id,payment_stage,status,amount)
    values($1,$2,'remaining_balance','confirmed',790)`,[flowPayment,flow.bid]);
  await db.query('update package_bookings set remaining_balance=0 where id=$1',[flow.bid]);
  await db.query(`update booking_payment_requirements set status='satisfied',satisfied_by_payment_record_id=$2
    where booking_id=$1`,[flow.bid,flowPayment]);
  await slide(flow,'stop_done');
  check(await state(flow),'en_route_dropoff','paid flow navigates toward drop-off');
  await arrive();
  check(await state(flow),'at_dropoff','mocked drop-off arrival never completes automatically');
  await slide(flow,'at_dropoff');
  check(await state(flow),'completed','completion slide completes after settled drop-off');
  check((await slide(flow,'at_dropoff')).no_op,true,'duplicate completion cannot complete twice');

  const next=await seed({balance:0,waiting:40});
  await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,order_number)
    values($1,$2,'Following destination',2)`,[uuid(serial++),next.bid]);
  await slide(next,'at_stop');
  check(await state(next),'en_route_stop','non-final slide navigates to the following stop');
  check(Number(await scalar('select current_stop_index from booking_drivers where id=$1',[next.assignment])),1,'non-final slide advances exactly one stop');
  check((await slide(next,'at_stop')).no_op,true,'duplicate next-stop slide cannot skip two stops');
  check(await debt(next),40,'non-final waiting finalizes once without prematurely blocking next stop');

  const secondDriver=uuid(9),shared=await seed({balance:0,waiting:40});
  await db.query("insert into profiles(id,role) values($1,'driver')",[secondDriver]);
  await db.query('update package_bookings set required_drivers=2 where id=$1',[shared.bid]);
  const secondAssignment=uuid(serial++);
  await db.query(`insert into booking_drivers(id,booking_id,driver_id,status,journey_state)
    values($1,$2,$3,'accepted','at_stop')`,[secondAssignment,shared.bid,secondDriver]);
  await db.query(`insert into booking_driver_arrivals(booking_driver_id,itinerary_item_id,arrived_at)
    values($1,$2,clock_timestamp()-interval '61 minutes')`,[secondAssignment,shared.item]);
  const firstDeparture=await slide(shared,'at_stop');
  check(firstDeparture.final_stop_finalized,false,'first convoy departure waits for the shared stop to finalize');
  check(await debt(shared),0,'first convoy departure does not bill shared waiting early');
  await login(secondDriver);
  const lastDeparture=await slide(shared,'at_stop');
  check(lastDeparture.final_stop_finalized,true,'last convoy departure finalizes shared stop');
  check(await debt(shared),40,'last convoy departure bills shared waiting exactly once');
  check((await slide(shared,'at_stop')).no_op,true,'repeated convoy departure is idempotent');
  check(await debt(shared),40,'repeated convoy departure cannot duplicate financial debt');
  await denied("select advance_driver_journey_state($1,'en_route_dropoff')",[shared.bid]);

  console.log(`PASS: ${checks} driver tour drop-off/payment SQL checks`);
} catch (error) {
  console.error(JSON.stringify({message:error.message,where:error.where}));
  process.exitCode=1;
} finally { await db.close(); }
