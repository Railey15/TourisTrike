-- Booking-scoped Tourist/Driver complaints and MTO-only, reviewable
-- restrictions. No complaint submission changes account eligibility.
begin;

create table public.municipal_complaints (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.package_bookings(id) on delete restrict,
  municipality text not null,
  province text not null,
  reporter_id uuid not null references public.profiles(id) on delete restrict,
  reported_user_id uuid not null references public.profiles(id) on delete restrict,
  reported_role text not null check (reported_role in ('tourist','driver')),
  category text not null check (category in
    ('safety','conduct','service','payment','other')),
  description text not null check (char_length(btrim(description)) between 20 and 2000),
  status text not null default 'submitted' check (status in
    ('submitted','under_investigation','resolved','dismissed')),
  investigator_id uuid references public.profiles(id),
  investigation_notes text,
  findings text,
  resolution_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  decided_at timestamptz,
  check (reporter_id <> reported_user_id)
);
create index municipal_complaints_office_idx on public.municipal_complaints
  (lower(municipality),lower(province),status,created_at desc);
create index municipal_complaints_parties_idx on public.municipal_complaints
  (reporter_id,reported_user_id,created_at desc);
create unique index municipal_complaints_one_open_case_idx
  on public.municipal_complaints (booking_id,reporter_id,reported_user_id)
  where status in ('submitted','under_investigation');

create table public.municipal_complaint_events (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null references public.municipal_complaints(id) on delete restrict,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  action text not null check (action in
    ('submitted','investigation_started','note_added','warning_issued',
     'resolved','dismissed','suspended','lifted','appeal_submitted',
     'appeal_upheld','appeal_granted')),
  details text not null,
  created_at timestamptz not null default now()
);
create index municipal_complaint_events_case_idx
  on public.municipal_complaint_events(complaint_id,created_at);

create table public.municipal_complaint_evidence (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null references public.municipal_complaints(id) on delete restrict,
  storage_path text not null unique,
  file_name text not null,
  content_type text not null,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.municipal_booking_restrictions (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null references public.municipal_complaints(id) on delete restrict,
  account_id uuid not null references public.profiles(id) on delete restrict,
  account_role text not null check (account_role in ('tourist','driver')),
  municipality text not null,
  province text not null,
  reason text not null check (char_length(btrim(reason)) between 20 and 1000),
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null check (ends_at > starts_at),
  imposed_by uuid not null references public.profiles(id) on delete restrict,
  lifted_at timestamptz,
  lifted_by uuid references public.profiles(id),
  lift_note text,
  created_at timestamptz not null default now()
);
create index municipal_booking_restrictions_active_idx
  on public.municipal_booking_restrictions(account_id,municipality,province,ends_at)
  where lifted_at is null;

create table public.municipal_restriction_appeals (
  id uuid primary key default gen_random_uuid(),
  restriction_id uuid not null references public.municipal_booking_restrictions(id)
    on delete restrict,
  account_id uuid not null references public.profiles(id) on delete restrict,
  reason text not null check (char_length(btrim(reason)) between 20 and 2000),
  status text not null default 'pending' check (status in
    ('pending','upheld','granted')),
  decision_note text,
  reviewed_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create unique index municipal_restriction_one_pending_appeal_idx
  on public.municipal_restriction_appeals(restriction_id)
  where status = 'pending';

alter table public.municipal_complaints enable row level security;
alter table public.municipal_complaint_events enable row level security;
alter table public.municipal_complaint_evidence enable row level security;
alter table public.municipal_booking_restrictions enable row level security;
alter table public.municipal_restriction_appeals enable row level security;
revoke all on public.municipal_complaints from public,anon,authenticated;
revoke all on public.municipal_complaint_events from public,anon,authenticated;
revoke all on public.municipal_complaint_evidence from public,anon,authenticated;
revoke all on public.municipal_booking_restrictions from public,anon,authenticated;
revoke all on public.municipal_restriction_appeals from public,anon,authenticated;

create function public.is_municipal_complaint_officer(p_city text,p_province text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from public.profiles p
    join public.subtenant_details office on office.id=p.id
    where p.id=auth.uid() and p.role='subtenant' and office.is_active
      and public.cities_match(office.city,p_city)
      and public.cities_match(office.province,p_province));
$$;
revoke all on function public.is_municipal_complaint_officer(text,text)
  from public,anon;
grant execute on function public.is_municipal_complaint_officer(text,text)
  to authenticated;

create function public.submit_municipal_complaint(
  p_booking_id uuid,p_reported_user_id uuid,p_category text,p_description text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  b public.package_bookings;
  v_role text;
  v_reported_role text;
  v_id uuid;
  v_office uuid;
begin
  select role into v_role from public.profiles where id=auth.uid();
  if v_role not in ('tourist','driver') or v_role is null then
    raise exception 'REPORTER_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_category not in ('safety','conduct','service','payment','other')
     or char_length(btrim(coalesce(p_description,''))) not between 20 and 2000 then
    raise exception 'INVALID_COMPLAINT_DETAILS' using errcode='22023';
  end if;
  select * into b from public.package_bookings where id=p_booking_id;
  if not found or nullif(b.municipality,'') is null
     or nullif(b.province,'') is null then
    raise exception 'BOOKING_NOT_FOUND' using errcode='P0002';
  end if;
  if v_role='tourist' then
    if b.tourist_id is distinct from auth.uid()
       or not exists(select 1 from public.booking_drivers d
         where d.booking_id=b.id and d.driver_id=p_reported_user_id
           and d.status in ('accepted','completed')) then
      raise exception 'BOOKING_PARTICIPANT_REQUIRED' using errcode='42501';
    end if;
    v_reported_role:='driver';
  else
    if b.tourist_id is distinct from p_reported_user_id
       or not exists(select 1 from public.booking_drivers d
         where d.booking_id=b.id and d.driver_id=auth.uid()
           and d.status in ('accepted','completed')) then
      raise exception 'BOOKING_PARTICIPANT_REQUIRED' using errcode='42501';
    end if;
    v_reported_role:='tourist';
  end if;
  if not exists(select 1 from public.profiles p
       where p.id=p_reported_user_id and p.role=v_reported_role) then
    raise exception 'REPORTED_USER_ROLE_INVALID' using errcode='42501';
  end if;
  if exists(select 1 from public.municipal_complaints c
      where c.booking_id=b.id and c.reporter_id=auth.uid()
        and c.reported_user_id=p_reported_user_id
        and c.created_at>now()-interval '24 hours') then
    raise exception 'RECENT_COMPLAINT_ALREADY_EXISTS' using errcode='23505';
  end if;
  insert into public.municipal_complaints(booking_id,municipality,province,
    reporter_id,reported_user_id,reported_role,category,description)
  values(b.id,b.municipality,b.province,auth.uid(),p_reported_user_id,
    v_reported_role,p_category,btrim(p_description)) returning id into v_id;
  insert into public.municipal_complaint_events
    (complaint_id,actor_id,action,details)
  values(v_id,auth.uid(),'submitted','Complaint submitted for MTO review');
  for v_office in select office.id from public.subtenant_details office
    join public.profiles p on p.id=office.id
    where p.role='subtenant' and office.is_active
      and public.cities_match(office.city,b.municipality)
      and public.cities_match(office.province,b.province) loop
    insert into public.notifications(user_id,title,body,type)
    values(v_office,'New user complaint',
      'A booking complaint requires municipal review.','municipal_complaint');
  end loop;
  return v_id;
end $$;
revoke all on function public.submit_municipal_complaint(uuid,uuid,text,text)
  from public,anon;
grant execute on function public.submit_municipal_complaint(uuid,uuid,text,text)
  to authenticated;

create function public.get_municipal_complaints(p_complaint_id uuid default null)
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id',c.id,'booking_id',c.booking_id,'municipality',c.municipality,
    'province',c.province,'reporter_id',c.reporter_id,
    'reporter_name',reporter.full_name,'reported_user_id',c.reported_user_id,
    'reported_name',reported.full_name,'reported_role',c.reported_role,
    'category',c.category,'description',c.description,'status',c.status,
    'investigation_notes',c.investigation_notes,'findings',c.findings,
    'resolution_note',c.resolution_note,'created_at',c.created_at,
    'decided_at',c.decided_at,
    'booking_status',b.booking_status,'booking_travel_date',b.travel_date,
    'booking_history',coalesce((select jsonb_agg(jsonb_build_object(
      'booking_id',h.id,'travel_date',h.travel_date,
      'booking_status',h.booking_status) order by h.travel_date desc)
      from (select prior.id,prior.travel_date,prior.booking_status
        from public.package_bookings prior
        where public.cities_match(prior.municipality,c.municipality)
          and public.cities_match(prior.province,c.province)
          and (c.reported_role='tourist' and
                prior.tourist_id=c.reported_user_id
            or c.reported_role='driver' and exists(
              select 1 from public.booking_drivers prior_driver
              where prior_driver.booking_id=prior.id
                and prior_driver.driver_id=c.reported_user_id
                and prior_driver.status in ('accepted','completed')))
        order by prior.travel_date desc limit 20) h),'[]'::jsonb),
    'evidence',coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'storage_path',e.storage_path,'file_name',e.file_name,
      'content_type',e.content_type) order by e.created_at)
      from public.municipal_complaint_evidence e where e.complaint_id=c.id),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(jsonb_build_object(
      'action',ev.action,'details',ev.details,'created_at',ev.created_at)
      order by ev.created_at)
      from public.municipal_complaint_events ev where ev.complaint_id=c.id),'[]'::jsonb))
  from public.municipal_complaints c
  join public.profiles reporter on reporter.id=c.reporter_id
  join public.profiles reported on reported.id=c.reported_user_id
  join public.package_bookings b on b.id=c.booking_id
  where (p_complaint_id is null or c.id=p_complaint_id)
    and public.is_municipal_complaint_officer(c.municipality,c.province)
  order by c.created_at desc;
$$;
revoke all on function public.get_municipal_complaints(uuid) from public,anon;
grant execute on function public.get_municipal_complaints(uuid) to authenticated;

create function public.get_my_municipal_complaints()
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',c.id,'booking_id',c.booking_id,
    'category',c.category,'status',c.status,'created_at',c.created_at,
    'decided_at',c.decided_at,'resolution_note',c.resolution_note,
    'reported_role',c.reported_role,
    'is_reporter',c.reporter_id=auth.uid())
  from public.municipal_complaints c
  where auth.uid() in (c.reporter_id,c.reported_user_id)
  order by c.created_at desc;
$$;
revoke all on function public.get_my_municipal_complaints() from public,anon;
grant execute on function public.get_my_municipal_complaints() to authenticated;

create function public.update_municipal_complaint(
  p_complaint_id uuid,p_action text,p_notes text,p_findings text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.municipal_complaints;
begin
  select * into c from public.municipal_complaints where id=p_complaint_id
    for update;
  if not found or not public.is_municipal_complaint_officer(
      c.municipality,c.province) then
    raise exception 'MTO_SCOPE_REQUIRED' using errcode='42501';
  end if;
  if char_length(btrim(coalesce(p_notes,''))) < 10 then
    raise exception 'DOCUMENTED_NOTES_REQUIRED' using errcode='22023';
  end if;
  if p_action='investigate' then
    if c.status<>'submitted' then raise exception 'INVALID_CASE_TRANSITION'; end if;
    update public.municipal_complaints set status='under_investigation',
      investigator_id=auth.uid(),investigation_notes=btrim(p_notes),
      updated_at=now() where id=c.id;
    p_action:='investigation_started';
  elsif p_action='note' then
    if c.status<>'under_investigation' then raise exception 'INVALID_CASE_TRANSITION'; end if;
    update public.municipal_complaints set
      investigation_notes=concat_ws(E'\n',investigation_notes,btrim(p_notes)),
      updated_at=now() where id=c.id;
    p_action:='note_added';
  elsif p_action in ('resolve','dismiss') then
    if c.status<>'under_investigation' or
       char_length(btrim(coalesce(p_findings,''))) < 10 then
      raise exception 'INVESTIGATION_AND_FINDINGS_REQUIRED';
    end if;
    update public.municipal_complaints set
      status=case when p_action='resolve' then 'resolved' else 'dismissed' end,
      findings=btrim(p_findings),resolution_note=btrim(p_notes),
      decided_at=now(),updated_at=now() where id=c.id;
    p_action:=case when p_action='resolve' then 'resolved' else 'dismissed' end;
  elsif p_action='warn' then
    if c.status<>'under_investigation' then raise exception 'INVALID_CASE_TRANSITION'; end if;
    if exists(select 1 from public.municipal_complaint_events ev
      where ev.complaint_id=c.id and ev.action='warning_issued') then
      raise exception 'WARNING_ALREADY_ISSUED';
    end if;
    p_action:='warning_issued';
  else
    raise exception 'INVALID_CASE_ACTION' using errcode='22023';
  end if;
  insert into public.municipal_complaint_events
    (complaint_id,actor_id,action,details)
  values(c.id,auth.uid(),p_action,btrim(p_notes));
  if p_action in ('warning_issued','resolved','dismissed','investigation_started') then
    insert into public.notifications(user_id,title,body,type)
    select recipient,'Complaint update',
      'Complaint '||upper(left(c.id::text,8))||': '||
        replace(p_action,'_',' ')||'. Review the decision in TourisTrike.',
      'municipal_complaint'
    from unnest(array[c.reporter_id,c.reported_user_id]) recipient;
  end if;
  return (select to_jsonb(updated) from public.municipal_complaints updated
    where updated.id=c.id);
end $$;
revoke all on function public.update_municipal_complaint(uuid,text,text,text)
  from public,anon;
grant execute on function public.update_municipal_complaint(uuid,text,text,text)
  to authenticated;

create function public.municipal_restriction_active(
  p_account_id uuid,p_municipality text,p_province text
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.municipal_booking_restrictions r
    where r.account_id=p_account_id and r.lifted_at is null
      and r.starts_at<=now() and r.ends_at>now()
      and public.cities_match(r.municipality,p_municipality)
      and public.cities_match(r.province,p_province));
$$;
revoke all on function public.municipal_restriction_active(uuid,text,text)
  from public,anon,authenticated;

create function public.get_municipal_restrictions()
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',r.id,'complaint_id',r.complaint_id,
    'account_id',r.account_id,'account_role',r.account_role,
    'municipality',r.municipality,'province',r.province,
    'reason',r.reason,'starts_at',r.starts_at,'ends_at',r.ends_at,
    'lifted_at',r.lifted_at,'active',r.lifted_at is null and r.ends_at>now(),
    'appeals',coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'reason',a.reason,'status',a.status,
      'decision_note',a.decision_note,'created_at',a.created_at)
      order by a.created_at) from public.municipal_restriction_appeals a
      where a.restriction_id=r.id),'[]'::jsonb))
  from public.municipal_booking_restrictions r
  where public.is_municipal_complaint_officer(r.municipality,r.province)
  order by r.created_at desc;
$$;
revoke all on function public.get_municipal_restrictions() from public,anon;
grant execute on function public.get_municipal_restrictions() to authenticated;

create function public.get_my_municipal_restrictions()
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',r.id,'complaint_id',r.complaint_id,
    'municipality',r.municipality,'province',r.province,'reason',r.reason,
    'starts_at',r.starts_at,'ends_at',r.ends_at,'lifted_at',r.lifted_at,
    'active',r.lifted_at is null and r.ends_at>now(),
    'appeal_status',(select a.status from public.municipal_restriction_appeals a
      where a.restriction_id=r.id order by a.created_at desc limit 1))
  from public.municipal_booking_restrictions r
  where r.account_id=auth.uid() order by r.created_at desc;
$$;
revoke all on function public.get_my_municipal_restrictions() from public,anon;
grant execute on function public.get_my_municipal_restrictions() to authenticated;

create function public.impose_municipal_restriction(
  p_complaint_id uuid,p_reason text,p_ends_at timestamptz,p_confirm boolean
) returns uuid language plpgsql security definer set search_path = '' as $$
declare c public.municipal_complaints; v_id uuid;
begin
  select * into c from public.municipal_complaints where id=p_complaint_id
    for update;
  if not found or not public.is_municipal_complaint_officer(
      c.municipality,c.province) then
    raise exception 'MTO_SCOPE_REQUIRED' using errcode='42501';
  end if;
  if p_confirm is distinct from true or c.status<>'under_investigation'
     or char_length(btrim(coalesce(c.investigation_notes,''))) < 10
     or char_length(btrim(coalesce(p_reason,''))) < 20
     or p_ends_at is null or p_ends_at<=now()
     or p_ends_at>now()+interval '365 days' then
    raise exception 'DOCUMENTED_INVESTIGATION_AND_DURATION_REQUIRED';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(c.reported_user_id::text,0));
  if public.municipal_restriction_active(c.reported_user_id,
      c.municipality,c.province) then
    raise exception 'MUNICIPAL_RESTRICTION_ALREADY_ACTIVE';
  end if;
  insert into public.municipal_booking_restrictions(complaint_id,account_id,
    account_role,municipality,province,reason,ends_at,imposed_by)
  values(c.id,c.reported_user_id,c.reported_role,c.municipality,c.province,
    btrim(p_reason),p_ends_at,auth.uid()) returning id into v_id;
  insert into public.municipal_complaint_events
    (complaint_id,actor_id,action,details)
  values(c.id,auth.uid(),'suspended',btrim(p_reason));
  insert into public.notifications(user_id,title,body,type)
  values(c.reported_user_id,'Municipal booking restriction',
    'New bookings or driver job acceptances in '||c.municipality||
    ' are restricted until '||p_ends_at::text||'. Existing trips and payments remain accessible. You may appeal.',
    'municipal_restriction');
  return v_id;
end $$;
revoke all on function public.impose_municipal_restriction(uuid,text,timestamptz,boolean)
  from public,anon;
grant execute on function public.impose_municipal_restriction(uuid,text,timestamptz,boolean)
  to authenticated;

create function public.lift_municipal_restriction(p_restriction_id uuid,p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.municipal_booking_restrictions;
begin
  select * into r from public.municipal_booking_restrictions
    where id=p_restriction_id for update;
  if not found or not public.is_municipal_complaint_officer(
      r.municipality,r.province) then
    raise exception 'MTO_SCOPE_REQUIRED' using errcode='42501';
  end if;
  if r.lifted_at is not null or char_length(btrim(coalesce(p_note,'')))<10 then
    raise exception 'LIFT_NOTE_REQUIRED';
  end if;
  update public.municipal_booking_restrictions set lifted_at=now(),
    lifted_by=auth.uid(),lift_note=btrim(p_note) where id=r.id;
  insert into public.municipal_complaint_events
    (complaint_id,actor_id,action,details)
  values(r.complaint_id,auth.uid(),'lifted',btrim(p_note));
  insert into public.notifications(user_id,title,body,type)
  values(r.account_id,'Municipal restriction lifted',
    'Your municipal booking restriction has been lifted.','municipal_restriction');
end $$;
revoke all on function public.lift_municipal_restriction(uuid,text)
  from public,anon;
grant execute on function public.lift_municipal_restriction(uuid,text)
  to authenticated;

create function public.appeal_municipal_restriction(p_restriction_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare r public.municipal_booking_restrictions; v_id uuid;
begin
  select * into r from public.municipal_booking_restrictions
    where id=p_restriction_id;
  if not found or r.account_id is distinct from auth.uid() then
    raise exception 'RESTRICTION_ACCESS_DENIED' using errcode='42501';
  end if;
  if char_length(btrim(coalesce(p_reason,''))) not between 20 and 2000
     or r.lifted_at is not null or r.ends_at<=now() then
    raise exception 'INVALID_APPEAL';
  end if;
  insert into public.municipal_restriction_appeals
    (restriction_id,account_id,reason)
  values(r.id,auth.uid(),btrim(p_reason)) returning id into v_id;
  insert into public.municipal_complaint_events
    (complaint_id,actor_id,action,details)
  values(r.complaint_id,auth.uid(),'appeal_submitted','Account appeal submitted');
  return v_id;
end $$;
revoke all on function public.appeal_municipal_restriction(uuid,text)
  from public,anon;
grant execute on function public.appeal_municipal_restriction(uuid,text)
  to authenticated;

create function public.decide_municipal_restriction_appeal(
  p_appeal_id uuid,p_grant boolean,p_note text
) returns void language plpgsql security definer set search_path = '' as $$
declare a public.municipal_restriction_appeals;
  r public.municipal_booking_restrictions;
begin
  select * into a from public.municipal_restriction_appeals
    where id=p_appeal_id for update;
  select * into r from public.municipal_booking_restrictions
    where id=a.restriction_id for update;
  if not found or a.status<>'pending' or
     not public.is_municipal_complaint_officer(r.municipality,r.province) then
    raise exception 'MTO_SCOPE_REQUIRED' using errcode='42501';
  end if;
  if p_grant is null or char_length(btrim(coalesce(p_note,'')))<10 then
    raise exception 'APPEAL_DECISION_NOTE_REQUIRED';
  end if;
  update public.municipal_restriction_appeals set
    status=case when p_grant then 'granted' else 'upheld' end,
    decision_note=btrim(p_note),reviewed_by=auth.uid(),reviewed_at=now()
  where id=a.id;
  if p_grant and r.lifted_at is null then
    update public.municipal_booking_restrictions set lifted_at=now(),
      lifted_by=auth.uid(),lift_note=btrim(p_note) where id=r.id;
  end if;
  insert into public.municipal_complaint_events
    (complaint_id,actor_id,action,details)
  values(r.complaint_id,auth.uid(),
    case when p_grant then 'appeal_granted' else 'appeal_upheld' end,
    btrim(p_note));
  insert into public.notifications(user_id,title,body,type)
  values(r.account_id,'Restriction appeal decision',
    case when p_grant then 'Your appeal was granted and the restriction was lifted.'
      else 'Your appeal was reviewed and the restriction remains in effect.' end,
    'municipal_restriction');
end $$;
revoke all on function public.decide_municipal_restriction_appeal(uuid,boolean,text)
  from public,anon;
grant execute on function public.decide_municipal_restriction_appeal(uuid,boolean,text)
  to authenticated;

-- The outer booking RPC already checks late cancellation restrictions and
-- selected vehicle capacity. Add municipal scope using the package owner,
-- rather than client-supplied municipality or province strings.
create or replace function public.create_package_booking(
  p_booking jsonb,
  p_customized_spots jsonb default '[]'::jsonb,
  p_itinerary_items jsonb default '[]'::jsonb
) returns public.package_bookings language plpgsql security definer
set search_path = '' as $$
declare v_until timestamptz; v_selected integer; v_adults integer;
  v_children integer; v_capacity integer := public.tricycle_passenger_capacity();
  v_city text; v_province text;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
  select restricted_until into v_until from public.tourist_booking_restrictions
  where tourist_id=auth.uid() and status='active'
    and restricted_until>clock_timestamp();
  if v_until is not null then
    raise exception 'NEW_BOOKINGS_TEMPORARILY_RESTRICTED until %',v_until;
  end if;
  if p_booking ? 'selected_total_tricycles' then
    v_selected:=(p_booking->>'selected_total_tricycles')::integer;
    v_adults:=(p_booking->>'adults')::integer;
    v_children:=coalesce((p_booking->>'children')::integer,0);
    if v_adults is null or v_adults<1 or v_children<0 or v_selected is null
       or v_selected<public.minimum_required_tricycles(v_adults)
       or v_selected>v_adults or v_adults+v_children>v_selected*v_capacity
       or (p_booking->>'total_passengers')::integer is distinct from
          v_adults+v_children
       or (p_booking->>'required_drivers')::integer is distinct from v_selected
       or coalesce((p_booking->>'additional_tricycle_count')::integer,0)<>0 then
      raise exception 'INVALID_SELECTED_TRICYCLE_COUNT';
    end if;
  elsif coalesce((p_booking->>'additional_tricycle_count')::integer,0)>0 then
    raise exception 'ADDITIONAL_TRICYCLE_REQUEST_RETIRED';
  end if;
  select p.city,office.province into v_city,v_province
  from public.tour_packages p
  join public.subtenant_details office on office.id=p.submitted_by
  where p.id=(p_booking->>'package_id')::bigint;
  if v_city is null or v_province is null then
    raise exception 'PACKAGE_MUNICIPAL_OWNER_REQUIRED' using errcode='42501';
  end if;
  if public.municipal_restriction_active(auth.uid(),
      v_city,v_province) then
    raise exception 'MUNICIPAL_TOURIST_BOOKING_RESTRICTED'
      using errcode='42501';
  end if;
  return public.create_package_booking_restriction_impl(
    p_booking,p_customized_spots,p_itinerary_items);
end $$;
revoke all on function public.create_package_booking(jsonb,jsonb,jsonb)
  from public,anon;
grant execute on function public.create_package_booking(jsonb,jsonb,jsonb)
  to authenticated;

create function public.guard_municipal_driver_job_acceptance()
returns trigger language plpgsql security definer set search_path = '' as $$
declare b public.package_bookings;
begin
  if new.status='accepted'
     and (tg_op='INSERT' or old.status is distinct from 'accepted') then
    select * into b from public.package_bookings where id=new.booking_id;
    if public.municipal_restriction_active(new.driver_id,
        b.municipality,b.province) then
      raise exception 'MUNICIPAL_DRIVER_JOBS_RESTRICTED'
        using errcode='42501';
    end if;
  end if;
  return new;
end $$;
create trigger guard_municipal_driver_job_acceptance
before insert or update of status on public.booking_drivers
for each row execute function public.guard_municipal_driver_job_acceptance();
revoke all on function public.guard_municipal_driver_job_acceptance()
  from public,anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('municipal-complaint-evidence','municipal-complaint-evidence',false,
  10485760,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do nothing;

create function public.can_access_municipal_complaint_path(
  p_path text,p_write boolean
) returns boolean language plpgsql stable security definer set search_path = '' as $$
declare v_case_id uuid; c public.municipal_complaints;
begin
  if auth.uid() is null or split_part(p_path,'/',1) !~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
     or split_part(p_path,'/',2)='' or split_part(p_path,'/',3)<>'' then
    return false;
  end if;
  v_case_id:=split_part(p_path,'/',1)::uuid;
  select * into c from public.municipal_complaints where id=v_case_id;
  if not found then return false; end if;
  if p_write then return c.reporter_id=auth.uid() and c.status='submitted'; end if;
  return c.reporter_id=auth.uid() or
    public.is_municipal_complaint_officer(c.municipality,c.province);
end $$;
revoke all on function public.can_access_municipal_complaint_path(text,boolean)
  from public,anon;
grant execute on function public.can_access_municipal_complaint_path(text,boolean)
  to authenticated;
create policy municipal_complaint_evidence_insert on storage.objects
for insert to authenticated with check (
  bucket_id='municipal-complaint-evidence' and
  public.can_access_municipal_complaint_path(name,true));
create policy municipal_complaint_evidence_select on storage.objects
for select to authenticated using (
  bucket_id='municipal-complaint-evidence' and
  public.can_access_municipal_complaint_path(name,false));

create function public.attach_municipal_complaint_evidence(
  p_complaint_id uuid,p_storage_path text,p_file_name text,p_content_type text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.can_access_municipal_complaint_path(p_storage_path,true)
     or split_part(p_storage_path,'/',1)<>p_complaint_id::text
     or p_content_type not in ('image/jpeg','image/png','image/webp','application/pdf')
     or char_length(btrim(coalesce(p_file_name,''))) not between 1 and 200
     or not exists(select 1 from storage.objects o
       where o.bucket_id='municipal-complaint-evidence'
         and o.name=p_storage_path) then
    raise exception 'EVIDENCE_ACCESS_DENIED' using errcode='42501';
  end if;
  insert into public.municipal_complaint_evidence
    (complaint_id,storage_path,file_name,content_type,uploaded_by)
  values(p_complaint_id,p_storage_path,btrim(p_file_name),p_content_type,
    auth.uid()) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.attach_municipal_complaint_evidence(uuid,text,text,text)
  from public,anon;
grant execute on function public.attach_municipal_complaint_evidence(uuid,text,text,text)
  to authenticated;

commit;
