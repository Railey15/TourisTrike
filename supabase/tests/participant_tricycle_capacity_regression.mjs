// In-memory PostgreSQL regression; never connects to or mutates a linked project.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const tourist = '00000000-0000-0000-0000-000000000001';
const office = '00000000-0000-0000-0000-000000000002';

try {
  await db.exec(`
    create schema auth;
    create role anon;
    create role authenticated;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('test.uid', true), '')::uuid $$;
    create table public.tourist_booking_restrictions(
      tourist_id uuid, status text, restricted_until timestamptz);
    create table public.subtenant_details(id uuid primary key, province text);
    create table public.tour_packages(
      id bigint primary key, city text, submitted_by uuid
        references public.subtenant_details(id));
    create table public.package_bookings(
      id uuid primary key default gen_random_uuid(),
      adults integer, children integer, total_passengers integer,
      required_drivers integer, additional_tricycle_count integer default 0,
      additional_tricycle_approved_count integer default 0,
      scheduled_start_at timestamptz, estimated_end_at timestamptz,
      travel_date date, total_amount numeric);
    create function public.tricycle_passenger_capacity() returns integer
      language sql immutable as $$ select 3 $$;
    create function public.minimum_required_tricycles(integer) returns integer
      language sql immutable as $$
        select greatest(ceil(greatest(coalesce($1,1),1)::numeric / 3)::integer,1)
      $$;
    create function public.municipal_restriction_active(uuid,text,text)
      returns boolean language sql stable as $$ select false $$;
    create function public.create_package_booking_restriction_impl(
      p_booking jsonb, p_customized_spots jsonb, p_itinerary_items jsonb)
    returns public.package_bookings language plpgsql as $$
    declare result public.package_bookings;
    begin
      insert into public.package_bookings(
        adults,children,total_passengers,required_drivers,
        scheduled_start_at,estimated_end_at,travel_date,total_amount)
      values(
        (p_booking->>'adults')::integer,
        (p_booking->>'children')::integer,
        (p_booking->>'total_passengers')::integer,
        (p_booking->>'required_drivers')::integer,
        '2026-10-10 00:00:00+00','2026-10-10 04:00:00+00',
        '2026-10-10',(p_booking->>'total_amount')::numeric)
      returning * into result;
      return result;
    end $$;
    insert into public.subtenant_details values('${office}','Bulacan');
    insert into public.tour_packages values(1,'Bustos','${office}');
  `);

  const migration = readFileSync(new URL(
    '../migrations/20261009190000_participant_tricycle_capacity_fix.sql',
    import.meta.url), 'utf8');
  await db.exec(migration);
  await db.exec(`create trigger capacity_guard before insert or update
    on public.package_bookings for each row
    execute function public.validate_booking_schedule_and_capacity()`);
  await db.query("select set_config('test.uid',$1,false)", [tourist]);

  const book = (adults, children, selected, overrides = {}) => {
    const payload = {
      package_id: 1,
      adults,
      children,
      total_passengers: adults + children,
      required_drivers: selected,
      selected_total_tricycles: selected,
      total_amount: 2000,
      ...overrides,
    };
    return db.query('select * from public.create_package_booking($1::jsonb)', [
      JSON.stringify(payload),
    ]);
  };

  await assert.rejects(() => book(0, 2, 1), /CHILDREN_REQUIRE_ADULT/);

  assert.equal((await book(1, 2, 1)).rows[0].required_drivers, 1);
  assert.equal((await book(2, 0, 1)).rows[0].required_drivers, 1);
  assert.equal((await book(3, 3, 2)).rows[0].required_drivers, 2);
  assert.equal((await book(3, 3, 3)).rows[0].required_drivers, 3);
  await assert.rejects(() => book(3, 3, 1),
    /INVALID_SELECTED_TRICYCLE_COUNT/);

  assert.equal((await book(1, 2, 2)).rows[0].required_drivers, 2);
  assert.equal((await book(1, 2, 3)).rows[0].required_drivers, 3);
  await assert.rejects(() => book(1, 2, 4),
    /INVALID_SELECTED_TRICYCLE_COUNT/);
  await assert.rejects(() => book(1, 2, 1, {total_passengers: 2}),
    /INVALID_SELECTED_TRICYCLE_COUNT/);

  assert.equal((await db.query(
    'select count(*)::integer as count from public.package_bookings'
  )).rows[0].count, 6);
  console.log('PASS: all participants drive capacity; children require one adult; selection respects minimum');
} finally {
  await db.close();
}
