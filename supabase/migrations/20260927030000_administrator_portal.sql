-- Read-only platform oversight for the System Administrator portal.
-- This does not grant access to bookings, payments, tourism content, or other
-- Main Tenant operational data.

begin;

create or replace function public.administrator_list_accounts()
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
  banned_until timestamptz
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
    u.banned_until
  from public.profiles p
  join auth.users u on u.id = p.id
  order by u.created_at desc;
end;
$$;

revoke all on function public.administrator_list_accounts()
  from public, anon;
grant execute on function public.administrator_list_accounts()
  to authenticated;

-- The platform administrator can inspect tenant identity, assignment, and
-- activation metadata. Province/business operations remain protected by their
-- existing policies.
drop policy if exists subtenant_details_select on public.subtenant_details;
create policy subtenant_details_select on public.subtenant_details
for select to authenticated
using (
  id = auth.uid()
  or public.is_main_tenant()
  or public.is_system_administrator()
  or (
    public.current_subtenant_city() is not null
    and public.cities_match(city, public.current_subtenant_city())
  )
  or (
    public.current_subtenant_city() is null
    and is_active = true
  )
);

commit;
