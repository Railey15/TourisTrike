// GPS arrivals and explicit departure slides in isolated PostgreSQL.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const read = path => readFileSync(new URL(path, import.meta.url), 'utf8').replaceAll('\r\n','\n');
const old = read('../migrations/20260927000000_automatic_tour_progression.sql');
const next = read('../migrations/20260928000000_tour_stay_waiting_and_tourist_reviews.sql');
const functionSql = (source,name) => {
  const start=source.indexOf(`create or replace function public.${name}(`);
  assert(start>=0,name);
  const end=source.indexOf('$$;',start);
  assert(end>start,name);
  return source.slice(start,end+3);
};
const uuid=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const booking=uuid(40), activity=uuid(41), assignment=uuid(42), driver=uuid(2), tourist=uuid(1);
let checks=0;
const check=(actual,expected,label)=>{assert.deepEqual(actual,expected,label);checks++;};
const scalar=async(sql,params=[])=>Object.values((await db.query(sql,params)).rows[0])[0];
const state=()=>scalar('select journey_state from booking_drivers where id=$1',[assignment]);
const login=user=>db.query("select set_config('test.uid',$1,false)",[user]);
const tick=()=>db.query(`update driver_journey_evidence set
  first_sample_at=first_sample_at-interval '5 seconds',
  first_received_at=first_received_at-interval '5 seconds',
  last_sample_at=last_sample_at-interval '5 seconds',
  last_received_at=last_received_at-interval '5 seconds'`);
const fix=lat=>db.query(`select observe_driver_journey_location($1,$2,121,10,0,clock_timestamp())`,[booking,lat]);
const arrive=async(lat)=>{for(let i=0;i<4;i++){await tick();await fix(lat);}};
const slide=(expected,index)=>db.query('select advance_driver_tour_action($1,$2,$3) as result',[booking,expected,index]);

try {
  await db.exec(read('./event_driven_trip_fixture.sql'));
  await db.exec('alter table driver_live_locations add column activity_id uuid, add column speed double precision');
  const base=read('../migrations/20260831010000_transaction_lifecycle_consistency.sql');
  for(const name of ['compute_convoy_stage_progress','finalize_package_booking_if_eligible',
    'is_booking_remaining_payment_satisfied','is_booking_itinerary_complete'])
    await db.exec(functionSql(base,name));
  for(const file of ['20260906020000_restore_booking_downpayment_check.sql',
    '20260906000000_event_driven_trip_feedback.sql',
    '20260906010000_test_mode_live_tracking_consistency.sql',
    '20260906030000_keep_debug_arrivals_gps_verified.sql',
    '20260906040000_centralize_driver_arrival_radius.sql',
    '20260906050000_guard_remaining_payment_completion.sql'])
    await db.exec(read('../migrations/'+file));
  await db.exec(`create trigger proximity before update of journey_state on booking_drivers
    for each row execute function guard_live_driver_journey_proximity();
    create trigger milestones after update of journey_state on booking_drivers
    for each row execute function sync_driver_journey_milestones();`);
  await db.exec(old);
  await db.exec(`create function public.required_booking_driver_roster(uuid)
    returns setof booking_drivers language sql stable as $$
    select * from public.booking_drivers where booking_id=$1 and status in ('accepted','completed') $$`);
  for(const name of ['guard_verified_journey_transition','observe_driver_journey_location',
    'complete_current_itinerary_item','advance_driver_tour_action','align_convoy_stop_arrival'])
    await db.exec(functionSql(next,name));
  await db.exec(`create trigger align_convoy_stop_arrival before update of actual_arrival_time
    on booking_itinerary_items for each row execute function align_convoy_stop_arrival()`);
  await db.query("insert into profiles(id,role) values($1,'tourist'),($2,'driver')",[tourist,driver]);
  await db.exec("insert into tour_packages values(1,'Slide tour')");
  await db.query(`insert into package_bookings(id,tourist_id,package_id,status,booking_status,
    required_drivers,scheduled_start_at,estimated_end_at,pickup_latitude,
    dropoff_latitude,remaining_balance) values
    ($1,$2,1,'ongoing','on_tour',1,now()-interval '1 hour',now()+interval '2 hours',15,15.03,0)`,[booking,tourist]);
  await db.query('insert into package_activities(id,booking_id) values($1,$2)',[activity,booking]);
  await db.query(`insert into booking_drivers(id,booking_id,driver_id,status,journey_state)
    values($1,$2,$3,'accepted','en_route_stop')`,[assignment,booking,driver]);
  await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,
    order_number,latitude,arrival_time,departure_time,estimated_stay_duration_minutes)
    values($1,$2,'First',1,15.01,'09:00','10:00',60),
      ($3,$2,'Second',2,15.02,'10:00','11:00',60)`,[uuid(43),booking,uuid(44)]);
  await db.query(`insert into payment_records(id,booking_id,status,payment_stage,amount)
    values($1,$2,'confirmed','remaining_balance',1)`,[uuid(45),booking]);
  await login(driver);
  await arrive(15.01);
  check(await state(),'at_stop','GPS arrives only at current stop');
  await arrive(15.03);
  check(await state(),'at_stop','GPS movement cannot depart a stop');
  await slide('at_stop',0);
  check(await state(),'en_route_stop','slide departs and navigates to next stop');
  check(Number(await scalar('select current_stop_index from booking_drivers where id=$1',[assignment])),1,'slide advances one stop');
  check((await slide('at_stop',0)).rows[0].result.no_op,true,'duplicate callback is idempotent');
  await arrive(15.02);
  check(await state(),'at_stop','second stop arrives automatically');
  await slide('at_stop',1);
  check(await state(),'en_route_dropoff','final itinerary slide navigates to drop-off');
  await arrive(15.03);
  check(await state(),'at_dropoff','GPS drop-off arrival does not complete tour');
  await slide('at_dropoff',1);
  check(await state(),'completed','final slide completes exactly once');
  check((await slide('at_dropoff',1)).rows[0].result.no_op,true,'duplicate completion is idempotent');
  await db.query("insert into profiles(id,role) values($1,'driver')",[uuid(9)]);
  await db.query(`insert into package_bookings(id,tourist_id,package_id,status,booking_status,
    required_drivers,scheduled_start_at,estimated_end_at,remaining_balance)
    values($1,$2,1,'ongoing','on_tour',2,now()-interval '1 hour',
      now()+interval '2 hours',0)`,[uuid(50),tourist]);
  await db.query(`insert into booking_drivers(id,booking_id,driver_id,status,journey_state)
    values($1,$2,$3,'accepted','at_stop'),($4,$2,$5,'accepted','at_stop')`,
    [uuid(51),uuid(50),driver,uuid(52),uuid(9)]);
  await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,
    order_number,latitude,arrival_time,departure_time) values
    ($1,$2,'Convoy stop',1,15.01,'09:00','10:00')`,[uuid(53),uuid(50)]);
  await db.query(`insert into booking_driver_arrivals(booking_driver_id,itinerary_item_id,
    arrived_at) values($1,$2,'2026-09-27 09:00:00+00')`,[uuid(51),uuid(53)]);
  await db.query(`update booking_itinerary_items set actual_arrival_time=now() where id=$1`,[uuid(53)]);
  check(await scalar('select actual_arrival_time from booking_itinerary_items where id=$1',[uuid(53)]),null,
    'first convoy arrival does not start shared paid stay');
  await db.query(`insert into booking_driver_arrivals(booking_driver_id,itinerary_item_id,
    arrived_at) values($1,$2,'2026-09-27 09:03:00+00')`,[uuid(52),uuid(53)]);
  await db.query(`update booking_itinerary_items set actual_arrival_time=now() where id=$1`,[uuid(53)]);
  check(await scalar('select actual_arrival_time from booking_itinerary_items where id=$1',[uuid(53)]),
    new Date('2026-09-27T09:03:00.000Z'),'last required driver starts shared paid stay');
  console.log(`PASS: ${checks} explicit tour-slide SQL checks`);
} finally {
  await db.close();
}
