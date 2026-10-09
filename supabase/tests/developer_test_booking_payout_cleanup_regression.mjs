import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const admin = id(1), tourist = id(2);
const pending = id(10), sandboxPaid = id(11), live = id(12);
const processing = id(13), disabled = id(14), noSession = id(15);
const count = async (table, booking) => (await db.query(
  `select count(*)::integer as n from ${table} where ${table === 'package_bookings' ? 'id' : 'booking_id'}=$1`,
  [booking],
)).rows[0].n;
const fails = (booking, code) => assert.rejects(
  () => db.query('select public.administrator_delete_test_booking($1)', [booking]),
  new RegExp(code),
);

try {
  await db.exec(`
    create role anon; create role authenticated; create schema auth;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('test.uid',true),'')::uuid $$;
    create table profiles(id uuid primary key, role text);
    create function public.is_system_administrator() returns boolean
      language sql stable as $$ select exists(select 1 from public.profiles
        where id=auth.uid() and role='administrator') $$;
    create table system_settings(singleton boolean primary key,
      developer_testing_enabled boolean);
    create table package_bookings(id uuid primary key, status text,
      booking_status text);
    create function public.booking_test_admin_authorized(uuid) returns boolean
      language sql stable as $$ select public.is_system_administrator()
        and exists(select 1 from public.package_bookings where id=$1) $$;
    create table developer_test_sessions(booking_id uuid references package_bookings(id)
      on delete cascade,status text,expires_at timestamptz);
    create table package_activities(id uuid primary key,
      booking_id uuid references package_bookings(id) on delete cascade);
    create table booking_drivers(id uuid primary key,
      booking_id uuid references package_bookings(id) on delete cascade,
      activity_id uuid references package_activities(id));
    create table driver_live_locations(driver_id uuid,
      activity_id uuid references package_activities(id));
    create table payment_records(id uuid primary key,
      booking_id uuid references package_bookings(id),provider text,
      provider_livemode boolean,status text,paid_at timestamptz,
      payee_confirmed_at timestamptz,receipt_no text,external_reference_no text,
      proof_image_url text,provider_payment_id text,provider_checkout_id text,
      provider_reference text);
    create table payment_allocations(id uuid primary key,
      booking_id uuid references package_bookings(id),
      payment_record_id uuid references payment_records(id),status text,
      provider_transfer_id text,provider_transfer_status text,paid_at timestamptz);
    create table payout_records(booking_id uuid references package_bookings(id),
      source_payment_record_id uuid references payment_records(id),
      payment_allocation_id uuid references payment_allocations(id),
      provider_livemode boolean,status text);
    create table payment_provider_events(payment_record_id uuid references
      payment_records(id) on delete set null,provider text,
      provider_livemode boolean,provider_payment_id text,
      provider_checkout_id text);
    create table booking_payment_requirements(booking_id uuid references
      package_bookings(id),satisfied_by_payment_record_id uuid references
      payment_records(id));
    create table refund_requests(booking_id uuid references package_bookings(id));
    create table payment_disputes(booking_id uuid references package_bookings(id));
    create table emergency_alerts(booking_id uuid references package_bookings(id));
    create table driver_reviews(booking_id uuid references package_bookings(id));
    create table package_reviews(booking_id uuid references package_bookings(id));
    create table tourist_reviews(booking_id uuid references package_bookings(id));
    create table booking_stop_waiting_charges(booking_id uuid references package_bookings(id));
    create table booking_custom_fare_quotes(booking_id uuid references package_bookings(id));
    create table trip_status_logs(booking_id uuid references package_bookings(id));
    create table notifications(id bigint generated always as identity primary key,
      booking_id uuid references package_bookings(id) on delete set null);
    create table notification_deliveries(notification_id text);
    create table conversations(booking_id uuid references package_bookings(id));
    create table audit_logs(actor_id uuid,action text,table_name text,
      record_id text,description text);
    insert into profiles values('${admin}','administrator'),('${tourist}','tourist');
    insert into system_settings values(true,true);
  `);
  const sql = readFileSync(new URL(
    '../migrations/20261009090000_developer_test_booking_payout_cleanup.sql',
    import.meta.url), 'utf8');
  await db.exec(sql);
  for (const booking of [pending,sandboxPaid,live,processing,disabled,noSession]) {
    await db.query('insert into package_bookings values($1,$2,$3)',
      [booking,'confirmed','on_tour']);
    if (booking !== noSession) await db.query(
      "insert into developer_test_sessions values($1,'active',now()+interval '1 hour')",
      [booking]);
  }
  for (const [n,booking,status,livemode,transfer] of [
    [20,pending,'pending',false,null],
    [21,sandboxPaid,'paid',false,'sandbox-transfer'],
    [22,live,'pending',true,null],
    [23,processing,'processing',false,null],
  ]) {
    await db.query(`insert into payment_records(id,booking_id,provider,
      provider_livemode,status) values($1,$2,'paymongo',false,'confirmed')`,
      [id(n),booking]);
    await db.query(`insert into payment_allocations(id,booking_id,
      payment_record_id,status,provider_transfer_id) values($1,$2,$3,$4,$5)`,
      [id(n+10),booking,id(n),status,transfer]);
    await db.query(`insert into payout_records values($1,$2,$3,$4,$5)`,
      [booking,id(n),id(n+10),livemode,status]);
  }
  await db.query("select set_config('test.uid',$1,false)",[tourist]);
  await fails(pending,'SYSTEM_ADMINISTRATOR_REQUIRED');
  assert.equal(await count('payout_records',pending),1);
  await db.query("select set_config('test.uid',$1,false)",[admin]);
  await fails(live,'BOOKING_HAS_PRODUCTION_PAYOUT');
  await fails(processing,'BOOKING_HAS_PRODUCTION_PAYOUT');
  await fails(noSession,'ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED');
  await db.query('update system_settings set developer_testing_enabled=false');
  await fails(disabled,'ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED');
  await db.query('update system_settings set developer_testing_enabled=true');
  for (const booking of [pending,sandboxPaid]) {
    const result = (await db.query(
      'select public.administrator_delete_test_booking($1) as result',
      [booking],
    )).rows[0].result;
    assert.equal(result.success,true);
    for (const table of ['package_bookings','payment_records',
      'payment_allocations','payout_records','developer_test_sessions']) {
      assert.equal(await count(table,booking),0,`${table} removed`);
    }
    assert.equal((await db.query(`select count(*)::integer as n from audit_logs
      where record_id=$1`,[booking])).rows[0].n,1);
  }
  assert.equal(await count('package_bookings',live),1);
  assert.equal(await count('payout_records',live),1);
  assert.equal(await count('package_bookings',processing),1);
  console.log('PASS: sandbox payout and booking deleted; live and in-flight payouts retained');
} finally {
  await db.close();
}
