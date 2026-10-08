-- Repair maintenance objects when migration history was recorded without the
-- corresponding schema/functions being present on the linked database.

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
  maintenance_updated_at timestamptz not null default now()
);
alter table public.system_settings
  add column if not exists singleton boolean default true,
  add column if not exists maintenance_enabled boolean default false,
  add column if not exists maintenance_title text default 'We''ll be right back!',
  add column if not exists maintenance_message text default 'TourisTrike is temporarily unavailable while we perform system maintenance. Your account and booking information remain safe.',
  add column if not exists maintenance_starts_at timestamptz,
  add column if not exists maintenance_ends_at timestamptz,
  add column if not exists maintenance_indefinite boolean default false,
  add column if not exists maintenance_allow_main_tenant boolean default false,
  add column if not exists maintenance_updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists maintenance_updated_at timestamptz default now();
update public.system_settings
set singleton = coalesce(singleton, true),
    maintenance_enabled = coalesce(maintenance_enabled, false),
    maintenance_title = coalesce(
      nullif(btrim(maintenance_title), ''),
      'We''ll be right back!'
    ),
    maintenance_message = coalesce(
      nullif(btrim(maintenance_message), ''),
      'TourisTrike is temporarily unavailable while we perform system maintenance. Your account and booking information remain safe.'
    ),
    maintenance_indefinite = coalesce(maintenance_indefinite, false),
    maintenance_allow_main_tenant = coalesce(maintenance_allow_main_tenant, false),
    maintenance_updated_at = coalesce(maintenance_updated_at, now());
alter table public.system_settings
  alter column singleton set default true,
  alter column singleton set not null,
  alter column maintenance_enabled set default false,
  alter column maintenance_enabled set not null,
  alter column maintenance_title set default 'We''ll be right back!',
  alter column maintenance_title set not null,
  alter column maintenance_message set default 'TourisTrike is temporarily unavailable while we perform system maintenance. Your account and booking information remain safe.',
  alter column maintenance_message set not null,
  alter column maintenance_indefinite set default false,
  alter column maintenance_indefinite set not null,
  alter column maintenance_allow_main_tenant set default false,
  alter column maintenance_allow_main_tenant set not null,
  alter column maintenance_updated_at set default now(),
  alter column maintenance_updated_at set not null;
insert into public.system_settings (singleton)
select true
where not exists (
  select 1 from public.system_settings where singleton
);
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
    select
      s.*,
      s.maintenance_enabled
      and s.maintenance_starts_at is not null
      and s.maintenance_starts_at <= now()
      and (
        s.maintenance_indefinite
        or (
          s.maintenance_ends_at is not null
          and s.maintenance_ends_at > now()
        )
      ) as maintenance_active
    from public.system_settings s
    where s.singleton
    order by s.maintenance_updated_at desc
    limit 1
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
    'maintenance_allow_main_tenant', coalesce(
      s.maintenance_allow_main_tenant,
      false
    ),
    'maintenance_updated_by', s.maintenance_updated_by,
    'maintenance_updated_by_name', coalesce(
      nullif(actor.full_name, ''),
      nullif(concat_ws(' ', actor.first_name, actor.last_name), ''),
      case
        when s.maintenance_updated_by is null then ''
        else 'System Administrator'
      end
    ),
    'maintenance_updated_at', s.maintenance_updated_at,
    'maintenance_active', coalesce(s.maintenance_active, false),
    'viewer_role', v.role,
    'viewer_allowed', case
      when not coalesce(s.maintenance_active, false) then true
      when coalesce(current_setting('role', true), '') = 'service_role' then true
      when v.role = 'administrator' then true
      when v.role = 'main_tenant'
        and coalesce(s.maintenance_allow_main_tenant, false) then true
      else false
    end
  )
  from (select 1) seed
  left join setting s on true
  left join viewer v on true
  left join public.profiles actor on actor.id = s.maintenance_updated_by;
$$;
revoke all on function public.get_maintenance_status() from public;
grant execute on function public.get_maintenance_status()
  to anon, authenticated, service_role;
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
      and coalesce(current_setting('role', true), '') <> 'service_role'
      and s.maintenance_enabled
      and s.maintenance_starts_at is not null
      and s.maintenance_starts_at <= now()
      and (
        s.maintenance_indefinite
        or (
          s.maintenance_ends_at is not null
          and s.maintenance_ends_at > now()
        )
      )
      and coalesce(p.role, '') <> 'administrator'
      and not (
        coalesce(p.role, '') = 'main_tenant'
        and s.maintenance_allow_main_tenant
      )
  );
$$;
revoke all on function public.is_current_maintenance_blocked() from public;
grant execute on function public.is_current_maintenance_blocked()
  to anon, authenticated, service_role;
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
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED'
      using errcode = '42501';
  end if;

  if p_enabled is null
     or p_indefinite is null
     or p_allow_main_tenant is null then
    raise exception 'INVALID_MAINTENANCE_SETTINGS'
      using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 1 and 120 then
    raise exception 'INVALID_MAINTENANCE_TITLE'
      using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_message, ''))) not between 1 and 1000 then
    raise exception 'INVALID_MAINTENANCE_MESSAGE'
      using errcode = '22023';
  end if;
  if p_enabled and p_starts_at is null then
    raise exception 'MAINTENANCE_START_REQUIRED'
      using errcode = '22023';
  end if;
  if p_enabled and p_indefinite and p_ends_at is not null then
    raise exception 'INDEFINITE_MAINTENANCE_CANNOT_HAVE_END'
      using errcode = '22023';
  end if;
  if p_enabled and not p_indefinite and (
    p_ends_at is null
    or p_ends_at <= p_starts_at
    or p_ends_at <= v_now
  ) then
    raise exception 'INVALID_MAINTENANCE_END'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(20260930, 20000);

  select *
  into v_previous
  from public.system_settings
  where singleton
  order by maintenance_updated_at desc
  limit 1
  for update;

  if not found then
    insert into public.system_settings (singleton)
    values (true)
    returning * into v_previous;
  end if;

  if not p_enabled then
    v_action := 'SYSTEM_MAINTENANCE_DISABLED';
  elsif not coalesce(v_previous.maintenance_enabled, false)
    and p_starts_at > v_now then
    v_action := 'SYSTEM_MAINTENANCE_SCHEDULED';
  elsif not coalesce(v_previous.maintenance_enabled, false) then
    v_action := 'SYSTEM_MAINTENANCE_ENABLED';
  else
    v_action := 'SYSTEM_MAINTENANCE_UPDATED';
  end if;

  update public.system_settings
  set maintenance_enabled = p_enabled,
      maintenance_title = btrim(p_title),
      maintenance_message = btrim(p_message),
      maintenance_starts_at = case
        when p_enabled then p_starts_at
        else maintenance_starts_at
      end,
      maintenance_ends_at = case
        when p_enabled then p_ends_at
        else maintenance_ends_at
      end,
      maintenance_indefinite = case
        when p_enabled then p_indefinite
        else maintenance_indefinite
      end,
      maintenance_allow_main_tenant = p_allow_main_tenant,
      maintenance_updated_by = auth.uid(),
      maintenance_updated_at = v_now
  where singleton;

  insert into public.audit_logs (
    actor_id,
    action,
    table_name,
    record_id,
    description
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
  boolean,
  text,
  text,
  timestamptz,
  timestamptz,
  boolean,
  boolean
) from public, anon, authenticated;
grant execute on function public.administrator_set_maintenance(
  boolean,
  text,
  text,
  timestamptz,
  timestamptz,
  boolean,
  boolean
) to authenticated;
-- Keep account suspension enforcement first. The maintenance status RPC is
-- the only request-path exception so blocked clients can render current status.
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
    raise exception 'ACCOUNT_SUSPENDED'
      using errcode = '42501';
  end if;

  if coalesce(current_setting('role', true), '') <> 'service_role'
     and public.is_current_maintenance_blocked()
     and coalesce(v_request_path, '') <> '/rpc/get_maintenance_status' then
    raise exception 'SYSTEM_MAINTENANCE_ACTIVE'
      using errcode = '42501';
  end if;
end;
$$;
revoke all on function public.enforce_current_account_access() from public;
grant execute on function public.enforce_current_account_access()
  to anon, authenticated, service_role;
alter role authenticator
  set pgrst.db_pre_request = 'public.enforce_current_account_access';
commit;
NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';
