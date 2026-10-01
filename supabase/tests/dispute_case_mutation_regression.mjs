import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '../../build/sql-validation/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const migration = await readFile(
  new URL('../migrations/20260930040000_repair_dispute_case_mutation_results.sql', import.meta.url),
  'utf8',
);
const id = value => `40000000-0000-0000-0000-${String(value).padStart(12, '0')}`;
const subtenantA = id(1);
const subtenantB = id(2);
const reporter = id(3);
const reported = id(4);
const reviewCase = id(10);
const resolveCase = id(11);
const auditFailureCase = id(12);
const crossCityCase = id(13);
let checks = 0;

const check = (actual, expected, label) => {
  assert.deepEqual(actual, expected, label);
  checks++;
};
const scalar = async (sql, params = []) =>
  Object.values((await db.query(sql, params)).rows[0])[0];

await db.exec(`
  create role authenticated;
  create role anon;
  create schema auth;
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;

  create table public.profiles(id uuid primary key, role text, city text);
  create table public.subtenant_details(
    id uuid primary key, city text, is_active boolean not null default true
  );
  create table public.payment_records(id uuid primary key, status text);
  create table public.payment_disputes(
    id uuid primary key,
    payment_record_id uuid,
    raised_by uuid not null,
    reported_user_id uuid,
    category text not null,
    municipality text not null,
    status text not null,
    reviewed_at timestamptz,
    assigned_to uuid,
    resolution_type text,
    custom_resolution text,
    resolution_note text,
    resolved_by uuid,
    resolved_at timestamptz
  );
  create table public.audit_logs(
    id bigint generated always as identity primary key,
    actor_id uuid,
    action text,
    table_name text,
    record_id text,
    description text
  );
  create table public.notifications(
    id bigint generated always as identity primary key,
    user_id uuid,
    title text,
    body text,
    type text,
    is_read boolean default false,
    dedupe_key text unique
  );

  create function public.can_manage_dispute_case(p_case_id uuid)
  returns boolean language sql stable security definer set search_path = '' as $$
    select exists(
      select 1
      from public.payment_disputes dispute
      join public.subtenant_details office on office.id = auth.uid()
      where dispute.id = p_case_id
        and office.is_active
        and lower(office.city) = lower(dispute.municipality)
    )
  $$;

  create function public.fail_case_notification()
  returns trigger language plpgsql as $$
  begin
    if current_setting('test.fail_notifications', true) = 'true' then
      raise exception 'SIMULATED_NOTIFICATION_FAILURE';
    end if;
    return new;
  end
  $$;
  create trigger fail_case_notification
  before insert on public.notifications
  for each row execute function public.fail_case_notification();

  insert into public.profiles values
    ('${subtenantA}', 'subtenant', 'City A'),
    ('${subtenantB}', 'subtenant', 'City B'),
    ('${reporter}', 'tourist', 'City A'),
    ('${reported}', 'driver', 'City A');
  insert into public.subtenant_details values
    ('${subtenantA}', 'City A', true),
    ('${subtenantB}', 'City B', true);
  insert into public.payment_disputes(
    id, raised_by, reported_user_id, category, municipality, status,
    reviewed_at, assigned_to
  ) values
    ('${reviewCase}', '${reporter}', '${reported}', 'driver', 'City A', 'needs_review', null, null),
    ('${resolveCase}', '${reporter}', '${reported}', 'driver', 'City A', 'under_review', now(), '${subtenantA}'),
    ('${auditFailureCase}', '${reporter}', '${reported}', 'booking', 'City A', 'needs_review', null, null),
    ('${crossCityCase}', '${reporter}', '${reported}', 'driver', 'City B', 'needs_review', null, null);

  grant usage on schema public, auth to authenticated;
  grant select on public.payment_disputes, public.audit_logs,
    public.notifications to authenticated;
  grant execute on function auth.uid(), public.can_manage_dispute_case(uuid)
    to authenticated;
`);

await db.exec(migration);
await db.query("select set_config('request.jwt.claim.sub', $1, false)", [subtenantA]);
await db.query("select set_config('test.fail_notifications', 'true', false)");
await db.exec('set role authenticated');

const started = await scalar('select start_dispute_case($1)', [reviewCase]);
check(started.status, 'under_review', 'start returns authoritative status');
check(started.transitioned, true, 'first start reports a transition');
check(started.notification_failures, 2, 'notification failures are reported but non-fatal');
check(
  await scalar('select reviewed_at is not null from payment_disputes where id=$1', [reviewCase]),
  true,
  'reviewed_at persists',
);
check(
  await scalar('select assigned_to from payment_disputes where id=$1', [reviewCase]),
  subtenantA,
  'reviewer persists',
);
const firstReviewedAt = await scalar(
  'select reviewed_at::text from payment_disputes where id=$1',
  [reviewCase],
);
check(
  await scalar("select count(*)::int from audit_logs where record_id=$1 and action='start_case_review'", [reviewCase]),
  1,
  'review audit is written exactly once',
);

const repeatedStart = await scalar('select start_dispute_case($1)', [reviewCase]);
check(repeatedStart.transitioned, false, 'repeated start is an idempotent no-op');
check(
  await scalar('select reviewed_at::text from payment_disputes where id=$1', [reviewCase]),
  firstReviewedAt,
  'repeated start preserves the original review timestamp',
);
check(
  await scalar("select count(*)::int from audit_logs where record_id=$1 and action='start_case_review'", [reviewCase]),
  1,
  'repeated start does not duplicate review history',
);

const resolved = await scalar(
  'select resolve_dispute_case($1,$2,$3,$4)',
  [resolveCase, 'warning_issued', 'Documented warning.', null],
);
check(resolved.status, 'closed', 'resolve returns authoritative status');
check(resolved.transitioned, true, 'first resolve reports a transition');
check(resolved.notification_failures, 2, 'resolve notification failures are non-fatal');
check(
  await scalar('select resolved_at is not null from payment_disputes where id=$1', [resolveCase]),
  true,
  'resolution metadata persists',
);
check(
  await scalar("select count(*)::int from audit_logs where record_id=$1 and action='resolve_dispute_case'", [resolveCase]),
  1,
  'resolution audit is written exactly once',
);

const repeatedResolve = await scalar(
  'select resolve_dispute_case($1,$2,$3,$4)',
  [resolveCase, 'warning_issued', 'Documented warning.', null],
);
check(repeatedResolve.transitioned, false, 'exact repeated resolution is idempotent');
check(
  await scalar("select count(*)::int from audit_logs where record_id=$1 and action='resolve_dispute_case'", [resolveCase]),
  1,
  'repeated resolve does not duplicate resolution history',
);
await assert.rejects(
  () => db.query('select resolve_dispute_case($1,$2,$3,$4)', [resolveCase, 'no_action_required', 'Changed result.', null]),
  /CASE_ALREADY_RESOLVED/,
);
checks++;

await assert.rejects(
  () => db.query('select start_dispute_case($1)', [crossCityCase]),
  /NOT_AUTHORIZED/,
);
checks++;
check(
  await scalar('select status from payment_disputes where id=$1', [crossCityCase]),
  'needs_review',
  'municipality isolation leaves cross-city state unchanged',
);

await db.exec('reset role');
await db.exec(`
  create function public.fail_case_audit()
  returns trigger language plpgsql as $$
  begin
    if new.record_id = '${auditFailureCase}' then
      raise exception 'SIMULATED_AUDIT_FAILURE';
    end if;
    return new;
  end
  $$;
  create trigger fail_case_audit before insert on public.audit_logs
  for each row execute function public.fail_case_audit();
`);
await db.exec('set role authenticated');
await assert.rejects(
  () => db.query('select start_dispute_case($1)', [auditFailureCase]),
  /SIMULATED_AUDIT_FAILURE/,
);
checks++;
check(
  await scalar('select status from payment_disputes where id=$1', [auditFailureCase]),
  'needs_review',
  'authoritative audit failure rolls back the primary transition',
);

console.log(`dispute case mutation regression passed (${checks} checks)`);
