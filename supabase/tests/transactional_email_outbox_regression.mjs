import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
try {
  await db.exec(`
    create schema auth;
    create role anon; create role authenticated; create role service_role;
    create function auth.role() returns text language sql stable as $$
      select current_setting('test.role', true) $$;
    create table profiles(id uuid primary key);
    create table package_bookings (
      id uuid primary key, tourist_id uuid, status text, booking_status text,
      accepted_drivers_count integer, required_drivers integer,
      completed_at timestamptz);
    create table payment_records (
      id uuid primary key, booking_id uuid, status text,
      payment_stage text, payee_id uuid, amount numeric,
      payment_method text, receipt_no text, paid_at timestamptz,
      payee_confirmed_at timestamptz);
    insert into profiles values ('${id(1)}');
    insert into package_bookings values
      ('${id(2)}','${id(1)}','pending','waiting_for_drivers',0,2,null);
  `);
  const migration = readFileSync(new URL(
    '../migrations/20261008040000_transactional_email_outbox.sql',
    import.meta.url), 'utf8');
  await db.exec(migration);
  await db.exec(`
    update package_bookings set accepted_drivers_count = 2,
      booking_status = 'accepted' where id = '${id(2)}';
    insert into payment_records values
      ('${id(3)}','${id(2)}','pending_confirmation','down_payment',
        null,500,'gcash',null,null,null),
      ('${id(4)}','${id(2)}','pending_confirmation','remaining_balance',
        null,650,'cash',null,null,null);
    update payment_records set status = 'confirmed', paid_at = now();
    update package_bookings set booking_status = 'completed',
      status = 'completed', completed_at = now() where id = '${id(2)}';
    update payment_records set status = 'confirmed';
    update package_bookings set booking_status = 'completed'
      where id = '${id(2)}';
  `);
  assert.equal((await db.query(`select count(*)::integer as n
    from transactional_email_outbox`)).rows[0].n, 4);
  const receipts = (await db.query(`select event_type,
    (payload->>'amount')::numeric as amount
    from transactional_email_outbox where payment_record_id is not null
    order by event_type`)).rows;
  assert.deepEqual(receipts.map(r => Number(r.amount)), [500, 650]);
  await db.exec(`
    update package_bookings set booking_status = 'waiting_for_drivers',
      required_drivers = 3 where id = '${id(2)}';
    update package_bookings set booking_status = 'accepted',
      accepted_drivers_count = 3 where id = '${id(2)}';
  `);
  assert.equal((await db.query(`select count(*)::integer as n
    from transactional_email_outbox where event_type = 'drivers_accepted'`))
    .rows[0].n, 2);
  await assert.rejects(() => db.query(
    `select * from claim_transactional_emails(20)`
  ), /SERVICE_ROLE_REQUIRED/);
  await db.query(`select set_config('test.role','service_role',false)`);
  const claimed = (await db.query(`select * from claim_transactional_emails(20)`))
    .rows;
  assert.equal(claimed.length, 5);
  const job = claimed[0];
  const done = (await db.query(`select finish_transactional_email(
    $1,$2,'sent','provider-1',null) as ok`, [job.id, job.lease_id]))
    .rows[0].ok;
  assert.equal(done, true);
  assert.equal((await db.query(`select count(*)::integer as n
    from transactional_email_outbox where status = 'sent'`)).rows[0].n, 1);
  const retryJob = claimed[1];
  assert.equal((await db.query(`select finish_transactional_email(
    $1,$2,'sent','wrong-lease',null) as ok`,[retryJob.id,id(999)]))
    .rows[0].ok,false);
  assert.equal((await db.query(`select finish_transactional_email(
    $1,$2,'retry',null,'RESEND_503') as ok`,
    [retryJob.id,retryJob.lease_id])).rows[0].ok,true);
  const retryState = (await db.query(`select status,attempts,last_error,
    next_attempt_at from transactional_email_outbox where id=$1`,
    [retryJob.id])).rows[0];
  assert.equal(retryState.status,'pending');
  assert.equal(retryState.attempts,1);
  assert.equal(retryState.last_error,'RESEND_503');
  assert.ok(new Date(retryState.next_attempt_at) > new Date());
  await db.query(`update transactional_email_outbox
    set first_attempt_at=now()-interval '24 hours' where id=$1`,
    [retryJob.id]);
  await db.query('select * from claim_transactional_emails(20)');
  assert.equal((await db.query(`select status from transactional_email_outbox
    where id=$1`,[retryJob.id])).rows[0].status,'dead');
  console.log('PASS: authoritative email events, unique queue and worker lease');
} finally {
  await db.close();
}
