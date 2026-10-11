-- Allow a Driver to choose a supported municipality exactly once through a
-- controlled RPC. Direct self-updates of role and tenant scope remain blocked.

begin;

alter table public.profiles
  add column if not exists municipality text;

create table if not exists public.driver_municipality_assignments (
  driver_id uuid primary key references public.profiles(id) on delete cascade,
  municipality text not null,
  province text not null default 'Bulacan'
    check (province = 'Bulacan'),
  assigned_at timestamptz not null default now()
);

insert into public.driver_municipality_assignments (
  driver_id,
  municipality,
  province
)
select
  p.id,
  coalesce(nullif(trim(p.municipality), ''), nullif(trim(p.city), '')),
  'Bulacan'
from public.profiles p
where lower(trim(coalesce(p.role, ''))) = 'driver'
  and coalesce(nullif(trim(p.municipality), ''), nullif(trim(p.city), '')) is not null
on conflict (driver_id) do nothing;

update public.profiles
set municipality = city
where lower(trim(coalesce(role, ''))) = 'driver'
  and nullif(trim(municipality), '') is null
  and nullif(trim(city), '') is not null;

update public.profiles
set city = municipality
where lower(trim(coalesce(role, ''))) = 'driver'
  and nullif(trim(city), '') is null
  and nullif(trim(municipality), '') is not null;

update public.profiles
set province = 'Bulacan'
where lower(trim(coalesce(role, ''))) = 'driver'
  and nullif(trim(province), '') is null;

alter table public.driver_municipality_assignments enable row level security;

revoke all on table public.driver_municipality_assignments
  from public, anon, authenticated;
grant select on table public.driver_municipality_assignments to authenticated;

drop policy if exists driver_municipality_assignments_select
  on public.driver_municipality_assignments;
create policy driver_municipality_assignments_select
on public.driver_municipality_assignments
for select to authenticated
using (
  driver_id = auth.uid()
  or public.current_profile_role() = 'admin'
  or (
    public.current_profile_role() = 'subtenant'
    and lower(municipality) = lower(public.current_profile_city())
  )
);

-- Keep the existing self-scope protection and permit only the single atomic
-- transition backed by an immutable assignment row created by the RPC below.
create or replace function public.protect_own_profile_scope()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_initial_driver_assignment boolean := false;
begin
  if auth.uid() = old.id and coalesce(auth.role(), '') <> 'service_role' then
    if new.role is distinct from old.role
      or new.city is distinct from old.city
      or new.municipality is distinct from old.municipality
      or new.province is distinct from old.province then

      if lower(trim(coalesce(old.role, ''))) = 'driver'
        and lower(trim(coalesce(new.role, ''))) = 'driver'
        and nullif(trim(old.city), '') is null
        and nullif(trim(old.municipality), '') is null then
        select exists (
          select 1
          from public.driver_municipality_assignments assignment
          where assignment.driver_id = old.id
            and assignment.municipality = new.city
            and assignment.municipality = new.municipality
            and assignment.province = new.province
        ) into v_initial_driver_assignment;
      end if;

      if not v_initial_driver_assignment then
        raise exception 'ROLE_AND_TENANT_SCOPE_ARE_READ_ONLY';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_own_profile_scope on public.profiles;
create trigger protect_own_profile_scope
before update on public.profiles
for each row execute function public.protect_own_profile_scope();

create or replace function public.assign_initial_driver_municipality(
  p_municipality text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_role text;
  v_city text;
  v_municipality text;
  v_province text;
  v_existing_municipality text;
  v_canonical_municipality text;
begin
  if v_driver_id is null then
    raise exception 'Authentication is required.' using errcode = '28000';
  end if;

  select supported.municipality
  into v_canonical_municipality
  from (
    values
      ('Angat'),
      ('Balagtas'),
      ('Baliwag'),
      ('Bocaue'),
      ('Bulakan'),
      ('Bustos'),
      ('Calumpit'),
      ('Dona Remedios Trinidad'),
      ('Guiguinto'),
      ('Hagonoy'),
      ('Malolos'),
      ('Marilao'),
      ('Meycauayan'),
      ('Norzagaray'),
      ('Obando'),
      ('Pandi'),
      ('Paombong'),
      ('Plaridel'),
      ('Pulilan'),
      ('San Ildefonso'),
      ('San Jose del Monte'),
      ('San Miguel'),
      ('San Rafael'),
      ('Santa Maria')
  ) as supported(municipality)
  where lower(supported.municipality) = lower(trim(coalesce(p_municipality, '')));

  if v_canonical_municipality is null then
    raise exception 'UNSUPPORTED_BULACAN_MUNICIPALITY'
      using errcode = '22023';
  end if;

  select role, city, municipality, province
  into v_role, v_city, v_municipality, v_province
  from public.profiles
  where id = v_driver_id
  for update;

  if not found then
    raise exception 'Driver profile not found.' using errcode = 'P0002';
  end if;

  if lower(trim(coalesce(v_role, ''))) <> 'driver' then
    raise exception 'Only Driver accounts can assign a driver municipality.'
      using errcode = '42501';
  end if;

  v_existing_municipality := coalesce(
    nullif(trim(v_municipality), ''),
    nullif(trim(v_city), '')
  );

  if v_existing_municipality is not null then
    if lower(v_existing_municipality) = lower(v_canonical_municipality)
      and lower(trim(coalesce(v_province, 'Bulacan'))) = 'bulacan' then
      return jsonb_build_object(
        'success', true,
        'municipality', v_existing_municipality,
        'province', 'Bulacan',
        'already_assigned', true
      );
    end if;

    raise exception 'DRIVER_MUNICIPALITY_ALREADY_ASSIGNED'
      using errcode = '42501';
  end if;

  if nullif(trim(v_province), '') is not null
    and lower(trim(v_province)) <> 'bulacan' then
    raise exception 'DRIVER_PROVINCE_SCOPE_CONFLICT' using errcode = '42501';
  end if;

  insert into public.driver_municipality_assignments (
    driver_id,
    municipality,
    province
  ) values (
    v_driver_id,
    v_canonical_municipality,
    'Bulacan'
  );

  update public.profiles
  set
    city = v_canonical_municipality,
    municipality = v_canonical_municipality,
    province = 'Bulacan'
  where id = v_driver_id;

  insert into public.driver_applications (
    driver_id,
    city,
    status
  )
  select
    v_driver_id,
    v_canonical_municipality,
    'pending'
  where not exists (
    select 1
    from public.driver_applications application
    where application.driver_id = v_driver_id
  );

  return jsonb_build_object(
    'success', true,
    'municipality', v_canonical_municipality,
    'province', 'Bulacan',
    'already_assigned', false
  );
end;
$$;

revoke all on function public.assign_initial_driver_municipality(text)
  from public, anon, authenticated;
grant execute on function public.assign_initial_driver_municipality(text)
  to authenticated;

commit;
