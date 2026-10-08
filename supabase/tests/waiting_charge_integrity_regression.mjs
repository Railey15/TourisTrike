import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
try {
  await db.exec(`
    create schema auth;
    create role anon; create role authenticated;
    create function auth.uid() returns uuid language sql stable as $$
      select '${id(1)}'::uuid $$;
    create table package_bookings (
      id uuid primary key, municipality text, province text,
      remaining_balance numeric, tour_waiting_subtenant_id uuid,
      tour_waiting_hourly_rate_snapshot numeric,
      tour_waiting_rate_snapshot numeric,
      tour_waiting_interval_snapshot integer,
      tour_waiting_interval_minutes_snapshot integer
    );
    create table booking_itinerary_items (
      id uuid primary key, booking_id uuid, destination_name text,
      estimated_stay_duration_minutes integer,
      actual_arrival_time timestamptz, actual_departure_time timestamptz
    );
    create table booking_stop_waiting_charges (
      id uuid primary key default gen_random_uuid(), booking_id uuid,
      itinerary_item_id uuid, municipality text, subtenant_id uuid,
      included_minutes integer, arrived_at timestamptz, paid_until timestamptz,
      departed_at timestamptz, interval_minutes integer, hourly_rate numeric,
      rate_per_interval numeric, overtime_seconds integer default 0,
      chargeable_intervals integer default 0, additional_amount numeric default 0,
      test_deadline_override timestamptz,
      test_rate_per_interval_override numeric,
      test_override_kind text,
      status text default 'active', updated_at timestamptz,
      unique (booking_id, itinerary_item_id),
      constraint booking_stop_waiting_effective_amount_check check
        (additional_amount = case
          when test_rate_per_interval_override is not null then
            round(chargeable_intervals * test_rate_per_interval_override, 2)
          else round(chargeable_intervals * coalesce(hourly_rate, 0)
            * interval_minutes / 60.0, 2) end)
    );
    create function can_read_tour_booking(uuid) returns boolean
      language sql stable as $$ select true $$;
    create function resolve_tour_waiting_policy(text, text)
      returns table(subtenant_id uuid, hourly_rate numeric,
        interval_minutes integer, rate_per_interval numeric)
      language sql stable as $$ select null::uuid, 200::numeric,
        15, 50::numeric $$;
    create function resolve_tour_waiting_rate(text, text)
      returns table(subtenant_id uuid, rate numeric)
      language sql stable as $$ select null::uuid, 50::numeric $$;
    create function tour_waiting_chargeable_intervals(numeric, integer)
      returns integer language sql immutable as $$
      select floor($1 / ($2 * 60))::integer $$;
    create function finalize_booking_stop_waiting_charge()
      returns trigger language plpgsql as $$
    declare v_charge booking_stop_waiting_charges; v_intervals integer;
      v_amount numeric; v_seconds integer;
    begin
      if new.actual_departure_time is null or old.actual_departure_time is not null
        then return new; end if;
      select * into v_charge from booking_stop_waiting_charges
        where itinerary_item_id = new.id for update;
      if not found or v_charge.status = 'finalized' then return new; end if;
      v_seconds := greatest(0, floor(extract(epoch from
        new.actual_departure_time - v_charge.paid_until)))::integer;
      v_intervals := tour_waiting_chargeable_intervals(v_seconds,
        v_charge.interval_minutes);
      v_amount := round(v_intervals * coalesce(v_charge.hourly_rate,0)
        * v_charge.interval_minutes / 60.0, 2);
      update booking_stop_waiting_charges set status = 'finalized',
        departed_at = new.actual_departure_time,
        overtime_seconds = v_seconds, chargeable_intervals = v_intervals,
        additional_amount = v_amount where id = v_charge.id;
      update public.package_bookings set
        remaining_balance = remaining_balance + v_amount
        where id = new.booking_id;
      return new;
    end $$;
    create trigger finalize_booking_stop_waiting_charge
      after update of actual_departure_time on booking_itinerary_items
      for each row execute function finalize_booking_stop_waiting_charge();
    create function refresh_active_tour_waiting()
      returns integer language plpgsql as $$
    declare c booking_stop_waiting_charges; v_intervals integer;
      v_amount numeric;
    begin
      v_intervals := tour_waiting_chargeable_intervals(1800,
        c.interval_minutes);
      v_amount := round(v_intervals * coalesce(c.hourly_rate,0)
        * c.interval_minutes / 60.0, 2);
      return 0;
    end $$;
    insert into package_bookings values
      ('${id(2)}', 'Baliwag', 'Bulacan', 500, null, null, 50, 15, 15);
    insert into booking_itinerary_items values
      ('${id(3)}', '${id(2)}', 'Museum', 30,
       now() - interval '75 minutes', null);
    insert into booking_stop_waiting_charges
      (booking_id, itinerary_item_id, municipality, included_minutes,
       arrived_at, paid_until, interval_minutes, rate_per_interval)
      values ('${id(2)}', '${id(3)}', 'Baliwag', 30,
        now() - interval '75 minutes', now() - interval '45 minutes', 15, 50);
  `);
  const migration = readFileSync(
    new URL('../migrations/20261009020000_waiting_charge_integrity.sql',
      import.meta.url), 'utf8');
  await db.exec(migration);
  await db.exec(`
    create trigger snapshot_booking_stop_waiting_charge
      after update of actual_arrival_time on booking_itinerary_items
      for each row execute function snapshot_booking_stop_waiting_charge();
    insert into package_bookings values
      ('${id(4)}', 'Baliwag', 'Bulacan', 500, null, null, 40, 15, 15);
    insert into booking_itinerary_items values
      ('${id(5)}', '${id(4)}', 'Market', 30, null, null);
    update booking_itinerary_items set actual_arrival_time = now()
      where id = '${id(5)}';
  `);
  const bookedRate = (await db.query(`select rate_per_interval,
    hourly_rate from booking_stop_waiting_charges
    where itinerary_item_id = $1`, [id(5)])).rows[0];
  assert.equal(Number(bookedRate.rate_per_interval), 40);
  assert.equal(Number(bookedRate.hourly_rate), 160);
  const summary = (await db.query(
    'select get_booking_waiting_summary($1) as value', [id(2)]
  )).rows[0].value;
  assert.equal(Number(summary.accrued_waiting), 150);
  assert.equal(Number(summary.total_remaining), 650);
  assert.equal(Number(summary.charges[0].additional_amount), 150);
  for (const [minutes, expected] of [
    [0, 0], [14, 0], [15, 50], [16, 50], [30, 100], [45, 150],
  ]) {
    await db.query(`update booking_stop_waiting_charges
      set paid_until = now() - make_interval(mins => $1)
      where itinerary_item_id = $2`, [minutes, id(3)]);
    const value = (await db.query(
      'select get_booking_waiting_summary($1) as value', [id(2)]
    )).rows[0].value;
    assert.equal(Number(value.accrued_waiting), expected,
      `unexpected charge at ${minutes} chargeable minutes`);
  }
  await db.query(`update booking_stop_waiting_charges
    set test_rate_per_interval_override = 75,
        chargeable_intervals = 3, additional_amount = 225
    where itinerary_item_id = $1`, [id(3)]);
  const override = (await db.query(
    'select get_booking_waiting_summary($1) as value', [id(2)]
  )).rows[0].value;
  assert.equal(Number(override.accrued_waiting), 225);
  await db.query(`update booking_stop_waiting_charges
    set test_rate_per_interval_override = null,
        chargeable_intervals = 3, additional_amount = 150
    where itinerary_item_id = $1`, [id(3)]);
  const count = (await db.query(`select count(*)::integer as n
    from booking_stop_waiting_charges where additional_amount = 150`)).rows[0].n;
  assert.equal(count, 1);
  await db.query('update booking_itinerary_items set actual_departure_time = now() where id = $1', [id(3)]);
  assert.equal(Number((await db.query('select remaining_balance from package_bookings where id = $1', [id(2)])).rows[0].remaining_balance), 650);
  assert.equal(Number((await db.query('select additional_amount from booking_stop_waiting_charges where itinerary_item_id = $1', [id(3)])).rows[0].additional_amount), 150);
  await db.query('update booking_itinerary_items set actual_departure_time = now() where id = $1', [id(3)]);
  assert.equal(Number((await db.query('select remaining_balance from package_bookings where id = $1', [id(2)])).rows[0].remaining_balance), 650);
  console.log('PASS: waiting ledger, finalized balance and repeated departure use one snapshotted fee');
} finally {
  await db.close();
}
