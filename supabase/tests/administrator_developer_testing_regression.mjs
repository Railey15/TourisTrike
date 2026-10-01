// In-memory PostgreSQL; never connects to or changes the linked project.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const migration = readFileSync(
  new URL('../migrations/20261001050000_system_administrator_developer_testing.sql', import.meta.url),
  'utf8',
).replaceAll('\r\n', '\n');
const completedFilterMigration = readFileSync(
  new URL('../migrations/20261001070000_exclude_completed_developer_test_bookings.sql', import.meta.url),
  'utf8',
).replaceAll('\r\n', '\n');
const ongoingFilterMigration = readFileSync(
  new URL('../migrations/20261001080000_limit_developer_tools_to_ongoing_bookings.sql', import.meta.url),
  'utf8',
).replaceAll('\r\n', '\n');
const id = value => `00000000-0000-0000-0000-${String(value).padStart(12, '0')}`;
const admin = id(1), tourist = id(2), driver = id(3), stranger = id(4);
const mainTenant = id(5), subtenant = id(6), unrelatedTourist = id(7);
const booking = id(10), activity = id(11), assignment = id(12);
const normalBooking = id(20), normalAssignment = id(21);
const completedBooking = id(30), completedActivity = id(31), completedAssignment = id(32);
const cancelledBooking = id(40), cancelledActivity = id(41), cancelledAssignment = id(42);
let checks = 0;
const check = (actual, expected, message) => {
  assert.deepEqual(actual, expected, message);
  checks++;
};
const scalar = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const fail = async (sql, params, code) => {
  await assert.rejects(() => db.query(sql, params), new RegExp(code));
  checks++;
};
const login = user => db.query("select set_config('test.uid',$1,false)", [user]);

try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('test.uid', true), '')::uuid $$;

    create table public.profiles (
      id uuid primary key, role text not null, full_name text,
      first_name text, last_name text
    );
    create table public.tour_packages (
      id bigint primary key, title text not null, city text not null
    );
    create table public.package_bookings (
      id uuid primary key, package_id bigint not null references public.tour_packages(id),
      tourist_id uuid not null references public.profiles(id), municipality text,
      status text not null default 'confirmed', booking_status text,
      scheduled_start_at timestamptz, estimated_end_at timestamptz,
      required_drivers integer not null default 1, current_spot_index integer not null default 0,
      downpayment_ready boolean not null default false,
      remaining_payment_ready boolean not null default false,
      created_at timestamptz not null default now(), updated_at timestamptz not null default now()
    );
    create table public.package_activities (
      id uuid primary key, booking_id uuid not null references public.package_bookings(id),
      status text not null default 'accepted', tour_status text not null default 'driver_accepted',
      current_spot_index integer not null default 0, dropped_off_at timestamptz,
      created_at timestamptz not null default now(), updated_at timestamptz not null default now()
    );
    create table public.booking_drivers (
      id uuid primary key, booking_id uuid not null references public.package_bookings(id),
      driver_id uuid not null references public.profiles(id), status text not null default 'accepted',
      journey_state text not null default 'assigned', current_stop_index integer not null default 0,
      state_updated_at timestamptz not null default now(), completed_at timestamptz
    );
    create table public.booking_itinerary_items (
      id uuid primary key default gen_random_uuid(), booking_id uuid not null,
      spot_status text not null default 'pending'
    );
    create table public.trip_status_logs (
      id bigint generated always as identity primary key, activity_id uuid, booking_id uuid,
      driver_id uuid, status text, previous_state text, new_state text,
      spot_index integer, logged_at timestamptz, notes text
    );
    create table public.audit_logs (
      id bigint generated always as identity primary key, actor_id uuid, action text,
      table_name text, record_id text, description text, created_at timestamptz default now()
    );
    create table public.system_settings (
      singleton boolean primary key default true check (singleton)
    );
    insert into public.system_settings(singleton) values(true);

    create function public.is_system_administrator() returns boolean language sql stable as
      $$ select exists(select 1 from public.profiles where id=auth.uid() and role='administrator') $$;
    create function public.is_developer_test_booking(uuid) returns boolean language sql stable as
      $$ select false $$;
    create function public.is_booking_downpayment_confirmed(p_id uuid) returns boolean language sql stable as
      $$ select downpayment_ready from public.package_bookings where id=p_id $$;
    create function public.is_booking_remaining_payment_satisfied(p_id uuid) returns boolean language sql stable as
      $$ select remaining_payment_ready from public.package_bookings where id=p_id $$;
    create function public.package_booking_schedule_window(b public.package_bookings)
      returns tstzrange language sql stable as
      $$ select tstzrange(b.scheduled_start_at,b.estimated_end_at,'[)') $$;
    create function public.journey_state_order(value text) returns integer language sql immutable as
      $$ select case value when 'assigned' then 0 when 'en_route_pickup' then 1
        when 'at_pickup' then 2 when 'boarded' then 3 when 'en_route_stop' then 4
        when 'at_stop' then 5 when 'stop_done' then 6 when 'en_route_dropoff' then 7
        when 'at_dropoff' then 8 when 'completed' then 9 end $$;
    create function public.finalize_package_booking_if_eligible(uuid) returns jsonb language sql as
      $$ select jsonb_build_object('overall_completed',false,'awaiting_final_payment',false) $$;
    create function public.compute_convoy_stage_progress(uuid,text,integer) returns jsonb language sql as
      $$ select jsonb_build_object('all_satisfied',true) $$;
    create function public.test_require_gps_for_arrival() returns trigger language plpgsql as $$
    begin
      if old.journey_state='en_route_pickup' and new.journey_state='at_pickup'
         and coalesce(current_setting('test.gps_verified',true),'') <> 'true' then
        raise exception 'GPS_VERIFICATION_REQUIRED';
      end if;
      return new;
    end $$;
    create trigger test_gps_guard before update of journey_state on public.booking_drivers
      for each row execute function public.test_require_gps_for_arrival();
  `);

  await db.query(
    `insert into profiles(id,role,full_name) values
      ($1,'administrator','System Admin'),($2,'tourist','Test Tourist'),
      ($3,'driver','Test Driver'),($4,'driver','Other Driver'),
      ($5,'main_tenant','Main Tenant'),($6,'subtenant','Subtenant'),
      ($7,'tourist','Other Tourist')`,
    [admin, tourist, driver, stranger, mainTenant, subtenant, unrelatedTourist],
  );
  await db.exec("insert into tour_packages values(1,'Regression tour','Malolos'),(2,'Completed hidden tour','Malolos')");
  await db.query(
    `insert into package_bookings(id,package_id,tourist_id,municipality,status,booking_status,
      scheduled_start_at,estimated_end_at,required_drivers)
      values($1,1,$2,'Malolos','confirmed','confirmed',now()+interval '4 hours',now()+interval '8 hours',1)`,
    [booking, tourist],
  );
  await db.query('insert into package_activities(id,booking_id) values($1,$2)', [activity, booking]);
  await db.query('insert into booking_drivers(id,booking_id,driver_id) values($1,$2,$3)', [assignment, booking, driver]);
  await db.query(
    `insert into package_bookings(id,package_id,tourist_id,municipality,status,booking_status,
      scheduled_start_at,estimated_end_at,required_drivers,downpayment_ready)
      values($1,1,$2,'Malolos','confirmed','confirmed',now()+interval '4 hours',now()+interval '8 hours',1,true)`,
    [normalBooking, tourist],
  );
  await db.query('insert into booking_drivers(id,booking_id,driver_id) values($1,$2,$3)', [normalAssignment, normalBooking, driver]);
  await db.query(
    `insert into package_bookings(id,package_id,tourist_id,municipality,status,booking_status,
      scheduled_start_at,estimated_end_at,required_drivers,downpayment_ready)
      values($1,2,$2,'Malolos','completed','completed',now()+interval '3 hours',now()+interval '7 hours',1,true)`,
    [completedBooking, tourist],
  );
  await db.query(
    "insert into package_activities(id,booking_id,status,tour_status) values($1,$2,'completed','completed')",
    [completedActivity, completedBooking],
  );
  await db.query(
    "insert into booking_drivers(id,booking_id,driver_id,status,journey_state,completed_at) values($1,$2,$3,'completed','completed',now())",
    [completedAssignment, completedBooking, driver],
  );
  await db.query(
    `insert into package_bookings(id,package_id,tourist_id,municipality,status,booking_status,
      scheduled_start_at,estimated_end_at,required_drivers,downpayment_ready)
      values($1,1,$2,'Malolos','cancelled','cancelled',now()+interval '5 hours',now()+interval '9 hours',1,true)`,
    [cancelledBooking, tourist],
  );
  await db.query(
    "insert into package_activities(id,booking_id,status,tour_status) values($1,$2,'cancelled','cancelled')",
    [cancelledActivity, cancelledBooking],
  );
  await db.query(
    "insert into booking_drivers(id,booking_id,driver_id) values($1,$2,$3)",
    [cancelledAssignment, cancelledBooking, driver],
  );

  await db.exec(migration);
  await db.exec(completedFilterMigration);
  await db.exec(ongoingFilterMigration);

  check(
    await scalar("select has_table_privilege('authenticated','developer_test_sessions','select,insert,update,delete')"),
    false,
    'authenticated clients have no direct session-table access',
  );
  check(
    await scalar("select has_function_privilege('authenticated','administrator_activate_developer_test_session(uuid,text,timestamptz)','execute')"),
    true,
    'authenticated role can reach the server-side administrator guard',
  );

  await login(tourist);
  await fail('select administrator_set_developer_testing(true)', [], 'SYSTEM_ADMINISTRATOR_REQUIRED');
  await login(driver);
  await fail('select administrator_set_developer_testing(true)', [], 'SYSTEM_ADMINISTRATOR_REQUIRED');
  await login(mainTenant);
  await fail('select administrator_set_developer_testing(true)', [], 'SYSTEM_ADMINISTRATOR_REQUIRED');
  await login(subtenant);
  await fail('select administrator_set_developer_testing(true)', [], 'SYSTEM_ADMINISTRATOR_REQUIRED');
  await login(stranger);
  await fail(
    "select administrator_activate_developer_test_session($1,'Unauthorized test',now()+interval '1 hour')",
    [booking],
    'SYSTEM_ADMINISTRATOR_REQUIRED',
  );

  await login(admin);
  await scalar('select administrator_set_developer_testing(true)');
  const session = await scalar(
    "select administrator_activate_developer_test_session($1,'Verify early departure gate',now()+interval '2 hours')",
    [booking],
  );
  check(session.status, 'active', 'administrator creates an active authorization');
  check(session.bypass_scheduled_start, true, 'session contains only the schedule override');
  const overview = await scalar('select administrator_get_developer_testing_overview()');
  check(overview.enabled, true, 'overview returns authoritative global state');
  check(overview.active_sessions, 1, 'overview counts active sessions');
  check(overview.eligible_bookings, 2, 'completed booking is excluded from eligible count');
  check(overview.upcoming_bookings, 2, 'completed booking is excluded from upcoming count');
  const listed = (await db.query(
    "select * from administrator_list_testable_bookings('', 'all', 'all', 25, 0)",
  )).rows;
  check(listed.length, 2, 'administrator booking RPC returns only ongoing bookings');
  check(listed.some(row => row.booking_id === completedBooking), false, 'completed booking is excluded from all bookings');
  check(listed.some(row => row.booking_id === cancelledBooking), false, 'cancelled booking is excluded from all bookings');
  check(Number(listed[0].total_count), 2, 'total_count includes only ongoing bookings');
  check(listed.find(row => row.booking_id === booking).eligible, true, 'booking RPC derives testing eligibility');
  const completedSearch = (await db.query(
    "select * from administrator_list_testable_bookings('Completed hidden tour', 'all', 'all', 25, 0)",
  )).rows;
  check(completedSearch.length, 0, 'search cannot return a completed booking');
  const completedFilter = (await db.query(
    "select * from administrator_list_testable_bookings('', 'completed', 'all', 25, 0)",
  )).rows;
  check(completedFilter.length, 0, 'completed filter cannot reintroduce completed bookings');
  const cancelledFilter = (await db.query(
    "select * from administrator_list_testable_bookings('', 'cancelled', 'all', 25, 0)",
  )).rows;
  check(cancelledFilter.length, 0, 'cancelled filter cannot reintroduce cancelled bookings');
  const inactiveRows = (await db.query(
    "select * from administrator_list_testable_bookings('', 'all', 'inactive', 25, 0)",
  )).rows;
  check(inactiveRows.some(row => row.booking_id === completedBooking), false, 'inactive test-state filter excludes completed bookings');
  check(inactiveRows.some(row => row.booking_id === cancelledBooking), false, 'inactive test-state filter excludes cancelled bookings');
  const firstPage = (await db.query(
    "select * from administrator_list_testable_bookings('', 'all', 'all', 1, 0)",
  )).rows;
  const secondPage = (await db.query(
    "select * from administrator_list_testable_bookings('', 'all', 'all', 1, 1)",
  )).rows;
  const beyondLastPage = (await db.query(
    "select * from administrator_list_testable_bookings('', 'all', 'all', 1, 2)",
  )).rows;
  check(firstPage.length, 1, 'first page contains one non-completed booking');
  check(secondPage.length, 1, 'second page contains one non-completed booking');
  check(firstPage[0].booking_id === secondPage[0].booking_id, false, 'pagination returns distinct non-completed bookings');
  check(Number(firstPage[0].total_count), 2, 'first page total_count uses ongoing population');
  check(Number(secondPage[0].total_count), 2, 'second page total_count uses ongoing population');
  check(beyondLastPage.length, 0, 'pagination ends after the non-completed population');
  await fail(
    "select administrator_activate_developer_test_session($1,'Duplicate authorization',now()+interval '3 hours')",
    [booking],
    'DEVELOPER_TEST_SESSION_ALREADY_ACTIVE',
  );
  check(await scalar('select booking_status from package_bookings where id=$1', [booking]), 'confirmed', 'activation does not mutate lifecycle');
  check(await scalar('select downpayment_ready from package_bookings where id=$1', [booking]), false, 'activation does not mutate payment');
  check(await scalar("select count(*)::int from audit_logs where action='DEVELOPER_TEST_SESSION_ACTIVATED'"), 1, 'activation is audited');

  await login(unrelatedTourist);
  check((await scalar('select get_my_booking_test_authorization($1)', [booking])).authorized, false, 'unrelated Tourist cannot read authorization');
  await login(tourist);
  check((await scalar('select get_my_booking_test_authorization($1)', [booking])).authorized, true, 'Tourist participant sees effective authorization');
  await login(driver);
  check((await scalar('select get_my_booking_test_authorization($1)', [booking])).authorized, true, 'accepted Driver sees effective authorization');
  await login(stranger);
  check((await scalar('select get_my_booking_test_authorization($1)', [booking])).authorized, false, 'unassigned Driver cannot read authorization');
  await fail("select advance_driver_journey_state($1,'en_route_pickup')", [booking], 'NOT_IN_CONVOY');

  await login(admin);
  await db.query("update developer_test_sessions set activated_at=now()-interval '2 hours',expires_at=now()-interval '1 hour' where id=$1", [session.id]);
  await login(tourist);
  check((await scalar('select get_my_booking_test_authorization($1)', [booking])).authorized, false, 'expired session is ineffective');
  await login(admin);
  const renewedSession = await scalar(
    "select administrator_activate_developer_test_session($1,'Renew after expiry',now()+interval '2 hours')",
    [booking],
  );

  await login(driver);
  await fail("select advance_driver_journey_state($1,'at_pickup')", [booking], 'INVALID_TRANSITION');
  await fail("select advance_driver_journey_state($1,'en_route_pickup')", [normalBooking], 'BOOKING_START_TOO_EARLY');
  await fail("select advance_driver_journey_state($1,'en_route_pickup')", [booking], 'DOWNPAYMENT_NOT_CONFIRMED');
  check(await scalar('select journey_state from booking_drivers where id=$1', [assignment]), 'assigned', 'new authorization never bypasses downpayment');
  await db.query('update package_bookings set downpayment_ready=true where id=$1', [booking]);
  await scalar("select advance_driver_journey_state($1,'en_route_pickup')", [booking]);
  check(await scalar('select journey_state from booking_drivers where id=$1', [assignment]), 'en_route_pickup', 'authorized Driver bypasses only the future schedule');
  await fail("select advance_driver_journey_state($1,'at_pickup')", [booking], 'GPS_VERIFICATION_REQUIRED');
  check(await scalar('select journey_state from booking_drivers where id=$1', [assignment]), 'en_route_pickup', 'test authorization does not bypass GPS arrival enforcement');

  await login(admin);
  await scalar('select administrator_set_developer_testing(false)');
  await login(tourist);
  check((await scalar('select get_my_booking_test_authorization($1)', [booking])).authorized, false, 'global OFF makes an active session ineffective');
  await login(admin);
  await db.query("update booking_drivers set journey_state='assigned' where id=$1", [assignment]);
  await login(driver);
  await fail("select advance_driver_journey_state($1,'en_route_pickup')", [booking], 'BOOKING_START_TOO_EARLY');
  check(await scalar("select count(*)::int from developer_test_sessions where status='active'"), 1, 'global disable preserves the session');

  await login(admin);
  await scalar('select administrator_set_developer_testing(true)');
  await scalar('select administrator_deactivate_developer_test_session($1,null)', [renewedSession.id]);
  check(await scalar('select status from developer_test_sessions where id=$1', [renewedSession.id]), 'deactivated', 'administrator deactivation is persisted');
  check(await scalar("select count(*)::int from audit_logs where action='DEVELOPER_TEST_SESSION_DEACTIVATED'"), 1, 'deactivation is audited');
  await login(tourist);
  check((await scalar('select get_my_booking_test_authorization($1)', [booking])).authorized, false, 'deactivated session is ineffective');

  console.log(`PASS: ${checks} administrator developer-testing regression checks`);
} finally {
  await db.close();
}
