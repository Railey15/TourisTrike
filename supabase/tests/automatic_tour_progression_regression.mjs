// In-memory PostgreSQL; never connects to or changes the linked project.
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
let checks = 0;
const check = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };
const scalar = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const fail = async (sql, params, code) => { await assert.rejects(() => db.query(sql, params), new RegExp(code)); checks++; };
const id = n => '00000000-0000-0000-0000-' + String(n).padStart(12, '0');
const tourist=id(1), driver=id(2), other=id(3);
let booking=id(10), activity=id(11), assignment=id(12);
const login = user => db.query("select set_config('test.uid',$1,false)",[user]);
const state = () => scalar('select journey_state from booking_drivers where id=$1',[assignment]);
// Advance only stored timestamps to model time between fixes without sleeping.
// Counts, positions, transitions, locks and constraints run in actual SQL.
const tick = async (seconds=5) => db.query(`update driver_journey_evidence set
  first_sample_at=first_sample_at-make_interval(secs=>$1),first_received_at=first_received_at-make_interval(secs=>$1),
  last_sample_at=last_sample_at-make_interval(secs=>$1),last_received_at=last_received_at-make_interval(secs=>$1)`,[seconds]);
const fix = async (lat, speed=0, accuracy=10, sampledAt=null) => scalar(
  'select observe_driver_journey_location($1,$2,121,$3,$4,coalesce($5::timestamptz,clock_timestamp()))',
  [booking,lat,accuracy,speed,sampledAt]);
const fixes = async (lat, speed=0, count=4) => { let result; for(let i=0;i<count;i++) {await tick(); result=await fix(lat,speed);} return result; };
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
  await db.query("insert into profiles(id,role) values($1,'tourist'),($2,'driver'),($3,'driver')",[tourist,driver,other]);
  await db.exec("insert into tour_packages values(1,'GPS tour')");
  await db.query(`insert into package_bookings(id,tourist_id,package_id,status,booking_status,required_drivers,scheduled_start_at,estimated_end_at,
    pickup_latitude,dropoff_latitude) values($1,$2,1,'ongoing','on_tour',1,now()-interval '1 hour',now()+interval '2 hours',15,15.03)`,[booking,tourist]);
  await db.query('insert into package_activities(id,booking_id) values($1,$2)',[activity,booking]);
  await db.query("insert into booking_drivers(id,booking_id,driver_id,status,journey_state) values($1,$2,$3,'accepted','en_route_pickup')",[assignment,booking,driver]);
  await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,order_number,latitude,arrival_time,departure_time)
    values($1,$2,'First',1,15.01,'09:00','09:30'),($3,$2,'Second',2,15.02,'10:00','10:30')`,[id(13),booking,id(14)]);
  await login(other);
  await fail('select observe_driver_journey_location($1,15,121,10,0,now())',[booking],'NOT_ASSIGNED_DRIVER');
  await fail('select get_tour_tracking_status($1)',[booking],'NOT_BOOKING_PARTICIPANT');
  await login(tourist);
  await fail('select observe_driver_journey_location($1,15,121,10,0,now())',[booking],'NOT_ASSIGNED_DRIVER');
  await login('');
  await fail('select observe_driver_journey_location($1,15,121,10,0,now())',[booking],'UNAUTHENTICATED');
  await login(driver);
  await fail("select advance_driver_journey_state($1,'at_pickup')",[booking],'VERIFIED_GPS_OR_AUDITED_RECOVERY_REQUIRED|DRIVER_LOCATION_STALE');
  await fail('update booking_drivers set current_stop_index=1 where id=$1',[assignment],'JOURNEY_RPC_REQUIRED');
  await fail('update package_bookings set tracking_interrupted_at=now() where id=$1',[booking],'TRACKING_STATUS_SERVER_ONLY');
  check(await scalar("select has_function_privilege('anon','observe_driver_journey_location(uuid,double precision,double precision,double precision,double precision,timestamptz)','execute')"),false,'anonymous cannot ingest');
  check(await scalar("select has_function_privilege('authenticated','reconcile_stale_tour_tracking(uuid)','execute')"),false,'clients cannot reconcile arbitrary bookings');
  check(await scalar("select has_table_privilege('authenticated','driver_journey_evidence','insert,update,delete')"),false,'clients cannot forge evidence');
  check((await fix(15)).phase,'detecting_arrival','first reading only detects');
  check(await state(),'en_route_pickup','single fix never arrives');
  await fixes(15,9);
  check(await state(),'en_route_pickup','fast pass-by never arrives');
  await fixes(15.02);
  check(await state(),'en_route_pickup','passing later stop cannot advance pickup');
  await fix(15,0,80);
  check(await scalar('select sample_count from driver_journey_evidence'),0,'poor accuracy resets evidence');
  await fix(15,0,10,new Date(Date.now()-60000).toISOString());
  check(await scalar('select sample_count from driver_journey_evidence'),0,'stale fix resets evidence');
  await fix(15,0,10,new Date(Date.now()+60000).toISOString());
  check(await scalar('select sample_count from driver_journey_evidence'),0,'future fix cannot poison window');
  // Rapid distinct events cannot satisfy elapsed server time.
  await fixes(15,0,1);
  for(let i=0;i<8;i++) await fix(15);
  check(await state(),'en_route_pickup','burst cannot masquerade as dwell');
  await fixes(15);
  check(await state(),'at_pickup','accurate low-speed dwell confirms arrival');
  await fixes(15.0016,2);
  check(await state(),'at_pickup','jitter between entry/exit radii does not depart');
  await fixes(15.003,0);
  check(await state(),'at_pickup','stationary outside fixes cannot depart');
  await fixes(15.003,3);
  check(await state(),'en_route_stop','pickup departure automatically starts first stop');
  check(await scalar('select current_stop_index from booking_drivers where id=$1',[assignment]),0,'first stop remains expected');
  await fixes(15.02);
  check(await state(),'en_route_stop','later stop proximity cannot arrive at current stop');
  await fixes(15.01,8);
  check(await state(),'en_route_stop','drive-through stop is rejected');
  await fixes(15.01,0,2);
  await tick(25);
  await fix(15.01);
  check(await scalar('select sample_count from driver_journey_evidence'),1,'GPS/internet gap starts fresh dwell');
  await fixes(15.01);
  check(await state(),'at_stop','current stop arrival confirmed');
  check(await scalar('select count(*)::int from booking_driver_arrivals'),1,'actual arrival stored once');
  const saved=await scalar('select get_tour_tracking_status($1)',[booking]);
  check(saved.journey_state,'at_stop','restart restores persisted arrival');
  check(saved.current_stop_index,0,'restart restores expected index');
  const duplicateAt=await scalar('select last_sample_at::text from driver_journey_evidence');
  check((await fix(15.01,0,10,duplicateAt)).duplicate,true,'duplicate timestamp ignored');
  check(await scalar('select count(*)::int from booking_driver_arrivals'),1,'duplicate cannot emit another arrival');
  await fixes(15.013,3);
  check(await state(),'en_route_stop','verified departure activates next stop without button');
  check(await scalar('select current_stop_index from booking_drivers where id=$1',[assignment]),1,'index increments once');
  check(await scalar('select departed_at is not null from booking_driver_arrivals'),true,'actual departure stored');
  check(await scalar('select actual_departure_time is not null from booking_itinerary_items where id=$1',[id(13)]),true,'shared actual departure stored');
  check(await scalar("select arrival_time::text||'/'||departure_time::text from booking_itinerary_items where id=$1",[id(13)]),'09:00:00/09:30:00','planned times untouched');
  await fixes(15.02);
  await fixes(15.023,3);
  check(await state(),'stop_done','final stop departure preserves remaining-payment gate');
  check((await scalar('select get_tour_tracking_status($1)',[booking])).phase,'waiting_for_convoy_or_payment','UI explains payment wait');
  await db.query("insert into payment_records values($1,$2,'confirmed','remaining_balance',now(),3600)",[id(20),booking]);
  await db.query("insert into booking_payment_requirements values($1,'remaining_balance','satisfied',3600,$2)",[booking,id(20)]);
  await tick(); await fix(15.023,3);
  check(await state(),'en_route_dropoff','payment confirmation allows automatic final navigation');
  // Overdue and stopped tracking is interrupted, NEVER completed.
  await db.query("update package_bookings set scheduled_start_at=now()-interval '2 days',estimated_end_at=now()-interval '1 day' where id=$1",[booking]);
  await db.query("update booking_drivers set state_updated_at=now()-interval '1 day' where id=$1",[assignment]);
  await db.exec("update driver_journey_evidence set last_received_at=now()-interval '1 day',last_sample_at=now()-interval '1 day'");
  check(await scalar('select reconcile_stale_tour_tracking()'),1,'previous-day tour marked interrupted');
  check(await scalar('select reconcile_stale_tour_tracking()'),0,'stale reconciliation is idempotent');
  check(await state(),'en_route_dropoff','estimated end never causes completion');
  check((await scalar('select get_tour_tracking_status($1)',[booking])).interrupted_at != null,true,'restart exposes interrupted state');
  check((await scalar('select get_driver_home_overview()')).active_trips,0,'interrupted tour excluded from normal active count');
  check((await scalar('select get_driver_home_overview()')).interrupted_trips,1,'interrupted tour remains available for recovery');
  check(await scalar("select count(*)::int from trip_status_logs where status='tracking_interrupted'"),1,'interruption audit stored once');
  await tick(); await fix(15.023,3);
  check((await scalar('select get_tour_tracking_status($1)',[booking])).interrupted_at,null,'fresh tracking safely resumes expected leg');
  await fixes(15.03,6);
  check(await state(),'en_route_dropoff','passing dropoff never completes');
  await fixes(15.03);
  check(await state(),'completed','verified final dwell automatically completes');
  check(await scalar('select booking_status from package_bookings where id=$1',[booking]),'completed','canonical finalizer completes paid tour');
  check(await scalar('select completed_at is not null from booking_drivers where id=$1',[assignment]),true,'actual completion timestamp persisted');
  const logs=await scalar('select count(*)::int from trip_status_logs');
  await fix(15.03);
  check(await scalar('select count(*)::int from trip_status_logs'),logs,'completed duplicate has no lifecycle side effects');
  // A separate legacy active tour can recover manually, with strict expected-state concurrency.
  await db.query("update package_bookings set status='ongoing',booking_status='on_tour',completed_at=null where id=$1",[booking]);
  await db.exec("select set_config('touristrike.gps_transition_verified','true',false)");
  await db.query("update booking_drivers set status='accepted',journey_state='en_route_dropoff' where id=$1",[assignment]);
  await db.exec("select set_config('touristrike.gps_transition_verified','false',false)");
  await fail("select recover_driver_journey($1,'en_route_dropoff',1,'short')",[booking],'RECOVERY_REASON_REQUIRED');
  await db.exec("update driver_live_locations set updated_at=now()-interval '1 hour'");
  await fail("select recover_driver_journey($1,'en_route_dropoff',1,'GPS permission unavailable')",[booking],'DRIVER_LOCATION_STALE');
  await db.query('insert into booking_participant_live_locations values($1,$2,15.03,121,10,now())',[booking,tourist]);
  await scalar("select recover_driver_journey($1,'en_route_dropoff',1,'GPS permission unavailable')",[booking]);
  check(await state(),'at_dropoff','manual fallback needs corroborated final arrival');
  check((await scalar("select recover_driver_journey($1,'en_route_dropoff',1,'Network retry of recovery')",[booking])).no_op,true,'retry cannot confirm different state');
  await scalar("select recover_driver_journey($1,'at_dropoff',1,'Confirmed passengers alighted safely')",[booking]);
  check(await state(),'completed','audited recovery uses canonical completion');
  check(await scalar("select count(*)::int from trip_status_logs where status='manual_journey_recovery'"),2,'manual transitions audited');
  check((await scalar("select recover_driver_journey($1,'at_dropoff',1,'Confirmed passengers alighted safely')",[booking])).no_op,true,'completed recovery retry is idempotent');

  // Two drivers must independently arrive/depart. One GPS stream cannot move
  // another assignment or complete the entire convoy prematurely.
  booking=id(40); activity=id(41); assignment=id(42);
  await db.query(`insert into package_bookings(id,tourist_id,package_id,status,booking_status,required_drivers,
    scheduled_start_at,estimated_end_at,dropoff_latitude) values($1,$2,1,'ongoing','on_tour',2,
    now()-interval '4 hours',now()-interval '1 hour',15.03)`,[booking,tourist]);
  await db.query('insert into package_activities(id,booking_id) values($1,$2)',[activity,booking]);
  await db.query(`insert into booking_drivers(id,booking_id,driver_id,status,journey_state,state_updated_at)
    values($1,$2,$3,'accepted','en_route_stop',now()-interval '3 hours'),($4,$2,$5,'accepted','en_route_stop',now()-interval '3 hours')`,[assignment,booking,driver,id(43),other]);
  await db.query("insert into booking_itinerary_items(id,booking_id,destination_name,order_number,latitude) values($1,$2,'Convoy stop',1,15.01)",[id(44),booking]);
  check(await scalar('select reconcile_stale_tour_tracking($1)',[booking]),0,'estimated end plus one hour remains within grace');
  await db.query("insert into payment_records values($1,$2,'confirmed','remaining_balance',now(),3600)",[id(45),booking]);
  await db.query("insert into booking_payment_requirements values($1,'remaining_balance','satisfied',3600,$2)",[booking,id(45)]);
  await fixes(15.01);
  check(await scalar('select journey_state from booking_drivers where id=$1',[id(43)]),'en_route_stop','A arrival cannot move B');
  await fixes(15.013,3);
  check(await state(),'stop_done','A departure waits for B');
  check(await scalar('select spot_status from booking_itinerary_items where id=$1',[id(44)]),'at_spot','shared stop remains open until B departs');
  await login(other); assignment=id(43);
  await fixes(15.01); await fixes(15.013,3);
  check(await state(),'en_route_dropoff','B verified departure clears convoy barrier');
  check(await scalar('select spot_status from booking_itinerary_items where id=$1',[id(44)]),'completed','all drivers departed completes shared stop');
  check(await scalar('select count(*)::int from booking_driver_arrivals where itinerary_item_id=$1 and departed_at is not null',[id(44)]),2,'each driver has an actual departure');
  // A disputed/reversed payment while travelling must preserve arrival, and
  // must not let automatic completion bypass financial authorization.
  await db.query("update booking_payment_requirements set status='pending' where booking_id=$1",[booking]);
  await fixes(15.03);
  check(await state(),'at_dropoff','payment reversal preserves verified final arrival');
  check((await scalar('select get_tour_tracking_status($1)',[booking])).phase,'completion_pending','payment review has a recoverable UI state');
  await fixes(15.03);
  check(await state(),'at_dropoff','repeated fixes do not bypass reversed payment');
  await db.query("update booking_payment_requirements set status='satisfied' where booking_id=$1",[booking]);
  await tick(); await fix(15.03);
  check(await state(),'completed','paid final destination completes B automatically');
  check(await scalar('select status from package_bookings where id=$1',[booking]),'ongoing','B completion cannot finish A');
  await login(driver); assignment=id(42);
  await tick(); await fix(15.013,3);
  check(await state(),'en_route_dropoff','A resumes from saved stop after convoy barrier clears');
  await fixes(15.03);
  check(await scalar('select status from package_bookings where id=$1',[booking]),'completed','all-driver final verification completes convoy');

  // Manual stop recovery preserves the existing minimum stay requirement.
  booking=id(60); activity=id(61); assignment=id(62);
  await db.query("insert into package_bookings(id,tourist_id,package_id,status,booking_status,required_drivers) values($1,$2,1,'ongoing','on_tour',1)",[booking,tourist]);
  await db.query('insert into package_activities(id,booking_id) values($1,$2)',[activity,booking]);
  await db.query("insert into booking_drivers(id,booking_id,driver_id,status,journey_state) values($1,$2,$3,'accepted','en_route_stop')",[assignment,booking,driver]);
  await db.query("insert into booking_itinerary_items(id,booking_id,destination_name,order_number,latitude) values($1,$2,'Recovery stop',1,15.01)",[id(63),booking]);
  await fixes(15.01);
  await fail("select recover_driver_journey($1,'at_stop',0,'Location sensor stopped after arrival')",[booking],'STOP_DWELL_TIME_NOT_MET');
  await db.query("update booking_driver_arrivals set arrived_at=now()-interval '11 minutes' where booking_driver_id=$1",[assignment]);
  await scalar("select recover_driver_journey($1,'at_stop',0,'Location sensor stopped after arrival')",[booking]);
  check(await state(),'stop_done','manual departure recovery retains existing stay validation');
  await db.query("update package_bookings set booking_status='cancelled',status='cancelled' where id=$1",[booking]);
  await fixes(15.03);
  check(await state(),'stop_done','cancelled tour GPS cannot progress');
  console.log(`PASS: ${checks} automatic-tour regression checks`);
} finally { await db.close(); }
