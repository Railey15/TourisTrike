-- Secure System Administrator account suspension history and enforcement.

begin;

create table if not exists public.account_suspensions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null,
  notes text not null default '',
  suspended_at timestamptz not null default now(),
  suspended_until timestamptz,
  suspended_by uuid not null references public.profiles(id),
  is_permanent boolean not null default false,
  state text not null default 'pending',
  reactivation_requested_at timestamptz,
  reactivation_requested_by uuid references public.profiles(id),
  reactivated_at timestamptz,
  reactivated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint account_suspensions_reason_check check (
    reason in (
      'policy_violation',
      'fraudulent_activity',
      'inappropriate_behavior',
      'account_misuse',
      'verification_issue',
      'security_concern',
      'other'
    )
  ),
  constraint account_suspensions_notes_length_check check (
    char_length(notes) <= 500
  ),
  constraint account_suspensions_state_check check (
    state in (
      'pending',
      'active',
      'reactivation_pending',
      'reactivated',
      'expired',
      'cancelled'
    )
  ),
  constraint account_suspensions_duration_check check (
    (is_permanent and suspended_until is null)
    or
    (not is_permanent and suspended_until is not null
      and suspended_until > suspended_at)
  )
);

create unique index if not exists account_suspensions_one_open_per_account_idx
  on public.account_suspensions (account_id)
  where state in ('pending', 'active', 'reactivation_pending');

create index if not exists account_suspensions_account_history_idx
  on public.account_suspensions (account_id, suspended_at desc);

create index if not exists account_suspensions_actor_idx
  on public.account_suspensions (suspended_by, suspended_at desc);

alter table public.account_suspensions enable row level security;

revoke all on table public.account_suspensions from public, anon;
grant select on table public.account_suspensions to authenticated;

drop policy if exists account_suspensions_administrator_select
  on public.account_suspensions;
create policy account_suspensions_administrator_select
on public.account_suspensions
for select to authenticated
using (public.is_system_administrator());

create or replace function public.is_current_account_suspended()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.account_suspensions s
    where s.account_id = auth.uid()
      and s.reactivated_at is null
      and s.state in ('pending', 'active', 'reactivation_pending')
      and (s.is_permanent or s.suspended_until > now())
  );
$$;

revoke all on function public.is_current_account_suspended()
  from public;
grant execute on function public.is_current_account_suspended()
  to anon, authenticated, service_role;

create or replace function public.enforce_current_account_access()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.is_current_account_suspended() then
    raise exception 'ACCOUNT_SUSPENDED'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.enforce_current_account_access()
  from public;
grant execute on function public.enforce_current_account_access()
  to anon, authenticated, service_role;

-- Auth bans prevent new sign-ins and refreshes. This PostgREST pre-request
-- guard closes the remaining window for already-issued access tokens.
alter role authenticator
  set pgrst.db_pre_request = 'public.enforce_current_account_access';
notify pgrst, 'reload config';

create or replace function public.administrator_begin_account_suspension(
  p_account_id uuid,
  p_reason text,
  p_notes text,
  p_suspended_until timestamptz,
  p_is_permanent boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_suspension_id uuid;
  v_target_role text;
  v_banned_until timestamptz;
  v_usable_administrators integer;
begin
  if not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED'
      using errcode = '42501';
  end if;
  if p_account_id is null then
    raise exception 'TARGET_ACCOUNT_REQUIRED' using errcode = '22023';
  end if;
  if p_account_id = v_actor_id then
    raise exception 'SELF_SUSPENSION_NOT_ALLOWED' using errcode = '42501';
  end if;
  if p_reason not in (
    'policy_violation',
    'fraudulent_activity',
    'inappropriate_behavior',
    'account_misuse',
    'verification_issue',
    'security_concern',
    'other'
  ) then
    raise exception 'INVALID_SUSPENSION_REASON' using errcode = '22023';
  end if;
  if char_length(coalesce(p_notes, '')) > 500 then
    raise exception 'SUSPENSION_NOTES_TOO_LONG' using errcode = '22023';
  end if;
  if p_reason = 'other' and btrim(coalesce(p_notes, '')) = '' then
    raise exception 'CUSTOM_SUSPENSION_REASON_REQUIRED'
      using errcode = '22023';
  end if;
  if p_is_permanent and p_suspended_until is not null then
    raise exception 'PERMANENT_SUSPENSION_CANNOT_HAVE_END'
      using errcode = '22023';
  end if;
  if not p_is_permanent and (
    p_suspended_until is null
    or p_suspended_until <= now()
    or p_suspended_until > now() + interval '3650 days 5 minutes'
  ) then
    raise exception 'INVALID_SUSPENSION_END' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(20260927, 40000);

  update public.account_suspensions
  set state = 'expired',
      reactivated_at = suspended_until,
      updated_at = now()
  where state in ('pending', 'active', 'reactivation_pending')
    and not is_permanent
    and suspended_until <= now();

  select p.role, u.banned_until
    into v_target_role, v_banned_until
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = p_account_id
    and u.deleted_at is null;

  if not found then
    raise exception 'TARGET_ACCOUNT_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_banned_until is not null and v_banned_until > now() then
    raise exception 'ACCOUNT_ALREADY_SUSPENDED' using errcode = '23505';
  end if;
  if exists (
    select 1
    from public.account_suspensions s
    where s.account_id = p_account_id
      and s.state in ('pending', 'active', 'reactivation_pending')
      and s.reactivated_at is null
      and (s.is_permanent or s.suspended_until > now())
  ) then
    raise exception 'ACCOUNT_ALREADY_SUSPENDED' using errcode = '23505';
  end if;

  if v_target_role = 'administrator' then
    select count(*)::integer
      into v_usable_administrators
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.role = 'administrator'
      and u.deleted_at is null
      and u.email_confirmed_at is not null
      and (u.banned_until is null or u.banned_until <= now())
      and not exists (
        select 1
        from public.account_suspensions s
        where s.account_id = p.id
          and s.reactivated_at is null
          and s.state in ('pending', 'active', 'reactivation_pending')
          and (s.is_permanent or s.suspended_until > now())
      );
    if v_usable_administrators <= 1 then
      raise exception 'LAST_USABLE_ADMINISTRATOR'
        using errcode = '42501';
    end if;
  end if;

  insert into public.account_suspensions (
    account_id,
    reason,
    notes,
    suspended_until,
    suspended_by,
    is_permanent,
    state
  ) values (
    p_account_id,
    p_reason,
    btrim(coalesce(p_notes, '')),
    case when p_is_permanent then null else p_suspended_until end,
    v_actor_id,
    p_is_permanent,
    'pending'
  )
  returning id into v_suspension_id;

  return v_suspension_id;
end;
$$;

create or replace function public.administrator_finalize_account_suspension(
  p_suspension_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_suspension public.account_suspensions%rowtype;
  v_duration text;
begin
  if not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED'
      using errcode = '42501';
  end if;

  update public.account_suspensions
  set state = 'active', updated_at = now()
  where id = p_suspension_id
    and suspended_by = auth.uid()
    and state = 'pending'
  returning * into v_suspension;

  if not found then
    raise exception 'SUSPENSION_FINALIZATION_NOT_ALLOWED'
      using errcode = '42501';
  end if;

  v_duration := case
    when v_suspension.is_permanent then 'permanent'
    else 'until ' || v_suspension.suspended_until::text
  end;

  insert into public.audit_logs (
    actor_id, action, table_name, record_id, description
  ) values (
    auth.uid(),
    'account_suspended',
    'account_suspensions',
    v_suspension.account_id::text,
    format(
      'Suspended account %s: reason=%s; duration=%s; notes=%s',
      v_suspension.account_id,
      v_suspension.reason,
      v_duration,
      nullif(v_suspension.notes, '')
    )
  );
end;
$$;

create or replace function public.administrator_cancel_account_suspension(
  p_suspension_id uuid
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.account_suspensions
  set state = 'cancelled', updated_at = now()
  where id = p_suspension_id and state = 'pending';
$$;

create or replace function public.administrator_begin_account_reactivation(
  p_account_id uuid
)
returns table (
  suspension_id uuid,
  is_permanent boolean,
  suspended_until timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(20260927, 40000);

  update public.account_suspensions as suspension
  set state = 'expired',
      reactivated_at = suspension.suspended_until,
      updated_at = now()
  where suspension.account_id = p_account_id
    and suspension.state in ('pending', 'active', 'reactivation_pending')
    and not suspension.is_permanent
    and suspension.suspended_until <= now();

  return query
  update public.account_suspensions s
  set state = 'reactivation_pending',
      reactivation_requested_at = now(),
      reactivation_requested_by = auth.uid(),
      updated_at = now()
  where s.account_id = p_account_id
    and s.reactivated_at is null
    and s.state = 'active'
    and (s.is_permanent or s.suspended_until > now())
  returning s.id, s.is_permanent, s.suspended_until;

  if not found then
    raise exception 'ACCOUNT_NOT_SUSPENDED' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.administrator_finalize_account_reactivation(
  p_suspension_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account_id uuid;
begin
  if not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED'
      using errcode = '42501';
  end if;

  update public.account_suspensions
  set state = 'reactivated',
      reactivated_at = now(),
      reactivated_by = auth.uid(),
      updated_at = now()
  where id = p_suspension_id
    and reactivation_requested_by = auth.uid()
    and state = 'reactivation_pending'
  returning account_id into v_account_id;

  if not found then
    raise exception 'REACTIVATION_FINALIZATION_NOT_ALLOWED'
      using errcode = '42501';
  end if;

  insert into public.audit_logs (
    actor_id, action, table_name, record_id, description
  ) values (
    auth.uid(),
    'account_reactivated',
    'account_suspensions',
    v_account_id::text,
    format('Reactivated account %s after manual administrator review', v_account_id)
  );
end;
$$;

create or replace function public.administrator_cancel_account_reactivation(
  p_suspension_id uuid
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.account_suspensions
  set state = 'active',
      reactivation_requested_at = null,
      reactivation_requested_by = null,
      updated_at = now()
  where id = p_suspension_id and state = 'reactivation_pending';
$$;

revoke all on function public.administrator_begin_account_suspension(
  uuid, text, text, timestamptz, boolean
) from public, anon;
revoke all on function public.administrator_finalize_account_suspension(uuid)
  from public, anon;
revoke all on function public.administrator_begin_account_reactivation(uuid)
  from public, anon;
revoke all on function public.administrator_finalize_account_reactivation(uuid)
  from public, anon;
revoke all on function public.administrator_cancel_account_suspension(uuid)
  from public, anon, authenticated;
revoke all on function public.administrator_cancel_account_reactivation(uuid)
  from public, anon, authenticated;

grant execute on function public.administrator_begin_account_suspension(
  uuid, text, text, timestamptz, boolean
) to authenticated;
grant execute on function public.administrator_finalize_account_suspension(uuid)
  to authenticated;
grant execute on function public.administrator_begin_account_reactivation(uuid)
  to authenticated;
grant execute on function public.administrator_finalize_account_reactivation(uuid)
  to authenticated;
grant execute on function public.administrator_cancel_account_suspension(uuid)
  to service_role;
grant execute on function public.administrator_cancel_account_reactivation(uuid)
  to service_role;

drop function if exists public.administrator_list_accounts();
create function public.administrator_list_accounts()
returns table (
  id uuid,
  role text,
  full_name text,
  first_name text,
  last_name text,
  email text,
  city text,
  province text,
  profile_created_at timestamptz,
  auth_created_at timestamptz,
  email_confirmed_at timestamptz,
  last_sign_in_at timestamptz,
  banned_until timestamptz,
  suspension_id uuid,
  suspension_reason text,
  suspension_notes text,
  suspended_at timestamptz,
  suspended_until timestamptz,
  suspension_is_permanent boolean,
  suspended_by uuid,
  suspended_by_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED'
      using errcode = '42501';
  end if;

  return query
  select
    p.id,
    p.role,
    p.full_name,
    p.first_name,
    p.last_name,
    u.email::text,
    p.city,
    p.province,
    p.created_at,
    u.created_at,
    u.email_confirmed_at,
    u.last_sign_in_at,
    u.banned_until,
    s.id,
    s.reason,
    s.notes,
    s.suspended_at,
    s.suspended_until,
    s.is_permanent,
    s.suspended_by,
    s.suspended_by_name
  from public.profiles p
  join auth.users u on u.id = p.id
  left join lateral (
    select
      suspension.id,
      suspension.reason,
      suspension.notes,
      suspension.suspended_at,
      suspension.suspended_until,
      suspension.is_permanent,
      suspension.suspended_by,
      coalesce(
        nullif(actor.full_name, ''),
        nullif(concat_ws(' ', actor.first_name, actor.last_name), ''),
        'System Administrator'
      ) as suspended_by_name
    from public.account_suspensions suspension
    left join public.profiles actor on actor.id = suspension.suspended_by
    where suspension.account_id = p.id
      and suspension.reactivated_at is null
      and suspension.state in ('pending', 'active', 'reactivation_pending')
      and (
        suspension.is_permanent
        or suspension.suspended_until > now()
      )
    order by suspension.suspended_at desc
    limit 1
  ) s on true
  order by u.created_at desc;
end;
$$;

revoke all on function public.administrator_list_accounts()
  from public, anon;
grant execute on function public.administrator_list_accounts()
  to authenticated;

commit;
