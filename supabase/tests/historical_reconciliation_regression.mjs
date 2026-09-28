import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const migration = await readFile(new URL('../migrations/20260927230000_historical_schema_reconciliation.sql', import.meta.url), 'utf8');
const uuid = n => `10000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [touristA, touristB, stranger, driverA, driverB, convoy, subtenantA, subtenantB,
  mainTenant, administrator, reviewer, reviewDriver, chatTourist, chatDriver,
  rideTourist, rideDriver, noProvince] = Array.from({length:17}, (_,i) => uuid(i+1));
const bookingA=uuid(101), bookingB=uuid(102), historyBooking=uuid(103);
const itemA=uuid(201), itemB=uuid(202), group=uuid(301), direct=uuid(302);
let checks=0;
async function check(name, fn) { try { await fn(); checks++; } catch(error) { error.message = name+': '+error.message; throw error; } }

await db.exec(`
  create role authenticated; create role anon; create role service_role; create schema auth;
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
  create function auth.role() returns text language sql stable as $$select current_setting('role',true)$$;
  create table public.profiles (
    id uuid primary key,role text not null check(role in ('tourist','driver','subtenant','main_tenant','administrator')),
    full_name text default 'Fixture Name',first_name text default 'Fixture',last_name text default 'Name',
    avatar_url text,profile_image_url text,average_rating numeric default 4,total_reviews integer default 2,
    mobile text default 'private-phone',city text,province text,address text default 'private-address',
    birthdate date default '1990-01-01',middle_name text,barangay text,postal_code text,
    driver_status text default 'pending',is_approved boolean default false,is_verified boolean default false,
    verification_status text default 'pending'
  );
  create table public.subtenant_details(id uuid primary key,city text,province text,is_active boolean);
  create table public.driver_details(driver_id uuid primary key,status text default 'pending',approved_by uuid,approved_at timestamptz,mobile text);
  create table public.driver_applications(id uuid primary key,driver_id uuid,status text default 'pending',reviewed_by uuid,reviewed_at timestamptz,city text);
  create table public.tour_packages(id bigint primary key,city text);
  create table public.package_bookings(id uuid primary key,package_id bigint,tourist_id uuid,
    assigned_driver_id uuid,booking_status text,status text,province text);
  create table public.booking_drivers(booking_id uuid,driver_id uuid,status text);
  create table public.package_activities(booking_id uuid,driver_id uuid);
  create table public.booking_itinerary_items(id uuid primary key,booking_id uuid,tourist_id uuid);
  create table public.rides(id uuid primary key,tourist_id uuid,driver_id uuid,status text);
  create table public.driver_reviews(booking_id uuid,driver_id uuid,tourist_id uuid);
  create table public.ride_reviews(ride_id uuid,driver_id uuid,tourist_id uuid);
  create table public.conversations(id uuid primary key,tourist_id uuid,driver_id uuid,booking_id uuid,
    conversation_type text default 'direct',last_message text);
  create table public.conversation_members(conversation_id uuid,user_id uuid);
  create function public.cities_match(text,text) returns boolean language sql immutable as $$
    select nullif(lower(trim($1)),'')=nullif(lower(trim($2)),'') $$;
  create function public.current_app_role() returns text language sql stable security definer as $$
    select role from public.profiles where id=auth.uid() $$;
  create function public.is_main_tenant() returns boolean language sql stable security definer as $$
    select coalesce(public.current_app_role()='main_tenant',false) $$;
  create function public.subtenant_can_access_booking(uuid) returns boolean language sql stable security definer as $$
    select exists(select 1 from public.subtenant_details s join public.profiles actor on actor.id=s.id and actor.role='subtenant'
      join public.tour_packages t on public.cities_match(t.city,s.city) join public.package_bookings b on b.package_id=t.id
      where s.id=auth.uid() and s.is_active and b.id=$1) $$;
  insert into public.profiles(id,role,city,province) values
    ('${touristA}','tourist','Elsewhere','Visitor Province'),('${touristB}','tourist','City B','Bulacan'),
    ('${stranger}','tourist','City A','Bulacan'),('${driverA}','driver','City A','Bulacan'),
    ('${driverB}','driver','City B','Bulacan'),('${convoy}','driver','City A','Bulacan'),
    ('${subtenantA}','subtenant','City A','Bulacan'),('${subtenantB}','subtenant','City B','Bulacan'),
    ('${mainTenant}','main_tenant',null,'Bulacan'),('${administrator}','administrator',null,'Bulacan'),
    ('${reviewer}','tourist','Elsewhere','Visitor Province'),('${reviewDriver}','driver','City A','Bulacan'),
    ('${chatTourist}','tourist','Elsewhere','Visitor Province'),('${chatDriver}','driver','City A','Visitor Province'),
    ('${rideTourist}','tourist','Elsewhere','Visitor Province'),('${rideDriver}','driver','City A','Bulacan'),
    ('${noProvince}','main_tenant',null,null);
  insert into public.subtenant_details values ('${subtenantA}','City A','Bulacan',true),('${subtenantB}','City B','Bulacan',true);
  insert into public.tour_packages values (1,'City A'),(2,'City B');
  insert into public.package_bookings values
    ('${bookingA}',1,'${touristA}','${driverA}','accepted','accepted','Bulacan'),
    ('${bookingB}',2,'${touristB}','${driverB}','accepted','accepted','Bulacan'),
    ('${historyBooking}',1,'${reviewer}','${reviewDriver}','completed','completed','Bulacan');
  insert into public.booking_drivers values ('${bookingA}','${driverA}','accepted'),('${bookingA}','${convoy}','accepted'),
    ('${bookingB}','${driverB}','accepted'),('${historyBooking}','${reviewDriver}','completed');
  insert into public.booking_itinerary_items values ('${itemA}','${bookingA}','${touristA}'),('${itemB}','${bookingB}','${touristB}');
  insert into public.driver_reviews values ('${historyBooking}','${reviewDriver}','${reviewer}');
  insert into public.conversations values ('${group}',null,null,null,'booking_group','legacy'),
    ('${direct}','${chatTourist}','${chatDriver}',null,'direct','legacy');
  insert into public.conversation_members values ('${group}','${chatTourist}'),('${group}','${chatDriver}'),
    ('${group}','${subtenantA}'),('${group}','${mainTenant}');
  insert into public.rides values ('${uuid(401)}','${rideTourist}','${rideDriver}','ongoing'),('${uuid(402)}','${stranger}',null,'searching');
  alter table public.profiles enable row level security;
  alter table public.booking_itinerary_items enable row level security;
  alter table public.conversations enable row level security;
  alter table public.conversation_members enable row level security;
  create policy profiles_select_authenticated on public.profiles for select to authenticated using(true);
  create policy profiles_insert_own on public.profiles for insert to authenticated with check(id=auth.uid());
  create policy conversations_members_only on public.conversations for all to authenticated
    using(auth.uid() in (tourist_id,driver_id)) with check(auth.uid() in (tourist_id,driver_id));
  grant usage on schema public,auth to authenticated,anon;
  grant select on public.package_bookings,public.booking_drivers,public.package_activities to authenticated;
  grant all on public.profiles to authenticated,anon;
  grant select,insert,update on public.driver_details,public.driver_applications to authenticated;
  grant update on public.profiles to authenticated;
  create policy profiles_update_own on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
  grant select(address) on public.profiles to anon;
  grant select,insert,update,delete on public.booking_itinerary_items,public.conversations to authenticated;
  grant execute on all functions in schema auth,public to authenticated,anon;
`);
await db.exec(migration);
await db.exec(migration); // Reapplying must preserve scope and private helper grants.
async function asUser(actor, sql, params=[], role='authenticated') {
  await db.exec('begin');
  try {
    await db.query("select set_config('request.jwt.claim.sub',$1,true)",[actor??'']);
    await db.exec(`set local role ${role}`);
    return await db.query(sql,params);
  } finally { await db.exec('rollback'); }
}
const full=(actor,targets)=>asUser(actor,'select * from public.profiles where id=any($1::uuid[])',[targets]);
const basic=(actor,targets)=>asUser(actor,'select * from public.get_participant_profiles($1::uuid[])',[targets]);
const ids=result=>result.rows.map(row=>row.id).sort();
const safeKeys=row=>assert.deepEqual(Object.keys(row).sort(),['id','role','full_name','first_name','last_name','avatar_url','profile_image_url','average_rating','total_reviews','mobile'].sort());

await check('Tourist own private data',async()=>assert.equal((await full(touristA,[touristA])).rows[0].address,'private-address'));
await check('Driver own private data',async()=>assert.equal((await full(driverA,[driverA])).rows[0].birthdate.toISOString().slice(0,10),'1990-01-01'));
for(const [name,actor,target] of [['assigned Driver',touristA,driverA],['assigned Tourist',driverA,touristA]]) {
  await check(name+' limited identity/contact',async()=>{const row=(await basic(actor,[target])).rows[0];safeKeys(row);assert.equal(row.mobile,'private-phone');});
  await check(name+' private full row denied',async()=>assert.equal((await full(actor,[target])).rows.length,0));
}
for(const [name,actor,targets] of [['unrelated Tourist',stranger,[touristB,driverB]],['unrelated Driver',driverA,[touristB,driverB]]]) {
  await check(name+' table denial',async()=>assert.equal((await full(actor,targets)).rows.length,0));
  await check(name+' RPC denial',async()=>assert.equal((await basic(actor,targets)).rows.length,0));
}
await check('Tourist cannot enumerate Drivers',async()=>assert.equal((await asUser(touristA,"select id from public.profiles where role='driver'")).rows.length,0));
await check('Driver cannot enumerate Tourists',async()=>assert.equal((await asUser(driverA,"select id from public.profiles where role='tourist'")).rows.length,0));
await check('Subtenant local Driver verification',async()=>assert.equal((await full(subtenantA,[driverA])).rows[0].driver_status,'pending'));
await check('Subtenant foreign municipality table denial',async()=>assert.equal((await full(subtenantA,[driverB,touristB])).rows.length,0));
await check('Subtenant foreign municipality RPC denial',async()=>assert.equal((await basic(subtenantA,[driverB,touristB])).rows.length,0));
await check('Subtenant cannot browse unassigned local Tourist',async()=>assert.equal((await full(subtenantA,[stranger])).rows.length,0));
await check('Subtenant visiting booked Tourist limited identity',async()=>{assert.equal((await full(subtenantA,[touristA])).rows.length,0);safeKeys((await basic(subtenantA,[touristA])).rows[0]);});
await check('Main Tenant provincial full records',async()=>assert.deepEqual(ids(await full(mainTenant,[driverA,driverB])),[driverA,driverB].sort()));
await check('Main Tenant foreign/Administrator full records denied',async()=>assert.equal((await full(mainTenant,[touristA,administrator,chatDriver])).rows.length,0));
await check('Main Tenant visitor identity for provincial booking',async()=>safeKeys((await basic(mainTenant,[touristA])).rows[0]));
await check('Missing province fails closed',async()=>assert.equal((await full(noProvince,[driverA])).rows.length,0));
await check('Administrator oversight has no operational contact',async()=>{assert.equal((await full(administrator,[touristA,driverA])).rows.length,0);const row=(await basic(administrator,[touristA])).rows[0];safeKeys(row);assert.equal(row.mobile,null);});
for(const sql of ['select * from public.profiles','select address from public.profiles','select * from public.get_participant_profiles(null)'])
  await check('Anonymous denied: '+sql,async()=>assert.rejects(()=>asUser(null,sql,[],'anon'),/permission denied/));
await check('Private identity helper is not callable',async()=>assert.rejects(()=>asUser(touristA,'select public.profile_identity_access_level($1)',[driverA]),/permission denied/));
await check('Trusted group messaging identity masked contact',async()=>{const row=(await basic(chatTourist,[chatDriver])).rows[0];safeKeys(row);assert.equal(row.mobile,null);});
await check('Legacy direct messaging identity masked contact',async()=>assert.equal((await basic(chatDriver,[chatTourist])).rows[0].mobile,null));
await check('Subtenant same-city foreign-province profile denied despite group membership',async()=>{
  assert.equal((await full(subtenantA,[chatDriver])).rows.length,0);
  assert.equal((await basic(subtenantA,[chatDriver])).rows.length,0);
});
await check('Main Tenant foreign-province group membership grants no operational identity',async()=>assert.equal((await basic(mainTenant,[chatDriver])).rows.length,0));
await check('Historical review counterpart identity masked contact',async()=>{const row=(await basic(reviewDriver,[reviewer])).rows[0];safeKeys(row);assert.equal(row.mobile,null);});
await check('Subtenant review author identity',async()=>assert.equal((await basic(subtenantA,[reviewer])).rows[0].mobile,null));
await check('Convoy participant identity',async()=>assert.equal((await basic(convoy,[driverA,touristA])).rows.length,2));
await check('Assigned ride contact/emergency identity',async()=>assert.equal((await basic(rideDriver,[rideTourist])).rows[0].mobile,'private-phone'));
await check('Searching ride grants no identity',async()=>assert.equal((await basic(rideDriver,[stranger])).rows.length,0));
await check('Forged conversation cannot grant profile access',async()=>assert.rejects(()=>asUser(stranger,'insert into public.conversations(id,tourist_id,driver_id) values($1,$2,$3)',[uuid(303),stranger,driverA]),/CONVERSATION_ASSIGNMENT_REQUIRED/));
await check('Conversation target cannot be repointed',async()=>assert.rejects(()=>asUser(chatTourist,'update public.conversations set driver_id=$1 where id=$2',[driverA,direct]),/CONVERSATION_PARTICIPANTS_ARE_READ_ONLY/));
await check('Valid assignment conversation creation',async()=>assert.equal((await asUser(touristA,'insert into public.conversations(id,tourist_id,driver_id,booking_id) values($1,$2,$3,$4) returning id',[uuid(304),touristA,driverA,bookingA])).rows.length,1));
await check('Legacy messaging updates preserved',async()=>assert.equal((await asUser(chatTourist,'update public.conversations set last_message=$1 where id=$2 returning id',['new',direct])).rows.length,1));
await check('Driver itinerary assigned read only',async()=>assert.deepEqual(ids(await asUser(driverA,'select id from public.booking_itinerary_items')),[itemA]));
await check('Driver unrelated itinerary update denied',async()=>assert.equal((await asUser(driverA,'update public.booking_itinerary_items set tourist_id=$1 where id=$2 returning id',[touristA,itemB])).rows.length,0));
await check('Tourist own itinerary insert',async()=>assert.equal((await asUser(touristA,'insert into public.booking_itinerary_items values($1,$2,$3) returning id',[uuid(203),bookingA,touristA])).rows.length,1));
await check('Tourist foreign itinerary insert denied',async()=>assert.rejects(()=>asUser(touristA,'insert into public.booking_itinerary_items values($1,$2,$3)',[uuid(204),bookingB,touristA]),/row-level security/));
await check('Privileged self profile insertion denied',async()=>assert.rejects(()=>asUser(uuid(501),"insert into public.profiles(id,role) values($1,'administrator')",[uuid(501)]),/row-level security/));
await check('Tourist self profile insertion',async()=>assert.equal((await asUser(uuid(501),"insert into public.profiles(id,role) values($1,'tourist') returning id",[uuid(501)])).rows.length,1));
await check('Profile TRUNCATE privilege revoked',async()=>assert.equal((await db.query("select has_table_privilege('authenticated','public.profiles','TRUNCATE') as allowed")).rows[0].allowed,false));
await check('Lookup size limit enforced',async()=>assert.rejects(()=>basic(touristA,Array(201).fill(driverA)),/PROFILE_LOOKUP_LIMIT/));
await check('New definer functions pin empty search_path',async()=>{const result=await db.query("select proconfig from pg_proc where proname in ('profile_operational_access','profile_identity_access_level','get_participant_profiles','guard_conversation_profile_identity')");assert.equal(result.rows.length,4);for(const row of result.rows)assert.ok(row.proconfig.includes('search_path=""'));});
// Deployment gates requested after the readiness checkpoint. Keep their
// results separate so a failure cannot be hidden by the original 48 checks.
const deploymentFailures=[];
let deploymentChecks=0;
async function deploymentGate(name, fn) {
  try { await fn(); deploymentChecks++; }
  catch(error) { deploymentFailures.push({name, detail:error.message}); }
}
for(const role of ['main_tenant','subtenant']) {
  await deploymentGate(role+' self profile insertion denied',async()=>assert.rejects(
    ()=>asUser(uuid(501),'insert into public.profiles(id,role) values($1,$2)',[uuid(501),role]),
    /row-level security/));
}
await deploymentGate('Profile insertion for another user denied',async()=>assert.rejects(
  ()=>asUser(uuid(501),"insert into public.profiles(id,role) values($1,'tourist')",[uuid(502)]),
  /row-level security/));
await deploymentGate('Legitimate Driver self provisioning remains pending',async()=>{
  const row=(await asUser(uuid(501),"insert into public.profiles(id,role) values($1,'driver') returning *",[uuid(501)])).rows[0];
  assert.equal(row.driver_status,'pending');assert.equal(row.verification_status,'pending');assert.equal(row.is_approved,false);assert.equal(row.is_verified,false);
});
for(const [field,value] of [['is_approved','true'],['is_verified','true'],['driver_status',"'approved'"],['verification_status',"'verified'"]]) {
  await deploymentGate('Profile self approval INSERT denied: '+field,async()=>assert.rejects(
    ()=>asUser(uuid(501),`insert into public.profiles(id,role,${field}) values($1,'driver',${value})`,[uuid(501)]),/APPROVAL_STATE_IS_STAFF_MANAGED/));
  await deploymentGate('Profile self approval UPDATE denied: '+field,async()=>assert.rejects(
    ()=>asUser(driverA,`update public.profiles set ${field}=${value} where id=$1`,[driverA]),/APPROVAL_STATE_IS_STAFF_MANAGED/));
}
for(const [table,fields,values] of [
  ['driver_details','status',"'approved'"],['driver_details','approved_at','now()'],['driver_details','approved_by',`'${subtenantA}'`],
  ['driver_applications','status',"'approved'"],['driver_applications','reviewed_at','now()'],['driver_applications','reviewed_by',`'${subtenantA}'`]
]) await deploymentGate('Driver accreditation INSERT injection denied: '+table+'.'+fields,async()=>assert.rejects(
  ()=>asUser(driverA,`insert into public.${table}(${table==='driver_details'?'driver_id':'id,driver_id'},${fields}) values(${table==='driver_details'?'$1':'$2,$1'},${values})`,table==='driver_details'?[driverA]:[driverA,uuid(601)]),/APPROVAL_STATE_IS_STAFF_MANAGED/));
await deploymentGate('Driver details legitimate onboarding',async()=>assert.equal(
  (await asUser(driverA,'insert into public.driver_details(driver_id,mobile) values($1,$2) returning status',[driverA,'onboarding-phone'])).rows[0].status,'pending'));
await db.query('insert into public.driver_details(driver_id) values($1)',[driverA]);
await db.query('insert into public.driver_applications(id,driver_id,city) values($1,$2,$3)',[uuid(601),driverA,'City A']);
for(const table of ['driver_details','driver_applications']) await deploymentGate('Driver accreditation UPDATE injection denied: '+table,async()=>assert.rejects(
  ()=>asUser(driverA,`update public.${table} set status='approved' where driver_id=$1`,[driverA]),/APPROVAL_STATE_IS_STAFF_MANAGED/));
await deploymentGate('Main Tenant provincial itinerary allowed',async()=>assert.equal(
  (await asUser(mainTenant,'select id from public.booking_itinerary_items where id=$1',[itemA])).rows.length,1));
await deploymentGate('Main Tenant without province itinerary denied',async()=>assert.equal(
  (await asUser(noProvince,'select id from public.booking_itinerary_items')).rows.length,0));
await deploymentGate('Subtenant foreign municipality itinerary denied',async()=>assert.equal(
  (await asUser(subtenantA,'select id from public.booking_itinerary_items where id=$1',[itemB])).rows.length,0));
await deploymentGate('Subtenant own municipal/provincial itinerary allowed',async()=>assert.equal(
  (await asUser(subtenantA,'select id from public.booking_itinerary_items where id=$1',[itemA])).rows.length,1));
for(const province of ['   ','#INVALID#']) {
  await db.query('update public.profiles set province=$1 where id=$2',[province,noProvince]);
  await deploymentGate('Main Tenant invalid authoritative province denied: '+JSON.stringify(province),async()=>assert.equal(
    (await asUser(noProvince,'select id from public.booking_itinerary_items')).rows.length,0));
}
await db.query('update public.subtenant_details set city=null where id=$1',[subtenantB]);
await deploymentGate('Subtenant missing assignment itinerary denied',async()=>assert.equal(
  (await asUser(subtenantB,'select id from public.booking_itinerary_items')).rows.length,0));
await deploymentGate('Tourist own itinerary access',async()=>assert.equal(
  (await asUser(touristA,'select id from public.booking_itinerary_items where id=$1',[itemA])).rows.length,1));
await deploymentGate('Unrelated Tourist itinerary denied',async()=>assert.equal(
  (await asUser(stranger,'select id from public.booking_itinerary_items')).rows.length,0));
await deploymentGate('Unrelated Driver itinerary denied',async()=>assert.equal(
  (await asUser(rideDriver,'select id from public.booking_itinerary_items')).rows.length,0));
for(const actor of [mainTenant,subtenantA]) {
  await deploymentGate('Staff have no new itinerary UPDATE right: '+actor,async()=>assert.equal(
    (await asUser(actor,'update public.booking_itinerary_items set tourist_id=tourist_id where id=$1 returning id',[itemA])).rows.length,0));
  await deploymentGate('Staff have no new itinerary DELETE right: '+actor,async()=>assert.equal(
    (await asUser(actor,'delete from public.booking_itinerary_items where id=$1 returning id',[itemA])).rows.length,0));
  await deploymentGate('Staff have no new itinerary INSERT right: '+actor,async()=>assert.rejects(
    ()=>asUser(actor,'insert into public.booking_itinerary_items values($1,$2,$3)',[uuid(205),bookingA,touristA]),/row-level security/));
}
await deploymentGate('Tourist initialization RPC',async()=>assert.equal(
  (await asUser(touristA,'select public.ensure_booking_itinerary($1) as count',[bookingA])).rows[0].count,1));
await deploymentGate('Driver initialization RPC',async()=>assert.equal(
  (await asUser(driverA,'select public.ensure_booking_itinerary($1) as count',[bookingA])).rows[0].count,1));
for(const actor of [stranger,rideDriver,mainTenant,subtenantA]) await deploymentGate('Unrelated/staff initialization RPC denied: '+actor,async()=>assert.rejects(
  ()=>asUser(actor,'select public.ensure_booking_itinerary($1)',[bookingA]),/ITINERARY_PARTICIPATION_REQUIRED/));
// Same city name in another province must not expand an office's scope.
await db.query('update public.package_bookings set province=$1 where id=$2',['Other Province',bookingA]);
await deploymentGate('Main Tenant foreign province itinerary denied',async()=>assert.equal(
  (await asUser(mainTenant,'select id from public.booking_itinerary_items where id=$1',[itemA])).rows.length,0));
await deploymentGate('Subtenant same city foreign province itinerary denied',async()=>assert.equal(
  (await asUser(subtenantA,'select id from public.booking_itinerary_items where id=$1',[itemA])).rows.length,0));
await db.close();
console.log(`PASS: ${checks} historical profile/itinerary authorization checks`);
console.log(`Deployment gates: ${deploymentChecks} PASS, ${deploymentFailures.length} FAIL`);
for(const failure of deploymentFailures) console.error(`FAIL: ${failure.name}: ${failure.detail}`);
if(deploymentFailures.length) process.exitCode=1;
