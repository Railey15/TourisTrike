// Local PostgreSQL only; never connects to Supabase or sends notifications.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const db = new PGlite();
const read = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const scalar = async (sql, params=[]) => Object.values((await db.query(sql,params)).rows[0])[0];
let checks=0;
const check=(a,b,label)=>{assert.deepEqual(a,b,label);checks++;};
const rejects=async(sql,params,pattern)=>{await assert.rejects(db.query(sql,params),pattern);checks++;};
try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create function auth.uid() returns uuid language sql as $$
      select nullif(current_setting('test.uid',true),'')::uuid $$;
    create table subtenant_details(id uuid primary key,city text,province text);
    create table tour_packages(id bigint primary key,submitted_by uuid,city text);
    create table package_bookings(id uuid primary key default gen_random_uuid(),package_id bigint,
      pickup_latitude double precision,pickup_longitude double precision,
      dropoff_latitude double precision,dropoff_longitude double precision,
      municipality text,province text,status text default 'pending');
    create table booking_itinerary_items(id bigint generated always as identity,booking_id uuid,
      latitude double precision,longitude double precision,spot_status text default 'pending');
    create table customized_package_spots(id bigint generated always as identity,booking_id uuid,
      latitude double precision,longitude double precision,action_type text default 'kept');
    insert into subtenant_details values('00000000-0000-0000-0000-000000000001','Baliwag','Bulacan');
    insert into tour_packages values(1,'00000000-0000-0000-0000-000000000001','Baliuag');
    insert into package_bookings(id,package_id,status) values('00000000-0000-0000-0000-000000000099',1,'completed');
    insert into booking_itinerary_items(booking_id) values('00000000-0000-0000-0000-000000000099');
  `);
  await db.exec(read('../migrations/20260926000000_booking_service_areas.sql'));
  await db.exec(read('../migrations/20260926000001_booking_service_area_seed.sql'));
  check(await scalar('select count(*)::int from booking_service_areas'),3,'all configured municipalities');
  check(await scalar("select (resolve_booking_service_area(1)).municipality"),'Baliwag','stored owner/province and alias determine coverage');
  const geometry={type:'MultiPolygon',coordinates:[
    [[[120,14],[121,14],[121,15],[120,15],[120,14]],[[120.4,14.4],[120.6,14.4],[120.6,14.6],[120.4,14.6],[120.4,14.4]]],
    [[[122,14],[123,14],[123,15],[122,15],[122,14]]],
  ]};
  for(const [lat,lng,expected,label] of [
    [14.2,120.2,true,'inside'],[14.2,119.9,false,'outside'],[14,120.5,true,'edge'],[14,120,true,'vertex'],
    [14-1e-8,120.5,false,'just outside'],[14+1e-8,120.5,true,'just inside'],
    [14.5,120.5,false,'hole'],[14.4,120.5,true,'hole edge'],[14.5,122.5,true,'island'],
    [14.5,121.5,false,'between islands'],[null,120,false,'null'],['NaN',120,false,'NaN'],['Infinity',120,false,'infinity'],
  ]) check(await scalar('select service_area_covers($1,$2,$3)',[geometry,lat,lng]),expected,label);
  check(await scalar('select service_area_geometry_valid($1)',[{type:'Polygon',coordinates:[[[120,14],[121,14],[121,15],[120,14]]]}]),true,'valid geometry');
  for(const malformed of [null,{}, {type:'Point',coordinates:[120,14]}, {type:'Polygon',coordinates:[]},
    {type:'Polygon',coordinates:[[[120,14],[121,14],[121,15],[120,15]]]},
    {type:'Polygon',coordinates:[[[120,14],[181,14],[121,15],[120,14]]]}])
    check(await scalar('select service_area_geometry_valid($1)',[malformed]),false,'bad configuration rejected');

  // Known town-centre points and full-resolution dataset vertices.
  for(const [id,lat,lng] of [['ph-bul-baliwag',14.9549,120.9004],['ph-bul-bustos',14.9539783,120.9185984],['ph-bul-malolos',14.8433,120.8114]]) {
    check(await scalar('select service_area_covers(geometry,$2,$3) from booking_service_areas where id=$1',[id,lat,lng]),true,`${id} centre`);
    const g=await scalar('select geometry from booking_service_areas where id=$1',[id]);
    const p=g.type === 'Polygon' ? g.coordinates[0][0] : g.coordinates[0][0][0];
    check(await scalar('select service_area_covers($1,$2,$3)',[g,p[1],p[0]]),true,`${id} boundary vertex`);
  }
  const insert=`insert into package_bookings(package_id,pickup_latitude,pickup_longitude,dropoff_latitude,dropoff_longitude,municipality,province)
    values(1,$1,$2,$3,$4,'Baliwag','Bulacan') returning id`;
  const booking=await scalar(insert,[14.9549,120.9004,14.9549,120.9004]); checks++;
  await rejects(insert,[14.9549,120.9004,14.9539783,120.9185984],/Drop-off outside service area/);
  await rejects(insert,[14.9539783,120.9185984,14.9549,120.9004],/Pickup outside service area/);
  await rejects(insert,[null,null,14.9549,120.9004],/Pickup outside service area/);
  await rejects('update package_bookings set pickup_latitude=14.6,pickup_longitude=121 where id=$1',[booking],/Pickup outside/);
  await rejects('insert into booking_itinerary_items(booking_id,latitude,longitude) values($1,14.6,121)',[booking],/Destination outside/);
  await rejects('insert into customized_package_spots(booking_id,latitude,longitude) values($1,14.6,121)',[booking],/Destination outside/);
  await db.query("insert into customized_package_spots(booking_id,latitude,longitude,action_type) values($1,14.6,121,'removed')",[booking]);
  await rejects("update customized_package_spots set action_type='kept' where booking_id=$1",[booking],/Destination outside/);
  await db.query('insert into booking_itinerary_items(booking_id,latitude,longitude) values($1,14.9549,120.9004)',[booking]);
  await db.exec(`insert into subtenant_details values('00000000-0000-0000-0000-000000000002','Bustos','Bulacan');
    insert into tour_packages values(2,'00000000-0000-0000-0000-000000000002','Bustos')`);
  await rejects('update package_bookings set package_id=2,pickup_latitude=14.9539783,pickup_longitude=120.9185984,dropoff_latitude=14.9539783,dropoff_longitude=120.9185984 where id=$1',[booking],/Destination outside/);
  await db.exec("update package_bookings set status='completed'; update booking_itinerary_items set spot_status='completed'");
  check(await scalar("select status from package_bookings where id='00000000-0000-0000-0000-000000000099'"),'completed','historical booking remains readable/updateable');
  check(await scalar("select spot_status from booking_itinerary_items where booking_id='00000000-0000-0000-0000-000000000099'"),'completed','legacy arrival/status updates do not validate old coordinates');
  await db.exec("update subtenant_details set province='Another province'");
  await rejects(insert,[14.9549,120.9004,14.9549,120.9004],/not configured/);
  await db.exec("update subtenant_details set province='Bulacan'");
  await db.exec("update booking_service_areas set active=false where id='ph-bul-baliwag'");
  await rejects(insert,[14.9549,120.9004,14.9549,120.9004],/not configured/);
  await db.exec("update booking_service_areas set active=true where id='ph-bul-baliwag'");
  await rejects('select booking_service_area(1)',[],/Authentication required/);
  await db.exec("select set_config('test.uid','00000000-0000-0000-0000-000000000001',false)");
  check((await scalar('select booking_service_area(1)')).municipality,'Baliwag','authenticated RPC returns shared geometry');
  await db.exec('grant usage on schema public,auth to authenticated; set role authenticated');
  await rejects("update booking_service_areas set active=false",[],/permission denied/);
  await rejects('select resolve_booking_service_area(1)',[],/permission denied/);
  check((await scalar('select booking_service_area(1)')).id,'ph-bul-baliwag','restricted role can load package coverage');
  console.log(`PASS: ${checks} booking service-area database checks`);
} finally {await db.close();}
