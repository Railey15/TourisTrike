// Isolated PostgreSQL (PGlite) contract checks, never connects to Supabase.
// npm install --prefix "$env:TEMP/TourisTrike-map-sql-check" --no-save @electric-sql/pglite
const {PGlite} = require(require('path').join(process.env.TEMP,
  'TourisTrike-map-sql-check/node_modules/@electric-sql/pglite'));
const fs = require('fs');
const assert = require('assert/strict');
(async () => {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated;
    create table shared_trip_links(id uuid, booking_id uuid, tourist_id uuid,
      public_token text, access_code text, is_active boolean, revoked_at timestamptz, expires_at timestamptz);
    create table package_bookings(id uuid, assigned_driver_id uuid, status text,
      booking_status text, pickup_address text, dropoff_address text,
      pickup_latitude double precision, pickup_longitude double precision,
      dropoff_latitude double precision, dropoff_longitude double precision);
    create table package_activities(id uuid, booking_id uuid, tour_status text,
      driver_id uuid, driver_latitude double precision, driver_longitude double precision, created_at timestamptz);
    create table booking_drivers(booking_id uuid, driver_id uuid, status text,
      journey_state text, current_stop_index integer, state_updated_at timestamptz);
    create table driver_live_locations(driver_id uuid, activity_id uuid,
      latitude double precision, longitude double precision, heading double precision);
    create table booking_itinerary_items(booking_id uuid, destination_name text,
      spot_status text, destination_order integer, order_number integer,
      actual_arrival_time timestamptz, actual_departure_time timestamptz,
      latitude double precision, longitude double precision,
      arrival_time time, departure_time time, estimated_stay_duration_minutes integer);
    create table shared_trip_access_logs(shared_link_id uuid, booking_id uuid,
      device_info text, user_agent text, access_status text);
    create table notifications(user_id uuid, title text, body text, type text, is_read boolean);
    insert into package_bookings values ('00000000-0000-0000-0000-000000000001',
      null, 'active','on_tour','Pickup, Area','Dropoff, Area',15,121,15.1,121.1);
    insert into shared_trip_links values ('00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000001',null,'test-token','123456',true,null,now()+interval '1 hour');
    insert into package_activities values ('00000000-0000-0000-0000-000000000003',
      '00000000-0000-0000-0000-000000000001','on_tour',null,88,88,now());
    insert into booking_drivers select '00000000-0000-0000-0000-000000000001',
      ('00000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
      'accepted','en_route_stop',0,now() from generate_series(10,12) i;
    insert into driver_live_locations select driver_id,
      '00000000-0000-0000-0000-000000000003',15,121,30 from booking_drivers;
  `);
  await db.exec(fs.readFileSync('supabase/migrations/20260907010000_shared_trip_read_only_tracking.sql', 'utf8'));
  async function read(code='123456', silent=true) {
    await db.exec('set role anon');
    try {
      return (await db.query(`select get_shared_trip_details(
        p_public_token => 'test-token', p_access_code => $1,
        p_user_agent => 'test', p_silent => $2) as data`,[code,silent])).rows[0].data;
    } finally { await db.exec('reset role'); }
  }
  let data = await read();
  assert.equal(data.drivers.length,3);
  assert.equal(data.drivers.filter(d=>d.latitude!==null).length,3);
  assert.equal(data.driver_latitude,15); // No obsolete activity GPS fallback.
  assert.equal(data.driver_name,''); assert.equal(data.driver_phone_masked,null);
  assert.equal((await read('wrong')).error,'invalid_code');
  assert.equal((await db.query('select count(*)::int n from shared_trip_access_logs')).rows[0].n,0);
  await read('123456',false);
  assert.equal((await db.query('select count(*)::int n from shared_trip_access_logs')).rows[0].n,1);
  await db.exec("update package_activities set tour_status='at_spot'");
  assert.equal((await read()).tour_status,'at_spot');
  await db.exec("update driver_live_locations set activity_id=null where driver_id='00000000-0000-0000-0000-000000000010'");
  assert.equal((await read()).drivers.filter(d=>d.latitude!==null).length,2);
  await db.exec("update package_bookings set booking_status='completed'");
  data=await read();
  assert.equal(data.driver_latitude,null);
  assert(data.drivers.every(d=>d.latitude===null && d.longitude===null));
  await db.exec("update shared_trip_links set is_active=false");
  assert.equal((await read()).error,'invalid_or_expired');
  await db.exec('set role anon');
  await assert.rejects(db.query('select * from driver_live_locations'));
  await db.close();
  console.log('Shared-trip SQL checks passed: named RPC, 3 drivers, persisted status, token/code, silent access, booking scope, completion, revocation, no anonymous table access.');
})().catch(e=>{console.error(e);process.exitCode=1;});
