-- Exact tourist cancellation protection: three tourist-initiated cancellations
-- on the same Asia/Manila calendar day suspend only new-booking privileges for
-- three days. Appeals are exposed through the existing case-management UI.
begin;

update public.tourist_cancellation_protection_settings
set enabled = true,
    rolling_days = 1,
    restriction_threshold = 3,
    restriction_hours = 72,
    updated_at = now()
where id = true;

alter table public.tourist_booking_restrictions
  add column if not exists case_id uuid default gen_random_uuid(),
  add column if not exists started_at timestamptz,
  add column if not exists reason text,
  add column if not exists cancellation_count integer,
  add column if not exists source text,
  add column if not exists cancellation_booking_ids uuid[],
  add column if not exists municipality text,
  add column if not exists province text;

update public.tourist_booking_restrictions restriction
set case_id = coalesce(restriction.case_id, gen_random_uuid()),
    started_at = coalesce(restriction.started_at, restriction.updated_at, now()),
    reason = coalesce(
      nullif(restriction.reason, ''),
      'Repeated tourist-initiated booking cancellations.'
    ),
    cancellation_count = coalesce(restriction.cancellation_count, 3),
    source = coalesce(nullif(restriction.source, ''), 'legacy_cancellation_protection'),
    cancellation_booking_ids = coalesce(
      restriction.cancellation_booking_ids,
      case when restriction.source_booking_id is null
        then '{}'::uuid[] else array[restriction.source_booking_id] end
    ),
    municipality = coalesce(restriction.municipality, booking.municipality),
    province = coalesce(restriction.province, booking.province)
from public.package_bookings booking
where booking.id = restriction.source_booking_id;

update public.tourist_booking_restrictions
set case_id = coalesce(case_id, gen_random_uuid()),
    started_at = coalesce(started_at, updated_at, now()),
    reason = coalesce(nullif(reason, ''), 'Repeated tourist-initiated booking cancellations.'),
    cancellation_count = coalesce(cancellation_count, 3),
    source = coalesce(nullif(source, ''), 'legacy_cancellation_protection'),
    cancellation_booking_ids = coalesce(cancellation_booking_ids, '{}'::uuid[]);

alter table public.tourist_booking_restrictions
  alter column case_id set not null,
  alter column started_at set not null,
  alter column reason set not null,
  alter column cancellation_count set not null,
  alter column source set not null,
  alter column cancellation_booking_ids set not null;

create unique index if not exists tourist_booking_restrictions_case_id_idx
  on public.tourist_booking_restrictions(case_id);

alter table public.tourist_booking_restriction_appeals
  add column if not exists case_id uuid,
  add column if not exists municipality text,
  add column if not exists province text,
  add column if not exists source_booking_id uuid,
  add column if not exists suspension_reason text,
  add column if not exists cancellation_count integer,
  add column if not exists cancellation_booking_ids uuid[],
  add column if not exists suspension_started_at timestamptz,
  add column if not exists suspension_ends_at timestamptz;

update public.tourist_booking_restriction_appeals appeal
set case_id = coalesce(appeal.case_id, restriction.case_id),
    municipality = coalesce(appeal.municipality, restriction.municipality),
    province = coalesce(appeal.province, restriction.province),
    source_booking_id = coalesce(appeal.source_booking_id, restriction.source_booking_id),
    suspension_reason = coalesce(appeal.suspension_reason, restriction.reason),
    cancellation_count = coalesce(appeal.cancellation_count, restriction.cancellation_count),
    cancellation_booking_ids = coalesce(
      appeal.cancellation_booking_ids,
      restriction.cancellation_booking_ids
    ),
    suspension_started_at = coalesce(appeal.suspension_started_at, restriction.started_at),
    suspension_ends_at = coalesce(appeal.suspension_ends_at, restriction.restricted_until)
from public.tourist_booking_restrictions restriction
where restriction.tourist_id = appeal.tourist_id;

update public.tourist_booking_restriction_appeals
set case_id = coalesce(case_id, gen_random_uuid()),
    suspension_reason = coalesce(
      nullif(suspension_reason, ''),
      'Repeated tourist-initiated booking cancellations.'
    ),
    cancellation_count = coalesce(cancellation_count, 3),
    cancellation_booking_ids = coalesce(cancellation_booking_ids, '{}'::uuid[]),
    suspension_started_at = coalesce(suspension_started_at, created_at),
    suspension_ends_at = coalesce(suspension_ends_at, created_at + interval '3 days');

alter table public.tourist_booking_restriction_appeals
  alter column case_id set not null,
  alter column suspension_reason set not null,
  alter column cancellation_count set not null,
  alter column cancellation_booking_ids set not null,
  alter column suspension_started_at set not null,
  alter column suspension_ends_at set not null;

drop index if exists public.one_pending_booking_appeal;
alter table public.tourist_booking_restriction_appeals
  drop constraint if exists tourist_booking_restriction_appeals_status_check;
update public.tourist_booking_restriction_appeals
set status = case status
  when 'pending' then 'pending_review'
  when 'declined' then 'rejected'
  else status
end;
alter table public.tourist_booking_restriction_appeals
  alter column status set default 'pending_review',
  add constraint tourist_booking_restriction_appeals_status_check
    check (status in ('pending_review', 'approved', 'rejected'));
create unique index tourist_booking_restriction_one_pending_case_idx
  on public.tourist_booking_restriction_appeals(case_id)
  where status = 'pending_review';

create or replace function public.can_review_tourist_booking_suspension(
  p_municipality text,
  p_province text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and (
    public.is_system_administrator()
    or public.is_municipal_complaint_officer(p_municipality, p_province)
    or (
      public.is_main_tenant()
      and exists (
        select 1
        from public.provincial_office_details office
        where office.user_id = auth.uid()
          and public.cities_match(office.province, p_province)
      )
    )
  );
$$;
revoke all on function public.can_review_tourist_booking_suspension(text, text)
  from public, anon;
grant execute on function public.can_review_tourist_booking_suspension(text, text)
  to authenticated;

create or replace function public.cancel_package_booking(
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
  v_count integer := 0;
  v_booking_ids uuid[] := '{}'::uuid[];
  v_restriction public.tourist_booking_restrictions;
  v_case_id uuid;
  v_started_at timestamptz;
  v_until timestamptz;
  v_created boolean := false;
  v_recipient uuid;
  v_reason constant text :=
    'Three tourist-initiated bookings were cancelled on the same calendar day.';
begin
  v_result := public.cancel_package_booking_protection_impl(
    p_booking_id, p_reason, p_note, p_category
  );

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id;

  if not found
     or v_booking.tourist_id is null
     or v_booking.cancelled_by is distinct from v_booking.tourist_id
     or coalesce(v_booking.cancellation_party, '') <> 'tourist'
     or v_booking.cancelled_at is null then
    return v_result;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_booking.tourist_id::text, 0)
  );

  select count(*)::integer, coalesce(array_agg(booking.id order by booking.cancelled_at), '{}'::uuid[])
  into v_count, v_booking_ids
  from public.package_bookings booking
  where booking.tourist_id = v_booking.tourist_id
    and booking.cancelled_by = booking.tourist_id
    and booking.cancellation_party = 'tourist'
    and booking.cancelled_at is not null
    and lower(coalesce(booking.booking_status, booking.status, '')) = 'cancelled'
    and (booking.cancelled_at at time zone 'Asia/Manila')::date =
        (clock_timestamp() at time zone 'Asia/Manila')::date
    and not exists (
      select 1
      from public.tourist_cancellation_exception_reviews exception_review
      where exception_review.booking_id = booking.id
    );

  if v_count = 1 then
    insert into public.notifications(
      user_id, booking_id, title, body, type, is_read, dedupe_key, data
    ) values (
      v_booking.tourist_id, p_booking_id, 'Cancellation recorded',
      'Three tourist-initiated cancellations in one day will temporarily suspend new booking privileges.',
      'booking_cancellation_warning', false,
      'same_day_cancel_warning:' || p_booking_id::text,
      jsonb_build_object('cancellation_count', v_count)
    ) on conflict (dedupe_key) where dedupe_key is not null do nothing;
  elsif v_count = 2 then
    insert into public.notifications(
      user_id, booking_id, title, body, type, is_read, dedupe_key, data
    ) values (
      v_booking.tourist_id, p_booking_id, 'Final cancellation warning',
      'One more tourist-initiated cancellation today will suspend new booking privileges for 3 days.',
      'booking_cancellation_warning', false,
      'same_day_cancel_final:' || p_booking_id::text,
      jsonb_build_object('cancellation_count', v_count)
    ) on conflict (dedupe_key) where dedupe_key is not null do nothing;
  elsif v_count >= 3 then
    select * into v_restriction
    from public.tourist_booking_restrictions
    where tourist_id = v_booking.tourist_id
    for update;

    if found
       and v_restriction.status = 'active'
       and v_restriction.restricted_until > clock_timestamp() then
      v_case_id := v_restriction.case_id;
      v_started_at := v_restriction.started_at;
      v_until := v_restriction.restricted_until;
    else
      v_case_id := gen_random_uuid();
      v_started_at := clock_timestamp();
      v_until := v_started_at + interval '3 days';
      v_created := true;

      insert into public.tourist_booking_restrictions(
        tourist_id, case_id, restricted_until, status, source_booking_id,
        started_at, reason, cancellation_count, source,
        cancellation_booking_ids, municipality, province,
        reviewed_by, review_note, updated_at
      ) values (
        v_booking.tourist_id, v_case_id, v_until, 'active', p_booking_id,
        v_started_at, v_reason, v_count, 'same_day_tourist_cancellations',
        v_booking_ids, v_booking.municipality, v_booking.province,
        null, null, clock_timestamp()
      ) on conflict (tourist_id) do update set
        case_id = excluded.case_id,
        restricted_until = excluded.restricted_until,
        status = 'active',
        source_booking_id = excluded.source_booking_id,
        started_at = excluded.started_at,
        reason = excluded.reason,
        cancellation_count = excluded.cancellation_count,
        source = excluded.source,
        cancellation_booking_ids = excluded.cancellation_booking_ids,
        municipality = excluded.municipality,
        province = excluded.province,
        reviewed_by = null,
        review_note = null,
        updated_at = clock_timestamp();

      insert into public.notifications(
        user_id, booking_id, title, body, type, is_read, dedupe_key, data
      ) values (
        v_booking.tourist_id, p_booking_id,
        'Booking privileges suspended for 3 days',
        'Your booking privileges have been temporarily suspended for 3 days because 3 bookings were cancelled today. The suspension ends ' ||
          to_char(v_until at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM') || '.',
        'booking_restriction', false,
        'tourist_auto_suspension:' || v_case_id::text || ':' || v_booking.tourist_id::text,
        jsonb_build_object(
          'case_id', v_case_id,
          'route', 'disputes_cases',
          'restricted_until', v_until,
          'cancellation_count', v_count
        )
      ) on conflict (dedupe_key) where dedupe_key is not null do nothing;

      for v_recipient in
        select office.id
        from public.subtenant_details office
        join public.profiles profile on profile.id = office.id
        where profile.role = 'subtenant'
          and office.is_active
          and public.cities_match(office.city, v_booking.municipality)
          and public.cities_match(office.province, v_booking.province)
      loop
        insert into public.notifications(
          user_id, booking_id, title, body, type, is_read, dedupe_key, data
        ) values (
          v_recipient, p_booking_id, 'Tourist automatically suspended',
          'Tourist automatically suspended after 3 same-day booking cancellations.',
          'booking_restriction_case', false,
          'tourist_auto_suspension:' || v_case_id::text || ':' || v_recipient::text,
          jsonb_build_object('case_id', v_case_id, 'route', 'disputes_cases')
        ) on conflict (dedupe_key) where dedupe_key is not null do nothing;
      end loop;

      for v_recipient in
        select profile.id
        from public.profiles profile
        left join public.provincial_office_details office
          on office.user_id = profile.id
        where profile.role = 'main_tenant'
          and (
            office.user_id is null
            or public.cities_match(office.province, v_booking.province)
          )
      loop
        insert into public.notifications(
          user_id, booking_id, title, body, type, is_read, dedupe_key, data
        ) values (
          v_recipient, p_booking_id, 'Tourist automatically suspended',
          'Tourist automatically suspended after 3 same-day booking cancellations.',
          'booking_restriction_case', false,
          'tourist_auto_suspension:' || v_case_id::text || ':' || v_recipient::text,
          jsonb_build_object('case_id', v_case_id, 'route', 'disputes_cases')
        ) on conflict (dedupe_key) where dedupe_key is not null do nothing;
      end loop;
    end if;
  end if;

  return v_result || jsonb_build_object(
    'qualifying_cancellations_today', v_count,
    'booking_restriction_created', v_created,
    'booking_restricted_until', v_until,
    'booking_restriction_case_id', v_case_id,
    'booking_restriction_reason', case when v_case_id is null then null else v_reason end
  );
end;
$$;
revoke all on function public.cancel_package_booking(uuid, text, text, text)
  from public, anon;
grant execute on function public.cancel_package_booking(uuid, text, text, text)
  to authenticated;

create or replace function public.get_my_tourist_booking_restriction()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'case_id', restriction.case_id,
    'reason', restriction.reason,
    'starts_at', restriction.started_at,
    'ends_at', restriction.restricted_until,
    'cancellation_count', restriction.cancellation_count,
    'source', restriction.source,
    'active', restriction.status = 'active'
      and restriction.restricted_until > clock_timestamp(),
    'status', case
      when restriction.status = 'lifted' then 'lifted'
      when restriction.restricted_until <= clock_timestamp() then 'expired'
      else restriction.status
    end,
    'appeal_status', appeal.status
  )
  from public.tourist_booking_restrictions restriction
  left join lateral (
    select item.status
    from public.tourist_booking_restriction_appeals item
    where item.case_id = restriction.case_id
    order by item.created_at desc
    limit 1
  ) appeal on true
  where restriction.tourist_id = auth.uid();
$$;
revoke all on function public.get_my_tourist_booking_restriction()
  from public, anon;
grant execute on function public.get_my_tourist_booking_restriction()
  to authenticated;

create or replace function public.appeal_tourist_booking_restriction(
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restriction public.tourist_booking_restrictions;
  v_id uuid;
  v_recipient uuid;
begin
  if auth.uid() is null or public.current_profile_role() <> 'tourist' then
    raise exception 'TOURIST_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 1000 then
    raise exception 'APPEAL_REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into v_restriction
  from public.tourist_booking_restrictions
  where tourist_id = auth.uid()
  for update;

  if not found
     or v_restriction.status <> 'active'
     or v_restriction.restricted_until <= clock_timestamp() then
    raise exception 'NO_ACTIVE_BOOKING_RESTRICTION';
  end if;

  if exists (
    select 1
    from public.tourist_booking_restriction_appeals appeal
    where appeal.case_id = v_restriction.case_id
  ) then
    raise exception 'APPEAL_ALREADY_SUBMITTED' using errcode = '23505';
  end if;

  insert into public.tourist_booking_restriction_appeals(
    tourist_id, case_id, reason, status, municipality, province,
    source_booking_id, suspension_reason, cancellation_count,
    cancellation_booking_ids, suspension_started_at, suspension_ends_at
  ) values (
    auth.uid(), v_restriction.case_id, btrim(p_reason), 'pending_review',
    v_restriction.municipality, v_restriction.province,
    v_restriction.source_booking_id, v_restriction.reason,
    v_restriction.cancellation_count, v_restriction.cancellation_booking_ids,
    v_restriction.started_at, v_restriction.restricted_until
  ) on conflict (case_id) where status = 'pending_review' do nothing
  returning id into v_id;

  if v_id is null then
    raise exception 'APPEAL_ALREADY_SUBMITTED' using errcode = '23505';
  end if;

  insert into public.notifications(
    user_id, booking_id, title, body, type, is_read, dedupe_key, data
  ) values (
    auth.uid(), v_restriction.source_booking_id,
    'Suspension appeal submitted',
    'Your appeal was submitted and is pending review.',
    'booking_restriction_appeal', false,
    'tourist_suspension_appeal_received:' || v_id::text || ':' || auth.uid()::text,
    jsonb_build_object('case_id', v_restriction.case_id, 'route', 'disputes_cases')
  ) on conflict (dedupe_key) where dedupe_key is not null do nothing;

  for v_recipient in
    select office.id
    from public.subtenant_details office
    join public.profiles profile on profile.id = office.id
    where profile.role = 'subtenant'
      and office.is_active
      and public.cities_match(office.city, v_restriction.municipality)
      and public.cities_match(office.province, v_restriction.province)
  loop
    insert into public.notifications(
      user_id, booking_id, title, body, type, is_read, dedupe_key, data
    ) values (
      v_recipient, v_restriction.source_booking_id,
      'Suspension appeal submitted',
      'Suspended tourist submitted an appeal for review.',
      'booking_restriction_appeal', false,
      'tourist_suspension_appeal:' || v_id::text || ':' || v_recipient::text,
      jsonb_build_object('case_id', v_restriction.case_id, 'route', 'disputes_cases')
    ) on conflict (dedupe_key) where dedupe_key is not null do nothing;
  end loop;

  for v_recipient in
    select profile.id
    from public.profiles profile
    left join public.provincial_office_details office
      on office.user_id = profile.id
    where profile.role = 'main_tenant'
      and (
        office.user_id is null
        or public.cities_match(office.province, v_restriction.province)
      )
  loop
    insert into public.notifications(
      user_id, booking_id, title, body, type, is_read, dedupe_key, data
    ) values (
      v_recipient, v_restriction.source_booking_id,
      'Suspension appeal submitted',
      'Suspended tourist submitted an appeal for review.',
      'booking_restriction_appeal', false,
      'tourist_suspension_appeal:' || v_id::text || ':' || v_recipient::text,
      jsonb_build_object('case_id', v_restriction.case_id, 'route', 'disputes_cases')
    ) on conflict (dedupe_key) where dedupe_key is not null do nothing;
  end loop;

  return v_id;
end;
$$;
revoke all on function public.appeal_tourist_booking_restriction(text)
  from public, anon;
grant execute on function public.appeal_tourist_booking_restriction(text)
  to authenticated;

create or replace function public.review_tourist_booking_restriction_appeal(
  p_appeal_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_appeal public.tourist_booking_restriction_appeals;
  v_restriction public.tourist_booking_restrictions;
begin
  select * into v_appeal
  from public.tourist_booking_restriction_appeals
  where id = p_appeal_id
  for update;

  if not found or v_appeal.status <> 'pending_review' then
    raise exception 'APPEAL_NOT_PENDING';
  end if;
  if p_approve is null then
    raise exception 'APPEAL_DECISION_REQUIRED' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_note, '')), '') is not null
     and char_length(btrim(p_note)) < 10 then
    raise exception 'APPEAL_DECISION_NOTE_TOO_SHORT' using errcode = '22023';
  end if;
  if not public.can_review_tourist_booking_suspension(
      v_appeal.municipality, v_appeal.province) then
    raise exception 'SUSPENSION_REVIEW_SCOPE_REQUIRED' using errcode = '42501';
  end if;

  select * into v_restriction
  from public.tourist_booking_restrictions
  where tourist_id = v_appeal.tourist_id
    and case_id = v_appeal.case_id
  for update;

  update public.tourist_booking_restriction_appeals
  set status = case when p_approve then 'approved' else 'rejected' end,
      reviewed_at = clock_timestamp(),
      reviewed_by = auth.uid(),
      review_note = nullif(btrim(coalesce(p_note, '')), '')
  where id = v_appeal.id
    and status = 'pending_review';

  if not found then
    raise exception 'APPEAL_NOT_PENDING';
  end if;

  if p_approve and v_restriction.tourist_id is not null then
    update public.tourist_booking_restrictions
    set status = 'lifted',
        reviewed_by = auth.uid(),
        review_note = coalesce(
          nullif(btrim(coalesce(p_note, '')), ''),
          'Suspension appeal approved.'
        ),
        updated_at = clock_timestamp()
    where tourist_id = v_appeal.tourist_id
      and case_id = v_appeal.case_id
      and status = 'active';
  end if;

  insert into public.notifications(
    user_id, booking_id, title, body, type, is_read, dedupe_key, data
  ) values (
    v_appeal.tourist_id, v_appeal.source_booking_id,
    'Booking suspension appeal decision',
    case when p_approve
      then 'Your appeal was approved. Your booking privileges have been restored immediately.'
      else 'Your appeal was rejected. The original suspension remains active until its scheduled expiry.'
    end,
    'booking_restriction_appeal', false,
    'tourist_suspension_appeal_decision:' || v_appeal.id::text,
    jsonb_build_object(
      'case_id', v_appeal.case_id,
      'route', 'disputes_cases',
      'decision', case when p_approve then 'approved' else 'rejected' end
    )
  ) on conflict (dedupe_key) where dedupe_key is not null do nothing;

  return jsonb_build_object(
    'appeal_id', v_appeal.id,
    'case_id', v_appeal.case_id,
    'status', case when p_approve then 'approved' else 'rejected' end,
    'restriction_lifted', p_approve
  );
end;
$$;
revoke all on function public.review_tourist_booking_restriction_appeal(
  uuid, boolean, text
) from public, anon;
grant execute on function public.review_tourist_booking_restriction_appeal(
  uuid, boolean, text
) to authenticated;

create or replace function public.administrator_review_booking_restriction_appeal(
  p_appeal_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  return public.review_tourist_booking_restriction_appeal(
    p_appeal_id, p_approve, p_note
  );
end;
$$;
revoke all on function public.administrator_review_booking_restriction_appeal(
  uuid, boolean, text
) from public, anon;
grant execute on function public.administrator_review_booking_restriction_appeal(
  uuid, boolean, text
) to authenticated;

create or replace function public.get_tourist_booking_restriction_cases(
  p_case_id uuid default null
)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', restriction.case_id,
    'municipality', restriction.municipality,
    'province', restriction.province,
    'booking_id', restriction.source_booking_id,
    'package_id', booking.package_id,
    'category', 'tourist',
    'subject', 'Automatic booking suspension',
    'description', restriction.reason,
    'priority', 'high',
    'status', case
      when restriction.restricted_until <= clock_timestamp()
        or restriction.status = 'lifted'
        or appeal.status in ('approved', 'rejected') then 'closed'
      when appeal.status = 'pending_review' then 'under_review'
      else 'needs_review'
    end,
    'original_status', case
      when appeal.status is not null then appeal.status
      when restriction.restricted_until <= clock_timestamp() then 'expired'
      else restriction.status
    end,
    'resolution_notes', coalesce(appeal.review_note, restriction.review_note),
    'created_at', restriction.started_at,
    'reviewed_at', appeal.created_at,
    'resolved_at', appeal.reviewed_at,
    'updated_at', greatest(restriction.updated_at, coalesce(appeal.reviewed_at, appeal.created_at, restriction.updated_at)),
    'reporter', jsonb_build_object(
      'id', tourist.id,
      'name', coalesce(
        nullif(tourist.full_name, ''),
        nullif(trim(concat_ws(' ', tourist.first_name, tourist.last_name)), ''),
        'Tourist'
      ),
      'role', 'tourist',
      'mobile', tourist.mobile
    ),
    'reported_user', null,
    'assignee', case when reviewer.id is null then null else jsonb_build_object(
      'id', reviewer.id,
      'name', coalesce(nullif(reviewer.full_name, ''), 'Tourism officer'),
      'role', reviewer.role
    ) end,
    'booking', case when booking.id is null then null else jsonb_build_object(
      'id', booking.id,
      'status', coalesce(booking.booking_status, booking.status),
      'travel_date', booking.travel_date
    ) end,
    'tour_package', case when package.id is null then null else jsonb_build_object(
      'id', package.id,
      'title', package.title,
      'city', package.city
    ) end,
    'evidence', '[]'::jsonb,
    'booking_history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'booking_id', history.id,
        'travel_date', history.travel_date,
        'booking_status', coalesce(history.booking_status, history.status),
        'cancelled_at', history.cancelled_at
      ) order by history.cancelled_at)
      from public.package_bookings history
      where history.id = any(restriction.cancellation_booking_ids)
    ), '[]'::jsonb),
    'timeline', jsonb_build_array(
      jsonb_build_object(
        'label', 'Automatic suspension applied',
        'details', restriction.cancellation_count || ' same-day tourist cancellations',
        'at', restriction.started_at
      ),
      case when appeal.id is null then null else jsonb_build_object(
        'label', 'Appeal submitted',
        'details', appeal.reason,
        'at', appeal.created_at
      ) end,
      case when appeal.reviewed_at is null then null else jsonb_build_object(
        'label', 'Appeal ' || replace(appeal.status, '_', ' '),
        'details', coalesce(appeal.review_note, 'Decision recorded'),
        'at', appeal.reviewed_at
      ) end
    ),
    'restrictions', jsonb_build_array(jsonb_build_object(
      'id', restriction.case_id,
      'active', restriction.status = 'active'
        and restriction.restricted_until > clock_timestamp(),
      'reason', restriction.reason,
      'starts_at', restriction.started_at,
      'ends_at', restriction.restricted_until,
      'cancellation_count', restriction.cancellation_count,
      'source_booking_ids', restriction.cancellation_booking_ids,
      'appeals', case when appeal.id is null then '[]'::jsonb else jsonb_build_array(
        jsonb_build_object(
          'id', appeal.id,
          'reason', appeal.reason,
          'status', appeal.status,
          'decision_note', appeal.review_note,
          'created_at', appeal.created_at,
          'reviewed_at', appeal.reviewed_at
        )
      ) end
    ))
  )
  from public.tourist_booking_restrictions restriction
  join public.profiles tourist on tourist.id = restriction.tourist_id
  left join lateral (
    select item.*
    from public.tourist_booking_restriction_appeals item
    where item.case_id = restriction.case_id
    order by item.created_at desc
    limit 1
  ) appeal on true
  left join public.profiles reviewer on reviewer.id = appeal.reviewed_by
  left join public.package_bookings booking
    on booking.id = restriction.source_booking_id
  left join public.tour_packages package on package.id = booking.package_id
  where (p_case_id is null or restriction.case_id = p_case_id)
    and public.can_review_tourist_booking_suspension(
      restriction.municipality, restriction.province
    )
  order by restriction.started_at desc;
$$;
revoke all on function public.get_tourist_booking_restriction_cases(uuid)
  from public, anon;
grant execute on function public.get_tourist_booking_restriction_cases(uuid)
  to authenticated;

commit;
