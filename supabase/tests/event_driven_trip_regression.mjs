// Run using the isolated dependency installed under ignored build/sql-validation.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const db = new PGlite();
const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8').replaceAll('\r\n', '\n');
function extract(source, name) {
  const start = source.indexOf('create or replace function public.' + name + '(');
  assert(start >= 0, name);
  return source.slice(start, source.indexOf('\n$$;', start) + 4);
}
let checks = 0;
const check = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };
const scalar = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const fail = async (sql, params, code) => { await assert.rejects(() => db.query(sql, params), new RegExp(code)); checks++; };
try {
  await db.exec(read('./event_driven_trip_fixture.sql'));
  const downpaymentRepair = read('../migrations/20260906020000_restore_booking_downpayment_check.sql');
  check(extract(downpaymentRepair, 'is_booking_downpayment_confirmed'),
    extract(read('../migrations/20260831010000_transaction_lifecycle_consistency.sql'), 'is_booking_downpayment_confirmed'),
    'repair reuses the canonical payment predicate without changing payment rules');
  await db.exec(downpaymentRepair);
  await db.exec(extract(read('../migrations/20260831010000_transaction_lifecycle_consistency.sql'), 'compute_convoy_stage_progress'));
  for (const name of ['finalize_package_booking_if_eligible', 'is_booking_remaining_payment_satisfied', 'is_booking_itinerary_complete']) {
    await db.exec(extract(read('../migrations/20260831010000_transaction_lifecycle_consistency.sql'), name));
  }
  await db.exec(read('../migrations/20260906000000_event_driven_trip_feedback.sql'));
  await db.exec(extract(read('../migrations/20260831000000_automatic_developer_test_mode.sql'), 'debug_test_driver_assignment'));
  await db.exec(read('../migrations/20260906010000_test_mode_live_tracking_consistency.sql'));
  const gpsDebugRepair = read('../migrations/20260906030000_keep_debug_arrivals_gps_verified.sql');
  await db.exec(gpsDebugRepair);
  const radiusMigration = read('../migrations/20260906040000_centralize_driver_arrival_radius.sql');
  await db.exec(radiusMigration);
  await db.exec(read('../migrations/20260906050000_guard_remaining_payment_completion.sql'));
  check(await scalar('select driver_arrival_radius_meters()'),150,'database exposes the shared arrival radius');
  // The original migration owns these triggers; install them in the fixture.
  await db.exec(`create trigger proximity before update of journey_state on booking_drivers for each row execute function guard_live_driver_journey_proximity();
    create trigger milestones after update of journey_state on booking_drivers for each row execute function sync_driver_journey_milestones();`);
  const id = (n) => '00000000-0000-0000-0000-' + String(n).padStart(12, '0');
  const tourist = id(1), a = id(2), b = id(3), outsider = id(4), booking = id(10), activity = id(11), stop = id(12), da = id(20), dbid = id(21);
  const login = async (user) => db.query("select set_config('test.uid', $1, false)", [user]);
  await db.query(`insert into profiles(id, full_name, role) values ($1,'Tourist','tourist'),($2,'Driver A','driver'),($3,'Driver B','driver'),($4,'Outsider','tourist')`, [tourist, a, b, outsider]);
  await db.exec("insert into tour_packages values (1, 'Baliwag Tour')");
  await db.query("insert into package_bookings(id,tourist_id,package_id,booking_status,status) values($1,$2,1,'on_tour','ongoing')", [booking, tourist]);
  await db.query('insert into package_activities(id,booking_id) values($1,$2)', [activity, booking]);
  await db.query("insert into booking_drivers(id,booking_id,driver_id,status,journey_state) values($1,$2,$3,'accepted','en_route_stop'),($4,$2,$5,'accepted','en_route_stop')", [da, booking, a, dbid, b]);
  await db.query("insert into booking_itinerary_items(id,booking_id,destination_name,arrival_time,departure_time,order_number) values($1,$2,'Cafe Beam','08:10','08:20',1)", [stop, booking]);
  await login(a);
  await fail("select advance_driver_journey_state($1,'at_stop')", [booking], 'DRIVER_LOCATION_STALE');
  await db.query('insert into driver_live_locations(driver_id,latitude,longitude) values($1,15,121),($2,15,121)', [a,b]);
  await db.query("select advance_driver_journey_state($1,'at_stop')", [booking]);
  check(await scalar('select count(*)::int from booking_driver_arrivals'), 1, 'own arrival recorded once');
  check(await scalar('select journey_state from booking_drivers where driver_id=$1', [b]), 'en_route_stop', 'GPS arrival does not advance other drivers');
  await db.query("select advance_driver_journey_state($1,'at_stop')", [booking]);
  check(await scalar('select count(*)::int from booking_driver_arrivals'), 1, 'arrival retry is idempotent');
  check(await scalar('select count(*)::int from notifications'), 3, 'arrival notifications preserve deduplication');
  await fail('select complete_current_itinerary_item($1,$2,null)', [activity,stop], 'STOP_DWELL_TIME_NOT_MET');
  await db.query("update booking_driver_arrivals set arrived_at=now()-interval '11 minutes' where booking_driver_id=$1", [da]);
  const ready = await scalar('select complete_current_itinerary_item($1,$2,null)', [activity,stop]);
  check(ready.driver_ready, true, 'driver A ready independently');
  check(await scalar('select spot_status from booking_itinerary_items where id=$1',[stop]), 'at_spot', 'shared stop waits for driver B');
  await fail("select advance_driver_journey_state($1,'en_route_dropoff')", [booking], 'INCOMPLETE_ITINERARY');
  await login(b);
  await db.query("select advance_driver_journey_state($1,'at_stop')", [booking]);
  await db.query("update booking_driver_arrivals set arrived_at=now()-interval '11 minutes'");
  await db.query('select complete_current_itinerary_item($1,$2,null)', [activity,stop]);
  check(await scalar('select spot_status from booking_itinerary_items where id=$1',[stop]), 'completed', 'shared completion after both drivers ready');
  check(await scalar('select booking_status from package_bookings where id=$1',[booking]), 'awaiting_remaining_payment', 'remaining-payment state entered');
  await fail("select advance_driver_journey_state($1,'en_route_stop')", [booking], 'ITINERARY_STOP_OUT_OF_RANGE');
  await fail("select advance_driver_journey_state($1,'en_route_dropoff')", [booking], 'REMAINING_BALANCE_NOT_CONFIRMED');
  await db.query("insert into payment_records values($1,$2,'confirmed','remaining_balance',now(),3600)",[id(30),booking]);
  await fail("select advance_driver_journey_state($1,'en_route_dropoff')", [booking], 'REMAINING_BALANCE_NOT_CONFIRMED');
  await db.query("insert into booking_payment_requirements values($1,'remaining_balance','satisfied',3600,$2)",[booking,id(30)]);
  await db.query("select advance_driver_journey_state($1,'en_route_dropoff')", [booking]);
  check(await scalar('select departed_at is not null from booking_driver_arrivals where booking_driver_id=$1',[dbid]), true, 'actual departure persisted separately');
  check(await scalar("select arrival_time::text || '/' || departure_time::text from booking_itinerary_items where id=$1",[stop]), '08:10:00/08:20:00', 'planned times preserved');
  await db.query("select advance_driver_journey_state($1,'at_dropoff')", [booking]);
  check(await scalar('select dropped_off_at is null from package_activities where id=$1',[activity]), true, 'GPS arrival is not passenger drop-off');
  await db.query("select advance_driver_journey_state($1,'completed')", [booking]);
  check(await scalar('select status from booking_drivers where driver_id=$1',[a]), 'accepted', 'drop-off confirmation completes only self');
  await login(a);
  await db.query("select advance_driver_journey_state($1,'en_route_dropoff')", [booking]);
  // GPS-off fallback needs corroborating tourist proximity and a reason.
  await db.query("update driver_live_locations set updated_at=now()-interval '1 hour' where driver_id=$1", [a]);
  await fail('select confirm_driver_arrival_fallback($1,$2)',[booking,'GPS unavailable at dropoff'],'DRIVER_LOCATION_STALE');
  await db.query('insert into booking_participant_live_locations values($1,$2,15,121,20,now())',[booking,tourist]);
  await db.query('select confirm_driver_arrival_fallback($1,$2)',[booking,'GPS unavailable at dropoff']);
  check(await scalar("select count(*)::int from trip_status_logs where status='arrival_manual_fallback'"),1,'fallback audit log');
  await db.query("select advance_driver_journey_state($1,'completed')", [booking]);
  await login(tourist);
  check(await scalar('select booking_status from package_bookings where id=$1',[booking]),'completed','real finalizer completes only all-driver paid booking');
  check(await scalar('select tourist_has_reviewed_booking($1)',[booking]),false,'unreviewed booking');
  await fail('select submit_booking_feedback($1,5,$2,$3)',[booking,'Great tour',JSON.stringify([{driver_id:a,rating:5}])],'INCOMPLETE_BOOKING_FEEDBACK');
  check(await scalar('select count(*)::int from package_reviews'),0,'partial submission rolls back package review');
  check(await scalar('select count(*)::int from driver_reviews'),0,'partial submission rolls back driver review');
  const reviews=JSON.stringify([{driver_id:a,rating:5,review_text:'Very accommodating'},{driver_id:b,rating:4,review_text:'Good driver'}]);
  await db.query('select submit_booking_feedback($1,5,$2,$3)',[booking,'Great tour',reviews]);
  check(await scalar('select tourist_has_reviewed_booking($1)',[booking]),true,'all participating drivers reviewed');
  await db.query('select submit_booking_feedback($1,1,$2,$3)',[booking,'duplicate retry',reviews]);
  check(await scalar('select count(*)::int from driver_reviews'),2,'retry does not duplicate reviews');
  check(await scalar('select rating from package_reviews'),5,'retry preserves original rating');
  const feedback=await scalar('select get_booking_feedback($1)',[booking]);
  check(feedback.drivers.length,2,'booking history returns all drivers');
  check(feedback.package_review.review_text,'Great tour','booking-specific comment retained');
  await login(outsider);
  await fail('select get_driver_home_overview()', [], 'DRIVER_ROLE_REQUIRED');
  await fail('select get_booking_feedback($1)',[booking],'NOT_BOOKING_PARTICIPANT');
  await fail('select submit_booking_feedback($1,5,$2,$3)',[booking,'Great tour',reviews],'NOT_BOOKING_OWNER');
  await login(a);
  await db.query("insert into payment_allocations(payment_record_id,driver_id,driver_amount,status,paid_at) values($1,$2,1800,'allocated',now())",[id(30),a]);
  const overview=await scalar('select get_driver_home_overview()');
  check(overview.completed_tours,1,'dashboard counts independent completed assignments');
  check(overview.today_trips,1,'dashboard counts trips rather than payments');
  check(overview.average_rating,5,'driver-specific average');
  check(overview.review_count,1,'driver-specific count');
  check(overview.today_earnings,1800,'earnings are allocated driver share');
  check(overview.recent_reviews[0].review_text,'Very accommodating','driver-specific recent feedback');
  // A second booking exercises pickup and the repeating two-stop loop.
  const booking2=id(40), activity2=id(41), stop1=id(42), stop2=id(43), assignment2=id(44);
  await db.query("insert into package_bookings(id,tourist_id,package_id,booking_status,status,required_drivers,scheduled_start_at) values($1,$2,1,'accepted','confirmed',1,now()-interval '1 hour')",[booking2,tourist]);
  await db.query('insert into package_activities(id,booking_id) values($1,$2)',[activity2,booking2]);
  await db.query("insert into booking_drivers(id,booking_id,driver_id,status,journey_state) values($1,$2,$3,'accepted','assigned')",[assignment2,booking2,a]);
  await db.query("insert into booking_itinerary_items(id,booking_id,destination_name,order_number) values($1,$2,'First',1),($3,$2,'Second',2)",[stop1,booking2,stop2]);
  check((await scalar('select get_driver_home_overview()')).active_trips,1,'current assignment uses booking_drivers');
  await db.query("update package_bookings set scheduled_start_at=now()+interval '1 hour' where id=$1",[booking2]);
  check((await scalar('select get_driver_home_overview()')).upcoming_trips,1,'later today is upcoming');
  await db.query("update package_bookings set scheduled_start_at=now()-interval '1 hour' where id=$1",[booking2]);
  // Reproduce the deployed missing dependency in both normal and debug RPCs.
  await db.exec('drop function public.is_booking_downpayment_confirmed(uuid)');
  const missingHelper = { code: '42883', message: /is_booking_downpayment_confirmed/ };
  await assert.rejects(() => db.query("select advance_driver_journey_state($1,'en_route_pickup')",[booking2]), missingHelper); checks++;
  await db.query('update package_bookings set test_mode=true where id=$1',[booking2]);
  await assert.rejects(() => db.query("select debug_advance_driver_journey_state($1,'en_route_pickup')",[booking2]), missingHelper); checks++;
  await db.exec(downpaymentRepair);
  await db.exec(downpaymentRepair); // Repair is safe to apply again.
  await db.query('update package_bookings set test_mode=false where id=$1',[booking2]);
  await fail("select advance_driver_journey_state($1,'en_route_pickup')",[booking2],'DOWNPAYMENT_NOT_CONFIRMED');
  for (const [status, stage, amount] of [
    ['pending_confirmation', 'down_payment', 3600],
    ['cancelled', 'down_payment', 3600],
    ['confirmed', 'remaining_balance', 3600],
    ['confirmed', 'down_payment', 3599],
  ]) {
    await db.query('insert into payment_records values($1,$2,$3,$4,now(),$5)',[id(45),booking2,status,stage,amount]);
    await fail("select advance_driver_journey_state($1,'en_route_pickup')",[booking2],'DOWNPAYMENT_NOT_CONFIRMED');
    await db.query('delete from payment_records where id=$1',[id(45)]);
  }
  check(await scalar('select is_booking_downpayment_confirmed($1)',[booking2]),false,'another booking payment cannot unlock pickup');
  await fail('select is_booking_downpayment_confirmed($1)',[id(999)],'BOOKING_NOT_FOUND');
  await db.query("insert into payment_records values($1,$2,'confirmed','down_payment',now(),3600)",[id(45),booking2]);
  check(await scalar('select is_booking_downpayment_confirmed($1)',[booking2]),true,'confirmed sufficient downpayment unlocks pickup');
  await db.query("update payment_records set payment_stage='full' where id=$1",[id(45)]);
  check(await scalar('select is_booking_downpayment_confirmed($1)',[booking2]),true,'legacy confirmed full payment remains supported');
  await db.query('update package_bookings set downpayment_amount=0 where id=$1',[booking2]);
  check(await scalar('select is_booking_downpayment_confirmed($1)',[booking2]),true,'legacy missing split uses half the total');
  await db.query('update payment_records set amount=3599 where id=$1',[id(45)]);
  check(await scalar('select is_booking_downpayment_confirmed($1)',[booking2]),false,'legacy fallback still rejects insufficient payment');
  await db.query("update payment_records set amount=3600,payment_stage='down_payment' where id=$1",[id(45)]);
  await db.query('update package_bookings set downpayment_amount=3600 where id=$1',[booking2]);
  await db.query("update driver_live_locations set updated_at=now() where driver_id=$1",[a]);
  for (const stage of ['en_route_pickup','at_pickup','boarded','en_route_stop','at_stop']) {
    await db.query('select advance_driver_journey_state($1,$2)',[booking2,stage]);
  }
  check(await scalar('select picked_up_at is not null from package_activities where id=$1',[activity2]),true,'manual boarding records actual pickup');
  await db.query("update booking_driver_arrivals set arrived_at=now()-interval '11 minutes' where booking_driver_id=$1",[assignment2]);
  await db.query('select complete_current_itinerary_item($1,$2,null)',[activity2,stop1]);
  await db.query("select advance_driver_journey_state($1,'en_route_stop')",[booking2]);
  check(await scalar('select current_stop_index from booking_drivers where id=$1',[assignment2]),1,'second navigation leg targets second stop');
  await db.query("select advance_driver_journey_state($1,'at_stop')",[booking2]);
  check(await scalar('select count(*)::int from booking_driver_arrivals where booking_driver_id=$1',[assignment2]),2,'repeated at_stop records each stop independently');
  await fail('select complete_current_itinerary_item($1,$2,null)',[activity2,stop2],'STOP_DWELL_TIME_NOT_MET');
  await db.query("update booking_driver_arrivals set arrived_at=now()-interval '11 minutes' where booking_driver_id=$1",[assignment2]);
  await db.query('select complete_current_itinerary_item($1,$2,null)',[activity2,stop2]);
  check(await scalar('select booking_status from package_bookings where id=$1',[booking2]),'awaiting_remaining_payment','remaining payment only after last stop');
  const future=id(60), futureActivity=id(61), futureAssignment=id(62);
  await db.query("insert into package_bookings(id,tourist_id,package_id,booking_status,status,required_drivers,scheduled_start_at,estimated_end_at) values($1,$2,1,'accepted','confirmed',1,now()+interval '4 days',now()+interval '5 days')",[future,tourist]);
  await db.query('insert into package_activities(id,booking_id) values($1,$2)',[futureActivity,future]);
  await db.query("insert into booking_drivers(id,booking_id,driver_id,status,journey_state) values($1,$2,$3,'accepted','assigned')",[futureAssignment,future,a]);
  await fail("select advance_driver_journey_state($1,'en_route_pickup')",[future],'BOOKING_START_TOO_EARLY');
  await fail("select debug_advance_driver_journey_state($1,'en_route_pickup')",[future],'TEST_BOOKING_NOT_REGISTERED');
  await db.query('update package_bookings set test_mode=true where id=$1',[future]);
  // Exact deployed defect observed by read-only pg_get_functiondef inspection:
  // authorization ran but the wrapper did not set the operational bypass flag.
  await db.exec(`create or replace function debug_advance_driver_journey_state(p_booking_id uuid,p_target_state text)
    returns jsonb language plpgsql security definer set search_path=public as $broken$
    begin perform debug_test_driver_assignment(p_booking_id);
    return advance_driver_journey_state(p_booking_id,p_target_state); end; $broken$;`);
  await fail("select debug_advance_driver_journey_state($1,'en_route_pickup')",[future],'BOOKING_START_TOO_EARLY');
  await db.exec(extract(read('../migrations/20260906010000_test_mode_live_tracking_consistency.sql'), 'debug_advance_driver_journey_state'));
  await db.exec(gpsDebugRepair);
  const started=await scalar("select debug_advance_driver_journey_state($1,'en_route_pickup')",[future]);
  check(started.debug_bypass,true,'debug future booking starts with real canonical transition');
  check(await scalar('select count(*)::int from payment_records where booking_id=$1',[future]),0,'bypass does not fabricate payments');
  await db.query("update driver_live_locations set updated_at=now()-interval '3 minutes' where driver_id=$1",[a]);
  await fail("select debug_advance_driver_journey_state($1,'at_pickup')",[future],'DRIVER_LOCATION_STALE');
  await db.query('update driver_live_locations set latitude=16, updated_at=now() where driver_id=$1',[a]);
  await fail("select advance_driver_journey_state($1,'at_pickup')",[future],'NOT_WITHIN_ARRIVAL_RADIUS');
  await fail("select debug_advance_driver_journey_state($1,'at_pickup')",[future],'NOT_WITHIN_ARRIVAL_RADIUS');
  await db.query('update driver_live_locations set latitude=15,updated_at=now() where driver_id=$1',[a]);
  await db.query("select advance_driver_journey_state($1,'at_pickup')",[future]);
  check(await scalar('select journey_state from booking_drivers where id=$1',[futureAssignment]),'at_pickup','real GPS arrival remains enabled on test booking');
  const arrivalLogs = await scalar('select count(*)::int from trip_status_logs where booking_id=$1',[future]);
  const arrivalTime = await scalar('select state_updated_at from booking_drivers where id=$1',[futureAssignment]);
  await db.query("select debug_advance_driver_journey_state($1,'at_pickup')",[future]);
  check(await scalar('select count(*)::int from trip_status_logs where booking_id=$1',[future]),arrivalLogs,'arrival retries do not duplicate logs');
  check(await scalar('select state_updated_at from booking_drivers where id=$1',[futureAssignment]),arrivalTime,'arrival retries preserve original timestamp');
  await db.query("insert into booking_itinerary_items(id,booking_id,destination_name,order_number) values($1,$2,'GPS test stop',1)",[id(63),future]);
  for (const [from, to] of [['en_route_stop','at_stop'],['en_route_dropoff','at_dropoff']]) {
    await db.query('update booking_drivers set journey_state=$2 where id=$1',[futureAssignment,from]);
    await db.query('update driver_live_locations set latitude=16,updated_at=now() where driver_id=$1',[a]);
    await fail('select debug_advance_driver_journey_state($1,$2)',[future,to],'NOT_WITHIN_ARRIVAL_RADIUS');
    await db.query('update driver_live_locations set latitude=15,updated_at=now() where driver_id=$1',[a]);
    const arrival = await scalar('select debug_advance_driver_journey_state($1,$2)',[future,to]);
    check(arrival.journey_state,to,'test '+to+' requires actual nearby GPS');
    check(arrival.debug_bypass,false,'test '+to+' does not set operational bypass');
  }
  await db.query("update booking_drivers set journey_state='assigned' where id=$1",[futureAssignment]);
  await db.query('update package_bookings set test_mode=false where id=$1',[future]);
  await fail("select advance_driver_journey_state($1,'en_route_pickup')",[future],'BOOKING_START_TOO_EARLY');
  await fail("select debug_advance_driver_journey_state($1,'en_route_pickup')",[future],'TEST_BOOKING_NOT_REGISTERED');
  // A single configuration change must affect both regular and corroborated
  // fallback checks; test at ~111 m (inside 150 m but outside 80 m).
  await db.exec('create or replace function driver_arrival_radius_meters() returns double precision language sql immutable as $$ select 80::double precision $$;');
  check(await scalar('select driver_arrival_radius_meters()'),80,'radius RPC reflects the single configuration source');
  await db.query("update booking_drivers set journey_state='en_route_pickup' where id=$1",[futureAssignment]);
  await db.query('update driver_live_locations set latitude=15.001,updated_at=now() where driver_id=$1',[a]);
  await db.query('insert into booking_participant_live_locations values($1,$2,15.001,121,10,now())',[future,tourist]);
  await fail("select advance_driver_journey_state($1,'at_pickup')",[future],'NOT_WITHIN_ARRIVAL_RADIUS');
  await fail('select confirm_driver_arrival_fallback($1,$2)',[future,'GPS verification fallback test'],'NOT_WITHIN_ARRIVAL_RADIUS');
  await db.exec(radiusMigration);
  check((await scalar("select advance_driver_journey_state($1,'at_pickup')",[future])).journey_state,'at_pickup','restored 150 m configuration accepts the same fix');
  // Switching off test bypass at drop-off must not allow unpaid completion.
  await fail("update booking_drivers set journey_state='completed' where id=$1", [futureAssignment], 'REMAINING_BALANCE_NOT_CONFIRMED');
  await db.query('update package_bookings set test_mode=true where id=$1',[future]);
  await db.query("select set_config('touristrike.debug_progression_bypass','true',false)");
  await db.query("update booking_drivers set journey_state='completed' where id=$1",[futureAssignment]);
  await db.query("select set_config('touristrike.debug_progression_bypass','false',false)");
  check(await scalar('select count(*)::int from payment_records where booking_id=$1',[future]),0,'authorized test completion does not fabricate payment');
  console.log(checks + ' SQL regression checks passed (isolated PostgreSQL fixture).');
} catch (error) { console.error(error.message, error.detail ?? '', error.where ?? ''); process.exitCode=1; } finally { await db.close(); }
