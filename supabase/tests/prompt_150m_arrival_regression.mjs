// In-memory PostgreSQL; runs the current observer against real journey functions.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const read = p => readFileSync(new URL(p, import.meta.url), 'utf8').replaceAll('\r\n', '\n');
const extract = (source, name) => {
  const start = source.indexOf('create or replace function public.' + name + '(');
  assert(start >= 0, name);
  return source.slice(start, source.indexOf('\n$$;', start) + 4);
};
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
let checks=0;
const check = (actual, expected, label) => { assert.deepEqual(actual, expected, label); checks++; };
const scalar = async (sql, params=[]) => Object.values((await db.query(sql,params)).rows[0])[0];
const login = user => db.query("select set_config('test.uid',$1,false)",[user]);
const fail = async (sql, params, code) => { await assert.rejects(() => db.query(sql,params),new RegExp(code)); checks++; };
const latitudeAt = (target, meters) => target + meters/6371000*180/Math.PI;
try {
  await db.exec(read('./event_driven_trip_fixture.sql'));
  await db.exec('alter table driver_live_locations add column activity_id uuid, add column speed double precision');
  const base=read('../migrations/20260831010000_transaction_lifecycle_consistency.sql');
  for (const name of ['compute_convoy_stage_progress','finalize_package_booking_if_eligible','is_booking_remaining_payment_satisfied','is_booking_itinerary_complete']) await db.exec(extract(base,name));
  for (const file of ['20260906020000_restore_booking_downpayment_check.sql','20260906000000_event_driven_trip_feedback.sql',
    '20260906010000_test_mode_live_tracking_consistency.sql','20260906030000_keep_debug_arrivals_gps_verified.sql',
    '20260906040000_centralize_driver_arrival_radius.sql','20260906050000_guard_remaining_payment_completion.sql']) await db.exec(read('../migrations/'+file));
  await db.exec(`create trigger proximity before update of journey_state on booking_drivers for each row execute function guard_live_driver_journey_proximity();
    create trigger milestones after update of journey_state on booking_drivers for each row execute function sync_driver_journey_milestones();`);
  await db.exec(read('../migrations/20260927000000_automatic_tour_progression.sql'));
  const current=read('../migrations/20261007010000_immediate_150m_auto_arrival.sql');
  await db.exec(extract(current,'driver_arrival_radius_meters'));
  await db.exec(extract(current,'observe_driver_journey_location'));
  check(await scalar('select driver_arrival_radius_meters()'),150,'one server radius is 150m');
  check(await scalar('select 150::double precision <= driver_arrival_radius_meters()'),true,'radius includes 150m');
  check(await scalar('select 151::double precision <= driver_arrival_radius_meters()'),false,'radius excludes 151m');
  await db.query("insert into profiles(id,role) values($1,'tourist'),($2,'driver'),($3,'driver'),($4,'driver'),($5,'driver'),($6,'driver'),($7,'driver'),($8,'driver'),($9,'driver'),($10,'driver')",[id(1),id(2),id(3),id(4),id(5),id(6),id(7),id(8),id(9),id(10)]);
  await db.exec("insert into tour_packages values(1,'GPS tour')");
  const baseCases = [
    {state:'en_route_pickup',target:15,arrived:'at_pickup'},
    {state:'en_route_stop',target:15.01,arrived:'at_stop'},
    {state:'en_route_dropoff',target:15.03,arrived:'at_dropoff'},
  ];
  const cases = baseCases.flatMap((c,index) => [150,149,100].map((arrivalMeters,offset) => ({
    ...c,booking:id(10+index*3+offset),activity:id(20+index*3+offset),
    assignment:id(30+index*3+offset),driver:id(2+index*3+offset),arrivalMeters,
  })));
  for (const [i,c] of cases.entries()) {
    await db.query(`insert into package_bookings(id,tourist_id,package_id,status,booking_status,required_drivers,
      scheduled_start_at,estimated_end_at,pickup_latitude,dropoff_latitude)
      values($1,$2,1,'ongoing','on_tour',1,now()-interval '1 hour',now()+interval '2 hours',15,15.03)`,[c.booking,id(1)]);
    await db.query('insert into package_activities(id,booking_id) values($1,$2)',[c.activity,c.booking]);
    await db.query('insert into booking_drivers(id,booking_id,driver_id,status,journey_state) values($1,$2,$3,$4,$5)',[c.assignment,c.booking,c.driver,'accepted',c.state]);
    await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,order_number,latitude,arrival_time,departure_time)
      values($1,$2,'First',1,15.01,'09:00','09:30'),($3,$2,'Second',2,15.02,'10:00','10:30')`,[id(40+i*2),c.booking,id(41+i*2)]);
    await login(c.driver);
    const fix = async (lat, accuracy=1, sampledAt=null,speed=0) => scalar(
      'select observe_driver_journey_location($1,$2,121,$3,$4,coalesce($5::timestamptz,clock_timestamp()))',
      [c.booking,lat,accuracy,speed,sampledAt]);
    const state = () => scalar('select journey_state from booking_drivers where id=$1',[c.assignment]);
    if (i === 0) {
      await db.query("update booking_drivers set status='pending' where id=$1",[c.assignment]);
      await fail('select observe_driver_journey_location($1,15,121,1,0,now())',[c.booking],'NOT_ASSIGNED_DRIVER');
      check(await state(),c.state,'unaccepted assignment does not arrive');
      await db.query("update booking_drivers set status='accepted' where id=$1",[c.assignment]);
    }
    await fix(latitudeAt(c.target,151),1,null,9);
    check(await state(),c.state,`${c.state}: 151m is outside`);
    await fix(c.target,1,new Date(Date.now()-60000).toISOString());
    check(await state(),c.state,`${c.state}: stale fix ignored`);
    await fix(c.target,80);
    check(await state(),c.state,`${c.state}: poor accuracy ignored`);
    if (c.state==='en_route_stop') {
      await fix(15.02);
      check(await state(),c.state,'later stop cannot skip current stop');
      check(await scalar('select current_stop_index from booking_drivers where id=$1',[c.assignment]),0,'current stop index unchanged');
    }
    const result=await fix(latitudeAt(c.target,c.arrivalMeters),1,null,9);
    check(result.changed,true,`${c.state}: ${c.arrivalMeters}m accepted promptly`);
    check(result.journey_state,c.arrived,`${c.state}: observer returns new state for Driver UI`);
    check(await state(),c.arrived,`${c.state}: correct arrival state`);
    check(await scalar('select tour_status from package_activities where booking_id=$1',[c.booking]),
      {en_route_pickup:'driver_arrived',en_route_stop:'at_spot',en_route_dropoff:'ready_to_complete'}[c.state],
      `${c.state}: Tourist realtime activity source updates`);
    const firstArrival = c.state==='en_route_stop'
      ? await scalar('select arrived_at from booking_driver_arrivals where booking_driver_id=$1',[c.assignment])
      : null;
    await fix(c.target);
    check(await state(),c.arrived,`${c.state}: repeated fixes cannot progress again`);
    check(await scalar("select count(*)::int from trip_status_logs where booking_id=$1 and status='gps_arrived'",[c.booking]),1,`${c.state}: one GPS arrival log`);
    if (firstArrival) {
      check(await scalar('select arrived_at from booking_driver_arrivals where booking_driver_id=$1',[c.assignment]),firstArrival,'stop arrival timestamp retained');
      check(await scalar('select count(*)::int from booking_driver_arrivals where booking_driver_id=$1',[c.assignment]),1,'stop arrival evidence unique');
    }
    check(await scalar('select count(*)::int from package_activities where booking_id=$1',[c.booking]),1,'arrival does not duplicate activity');
  }
  for (const currentIndex of [1,2]) {
    const booking=id(70+currentIndex), activity=id(75+currentIndex), assignment=id(80+currentIndex), driver=id(90+currentIndex);
    await db.query("insert into profiles(id,role) values($1,'driver')",[driver]);
    await db.query(`insert into package_bookings(id,tourist_id,package_id,status,booking_status,required_drivers,
      scheduled_start_at,estimated_end_at,pickup_latitude,dropoff_latitude)
      values($1,$2,1,'ongoing','on_tour',1,now()-interval '1 hour',now()+interval '2 hours',15,15.06)`,[booking,id(1)]);
    await db.query('insert into package_activities(id,booking_id) values($1,$2)',[activity,booking]);
    await db.query("insert into booking_drivers(id,booking_id,driver_id,status,journey_state,current_stop_index) values($1,$2,$3,'accepted','en_route_stop',$4)",[assignment,booking,driver,currentIndex]);
    for (let stop=0;stop<3;stop++) await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,order_number,latitude,arrival_time,departure_time,spot_status)
      values($1,$2,$3,$4,$5,'09:00','09:30',$6)`,[id(100+currentIndex*3+stop),booking,`Stop ${stop+1}`,stop+1,15.01+stop*0.01,stop<currentIndex?'completed':'pending']);
    await login(driver);
    const fix = lat => scalar('select observe_driver_journey_location($1,$2,121,1,0,clock_timestamp())',[booking,lat]);
    const target=15.01+currentIndex*0.01;
    await fix(15.01);
    check(await scalar('select journey_state from booking_drivers where id=$1',[assignment]),'en_route_stop',`stop ${currentIndex+1}: earlier location cannot arrive`);
    if (currentIndex===1) {
      await fix(15.03);
      check(await scalar('select journey_state from booking_drivers where id=$1',[assignment]),'en_route_stop','nearby future stop cannot arrive or skip');
    }
    check((await fix(latitudeAt(target,150))).changed,true,`stop ${currentIndex+1}: current target arrives immediately`);
    check(await scalar('select current_stop_index from booking_drivers where id=$1',[assignment]),currentIndex,'arrival does not increment itinerary index');
    check(await scalar('select count(*)::int from booking_driver_arrivals where booking_driver_id=$1',[assignment]),1,'only current stop gets arrival evidence');
    check(await scalar('select count(*)::int from booking_itinerary_items where booking_id=$1 and spot_status=$2',[booking,'completed']),currentIndex,'arrival does not complete any stop');
  }
  await login(id(90));
  await db.query("insert into profiles(id,role) values($1,'driver')",[id(90)]);
  await fail('select observe_driver_journey_location($1,15,121,1,0,now())',[cases[0].booking],'NOT_ASSIGNED_DRIVER');
  await login(id(2));
  await db.query("update package_bookings set booking_status='cancelled' where id=$1",[cases[0].booking]);
  check((await scalar('select observe_driver_journey_location($1,15,121,1,0,now())',[cases[0].booking])).changed,false,'cancelled booking cannot progress');
  await login(id(3));
  await db.query("update package_bookings set booking_status='completed' where id=$1",[cases[1].booking]);
  check((await scalar('select observe_driver_journey_location($1,15,121,1,0,now())',[cases[1].booking])).changed,false,'completed booking cannot restart');
  console.log(`PASS: ${checks} prompt 150m arrival checks`);
} finally { await db.close(); }
