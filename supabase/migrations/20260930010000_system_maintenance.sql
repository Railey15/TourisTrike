-- Platform-wide maintenance scheduling, administrator controls, and access enforcement.

begin;

create table if not exists public.system_settings (
  singleton boolean primary key default true check (singleton),
  maintenance_enabled boolean not null default false,
  maintenance_title text not null default 'We''ll be right back!',
  maintenance_message text not null default 'TourisTrike is temporarily unavailable while we perform system maintenance. Your account and booking information remain safe.',
  maintenance_starts_at timestamptz,
  maintenance_ends_at timestamptz,
  maintenance_indefinite boolean not null default false,
  maintenance_allow_main_tenant boolean not null default false,
  maintenance_updated_by uuid references public.profiles(id) on delete set null,
  maintenance_updated_at timestamptz not null default now(),
  constraint system_settings_maintenance_title_length check (
    char_length(btrim(maintenance_title)) between 1 and 120
  ),
  constraint system_settings_maintenance_message_length check (
    char_length(btrim(maintenance_message)) between 1 and 1000
  ),
  constraint system_settings_maintenance_window check (
    not maintenance_enabled
    or (
      maintenance_starts_at is not null
      and (
        (maintenance_indefinite and maintenance_ends_at is null)
        or
        (not maintenance_indefinite and maintenance_ends_at > maintenance_starts_at)
      )
    )
  )
);

insert into public.system_settings (singleton)
values (true)
on conflict (singleton) do nothing;

alter table public.system_settings enable row level security;
revoke all on table public.system_settings from public, anon, authenticated;

create or replace function public.get_maintenance_status()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with setting as (
    select s.*,
      s.maintenance_enabled
      and s.maintenance_starts_at is not null
      and s.maintenance_starts_at <= now()
      and (
        s.maintenance_indefinite
        or (s.maintenance_ends_at is not null and s.maintenance_ends_at > now())
      ) as maintenance_active
    from public.system_settings s
    where s.singleton
  ), viewer as (
    select p.role
    from public.profiles p
    where p.id = auth.uid()
  )
  select jsonb_build_object(
    'maintenance_enabled', coalesce(s.maintenance_enabled, false),
    'maintenance_title', coalesce(s.maintenance_title, 'We''ll be right back!'),
    'maintenance_message', coalesce(
      s.maintenance_message,
      'TourisTrike is temporarily unavailable while we perform system maintenance. Your account and booking information remain safe.'
    ),
    'maintenance_starts_at', s.maintenance_starts_at,
    'maintenance_ends_at', s.maintenance_ends_at,
    'maintenance_indefinite', coalesce(s.maintenance_indefinite, false),
    'maintenance_allow_main_tenant', coalesce(s.maintenance_allow_main_tenant, false),
    'maintenance_updated_by', s.maintenance_updated_by,
    'maintenance_updated_by_name', coalesce(
      nullif(actor.full_name, ''),
      nullif(concat_ws(' ', actor.first_name, actor.last_name), ''),
      case when s.maintenance_updated_by is null then '' else 'System Administrator' end
    ),
    'maintenance_updated_at', s.maintenance_updated_at,
    'maintenance_active', coalesce(s.maintenance_active, false),
    'viewer_role', v.role,
    'viewer_allowed', case
      when not coalesce(s.maintenance_active, false) then true
      when v.role = 'administrator' then true
      when v.role = 'main_tenant' and coalesce(s.maintenance_allow_main_tenant, false) then true
      else false
    end
  )
  from (select 1) seed
  left join setting s on true
  left join viewer v on true
  left join public.profiles actor on actor.id = s.maintenance_updated_by;
$$;

revoke all on function public.get_maintenance_status() from public;
grant execute on function public.get_maintenance_status() to anon, authenticated, service_role;

create or replace function public.is_current_maintenance_blocked()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.system_settings s
    left join public.profiles p on p.id = auth.uid()
    where s.singleton
      and s.maintenance_enabled
      and s.maintenance_starts_at is not null
      and s.maintenance_starts_at <= now()
      and (
        s.maintenance_indefinite
        or (s.maintenance_ends_at is not null and s.maintenance_ends_at > now())
      )
      and coalesce(p.role, '') <> 'administrator'
      and not (
        coalesce(p.role, '') = 'main_tenant'
        and s.maintenance_allow_main_tenant
      )
  );
$$;

revoke all on function public.is_current_maintenance_blocked() from public;
grant execute on function public.is_current_maintenance_blocked() to anon, authenticated, service_role;

create or replace function public.administrator_set_maintenance(
  p_enabled boolean,
  p_title text,
  p_message text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_indefinite boolean,
  p_allow_main_tenant boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous public.system_settings%rowtype;
  v_action text;
  v_now timestamptz := now();
begin
  if not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;

  if p_enabled is null or p_indefinite is null or p_allow_main_tenant is null then
    raise exception 'INVALID_MAINTENANCE_SETTINGS' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 1 and 120 then
    raise exception 'INVALID_MAINTENANCE_TITLE' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_message, ''))) not between 1 and 1000 then
    raise exception 'INVALID_MAINTENANCE_MESSAGE' using errcode = '22023';
  end if;
  if p_enabled and p_starts_at is null then
    raise exception 'MAINTENANCE_START_REQUIRED' using errcode = '22023';
  end if;
  if p_enabled and p_indefinite and p_ends_at is not null then
    raise exception 'INDEFINITE_MAINTENANCE_CANNOT_HAVE_END' using errcode = '22023';
  end if;
  if p_enabled and not p_indefinite and (
    p_ends_at is null or p_ends_at <= p_starts_at or p_ends_at <= v_now
  ) then
    raise exception 'INVALID_MAINTENANCE_END' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(20260930, 10000);
  select * into v_previous
  from public.system_settings
  where singleton
  for update;

  if not p_enabled then
    v_action := 'SYSTEM_MAINTENANCE_DISABLED';
  elsif not v_previous.maintenance_enabled and p_starts_at > v_now then
    v_action := 'SYSTEM_MAINTENANCE_SCHEDULED';
  elsif not v_previous.maintenance_enabled then
    v_action := 'SYSTEM_MAINTENANCE_ENABLED';
  else
    v_action := 'SYSTEM_MAINTENANCE_UPDATED';
  end if;

  update public.system_settings
  set maintenance_enabled = p_enabled,
      maintenance_title = btrim(p_title),
      maintenance_message = btrim(p_message),
      maintenance_starts_at = case when p_enabled then p_starts_at else maintenance_starts_at end,
      maintenance_ends_at = case when p_enabled then p_ends_at else maintenance_ends_at end,
      maintenance_indefinite = case when p_enabled then p_indefinite else maintenance_indefinite end,
      maintenance_allow_main_tenant = p_allow_main_tenant,
      maintenance_updated_by = auth.uid(),
      maintenance_updated_at = v_now
  where singleton;

  insert into public.audit_logs (
    actor_id, action, table_name, record_id, description
  ) values (
    auth.uid(),
    v_action,
    'system_settings',
    'maintenance',
    jsonb_build_object(
      'enabled', p_enabled,
      'title', btrim(p_title),
      'message', btrim(p_message),
      'starts_at', p_starts_at,
      'ends_at', p_ends_at,
      'indefinite', p_indefinite,
      'allow_main_tenant', p_allow_main_tenant
    )::text
  );

  return public.get_maintenance_status();
end;
$$;

revoke all on function public.administrator_set_maintenance(
  boolean, text, text, timestamptz, timestamptz, boolean, boolean
) from public, anon;
grant execute on function public.administrator_set_maintenance(
  boolean, text, text, timestamptz, timestamptz, boolean, boolean
) to authenticated;

-- Preserve suspension enforcement and then apply maintenance restrictions.
-- The read-only status RPC is the sole exception so blocked clients can render
-- the maintenance details and learn immediately when access is restored.
create or replace function public.enforce_current_account_access()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_request_path text := current_setting('request.path', true);
begin
  if public.is_current_account_suspended() then
    raise exception 'ACCOUNT_SUSPENDED' using errcode = '42501';
  end if;

  if current_setting('role', true) <> 'service_role'
     and public.is_current_maintenance_blocked()
     and coalesce(v_request_path, '') <> '/rpc/get_maintenance_status' then
    raise exception 'SYSTEM_MAINTENANCE_ACTIVE' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.enforce_current_account_access() from public;
grant execute on function public.enforce_current_account_access() to anon, authenticated, service_role;

alter role authenticator
  set pgrst.db_pre_request = 'public.enforce_current_account_access';
notify pgrst, 'reload schema';
notify pgrst, 'reload config';

commit;
