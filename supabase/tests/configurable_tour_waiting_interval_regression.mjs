import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const migration = readFileSync(
  new URL('../migrations/20261001000000_configurable_tour_waiting_interval.sql', import.meta.url),
  'utf8',
);
const uuid = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const office = uuid(1), tourist = uuid(2), office2 = uuid(3);
let checks = 0;
const check = (actual, expected, label) => {
  assert.deepEqual(actual, expected, label);
  checks++;
};
const scalar = async (sql, params = []) =>
  Object.values((await db.query(sql, params)).rows[0])[0];

try {
  await db.exec(`
    create schema auth;
    create role anon; create role authenticated;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('test.uid',true),'')::uuid $$;
    create table profiles(id uuid primary key,role text);
    create table subtenant_details(id uuid primary key,city text,province text,is_active boolean);
    create table audit_logs(id uuid default gen_random_uuid(),actor_id uuid,action text,
      table_name text,record_id text,description text);
    create function cities_match(a text,b text) returns boolean language sql immutable
      as $$ select lower(trim(a))=lower(trim(b)) $$;
    create function current_profile_role() returns text language sql stable as $$
      select role from public.profiles where id=auth.uid() $$;
    create table subtenant_fare_settings(
      id uuid primary key default gen_random_uuid(),subtenant_id uuid,city text,
      base_fare numeric default 0,fare_per_km numeric default 0,
      minimum_fare numeric default 0,waiting_fee numeric not null default 0,
      is_active boolean default true,tour_waiting_fee_per_15_minutes numeric(14,2),
      updated_at timestamptz default now(),unique(subtenant_id,city));
    create function guard_municipal_tour_waiting_rate() returns trigger language plpgsql
      as $$ begin return new; end $$;
    create trigger guard_municipal_tour_waiting_rate before insert or update
      on subtenant_fare_settings for each row execute function guard_municipal_tour_waiting_rate();
    create table package_bookings(
      id uuid primary key,tourist_id uuid,municipality text,province text,
      status text,booking_status text,total_amount numeric,remaining_balance numeric,
      updated_at timestamptz,tour_waiting_subtenant_id uuid,
      tour_waiting_rate_snapshot numeric(14,2));
    create function snapshot_booking_tour_waiting_rate() returns trigger language plpgsql
      as $$ begin return new; end $$;
    create trigger snapshot_booking_tour_waiting_rate before insert on package_bookings
      for each row execute function snapshot_booking_tour_waiting_rate();
    create function guard_booking_tour_waiting_snapshot() returns trigger language plpgsql
      as $$ begin return new; end $$;
    create trigger guard_booking_tour_waiting_snapshot before update of
      tour_waiting_subtenant_id,tour_waiting_rate_snapshot on package_bookings
      for each row execute function guard_booking_tour_waiting_snapshot();
    create table booking_itinerary_items(
      id uuid primary key,booking_id uuid,destination_name text,
      estimated_stay_duration_minutes integer,actual_arrival_time timestamptz,
      actual_departure_time timestamptz);
    create table booking_stop_waiting_charges(
      id uuid primary key default gen_random_uuid(),booking_id uuid,
      itinerary_item_id uuid,municipality text,subtenant_id uuid,
      included_minutes integer,arrived_at timestamptz,paid_until timestamptz,
      departed_at timestamptz,interval_minutes integer not null default 15
        check(interval_minutes=15),overtime_seconds integer default 0,
      chargeable_intervals integer default 0,rate_per_interval numeric(14,2),
      additional_amount numeric(14,2) default 0,status text default 'active',
      finalized_at timestamptz,created_at timestamptz default now(),
      updated_at timestamptz default now(),unique(booking_id,itinerary_item_id),
      check(additional_amount=chargeable_intervals*coalesce(rate_per_interval,0)));
    create function snapshot_booking_stop_waiting_charge() returns trigger language plpgsql
      as $$ begin return new; end $$;
    create trigger snapshot_booking_stop_waiting_charge after update of actual_arrival_time
      on booking_itinerary_items for each row execute function snapshot_booking_stop_waiting_charge();
    create function finalize_booking_stop_waiting_charge() returns trigger language plpgsql
      as $$ begin return new; end $$;
    create trigger finalize_booking_stop_waiting_charge after update of actual_departure_time
      on booking_itinerary_items for each row execute function finalize_booking_stop_waiting_charge();
    create table booking_payment_requirements(
      booking_id uuid,payment_stage text,amount numeric,status text default 'required',
      satisfied_at timestamptz,satisfied_by_payment_record_id uuid,
      updated_at timestamptz,unique(booking_id,payment_stage));
    create table package_activities(id uuid default gen_random_uuid(),booking_id uuid);
    create table trip_status_logs(id uuid default gen_random_uuid(),activity_id uuid,
      booking_id uuid,status text,notes text,logged_at timestamptz);
    create table booking_drivers(id uuid,booking_id uuid,driver_id uuid,status text);
    create function emit_tour_notification(uuid,uuid,text,text,text,text,boolean)
      returns void language sql as $$ select $$;
    create function can_read_tour_booking(uuid) returns boolean language sql stable
      as $$ select true $$;
  `);
  await db.query(`insert into profiles values($1,'subtenant'),($2,'tourist')`, [office, tourist]);
  await db.query(`insert into subtenant_details values($1,'Baliwag','Bulacan',true)`, [office]);
  await db.query(`insert into subtenant_fare_settings(subtenant_id,city,waiting_fee,
    tour_waiting_fee_per_15_minutes) values($1,'Baliwag',200,25)`, [office]);

  await db.exec(migration);

  check(Number(await scalar(`select additional_waiting_interval_minutes
    from subtenant_fare_settings where subtenant_id=$1`, [office])), 15,
    'existing municipality defaults to 15 minutes');
  check(Number(await scalar(`select tour_waiting_fee_per_15_minutes
    from subtenant_fare_settings where subtenant_id=$1`, [office])), 50,
    'legacy fee is recalculated from hourly rate');

  await db.query(`select set_config('test.uid',$1,false)`, [office]);
  await db.query(`update subtenant_fare_settings
    set additional_waiting_interval_minutes=20 where subtenant_id=$1`, [office]);
  check(Number(await scalar(`select tour_waiting_fee_per_15_minutes
    from subtenant_fare_settings where subtenant_id=$1`, [office])), 66.67,
    '20-minute compatibility fee is derived, not independently editable');
  await db.query(`update subtenant_fare_settings set tour_waiting_fee_per_15_minutes=999
    where subtenant_id=$1`, [office]);
  check(Number(await scalar(`select tour_waiting_fee_per_15_minutes
    from subtenant_fare_settings where subtenant_id=$1`, [office])), 66.67,
    'direct legacy fee edits are overwritten by the authoritative values');

  await db.query(`insert into profiles values($1,'subtenant')`, [office2]);
  await db.query(`insert into subtenant_details values($1,'Bustos','Bulacan',true)`, [office2]);
  await db.query(`select set_config('test.uid',$1,false)`, [office2]);
  await db.query(`insert into subtenant_fare_settings(subtenant_id,city,waiting_fee,
    additional_waiting_interval_minutes) values($1,'Bustos',240,30)`, [office2]);
  check(Number(await scalar(`select additional_waiting_interval_minutes
    from subtenant_fare_settings where subtenant_id=$1`, [office])), 20,
    'Baliwag retains its own interval');
  check(Number(await scalar(`select additional_waiting_interval_minutes
    from subtenant_fare_settings where subtenant_id=$1`, [office2])), 30,
    'Bustos persists a different municipality interval');
  check(Number(await scalar(`select (get_municipal_tour_waiting_policy(
    'Bustos','Bulacan')->>'rate_per_interval')::numeric`)), 120,
    'municipality policy resolves its own hourly rate and interval');
  await db.query(`select set_config('test.uid','',false)`);

  const cases = [
    [1, 1, 66.67], [20, 1, 66.67], [21, 2, 133.33],
    [40, 2, 133.33], [41, 3, 200], [60, 3, 200],
  ];
  for (let i = 0; i < cases.length; i++) {
    const [minutes, intervals, amount] = cases[i];
    const booking = uuid(100 + i), stop = uuid(200 + i);
    await db.query(`insert into package_bookings(id,tourist_id,municipality,province,
      status,booking_status,total_amount,remaining_balance,updated_at)
      values($1,$2,'Baliwag','Bulacan','ongoing','on_tour',1000,500,now())`,
      [booking, tourist]);
    check(Number(await scalar(`select tour_waiting_interval_minutes_snapshot
      from package_bookings where id=$1`, [booking])), 20,
      `${minutes} minute case snapshots its municipality interval`);
    await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,
      estimated_stay_duration_minutes) values($1,$2,'Stop',60)`, [stop, booking]);
    await db.query(`update booking_itinerary_items
      set actual_arrival_time='2026-10-01 08:00+00' where id=$1`, [stop]);
    await db.query(`update booking_itinerary_items set actual_departure_time=
      '2026-10-01 09:00+00'::timestamptz+make_interval(mins=>$2) where id=$1`,
      [stop, minutes]);
    check(Number(await scalar(`select chargeable_intervals
      from booking_stop_waiting_charges where itinerary_item_id=$1`, [stop])),
      intervals, `${minutes} minute started-interval boundary`);
    check(Number(await scalar(`select additional_amount
      from booking_stop_waiting_charges where itinerary_item_id=$1`, [stop])),
      amount, `${minutes} minute aggregate amount`);
  }

  console.log(`PASS: ${checks} configurable waiting-interval SQL checks`);
} finally {
  await db.close();
}
