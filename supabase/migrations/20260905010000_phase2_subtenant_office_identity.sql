-- Phase 2: assignment-owned LGU classification and editable generated office names.
-- Depends on 20260905000000_phase1_subtenant_scope_and_settings.sql.

begin;

alter table public.subtenant_details
  add column if not exists local_government_type text,
  add column if not exists office_name_customized boolean not null default false;

-- Existing office names came from an application or an administrator, so they
-- must be preserved as custom names. Blank names remain eligible for generation.
update public.subtenant_details
set office_name_customized = true
where nullif(trim(office_name), '') is not null;

-- Prefer explicit wording already stored in assignment/registration data. This
-- avoids maintaining a hardcoded municipality list in the client.
with assignment_registration as (
  select sd.id, registration.office_name, registration.office_address
  from public.subtenant_details sd
  left join lateral (
    select ctr.office_name, ctr.office_address
    from public.city_tenant_registrations ctr
    where ctr.user_id = sd.id
       or public.cities_match(ctr.city, sd.city)
    order by
      (ctr.user_id = sd.id) desc,
      ctr.reviewed_at desc nulls last,
      ctr.submitted_at desc
    limit 1
  ) registration on true
)
update public.subtenant_details sd
set local_government_type = case
  when concat_ws(
    ' ',
    sd.city,
    sd.office_name,
    sd.office_address,
    assignment_registration.office_name,
    assignment_registration.office_address
  ) ~* '(^|[^a-z])city([^a-z]|$)'
    then 'city'
  when concat_ws(
    ' ',
    sd.city,
    sd.office_name,
    sd.office_address,
    assignment_registration.office_name,
    assignment_registration.office_address
  ) ~* '(^|[^a-z])municipal(ity)?([^a-z]|$)'
    then 'municipality'
  else 'municipality'
end
from assignment_registration
where assignment_registration.id = sd.id
  and sd.local_government_type is null;

-- Rows without a matching registration still get a deterministic safe default.
update public.subtenant_details
set local_government_type = case
  when city ~* '(^city[[:space:]]+of[[:space:]]+|[[:space:]]+city$)'
    then 'city'
  else 'municipality'
end
where local_government_type is null;

alter table public.subtenant_details
  alter column local_government_type drop default,
  alter column local_government_type set not null;

alter table public.subtenant_details
  drop constraint if exists subtenant_details_local_government_type_check;
alter table public.subtenant_details
  add constraint subtenant_details_local_government_type_check
  check (local_government_type in ('city', 'municipality'));

create or replace function public.set_subtenant_local_government_type()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_registration_office_name text;
  v_registration_office_address text;
  v_source text;
begin
  if nullif(trim(new.office_name), '') is not null then
    new.office_name_customized := true;
  end if;

  if new.local_government_type is not null then
    return new;
  end if;

  select ctr.office_name, ctr.office_address
  into v_registration_office_name, v_registration_office_address
  from public.city_tenant_registrations ctr
  where ctr.user_id = new.id
     or public.cities_match(ctr.city, new.city)
  order by
    (ctr.user_id = new.id) desc,
    ctr.reviewed_at desc nulls last,
    ctr.submitted_at desc
  limit 1;

  v_source := concat_ws(
    ' ',
    new.city,
    new.office_name,
    new.office_address,
    v_registration_office_name,
    v_registration_office_address
  );
  new.local_government_type := case
    when v_source ~* '(^|[^a-z])city([^a-z]|$)' then 'city'
    when v_source ~* '(^|[^a-z])municipal(ity)?([^a-z]|$)'
      then 'municipality'
    else 'municipality'
  end;
  return new;
end;
$$;

drop trigger if exists set_subtenant_local_government_type
  on public.subtenant_details;
create trigger set_subtenant_local_government_type
before insert on public.subtenant_details
for each row execute function public.set_subtenant_local_government_type();

revoke all on function public.set_subtenant_local_government_type()
  from public, anon, authenticated;

-- A Subtenant may change its public office name and marker, but the assigned
-- city, province, and LGU classification remain administrator-controlled.
create or replace function public.guard_subtenant_assignment_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if auth.uid() = old.id and not public.is_provincial_admin() then
      raise exception 'SUBTENANT_ASSIGNMENT_IS_ADMIN_MANAGED'
        using errcode = '42501';
    end if;
    return old;
  end if;

  if auth.uid() = old.id
     and not public.is_provincial_admin()
     and (
       new.id is distinct from old.id
       or new.city is distinct from old.city
       or new.province is distinct from old.province
       or new.local_government_type is distinct from old.local_government_type
       or new.verification_status is distinct from old.verification_status
       or new.is_active is distinct from old.is_active
       or new.approved_by is distinct from old.approved_by
       or new.approved_at is distinct from old.approved_at
       or new.created_at is distinct from old.created_at
     ) then
    raise exception 'SUBTENANT_ASSIGNMENT_IS_ADMIN_MANAGED' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- Old rows may retain a disabled preference, but AI is no longer optional for
-- Subtenant workflows. Keep the legacy column true for backward compatibility.
update public.admin_settings settings
set enable_ai_suggestions = true,
    updated_at = now()
from public.profiles profile
where profile.id = settings.user_id
  and profile.role = 'subtenant'
  and settings.enable_ai_suggestions is distinct from true;

commit;
