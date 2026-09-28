// Isolated PostgreSQL behavior checks. Never connects to the linked project.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { runPaymentCases } from './tour_payment_consistency_cases.mjs';

const db = new PGlite();
const migration = readFileSync(new URL('../migrations/20260928000000_tour_stay_waiting_and_tourist_reviews.sql', import.meta.url), 'utf8');
const uuid = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const office = uuid(1), tourist = uuid(2), driver = uuid(3), outsider = uuid(4);
const booking = uuid(10), stop1 = uuid(11), stop2 = uuid(12);
let checks = 0;
const check = (actual, expected, label) => { assert.deepEqual(actual, expected, label); checks++; };
const scalar = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const failure = async (sql, params, pattern) => {
  await assert.rejects(() => db.query(sql, params), new RegExp(pattern));
  checks++;
};
const login = user => db.query("select set_config('test.uid',$1,false)", [user]);
const functionSql = name => {
  const start = migration.indexOf(`create or replace function public.${name}(`);
  assert(start >= 0, name);
  const end = migration.indexOf('$$;', start);
  assert(end > start, name);
  return migration.slice(start, end + 3);
};
const snippet = (startMarker, endMarker) => {
  const start = migration.indexOf(startMarker);
  const end = migration.indexOf(endMarker, start);
  assert(start >= 0 && end > start, startMarker);
  return migration.slice(start, end + endMarker.length);
};
const section = (startMarker,endMarker) => {
  const start=migration.indexOf(startMarker), end=migration.indexOf(endMarker,start);
  assert(start>=0 && end>start,startMarker);
  return migration.slice(start,end);
};

try {
  await db.exec(`
    create schema auth;
    create role anon; create role authenticated;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('test.uid',true),'')::uuid $$;
    create table public.profiles(id uuid primary key, role text, province text);
    create table public.subtenant_details(id uuid primary key, city text, is_active boolean,province text default 'Bulacan');
    create table public.subtenant_fare_settings(id uuid primary key,subtenant_id uuid,
      city text,is_active boolean,waiting_fee numeric,updated_at timestamptz);
    create table public.package_bookings(id uuid primary key,tourist_id uuid,
      municipality text,province text,status text,booking_status text,
      total_amount numeric,remaining_balance numeric,completed_at timestamptz,
      updated_at timestamptz,assigned_driver_id uuid);
    create table public.booking_itinerary_items(id uuid primary key,booking_id uuid,
      destination_name text,estimated_stay_duration_minutes integer,
      actual_arrival_time timestamptz,actual_departure_time timestamptz,spot_status text);
    create table public.booking_drivers(id uuid primary key,booking_id uuid,driver_id uuid,status text);
    create table public.package_activities(id uuid primary key,booking_id uuid);
    create table public.trip_status_logs(id uuid default gen_random_uuid(),activity_id uuid,
      booking_id uuid,status text,notes text,logged_at timestamptz);
    create table public.booking_payment_requirements(id uuid default gen_random_uuid(),
      booking_id uuid,payment_stage text,amount numeric,status text default 'required',
      satisfied_at timestamptz,satisfied_by_payment_record_id uuid,
      updated_at timestamptz,unique(booking_id,payment_stage));
    create table public.payment_records(id uuid primary key,booking_id uuid,payment_stage text,
      status text,amount numeric,paid_at timestamptz,created_at timestamptz default now());
    create table public.audit_logs(id uuid default gen_random_uuid(),actor_id uuid,
      action text,table_name text,record_id text,description text);
    create function public.cities_match(a text,b text) returns boolean language sql immutable
      as $$ select lower(trim(a))=lower(trim(b)) $$;
    create function public.current_profile_role() returns text language sql stable
      as $$ select case when role='main_tenant' then 'admin' else role end
        from public.profiles where id=auth.uid() $$;
    create function public.is_main_tenant() returns boolean language sql stable
      as $$ select exists(select 1 from public.profiles
        where id=auth.uid() and role='main_tenant') $$;
    create function public.current_subtenant_city() returns text language sql stable
      as $$ select city from public.subtenant_details where id=auth.uid() $$;
    create function public.is_provincial_admin() returns boolean language sql stable
      as $$ select false $$;
    create function public.is_developer_test_booking(uuid) returns boolean language sql stable
      as $$ select false $$;
    create table public.test_tour_notifications(recipient_id uuid, booking_id uuid,
      event_key text, unique(recipient_id,booking_id,event_key));
    create function public.emit_tour_notification(uuid,uuid,text,text,text,text,boolean)
      returns void language sql as $$
        insert into public.test_tour_notifications(recipient_id,booking_id,event_key)
        values($1,$2,$3) on conflict do nothing $$;
  `);
  await db.exec(snippet('alter table public.subtenant_fare_settings\n  add column if not exists tour_waiting_fee_per_15_minutes', 'check (tour_waiting_fee_per_15_minutes >= 0);'));
  await db.exec(snippet('create table public.booking_stop_waiting_charges (', '\n);'));
  await db.exec(snippet('alter table public.package_bookings\n  add column if not exists tour_waiting_subtenant_id', 'check (tour_waiting_rate_snapshot >= 0);'));
  await db.exec(snippet('create table public.tourist_reviews (', '\n);'));
  for (const name of [
    'main_tenant_can_read_booking','can_read_tour_booking','resolve_tour_waiting_rate','snapshot_booking_tour_waiting_rate',
    'snapshot_booking_stop_waiting_charge','finalize_booking_stop_waiting_charge',
    'submit_tourist_review','get_tourist_rating_summary',
    'get_booking_waiting_summary','get_tour_operations_report',
    'refresh_active_tour_waiting','guard_municipal_tour_waiting_rate',
    'guard_booking_tour_waiting_snapshot','guard_booked_stay_financial_fields',
    'get_municipal_tour_waiting_rate',
  ]) await db.exec(functionSql(name));
  await db.exec(`
    create trigger snapshot_booking_tour_waiting_rate before insert on package_bookings
      for each row execute function snapshot_booking_tour_waiting_rate();
    create trigger snapshot_booking_stop_waiting_charge after update of actual_arrival_time
      on booking_itinerary_items for each row execute function snapshot_booking_stop_waiting_charge();
    create trigger finalize_booking_stop_waiting_charge after update of actual_departure_time
      on booking_itinerary_items for each row execute function finalize_booking_stop_waiting_charge();
    create trigger guard_municipal_tour_waiting_rate before insert or update
      on subtenant_fare_settings for each row execute function guard_municipal_tour_waiting_rate();
    create trigger guard_booking_tour_waiting_snapshot before update of
      tour_waiting_subtenant_id,tour_waiting_rate_snapshot on package_bookings
      for each row execute function guard_booking_tour_waiting_snapshot();
    create trigger guard_booked_stay_financial_fields before update
      on booking_itinerary_items for each row execute function guard_booked_stay_financial_fields();
  `);
  await db.query(`insert into profiles values($1,'subtenant','Bulacan'),($2,'tourist','Bulacan'),
      ($3,'driver','Bulacan'),($4,'driver','Bulacan')`, [office,tourist,driver,outsider]);
  await db.query(`insert into subtenant_details(id,city,is_active) values($1,'Alpha',true)`, [office]);
  await db.query(`insert into subtenant_fare_settings values($1,$2,'Alpha',true,100,now(),25)`,[uuid(5),office]);
  await db.query(`insert into subtenant_fare_settings values($1,$2,'Beta',false,100,now(),99)`,[uuid(6),office]);
  await failure(`insert into package_bookings(id,tourist_id,municipality,province,status,
    booking_status,total_amount,remaining_balance,updated_at)
    values($1,$2,'Beta','Bulacan','ongoing','on_tour',200,100,now())`,
    [uuid(13),tourist],'TOUR_WAITING_RATE_NOT_CONFIGURED');
  await db.query(`insert into package_bookings(id,tourist_id,municipality,province,status,
    booking_status,total_amount,remaining_balance,updated_at)
    values($1,$2,'Alpha','Bulacan','ongoing','on_tour',200,100,now())`,[booking,tourist]);
  check(Number(await scalar('select tour_waiting_rate_snapshot from package_bookings where id=$1',[booking])),25,'booking snapshots city rate');
  check(Number(await scalar("select get_municipal_tour_waiting_rate('Alpha')")),25,'booking disclosure reads active city rate');
  await db.query(`insert into package_activities values($1,$2)`,[uuid(20),booking]);
  await db.query(`insert into booking_payment_requirements(booking_id,payment_stage,amount,updated_at)
    values($1,'remaining_balance',100,now())`,[booking]);
  await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,
    estimated_stay_duration_minutes,spot_status) values
    ($1,$2,'First',60,'pending'),($3,$2,'Second',30,'pending')`,[stop1,booking,stop2]);
  await db.query(`update booking_itinerary_items set actual_arrival_time='2026-09-27 08:11:00+00'
    where id=$1`,[stop1]);
  check(await scalar('select paid_until from booking_stop_waiting_charges where itinerary_item_id=$1',[stop1]),
    new Date('2026-09-27T09:11:00.000Z'),'booked 60-minute stay sets paid-until');
  await db.query(`update subtenant_fare_settings set tour_waiting_fee_per_15_minutes=40 where id=$1`,[uuid(5)]);
  await db.query(`update booking_itinerary_items set actual_departure_time='2026-09-27 09:12:00+00'
    where id=$1`,[stop1]);
  check(Number(await scalar('select additional_amount from booking_stop_waiting_charges where itinerary_item_id=$1',[stop1])),25,'one minute costs one snapshotted interval');
  check(Number(await scalar('select remaining_balance from package_bookings where id=$1',[booking])),125,'charge adds to remaining balance');
  check(Number(await scalar('select total_amount from package_bookings where id=$1',[booking])),200,'original package total stays fixed');
  await db.query(`update booking_itinerary_items set actual_departure_time='2026-09-27 09:12:00+00'
    where id=$1`,[stop1]);
  check(Number(await scalar('select remaining_balance from package_bookings where id=$1',[booking])),125,'repeat departure does not double charge');
  await db.query(`update booking_itinerary_items set actual_arrival_time='2026-09-27 10:00:00+00'
    where id=$1`,[stop2]);
  await db.query(`update booking_itinerary_items set actual_departure_time='2026-09-27 10:46:00+00'
    where id=$1`,[stop2]);
  check(Number(await scalar('select chargeable_intervals from booking_stop_waiting_charges where itinerary_item_id=$1',[stop2])),2,'16 overtime minutes cost two intervals');
  check(Number(await scalar('select additional_amount from booking_stop_waiting_charges where itinerary_item_id=$1',[stop2])),50,'second stop keeps booked rate');
  check(Number(await scalar('select remaining_balance from package_bookings where id=$1',[booking])),175,'multiple stop charges aggregate');
  const noticeStop = uuid(40), noticeDriverAssignment = uuid(41);
  await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,
    estimated_stay_duration_minutes,spot_status)
    values($1,$2,'Notice stop',60,'arrived')`,[noticeStop,booking]);
  await db.query(`insert into booking_drivers values($1,$2,$3,'accepted')`,
    [noticeDriverAssignment,booking,driver]);
  await db.query(`with t as (select clock_timestamp() as value)
    insert into booking_stop_waiting_charges(booking_id,itinerary_item_id,municipality,
      included_minutes,arrived_at,paid_until,rate_per_interval)
    select $1,$2,'Alpha',60,t.value-interval '46 minutes',
      t.value+interval '14 minutes',25 from t`,[booking,noticeStop]);
  await db.query('select refresh_active_tour_waiting()');
  check(Number(await scalar(`select count(*) from test_tour_notifications
    where event_key=$1`,[`stay:15:${noticeStop}`])),2,'15-minute notice reaches tourist and driver');
  await db.query(`with t as (select clock_timestamp() as value)
    update booking_stop_waiting_charges set arrived_at=t.value-interval '56 minutes',
      paid_until=t.value+interval '4 minutes' from t where itinerary_item_id=$1`,[noticeStop]);
  await db.query('select refresh_active_tour_waiting()');
  check(Number(await scalar(`select count(*) from test_tour_notifications
    where event_key=$1`,[`stay:5:${noticeStop}`])),2,'5-minute notice reaches tourist and driver');
  await db.query(`with t as (select clock_timestamp() as value)
    update booking_stop_waiting_charges set arrived_at=t.value-interval '61 minutes',
      paid_until=t.value-interval '1 minute' from t where itinerary_item_id=$1`,[noticeStop]);
  await db.query('select refresh_active_tour_waiting()');
  await db.query('select refresh_active_tour_waiting()');
  check(Number(await scalar(`select count(*) from test_tour_notifications
    where event_key=$1`,[`stay:overtime:${noticeStop}`])),2,'overtime notice is deduplicated');
  check(Number(await scalar(`select chargeable_intervals from booking_stop_waiting_charges
    where itinerary_item_id=$1`,[noticeStop])),1,'server refresh accrues one started interval');
  await db.query('delete from booking_stop_waiting_charges where itinerary_item_id=$1',[noticeStop]);
  await db.query('delete from booking_itinerary_items where id=$1',[noticeStop]);
  await db.query('delete from booking_drivers where id=$1',[noticeDriverAssignment]);
  await login(driver);
  await failure(`update subtenant_fare_settings set tour_waiting_fee_per_15_minutes=99
    where id=$1`,[uuid(5)],'MUNICIPAL_TOUR_RATE_OWNER_REQUIRED');
  await failure(`update package_bookings set tour_waiting_rate_snapshot=99 where id=$1`,
    [booking],'TOUR_WAITING_RATE_SNAPSHOT_IMMUTABLE');
  await login(tourist);
  await failure(`update booking_itinerary_items set estimated_stay_duration_minutes=1 where id=$1`,
    [stop1],'BOOKED_STAY_IMMUTABLE');
  await failure(`update booking_itinerary_items set actual_departure_time=now() where id=$1`,
    [stop1],'TOUR_MILESTONE_RPC_REQUIRED');
  await login('');
  check(Number(await scalar(`select amount from booking_payment_requirements
    where booking_id=$1 and payment_stage='remaining_balance'`,[booking])),175,'payment requirement follows obligation');
  check(Number(await scalar('select count(*) from payment_records')),0,'charges do not invent payments');
  await db.query(`insert into package_bookings(id,tourist_id,municipality,province,status,
    booking_status,total_amount,remaining_balance,updated_at)
    values($1,$2,'Alpha','Bulacan','ongoing','on_tour',200,100,now())`,[uuid(14),tourist]);
  await db.query(`insert into package_activities values($1,$2)`,[uuid(21),uuid(14)]);
  await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,
    estimated_stay_duration_minutes,spot_status) values($1,$2,'On time',15,'pending')`,[uuid(15),uuid(14)]);
  await db.query(`update booking_itinerary_items set actual_arrival_time='2026-09-27 11:00:00+00'
    where id=$1`,[uuid(15)]);
  await db.query(`update booking_itinerary_items set actual_departure_time='2026-09-27 11:15:00+00'
    where id=$1`,[uuid(15)]);
  check(Number(await scalar('select additional_amount from booking_stop_waiting_charges where itinerary_item_id=$1',[uuid(15)])),0,'no fee at paid-until boundary');
  check(Number(await scalar('select remaining_balance from package_bookings where id=$1',[uuid(14)])),100,'on-time departure preserves balance');
  // A booking created before this migration has no tour-rate snapshot. An
  // unconfigured municipality must not strand its driver at departure.
  await db.exec('alter table package_bookings disable trigger snapshot_booking_tour_waiting_rate;');
  await db.query(`insert into package_bookings(id,tourist_id,municipality,province,status,
    booking_status,total_amount,remaining_balance,updated_at)
    values($1,$2,'Beta','Bulacan','ongoing','on_tour',200,100,now())`,[uuid(16),tourist]);
  await db.exec('alter table package_bookings enable trigger snapshot_booking_tour_waiting_rate;');
  await db.query(`insert into package_activities values($1,$2)`,[uuid(22),uuid(16)]);
  await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,
    estimated_stay_duration_minutes,spot_status) values($1,$2,'Legacy stop',15,'pending')`,[uuid(17),uuid(16)]);
  await db.query(`update booking_itinerary_items set actual_arrival_time='2026-09-27 11:00:00+00'
    where id=$1`,[uuid(17)]);
  check(await scalar('select rate_per_interval from booking_stop_waiting_charges where itinerary_item_id=$1',[uuid(17)]),
    null,'historical stop records unavailable municipal rate explicitly');
  await db.query(`update booking_itinerary_items set actual_departure_time='2026-09-27 11:31:00+00'
    where id=$1`,[uuid(17)]);
  check(Number(await scalar('select chargeable_intervals from booking_stop_waiting_charges where itinerary_item_id=$1',[uuid(17)])),
    2,'historical overtime remains measurable without a rate');
  check(Number(await scalar('select additional_amount from booking_stop_waiting_charges where itinerary_item_id=$1',[uuid(17)])),
    0,'undefined municipal rate never becomes a fee');
  check(Number(await scalar('select remaining_balance from package_bookings where id=$1',[uuid(16)])),
    100,'historical booking can depart without undefined charge');
  await login(driver);
  await failure(`select submit_tourist_review($1,5::smallint,'Good')`,[booking],'COMPLETED_BOOKING_REQUIRED');
  await db.query(`update package_bookings set booking_status='completed' where id=$1`,[booking]);
  await failure(`select submit_tourist_review($1,5::smallint,'Good')`,[booking],'NOT_COMPLETED_BOOKING_DRIVER');
  await db.query(`insert into booking_drivers values($1,$2,$3,'completed')`,[uuid(30),booking,driver]);
  await db.query(`select submit_tourist_review($1,5::smallint,'Good')`,[booking]);
  check(Number(await scalar('select count(*) from tourist_reviews where tourist_id=$1',[tourist])),1,'driver reviewed actual booking tourist');
  await failure(`select submit_tourist_review($1,4::smallint,'Again')`,[booking],'duplicate key');
  await login(outsider);
  await failure(`select submit_tourist_review($1,1::smallint,'Bad')`,[booking],'NOT_COMPLETED_BOOKING_DRIVER');
  await login(driver);
  await failure(`select submit_tourist_review($1,6::smallint,'Invalid')`,[booking],'INVALID_RATING');
  await db.query(`insert into booking_drivers values($1,$2,$3,'completed')`,[uuid(31),booking,outsider]);
  await login(outsider);
  await db.query(`select submit_tourist_review($1,3::smallint,null)`,[booking]);
  await login(driver);
  const rating = (await db.query('select get_tourist_rating_summary($1) as summary',[tourist])).rows[0].summary;
  check(Number(rating.total_reviews),2,'each completed convoy driver may review once');
  check(Number(rating.average_rating),4,'tourist aggregate is separate and accurate');
  await login(tourist);
  const summary = (await db.query('select get_booking_waiting_summary($1) as summary',[booking])).rows[0].summary;
  check(Number(summary.finalized_waiting),75,'tourist reads finalized waiting from server ledger');
  check(Number(summary.total_remaining),175,'tourist balance includes finalized waiting');
  await login(office);
  const report = (await db.query(`select get_tour_operations_report(
    '2026-01-01'::timestamptz,'2027-01-01'::timestamptz,'Alpha') as report`)).rows[0].report;
  check(Number(report.tours_with_overtime),1,'municipal report counts affected booking once');
  check(Number(report.chargeable_intervals),3,'municipal report sums persisted intervals');
  check(Number(report.additional_waiting_fees),75,'municipal report sums finalized fees');
  check(Number(report.average_tourist_rating),4,'municipal report uses driver-to-tourist ratings');
  await failure(`select get_tour_operations_report(
    '2026-01-01'::timestamptz,'2027-01-01'::timestamptz,'Beta')`,[],
    'REPORT_CITY_ACCESS_DENIED');
  await db.query(`insert into payment_records(id,booking_id,payment_stage,status,amount)
    values($1,$2,'remaining_balance','pending_confirmation',900),
      ($3,$2,'remaining_balance','confirmed',20)`,[uuid(50),booking,uuid(51)]);
  const financial = (await db.query(`select get_tour_operations_report(
    '2026-01-01'::timestamptz,'2027-01-01'::timestamptz,'Alpha') as report`)).rows[0].report;
  check(Number(financial.confirmed_collections),20,'pending payments are not reported as collected');
  // The existing payment trigger zeroes the persisted balance when the
  // remaining requirement is satisfied. The summary must not subtract the
  // same confirmed payment for a second time.
  await db.query('update package_bookings set remaining_balance=0 where id=$1',[booking]);
  await login(tourist);
  const paidSummary = (await db.query('select get_booking_waiting_summary($1) as summary',[booking])).rows[0].summary;
  check(Number(paidSummary.total_remaining),0,'satisfied payment is not subtracted twice');
  await login(office);
  await db.query(`insert into profiles(id,role,province) values($1,'main_tenant','Bulacan'),
    ($2,'main_tenant','Other')`,[uuid(7),uuid(8)]);
  await login(uuid(7));
  const province = (await db.query(`select get_tour_operations_report(
    '2026-01-01'::timestamptz,'2027-01-01'::timestamptz,null) as report`)).rows[0].report;
  check(Number(province.additional_waiting_fees),75,'main tenant sees province waiting fees');
  check(Number((await db.query('select get_booking_waiting_summary($1) as summary',[booking])).rows[0].summary.finalized_waiting),
    75,'main tenant reads a booking in own province');
  await login(uuid(8));
  const otherProvince = (await db.query(`select get_tour_operations_report(
    '2026-01-01'::timestamptz,'2027-01-01'::timestamptz,null) as report`)).rows[0].report;
  check(Number(otherProvince.additional_waiting_fees),0,'main tenant cannot see another province');
  await failure('select get_booking_waiting_summary($1)',[booking],
    'BOOKING_ACCESS_DENIED');
  await db.exec(`grant usage on schema public,auth to authenticated;
    grant select on package_bookings,booking_drivers,profiles,subtenant_details
      to authenticated;`);
  await db.exec(section(
    'alter table public.booking_stop_waiting_charges enable row level security;',
    '-- One source of truth for the municipality'));
  await db.exec(section(
    'alter table public.tourist_reviews enable row level security;',
    'create or replace function public.submit_tourist_review'));
  check(await scalar(`select has_table_privilege('authenticated',
    'booking_stop_waiting_charges','insert')`),false,'client cannot insert waiting charges');
  check(await scalar(`select has_table_privilege('authenticated',
    'tourist_reviews','insert')`),false,'client cannot insert tourist reviews');
  await db.query(`insert into profiles(id,role,province) values($1,'driver','Bulacan')`,[uuid(60)]);
  await login(uuid(60));
  await db.exec('set role authenticated');
  check(Number(await scalar('select count(*) from booking_stop_waiting_charges')),0,
    'unrelated driver cannot read waiting charges');
  check(Number(await scalar('select count(*) from tourist_reviews')),0,
    'unrelated driver cannot read tourist reviews');
  await login(tourist);
  check(Number(await scalar('select count(*) from booking_stop_waiting_charges')),4,
    'tourist can read own waiting ledger');
  check(Number(await scalar('select count(*) from tourist_reviews')),2,
    'tourist can read reviews about them');
  await db.exec('reset role');
  await login('');
  const foreignOffice=uuid(70),provinceLess=uuid(71);
  await db.query("insert into profiles(id,role,province) values($1,'subtenant','Another Province'),($2,'main_tenant',null)",[foreignOffice,provinceLess]);
  await db.query("insert into subtenant_details(id,city,is_active,province) values($1,'Alpha',true,'Another Province')",[foreignOffice]);
  await db.query("insert into subtenant_fare_settings values($1,$2,'Alpha',true,500,now(),77)",[uuid(72),foreignOffice]);
  await failure("select get_municipal_tour_waiting_rate('Alpha')",[],'AMBIGUOUS_MUNICIPAL_TOUR_RATE');
  check(Number(await scalar("select get_municipal_tour_waiting_rate('Alpha','Bulacan')")),40,'province-qualified rate does not use same-city foreign office');
  check(Number(await scalar("select get_municipal_tour_waiting_rate('Alpha','Another Province')")),77,'foreign office has its own province-qualified rate');
  check(await scalar("select get_municipal_tour_waiting_rate('Alpha','Unconfigured Province')"),null,'missing province rate has no fallback');
  await login(foreignOffice);
  await failure('select get_booking_waiting_summary($1)',[booking],'BOOKING_ACCESS_DENIED');
  const foreignReport=(await db.query("select get_tour_operations_report('2026-01-01','2027-01-01','Alpha') as report")).rows[0].report;
  check(Number(foreignReport.additional_waiting_fees),0,'same-city foreign-province report excludes waiting obligations');
  check(Number(foreignReport.tourist_reviews),0,'same-city foreign-province report excludes reviews');
  await db.exec('set role authenticated');
  check(Number(await scalar('select count(*) from booking_stop_waiting_charges')),0,'same-city foreign-province waiting RLS denied');
  check(Number(await scalar('select count(*) from tourist_reviews')),0,'same-city foreign-province review RLS denied');
  await db.exec('reset role');
  await login(provinceLess);
  await failure("select get_tour_operations_report('2026-01-01','2027-01-01',null)",[],'PROVINCE_REQUIRED');
  await failure('select get_booking_waiting_summary($1)',[booking],'BOOKING_ACCESS_DENIED');
  await login('');
  const paymentCount=Number(await scalar('select count(*) from payment_records'));
  for(const [index,minutes,intervals] of [[0,0,0],[1,1,1],[2,15,1],[3,16,2],[4,30,2],[5,31,3]]) {
    const bid=uuid(100+index),sid=uuid(110+index);
    await db.query("insert into package_bookings(id,tourist_id,municipality,province,status,booking_status,total_amount,remaining_balance) values($1,$2,'Alpha','Bulacan','ongoing','on_tour',1000,750)",[bid,tourist]);
    await db.query("insert into booking_payment_requirements(booking_id,payment_stage,amount) values($1,'remaining_balance',750)",[bid]);
    await db.query("insert into booking_itinerary_items(id,booking_id,destination_name,estimated_stay_duration_minutes) values($1,$2,'Boundary',60)",[sid,bid]);
    await db.query("update booking_itinerary_items set actual_arrival_time='2026-09-27 08:00+00' where id=$1",[sid]);
    await db.query("update booking_itinerary_items set actual_departure_time='2026-09-27 09:00+00'::timestamptz+make_interval(mins=>$2) where id=$1",[sid,minutes]);
    check(Number(await scalar('select chargeable_intervals from booking_stop_waiting_charges where itinerary_item_id=$1',[sid])),intervals,minutes+' minute interval boundary');
    check(Number(await scalar('select remaining_balance from package_bookings where id=$1',[bid])),750+intervals*40,minutes+' minute remaining obligation');
    await db.query('update booking_itinerary_items set actual_departure_time=actual_departure_time where id=$1',[sid]);
    check(Number(await scalar('select amount from booking_payment_requirements where booking_id=$1',[bid])),750+intervals*40,minutes+' minute idempotent payment requirement');
  }
  check(Number(await scalar('select count(*) from payment_records')),paymentCount,'waiting finalization never fabricates confirmed payments');
  // Reopening a satisfied remaining stage must require only the new debt.
  // A historical requirement is a gross amount, while remaining_balance is
  // already net of the confirmed collection. The real submission validator
  // requires these two current amounts to agree.
  const settledBooking=uuid(200),laterStop=uuid(201),receipt=uuid(202);
  await db.query("insert into package_bookings(id,tourist_id,municipality,province,status,booking_status,total_amount,remaining_balance) values($1,$2,'Alpha','Bulacan','ongoing','on_tour',1500,0)",[settledBooking,tourist]);
  await db.query("insert into payment_records(id,booking_id,payment_stage,status,amount) values($1,$2,'remaining_balance','confirmed',750)",[receipt,settledBooking]);
  await db.query("insert into booking_payment_requirements(booking_id,payment_stage,amount,status,satisfied_by_payment_record_id) values($1,'remaining_balance',750,'satisfied',$2)",[settledBooking,receipt]);
  await db.query("insert into booking_itinerary_items(id,booking_id,destination_name,estimated_stay_duration_minutes) values($1,$2,'Later stop',60)",[laterStop,settledBooking]);
  await db.query("update booking_itinerary_items set actual_arrival_time='2026-09-27 08:00+00' where id=$1",[laterStop]);
  await db.query("update booking_itinerary_items set actual_departure_time='2026-09-27 09:01+00' where id=$1",[laterStop]);
  const debt=Number(await scalar('select remaining_balance from package_bookings where id=$1',[settledBooking]));
  const requirement=Number(await scalar("select amount from booking_payment_requirements where booking_id=$1 and payment_stage='remaining_balance'",[settledBooking]));
  check(requirement,debt,'new waiting obligation after confirmed payment must match the collectible remaining requirement');
  await runPaymentCases({db,check,failure,scalar,login,uuid,migration,section});
  console.log(`PASS: ${checks} tour waiting and tourist-review SQL checks`);
} finally {
  await db.close();
}
