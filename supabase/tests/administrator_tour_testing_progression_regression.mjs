// Runs only in PGlite. The linked database is never changed.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const timingMigration = readFileSync(new URL(
  '../migrations/20261008010000_booking_tour_developer_overrides.sql',
  import.meta.url), 'utf8');
const gpsMigration = readFileSync(new URL(
  '../migrations/20260906040000_centralize_driver_arrival_radius.sql',
  import.meta.url), 'utf8');
const timingRpc = name => {
  const start = timingMigration.indexOf(`create or replace function public.${name}(`);
  assert.ok(start >= 0, `missing ${name}`);
  return timingMigration.slice(start, timingMigration.indexOf('$$;',start)+3);
};
const oldGpsStart = gpsMigration.indexOf(
  'create or replace function public.guard_live_driver_journey_proximity()');
const oldGpsGuard = gpsMigration.slice(oldGpsStart,
  gpsMigration.indexOf('$$;',oldGpsStart)+3);
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const admin = id(1), tenant = id(2), booking = id(10), driver = id(11);
const activity = id(12), stop1 = id(13), stop2 = id(14);
let checks = 0;
const scalar = async sql => Object.values((await db.query(sql)).rows[0])[0];
const login = user => db.query("select set_config('test.uid',$1,false)", [user]);
const progress = async (action, state, index) => {
  const result = await db.query(
    'select public.administrator_progress_booking_test_v2($1,$2,$3,$4) as state',
    [booking, action, state, index],
  );
  return result.rows[0].state;
};
const expectState = async (state, index, spotStatus) => {
  const row = (await db.query(
    'select journey_state,current_stop_index from booking_drivers where booking_id=$1',
    [booking],
  )).rows[0];
  assert.equal(row.journey_state, state);
  assert.equal(row.current_stop_index, index);
  if (spotStatus) assert.equal(await scalar(
    `select spot_status from booking_itinerary_items where id='${index ? stop2 : stop1}'`,
  ), spotStatus);
  checks++;
};
const rejects = async (action, state, index, message) => {
  await assert.rejects(() => progress(action, state, index), new RegExp(message));
  checks++;
};

try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
    create table profiles(id uuid primary key,role text);
    create table package_bookings(id uuid primary key,status text,booking_status text,
      cancelled_at timestamptz,completed_at timestamptz,required_drivers integer,
      current_spot_index integer,updated_at timestamptz,
      downpayment_ready boolean,remaining_payment_ready boolean,
      pickup_latitude float8,pickup_longitude float8,
      dropoff_latitude float8,dropoff_longitude float8);
    create table booking_drivers(id uuid primary key,booking_id uuid,driver_id uuid,
      status text,journey_state text,current_stop_index integer,
      state_updated_at timestamptz,completed_at timestamptz);
    create table booking_itinerary_items(id uuid primary key,booking_id uuid,
      order_number integer,destination_order integer,arrival_time timestamptz,
      created_at timestamptz,destination_name text,spot_status text,
      actual_arrival_time timestamptz,actual_departure_time timestamptz,
      latitude float8,longitude float8);
    create table booking_driver_arrivals(booking_driver_id uuid,
      itinerary_item_id uuid,arrived_at timestamptz,departed_at timestamptz,
      latitude float8,longitude float8,
      primary key(booking_driver_id,itinerary_item_id));
    create table driver_live_locations(driver_id uuid,latitude float8,
      longitude float8,updated_at timestamptz);
    create table package_activities(id uuid primary key,booking_id uuid,
      status text,tour_status text,current_spot_index integer,
      dropped_off_at timestamptz,updated_at timestamptz,created_at timestamptz);
    create table booking_stop_waiting_charges(id uuid default gen_random_uuid(),
      itinerary_item_id uuid,booking_id uuid,status text,
      additional_amount numeric,created_at timestamptz default now(),
      paid_until timestamptz,interval_minutes integer,hourly_rate numeric,
      rate_per_interval numeric,test_deadline_override timestamptz,
      test_rate_per_interval_override numeric,test_hourly_rate_override numeric,
      test_override_kind text,test_override_updated_by uuid,
      test_override_updated_at timestamptz,overtime_seconds integer,
      chargeable_intervals integer,updated_at timestamptz);
    create table payment_records(booking_id uuid,provider text,
      provider_livemode boolean,status text,payment_stage text);
    create table payout_records(booking_id uuid,status text);
    create table payment_disputes(booking_id uuid);
    create table refund_requests(booking_id uuid,status text);
    create table system_settings(singleton boolean,developer_testing_enabled boolean);
    create table developer_test_sessions(booking_id uuid,status text,expires_at timestamptz);
    create table audit_logs(actor_id uuid,action text,table_name text,
      record_id text,description text,created_at timestamptz default now());
    create table trip_status_logs(activity_id uuid,booking_id uuid,
      status text,spot_index integer,logged_at timestamptz,notes text);
    create function public.is_system_administrator() returns boolean
      language sql stable set search_path = public as $$ select exists(select 1 from profiles
        where id=auth.uid() and role='administrator') $$;
    create function public.booking_test_admin_authorized(uuid) returns boolean
      language sql as $$ select true $$;
    create function public.driver_arrival_radius_meters() returns float8
      language sql immutable as $$ select 150::float8 $$;
    create function public.is_developer_test_booking(uuid) returns boolean
      language sql immutable as $$ select false $$;
    create function public.booking_test_session_active(uuid) returns boolean
      language sql as $$ select true $$;
    create function public.administrator_activate_developer_test_session(uuid,text,timestamptz)
      returns jsonb language sql as $$ select '{}'::jsonb $$;
    create function public.administrator_reset_developer_test_trip(uuid)
      returns jsonb language sql as $$ select '{}'::jsonb $$;
    create function public.administrator_delete_test_booking(uuid)
      returns jsonb language sql as $$ select '{}'::jsonb $$;
    create function public.is_booking_downpayment_confirmed(p_id uuid)
      returns boolean language sql set search_path = public as $$ select downpayment_ready
        from package_bookings where id=p_id $$;
    create function public.is_booking_remaining_payment_satisfied(p_id uuid)
      returns boolean language sql set search_path = public as $$ select remaining_payment_ready
        from package_bookings where id=p_id $$;
    create function public.is_booking_dropoff_payment_satisfied(p_id uuid)
      returns boolean language sql set search_path = public as $$ select remaining_payment_ready
        from package_bookings where id=p_id $$;
    create function public.tour_waiting_chargeable_intervals(seconds integer,
      minutes integer) returns integer language sql immutable as $$
        select greatest(0,seconds/(minutes*60)) $$;
    create function public.journey_state_order(value text) returns integer
      language sql immutable as $$ select case value
        when 'assigned' then 0 when 'en_route_stop' then 1
        when 'at_stop' then 2 when 'stop_done' then 3
        when 'en_route_dropoff' then 4 when 'at_dropoff' then 5
        when 'completed' then 6 end $$;
    create function public.finalize_package_booking_if_eligible(p_id uuid)
      returns jsonb language plpgsql set search_path = public as $$ begin
        update package_bookings set booking_status='completed',
          completed_at=now() where id=p_id;
        update package_activities set status='completed',tour_status='completed'
          where booking_id=p_id;
        return jsonb_build_object('overall_completed',true);
      end $$;
    create function public.administrator_get_booking_developer_state(p_id uuid)
      returns jsonb language sql set search_path = public as $$
        select jsonb_build_object('booking_id',b.id,
          'controls_enabled',true,'booking_status',b.booking_status,
          'journey_state',d.journey_state,
          'current_stop_index',d.current_stop_index,
          'current_stop_id',i.id,'current_stop_name',i.destination_name,
          'arrival_status',case when i.actual_arrival_time is null
            then 'pending' else 'arrived' end,
          'departure_status',case when i.actual_departure_time is null
            then 'pending' else 'departed' end)
        from package_bookings b join booking_drivers d on d.booking_id=b.id
        left join lateral (select * from booking_itinerary_items item
          where item.booking_id=b.id order by item.order_number
          offset d.current_stop_index limit 1) i on true
        where b.id=p_id $$;
    create function public.administrator_progress_booking_test(uuid,text)
      returns jsonb language sql as $$ select '{}'::jsonb $$;
  `);
  await db.query("insert into profiles values($1,'administrator'),($2,'main_tenant')", [admin,tenant]);
  await db.query(`insert into package_bookings(id,status,booking_status,
    required_drivers,current_spot_index,downpayment_ready,remaining_payment_ready,
    dropoff_latitude,dropoff_longitude)
    values($1,'accepted','accepted',1,0,false,false,14.8,120.8)`, [booking]);
  await db.query(`insert into booking_drivers(id,booking_id,driver_id,status,
    journey_state,current_stop_index) values($1,$2,$3,'accepted','assigned',0)`,
    [driver,booking,id(20)]);
  await db.query(`insert into package_activities(id,booking_id,status,tour_status,
    current_spot_index) values($1,$2,'accepted','driver_accepted',0)`,
    [activity,booking]);
  await db.query(`insert into booking_itinerary_items(id,booking_id,order_number,
    created_at,destination_name,spot_status,latitude,longitude) values
    ($1,$3,1,now(),'First','pending',14.8,120.8),
    ($2,$3,2,now(),'Second','pending',14.9,120.9)`,
    [stop1,stop2,booking]);
  await db.exec('insert into system_settings values(true,true)');
  await db.query("insert into developer_test_sessions values($1,'active',now()+interval '1 day')",[booking]);
  await db.exec(oldGpsGuard);
  await db.exec(`create trigger guard_live_driver_journey_proximity
    before update of journey_state on booking_drivers for each row
    execute function public.guard_live_driver_journey_proximity()`);
  await login(admin);
  await assert.rejects(() => db.query(`update booking_drivers
    set journey_state='at_stop' where booking_id=$1`,[booking]),
    /DRIVER_LOCATION_STALE/); checks++;
  await db.exec(readFileSync(new URL(
    '../migrations/20261009060000_administrator_tour_testing_progression.sql',
    import.meta.url), 'utf8'));
  await db.exec(timingRpc('administrator_apply_booking_timing_test'));
  await db.exec(timingRpc('administrator_reset_booking_timing_test'));

  for (const role of ['main_tenant','subtenant','driver','tourist']) {
    await db.query('update profiles set role=$1 where id=$2',[role,tenant]);
    await login(tenant);
    await rejects('force_start','assigned',0,'SYSTEM_ADMINISTRATOR_REQUIRED');
  }
  await login('');
  await rejects('force_start','assigned',0,'SYSTEM_ADMINISTRATOR_REQUIRED');
  await login(tenant);
  await assert.rejects(() => db.query(
    'select public.administrator_reset_developer_test_trip($1)',[booking]),
    /SYSTEM_ADMINISTRATOR_REQUIRED/); checks++;
  await assert.rejects(() => db.query(
    'select public.administrator_delete_test_booking($1)',[booking]),
    /SYSTEM_ADMINISTRATOR_REQUIRED/); checks++;
  await login(admin);
  await db.query(`insert into payment_records(booking_id,provider,
    provider_livemode,status,payment_stage)
    values($1,'paymongo',true,'confirmed','down_payment')`,[booking]);
  assert.equal(await scalar(`select public.booking_test_session_active('${booking}')`),false); checks++;
  await assert.rejects(() => db.query(
    'select public.administrator_activate_developer_test_session($1,$2,now()+interval \'1 day\')',
    [booking,'Test booking']),/BOOKING_HAS_PRODUCTION_FINANCIAL_HISTORY/); checks++;
  await assert.rejects(() => db.query(
    'select public.administrator_delete_test_booking($1)',[booking]),
    /ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED/); checks++;
  await db.query('delete from payment_records where booking_id=$1',[booking]);
  await rejects('force_start','assigned',0,'DOWNPAYMENT_NOT_CONFIRMED');
  await db.query('update package_bookings set downpayment_ready=true where id=$1',[booking]);
  await rejects('next_stop','assigned',0,'NEXT_STOP_REQUIRES_COMPLETED_STOP');
  await rejects('force_start','at_stop',0,'STALE_BOOKING_TEST_STATE');
  await progress('force_start','assigned',0);
  await expectState('en_route_stop',0,'pending');
  assert.notEqual(await scalar("select current_setting('touristrike.gps_transition_verified',true)"),'true'); checks++;
  await assert.rejects(() => db.query(`update booking_drivers
    set journey_state='at_stop' where booking_id=$1`,[booking]),
    /DRIVER_LOCATION_STALE/); checks++;
  await progress('simulate_arrival','en_route_stop',0);
  await expectState('at_stop',0,'at_spot');
  await db.query(`insert into payment_records(booking_id,provider,status,payment_stage)
    values($1,'manual','confirmed','down_payment')`,[booking]);
  assert.equal(await scalar(`select public.booking_test_session_active('${booking}')`),true); checks++;
  await db.query(`insert into booking_stop_waiting_charges(
    itinerary_item_id,booking_id,status,additional_amount,paid_until,
    interval_minutes,hourly_rate,rate_per_interval,overtime_seconds,
    chargeable_intervals) values($1,$2,'active',0,now()+interval '60 minutes',
      15,120,30,0,0)`,[stop1,booking]);
  await db.query(`select public.administrator_apply_booking_timing_test(
    $1,'remaining',1,null)`, [booking]);
  assert.equal(await scalar(`select test_override_kind from
    booking_stop_waiting_charges where itinerary_item_id='${stop1}'`),'remaining'); checks++;
  await db.query(`select public.administrator_apply_booking_timing_test(
    $1,'overtime',30,7)`, [booking]);
  assert.equal(await scalar(`select additional_amount from
    booking_stop_waiting_charges where itinerary_item_id='${stop1}'`),'14.00'); checks++;
  await db.query(`select public.administrator_reset_booking_timing_test(
    $1,'overtime')`, [booking]);
  assert.equal(await scalar(`select test_deadline_override is null and
    test_rate_per_interval_override is null from booking_stop_waiting_charges
    where itinerary_item_id='${stop1}'`),true); checks++;
  await rejects('next_stop','at_stop',0,'NEXT_STOP_REQUIRES_COMPLETED_STOP');
  await rejects('simulate_departure','at_stop',0,'DEPARTURE_REQUIRES_COMPLETED_STOP');
  await progress('complete_stop','at_stop',0);
  await progress('simulate_departure','at_stop',0);
  await expectState('stop_done',0,'completed');
  assert.equal(await scalar(`select actual_departure_time is not null
    from booking_itinerary_items where id='${stop1}'`),true); checks++;
  const next = await progress('next_stop','stop_done',0);
  assert.equal(next.current_stop_id,stop2); checks++;
  await expectState('en_route_stop',1,'pending');
  await rejects('next_stop','stop_done',0,'STALE_BOOKING_TEST_STATE');
  await assert.rejects(() => db.query(`update booking_drivers
    set journey_state='at_stop' where booking_id=$1`,[booking]),
    /DRIVER_LOCATION_STALE/); checks++;
  await db.query(`insert into booking_stop_waiting_charges(
    itinerary_item_id,booking_id,status,additional_amount)
    values($1,$2,'finalized',10)`,[stop1,booking]);
  await rejects('previous_stop','en_route_stop',1,
    'PREVIOUS_STOP_BLOCKED_BY_FINANCIAL_HISTORY');
  await expectState('en_route_stop',1,'pending');
  await db.query('delete from booking_stop_waiting_charges where itinerary_item_id=$1',[stop1]);
  await progress('previous_stop','en_route_stop',1);
  await expectState('en_route_stop',0,'pending');
  await progress('simulate_arrival','en_route_stop',0);
  await progress('complete_stop','at_stop',0);
  await progress('simulate_departure','at_stop',0);
  await progress('next_stop','stop_done',0);
  await progress('simulate_arrival','en_route_stop',1);
  await progress('complete_stop','at_stop',1);
  await progress('simulate_departure','at_stop',1);
  await rejects('next_stop','stop_done',1,'REMAINING_BALANCE_NOT_CONFIRMED');
  await db.query('update package_bookings set remaining_payment_ready=true where id=$1',[booking]);
  await progress('next_stop','stop_done',1);
  await expectState('en_route_dropoff',1,'completed');
  await rejects('next_stop','stop_done',1,'STALE_BOOKING_TEST_STATE');
  await rejects('force_complete','en_route_dropoff',1,'DROPOFF_REQUIRED_BEFORE_COMPLETION');
  await progress('simulate_arrival','en_route_dropoff',1);
  await expectState('at_dropoff',1,'completed');
  await progress('force_complete','at_dropoff',1);
  await expectState('completed',1,'completed');
  assert.equal(await scalar(`select booking_status from package_bookings
    where id='${booking}'`),'completed'); checks++;
  assert.equal(await scalar(`select count(*) from audit_logs
    where record_id='${booking}' and action='next_stop'`),3); checks++;
  await rejects('next_stop','completed',1,'ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED');
  await assert.rejects(() => db.query(
    'select public.administrator_progress_booking_test_missing($1)',[booking]),
    /does not exist/); checks++;
  console.log(`administrator tour testing: ${checks} persisted-state checks passed`);
} finally {
  await db.close();
}
