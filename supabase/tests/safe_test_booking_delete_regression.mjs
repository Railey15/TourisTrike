// In-memory PostgreSQL only. Exercises the real RPC body and FK rollback.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const source = readFileSync(new URL('../migrations/20261007000000_safe_test_booking_delete_and_prompt_arrival.sql', import.meta.url), 'utf8').replaceAll('\r\n', '\n');
const start = source.indexOf('create or replace function public.administrator_delete_test_booking(');
const rpc = source.slice(start, source.indexOf('\n$$;', start) + 4);
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const admin=id(1), other=id(2), driver=id(3), mainTenant=id(4), subtenant=id(5), good=id(10), protectedBooking=id(11), noSession=id(12), blockedByFk=id(13), expiredSession=id(14), terminal=id(15), sandbox=id(16), manualPending=id(17), payout=id(18), refund=id(19), transfer=id(60), manualConfirmed=id(61), mixedEvent=id(62), crossLinked=id(63);
let checks=0;
const check = (actual, expected, label) => { assert.deepEqual(actual, expected, label); checks++; };
const count = async (table, booking) => (await db.query(`select count(*)::int as n from ${table} where ${table === 'package_bookings' ? 'id' : 'booking_id'}=$1`,[booking])).rows[0].n;
const login = user => db.query("select set_config('test.uid',$1,false)",[user]);
const fails = async (booking, code) => { await assert.rejects(() => db.query('select administrator_delete_test_booking($1)',[booking]),new RegExp(code)); checks++; };
try {
  await db.exec(`
    create role anon; create role authenticated; create schema auth;
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
    create table profiles(id uuid primary key,role text);
    create function public.is_system_administrator() returns boolean language sql stable as
      $$ select exists(select 1 from public.profiles where id=auth.uid() and role='administrator') $$;
    create table package_bookings(id uuid primary key,status text default 'accepted',booking_status text default 'accepted');
    create table package_activities(id uuid primary key,booking_id uuid references package_bookings(id) on delete cascade);
    create table booking_drivers(id uuid primary key,booking_id uuid references package_bookings(id) on delete cascade,
      activity_id uuid references package_activities(id));
    create table booking_itinerary_items(id uuid primary key,booking_id uuid references package_bookings(id) on delete cascade);
    create table booking_driver_arrivals(booking_driver_id uuid references booking_drivers(id) on delete cascade,
      itinerary_item_id uuid references booking_itinerary_items(id) on delete cascade);
    create table driver_journey_evidence(booking_driver_id uuid references booking_drivers(id) on delete cascade);
    create table driver_live_locations(driver_id uuid primary key,activity_id uuid references package_activities(id));
    create table developer_test_sessions(id uuid primary key,booking_id uuid references package_bookings(id) on delete cascade,
      status text,expires_at timestamptz,activated_at timestamptz);
    create table payment_records(id uuid primary key,booking_id uuid references package_bookings(id),
      provider text,provider_livemode boolean,status text,paid_at timestamptz,payee_confirmed_at timestamptz,
      receipt_no text,external_reference_no text,proof_image_url text,provider_payment_id text,
      provider_checkout_id text,provider_reference text);
    create table booking_payment_requirements(booking_id uuid references package_bookings(id) on delete cascade,
      status text,satisfied_by_payment_record_id uuid references payment_records(id));
    create table payment_allocations(booking_id uuid references package_bookings(id),
      payment_record_id uuid references payment_records(id),booking_driver_id uuid references booking_drivers(id),
      status text,provider_transfer_id text,provider_transfer_status text,paid_at timestamptz);
    create table payment_provider_events(payment_record_id uuid references payment_records(id) on delete set null,
      provider text,
      provider_livemode boolean,provider_payment_id text,provider_checkout_id text);
    create table refund_requests(booking_id uuid references package_bookings(id),status text,completed_at timestamptz);
    create table payment_disputes(booking_id uuid references package_bookings(id));
    create table payout_records(booking_id uuid references package_bookings(id),status text);
    create table emergency_alerts(booking_id uuid references package_bookings(id));
    create table booking_stop_waiting_charges(booking_id uuid references package_bookings(id) on delete cascade);
    create table booking_custom_fare_quotes(booking_id uuid references package_bookings(id));
    create table driver_reviews(booking_id uuid references package_bookings(id) on delete cascade);
    create table package_reviews(booking_id uuid references package_bookings(id) on delete cascade);
    create table tourist_reviews(booking_id uuid references package_bookings(id) on delete cascade);
    create table trip_status_logs(activity_id uuid references package_activities(id) on delete cascade,
      booking_id uuid references package_bookings(id),status text);
    create table notifications(id bigint generated always as identity primary key,
      booking_id uuid references package_bookings(id) on delete set null);
    create table notification_deliveries(notification_id text);
    create table conversations(id uuid primary key,booking_id uuid references package_bookings(id) on delete set null);
    create table conversation_members(conversation_id uuid references conversations(id) on delete cascade);
    create table messages(conversation_id uuid references conversations(id) on delete cascade);
    create table shared_trip_links(id uuid primary key,booking_id uuid references package_bookings(id) on delete cascade);
    create table shared_trip_access_logs(link_id uuid references shared_trip_links(id) on delete cascade);
    create table booking_participant_live_locations(booking_id uuid references package_bookings(id) on delete cascade);
    create table audit_logs(actor_id uuid,action text,table_name text,record_id text,description text);
    create table unknown_dependent(booking_id uuid references package_bookings(id));
  `);
  await db.exec(rpc);
  await db.exec('revoke all on function public.administrator_delete_test_booking(uuid) from public,anon; grant execute on function public.administrator_delete_test_booking(uuid) to authenticated');
  await db.query("insert into profiles values($1,'administrator'),($2,'tourist'),($3,'driver'),($4,'main_tenant'),($5,'subtenant')",[admin,other,driver,mainTenant,subtenant]);
  for (const [n,b] of [good,protectedBooking,noSession,blockedByFk,sandbox,manualPending,payout,refund,transfer,manualConfirmed,mixedEvent,crossLinked].entries()) {
    await db.query('insert into package_bookings(id) values($1)',[b]);
    await db.query('insert into package_activities values($1,$2)',[id(20+n),b]);
    await db.query('insert into booking_drivers values($1,$2,$3)',[id(30+n),b,id(20+n)]);
    await db.query('insert into booking_itinerary_items values($1,$2)',[id(40+n),b]);
    await db.query('insert into booking_driver_arrivals values($1,$2)',[id(30+n),id(40+n)]);
    await db.query('insert into driver_journey_evidence values($1)',[id(30+n)]);
    if (b !== noSession) await db.query("insert into developer_test_sessions values($1,$2,'active',now()+interval '1 hour',now())",[id(50+n),b]);
  }
  await db.query('insert into driver_live_locations values($1,$2)',[driver,id(20)]);
  await db.query('insert into package_bookings(id) values($1)',[expiredSession]);
  await db.query("insert into developer_test_sessions values($1,$2,'expired',now()-interval '1 hour',now()-interval '2 hours')",[id(90),expiredSession]);
  await db.query("insert into package_bookings(id,status,booking_status) values($1,'completed','completed')",[terminal]);
  await db.query("insert into booking_payment_requirements(booking_id,status) values($1,'required')",[good]);
  await db.query("insert into trip_status_logs values($1,$2,'gps_arrived')",[id(20),good]);
  const noticeId=(await db.query('insert into notifications(booking_id) values($1) returning id',[good])).rows[0].id;
  await db.query('insert into notification_deliveries values($1)',[String(noticeId)]);
  await db.query('insert into booking_participant_live_locations values($1)',[good]);
  await db.query('insert into conversations values($1,$2)',[id(110),good]);
  await db.query('insert into conversation_members values($1)',[id(110)]);
  await db.query('insert into messages values($1)',[id(110)]);
  await db.query('insert into shared_trip_links values($1,$2)',[id(111),good]);
  await db.query('insert into shared_trip_access_logs values($1)',[id(111)]);
  await db.query("insert into payment_records(id,booking_id,provider,provider_livemode,status,paid_at,provider_payment_id) values($1,$2,'paymongo',true,'confirmed',now(),'live-payment')",[id(100),protectedBooking]);
  await db.query("insert into booking_payment_requirements(booking_id,status,satisfied_by_payment_record_id) values($1,'satisfied',$2)",[crossLinked,id(100)]);
  await db.query('insert into payment_provider_events(payment_record_id,provider_livemode,provider_payment_id) values($1,true,$2)',[id(100),'live-payment']);
  await db.query("insert into payment_records(id,booking_id,provider,provider_livemode,status,paid_at,receipt_no,provider_payment_id,provider_checkout_id) values($1,$2,'paymongo',false,'confirmed',now(),'sandbox-receipt','sandbox-payment','sandbox-checkout')",[id(101),sandbox]);
  await db.query("insert into booking_payment_requirements(booking_id,status,satisfied_by_payment_record_id) values($1,'satisfied',$2),($1,'required',null)",[sandbox,id(101)]);
  await db.query("insert into payment_allocations(booking_id,payment_record_id,booking_driver_id,status) values($1,$2,$3,'held')",[sandbox,id(101),id(34)]);
  await db.query('insert into payment_provider_events(payment_record_id,provider_livemode,provider_payment_id,provider_checkout_id) values($1,false,$2,$3)',[id(101),'sandbox-payment','sandbox-checkout']);
  await db.query("insert into payment_records(id,booking_id,provider,status) values($1,$2,'manual','pending_confirmation')",[id(102),manualPending]);
  await db.query("insert into payment_allocations(booking_id,payment_record_id,booking_driver_id,status) values($1,$2,$3,'held')",[manualPending,id(102),id(35)]);
  await db.query("insert into booking_payment_requirements(booking_id,status) values($1,'required')",[manualPending]);
  await db.query('insert into booking_custom_fare_quotes values($1)',[manualPending]);
  await db.query('insert into booking_stop_waiting_charges values($1)',[manualPending]);
  await db.query("insert into payout_records values($1,'paid')",[payout]);
  await db.query("insert into refund_requests values($1,'completed',now())",[refund]);
  await db.query("insert into payment_allocations(booking_id,status,provider_transfer_id) values($1,'paid','real-transfer')",[transfer]);
  await db.query("insert into payment_records(id,booking_id,provider,status,payee_confirmed_at,receipt_no) values($1,$2,'manual','confirmed',now(),'manual-receipt')",[id(103),manualConfirmed]);
  await db.query("insert into payment_records(id,booking_id,provider,provider_livemode,status,provider_payment_id) values($1,$2,'paymongo',false,'confirmed','mixed-payment')",[id(104),mixedEvent]);
  await db.query("insert into payment_provider_events(payment_record_id,provider_livemode,provider_payment_id) values($1,true,'mixed-payment')",[id(104)]);
  await db.query('insert into unknown_dependent values($1)',[blockedByFk]);
  for (const caller of [other,driver,mainTenant,subtenant,'']) {
    await login(caller);
    await fails(good,'SYSTEM_ADMINISTRATOR_REQUIRED');
  }
  check(await count('package_bookings',good),1,'non-admin changes nothing');
  await login(admin);
  await fails(terminal,'BOOKING_NOT_ELIGIBLE_FOR_DEVELOPER_CLEANUP');
  check((await db.query('select administrator_delete_test_booking($1) as result',[noSession])).rows[0].result.success,true,'inactive booking deletes without a session');
  check((await db.query('select administrator_delete_test_booking($1) as result',[expiredSession])).rows[0].result.success,true,'expired session does not block deletion');
  check(await count('developer_test_sessions',expiredSession),0,'expired authorization removed with booking');
  await fails(protectedBooking,'BOOKING_HAS_LIVE_PROVIDER_PAYMENT');
  check(await count('payment_records',protectedBooking),1,'payment retained');
  await fails(payout,'BOOKING_HAS_PAYOUT');
  await fails(refund,'BOOKING_HAS_REFUND');
  await fails(transfer,'BOOKING_HAS_TRANSFER');
  await fails(manualConfirmed,'BOOKING_HAS_PAYMENT_EVIDENCE');
  await fails(mixedEvent,'BOOKING_HAS_LIVE_PROVIDER_PAYMENT');
  await fails(crossLinked,'BOOKING_HAS_PAYMENT_EVIDENCE');
  await fails(blockedByFk,'BOOKING_HAS_OTHER_REFERENCE');
  check(await count('booking_drivers',blockedByFk),1,'failed FK deletion rolls back assignments');
  check(await count('package_activities',blockedByFk),1,'failed FK deletion rolls back activities');
  check((await db.query("select count(*)::int as n from audit_logs where record_id=$1",[blockedByFk])).rows[0].n,0,'failed deletion rolls back audit');
  check((await db.query('select administrator_delete_test_booking($1) as result',[sandbox])).rows[0].result.success,true,'confirmed PayMongo sandbox booking deletes');
  for (const table of ['package_bookings','payment_records','booking_payment_requirements','payment_allocations','developer_test_sessions','booking_drivers','package_activities','booking_itinerary_items'])
    check(await count(table,sandbox),0,`${table} removed for sandbox booking`);
  check((await db.query('select count(*)::int as n from payment_provider_events where provider_payment_id=$1',['sandbox-payment'])).rows[0].n,0,'sandbox event removed without orphan');
  check((await db.query('select administrator_delete_test_booking($1) as result',[manualPending])).rows[0].result.success,true,'pending internal payment booking deletes');
  for (const table of ['package_bookings','payment_records','payment_allocations','booking_payment_requirements','booking_custom_fare_quotes','booking_stop_waiting_charges'])
    check(await count(table,manualPending),0,`${table} removed for pending internal booking`);
  check((await db.query('select administrator_delete_test_booking($1) as result',[good])).rows[0].result.success,true,'eligible booking deletes');
  for (const table of ['package_bookings','package_activities','booking_drivers','booking_itinerary_items','developer_test_sessions','booking_payment_requirements','booking_participant_live_locations','trip_status_logs','notifications','conversations','shared_trip_links'])
    check(await count(table,good),0,`${table} removed through controlled transaction`);
  check((await db.query('select count(*)::int as n from messages where conversation_id=$1',[id(110)])).rows[0].n,0,'booking messages removed');
  check((await db.query('select count(*)::int as n from conversation_members where conversation_id=$1',[id(110)])).rows[0].n,0,'booking conversation members removed');
  check((await db.query('select count(*)::int as n from shared_trip_access_logs where link_id=$1',[id(111)])).rows[0].n,0,'shared trip access logs removed');
  check((await db.query('select count(*)::int as n from booking_driver_arrivals where booking_driver_id=$1',[id(30)])).rows[0].n,0,'arrival evidence has no orphan');
  check((await db.query('select count(*)::int as n from driver_journey_evidence where booking_driver_id=$1',[id(30)])).rows[0].n,0,'journey evidence has no orphan');
  check((await db.query('select count(*)::int as n from notification_deliveries where notification_id=$1',[String(noticeId)])).rows[0].n,0,'notification delivery cleaned with booking notice');
  check((await db.query('select activity_id from driver_live_locations where driver_id=$1',[driver])).rows[0].activity_id,null,'shared location retained without deleted activity');
  check((await db.query("select count(*)::int as n from audit_logs where action='DEVELOPER_TEST_BOOKING_DELETE'")).rows[0].n,5,'each successful deletion audited');
  await fails(good,'BOOKING_NOT_FOUND');
  console.log(`PASS: ${checks} safe test-booking delete checks`);
} finally { await db.close(); }
