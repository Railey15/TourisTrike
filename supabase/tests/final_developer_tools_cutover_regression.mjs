// In-memory PostgreSQL; never connects to or changes the linked project.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const sql = readFileSync(
  new URL('../migrations/20260930060000_final_developer_tools_cutover.sql', import.meta.url),
  'utf8',
).replaceAll('\r\n', '\n');
const db = new PGlite();
const id = value => `00000000-0000-0000-0000-${String(value).padStart(12, '0')}`;
const admin = id(1), tourist = id(2), driver = id(3), outsider = id(4);
const booking = id(10), otherBooking = id(11), activity = id(20), otherActivity = id(21);
const assignment = id(30), otherAssignment = id(31), session = id(40), stop = id(50);
let checks = 0;
const check = (actual, expected, message) => {
  assert.deepEqual(actual, expected, message);
  checks++;
};
const scalar = async (statement, params = []) =>
  Object.values((await db.query(statement, params)).rows[0])[0];
const fails = async (statement, params, code) => {
  await assert.rejects(() => db.query(statement, params), new RegExp(code));
  checks++;
};
const login = user => db.query("select set_config('test.uid',$1,false)", [user]);

try {
  for (const retired of [
    'debug_reset_test_trip', 'debug_advance_driver_journey_state',
    'debug_mark_itinerary_stop_arrived', 'debug_complete_package_tour',
    'debug_force_complete_test_trip', 'debug_get_test_booking_state',
    'debug_set_test_booking_mode', 'debug_test_driver_assignment',
    'debug_mark_remaining_balance_paid', 'debug_get_test_mode_diagnostics',
  ]) {
    check(sql.includes(`'${retired}'`), true, `${retired} is explicitly retired`);
  }
  check(sql.includes('delete from public.developer_test_bookings'), true, 'legacy booking allowlist is emptied');
  check(sql.includes('delete from public.developer_test_users'), true, 'legacy QA-user allowlist is emptied');
  const emit = sql.slice(sql.indexOf('create or replace function public.emit_tour_notification'), sql.indexOf('create or replace function public.normalize_tour_notification'));
  check(emit.includes('is_developer_test_booking'), false, 'tour notification emission has no test-booking suppression');
  const available = sql.slice(sql.indexOf('create or replace function public.notify_drivers_of_available_booking'), sql.indexOf('revoke all on function public.emit_tour_notification'));
  check(available.includes('is_developer_test_booking'), false, 'available-job notification has no test-booking suppression');

  await db.exec(`
    create role anon;
    create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
    create table profiles(id uuid primary key,role text not null);
    create function public.is_system_administrator() returns boolean language sql stable as
      $$ select exists(select 1 from public.profiles where id=auth.uid() and role='administrator') $$;
    create table system_settings(singleton boolean primary key,developer_testing_enabled boolean not null);
    create table package_bookings(
      id uuid primary key,tourist_id uuid,status text,booking_status text,
      accepted_drivers_count integer,current_spot_index integer,
      driver_latitude float8,driver_longitude float8,arrived_at timestamptz,
      picked_up_at timestamptz,completed_at timestamptz,cancelled_at timestamptz,
      tracking_interrupted_at timestamptz,updated_at timestamptz default now()
    );
    create table developer_test_sessions(
      id uuid primary key,booking_id uuid,status text,activated_at timestamptz,
      expires_at timestamptz
    );
    create table package_activities(
      id uuid primary key,booking_id uuid,status text,tour_status text,
      current_spot_index integer,driver_latitude float8,driver_longitude float8,
      driver_last_seen timestamptz,picked_up_at timestamptz,dropped_off_at timestamptz,
      created_at timestamptz default now(),updated_at timestamptz default now()
    );
    create table booking_drivers(
      id uuid primary key,booking_id uuid,driver_id uuid,status text,
      journey_state text,current_stop_index integer,state_updated_at timestamptz,
      completed_at timestamptz
    );
    create table booking_itinerary_items(
      id uuid primary key,booking_id uuid,spot_status text,
      actual_arrival_time timestamptz,actual_departure_time timestamptz
    );
    create table driver_journey_evidence(booking_driver_id uuid primary key);
    create table booking_driver_arrivals(booking_driver_id uuid,itinerary_item_id uuid);
    create table booking_stop_waiting_charges(
      booking_id uuid,status text,additional_amount numeric
    );
    create table payout_records(booking_id uuid,status text);
    create table payment_disputes(booking_id uuid,status text);
    create table refund_requests(booking_id uuid,status text);
    create table trip_status_logs(
      activity_id uuid,booking_id uuid,status text,spot_index integer,notes text
    );
    create table audit_logs(
      actor_id uuid,action text,table_name text,record_id text,description text
    );
  `);

  const resetStart = sql.indexOf('create or replace function public.administrator_reset_developer_test_trip');
  const resetEnd = sql.indexOf('\n$$;', resetStart) + 4;
  await db.exec(sql.slice(resetStart, resetEnd));
  await db.exec('grant execute on function public.administrator_reset_developer_test_trip(uuid) to authenticated');

  await db.query("insert into profiles values($1,'administrator'),($2,'tourist'),($3,'driver'),($4,'driver')", [admin,tourist,driver,outsider]);
  await db.exec('insert into system_settings values(true,true)');
  await db.query(`insert into package_bookings(
    id,tourist_id,status,booking_status,accepted_drivers_count,current_spot_index,
    driver_latitude,driver_longitude,arrived_at,picked_up_at,tracking_interrupted_at)
    values($1,$2,'ongoing','on_tour',1,1,15,121,now(),now(),now()),
          ($3,$2,'ongoing','on_tour',1,9,16,122,now(),now(),now())`, [booking,tourist,otherBooking]);
  await db.query("insert into developer_test_sessions values($1,$2,'active',now(),now()+interval '2 hours')", [session,booking]);
  await db.query("insert into package_activities(id,booking_id,status,tour_status,current_spot_index,driver_latitude,driver_longitude,driver_last_seen,picked_up_at) values($1,$2,'ongoing','on_tour',1,15,121,now(),now()),($3,$4,'ongoing','on_tour',9,16,122,now(),now())", [activity,booking,otherActivity,otherBooking]);
  await db.query("insert into booking_drivers values($1,$2,$3,'completed','at_stop',1,now(),now()),($4,$5,$3,'accepted','at_stop',9,now(),null)", [assignment,booking,driver,otherAssignment,otherBooking]);
  await db.query("insert into booking_itinerary_items values($1,$2,'completed',now(),now())", [stop,booking]);
  await db.query('insert into driver_journey_evidence values($1)', [assignment]);
  await db.query('insert into booking_driver_arrivals values($1,$2)', [assignment,stop]);
  await db.query("insert into booking_stop_waiting_charges values($1,'active',0)", [booking]);
  await db.query("insert into payout_records values($1,'pending')", [booking]);

  await login(tourist);
  await fails('select administrator_reset_developer_test_trip($1)', [booking], 'SYSTEM_ADMINISTRATOR_REQUIRED');
  await login(admin);
  const result = await scalar('select administrator_reset_developer_test_trip($1)', [booking]);
  check(result.success, true, 'administrator reset succeeds for an active reversible test trip');
  check(await scalar('select journey_state from booking_drivers where id=$1',[assignment]), 'assigned', 'driver journey resets');
  check(await scalar('select spot_status from booking_itinerary_items where id=$1',[stop]), 'pending', 'itinerary progress resets');
  check(await scalar('select count(*)::int from driver_journey_evidence'), 0, 'GPS transition evidence resets');
  check(await scalar('select count(*)::int from booking_driver_arrivals'), 0, 'arrival evidence resets');
  check(await scalar('select count(*)::int from booking_stop_waiting_charges'), 0, 'unfinished waiting state resets');
  check(await scalar('select count(*)::int from payout_records where booking_id=$1',[booking]), 1, 'payout record is preserved');
  check(await scalar('select count(*)::int from developer_test_sessions where id=$1 and status=$2',[session,'active']), 1, 'active session is preserved');
  check(await scalar('select developer_testing_enabled from system_settings'), true, 'global switch is preserved');
  check(await scalar('select count(*)::int from audit_logs where action=$1',['DEVELOPER_TEST_TRIP_RESET']), 1, 'reset is audited');
  check(await scalar('select current_spot_index from package_bookings where id=$1',[otherBooking]), 9, 'unrelated booking is untouched');
  check(await scalar('select journey_state from booking_drivers where id=$1',[otherAssignment]), 'at_stop', 'unrelated assignment is untouched');

  await db.query("update package_bookings set status='ongoing',booking_status='on_tour',current_spot_index=1 where id=$1", [booking]);
  await db.query("insert into payout_records values($1,'paid')", [booking]);
  await fails('select administrator_reset_developer_test_trip($1)', [booking], 'RESET_BLOCKED_BY_PAYOUT_STATE');
  await db.query("delete from payout_records where booking_id=$1 and status='paid'", [booking]);
  await db.query("insert into payment_disputes values($1,'resolved')", [booking]);
  await fails('select administrator_reset_developer_test_trip($1)', [booking], 'RESET_BLOCKED_BY_PAYMENT_DISPUTE');
  await db.query('delete from payment_disputes where booking_id=$1', [booking]);
  await db.query("insert into booking_stop_waiting_charges values($1,'finalized',25)", [booking]);
  await fails('select administrator_reset_developer_test_trip($1)', [booking], 'RESET_BLOCKED_BY_FINALIZED_WAITING_CHARGE');

  console.log(`PASS: ${checks} final developer-tools cutover regression checks`);
} finally {
  await db.close();
}
