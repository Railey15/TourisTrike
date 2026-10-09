import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
async function uid(n) { await db.query(`select set_config('test.uid',$1,false)`, [id(n)]); }
async function fails(sql, params, pattern) {
  await assert.rejects(() => db.query(sql, params), pattern);
}
try {
  await db.exec(`
    create schema auth; create schema storage;
    create role anon; create role authenticated;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('test.uid',true),'')::uuid $$;
    create table profiles(id uuid primary key, role text, full_name text);
    create table subtenant_details(id uuid primary key, city text,
      province text,is_active boolean);
    create table tour_packages(id bigint primary key,city text,submitted_by uuid);
    create table package_bookings(id uuid primary key,package_id bigint,
      tourist_id uuid,municipality text,province text,booking_status text,
      travel_date date,adults integer,children integer,total_passengers integer,
      required_drivers integer,additional_tricycle_count integer default 0,
      additional_tricycle_approved_count integer default 0,
      scheduled_start_at timestamptz,estimated_end_at timestamptz,
      total_amount numeric);
    create table booking_drivers(booking_id uuid,driver_id uuid,status text);
    create table driver_reviews(id uuid primary key,booking_id uuid,
      driver_id uuid,tourist_id uuid,rating integer,review_text text);
    create table tourist_booking_restrictions(tourist_id uuid,status text,
      restricted_until timestamptz);
    create table notifications(user_id uuid,title text,body text,type text);
    create table storage.buckets(id text primary key,name text,public boolean,
      file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(bucket_id text,name text);
    create function cities_match(text,text) returns boolean language sql
      immutable as $$ select lower(trim($1))=lower(trim($2)) $$;
    create function tricycle_passenger_capacity() returns integer
      language sql immutable as $$ select 3 $$;
    create function minimum_required_tricycles(integer) returns integer
      language sql immutable as $$ select ceil($1::numeric/3)::integer $$;
    create function create_package_booking_restriction_impl(
      p_booking jsonb,p_customized_spots jsonb,p_itinerary_items jsonb)
    returns public.package_bookings language plpgsql as $$
    declare b public.package_bookings;
    begin
      insert into public.package_bookings(id,package_id,tourist_id,municipality,
        province,booking_status,travel_date,adults,children,total_passengers,
        required_drivers,scheduled_start_at,estimated_end_at,total_amount)
      values (gen_random_uuid(),(p_booking->>'package_id')::bigint,auth.uid(),
        'Baliwag','Bulacan','waiting_for_drivers','2026-10-10',
        (p_booking->>'adults')::integer,(p_booking->>'children')::integer,
        (p_booking->>'total_passengers')::integer,
        (p_booking->>'required_drivers')::integer,
        '2026-10-10 00:00+00','2026-10-10 04:00+00',2000)
      returning * into b;
      return b;
    end $$;
    insert into profiles values
      ('${id(1)}','tourist','Tourist One'),
      ('${id(2)}','driver','Driver Two'),
      ('${id(3)}','subtenant','Baliwag MTO'),
      ('${id(4)}','subtenant','Other MTO'),
      ('${id(5)}','driver','Unrelated Driver');
    insert into subtenant_details values
      ('${id(3)}','Baliwag','Bulacan',true),
      ('${id(4)}','Malolos','Bulacan',true);
    insert into tour_packages values(1,'Baliwag','${id(3)}');
    insert into package_bookings values
      ('${id(10)}',1,'${id(1)}','Baliwag','Bulacan','completed',
      '2026-10-10',2,0,2,1,0,0,'2026-10-10 00:00+00',
      '2026-10-10 04:00+00',2000),
      ('${id(11)}',1,'${id(1)}','Baliwag','Bulacan','waiting_for_drivers',
      '2026-10-11',2,0,2,1,0,0,'2026-10-11 00:00+00',
      '2026-10-11 04:00+00',2000),
      ('${id(12)}',1,'${id(1)}','Baliwag','Bulacan','completed',
      '2026-10-12',2,0,2,1,0,0,'2026-10-12 00:00+00',
      '2026-10-12 04:00+00',2000);
    insert into booking_drivers values
      ('${id(10)}','${id(2)}','completed'),
      ('${id(12)}','${id(2)}','completed');
    insert into driver_reviews values('${id(20)}','${id(12)}',
      '${id(2)}','${id(1)}',1,'Verified low rating');
  `);
  await db.exec(readFileSync(new URL(
    '../migrations/20261009100000_selected_tricycles_at_booking.sql',
    import.meta.url), 'utf8'));
  await db.exec(`create trigger booking_capacity_guard before insert or update
    of adults,children,total_passengers,required_drivers
    on package_bookings for each row
    execute function validate_booking_schedule_and_capacity()`);
  await db.exec(readFileSync(new URL(
    '../migrations/20261009110000_municipal_complaints_and_restrictions.sql',
    import.meta.url), 'utf8'));
  await db.exec(readFileSync(new URL(
    '../migrations/20261009130000_driver_feedback_investigation_cases.sql',
    import.meta.url), 'utf8'));

  await db.query(`select set_config('test.uid','',false)`);
  await fails(`select submit_municipal_complaint($1,$2,'conduct',$3)`,
    [id(10),id(2),'Anonymous complaint must not be accepted.'],
    /REPORTER_ROLE_REQUIRED/);
  await uid(1);
  await fails(`select submit_municipal_complaint($1,$2,'conduct',$3)`,
    [id(10),id(5),'Unrelated driver complaint details'],
    /BOOKING_PARTICIPANT_REQUIRED/);
  const c1 = (await db.query(`select submit_municipal_complaint($1,$2,'conduct',$3)
    as id`,[id(10),id(2),'Driver conduct during the completed booking was unsafe.']))
    .rows[0].id;
  const evidencePath = `${c1}/incident.jpg`;
  assert.equal((await db.query(`select
    can_access_municipal_complaint_path($1,true) as allowed`,
    [evidencePath])).rows[0].allowed,true);
  await db.query(`insert into storage.objects values
    ('municipal-complaint-evidence',$1)`,[evidencePath]);
  await db.query(`select attach_municipal_complaint_evidence(
    $1,$2,'incident.jpg','image/jpeg')`,[c1,evidencePath]);
  await fails(`select submit_municipal_complaint($1,$2,'conduct',$3)`,
    [id(10),id(2),'Repeated report within one day.'],
    /RECENT_COMPLAINT_ALREADY_EXISTS/);
  assert.equal((await db.query(`select count(*)::integer as n from
    municipal_booking_restrictions`)).rows[0].n,0);
  await uid(2);
  const c2 = (await db.query(`select submit_municipal_complaint($1,$2,'service',$3)
    as id`,[id(10),id(1),'Tourist did not follow the agreed pickup schedule.']))
    .rows[0].id;
  await uid(4);
  assert.equal((await db.query(`select
    can_access_municipal_complaint_path($1,false) as allowed`,
    [evidencePath])).rows[0].allowed,false);
  assert.equal((await db.query(`select count(*)::integer as n from
    get_municipal_complaints()`)).rows[0].n,0);
  await fails(`select update_municipal_complaint($1,'investigate',$2)`,
    [c1,'Documented initial investigation'],/MTO_SCOPE_REQUIRED/);
  await uid(3);
  assert.equal((await db.query(`select
    can_access_municipal_complaint_path($1,false) as allowed`,
    [evidencePath])).rows[0].allowed,true);
  assert.equal((await db.query(`select count(*)::integer as n from
    get_municipal_complaints()`)).rows[0].n,2);
  await db.query(`select update_municipal_complaint($1,'investigate',$2)`,
    [c1,'Documented initial investigation']);
  await db.query(`select update_municipal_complaint($1,'warn',$2)`,
    [c1,'Formal warning after reviewing booking history.']);
  await fails(`select update_municipal_complaint($1,'warn',$2)`,
    [c1,'Duplicate formal warning request.'],/WARNING_ALREADY_ISSUED/);
  const restriction = (await db.query(`select impose_municipal_restriction(
    $1,$2,now()+interval '7 days',true) as id`,
    [c1,'Documented safety issue after municipal investigation.'])).rows[0].id;
  assert.equal((await db.query(`select municipal_restriction_active($1,
    'Baliwag','Bulacan') as active`,[id(2)])).rows[0].active,true);
  await fails(`insert into booking_drivers values($1,$2,'accepted')`,
    [id(11),id(2)],/MUNICIPAL_DRIVER_JOBS_RESTRICTED/);
  await db.query(`select update_municipal_complaint($1,'resolve',$2,$3)`,
    [c1,'Resolution after warning and temporary restriction.',
      'Booking history and witness notes supported the complaint.']);
  await uid(2);
  const appeal = (await db.query(`select appeal_municipal_restriction($1,$2)
    as id`,[restriction,'I request review of the restriction with new evidence.']))
    .rows[0].id;
  await uid(4);
  await fails(`select decide_municipal_restriction_appeal($1,true,$2)`,
    [appeal,'Grant after review'],/MTO_SCOPE_REQUIRED/);
  await uid(3);
  await db.query(`select decide_municipal_restriction_appeal($1,true,$2)`,
    [appeal,'New evidence supports lifting the restriction.']);
  assert.equal((await db.query(`select municipal_restriction_active($1,
    'Baliwag','Bulacan') as active`,[id(2)])).rows[0].active,false);
  await db.query(`insert into booking_drivers values($1,$2,'accepted')`,
    [id(11),id(2)]);
  assert.equal((await db.query(`select status from municipal_complaints
    where id=$1`,[c2])).rows[0].status,'submitted');
  await uid(4);
  await fails(`select open_municipal_driver_feedback_case($1,$2)`,
    [id(20),'Investigate verified low review for this driver.'],
    /MTO_SCOPE_REQUIRED/);
  await uid(3);
  const feedbackCase = (await db.query(`select
    open_municipal_driver_feedback_case($1,$2) as id`,
    [id(20),'Investigate verified low review for this driver.']))
    .rows[0].id;
  await fails(`select open_municipal_driver_feedback_case($1,$2)`,
    [id(20),'Duplicate investigation for the same review.'],
    /REVIEW_CASE_ALREADY_EXISTS/);
  await db.query(`select update_municipal_complaint($1,'investigate',$2)`,
    [feedbackCase,'Review booking history and tourist feedback.']);
  await db.query(`select update_municipal_complaint($1,'warn',$2)`,
    [feedbackCase,'Formal warning after verified feedback review.']);
  assert.equal((await db.query(`select count(*)::integer as n from
    municipal_complaint_events where complaint_id=$1 and
    action='warning_issued'`,[feedbackCase])).rows[0].n,1);
  await db.query(`select update_municipal_complaint($1,'investigate',$2)`,
    [c2,'Review the tourist conduct report and booking history.']);
  const touristRestriction = (await db.query(`select
    impose_municipal_restriction($1,$2,now()+interval '7 days',true) as id`,
    [c2,'Documented tourist conduct violation after investigation.']))
    .rows[0].id;
  await uid(1);
  await fails(`select create_package_booking($1::jsonb)`,
    [JSON.stringify({package_id:1,adults:2,children:0,
      total_passengers:2,required_drivers:1,selected_total_tricycles:1})],
    /MUNICIPAL_TOURIST_BOOKING_RESTRICTED/);
  await db.query(`update municipal_booking_restrictions
    set starts_at=now()-interval '8 days',
      ends_at=now()-interval '1 second' where id=$1`,[touristRestriction]);
  const afterExpiry = await db.query(`select create_package_booking($1::jsonb)`,
    [JSON.stringify({package_id:1,adults:2,children:0,
      total_passengers:2,required_drivers:1,selected_total_tricycles:1})]);
  assert.equal(afterExpiry.rows.length,1);
  console.log('PASS: scoped reports, feedback escalation, manual restrictions, expiry, appeal, and booking/job enforcement');
} finally { await db.close(); }
