-- RPC functions for city admin registration activation.
-- These run as security definer so approved accounts can be activated even
-- when client-side RLS would otherwise update zero profile rows.

drop function if exists public.approve_city_registration(uuid, text, text);
drop function if exists public.approve_city_registration(bigint, text, text);
drop function if exists public.approve_city_registration(text, text, text);

create function public.approve_city_registration(
  p_registration_id text,
  p_status text,
  p_rejection_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
  v_admin_role text;
  v_user_id uuid;
  v_contact_person text;
  v_office_name text;
  v_city text;
  v_contact_number text;
  v_email text;
  v_office_address text;
  v_normalized_status text;
  v_reviewed_at timestamptz := now();
  v_first_name text;
  v_last_name text;
begin
  if v_admin_id is null then
    raise exception 'Authentication is required.' using errcode = '28000';
  end if;

  select role into v_admin_role
  from public.profiles
  where id = v_admin_id;

  if lower(trim(coalesce(v_admin_role, ''))) <> 'admin' then
    raise exception 'Only admins can review registrations.' using errcode = '42501';
  end if;

  v_normalized_status := lower(trim(coalesce(p_status, '')));
  if v_normalized_status not in ('approved', 'rejected') then
    raise exception 'Invalid review status: %', p_status using errcode = '22023';
  end if;

  select
    user_id,
    contact_person,
    office_name,
    city,
    contact_number,
    email,
    office_address
  into
    v_user_id,
    v_contact_person,
    v_office_name,
    v_city,
    v_contact_number,
    v_email,
    v_office_address
  from public.city_tenant_registrations
  where id::text = p_registration_id;

  if not found then
    raise exception 'Registration not found.' using errcode = '22023';
  end if;

  if v_normalized_status = 'approved' then
    if v_user_id is null then
      raise exception 'Registration is not linked to a user account.' using errcode = '22023';
    end if;

    v_first_name := split_part(trim(coalesce(v_contact_person, '')), ' ', 1);
    v_last_name := nullif(
      trim(
        regexp_replace(
          trim(coalesce(v_contact_person, '')),
          '^[^[:space:]]+[[:space:]]*',
          ''
        )
      ),
      ''
    );

    update public.profiles
    set
      role = 'subtenant',
      first_name = coalesce(v_first_name, ''),
      last_name = coalesce(v_last_name, ''),
      full_name = v_contact_person,
      mobile = v_contact_number,
      address = v_office_address,
      city = v_city,
      province = 'Bulacan'
    where id = v_user_id;

    if not found then
      raise exception 'Applicant profile not found.' using errcode = '22023';
    end if;

    insert into public.subtenant_details (
      id,
      office_name,
      city,
      province,
      contact_person,
      contact_number,
      email,
      office_address,
      verification_status,
      is_active,
      approved_by,
      approved_at
    ) values (
      v_user_id,
      v_office_name,
      v_city,
      'Bulacan',
      v_contact_person,
      v_contact_number,
      v_email,
      v_office_address,
      'approved',
      true,
      v_admin_id,
      v_reviewed_at
    )
    on conflict (id) do update set
      office_name = excluded.office_name,
      city = excluded.city,
      province = excluded.province,
      contact_person = excluded.contact_person,
      contact_number = excluded.contact_number,
      email = excluded.email,
      office_address = excluded.office_address,
      verification_status = excluded.verification_status,
      is_active = excluded.is_active,
      approved_by = excluded.approved_by,
      approved_at = excluded.approved_at,
      updated_at = now();
  end if;

  update public.city_tenant_registrations
  set
    status = v_normalized_status,
    reviewed_by = v_admin_id,
    reviewed_at = v_reviewed_at,
    rejection_reason = case
      when v_normalized_status = 'rejected'
      then nullif(trim(coalesce(p_rejection_reason, '')), '')
      else null
    end
  where id::text = p_registration_id;

  return jsonb_build_object(
    'success', true,
    'status', v_normalized_status,
    'message', 'Registration status updated successfully.'
  );
end;
$$;

revoke all on function public.approve_city_registration(
  text,
  text,
  text
) from public;

grant execute on function public.approve_city_registration(
  text,
  text,
  text
) to authenticated;

drop function if exists public.activate_approved_city_admin();

create function public.activate_approved_city_admin()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_registration record;
  v_existing_role text;
  v_first_name text;
  v_last_name text;
begin
  if v_user_id is null then
    raise exception 'Authentication is required.' using errcode = '28000';
  end if;

  select *
  into v_registration
  from public.city_tenant_registrations
  where user_id = v_user_id
    and lower(status) = 'approved'
  order by reviewed_at desc nulls last, submitted_at desc
  limit 1;

  if not found then
    raise exception 'No approved city admin application was found.' using errcode = '42501';
  end if;

  select role
  into v_existing_role
  from public.profiles
  where id = v_user_id;

  if not found then
    raise exception 'Applicant profile not found.' using errcode = '22023';
  end if;

  if lower(trim(coalesce(v_existing_role, ''))) not in ('tourist', 'subtenant') then
    raise exception 'This account cannot be activated as a city admin.' using errcode = '42501';
  end if;

  v_first_name := split_part(trim(coalesce(v_registration.contact_person, '')), ' ', 1);
  v_last_name := nullif(
    trim(
      regexp_replace(
        trim(coalesce(v_registration.contact_person, '')),
        '^[^[:space:]]+[[:space:]]*',
        ''
      )
    ),
    ''
  );

  update public.profiles
  set
    role = 'subtenant',
    first_name = coalesce(v_first_name, ''),
    last_name = coalesce(v_last_name, ''),
    full_name = v_registration.contact_person,
    mobile = v_registration.contact_number,
    address = v_registration.office_address,
    city = v_registration.city,
    province = 'Bulacan'
  where id = v_user_id;

  insert into public.subtenant_details (
    id,
    office_name,
    city,
    province,
    contact_person,
    contact_number,
    email,
    office_address,
    verification_status,
    is_active,
    approved_by,
    approved_at
  ) values (
    v_user_id,
    v_registration.office_name,
    v_registration.city,
    'Bulacan',
    v_registration.contact_person,
    v_registration.contact_number,
    v_registration.email,
    v_registration.office_address,
    'approved',
    true,
    v_registration.reviewed_by,
    coalesce(v_registration.reviewed_at, now())
  )
  on conflict (id) do update set
    office_name = excluded.office_name,
    city = excluded.city,
    province = excluded.province,
    contact_person = excluded.contact_person,
    contact_number = excluded.contact_number,
    email = excluded.email,
    office_address = excluded.office_address,
    verification_status = excluded.verification_status,
    is_active = excluded.is_active,
    approved_by = excluded.approved_by,
    approved_at = excluded.approved_at,
    updated_at = now();

  return jsonb_build_object(
    'success', true,
    'status', 'approved',
    'message', 'City admin account activated.'
  );
end;
$$;

revoke all on function public.activate_approved_city_admin() from public;
grant execute on function public.activate_approved_city_admin() to authenticated;
