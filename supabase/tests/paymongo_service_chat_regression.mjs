// Isolated SQL regression: a verified provider event has no auth.uid(), but
// its payment requirement trigger still needs to write a booking system message.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const tourist = id(1), outsider = id(2), driver = id(3), booking = id(4);
const migration = readFileSync(
  new URL('../migrations/20261007030000_allow_provider_payment_system_chat.sql', import.meta.url),
  'utf8',
).replaceAll('\r\n', '\n');
const start = migration.indexOf('create or replace function public.ensure_booking_group_conversation(');
const end = migration.indexOf('$$;', start);
assert(start >= 0 && end > start);

try {
  await db.exec(`
    create schema auth;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('test.uid',true),'')::uuid $$;
    create function auth.role() returns text language sql stable as $$
      select nullif(current_setting('test.role',true),'') $$;
    create table public.tour_packages(id uuid primary key,title text);
    create table public.profiles(id uuid primary key,full_name text,first_name text,last_name text);
    create table public.package_bookings(id uuid primary key,package_id uuid,tourist_id uuid);
    create table public.conversations(id uuid primary key default gen_random_uuid(),
      tourist_id uuid,driver_id uuid,booking_id uuid,conversation_type text,title text);
    create unique index booking_group_unique on public.conversations(booking_id)
      where conversation_type='booking_group' and booking_id is not null;
    create table public.conversation_members(conversation_id uuid,user_id uuid,
      member_role text,unique(conversation_id,user_id));
    create table public.booking_drivers(booking_id uuid,driver_id uuid,status text);
    create function public.is_package_booking_participant(p_booking_id uuid)
      returns boolean language sql stable as $$
      select exists(select 1 from public.package_bookings
        where id=p_booking_id and tourist_id=auth.uid()) $$;
  `);
  await db.exec(migration.slice(start, end + 3));
  await db.query('insert into tour_packages values($1,$2)',[id(5),'Test Tour']);
  await db.query('insert into profiles values($1,$2,null,null)',[tourist,'Test Tourist']);
  await db.query('insert into package_bookings values($1,$2,$3)',[booking,id(5),tourist]);
  await db.query('insert into booking_drivers values($1,$2,$3)',[booking,driver,'accepted']);

  await db.query("select set_config('test.role','anon',false),set_config('test.uid','',false)");
  await assert.rejects(
    () => db.query('select ensure_booking_group_conversation($1)',[booking]),
    /UNAUTHENTICATED/,
  );
  await db.query("select set_config('test.role','authenticated',false),set_config('test.uid',$1,false)",[outsider]);
  await assert.rejects(
    () => db.query('select ensure_booking_group_conversation($1)',[booking]),
    /NOT_BOOKING_PARTICIPANT/,
  );
  await db.query("select set_config('test.uid',$1,false)",[tourist]);
  const touristConversation = (await db.query(
    'select ensure_booking_group_conversation($1) as id',[booking],
  )).rows[0].id;
  await db.query("select set_config('test.role','service_role',false),set_config('test.uid','',false)");
  const providerConversation = (await db.query(
    'select ensure_booking_group_conversation($1) as id',[booking],
  )).rows[0].id;
  assert.equal(providerConversation,touristConversation);
  assert.equal((await db.query(
    'select count(*)::int as count from conversation_members where conversation_id=$1',
    [providerConversation],
  )).rows[0].count,2);
  console.log('PASS: provider payment system chat permits service role; client access stays scoped');
} finally {
  await db.close();
}
