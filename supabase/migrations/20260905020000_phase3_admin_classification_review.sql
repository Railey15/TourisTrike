-- Phase 3: track Provincial Admin review of inferred LGU classification.
-- Depends on 20260905010000_phase2_subtenant_office_identity.sql.

begin;

alter table public.subtenant_details
  add column if not exists local_government_type_reviewed boolean
  not null default false;

-- The Admin header search uses bounded ILIKE queries. Trigram indexes keep
-- those lookups responsive without downloading province-wide tables.
create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;
set local search_path = public, extensions;

create index if not exists subtenant_details_admin_search_idx
  on public.subtenant_details using gin (
    city gin_trgm_ops,
    office_name gin_trgm_ops,
    contact_person gin_trgm_ops,
    email gin_trgm_ops
  );
create index if not exists tourist_spots_admin_search_idx
  on public.tourist_spots using gin (
    title gin_trgm_ops,
    city gin_trgm_ops,
    barangay gin_trgm_ops
  );
create index if not exists tour_packages_admin_search_idx
  on public.tour_packages using gin (
    title gin_trgm_ops,
    city gin_trgm_ops
  );
create index if not exists profiles_driver_admin_search_idx
  on public.profiles using gin (
    full_name gin_trgm_ops,
    first_name gin_trgm_ops,
    last_name gin_trgm_ops,
    mobile gin_trgm_ops,
    city gin_trgm_ops
  ) where role = 'driver';

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
set local_government_type_reviewed = true
from assignment_registration ar
where ar.id = sd.id
  and (
    concat_ws(
      ' ', sd.city, sd.office_name, sd.office_address,
      ar.office_name, ar.office_address
    ) ~* '(^|[^a-z])(city|municipal(ity)?)([^a-z]|$)'
  );

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
  v_has_explicit_type boolean;
begin
  if nullif(trim(new.office_name), '') is not null then
    new.office_name_customized := true;
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
    ' ', new.city, new.office_name, new.office_address,
    v_registration_office_name, v_registration_office_address
  );
  v_has_explicit_type :=
    v_source ~* '(^|[^a-z])(city|municipal(ity)?)([^a-z]|$)';

  if new.local_government_type is null then
    new.local_government_type := case
      when v_source ~* '(^|[^a-z])city([^a-z]|$)' then 'city'
      else 'municipality'
    end;
  end if;
  new.local_government_type_reviewed :=
    new.local_government_type_reviewed or v_has_explicit_type;
  return new;
end;
$$;

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
       or new.local_government_type_reviewed is distinct from
          old.local_government_type_reviewed
       or new.verification_status is distinct from old.verification_status
       or new.is_active is distinct from old.is_active
       or new.approved_by is distinct from old.approved_by
       or new.approved_at is distinct from old.approved_at
       or new.created_at is distinct from old.created_at
     ) then
    raise exception 'SUBTENANT_ASSIGNMENT_IS_ADMIN_MANAGED'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

commit;
