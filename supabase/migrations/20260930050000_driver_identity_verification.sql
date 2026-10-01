-- Didit identity is separate from driver_details.status and MTO accreditation.
-- Hosted URLs are private; clients and staff read only the status projection RPC.
create table if not exists public.driver_identity_verifications (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles(id) on delete cascade,
  provider_session_id uuid unique,
  workflow_id uuid,
  session_url text,
  status text not null default 'creating'
    check (status in ('creating','not_started','in_progress','in_review','approved','declined','expired')),
  provider_status text,
  provider_event_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  verified_at timestamptz,
  declined_at timestamptz
);

create unique index if not exists driver_identity_one_active_idx
  on public.driver_identity_verifications (driver_id)
  where status in ('creating','not_started','in_progress','in_review','approved');
create index if not exists driver_identity_driver_latest_idx
  on public.driver_identity_verifications (driver_id, created_at desc);

alter table public.driver_identity_verifications enable row level security;
revoke all on public.driver_identity_verifications from public, anon, authenticated;
grant all on public.driver_identity_verifications to service_role;

-- The reservation ID is sent as opaque vendor_data. It is never used by the
-- webhook to identify a Driver; only provider_session_id links the result.
create or replace function public.reserve_driver_identity_verification()
returns table(attempt_id uuid, internal_status text, hosted_url text, provider_session_id uuid)
language plpgsql security definer set search_path = ''
as $$
declare
  v_driver_id uuid := auth.uid();
  v_existing public.driver_identity_verifications%rowtype;
begin
  if v_driver_id is null or not exists (
    select 1 from public.profiles p where p.id = v_driver_id and p.role = 'driver'
  ) then
    raise exception 'DRIVER_REQUIRED' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.driver_details d
    where d.driver_id = v_driver_id and d.status = 'suspended'
  ) then
    raise exception 'DRIVER_SUSPENDED' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_driver_id::text, 4096));
  select * into v_existing from public.driver_identity_verifications v
  where v.driver_id = v_driver_id
    and v.status in ('creating','not_started','in_progress','in_review','approved')
  order by v.created_at desc limit 1 for update;
  if not found then
    insert into public.driver_identity_verifications (driver_id)
    values (v_driver_id) returning * into v_existing;
  end if;
  return query select v_existing.id, v_existing.status,
    v_existing.session_url, v_existing.provider_session_id;
end;
$$;
revoke all on function public.reserve_driver_identity_verification() from public, anon;
grant execute on function public.reserve_driver_identity_verification() to authenticated;

create or replace function public.finalize_driver_identity_verification(
  p_attempt_id uuid, p_session_id uuid, p_workflow_id uuid, p_url text
)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_existing public.driver_identity_verifications%rowtype;
begin
  select * into v_existing from public.driver_identity_verifications
  where id = p_attempt_id for update;
  if not found then return false; end if;
  if v_existing.provider_session_id is not null then
    return v_existing.provider_session_id = p_session_id;
  end if;
  update public.driver_identity_verifications
  set provider_session_id = p_session_id, workflow_id = p_workflow_id,
      session_url = p_url, status = 'not_started', provider_status = 'Not Started',
      updated_at = now()
  where id = p_attempt_id;
  insert into public.audit_logs (actor_id, action, table_name, record_id, description)
  values (v_existing.driver_id, 'driver_identity_verification_started',
    'driver_identity_verifications', p_attempt_id::text, 'Didit identity session created.');
  return true;
end;
$$;
revoke all on function public.finalize_driver_identity_verification(uuid,uuid,uuid,text)
  from public, anon, authenticated;
grant execute on function public.finalize_driver_identity_verification(uuid,uuid,uuid,text)
  to service_role;

create or replace function public.apply_driver_identity_webhook_status(
  p_session_id uuid, p_provider_status text, p_event_at timestamptz
)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare
  v_row public.driver_identity_verifications%rowtype;
  v_status text;
  v_current_rank integer;
  v_new_rank integer;
begin
  v_status := case p_provider_status
    when 'Not Started' then 'not_started'
    when 'In Progress' then 'in_progress'
    when 'Awaiting User' then 'in_progress'
    when 'Resubmitted' then 'in_progress'
    when 'In Review' then 'in_review'
    when 'Approved' then 'approved'
    when 'Declined' then 'declined'
    when 'Expired' then 'expired'
    when 'Abandoned' then 'expired'
    when 'Kyc Expired' then 'expired'
    else null end;
  if v_status is null then return false; end if;
  select * into v_row from public.driver_identity_verifications
  where provider_session_id = p_session_id for update;
  if not found then return false; end if;
  v_current_rank := case v_row.status
    when 'approved' then 5 when 'declined' then 4 when 'expired' then 4
    when 'in_review' then 3 when 'in_progress' then 2 else 1 end;
  v_new_rank := case v_status
    when 'approved' then 5 when 'declined' then 4 when 'expired' then 4
    when 'in_review' then 3 when 'in_progress' then 2 else 1 end;
  if v_row.provider_event_at is not null and
    (p_event_at < v_row.provider_event_at or
      (p_event_at = v_row.provider_event_at and v_new_rank <= v_current_rank)) then
    return true;
  end if;
  update public.driver_identity_verifications
  set status = v_status, provider_status = p_provider_status,
      provider_event_at = p_event_at, updated_at = now(),
      verified_at = case when v_status = 'approved' then p_event_at else verified_at end,
      declined_at = case when v_status = 'declined' then p_event_at else declined_at end
  where id = v_row.id;
  if v_status in ('approved','declined') and v_status is distinct from v_row.status then
    insert into public.audit_logs (action, table_name, record_id, description)
    values ('driver_identity_verification_' || v_status,
      'driver_identity_verifications', v_row.id::text,
      'Didit identity result recorded.');
  end if;
  return true;
end;
$$;
revoke all on function public.apply_driver_identity_webhook_status(uuid,text,timestamptz)
  from public, anon, authenticated;
grant execute on function public.apply_driver_identity_webhook_status(uuid,text,timestamptz)
  to service_role;

-- No direct table SELECT is granted. The projection exposes only the result
-- to the Driver, scoped MTO, same-province Main Tenant, or System Administrator.
create or replace function public.get_driver_identity_verification_status(
  p_driver_id uuid default null
)
returns table(status text, provider_status text, updated_at timestamptz, verified_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_target uuid := coalesce(p_driver_id, auth.uid());
  v_role text;
begin
  if auth.uid() is null or v_target is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select p.role into v_role from public.profiles p where p.id = auth.uid();
  if not (
    (v_role = 'driver' and v_target = auth.uid())
    or (v_role = 'subtenant' and public.subtenant_can_access_driver(v_target))
    or (v_role = 'main_tenant' and exists (
      select 1 from public.profiles viewer join public.profiles driver on driver.id = v_target
      where viewer.id = auth.uid() and driver.role = 'driver'
        and nullif(trim(viewer.province), '') is not null
        and lower(trim(viewer.province)) = lower(trim(driver.province))
    ))
    or v_role = 'administrator'
  ) then
    raise exception 'IDENTITY_STATUS_FORBIDDEN' using errcode = '42501';
  end if;
  return query select v.status, v.provider_status, v.updated_at, v.verified_at
  from public.driver_identity_verifications v
  where v.driver_id = v_target
  order by v.created_at desc limit 1;
end;
$$;
revoke all on function public.get_driver_identity_verification_status(uuid) from public, anon;
grant execute on function public.get_driver_identity_verification_status(uuid) to authenticated;
