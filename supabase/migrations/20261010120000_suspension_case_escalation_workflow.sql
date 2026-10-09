-- Durable suspension cases, configurable repeat-offense escalation, scoped
-- case actions, expiry notifications, and notification deep links.
begin;

alter table public.tourist_cancellation_protection_settings
  add column if not exists offense_lookback_days integer not null default 365,
  add column if not exists first_offense_hours integer not null default 72,
  add column if not exists second_offense_hours integer not null default 168,
  add column if not exists third_offense_hours integer not null default 336,
  add column if not exists further_offense_hours integer not null default 336;

alter table public.tourist_booking_restrictions
  add column if not exists offense_number integer not null default 1,
  add column if not exists manual_review_required boolean not null default false,
  add column if not exists risk_level text not null default 'standard';

alter table public.tourist_booking_restrictions
  drop constraint if exists tourist_booking_restrictions_status_check;
alter table public.tourist_booking_restrictions
  add constraint tourist_booking_restrictions_status_check
  check (status in ('active', 'lifted', 'expired'));

create table public.tourist_booking_suspension_cases (
  case_id uuid primary key,
  tourist_id uuid not null references public.profiles(id) on delete cascade,
  source_booking_id uuid references public.package_bookings(id) on delete set null,
  municipality text not null,
  province text not null,
  offense_day date not null,
  offense_number integer not null check (offense_number > 0),
  cancellation_count integer not null check (cancellation_count >= 3),
  cancellation_booking_ids uuid[] not null default '{}'::uuid[],
  reason text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  restriction_status text not null default 'active'
    check (restriction_status in ('active','lifted','expired','escalated')),
  case_status text not null default 'needs_review'
    check (case_status in ('needs_review','under_review','closed')),
  appeal_status text check (
    appeal_status is null or
    appeal_status in ('pending_review','approved','rejected')
  ),
  manual_review_required boolean not null default false,
  manual_extension_used boolean not null default false,
  risk_level text not null default 'standard'
    check (risk_level in ('standard','elevated','high_risk')),
  resolution_note text,
  resolved_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(tourist_id, offense_day)
);

create index tourist_booking_suspension_cases_scope_idx
  on public.tourist_booking_suspension_cases(province, municipality, created_at desc);
create index tourist_booking_suspension_cases_tourist_idx
  on public.tourist_booking_suspension_cases(tourist_id, created_at desc);

create table public.tourist_booking_suspension_events (
  id bigint generated always as identity primary key,
  case_id uuid not null references public.tourist_booking_suspension_cases(case_id)
    on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  details text not null,
  created_at timestamptz not null default clock_timestamp()
);
create index tourist_booking_suspension_events_case_idx
  on public.tourist_booking_suspension_events(case_id, created_at);

alter table public.tourist_booking_suspension_cases enable row level security;
alter table public.tourist_booking_suspension_events enable row level security;
revoke all on public.tourist_booking_suspension_cases,
  public.tourist_booking_suspension_events from public, anon, authenticated;

insert into public.tourist_booking_suspension_cases(
  case_id, tourist_id, source_booking_id, municipality, province, offense_day,
  offense_number, cancellation_count, cancellation_booking_ids, reason,
  starts_at, ends_at, restriction_status, case_status, manual_review_required,
  risk_level, created_at, updated_at
)
select
  restriction.case_id, restriction.tourist_id, restriction.source_booking_id,
  coalesce(nullif(restriction.municipality, ''), 'Unknown'),
  coalesce(nullif(restriction.province, ''), 'Unknown'),
  (restriction.started_at at time zone 'Asia/Manila')::date,
  restriction.offense_number, restriction.cancellation_count,
  restriction.cancellation_booking_ids, restriction.reason,
  restriction.started_at, restriction.restricted_until,
  case
    when restriction.status = 'lifted' then 'lifted'
    when restriction.restricted_until <= clock_timestamp() then 'expired'
    else 'active'
  end,
  case
    when restriction.status = 'lifted'
      or restriction.restricted_until <= clock_timestamp() then 'closed'
    else 'needs_review'
  end,
  restriction.manual_review_required, restriction.risk_level,
  restriction.started_at, restriction.updated_at
from public.tourist_booking_restrictions restriction
on conflict (case_id) do nothing;

insert into public.tourist_booking_suspension_events(
  case_id, actor_id, action, details, created_at
)
select case_record.case_id, null, 'automatic_suspension',
  case_record.cancellation_count ||
    ' same-day tourist-initiated cancellations; offense #' ||
    case_record.offense_number,
  case_record.starts_at
from public.tourist_booking_suspension_cases case_record
where not exists (
  select 1 from public.tourist_booking_suspension_events event
  where event.case_id = case_record.case_id
    and event.action = 'automatic_suspension'
);

alter function public.cancel_package_booking(uuid,text,text,text)
  rename to cancel_package_booking_same_day_impl;
revoke all on function public.cancel_package_booking_same_day_impl(
  uuid,text,text,text) from public, anon, authenticated;

create function public.cancel_package_booking(
  p_booking_id uuid,
  p_reason text,
  p_note text default null,
  p_category text default 'general'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_booking public.package_bookings;
  v_settings public.tourist_cancellation_protection_settings;
  v_restriction public.tourist_booking_restrictions;
  v_count integer;
  v_day date;
  v_case_id uuid;
  v_offense integer;
  v_hours integer;
  v_start timestamptz;
  v_end timestamptz;
  v_reason text;
  v_ids uuid[];
  v_manual boolean;
  v_risk text;
  v_new_case boolean := false;
  v_recipient uuid;
begin
  v_result := public.cancel_package_booking_same_day_impl(
    p_booking_id, p_reason, p_note, p_category
  );
  select * into v_booking from public.package_bookings where id = p_booking_id;
  if not found
     or v_booking.cancelled_by is distinct from v_booking.tourist_id
     or coalesce(v_booking.cancellation_party, '') <> 'tourist'
     or v_booking.cancelled_at is null then
    return v_result;
  end if;

  v_count := coalesce((v_result->>'qualifying_cancellations_today')::integer, 0);
  if v_count < 3 then return v_result; end if;
  v_day := (v_booking.cancelled_at at time zone 'Asia/Manila')::date;
  perform pg_advisory_xact_lock(hashtextextended(v_booking.tourist_id::text, 0));

  select case_record.case_id, case_record.offense_number,
    case_record.starts_at, case_record.ends_at,
    case_record.manual_review_required, case_record.risk_level
  into v_case_id, v_offense, v_start, v_end, v_manual, v_risk
  from public.tourist_booking_suspension_cases case_record
  where case_record.tourist_id = v_booking.tourist_id
    and case_record.offense_day = v_day;
  if found then
    return v_result || jsonb_build_object(
      'booking_restriction_created', false,
      'booking_restriction_case_id', v_case_id,
      'booking_restricted_until', v_end,
      'booking_restriction_offense_number', v_offense,
      'booking_restriction_manual_review_required', v_manual,
      'booking_restriction_risk_level', v_risk
    );
  end if;

  select * into v_settings
  from public.tourist_cancellation_protection_settings where id = true;
  select count(*)::integer + 1 into v_offense
  from public.tourist_booking_suspension_cases case_record
  where case_record.tourist_id = v_booking.tourist_id
    and case_record.starts_at >= clock_timestamp() -
      make_interval(days => v_settings.offense_lookback_days);
  v_hours := case v_offense
    when 1 then v_settings.first_offense_hours
    when 2 then v_settings.second_offense_hours
    when 3 then v_settings.third_offense_hours
    else v_settings.further_offense_hours
  end;
  v_manual := v_offense >= 3;
  v_risk := case when v_offense >= 4 then 'high_risk'
    when v_offense >= 2 then 'elevated' else 'standard' end;
  v_start := clock_timestamp();
  v_end := v_start + make_interval(hours => v_hours);
  v_case_id := case
    when coalesce((v_result->>'booking_restriction_created')::boolean, false)
      then (v_result->>'booking_restriction_case_id')::uuid
    else gen_random_uuid()
  end;
  v_reason := case when v_offense = 1
    then 'Three tourist-initiated bookings were cancelled on the same calendar day.'
    else 'Repeat cancellation offense #' || v_offense ||
      ': three tourist-initiated bookings were cancelled on the same calendar day.'
  end;
  select coalesce(array_agg(booking.id order by booking.cancelled_at), '{}'::uuid[])
  into v_ids
  from public.package_bookings booking
  where booking.tourist_id = v_booking.tourist_id
    and booking.cancelled_by = booking.tourist_id
    and booking.cancellation_party = 'tourist'
    and (booking.cancelled_at at time zone 'Asia/Manila')::date = v_day
    and lower(coalesce(booking.booking_status, booking.status, '')) = 'cancelled'
    and not exists (
      select 1 from public.tourist_cancellation_exception_reviews review
      where review.booking_id = booking.id
    );

  select * into v_restriction
  from public.tourist_booking_restrictions
  where tourist_id = v_booking.tourist_id for update;
  if found and v_restriction.case_id <> v_case_id then
    update public.tourist_booking_suspension_cases
    set restriction_status = case when ends_at <= clock_timestamp()
          then 'expired' else 'escalated' end,
        case_status = 'closed', resolved_at = clock_timestamp(),
        resolution_note = 'Superseded by repeat offense #' || v_offense,
        updated_at = clock_timestamp()
    where case_id = v_restriction.case_id and case_status <> 'closed';
    insert into public.tourist_booking_suspension_events(
      case_id, actor_id, action, details
    ) values (
      v_restriction.case_id, null, 'repeat_offense_escalation',
      'Superseded by repeat offense #' || v_offense
    );
  end if;

  insert into public.tourist_booking_suspension_cases(
    case_id, tourist_id, source_booking_id, municipality, province, offense_day,
    offense_number, cancellation_count, cancellation_booking_ids, reason,
    starts_at, ends_at, manual_review_required, risk_level
  ) values (
    v_case_id, v_booking.tourist_id, p_booking_id,
    coalesce(nullif(v_booking.municipality, ''), 'Unknown'),
    coalesce(nullif(v_booking.province, ''), 'Unknown'),
    v_day, v_offense, v_count, v_ids, v_reason, v_start, v_end, v_manual, v_risk
  );
  insert into public.tourist_booking_suspension_events(
    case_id, actor_id, action, details
  ) values (
    v_case_id, null, 'automatic_suspension',
    v_count || ' same-day tourist-initiated cancellations; offense #' || v_offense
  );

  insert into public.tourist_booking_restrictions(
    tourist_id, case_id, restricted_until, status, source_booking_id,
    started_at, reason, cancellation_count, source,
    cancellation_booking_ids, municipality, province, offense_number,
    manual_review_required, risk_level, reviewed_by, review_note, updated_at
  ) values (
    v_booking.tourist_id, v_case_id, v_end, 'active', p_booking_id,
    v_start, v_reason, v_count, 'same_day_tourist_cancellations', v_ids,
    v_booking.municipality, v_booking.province, v_offense, v_manual, v_risk,
    null, null, clock_timestamp()
  ) on conflict (tourist_id) do update set
    case_id = excluded.case_id, restricted_until = excluded.restricted_until,
    status = 'active', source_booking_id = excluded.source_booking_id,
    started_at = excluded.started_at, reason = excluded.reason,
    cancellation_count = excluded.cancellation_count, source = excluded.source,
    cancellation_booking_ids = excluded.cancellation_booking_ids,
    municipality = excluded.municipality, province = excluded.province,
    offense_number = excluded.offense_number,
    manual_review_required = excluded.manual_review_required,
    risk_level = excluded.risk_level, reviewed_by = null, review_note = null,
    updated_at = clock_timestamp();
  v_new_case := true;

  update public.notifications
  set title = case when v_offense = 1
        then 'Booking privileges suspended for 3 days'
        else 'Booking suspension escalated: offense #' || v_offense end,
      body = 'Your booking privileges are suspended until ' ||
        to_char(v_end at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM') ||
        '. Offense level: ' || v_offense || '.',
      data = coalesce(data, '{}'::jsonb) || jsonb_build_object(
        'case_id', v_case_id, 'route', 'tourist_suspension',
        'offense_number', v_offense, 'restricted_until', v_end
      )
  where user_id = v_booking.tourist_id
    and dedupe_key = 'tourist_auto_suspension:' || v_case_id::text || ':' ||
      v_booking.tourist_id::text;

  if not found then
    insert into public.notifications(
      user_id, booking_id, title, body, type, is_read, dedupe_key, data
    ) values (
      v_booking.tourist_id, p_booking_id,
      case when v_offense = 1 then 'Booking privileges suspended for 3 days'
        else 'Booking suspension escalated: offense #' || v_offense end,
      'Your booking privileges are suspended until ' ||
        to_char(v_end at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM') ||
        '. Offense level: ' || v_offense || '.',
      'booking_restriction', false,
      'tourist_suspension_case:' || v_case_id::text || ':' ||
        v_booking.tourist_id::text,
      jsonb_build_object(
        'case_id', v_case_id, 'route', 'tourist_suspension',
        'offense_number', v_offense, 'restricted_until', v_end
      )
    ) on conflict (dedupe_key) where dedupe_key is not null do nothing;
  end if;

  for v_recipient in
    select office.id from public.subtenant_details office
    join public.profiles profile on profile.id = office.id
    where profile.role = 'subtenant' and office.is_active
      and public.cities_match(office.city, v_booking.municipality)
      and public.cities_match(office.province, v_booking.province)
  loop
    insert into public.notifications(
      user_id, booking_id, title, body, type, is_read, dedupe_key, data
    ) values (
      v_recipient, p_booking_id, 'Booking suspension case requires review',
      'Tourist cancellation offense #' || v_offense ||
        ' created a booking suspension case.',
      'booking_restriction_case', false,
      'tourist_suspension_case:' || v_case_id::text || ':' || v_recipient::text,
      jsonb_build_object('case_id', v_case_id, 'route', 'disputes_cases')
    ) on conflict (dedupe_key) where dedupe_key is not null do update
      set data = excluded.data, title = excluded.title, body = excluded.body;
  end loop;
  for v_recipient in
    select profile.id from public.profiles profile
    join public.provincial_office_details office on office.user_id = profile.id
    where profile.role = 'main_tenant'
      and public.cities_match(office.province, v_booking.province)
  loop
    insert into public.notifications(
      user_id, booking_id, title, body, type, is_read, dedupe_key, data
    ) values (
      v_recipient, p_booking_id, 'Province-wide suspension case',
      'Tourist cancellation offense #' || v_offense ||
        ' requires case review.',
      'booking_restriction_case', false,
      'tourist_suspension_case:' || v_case_id::text || ':' || v_recipient::text,
      jsonb_build_object('case_id', v_case_id, 'route', 'disputes_cases')
    ) on conflict (dedupe_key) where dedupe_key is not null do update
      set data = excluded.data, title = excluded.title, body = excluded.body;
  end loop;

  return v_result || jsonb_build_object(
    'booking_restriction_created', v_new_case,
    'booking_restriction_case_id', v_case_id,
    'booking_restricted_until', v_end,
    'booking_restriction_reason', v_reason,
    'booking_restriction_offense_number', v_offense,
    'booking_restriction_manual_review_required', v_manual,
    'booking_restriction_risk_level', v_risk
  );
end;
$$;
revoke all on function public.cancel_package_booking(uuid,text,text,text)
  from public, anon;
grant execute on function public.cancel_package_booking(uuid,text,text,text)
  to authenticated;

alter function public.appeal_tourist_booking_restriction(text)
  rename to appeal_tourist_booking_restriction_case_impl;
revoke all on function public.appeal_tourist_booking_restriction_case_impl(text)
  from public, anon, authenticated;

create function public.appeal_tourist_booking_restriction(p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_case uuid;
begin
  v_id := public.appeal_tourist_booking_restriction_case_impl(p_reason);
  select case_id into v_case from public.tourist_booking_restriction_appeals
    where id = v_id;
  update public.tourist_booking_suspension_cases
  set appeal_status = 'pending_review', case_status = 'under_review',
      updated_at = clock_timestamp()
  where case_id = v_case;
  insert into public.tourist_booking_suspension_events(
    case_id, actor_id, action, details
  ) values (v_case, auth.uid(), 'appeal_submitted', btrim(p_reason));
  return v_id;
end;
$$;
revoke all on function public.appeal_tourist_booking_restriction(text)
  from public, anon;
grant execute on function public.appeal_tourist_booking_restriction(text)
  to authenticated;

alter function public.review_tourist_booking_restriction_appeal(uuid,boolean,text)
  rename to review_tourist_booking_restriction_appeal_case_impl;
revoke all on function public.review_tourist_booking_restriction_appeal_case_impl(
  uuid,boolean,text) from public, anon, authenticated;

create function public.review_tourist_booking_restriction_appeal(
  p_appeal_id uuid, p_approve boolean, p_note text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_result jsonb; v_case uuid;
begin
  v_result := public.review_tourist_booking_restriction_appeal_case_impl(
    p_appeal_id, p_approve, p_note
  );
  v_case := (v_result->>'case_id')::uuid;
  update public.tourist_booking_suspension_cases
  set appeal_status = case when p_approve then 'approved' else 'rejected' end,
      restriction_status = case when p_approve then 'lifted'
        else restriction_status end,
      case_status = 'closed', resolution_note = nullif(btrim(coalesce(p_note,'')),''),
      resolved_at = clock_timestamp(), updated_at = clock_timestamp()
  where case_id = v_case;
  insert into public.tourist_booking_suspension_events(
    case_id, actor_id, action, details
  ) values (
    v_case, auth.uid(),
    case when p_approve then 'appeal_approved' else 'appeal_rejected' end,
    coalesce(nullif(btrim(coalesce(p_note,'')),''), 'Appeal decision recorded.')
  );
  return v_result;
end;
$$;
revoke all on function public.review_tourist_booking_restriction_appeal(
  uuid,boolean,text) from public, anon;
grant execute on function public.review_tourist_booking_restriction_appeal(
  uuid,boolean,text) to authenticated;

create or replace function public.administrator_review_booking_restriction_appeal(
  p_appeal_id uuid, p_approve boolean, p_note text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  return public.review_tourist_booking_restriction_appeal(
    p_appeal_id, p_approve, p_note
  );
end;
$$;

create function public.manage_tourist_booking_suspension_case(
  p_case_id uuid, p_action text, p_note text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_case public.tourist_booking_suspension_cases;
  v_hours integer;
  v_end timestamptz;
begin
  select * into v_case from public.tourist_booking_suspension_cases
  where case_id = p_case_id for update;
  if not found or not public.can_review_tourist_booking_suspension(
      v_case.municipality, v_case.province) then
    raise exception 'SUSPENSION_REVIEW_SCOPE_REQUIRED' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_note,''))) < 10 then
    raise exception 'DECISION_NOTE_REQUIRED' using errcode = '22023';
  end if;
  if p_action = 'start_review' then
    if v_case.case_status <> 'needs_review' then
      raise exception 'CASE_ALREADY_REVIEWED';
    end if;
    update public.tourist_booking_suspension_cases
    set case_status = 'under_review', updated_at = clock_timestamp()
    where case_id = p_case_id;
  elsif p_action = 'note' then
    if v_case.case_status = 'closed' then raise exception 'CASE_CLOSED'; end if;
    update public.tourist_booking_suspension_cases
    set updated_at = clock_timestamp() where case_id = p_case_id;
  elsif p_action = 'resolve' then
    if v_case.case_status = 'closed' then raise exception 'CASE_ALREADY_RESOLVED'; end if;
    update public.tourist_booking_suspension_cases
    set case_status = 'closed', resolution_note = btrim(p_note),
        resolved_at = clock_timestamp(), updated_at = clock_timestamp()
    where case_id = p_case_id;
  elsif p_action = 'escalate' then
    if not v_case.manual_review_required or v_case.manual_extension_used
       or v_case.restriction_status <> 'active'
       or v_case.ends_at <= clock_timestamp() then
      raise exception 'POLICY_EXTENSION_NOT_ALLOWED';
    end if;
    select further_offense_hours into v_hours
    from public.tourist_cancellation_protection_settings where id = true;
    v_end := greatest(v_case.ends_at, clock_timestamp() + make_interval(hours => v_hours));
    update public.tourist_booking_suspension_cases
    set ends_at = v_end, manual_extension_used = true,
        case_status = 'under_review', updated_at = clock_timestamp()
    where case_id = p_case_id;
    update public.tourist_booking_restrictions
    set restricted_until = v_end, updated_at = clock_timestamp()
    where case_id = p_case_id and status = 'active';
    insert into public.notifications(
      user_id, booking_id, title, body, type, is_read, dedupe_key, data
    ) values (
      v_case.tourist_id, v_case.source_booking_id,
      'Booking suspension extended after review',
      'Your repeat-offense suspension was extended until ' ||
        to_char(v_end at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM') || '.',
      'booking_restriction', false,
      'tourist_suspension_manual_extension:' || p_case_id::text,
      jsonb_build_object('case_id', p_case_id, 'route', 'tourist_suspension')
    ) on conflict (dedupe_key) where dedupe_key is not null do nothing;
  else
    raise exception 'INVALID_SUSPENSION_CASE_ACTION' using errcode = '22023';
  end if;
  insert into public.tourist_booking_suspension_events(
    case_id, actor_id, action, details
  ) values (p_case_id, auth.uid(), p_action, btrim(p_note));
  return jsonb_build_object('case_id', p_case_id, 'action', p_action,
    'ends_at', v_end);
end;
$$;
revoke all on function public.manage_tourist_booking_suspension_case(
  uuid,text,text) from public, anon;
grant execute on function public.manage_tourist_booking_suspension_case(
  uuid,text,text) to authenticated;

create or replace function public.get_my_tourist_booking_restriction()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'case_id', restriction.case_id, 'reason', restriction.reason,
    'starts_at', restriction.started_at, 'ends_at', restriction.restricted_until,
    'cancellation_count', restriction.cancellation_count,
    'offense_number', restriction.offense_number,
    'manual_review_required', restriction.manual_review_required,
    'risk_level', restriction.risk_level,
    'active', restriction.status = 'active'
      and restriction.restricted_until > clock_timestamp(),
    'status', case when restriction.status = 'lifted' then 'lifted'
      when restriction.restricted_until <= clock_timestamp() then 'expired'
      else restriction.status end,
    'appeal_status', case_record.appeal_status
  )
  from public.tourist_booking_restrictions restriction
  left join public.tourist_booking_suspension_cases case_record
    on case_record.case_id = restriction.case_id
  where restriction.tourist_id = auth.uid();
$$;

create or replace function public.get_tourist_booking_restriction_cases(
  p_case_id uuid default null
)
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', case_record.case_id,
    'municipality', case_record.municipality,
    'province', case_record.province,
    'booking_id', case_record.source_booking_id,
    'package_id', booking.package_id,
    'category', 'booking_suspension',
    'subject', 'Booking Suspension · Offense #' || case_record.offense_number,
    'description', case_record.reason,
    'priority', case when case_record.risk_level = 'high_risk' then 'urgent'
      else 'high' end,
    'status', case
      when case_record.restriction_status in ('lifted','expired','escalated')
        or case_record.ends_at <= clock_timestamp() then 'closed'
      else case_record.case_status end,
    'original_status', coalesce(case_record.appeal_status,
      case_record.restriction_status),
    'resolution_notes', case_record.resolution_note,
    'created_at', case_record.created_at,
    'reviewed_at', appeal.created_at,
    'resolved_at', case_record.resolved_at,
    'updated_at', case_record.updated_at,
    'reporter', jsonb_build_object(
      'id', tourist.id,
      'name', coalesce(nullif(tourist.full_name,''),
        nullif(trim(concat_ws(' ',tourist.first_name,tourist.last_name)),''),
        'Tourist'),
      'role', 'tourist', 'mobile', tourist.mobile
    ),
    'reported_user', null,
    'assignee', case when reviewer.id is null then null else jsonb_build_object(
      'id', reviewer.id, 'name', coalesce(nullif(reviewer.full_name,''),'Reviewer'),
      'role', reviewer.role) end,
    'booking', case when booking.id is null then null else jsonb_build_object(
      'id', booking.id, 'status', coalesce(booking.booking_status,booking.status),
      'travel_date', booking.travel_date) end,
    'tour_package', case when package.id is null then null else jsonb_build_object(
      'id',package.id,'title',package.title,'city',package.city) end,
    'evidence', '[]'::jsonb,
    'booking_history', coalesce((select jsonb_agg(jsonb_build_object(
      'booking_id', history.id, 'travel_date', history.travel_date,
      'booking_status', coalesce(history.booking_status,history.status),
      'cancelled_at', history.cancelled_at) order by history.cancelled_at)
      from public.package_bookings history
      where history.id = any(case_record.cancellation_booking_ids)), '[]'::jsonb),
    'timeline', coalesce((select jsonb_agg(jsonb_build_object(
      'label', replace(event.action,'_',' '), 'details', event.details,
      'at', event.created_at) order by event.created_at)
      from public.tourist_booking_suspension_events event
      where event.case_id = case_record.case_id), '[]'::jsonb),
    'restrictions', jsonb_build_array(jsonb_build_object(
      'id', case_record.case_id,
      'active', case_record.restriction_status = 'active'
        and case_record.ends_at > clock_timestamp(),
      'restriction_status', case when case_record.ends_at <= clock_timestamp()
        and case_record.restriction_status = 'active' then 'expired'
        else case_record.restriction_status end,
      'reason', case_record.reason, 'starts_at', case_record.starts_at,
      'ends_at', case_record.ends_at,
      'offense_number', case_record.offense_number,
      'cancellation_count', case_record.cancellation_count,
      'source_booking_ids', case_record.cancellation_booking_ids,
      'manual_review_required', case_record.manual_review_required,
      'manual_extension_used', case_record.manual_extension_used,
      'risk_level', case_record.risk_level,
      'previous_suspensions', coalesce((select jsonb_agg(jsonb_build_object(
        'case_id', previous.case_id, 'offense_number', previous.offense_number,
        'restriction_status', previous.restriction_status,
        'starts_at', previous.starts_at, 'ends_at', previous.ends_at)
        order by previous.starts_at desc)
        from public.tourist_booking_suspension_cases previous
        where previous.tourist_id = case_record.tourist_id
          and previous.case_id <> case_record.case_id
          and previous.starts_at < case_record.starts_at), '[]'::jsonb),
      'appeals', case when appeal.id is null then '[]'::jsonb else jsonb_build_array(
        jsonb_build_object('id',appeal.id,'reason',appeal.reason,
          'status',appeal.status,'decision_note',appeal.review_note,
          'created_at',appeal.created_at,'reviewed_at',appeal.reviewed_at)) end
    ))
  )
  from public.tourist_booking_suspension_cases case_record
  join public.profiles tourist on tourist.id = case_record.tourist_id
  left join lateral (select item.*
    from public.tourist_booking_restriction_appeals item
    where item.case_id = case_record.case_id
    order by item.created_at desc limit 1) appeal on true
  left join public.profiles reviewer on reviewer.id = appeal.reviewed_by
  left join public.package_bookings booking on booking.id = case_record.source_booking_id
  left join public.tour_packages package on package.id = booking.package_id
  where (p_case_id is null or case_record.case_id = p_case_id)
    and public.can_review_tourist_booking_suspension(
      case_record.municipality, case_record.province)
  order by case_record.created_at desc;
$$;

create function public.process_expired_tourist_booking_suspensions()
returns integer language plpgsql security definer set search_path = '' as $$
declare v_case public.tourist_booking_suspension_cases; v_count integer := 0;
begin
  for v_case in select * from public.tourist_booking_suspension_cases
    where restriction_status = 'active' and ends_at <= clock_timestamp()
    for update skip locked
  loop
    update public.tourist_booking_suspension_cases
    set restriction_status = 'expired', case_status = 'closed',
        resolved_at = coalesce(resolved_at, clock_timestamp()),
        resolution_note = coalesce(resolution_note, 'Suspension expired automatically.'),
        updated_at = clock_timestamp()
    where case_id = v_case.case_id;
    update public.tourist_booking_restrictions
    set status = 'expired', updated_at = clock_timestamp()
    where case_id = v_case.case_id and status = 'active';
    insert into public.tourist_booking_suspension_events(
      case_id, actor_id, action, details
    ) values (v_case.case_id, null, 'suspension_expired',
      'Booking privileges restored automatically at the scheduled expiry.');
    insert into public.notifications(
      user_id, booking_id, title, body, type, is_read, dedupe_key, data
    ) values (v_case.tourist_id, v_case.source_booking_id,
      'Booking suspension expired',
      'Your booking privileges have been restored.',
      'booking_restriction', false,
      'tourist_suspension_expired:' || v_case.case_id::text,
      jsonb_build_object('case_id',v_case.case_id,'route','tourist_suspension'))
    on conflict (dedupe_key) where dedupe_key is not null do nothing;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.process_expired_tourist_booking_suspensions()
  from public, anon, authenticated;

do $$ begin
  if exists(select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'touristrike-expire-booking-suspensions', '* * * * *',
      'select public.process_expired_tourist_booking_suspensions()'
    );
  else
    raise notice 'pg_cron unavailable: schedule process_expired_tourist_booking_suspensions every minute';
  end if;
exception when undefined_table or undefined_function then
  raise notice 'pg_cron unavailable: schedule process_expired_tourist_booking_suspensions every minute';
end $$;

create or replace function public.notification_destination(p_notification_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  n public.notifications;
  b public.package_bookings;
  v_activity uuid;
  v_case uuid;
  v_role text;
  v_suspension public.tourist_booking_suspension_cases;
begin
  select * into n from public.notifications
  where id::text = p_notification_id and user_id = auth.uid();
  if not found then return null; end if;
  v_role := public.current_profile_role();
  if n.data->>'case_id' is not null then
    begin v_case := (n.data->>'case_id')::uuid;
    exception when invalid_text_representation then v_case := null; end;
    if v_case is not null then
      select * into v_suspension
      from public.tourist_booking_suspension_cases where case_id = v_case;
      if found and v_role = 'tourist' and v_suspension.tourist_id = auth.uid() then
        return jsonb_build_object('screen','tourist_suspension','case_id',v_case);
      end if;
      if found and v_role = 'subtenant'
         and public.can_review_tourist_booking_suspension(
           v_suspension.municipality,v_suspension.province) then
        return jsonb_build_object('screen','subtenant_case','case_id',v_case);
      end if;
      if found and v_role = 'main_tenant'
         and public.can_review_tourist_booking_suspension(
           v_suspension.municipality,v_suspension.province) then
        return jsonb_build_object('screen','provincial_case','case_id',v_case);
      end if;
    end if;
  end if;
  if n.booking_id is null then
    return jsonb_build_object('screen','notifications');
  end if;
  select * into b from public.package_bookings where id = n.booking_id;
  if not found then return null; end if;
  if b.tourist_id = auth.uid() then
    return jsonb_build_object('screen','tourist_booking','booking_id',b.id);
  end if;
  if exists(select 1 from public.booking_drivers driver
      where driver.booking_id = b.id and driver.driver_id = auth.uid()
        and driver.status in ('accepted','completed')) then
    select id into v_activity from public.package_activities
      where booking_id = b.id limit 1;
    if v_activity is not null then
      return jsonb_build_object('screen','driver_tracking','activity_id',v_activity);
    end if;
    return jsonb_build_object('screen','driver_jobs');
  end if;
  if n.type in ('available_package_job','tour_assigned') and v_role = 'driver' then
    return jsonb_build_object('screen','driver_jobs');
  end if;
  return jsonb_build_object('screen','notifications');
end;
$$;
revoke all on function public.notification_destination(text) from public, anon;
grant execute on function public.notification_destination(text) to authenticated;

revoke all on function public.get_my_tourist_booking_restriction(),
  public.get_tourist_booking_restriction_cases(uuid) from public, anon;
grant execute on function public.get_my_tourist_booking_restriction(),
  public.get_tourist_booking_restriction_cases(uuid) to authenticated;

commit;
