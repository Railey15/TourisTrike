import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

export async function runTourUxCases({ db, check, failure, scalar, login, uuid }) {
  await login('');
  await db.exec(`
    alter table profiles add column city text, add column full_name text,
      add column first_name text, add column last_name text;
    alter table package_bookings add column adults integer default 1,
      add column children integer default 0, add column total_passengers integer default 1,
      add column package_id bigint, add column travel_date date,
      add column scheduled_start_at timestamptz, add column estimated_end_at timestamptz,
      add column booking_type text, add column pickup_address text, add column dropoff_address text,
      add column accepted_drivers_count integer default 0, add column created_at timestamptz default now();
    alter table package_activities add column created_at timestamptz default now();
    alter table booking_itinerary_items add column destination_address text,
      add column arrival_time timestamptz, add column departure_time timestamptz,
      add column order_number integer default 0, add column destination_order integer default 0,
      add column source_type text;
    create table tour_packages(id bigint primary key,title text,city text);
    create table driver_details(driver_id uuid,status text,approved_at timestamptz);
    create table driver_applications(driver_id uuid,status text,submitted_at timestamptz);
    create table notifications(user_id uuid,title text,body text,type text,is_read boolean);
    alter table notifications enable row level security;
    grant usage on schema public,auth to authenticated;
    grant select on profiles,subtenant_details to authenticated;
    grant insert(user_id,title,body,type,is_read) on notifications to authenticated;
  `);
  const policySource = readFileSync(new URL('../migrations/20260905000000_phase1_subtenant_scope_and_settings.sql', import.meta.url), 'utf8');
  const policyStart = policySource.indexOf('create policy notifications_insert_staff');
  await db.exec(policySource.slice(policyStart, policySource.indexOf(';', policyStart) + 1));
  const tourist = uuid(700), driver = uuid(701), driver2 = uuid(702), outsider = uuid(703);
  await db.query(`insert into profiles(id,role,city,province,full_name) values
    ($1,'tourist','Alpha','Bulacan','Juan Dela Cruz'),
    ($2,'driver','Alpha','Bulacan','Driver One'),($3,'driver','Alpha','Bulacan','Driver Two'),
    ($4,'driver','Other','Bulacan','Outsider')`, [tourist,driver,driver2,outsider]);
  await db.query(`insert into driver_details values($1,'approved',now()),($2,'approved',now()),($3,'approved',now())`, [driver,driver2,outsider]);
  await db.exec("insert into tour_packages values(1,'Saved Package','Alpha')");
  let serial = 720;
  const seed = async (drivers = [driver]) => {
    const bid=uuid(serial++), receipt=uuid(serial++);
    await login('');
    await db.query(`insert into package_bookings(id,tourist_id,municipality,province,status,booking_status,
      total_amount,downpayment_amount,remaining_balance,required_drivers,total_passengers,adults,package_id,
      pickup_address,dropoff_address,travel_date,scheduled_start_at,estimated_end_at)
      values($1,$2,'Alpha','Bulacan','ongoing','on_tour',100,50,50,$3,$3,$3,1,
      'SM City Baliwag, Baliwag, Bulacan','Bustos Municipal Hall, Bustos, Bulacan','2026-09-30',
      '2026-09-30 09:00+08','2026-09-30 11:00+08')`, [bid,tourist,drivers.length]);
    for (const d of drivers) await db.query('insert into booking_drivers(id,booking_id,driver_id,status) values($1,$2,$3,\'accepted\')',[uuid(serial++),bid,d]);
    await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,
      estimated_stay_duration_minutes,spot_status,actual_departure_time)
      values($1,$2,'Booked stop',60,'completed',now())`,[uuid(serial++),bid]);
    await db.exec('alter table payment_records disable trigger trg_validate_booking_payment_submission');
    await db.query(`insert into payment_records(id,booking_id,payment_stage,status,amount,payer_id,payee_id)
      values($1,$2,'down_payment','confirmed',50,$3,$4)`,[receipt,bid,tourist,driver]);
    await db.exec('alter table payment_records enable trigger trg_validate_booking_payment_submission');
    await db.query('select ensure_booking_payment_requirements($1)',[bid]);
    await db.query(`update booking_payment_requirements set status='satisfied',satisfied_by_payment_record_id=$2
      where booking_id=$1 and payment_stage='down_payment'`,[bid,receipt]);
    return bid;
  };
  const prepare = async bid => { await login(tourist); return scalar('select to_jsonb(prepare_group_cash_remaining_balance($1,$2))',[bid,'ux-cash-fixture-'+bid]); };
  const confirm = async (id, who=driver) => { await login(who); return scalar('select to_jsonb(confirm_group_cash_share($1))',[id]); };
  const debt = async bid => Number(await scalar('select remaining_balance from package_bookings where id=$1',[bid]));

  // Reproduce the original Driver UI sequence using real RPC and staff INSERT RLS.
  const original=await seed(), oldPayment=await prepare(original);
  await confirm(oldPayment.id);
  check(await debt(original),0,'original cash RPC succeeds before notification insert');
  await db.exec('set role authenticated');
  try {
    await assert.rejects(() => db.query(`insert into notifications(user_id,title,body,type,is_read)
      values($1,'Cash received','Received','cash_payment_confirmed',false)`,[tourist]), error => {
      check(error.code,'42501','original error SQLSTATE');
      check(error.message,'new row violates row-level security policy for table "notifications"','original cash UI failure reproduced');
      console.log('REPRODUCED: 42501 — notification INSERT denied after successful cash RPC');
      return true;
    });
  } finally { await db.exec('reset role'); }
  check(await debt(original),0,'notification failure does not undo committed cash');
  await db.query("update package_bookings set booking_status='completed' where id=$1",[original]);
  await failure('select confirm_group_cash_share($1)',[oldPayment.id],'BOOKING_NOT_ACTIVE');

  await db.exec(readFileSync(new URL('../migration_hold/20261001070000_tour_assignment_reputation_and_cash_ux.sql',import.meta.url),'utf8'));
  await db.exec(readFileSync(new URL('../migrations/20260930010000_repair_tour_assignment_migration.sql',import.meta.url),'utf8'));
  const before=await scalar('select to_jsonb(p) from payment_records p where id=$1',[oldPayment.id]);
  check((await confirm(oldPayment.id)).status,'confirmed','authorized completed-booking retry succeeds');
  check(await scalar('select to_jsonb(p) from payment_records p where id=$1',[oldPayment.id]),before,'retry preserves receipt history');
  await login(outsider);
  await failure('select confirm_group_cash_share($1)',[oldPayment.id],'NOT_ASSIGNED_PAYMENT_DRIVER');

  const convoy=await seed([driver,driver2]), cash=await prepare(convoy);
  await confirm(cash.id);
  check(await debt(convoy),50,'first convoy confirmation keeps payment gate locked');
  check((await confirm(cash.id)).status,'pending_confirmation','repeated first confirmation is idempotent');
  await confirm(cash.id,driver2);
  check(await debt(convoy),0,'all shares confirmed clears authoritative debt');
  check(Number(await scalar('select sum(gross_amount) from payment_allocations where payment_record_id=$1',[cash.id])),50,'allocations sum to exact submitted obligation');
  check(Number(await scalar('select count(*) from payment_allocations where payment_record_id=$1',[cash.id])),2,'no duplicate convoy allocations');
  check(await scalar('select is_booking_remaining_payment_satisfied($1)',[convoy]),true,'drop-off payment gate unlocks after settlement');
  await confirm(cash.id,driver2);
  check(await debt(convoy),0,'repeated final confirmation never makes balance negative');

  const stale=await seed(), staleCash=await prepare(stale);
  await db.query('update package_bookings set remaining_balance=70 where id=$1',[stale]);
  await login(driver);
  await failure('select confirm_group_cash_share($1)',[staleCash.id],'CASH_PAYMENT_STATE_CHANGED');
  check(await scalar('select status from payment_allocations where payment_record_id=$1',[staleCash.id]),'awaiting_cash','stale attempt preserves unconfirmed allocation');
  check(await debt(stale),70,'stale amount cannot settle changed balance');
  await db.query("update package_bookings set booking_status='cancelled' where id=$1",[stale]);
  await failure('select confirm_group_cash_share($1)',[staleCash.id],'BOOKING_NOT_ACTIVE');

  const pending=await seed();
  await db.query('insert into package_activities(id,booking_id) values($1,$2)',[uuid(serial++),pending]);
  await db.query('delete from booking_drivers where booking_id=$1',[pending]);
  await db.query("update package_bookings set booking_status='pending' where id=$1",[pending]);
  await login(driver);
  const assignments=await db.query('select get_available_tour_assignments(30) as assignment');
  const assignment=assignments.rows.find(r=>r.assignment.booking_id===pending).assignment;
  check(assignment.package_bookings.pickup_address,'SM City Baliwag, Baliwag, Bulacan','pre-acceptance exact pickup');
  check(assignment.package_bookings.dropoff_address,'Bustos Municipal Hall, Bustos, Bulacan','pre-acceptance exact drop-off');
  check(assignment.itinerary_items.length,1,'pre-acceptance saved itinerary');
  let reputation=await scalar('select get_booking_tourist_reputation($1)',[pending]);
  check(reputation.display_name,'Juan Dela Cruz','minimal tourist display name');
  check(reputation.total_reviews,0,'no fabricated review count');
  check(reputation.average_rating,null,'unrated tourist has no negative zero rating');
  await db.query(`insert into tourist_reviews(booking_id,driver_id,tourist_id,rating,review_text)
    values($1,$2,$3,5,'Helpful'),($4,$5,$3,3,null)`,[original,driver,tourist,convoy,driver2]);
  reputation=await scalar('select get_booking_tourist_reputation($1)',[pending]);
  check(Number(reputation.average_rating),4,'average from existing Driver-to-Tourist reviews');
  check(reputation.total_reviews,2,'count from existing review table');
  check(reputation.distribution['5'],1,'rating distribution');
  check(reputation.reviews.length,2,'recent reviews only');
  check(Object.keys(reputation.reviews[0]).sort(),['created_at','rating','review_text'],'no private Driver identity');
  check(Object.keys(reputation).sort(),['average_rating','display_name','distribution','reviews','total_reviews'],'no tourist contacts or profile data');
  await login(outsider);
  check((await db.query('select get_available_tour_assignments(30)')).rows.length,0,'out-of-area assignments hidden');
  await failure('select get_booking_tourist_reputation($1)',[pending],'BOOKING_ACCESS_DENIED');
  await login(tourist);
  await failure('select get_booking_tourist_reputation($1)',[pending],'DRIVER_ROLE_REQUIRED');
  await login(driver);
  await db.query("update driver_details set status='suspended' where driver_id=$1",[driver]);
  await failure('select get_booking_tourist_reputation($1)',[pending],'BOOKING_ACCESS_DENIED');
  await db.query("update driver_details set status='approved' where driver_id=$1",[driver]);
  await db.query("insert into booking_drivers(id,booking_id,driver_id,status) values($1,$2,$3,'accepted')",[uuid(serial++),pending,driver2]);
  await failure('select get_booking_tourist_reputation($1)',[pending],'BOOKING_ACCESS_DENIED');
  await login(driver2);
  check((await scalar('select get_booking_tourist_reputation($1)',[pending])).total_reviews,2,'participating driver retains reputation access');

  await login('');
  await failure('update package_bookings set required_drivers=2 where id=$1',[pending],'SINGLE_PASSENGER_ONE_TRICYCLE_REQUIRED');
  await failure('update package_bookings set required_drivers=2,total_passengers=2 where id=$1',[pending],'SINGLE_PASSENGER_ONE_TRICYCLE_REQUIRED');
  await db.query('update package_bookings set total_passengers=2,adults=2,required_drivers=2 where id=$1',[pending]);
  check(Number(await scalar('select required_drivers from package_bookings where id=$1',[pending])),2,'two passengers keep existing multi-tricycle behavior');
  await failure('update package_bookings set total_passengers=1,adults=1 where id=$1',[pending],'SINGLE_PASSENGER_ONE_TRICYCLE_REQUIRED');
  await db.query('update package_bookings set total_passengers=1,adults=1,required_drivers=1 where id=$1',[pending]);
  check(Number(await scalar('select required_drivers from package_bookings where id=$1',[pending])),1,'safe single-passenger normalization persists');
}
