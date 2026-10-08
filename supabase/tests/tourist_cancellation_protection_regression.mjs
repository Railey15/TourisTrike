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
    create table profiles(id uuid primary key, role text);
    insert into profiles values ('${id(1)}','tourist'),
      ('${id(2)}','administrator');
    create function current_profile_role() returns text language sql stable
      as $$ select role from public.profiles where id = auth.uid() $$;
    create function is_system_administrator() returns boolean
      language sql stable as $$ select public.current_profile_role() = 'administrator' $$;
    create table package_bookings (
      id uuid primary key, tourist_id uuid, cancelled_by uuid,
      cancelled_at timestamptz, cancellation_type text
    );
    create table notifications (
      user_id uuid, booking_id uuid, title text, body text,
      type text, is_read boolean, dedupe_key text
    );
    create unique index notifications_dedupe on notifications(dedupe_key)
      where dedupe_key is not null;
    create function cancel_package_booking(uuid,text,text,text)
      returns jsonb language plpgsql as $$
    begin
      update public.package_bookings set cancelled_by = auth.uid(),
        cancelled_at = clock_timestamp(),
        cancellation_type = case when $2 = 'approved_exception'
          then 'exceptional' else 'late' end
      where id = $1 and cancelled_at is null;
      if not found then raise exception 'BOOKING_ALREADY_CANCELLED'; end if;
      return jsonb_build_object('cancellation_type','late');
    end $$;
    create function create_package_booking(jsonb,jsonb,jsonb)
      returns package_bookings language plpgsql as $$
    declare b public.package_bookings;
    begin
      insert into public.package_bookings(id,tourist_id)
        values(($1->>'id')::uuid,auth.uid()) returning * into b;
      return b;
    end $$;
    insert into package_bookings(id,tourist_id) values
      ('${id(11)}','${id(1)}'), ('${id(12)}','${id(1)}'),
      ('${id(13)}','${id(1)}');
  `);
  const migration = readFileSync(new URL(
    '../migrations/20261009040000_tourist_late_cancellation_protection.sql',
    import.meta.url), 'utf8');
  await db.exec(migration);
  await db.query(`select set_config('test.uid',$1,false)`, [id(1)]);
  for (const n of [11, 12, 13]) {
    await db.query(`select cancel_package_booking($1,'late',null,'general')`,
      [id(n)]);
  }
  const restriction = (await db.query(`select status,
    restricted_until > now() as active from tourist_booking_restrictions
    where tourist_id = $1`, [id(1)])).rows[0];
  assert.equal(restriction.status, 'active');
  assert.equal(restriction.active, true);
  await assert.rejects(() => db.query(
    `select create_package_booking($1::jsonb,'[]','[]')`,
    [JSON.stringify({id: id(14)})]),
  /NEW_BOOKINGS_TEMPORARILY_RESTRICTED/);
  const appeal = (await db.query(
    `select appeal_tourist_booking_restriction($1) as id`,
    ['Please review this cancellation restriction.']
  )).rows[0].id;
  await db.query(`select set_config('test.uid',$1,false)`, [id(2)]);
  await db.query(`select administrator_review_booking_restriction_appeal(
    $1,true,'Reviewed')`, [appeal]);
  await db.query(`select set_config('test.uid',$1,false)`, [id(1)]);
  const booking = (await db.query(
    `select (create_package_booking($1::jsonb,'[]','[]')).id as id`,
    [JSON.stringify({id: id(14)})]
  )).rows[0];
  assert.equal(booking.id, id(14));
  console.log('PASS: warning threshold, backend booking gate and appeal');
} finally {
  await db.close();
}
