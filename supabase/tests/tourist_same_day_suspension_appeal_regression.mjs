// In-memory PostgreSQL regression; never connects to or mutates a linked project.
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const tourist = id(1);
const administrator = id(2);
const mto = id(3);
const provincial = id(4);
const secondTourist = id(5);

const asUser = actor => db.query(
  `select set_config('test.uid', $1, false)`,
  [actor],
);

try {
  await db.exec(`
    create schema auth;
    create role anon;
    create role authenticated;

    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('test.uid', true), '')::uuid
    $$;

    create table public.profiles(
      id uuid primary key,
      role text not null,
      full_name text,
      first_name text,
      last_name text,
      mobile text
    );
    insert into public.profiles(id, role, full_name) values
      ('${tourist}', 'tourist', 'Tourist One'),
      ('${administrator}', 'administrator', 'System Administrator'),
      ('${mto}', 'subtenant', 'Baliwag Tourism Office'),
      ('${provincial}', 'main_tenant', 'Bulacan Provincial Admin'),
      ('${secondTourist}', 'tourist', 'Tourist Two');

    create function public.current_profile_role() returns text
      language sql stable as $$
        select role from public.profiles where id = auth.uid()
      $$;
    create function public.is_system_administrator() returns boolean
      language sql stable as $$
        select public.current_profile_role() = 'administrator'
      $$;
    create function public.is_main_tenant() returns boolean
      language sql stable as $$
        select public.current_profile_role() = 'main_tenant'
      $$;
    create function public.cities_match(text, text) returns boolean
      language sql immutable as $$
        select lower(trim(coalesce($1, ''))) = lower(trim(coalesce($2, '')))
      $$;

    create table public.subtenant_details(
      id uuid primary key,
      city text not null,
      province text not null,
      is_active boolean not null default true
    );
    insert into public.subtenant_details values
      ('${mto}', 'Baliwag', 'Bulacan', true);
    create table public.provincial_office_details(
      user_id uuid primary key,
      province text not null
    );
    insert into public.provincial_office_details values
      ('${provincial}', 'Bulacan');
    create function public.is_municipal_complaint_officer(text, text)
      returns boolean language sql stable as $$
        select exists (
          select 1 from public.subtenant_details office
          where office.id = auth.uid() and office.is_active
            and public.cities_match(office.city, $1)
            and public.cities_match(office.province, $2)
        )
      $$;

    create table public.tour_packages(
      id bigint primary key,
      title text not null,
      city text not null
    );
    insert into public.tour_packages values (1, 'Heritage Tour', 'Baliwag');

    create table public.package_bookings(
      id uuid primary key,
      tourist_id uuid not null references public.profiles(id),
      package_id bigint references public.tour_packages(id),
      status text not null default 'confirmed',
      booking_status text not null default 'confirmed',
      travel_date date default current_date,
      municipality text,
      province text,
      cancelled_by uuid,
      cancelled_at timestamptz,
      cancellation_party text,
      cancellation_type text
    );

    create table public.notifications(
      id bigint generated always as identity primary key,
      user_id uuid not null,
      booking_id uuid,
      title text not null,
      body text not null,
      type text not null,
      is_read boolean not null default false,
      dedupe_key text,
      data jsonb not null default '{}'::jsonb
    );
    create unique index notifications_dedupe on public.notifications(dedupe_key)
      where dedupe_key is not null;

    create table public.tourist_cancellation_protection_settings(
      id boolean primary key default true check (id),
      enabled boolean not null default true,
      rolling_days integer not null default 30,
      restriction_threshold integer not null default 3,
      restriction_hours integer not null default 24,
      updated_at timestamptz not null default now()
    );
    insert into public.tourist_cancellation_protection_settings(id) values(true);

    create table public.tourist_booking_restrictions(
      tourist_id uuid primary key references public.profiles(id),
      restricted_until timestamptz not null,
      status text not null check (status in ('active', 'lifted')),
      source_booking_id uuid references public.package_bookings(id),
      reviewed_by uuid references public.profiles(id),
      review_note text,
      updated_at timestamptz not null default now()
    );
    create table public.tourist_booking_restriction_appeals(
      id uuid primary key default gen_random_uuid(),
      tourist_id uuid not null references public.profiles(id),
      reason text not null,
      status text not null default 'pending'
        check (status in ('pending', 'approved', 'declined')),
      created_at timestamptz not null default now(),
      reviewed_at timestamptz,
      reviewed_by uuid references public.profiles(id),
      review_note text
    );
    create unique index one_pending_booking_appeal
      on public.tourist_booking_restriction_appeals(tourist_id)
      where status = 'pending';
    create table public.tourist_cancellation_exception_reviews(
      booking_id uuid primary key references public.package_bookings(id),
      approved_by uuid not null references public.profiles(id),
      approved_at timestamptz not null default now(),
      note text not null
    );

    create function public.cancel_package_booking_protection_impl(
      p_booking_id uuid,
      p_reason text,
      p_note text default null,
      p_category text default 'general'
    ) returns jsonb language plpgsql security definer set search_path = '' as $$
    begin
      update public.package_bookings
      set cancelled_by = auth.uid(),
          cancelled_at = clock_timestamp(),
          cancellation_party = 'tourist',
          cancellation_type = 'general',
          status = 'cancelled',
          booking_status = 'cancelled'
      where id = p_booking_id
        and tourist_id = auth.uid()
        and cancelled_at is null;
      if not found then raise exception 'BOOKING_NOT_CANCELLABLE'; end if;
      return jsonb_build_object('booking_id', p_booking_id, 'status', 'cancelled');
    end;
    $$;

    create function public.create_package_booking(
      p_booking jsonb,
      p_customized_spots jsonb default '[]'::jsonb,
      p_itinerary_items jsonb default '[]'::jsonb
    ) returns public.package_bookings language plpgsql security definer
    set search_path = '' as $$
    declare result public.package_bookings;
    begin
      if exists (
        select 1 from public.tourist_booking_restrictions restriction
        where restriction.tourist_id = auth.uid()
          and restriction.status = 'active'
          and restriction.restricted_until > clock_timestamp()
      ) then
        raise exception 'NEW_BOOKINGS_TEMPORARILY_RESTRICTED';
      end if;
      insert into public.package_bookings(
        id, tourist_id, package_id, municipality, province
      ) values (
        (p_booking->>'id')::uuid, auth.uid(), 1, 'Baliwag', 'Bulacan'
      ) returning * into result;
      return result;
    end;
    $$;
  `);

  const bookingRows = [11, 12, 13, 14]
    .map(n => `('${id(n)}', '${tourist}', 1, 'Baliwag', 'Bulacan')`)
    .join(',');
  await db.exec(`
    insert into public.package_bookings(
      id, tourist_id, package_id, municipality, province
    ) values ${bookingRows};
  `);

  const migration = readFileSync(new URL(
    '../migrations/20261010110000_tourist_same_day_cancellation_suspension.sql',
    import.meta.url,
  ), 'utf8');
  await db.exec(migration);
  const escalationMigration = readFileSync(new URL(
    '../migrations/20261010120000_suspension_case_escalation_workflow.sql',
    import.meta.url,
  ), 'utf8');
  await db.exec(escalationMigration);

  await asUser(tourist);
  for (const [index, booking] of [11, 12].entries()) {
    const result = (await db.query(
      `select public.cancel_package_booking($1, 'general', null, 'general') as result`,
      [id(booking)],
    )).rows[0].result;
    assert.equal(result.qualifying_cancellations_today, index + 1);
    assert.equal(result.booking_restriction_created, false);
  }

  const third = (await db.query(
    `select public.cancel_package_booking($1, 'general', null, 'general') as result`,
    [id(13)],
  )).rows[0].result;
  assert.equal(third.qualifying_cancellations_today, 3);
  assert.equal(third.booking_restriction_created, true);
  assert.ok(third.booking_restriction_case_id);

  const initialRestriction = (await db.query(`
    select case_id, status, source, cancellation_count, offense_number,
      extract(epoch from (restricted_until - started_at))::integer as seconds
    from public.tourist_booking_restrictions where tourist_id = $1
  `, [tourist])).rows[0];
  assert.equal(initialRestriction.status, 'active');
  assert.equal(initialRestriction.source, 'same_day_tourist_cancellations');
  assert.equal(initialRestriction.cancellation_count, 3);
  assert.equal(initialRestriction.seconds, 259200);
  assert.equal(initialRestriction.offense_number, 1);

  await assert.rejects(() => db.query(
    `select public.create_package_booking($1::jsonb, '[]', '[]')`,
    [JSON.stringify({id: id(20)})],
  ), /NEW_BOOKINGS_TEMPORARILY_RESTRICTED/);

  const fourth = (await db.query(
    `select public.cancel_package_booking($1, 'general', null, 'general') as result`,
    [id(14)],
  )).rows[0].result;
  assert.equal(fourth.qualifying_cancellations_today, 4);
  assert.equal(fourth.booking_restriction_created, false);
  assert.equal(fourth.booking_restriction_case_id, initialRestriction.case_id);
  assert.equal((await db.query(
    `select count(*)::integer as count from public.tourist_booking_restrictions
      where tourist_id = $1`, [tourist],
  )).rows[0].count, 1);

  const recipients = (await db.query(`
    select user_id::text as user_id, count(*)::integer as count
    from public.notifications
    where type = 'booking_restriction_case'
    group by user_id
  `)).rows;
  assert.deepEqual(
    new Set(recipients.map(row => row.user_id)),
    new Set([mto, provincial]),
  );

  const appealId = (await db.query(
    `select public.appeal_tourist_booking_restriction($1) as id`,
    ['Please review the circumstances of these cancellations.'],
  )).rows[0].id;
  assert.equal((await db.query(
    `select status from public.tourist_booking_restriction_appeals where id = $1`,
    [appealId],
  )).rows[0].status, 'pending_review');
  await assert.rejects(() => db.query(
    `select public.appeal_tourist_booking_restriction($1)`,
    ['This duplicate appeal must not be accepted.'],
  ), /APPEAL_ALREADY_SUBMITTED/);

  await asUser(mto);
  const cases = (await db.query(
    `select * from public.get_tourist_booking_restriction_cases(null)`,
  )).rows;
  assert.equal(cases.length, 1);
  assert.equal(cases[0].get_tourist_booking_restriction_cases.status, 'under_review');
  assert.equal(cases[0].get_tourist_booking_restriction_cases.original_status, 'pending_review');

  const rejected = (await db.query(
    `select public.review_tourist_booking_restriction_appeal($1, false, $2) as result`,
    [appealId, 'The same-day cancellation evidence was confirmed.'],
  )).rows[0].result;
  assert.equal(rejected.status, 'rejected');
  assert.equal((await db.query(
    `select status from public.tourist_booking_restrictions where tourist_id = $1`,
    [tourist],
  )).rows[0].status, 'active');
  await assert.rejects(() => db.query(
    `select public.review_tourist_booking_restriction_appeal($1, true, $2)`,
    [appealId, 'A duplicate decision must not be accepted.'],
  ), /APPEAL_NOT_PENDING/);

  // Move the completed first offense into yesterday, then reach the threshold
  // on a new calendar day while the previous restriction is still active.
  await db.query(`
    update public.tourist_booking_suspension_cases
    set offense_day = current_date - 1, starts_at = starts_at - interval '1 day'
    where case_id = $1
  `, [initialRestriction.case_id]);
  await db.query(`
    update public.package_bookings
    set cancelled_at = cancelled_at - interval '1 day'
    where id = any($1::uuid[])
  `, [[id(11), id(12), id(13), id(14)]]);
  await db.exec(`
    insert into public.package_bookings(
      id, tourist_id, package_id, municipality, province
    ) values
      ('${id(21)}','${tourist}',1,'Baliwag','Bulacan'),
      ('${id(22)}','${tourist}',1,'Baliwag','Bulacan'),
      ('${id(23)}','${tourist}',1,'Baliwag','Bulacan');
  `);
  await asUser(tourist);
  let secondOffense;
  for (const booking of [21, 22, 23]) {
    secondOffense = (await db.query(
      `select public.cancel_package_booking($1, 'general', null, 'general') as result`,
      [id(booking)],
    )).rows[0].result;
  }
  assert.equal(secondOffense.booking_restriction_created, true);
  assert.equal(secondOffense.booking_restriction_offense_number, 2);
  assert.equal(secondOffense.booking_restriction_manual_review_required, false);
  const secondOffenseCase = secondOffense.booking_restriction_case_id;
  assert.equal((await db.query(`
    select extract(epoch from (ends_at - starts_at))::integer as seconds
    from public.tourist_booking_suspension_cases where case_id = $1
  `, [secondOffenseCase])).rows[0].seconds, 604800);

  const routeNotification = async (actor, type) => {
    await asUser(actor);
    const notification = (await db.query(`
      select id::text as id from public.notifications
      where user_id = $1 and data->>'case_id' = $2
      order by id desc limit 1
    `, [actor, secondOffenseCase])).rows[0];
    assert.ok(notification, `missing routed notification for ${actor}`);
    return (await db.query(
      `select public.notification_destination($1) as destination`,
      [notification.id],
    )).rows[0].destination;
  };
  assert.equal((await routeNotification(tourist, 'tourist')).screen, 'tourist_suspension');
  assert.equal((await routeNotification(mto, 'mto')).screen, 'subtenant_case');
  assert.equal((await routeNotification(provincial, 'provincial')).screen, 'provincial_case');

  // A third qualifying day escalates to 14 days and requires manual review.
  await db.query(`
    update public.tourist_booking_suspension_cases
    set offense_day = current_date - 2
    where case_id = $1
  `, [initialRestriction.case_id]);
  await db.query(`
    update public.tourist_booking_suspension_cases
    set offense_day = current_date - 1, starts_at = starts_at - interval '1 day'
    where case_id = $1
  `, [secondOffenseCase]);
  await db.query(`
    update public.package_bookings
    set cancelled_at = cancelled_at - interval '1 day'
    where id = any($1::uuid[])
  `, [[id(21), id(22), id(23)]]);
  await db.exec(`
    insert into public.package_bookings(
      id, tourist_id, package_id, municipality, province
    ) values
      ('${id(31)}','${tourist}',1,'Baliwag','Bulacan'),
      ('${id(32)}','${tourist}',1,'Baliwag','Bulacan'),
      ('${id(33)}','${tourist}',1,'Baliwag','Bulacan'),
      ('${id(34)}','${tourist}',1,'Baliwag','Bulacan');
  `);
  await asUser(tourist);
  let thirdOffense;
  for (const booking of [31, 32, 33]) {
    thirdOffense = (await db.query(
      `select public.cancel_package_booking($1, 'general', null, 'general') as result`,
      [id(booking)],
    )).rows[0].result;
  }
  assert.equal(thirdOffense.booking_restriction_offense_number, 3);
  assert.equal(thirdOffense.booking_restriction_manual_review_required, true);
  assert.equal(thirdOffense.booking_restriction_risk_level, 'elevated');
  const thirdOffenseCase = thirdOffense.booking_restriction_case_id;
  assert.equal((await db.query(`
    select extract(epoch from (ends_at - starts_at))::integer as seconds
    from public.tourist_booking_suspension_cases where case_id = $1
  `, [thirdOffenseCase])).rows[0].seconds, 1209600);
  const duplicateDay = (await db.query(
    `select public.cancel_package_booking($1, 'general', null, 'general') as result`,
    [id(34)],
  )).rows[0].result;
  assert.equal(duplicateDay.booking_restriction_created, false);
  assert.equal(duplicateDay.booking_restriction_case_id, thirdOffenseCase);
  assert.equal((await db.query(`
    select count(*)::integer as count
    from public.tourist_booking_suspension_cases where tourist_id = $1
  `, [tourist])).rows[0].count, 3);

  await asUser(provincial);
  await db.query(`select public.manage_tourist_booking_suspension_case(
    $1, 'start_review', $2)`, [thirdOffenseCase, 'Provincial manual review started.']);
  await db.query(`select public.manage_tourist_booking_suspension_case(
    $1, 'escalate', $2)`, [thirdOffenseCase, 'Repeated abuse supports the one policy extension.']);
  await assert.rejects(() => db.query(
    `select public.manage_tourist_booking_suspension_case($1, 'escalate', $2)`,
    [thirdOffenseCase, 'A duplicate policy extension must be rejected.'],
  ), /POLICY_EXTENSION_NOT_ALLOWED/);

  const secondCase = id(90);
  const secondAppeal = id(91);
  await db.query(`
    insert into public.tourist_booking_restrictions(
      tourist_id, case_id, restricted_until, status, started_at, reason,
      cancellation_count, source, cancellation_booking_ids,
      municipality, province
    ) values ($1, $2, clock_timestamp() + interval '3 days', 'active',
      clock_timestamp(), 'Three same-day tourist cancellations.', 3,
      'same_day_tourist_cancellations', '{}'::uuid[], 'Baliwag', 'Bulacan')
  `, [secondTourist, secondCase]);
  await db.query(`
    insert into public.tourist_booking_suspension_cases(
      case_id, tourist_id, municipality, province, offense_day,
      offense_number, cancellation_count, reason, starts_at, ends_at
    ) values ($1, $2, 'Baliwag', 'Bulacan', current_date, 1, 3,
      'Three same-day tourist cancellations.', clock_timestamp(),
      clock_timestamp() + interval '3 days')
  `, [secondCase, secondTourist]);
  await db.query(`
    insert into public.tourist_booking_restriction_appeals(
      id, tourist_id, case_id, reason, status, municipality, province,
      suspension_reason, cancellation_count, cancellation_booking_ids,
      suspension_started_at, suspension_ends_at
    ) values ($1, $2, $3, 'Please approve this valid appeal.', 'pending_review',
      'Baliwag', 'Bulacan', 'Three same-day tourist cancellations.', 3,
      '{}'::uuid[], clock_timestamp(), clock_timestamp() + interval '3 days')
  `, [secondAppeal, secondTourist, secondCase]);
  await asUser(provincial);
  const approved = (await db.query(
    `select public.review_tourist_booking_restriction_appeal($1, true, $2) as result`,
    [secondAppeal, 'The appeal evidence supports immediate restoration.'],
  )).rows[0].result;
  assert.equal(approved.status, 'approved');
  assert.equal(approved.restriction_lifted, true);
  assert.equal((await db.query(
    `select status from public.tourist_booking_restrictions where tourist_id = $1`,
    [secondTourist],
  )).rows[0].status, 'lifted');

  await db.query(`
    update public.tourist_booking_restrictions
    set restricted_until = clock_timestamp() - interval '1 second'
    where tourist_id = $1
  `, [tourist]);
  await asUser(tourist);
  const expired = (await db.query(
    `select public.get_my_tourist_booking_restriction() as result`,
  )).rows[0].result;
  assert.equal(expired.active, false);
  assert.equal(expired.status, 'expired');
  const bookingAfterExpiry = (await db.query(
    `select (public.create_package_booking($1::jsonb, '[]', '[]')).id as id`,
    [JSON.stringify({id: id(20)})],
  )).rows[0];
  assert.equal(bookingAfterExpiry.id, id(20));

  console.log('PASS: exact threshold, scoped case appeal, decisions and expiry');
} finally {
  await db.close();
}
