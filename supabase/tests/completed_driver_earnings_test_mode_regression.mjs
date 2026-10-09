// In-memory PostgreSQL regression; never connects to or mutates a linked project.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const id = value => `00000000-0000-0000-0000-${String(value).padStart(12, '0')}`;
const tourist = id(1), driver = id(2), booking = id(3), assignment = id(4);
const payment = id(5), allocation = id(6), requirement = id(7), dispute = id(8);
const futureBooking = id(9), futureAssignment = id(10);
const scalar = async (sql, params = []) =>
  Object.values((await db.query(sql, params)).rows[0])[0];

try {
  await db.exec(`
    create role anon; create role authenticated; create schema auth;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('test.uid', true), '')::uuid $$;
    create function public.is_provincial_admin() returns boolean
      language sql stable as $$ select false $$;
    create function public.subtenant_can_access_booking(uuid) returns boolean
      language sql stable as $$ select false $$;
    create function public.developer_test_schedule_bypass_authorized(uuid, uuid)
      returns boolean language sql stable as $$
        select current_setting('test.bypass', true) = 'true' $$;
    create function public.set_updated_at() returns trigger language plpgsql as $$
      begin new.updated_at=now(); return new; end $$;

    create table public.profiles(id uuid primary key, first_name text,
      last_name text, full_name text);
    create table public.tour_packages(id bigint primary key, title text);
    create table public.package_bookings(
      id uuid primary key, package_id bigint references tour_packages(id),
      tourist_id uuid references profiles(id), status text, booking_status text,
      scheduled_start_at timestamptz, completed_at timestamptz,
      updated_at timestamptz default now());
    create table public.booking_drivers(
      id uuid primary key, booking_id uuid references package_bookings(id),
      driver_id uuid references profiles(id), status text, journey_state text,
      completed_at timestamptz);
    create table public.payment_records(
      id uuid primary key, booking_id uuid references package_bookings(id),
      status text, provider text, payment_method text, payment_stage text,
      paid_at timestamptz, receipt_no text, provider_payment_id text,
      provider_reference text, external_reference_no text);
    create table public.payment_allocations(
      id uuid primary key, payment_record_id uuid references payment_records(id),
      booking_id uuid references package_bookings(id),
      booking_driver_id uuid references booking_drivers(id),
      driver_id uuid references profiles(id), gross_amount numeric,
      platform_fee numeric, driver_amount numeric, split_basis_points integer,
      currency text, status text, provider_transfer_status text,
      paid_at timestamptz, created_at timestamptz default now(),
      updated_at timestamptz default now());
    create table public.booking_payment_requirements(
      id uuid primary key, booking_id uuid references package_bookings(id),
      status text, satisfied_by_payment_record_id uuid references payment_records(id));
    create table public.payment_disputes(
      id uuid primary key, payment_record_id uuid references payment_records(id),
      booking_id uuid references package_bookings(id), status text);
    create table public.refund_requests(
      id uuid primary key default gen_random_uuid(),
      payment_record_id uuid references payment_records(id),
      booking_id uuid references package_bookings(id), status text);
  `);

  const migration = readFileSync(new URL(
    '../migrations/20261009140000_completed_driver_earnings_and_test_tracking.sql',
    import.meta.url), 'utf8');
  await db.exec(migration);

  await db.query('insert into profiles values($1,$2,$3,$4),($5,$6,$7,$8)', [
    tourist, 'Juan', 'Dela Cruz', 'Juan Dela Cruz',
    driver, 'Dina', 'Driver', 'Dina Driver',
  ]);
  await db.exec("insert into tour_packages values(1,'Baliwag Heritage Tour')");
  await db.query(`insert into package_bookings values(
    $1,1,$2,'completed','completed',now()-interval '1 hour',now(),now())`,
    [booking, tourist]);
  await db.query(`insert into booking_drivers values(
    $1,$2,$3,'completed','completed',now())`, [assignment, booking, driver]);
  await db.query(`insert into payment_records values(
    $1,$2,'confirmed','paymongo','gcash','down_payment',now(),
    'R-1','pay_1','provider_1',null)`, [payment, booking]);
  await db.query(`insert into booking_payment_requirements values(
    $1,$2,'satisfied',$3)`, [requirement, booking, payment]);
  await db.query(`insert into payment_allocations(
    id,payment_record_id,booking_id,booking_driver_id,driver_id,gross_amount,
    platform_fee,driver_amount,split_basis_points,currency,status)
    values($1,$2,$3,$4,$5,900,0,900,10000,'PHP','eligible')`,
    [allocation, payment, booking, assignment, driver]);
  await db.query('select public.recompute_booking_driver_earnings($1)', [booking]);
  assert.equal(await scalar(
    'select earning_status from payment_allocations where id=$1', [allocation]),
  'completed');
  assert.equal(await scalar(
    'select status from payment_allocations where id=$1', [allocation]),
  'eligible', 'provider payout transport must remain independent');

  await db.query('insert into payment_disputes values($1,$2,$3,$4)',
    [dispute, payment, booking, 'open']);
  assert.equal(await scalar(
    'select earning_status from payment_allocations where id=$1', [allocation]),
  'disputed');
  await db.query("update payment_disputes set status='rejected' where id=$1", [dispute]);
  assert.equal(await scalar(
    'select earning_status from payment_allocations where id=$1', [allocation]),
  'completed');
  await db.query("insert into refund_requests(payment_record_id,booking_id,status) values($1,$2,'pending')",
    [payment, booking]);
  assert.equal(await scalar(
    'select earning_status from payment_allocations where id=$1', [allocation]),
  'refund_pending');

  await db.query(`insert into package_bookings values(
    $1,1,$2,'confirmed','confirmed',now()+interval '1 day',null,now())`,
    [futureBooking, tourist]);
  await db.query(`insert into booking_drivers values(
    $1,$2,$3,'accepted','assigned',null)`,
    [futureAssignment, futureBooking, driver]);
  await db.query("select set_config('test.uid',$1,false)", [driver]);
  await db.query("select set_config('test.bypass','false',false)");
  assert.equal(await scalar(
    'select public.can_access_live_tour_tracking($1,$2)',
    [futureBooking, driver]), false);
  await db.query("select set_config('test.bypass','true',false)");
  assert.equal(await scalar(
    'select public.can_access_live_tour_tracking($1,$2)',
    [futureBooking, driver]), true);
  const eligibility = await scalar(
    'select public.get_live_tour_tracking_eligibility($1)', [futureBooking]);
  assert.equal(eligibility.reason_code, 'TEST_MODE_SCHEDULE_BYPASS');

  console.log('PASS: completed earnings, exception states, and TEST MODE schedule bypass');
} finally {
  await db.close();
}
