import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const booking = '00000000-0000-0000-0000-000000000001';
const payment = '00000000-0000-0000-0000-000000000002';
const laterBooking = '00000000-0000-0000-0000-000000000003';
const value = async (sql) => (await db.query(sql)).rows[0];

try {
  await db.exec(`
    create role anon; create role authenticated;
    create table public.payment_records (
      id uuid primary key default gen_random_uuid(),
      booking_id uuid, payment_stage text, amount numeric(14,2),
      status text default 'pending_confirmation',
      created_at timestamptz default now(), paid_at timestamptz
    );
    create table public.booking_stop_waiting_charges (
      booking_id uuid, status text, additional_amount numeric(14,2),
      finalized_at timestamptz
    );
  `);
  await db.exec(readFileSync(new URL(
    '../migrations/20261009120000_remaining_payment_component_snapshot.sql',
    import.meta.url), 'utf8'));

  await db.query(`insert into payment_records(booking_id,payment_stage,amount)
    values($1,'remaining_balance',1800)`, [booking]);
  let row = await value(`select remaining_package_component,
    additional_waiting_component,amount from payment_records limit 1`);
  assert.equal(Number(row.remaining_package_component), 1800);
  assert.equal(Number(row.additional_waiting_component), 0);

  await db.query(`insert into booking_stop_waiting_charges
    (booking_id,status,additional_amount,finalized_at) values
    ($1,'finalized',100,now()),($1,'finalized',50,now())`, [booking]);
  await db.query(`insert into payment_records(booking_id,payment_stage,amount)
    values($1,'remaining_balance',1950)`, [booking]);
  row = await value(`select remaining_package_component,
    additional_waiting_component,amount from payment_records
    order by amount desc limit 1`);
  assert.equal(Number(row.remaining_package_component), 1800);
  assert.equal(Number(row.additional_waiting_component), 150);
  assert.equal(Number(row.amount), 1950);

  // The booking can owe another waiting fee after its first remaining payment.
  // Historical finalized charges must not be charged twice or block checkout.
  await db.query(`insert into payment_records(booking_id,payment_stage,amount,
    status,paid_at) values($1,'remaining_balance',1800,'confirmed',
    '2026-01-01')`, [laterBooking]);
  await db.query(`insert into booking_stop_waiting_charges
    (booking_id,status,additional_amount,finalized_at) values
    ($1,'finalized',40,'2026-01-02')`, [laterBooking]);
  await db.query(`insert into payment_records(booking_id,payment_stage,amount,
    status,paid_at) values($1,'remaining_balance',40,'confirmed',
    '2026-01-03')`, [laterBooking]);
  await db.query(`insert into booking_stop_waiting_charges
    (booking_id,status,additional_amount,finalized_at) values
    ($1,'finalized',20,'2026-01-04')`, [laterBooking]);
  await db.query(`insert into payment_records(booking_id,payment_stage,amount)
    values($1,'remaining_balance',20)`, [laterBooking]);
  row = await value(`select remaining_package_component,
    additional_waiting_component from payment_records
    where booking_id='${laterBooking}' and amount=20`);
  assert.equal(Number(row.remaining_package_component), 0);
  assert.equal(Number(row.additional_waiting_component), 20);

  await db.query(`insert into payment_records(id,booking_id,payment_stage,amount)
    values($1,$2,'down_payment',500)`, [payment,booking]);
  row = await value(`select remaining_package_component,
    additional_waiting_component from payment_records where id='${payment}'`);
  assert.equal(row.remaining_package_component, null);
  assert.equal(row.additional_waiting_component, null);

  await assert.rejects(() => db.query(`update payment_records
    set additional_waiting_component=0 where amount=1950`),
  /PAYMENT_COMPONENT_SNAPSHOT_IMMUTABLE/);
  await assert.rejects(() => db.query(`insert into payment_records(
    booking_id,payment_stage,amount,additional_waiting_component)
    values($1,'remaining_balance',100,999)`, [booking]),
  /PAYMENT_COMPONENTS_OUT_OF_SYNC/);
  await db.query(`insert into booking_stop_waiting_charges
    (booking_id,status,additional_amount) values ($1,'active',0)`, [booking]);
  await assert.rejects(() => db.query(`insert into payment_records(
    booking_id,payment_stage,amount) values($1,'remaining_balance',1950)`,
  [booking]), /WAITING_CHARGE_NOT_FINALIZED/);

  console.log('PASS: waiting snapshots, repeat fee after settlement, immutable history and active-charge guard');
} finally {
  await db.close();
}
