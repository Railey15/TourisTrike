begin;

create table public.tourist_cancellation_protection_settings (
  id boolean primary key default true check (id),
  enabled boolean not null default true,
  rolling_days integer not null default 30 check (rolling_days between 1 and 365),
  restriction_threshold integer not null default 3
    check (restriction_threshold between 2 and 20),
  restriction_hours integer not null default 24
    check (restriction_hours between 1 and 168),
  updated_at timestamptz not null default now()
);
insert into public.tourist_cancellation_protection_settings(id) values(true);
revoke all on public.tourist_cancellation_protection_settings
  from public, anon, authenticated;

create table public.tourist_booking_restrictions (
  tourist_id uuid primary key references public.profiles(id) on delete cascade,
  restricted_until timestamptz not null,
  status text not null check (status in ('active', 'lifted')),
  source_booking_id uuid references public.package_bookings(id),
  reviewed_by uuid references public.profiles(id),
  review_note text,
  updated_at timestamptz not null default now()
);
alter table public.tourist_booking_restrictions enable row level security;
revoke all on public.tourist_booking_restrictions
  from public, anon, authenticated;
grant select on public.tourist_booking_restrictions to authenticated;
create policy tourist_reads_own_booking_restriction
on public.tourist_booking_restrictions for select to authenticated
using (tourist_id = auth.uid() or public.is_system_administrator());

create table public.tourist_booking_restriction_appeals (
  id uuid primary key default gen_random_uuid(),
  tourist_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (char_length(btrim(reason)) between 10 and 1000),
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
alter table public.tourist_booking_restriction_appeals enable row level security;
revoke all on public.tourist_booking_restriction_appeals
  from public, anon, authenticated;
grant select on public.tourist_booking_restriction_appeals to authenticated;
create policy tourist_reads_own_booking_appeals
on public.tourist_booking_restriction_appeals for select to authenticated
using (tourist_id = auth.uid() or public.is_system_administrator());

create table public.tourist_cancellation_exception_reviews (
  booking_id uuid primary key references public.package_bookings(id),
  approved_by uuid not null references public.profiles(id),
  approved_at timestamptz not null default now(),
  note text not null check (char_length(btrim(note)) between 10 and 1000)
);
alter table public.tourist_cancellation_exception_reviews enable row level security;
revoke all on public.tourist_cancellation_exception_reviews
  from public, anon, authenticated;
grant select on public.tourist_cancellation_exception_reviews to authenticated;
create policy reviewed_exception_visibility
on public.tourist_cancellation_exception_reviews for select to authenticated
using (public.is_system_administrator() or exists(
  select 1 from public.package_bookings b
  where b.id = booking_id and b.tourist_id = auth.uid()));

-- Count only tourist-initiated late cancellations after the established
-- cancellation RPC has applied its exceptional-case classification.
alter function public.cancel_package_booking(uuid,text,text,text)
  rename to cancel_package_booking_protection_impl;
revoke all on function public.cancel_package_booking_protection_impl(
  uuid,text,text,text) from public, anon, authenticated;
create function public.cancel_package_booking(
  p_booking_id uuid, p_reason text, p_note text default null,
  p_category text default 'general'
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_result jsonb;
  v_booking public.package_bookings;
  v_settings public.tourist_cancellation_protection_settings;
  v_count integer;
  v_until timestamptz;
begin
  v_result := public.cancel_package_booking_protection_impl(
    p_booking_id, p_reason, p_note, p_category);
  select * into v_booking from public.package_bookings
    where id = p_booking_id;
  select * into v_settings from public.tourist_cancellation_protection_settings
    where id = true;
  if not coalesce(v_settings.enabled, false)
     or v_booking.cancelled_by is distinct from auth.uid()
     or coalesce(v_booking.cancellation_type, '') not in ('late', 'exceptional') then
    return v_result;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_booking.tourist_id::text, 0));
  select count(*) into v_count from public.package_bookings b
  where b.tourist_id = v_booking.tourist_id
    and b.cancelled_by = b.tourist_id
    and b.cancellation_type in ('late', 'exceptional')
    and not exists(select 1 from public.tourist_cancellation_exception_reviews e
      where e.booking_id = b.id)
    and b.cancelled_at >= clock_timestamp()
      - make_interval(days => v_settings.rolling_days);
  if v_count = 1 then
    insert into public.notifications(user_id, booking_id, title, body,
      type, is_read, dedupe_key)
    values (v_booking.tourist_id, p_booking_id, 'Late cancellation warning',
      'Repeated late cancellations may temporarily limit new bookings. Existing bookings and support remain available.',
      'booking_cancellation_warning', false,
      'late_cancel_warning:' || p_booking_id::text)
    on conflict (dedupe_key) where dedupe_key is not null do nothing;
  elsif v_count = v_settings.restriction_threshold - 1 then
    insert into public.notifications(user_id, booking_id, title, body,
      type, is_read, dedupe_key)
    values (v_booking.tourist_id, p_booking_id, 'Final cancellation warning',
      'One more qualifying late cancellation in the rolling period may temporarily pause new bookings.',
      'booking_cancellation_warning', false,
      'late_cancel_final:' || p_booking_id::text)
    on conflict (dedupe_key) where dedupe_key is not null do nothing;
  elsif v_count >= v_settings.restriction_threshold then
    v_until := clock_timestamp()
      + make_interval(hours => v_settings.restriction_hours);
    insert into public.tourist_booking_restrictions(
      tourist_id, restricted_until, status, source_booking_id)
    values (v_booking.tourist_id, v_until, 'active', p_booking_id)
    on conflict (tourist_id) do update
      set restricted_until = greatest(
            public.tourist_booking_restrictions.restricted_until,
            excluded.restricted_until),
          status = 'active', source_booking_id = excluded.source_booking_id,
          reviewed_by = null, review_note = null,
          updated_at = clock_timestamp();
    insert into public.notifications(user_id, booking_id, title, body,
      type, is_read, dedupe_key)
    values (v_booking.tourist_id, p_booking_id, 'New bookings temporarily paused',
      'New bookings are temporarily paused. Your existing bookings, refunds, and support remain available. You may appeal this restriction.',
      'booking_restriction', false,
      'late_cancel_restriction:' || p_booking_id::text)
    on conflict (dedupe_key) where dedupe_key is not null do nothing;
  end if;
  return v_result || jsonb_build_object(
    'qualifying_late_cancellations', v_count,
    'booking_restricted_until', v_until);
end $$;
revoke all on function public.cancel_package_booking(uuid,text,text,text)
  from public, anon;
grant execute on function public.cancel_package_booking(uuid,text,text,text)
  to authenticated;

-- Wrap the existing atomic booking RPC. Its role, RLS and fare checks remain.
alter function public.create_package_booking(jsonb,jsonb,jsonb)
  rename to create_package_booking_restriction_impl;
revoke all on function public.create_package_booking_restriction_impl(
  jsonb,jsonb,jsonb) from public, anon, authenticated;
create function public.create_package_booking(
  p_booking jsonb,
  p_customized_spots jsonb default '[]'::jsonb,
  p_itinerary_items jsonb default '[]'::jsonb
) returns public.package_bookings language plpgsql security definer
set search_path = '' as $$
declare
  v_until timestamptz;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  select restricted_until into v_until
  from public.tourist_booking_restrictions
  where tourist_id = auth.uid() and status = 'active'
    and restricted_until > clock_timestamp();
  if v_until is not null then
    raise exception 'NEW_BOOKINGS_TEMPORARILY_RESTRICTED until %', v_until;
  end if;
  return public.create_package_booking_restriction_impl(
    p_booking, p_customized_spots, p_itinerary_items);
end $$;
revoke all on function public.create_package_booking(jsonb,jsonb,jsonb)
  from public, anon;
grant execute on function public.create_package_booking(jsonb,jsonb,jsonb)
  to authenticated;

create function public.appeal_tourist_booking_restriction(p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if auth.uid() is null or public.current_profile_role() <> 'tourist' then
    raise exception 'TOURIST_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 1000 then
    raise exception 'APPEAL_REASON_REQUIRED';
  end if;
  if not exists(select 1 from public.tourist_booking_restrictions r
    where r.tourist_id = auth.uid() and r.status = 'active'
      and r.restricted_until > clock_timestamp()) then
    raise exception 'NO_ACTIVE_BOOKING_RESTRICTION';
  end if;
  insert into public.tourist_booking_restriction_appeals(tourist_id, reason)
    values(auth.uid(), btrim(p_reason))
    on conflict (tourist_id) where status = 'pending' do nothing
    returning id into v_id;
  if v_id is null then
    select id into v_id from public.tourist_booking_restriction_appeals
      where tourist_id = auth.uid() and status = 'pending';
  end if;
  return v_id;
end $$;
revoke all on function public.appeal_tourist_booking_restriction(text)
  from public, anon;
grant execute on function public.appeal_tourist_booking_restriction(text)
  to authenticated;

create function public.administrator_review_booking_restriction_appeal(
  p_appeal_id uuid, p_approve boolean, p_note text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare a public.tourist_booking_restriction_appeals;
begin
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  select * into a from public.tourist_booking_restriction_appeals
    where id = p_appeal_id for update;
  if not found or a.status <> 'pending' then
    raise exception 'APPEAL_NOT_PENDING';
  end if;
  update public.tourist_booking_restriction_appeals
    set status = case when p_approve then 'approved' else 'declined' end,
        reviewed_at = clock_timestamp(), reviewed_by = auth.uid(),
        review_note = nullif(btrim(coalesce(p_note, '')), '')
    where id = a.id;
  if p_approve then
    update public.tourist_booking_restrictions
    set status = 'lifted', reviewed_by = auth.uid(),
        review_note = nullif(btrim(coalesce(p_note, '')), ''),
        updated_at = clock_timestamp()
    where tourist_id = a.tourist_id;
  end if;
  insert into public.notifications(user_id, title, body, type, is_read,
    dedupe_key) values(a.tourist_id, 'Booking appeal reviewed',
      case when p_approve then 'Your new-booking restriction has been lifted.'
        else 'Your appeal was reviewed. The current restriction remains until it expires.' end,
      'booking_restriction', false, 'appeal_review:' || a.id::text)
    on conflict (dedupe_key) where dedupe_key is not null do nothing;
  return jsonb_build_object('appeal_id', a.id,
    'status', case when p_approve then 'approved' else 'declined' end);
end $$;
revoke all on function public.administrator_review_booking_restriction_appeal(
  uuid,boolean,text) from public, anon;
grant execute on function public.administrator_review_booking_restriction_appeal(
  uuid,boolean,text) to authenticated;

create function public.administrator_approve_cancellation_exception(
  p_booking_id uuid, p_note text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  b public.package_bookings;
  s public.tourist_cancellation_protection_settings;
  v_count integer;
begin
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_note, ''))) not between 10 and 1000 then
    raise exception 'REVIEW_NOTE_REQUIRED';
  end if;
  select * into b from public.package_bookings where id = p_booking_id;
  if not found or b.cancelled_by is distinct from b.tourist_id
     or b.cancellation_type <> 'exceptional' then
    raise exception 'EXCEPTION_REVIEW_NOT_APPLICABLE';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(b.tourist_id::text, 0));
  insert into public.tourist_cancellation_exception_reviews(
    booking_id, approved_by, note)
    values(p_booking_id, auth.uid(), btrim(p_note))
    on conflict (booking_id) do nothing;
  select * into s from public.tourist_cancellation_protection_settings
    where id = true;
  select count(*) into v_count from public.package_bookings x
  where x.tourist_id = b.tourist_id and x.cancelled_by = x.tourist_id
    and x.cancellation_type in ('late', 'exceptional')
    and x.cancelled_at >= clock_timestamp()
      - make_interval(days => s.rolling_days)
    and not exists(select 1 from public.tourist_cancellation_exception_reviews e
      where e.booking_id = x.id);
  if v_count < s.restriction_threshold then
    update public.tourist_booking_restrictions
    set status = 'lifted', reviewed_by = auth.uid(),
        review_note = 'Approved cancellation exception: ' || btrim(p_note),
        updated_at = clock_timestamp()
    where tourist_id = b.tourist_id and status = 'active';
  end if;
  return jsonb_build_object('booking_id', p_booking_id,
    'qualifying_late_cancellations', v_count);
end $$;
revoke all on function public.administrator_approve_cancellation_exception(uuid,text)
  from public, anon;
grant execute on function public.administrator_approve_cancellation_exception(uuid,text)
  to authenticated;

commit;
