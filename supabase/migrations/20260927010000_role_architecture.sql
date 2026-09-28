-- Canonical TourisTrike role contract.
-- The legacy `admin` role represented the Provincial Administrator and is
-- therefore migrated to `main_tenant`. `administrator` is a new, separate
-- platform-operations role with deliberately narrow data access.

begin;

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (
    role in (
      'tourist', 'driver', 'subtenant', 'admin', 'main_tenant',
      'administrator'
    )
  ) not valid;

update public.profiles
set role = 'main_tenant'
where role = 'admin';

alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (
    role in ('tourist', 'driver', 'subtenant', 'main_tenant', 'administrator')
  );

do $$
begin
  if exists (select 1 from public.profiles where role = 'admin') then
    raise exception 'ROLE_MIGRATION_FAILED: legacy admin profiles remain';
  end if;
end;
$$;

-- Normalize the only auxiliary persisted role label in the current schema.
do $$
begin
  if to_regclass('public.conversation_members') is not null then
    update public.conversation_members
    set member_role = 'main_tenant'
    where member_role = 'admin';

    alter table public.conversation_members
      drop constraint if exists conversation_members_member_role_check;
    alter table public.conversation_members
      add constraint conversation_members_member_role_check check (
        member_role in ('tourist', 'driver', 'subtenant', 'main_tenant')
      );
  end if;
end;
$$;

create or replace function public.is_main_tenant()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'main_tenant'
  );
$$;

create or replace function public.is_system_administrator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'administrator'
  );
$$;

-- Compatibility wrapper for policies created by earlier migrations. It now
-- means main_tenant only; it never grants provincial data to administrator.
create or replace function public.is_provincial_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_main_tenant();
$$;
comment on function public.is_provincial_admin() is
  'Deprecated compatibility alias for is_main_tenant().';

-- Older operational RPCs compare this helper with the former `admin` value.
-- Preserve those deployed contracts while all new authorization uses the
-- explicit helpers above. The stored profile role remains canonical.
create or replace function public.current_profile_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when role = 'main_tenant' then 'admin' else role end
  from public.profiles
  where id = auth.uid();
$$;

create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.profiles where id = auth.uid();
$$;

revoke all on function public.is_main_tenant() from public, anon;
revoke all on function public.is_system_administrator() from public, anon;
revoke all on function public.current_app_role() from public, anon;
grant execute on function public.is_main_tenant() to authenticated;
grant execute on function public.is_system_administrator() to authenticated;
grant execute on function public.current_app_role() to authenticated;

-- System Administrators can inspect account identity and audit history only.
-- Main Tenant and municipality behavior remains unchanged.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
using (
  id = auth.uid()
  or public.is_main_tenant()
  or public.is_system_administrator()
  or (
    public.current_subtenant_city() is not null
    and public.cities_match(city, public.current_subtenant_city())
  )
);

-- current_profile_role() deliberately returns the legacy compatibility value
-- for main_tenant, so use an explicit role guard on self updates.
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
using (id = auth.uid())
with check (
  id = auth.uid()
  and role = public.current_app_role()
  and (
    role <> 'subtenant'
    or public.cities_match(city, public.current_subtenant_city())
  )
);

drop policy if exists profiles_update_admin on public.profiles;
drop policy if exists profiles_update_main_tenant on public.profiles;
create policy profiles_update_main_tenant on public.profiles
for update to authenticated
using (
  public.is_main_tenant()
  and role <> 'administrator'
)
with check (
  public.is_main_tenant()
  and role <> 'administrator'
  and (role <> 'main_tenant' or id = auth.uid())
);

drop policy if exists audit_select_admin_subtenant on public.audit_logs;
drop policy if exists audit_select_main_tenant_administrator
  on public.audit_logs;
create policy audit_select_main_tenant_administrator on public.audit_logs
for select to authenticated
using (
  public.is_main_tenant()
  or public.is_system_administrator()
  or actor_id = auth.uid()
);

drop policy if exists audit_insert_authenticated on public.audit_logs;
create policy audit_insert_authenticated on public.audit_logs
for insert to authenticated
with check (actor_id = auth.uid() or public.is_main_tenant());

commit;
