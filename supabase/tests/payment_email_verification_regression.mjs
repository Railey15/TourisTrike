import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const id = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const tourist = id(1);
const other = id(2);
const booking = id(3);
const hash = (character) => character.repeat(64);
const migration = readFileSync(
  new URL('../migrations/20261008000000_payment_email_verification.sql', import.meta.url),
  'utf8',
).replaceAll('\r\n', '\n');
const paymentSql = migration.slice(
  migration.indexOf('do $$'),
  migration.indexOf('-- The current registration'),
);

async function role(value) {
  await db.query("select set_config('test.role', $1, false)", [value]);
}

async function request(user = tourist, stage = 'down_payment', codeHash = hash('a')) {
  return db.query(
    'select public.request_payment_email_verification($1,$2,$3,$4) as result',
    [user, booking, stage, codeHash],
  );
}

async function verify(user = tourist, stage = 'down_payment', codeHash = hash('a')) {
  const result = await db.query(
    'select public.verify_payment_email_code($1,$2,$3,$4) as result',
    [user, booking, stage, codeHash],
  );
  return result.rows[0].result;
}

async function consume(user = tourist, stage = 'down_payment') {
  const result = await db.query(
    'select public.consume_payment_email_verification($1,$2,$3) as result',
    [user, booking, stage],
  );
  return result.rows[0].result;
}

try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create role service_role;
    create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.role() returns text language sql stable as $$
      select nullif(current_setting('test.role', true), '') $$;
    create table public.package_bookings(id uuid primary key, tourist_id uuid);
    create table public.booking_payment_requirements(
      booking_id uuid, payment_stage text, status text, amount numeric,
      primary key(booking_id, payment_stage)
    );
    create function public.is_booking_itinerary_complete(uuid)
    returns boolean language sql stable as $$
      select current_setting('test.itinerary_complete', true) = 'true' $$;
    create function public.is_booking_downpayment_confirmed(uuid)
    returns boolean language sql stable as $$
      select current_setting('test.downpayment_confirmed', true) = 'true' $$;
  `);
  await db.exec(paymentSql);
  const initialRows = (await db.query('select count(*)::integer as count from payment_email_verifications')).rows[0].count;
  await db.exec(paymentSql);
  assert.equal((await db.query('select count(*)::integer as count from payment_email_verifications')).rows[0].count, initialRows);
  await db.query('insert into auth.users(id) values($1),($2)', [tourist, other]);
  await db.query(
    'insert into package_bookings(id,tourist_id) values($1,$2)',
    [booking, tourist],
  );
  await db.query(`insert into booking_payment_requirements values
    ($1,'down_payment','required',3600),
    ($1,'remaining_balance','required',3600)`, [booking]);

  await role('authenticated');
  await assert.rejects(() => request(), /FORBIDDEN/);
  await role('service_role');
  await db.query("select set_config('test.itinerary_complete','false',false), set_config('test.downpayment_confirmed','false',false)");
  await assert.rejects(() => request(other), /NOT_BOOKING_TOURIST/);
  await db.query("update booking_payment_requirements set status='waived' where payment_stage='down_payment'");
  await assert.rejects(() => request(), /PAYMENT_STAGE_NOT_DUE/);
  await db.query("update booking_payment_requirements set status='required' where payment_stage='down_payment'");
  await assert.rejects(() => request(tourist, 'remaining_balance'), /PAYMENT_STAGE_NOT_DUE/);
  await db.query("select set_config('test.itinerary_complete','true',false)");
  await assert.rejects(() => request(tourist, 'remaining_balance'), /PAYMENT_STAGE_NOT_DUE/);
  await db.query("select set_config('test.downpayment_confirmed','true',false)");
  assert.equal((await request()).rows[0].result, 'SENT');
  await assert.rejects(() => request(), /RATE_LIMITED/);
  for (let attempt = 0; attempt < 5; attempt++) {
    assert.equal(await verify(tourist, 'down_payment', hash('b')), 'INCORRECT');
  }
  assert.equal(await verify(), 'RATE_LIMITED');
  await db.query("update payment_email_verifications set sent_at=now()-interval '31 seconds'");
  assert.equal((await request()).rows[0].result, 'SENT');
  await db.query("update payment_email_verifications set expires_at=now()-interval '1 second'");
  assert.equal(await verify(), 'EXPIRED');
  await db.query("update payment_email_verifications set sent_at=now()-interval '31 seconds'");
  assert.equal((await request()).rows[0].result, 'SENT');
  assert.equal(await verify(other), 'EXPIRED');
  assert.equal(await verify(tourist, 'remaining_balance'), 'EXPIRED');
  assert.equal(await verify(tourist, 'down_payment', hash('b')), 'INCORRECT');
  assert.equal(await verify(), 'VERIFIED');
  assert.equal(await consume(), true);
  assert.equal(await consume(), false);

  await db.query("update payment_email_verifications set sent_at=now()-interval '31 seconds'");
  assert.equal((await request(tourist, 'remaining_balance', hash('c'))).rows[0].result, 'SENT');
  assert.equal(await verify(tourist, 'remaining_balance', hash('c')), 'VERIFIED');
  await db.query("update payment_email_verifications set verified_until=now()-interval '1 second' where payment_stage='remaining_balance'");
  assert.equal(await consume(tourist, 'remaining_balance'), false);
  await db.query("update payment_email_verifications set verified_until=now()+interval '5 minutes' where payment_stage='remaining_balance'");
  await db.query("update booking_payment_requirements set amount=3700 where payment_stage='remaining_balance'");
  assert.equal(await consume(tourist, 'remaining_balance'), false);
  const existingRows = (await db.query('select count(*)::integer as count from payment_email_verifications')).rows[0].count;
  await db.exec(paymentSql);
  assert.equal((await db.query('select count(*)::integer as count from payment_email_verifications')).rows[0].count, existingRows);
  await db.exec('alter table payment_email_verifications disable row level security');
  await assert.rejects(() => db.exec(paymentSql), /PAYMENT_OTP_SCHEMA_MISMATCH: table or RLS/);
  await db.exec('alter table payment_email_verifications enable row level security');
  await db.exec('grant select on payment_email_verifications to anon');
  await assert.rejects(() => db.exec(paymentSql), /PAYMENT_OTP_SCHEMA_MISMATCH: policies or grants/);
  await db.exec('revoke select on payment_email_verifications from anon');
  await db.exec('alter table payment_email_verifications add column unexpected text');
  await assert.rejects(() => db.exec(paymentSql), /PAYMENT_OTP_SCHEMA_MISMATCH: columns/);
  console.log('PASS: payment OTP SQL enforces owner, stage, due state, attempts, amount and one-use proof');
} finally {
  await db.close();
}
