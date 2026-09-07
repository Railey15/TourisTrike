// Isolated PostgreSQL contract tests; never connects to the deployed database.
// Uses the same temporary PGlite installation as verify_shared_trip_sql.cjs.
const {PGlite} = require(require('path').join(process.env.TEMP,
  'TourisTrike-map-sql-check/node_modules/@electric-sql/pglite'));
const fs = require('fs');
const assert = require('assert/strict');
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
(async () => {
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon; create role authenticated;
      create table shared_trip_links(id uuid primary key, booking_id uuid, tourist_id uuid,
        public_token text, access_code text, is_active boolean, revoked_at timestamptz, expires_at timestamptz);
      create table package_bookings(id uuid primary key, assigned_driver_id uuid, status text,
        booking_status text, pickup_address text, dropoff_address text,
        pickup_latitude double precision, pickup_longitude double precision,
        dropoff_latitude double precision, dropoff_longitude double precision);
      create table package_activities(id uuid primary key, booking_id uuid, tour_status text,
        driver_id uuid, driver_latitude double precision, driver_longitude double precision, created_at timestamptz);
      create table booking_drivers(booking_id uuid, driver_id uuid, status text,
        journey_state text, current_stop_index integer, state_updated_at timestamptz, accepted_at timestamptz,
        primary key(booking_id, driver_id));
      create table driver_live_locations(driver_id uuid primary key, activity_id uuid,
        latitude double precision, longitude double precision, heading double precision, updated_at timestamptz);
      create table profiles(id uuid primary key, full_name text, first_name text, middle_name text, last_name text,
        mobile text, address text, email text);
      create table driver_details(driver_id uuid primary key, plate_number text, toda_name text, license_number text);
      create table booking_itinerary_items(booking_id uuid, destination_name text,
        spot_status text, destination_order integer, order_number integer,
        actual_arrival_time timestamptz, actual_departure_time timestamptz,
        latitude double precision, longitude double precision,
        arrival_time time, departure_time time, estimated_stay_duration_minutes integer);
      create table shared_trip_access_logs(shared_link_id uuid, booking_id uuid,
        device_info text, user_agent text, access_status text);
      create table notifications(user_id uuid, title text, body text, type text, is_read boolean);
      insert into package_bookings values ('${id(1)}','${id(10)}','accepted','driver_on_the_way',
        'Private street, Pickup Area','Private street, Dropoff Area',15,121,15.1,121.1);
      insert into shared_trip_links values ('${id(2)}','${id(1)}','${id(4)}','test-token','123456',true,null,now()+interval '1 hour');
      insert into package_activities values ('${id(3)}','${id(1)}','driver_en_route','${id(10)}',88,88,now());
      insert into package_activities values ('${id(30)}','${id(31)}','on_tour','${id(11)}',77,77,now());
      insert into booking_drivers values ('${id(1)}','${id(10)}','accepted','en_route_pickup',0,now(),now()-interval '1 minute');
      insert into driver_live_locations values ('${id(10)}','${id(3)}',15,121,30,now());
      insert into profiles values ('${id(10)}','Driver One','','','', 'PRIVATE_PHONE','PRIVATE_ADDRESS','PRIVATE_EMAIL');
      insert into driver_details values ('${id(10)}','ABC-123','Bustos TODA','PRIVATE_LICENSE');
    `);
    await db.exec(fs.readFileSync('supabase/migrations/20260907010000_shared_trip_read_only_tracking.sql', 'utf8'));
    async function read(code = '123456') {
      await db.exec('set role anon');
      try {
        return (await db.query(`select get_shared_trip_details(
          p_public_token => 'test-token', p_access_code => $1, p_silent => true) as data`, [code])).rows[0].data;
      } finally { await db.exec('reset role'); }
    }
    await db.exec(`
      insert into booking_drivers values ('${id(1)}','${id(11)}','accepted','en_route_pickup',0,now(),now());
      insert into driver_live_locations values ('${id(11)}',null,15.02,121.02,90,now());
    `);
    assert.equal((await read()).drivers.filter(d => d.latitude !== null).length, 1);
    console.log('PASS reproduced old RPC: 2 assignments but only 1 location when activity_id is null');

    await db.exec(fs.readFileSync('supabase/migrations/20260907020000_shared_trip_convoy_read.sql', 'utf8'));
    let data = await read();
    assert.equal(data.drivers.length, 2);
    assert.equal(data.drivers.filter(d => d.latitude !== null).length, 2);
    assert.equal(data.drivers[0].driver_name, 'Driver One');
    assert.equal(data.drivers[0].plate_number, 'ABC-123');
    assert(data.drivers.every(d => d.updated_at));
    assert(!JSON.stringify(data).includes('PRIVATE_'));
    assert.equal(data.pickup_landmark, 'Pickup Area');
    console.log('PASS 2 drivers, independent GPS, names/vehicle/freshness, guest-safe fields');

    await db.exec(`delete from driver_live_locations where driver_id='${id(11)}'`);
    data = await read();
    assert.equal(data.drivers.length, 2);
    assert.equal(data.drivers.filter(d => d.latitude !== null).length, 1);
    console.log('PASS missing GPS does not remove driver from roster');
    await db.exec(`insert into driver_live_locations values ('${id(11)}',null,15.03,121.03,90,now());
      update driver_live_locations set latitude=15.04,updated_at=now() where driver_id='${id(10)}';`);
    data = await read();
    assert.equal(data.drivers.find(d => d.driver_id === id(10)).latitude, 15.04);
    assert.equal(data.drivers.find(d => d.driver_id === id(11)).latitude, 15.03);
    console.log('PASS each driver updates independently');

    await db.exec(`update driver_live_locations set activity_id='${id(30)}' where driver_id='${id(11)}'`);
    assert.equal((await read()).drivers.find(d => d.driver_id === id(11)).latitude, null);
    await db.exec(`update driver_live_locations set activity_id=null,updated_at=now()-interval '1 day' where driver_id='${id(11)}'`);
    assert.equal((await read()).drivers.find(d => d.driver_id === id(11)).latitude, null);
    console.log('PASS excludes another booking and GPS older than an unlinked assignment');

    await db.exec(`update booking_drivers set status='rejected' where driver_id='${id(11)}'`);
    assert.equal((await read()).drivers.length, 1);
    await db.exec(`update driver_live_locations set latitude=999 where driver_id='${id(10)}'`);
    assert.equal((await read()).drivers[0].latitude, null);
    console.log('PASS 1-driver roster and invalid-coordinate rejection');
    assert.equal((await read('wrong')).error, 'invalid_code');
    assert.equal((await db.query('select count(*)::int n from shared_trip_access_logs')).rows[0].n, 0);
    assert.equal((await db.query('select count(*)::int n from notifications')).rows[0].n, 0);
    await db.exec("update package_activities set tour_status='at_spot'");
    assert.equal((await read()).tour_status, 'at_spot');
    await db.exec("update package_bookings set booking_status='completed'");
    assert((await read()).drivers.every(d => d.latitude === null && d.longitude === null));
    await db.exec("update shared_trip_links set expires_at=now()-interval '1 second'");
    assert.equal((await read()).error, 'invalid_or_expired');
    await db.exec("update shared_trip_links set expires_at=now()+interval '1 hour',revoked_at=now()");
    assert.equal((await read()).error, 'invalid_or_expired');
    console.log('PASS status mirrors persistence; completed/expired/revoked tracking is unavailable');

    await db.exec('set role anon');
    for (const table of ['package_bookings','booking_drivers','driver_live_locations','booking_itinerary_items']) {
      await assert.rejects(db.query(`select * from ${table}`));
      await assert.rejects(db.query(`delete from ${table}`));
    }
    console.log('PASS anonymous direct reads and trip mutations denied; silent refresh has no writes');
  } finally { await db.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
