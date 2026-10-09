// In-memory PostgreSQL regression; never connects to or mutates a linked project.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const id = value => `00000000-0000-0000-0000-${String(value).padStart(12, '0')}`;
const tourist = id(1), outsider = id(2), booking = id(3), activity = id(4);

const insertAlert = (alertId, touristId = tourist) => db.query(
  `insert into public.emergency_alerts(id,tourist_id,booking_id)
   values($1,$2,$3)`,
  [alertId, touristId, booking],
);

try {
  await db.exec(`
    create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('test.uid', true), '')::uuid $$;

    create table public.package_bookings(
      id uuid primary key,
      tourist_id uuid not null,
      status text,
      booking_status text,
      refund_status text default 'none',
      picked_up_at timestamptz
    );
    create table public.package_activities(
      id uuid primary key,
      booking_id uuid not null references public.package_bookings(id),
      status text,
      tour_status text,
      updated_at timestamptz default now()
    );
    create table public.emergency_alerts(
      id uuid primary key,
      tourist_id uuid not null,
      booking_id uuid
    );
    alter table public.emergency_alerts enable row level security;
    create policy "tourist_insert_own_emergency"
      on public.emergency_alerts for insert to authenticated
      with check (auth.uid() = tourist_id);

    insert into public.package_bookings values(
      '${booking}','${tourist}','ongoing','on_tour','none',now()
    );
    insert into public.package_activities values(
      '${activity}','${booking}','ongoing','on_tour',now()
    );
  `);

  const migration = readFileSync(new URL(
    '../migrations/20261009180000_completed_tour_emergency_guard.sql',
    import.meta.url), 'utf8');
  await db.exec(migration);

  await insertAlert(id(10));
  assert.equal((await db.query(
    'select count(*)::int as count from public.emergency_alerts')).rows[0].count,
  1, 'an active picked-up tour must still permit emergency assistance');

  await db.query(
    "update package_bookings set booking_status='completed' where id=$1",
    [booking],
  );
  await assert.rejects(() => insertAlert(id(11)),
    /EMERGENCY_ALERT_NOT_ALLOWED_FOR_TERMINAL_TOUR/);

  await db.query(
    "update package_bookings set booking_status='cancelled' where id=$1",
    [booking],
  );
  await assert.rejects(() => insertAlert(id(12)),
    /EMERGENCY_ALERT_NOT_ALLOWED_FOR_TERMINAL_TOUR/);

  await db.query(
    "update package_bookings set booking_status='on_tour',refund_status='refunded' where id=$1",
    [booking],
  );
  await assert.rejects(() => insertAlert(id(13)),
    /EMERGENCY_ALERT_NOT_ALLOWED_FOR_TERMINAL_TOUR/);

  await db.query(
    "update package_bookings set refund_status='none',picked_up_at=null where id=$1",
    [booking],
  );
  await db.query(
    "update package_activities set status='pending',tour_status='waiting_driver' where booking_id=$1",
    [booking],
  );
  await assert.rejects(() => insertAlert(id(14)),
    /EMERGENCY_ALERT_REQUIRES_ACTIVE_TOUR/);

  await db.exec(`
    grant usage on schema public, auth to authenticated;
    grant insert on public.emergency_alerts to authenticated;
    grant select on public.package_bookings, public.package_activities to authenticated;
  `);
  await db.query("select set_config('test.uid',$1,false)", [outsider]);
  await db.exec('set role authenticated');
  await assert.rejects(() => insertAlert(id(15), outsider),
    /row-level security policy|EMERGENCY_ALERT_BOOKING_MISMATCH/);
  await db.exec('reset role');

  console.log('PASS: emergency alerts are active-tour-only and terminal-safe');
} finally {
  await db.close();
}
