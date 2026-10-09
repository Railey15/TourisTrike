import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const tourist = '00000000-0000-0000-0000-000000000001';
try {
  await db.exec(`
    create schema auth;
    create role anon; create role authenticated;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('test.uid', true), '')::uuid $$;
    create table tourist_booking_restrictions
      (tourist_id uuid, status text, restricted_until timestamptz);
    create table package_bookings (
      id uuid primary key default gen_random_uuid(),
      adults integer, children integer, total_passengers integer,
      required_drivers integer, additional_tricycle_count integer default 0,
      additional_tricycle_approved_count integer default 0,
      scheduled_start_at timestamptz, estimated_end_at timestamptz,
      travel_date date, total_amount numeric);
    create function tricycle_passenger_capacity() returns integer
      language sql immutable as $$ select 3 $$;
    create function minimum_required_tricycles(integer) returns integer
      language sql immutable as $$ select ceil($1::numeric / 3)::integer $$;
    create function create_package_booking_restriction_impl(
      p_booking jsonb, p_customized_spots jsonb, p_itinerary_items jsonb)
    returns public.package_bookings language plpgsql as $$
    declare b public.package_bookings;
    begin
      insert into public.package_bookings(adults,children,total_passengers,
        required_drivers,scheduled_start_at,estimated_end_at,travel_date,
        total_amount)
      values ((p_booking->>'adults')::integer,
        (p_booking->>'children')::integer,
        (p_booking->>'total_passengers')::integer,
        (p_booking->>'required_drivers')::integer,
        '2026-10-10 00:00:00+00','2026-10-10 04:00:00+00',
        '2026-10-10', (p_booking->>'total_amount')::numeric)
      returning * into b;
      return b;
    end $$;
  `);
  await db.exec(readFileSync(new URL(
    '../migrations/20261009100000_selected_tricycles_at_booking.sql',
    import.meta.url), 'utf8'));
  await db.exec(`create trigger capacity_guard before insert or update
    on package_bookings for each row
    execute function validate_booking_schedule_and_capacity()`);
  await db.query(`select set_config('test.uid',$1,false)`, [tourist]);

  async function book(adults, children, selected, overrides = {}) {
    const payload = { adults, children, total_passengers: adults + children,
      required_drivers: selected, selected_total_tricycles: selected,
      total_amount: 2000, ...overrides };
    return db.query(`select * from create_package_booking($1::jsonb)`,
      [JSON.stringify(payload)]);
  }
  for (const [adults, minimum] of [[1,1],[2,1],[3,1],[4,2],[6,2],[9,3]]) {
    const min = await book(adults, 0, minimum);
    assert.equal(min.rows[0].required_drivers, minimum);
    const max = await book(adults, 0, adults);
    assert.equal(max.rows[0].required_drivers, adults);
    assert.equal(Number(max.rows[0].total_amount), 2000);
    if (minimum > 1) await assert.rejects(
      () => book(adults, 0, minimum - 1), /INVALID_SELECTED_TRICYCLE_COUNT/);
    await assert.rejects(
      () => book(adults, 0, adults + 1), /INVALID_SELECTED_TRICYCLE_COUNT/);
  }
  await assert.rejects(() => book(1, 3, 1),
    /INVALID_SELECTED_TRICYCLE_COUNT/);
  const withChild = await book(2, 2, 2);
  assert.equal(withChild.rows[0].required_drivers, 2);
  await assert.rejects(() => book(6, 0, 3,
    { required_drivers: 2 }), /INVALID_SELECTED_TRICYCLE_COUNT/);
  await assert.rejects(() => book(3, 0, 1,
    { additional_tricycle_count: 1 }), /INVALID_SELECTED_TRICYCLE_COUNT/);
  await assert.rejects(() => book(3, 0, 1,
    { selected_total_tricycles: undefined, additional_tricycle_count: 1 }),
    /ADDITIONAL_TRICYCLE_REQUEST_RETIRED/);
  assert.equal((await db.query(`select count(*)::integer as n
    from package_bookings`)).rows[0].n, 13);
  console.log('PASS: selected tricycles persist as real required driver slots; invalid ranges rejected');
} finally {
  await db.close();
}
