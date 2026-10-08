import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
try {
  await db.exec(`
    create schema auth; create role anon; create role authenticated;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('test.uid', true), '')::uuid $$;
    create table profiles (id uuid primary key, role text, city text,
      province text, is_online boolean, is_available boolean);
    create table subtenant_details (id uuid primary key, city text,
      province text, is_active boolean);
    create table driver_details (driver_id uuid, status text,
      approved_at timestamptz);
    create table driver_applications (driver_id uuid, status text,
      submitted_at timestamptz);
    create table package_bookings (
      id uuid primary key, tourist_id uuid, municipality text, province text,
      additional_tricycle_count smallint default 0,
      additional_tricycle_reason text,
      additional_tricycle_explanation text,
      required_drivers integer, accepted_drivers_count integer,
      adults integer, children integer, total_passengers integer,
      travel_date date, scheduled_start_at timestamptz,
      estimated_end_at timestamptz, arrived_at timestamptz,
      picked_up_at timestamptz, status text, booking_status text,
      total_amount numeric default 700, downpayment_amount numeric default 0,
      remaining_balance numeric default 700, updated_at timestamptz);
    create table booking_drivers (booking_id uuid, driver_id uuid,
      status text);
    create table package_activities (booking_id uuid, tour_status text);
    create table payment_records (id uuid primary key, booking_id uuid,
      payment_stage text, status text, amount numeric);
    create table booking_payment_requirements (booking_id uuid,
      payment_stage text, status text, satisfied_by_payment_record_id uuid,
      amount numeric);
    create table payment_allocations (payment_record_id uuid,
      gross_amount numeric);
    create table notifications (user_id uuid, title text, body text,
      type text, is_read boolean, dedupe_key text);
    create unique index notifications_dedupe on notifications(dedupe_key)
      where dedupe_key is not null;
    create table audit_logs (actor_id uuid, action text, table_name text,
      record_id text, description text);
    create function cities_match(text, text) returns boolean language sql
      immutable as $$ select lower(trim($1)) = lower(trim($2)) $$;
    create function current_profile_role() returns text language sql stable
      as $$ select role from public.profiles where id = auth.uid() $$;
    create function minimum_required_tricycles(integer) returns integer
      language sql immutable as $$ select ceil($1::numeric / 3)::integer $$;
    insert into profiles values
      ('${id(1)}', 'subtenant', 'Baliwag', 'Bulacan', false, false),
      ('${id(2)}', 'tourist', 'Baliwag', 'Bulacan', false, false),
      ('${id(3)}', 'driver', 'Baliwag', 'Bulacan', true, true),
      ('${id(4)}', 'subtenant', 'Other', 'Bulacan', false, false);
    insert into subtenant_details values
      ('${id(1)}', 'Baliwag', 'Bulacan', true),
      ('${id(4)}', 'Other', 'Bulacan', true);
    insert into driver_details values ('${id(3)}', 'approved', now());
    insert into package_bookings (
      id, tourist_id, municipality, province, additional_tricycle_count,
      additional_tricycle_reason, required_drivers, accepted_drivers_count,
      adults, children, total_passengers, travel_date, scheduled_start_at,
      estimated_end_at, status, booking_status
    ) values (
      '${id(5)}', '${id(2)}', 'Baliwag', 'Bulacan', 2,
      'extra_luggage', 1, 0, 2, 0, 2,
      (now() at time zone 'Asia/Manila')::date + 2,
      now() + interval '2 days', now() + interval '2 days 3 hours',
      'pending', 'waiting_for_drivers'
    );
  `);
  const migration = readFileSync(
    new URL('../migrations/20261008020000_additional_tricycle_review.sql',
      import.meta.url), 'utf8');
  await db.exec(migration);
  await db.exec(`
    create trigger trg_validate_booking_schedule_and_capacity
    before update of required_drivers on package_bookings
    for each row execute function validate_booking_schedule_and_capacity();
    create trigger guard_additional_tricycle_request_update
    before update of additional_tricycle_count,additional_tricycle_reason,
      additional_tricycle_explanation on package_bookings
    for each row execute function guard_additional_tricycle_request_update();
  `);
  assert.equal((await db.query(`select additional_tricycle_request_status as s
    from package_bookings where id = $1`, [id(5)])).rows[0].s, 'pending');
  await db.query(`select set_config('test.uid', $1, false)`, [id(4)]);
  await assert.rejects(() => db.query(
    `select review_additional_tricycle_request($1, true)`, [id(5)]
  ), /MTO_SCOPE_REQUIRED/);
  await db.query(`select set_config('test.uid', $1, false)`, [id(1)]);
  const result = (await db.query(
    `select review_additional_tricycle_request($1, true) as value`, [id(5)]
  )).rows[0].value;
  assert.equal(result.required_drivers, 3);
  assert.equal(result.status, 'approved');
  const row = (await db.query(`select required_drivers,
    additional_tricycle_approved_count, booking_status
    from package_bookings where id = $1`, [id(5)])).rows[0];
  assert.equal(row.required_drivers, 3);
  assert.equal(row.additional_tricycle_approved_count, 2);
  assert.equal(row.booking_status, 'waiting_for_drivers');
  assert.equal((await db.query(`select count(*)::integer as n from notifications`))
    .rows[0].n, 1);
  await assert.rejects(() => db.query(
    `select review_additional_tricycle_request($1, true)`, [id(5)]
  ), /REQUEST_NOT_PENDING/);
  await db.query(`insert into package_bookings (
    id,tourist_id,municipality,province,additional_tricycle_count,
    additional_tricycle_reason,required_drivers,accepted_drivers_count,
    adults,children,total_passengers,travel_date,scheduled_start_at,
    estimated_end_at,status,booking_status,total_amount,
    downpayment_amount,remaining_balance,additional_tricycle_request_status
  ) values (
    '${id(8)}','${id(2)}','Baliwag','Bulacan',1,'extra_luggage',
    1,1,2,0,2,(now() at time zone 'Asia/Manila')::date + 2,
    now() + interval '2 days',now() + interval '2 days 3 hours',
    'confirmed','accepted',1000,300,700,'pending'
  )`);
  await db.query(`insert into booking_drivers values
    ('${id(8)}','${id(3)}','accepted')`);
  await db.query(`insert into payment_records values
    ('${id(9)}','${id(8)}','down_payment','confirmed',300)`);
  await db.query(`insert into payment_allocations values ('${id(9)}',300)`);
  await db.query(`insert into booking_payment_requirements values
    ('${id(8)}','down_payment','satisfied','${id(9)}',300),
    ('${id(8)}','remaining_balance','required',null,700)`);
  const accepted = (await db.query(`select review_additional_tricycle_request(
    $1,true) as value`,[id(8)])).rows[0].value;
  assert.equal(accepted.required_drivers,2);
  const preserved = (await db.query(`select total_amount,downpayment_amount,
    remaining_balance,required_drivers,booking_status from package_bookings
    where id=$1`,[id(8)])).rows[0];
  assert.equal(Number(preserved.total_amount),1000);
  assert.equal(Number(preserved.downpayment_amount),300);
  assert.equal(Number(preserved.remaining_balance),700);
  assert.equal(preserved.booking_status,'waiting_for_drivers');
  assert.equal(Number((await db.query(`select sum(gross_amount) as amount
    from payment_allocations where payment_record_id=$1`,[id(9)]))
    .rows[0].amount),300);
  await db.query(`select set_config('test.uid',$1,false)`,[id(2)]);
  await assert.rejects(() => db.query(`select request_additional_tricycles(
    $1,1::smallint,'extra_luggage')`,[id(8)]),/REQUEST_ALREADY_EXISTS/);
  await db.query(`select set_config('test.uid',$1,false)`,[id(1)]);
  await db.query(`select set_config('touristrike.additional_review_write','true',false)`);
  await db.query(`select set_config('touristrike.additional_request_write','true',false)`);
  await db.query(`update package_bookings set
    additional_tricycle_request_status='pending',
    additional_tricycle_approved_count=0,required_drivers=1,
    booking_status='accepted' where id=$1`,[id(8)]);
  await db.query(`insert into payment_records values
    ('${id(10)}','${id(8)}','remaining_balance','pending_confirmation',700)`);
  await assert.rejects(() => db.query(`select review_additional_tricycle_request(
    $1,true)`,[id(8)]),/REMAINING_PAYMENT_ALREADY_STARTED/);
  await db.query(`delete from payment_records where id=$1`,[id(10)]);
  await db.query(`update package_bookings set
    additional_tricycle_request_status='none',
    additional_tricycle_count=0 where id=$1`,[id(8)]);
  await db.query(`select set_config('touristrike.additional_review_write','',false)`);
  await db.query(`select set_config('touristrike.additional_request_write','',false)`);
  await db.query(`select set_config('test.uid',$1,false)`,[id(2)]);
  const request = (await db.query(`select request_additional_tricycles(
    $1,1::smallint,'additional_space') as value`,[id(8)])).rows[0].value;
  assert.equal(request.status,'pending');
  await assert.rejects(() => db.query(`select request_additional_tricycles(
    $1,1::smallint,'extra_luggage')`,[id(8)]),/REQUEST_ALREADY_EXISTS/);
  await db.query(`select set_config('test.uid',$1,false)`,[id(1)]);
  await db.query(`update payment_allocations set gross_amount=299
    where payment_record_id=$1`,[id(9)]);
  await assert.rejects(() => db.query(`select review_additional_tricycle_request(
    $1,true)`,[id(8)]),/DOWNPAYMENT_ALLOCATION_REVIEW_REQUIRED/);
  await db.query(`update payment_allocations set gross_amount=300
    where payment_record_id=$1`,[id(9)]);
  await db.query(`update booking_payment_requirements set amount=699
    where booking_id=$1 and payment_stage='remaining_balance'`,[id(8)]);
  await assert.rejects(() => db.query(`select review_additional_tricycle_request(
    $1,true)`,[id(8)]),/UNPAID_BALANCE_REVIEW_REQUIRED/);
  await db.query(`update booking_payment_requirements set amount=700
    where booking_id=$1 and payment_stage='remaining_balance'`,[id(8)]);
  await db.query(`update package_bookings set arrived_at=now() where id=$1`,[id(8)]);
  await assert.rejects(() => db.query(`select review_additional_tricycle_request(
    $1,true)`,[id(8)]),/TOUR_ALREADY_STARTED/);
  await db.exec('grant select, update on package_bookings to authenticated');
  await db.exec('set role authenticated');
  await db.query(`select set_config('touristrike.additional_request_write','true',false)`);
  await assert.rejects(() => db.query(`update package_bookings
    set additional_tricycle_count=2 where id=$1`,[id(8)]),
    /ADDITIONAL_TRICYCLE_REQUEST_IMMUTABLE/);
  await db.query(`select set_config('touristrike.additional_review_write','true',false)`);
  await assert.rejects(() => db.query(`update package_bookings
    set additional_tricycle_request_status='approved' where id=$1`,[id(8)]),
    /ADDITIONAL_TRICYCLE_REVIEW_RPC_REQUIRED/);
  await db.exec('reset role');
  console.log('PASS: MTO scope, approval, real roster target and idempotency');
} finally {
  await db.close();
}
