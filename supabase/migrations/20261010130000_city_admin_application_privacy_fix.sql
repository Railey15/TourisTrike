-- Keep City/Municipal Admin applications separate from Tourist registration.
-- An authenticated applicant is represented by auth.users until the Main
-- Tenant approves the application and creates the subtenant profile.

begin;

alter table public.city_tenant_registrations
  drop constraint if exists city_tenant_registrations_user_id_fkey;

alter table public.city_tenant_registrations
  add constraint city_tenant_registrations_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

create or replace function public.submit_city_admin_application(
  p_city text,
  p_office_name text,
  p_contact_person text,
  p_contact_number text,
  p_email text,
  p_office_address text,
  p_first_name text default '',
  p_last_name text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_existing_role text;
  v_latest_status text;
  v_latest_reason text;
  v_registration_id text;
  v_authenticated_email text;
  v_city text := nullif(trim(coalesce(p_city, '')), '');
  v_office_name text := nullif(trim(coalesce(p_office_name, '')), '');
  v_contact_person text := nullif(trim(coalesce(p_contact_person, '')), '');
  v_contact_number text := nullif(trim(coalesce(p_contact_number, '')), '');
  v_email text := lower(nullif(trim(coalesce(p_email, '')), ''));
  v_office_address text := nullif(trim(coalesce(p_office_address, '')), '');
begin
  if v_user_id is null then
    raise exception 'Authentication is required to submit a city admin application.'
      using errcode = '28000';
  end if;

  if v_city is null then
    raise exception 'City or municipality is required.'
      using errcode = '22023';
  end if;

  if v_office_name is null then
    v_office_name := v_city || ' Tourism Office';
  end if;

  if v_contact_person is null then
    raise exception 'Authorized contact person is required.'
      using errcode = '22023';
  end if;

  if v_contact_number is null then
    raise exception 'Official contact number is required.'
      using errcode = '22023';
  end if;

  if v_email is null then
    raise exception 'Official email address is required.'
      using errcode = '22023';
  end if;

  if v_office_address is null then
    raise exception 'Office address is required.'
      using errcode = '22023';
  end if;

  select lower(nullif(trim(email), ''))
  into v_authenticated_email
  from auth.users
  where id = v_user_id;

  if v_authenticated_email is null or v_email <> v_authenticated_email then
    raise exception 'Official email must match the authenticated account.'
      using errcode = '42501';
  end if;

  select role
  into v_existing_role
  from public.profiles
  where id = v_user_id;

  if lower(trim(coalesce(v_existing_role, ''))) = 'subtenant' then
    return jsonb_build_object(
      'status', 'approved',
      'message', 'This account is already approved as a city admin.'
    );
  elsif v_existing_role is not null then
    raise exception 'This email already belongs to a % account. Use a dedicated office email or contact the main admin.', v_existing_role
      using errcode = '42501';
  end if;

  select status, rejection_reason
  into v_latest_status, v_latest_reason
  from public.city_tenant_registrations
  where user_id = v_user_id
  order by submitted_at desc
  limit 1;

  if lower(coalesce(v_latest_status, '')) in ('pending', 'approved') then
    return jsonb_build_object(
      'status', lower(v_latest_status),
      'rejection_reason', coalesce(v_latest_reason, '')
    );
  end if;

  insert into public.city_tenant_registrations (
    user_id,
    city,
    office_name,
    contact_person,
    contact_number,
    email,
    office_address,
    status
  )
  values (
    v_user_id,
    v_city,
    v_office_name,
    v_contact_person,
    v_contact_number,
    v_email,
    v_office_address,
    'pending'
  )
  returning id::text into v_registration_id;

  return jsonb_build_object(
    'status', 'pending',
    'registration_id', v_registration_id
  );
end;
$$;

revoke all on function public.submit_city_admin_application(
  text, text, text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.submit_city_admin_application(
  text, text, text, text, text, text, text, text
) to authenticated;

create or replace function public.approve_city_registration(
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
  v_user_id uuid;
  v_contact_person text;
  v_office_name text;
  v_city text;
  v_contact_number text;
  v_email text;
  v_office_address text;
  v_existing_role text;
  v_normalized_status text;
  v_reviewed_at timestamptz := now();
  v_first_name text;
  v_last_name text;
begin
  if v_admin_id is null then
    raise exception 'Authentication is required.' using errcode = '28000';
  end if;

  if not public.is_provincial_admin() then
    raise exception 'Only the Main Tenant can review registrations.' using errcode = '42501';
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
  where id::text = p_registration_id
  for update;

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

    select role
    into v_existing_role
    from public.profiles
    where id = v_user_id
    for update;

    if v_existing_role is not null
       and lower(trim(v_existing_role)) <> 'subtenant' then
      raise exception 'Applicant already has a % profile and cannot be approved as a city admin.', v_existing_role
        using errcode = '42501';
    end if;

    insert into public.profiles (
      id,
      role,
      first_name,
      last_name,
      full_name,
      mobile,
      address,
      city,
      province
    ) values (
      v_user_id,
      'subtenant',
      coalesce(v_first_name, ''),
      coalesce(v_last_name, ''),
      v_contact_person,
      v_contact_number,
      v_office_address,
      v_city,
      'Bulacan'
    )
    on conflict (id) do update set
      first_name = excluded.first_name,
      last_name = excluded.last_name,
      full_name = excluded.full_name,
      mobile = excluded.mobile,
      address = excluded.address,
      city = excluded.city,
      province = excluded.province
    where public.profiles.role = 'subtenant';

    select role
    into v_existing_role
    from public.profiles
    where id = v_user_id;

    if lower(trim(coalesce(v_existing_role, ''))) <> 'subtenant' then
      raise exception 'Applicant profile could not be safely activated as a city admin.'
        using errcode = '42501';
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
      'verified',
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

revoke all on function public.approve_city_registration(text, text, text)
  from public, anon, authenticated;
grant execute on function public.approve_city_registration(text, text, text)
  to authenticated;

-- Compatibility for approved applications created before approval became
-- atomic. This may create a missing subtenant profile, but never converts an
-- existing Tourist or Driver profile.
create or replace function public.activate_approved_city_admin()
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
  where id = v_user_id
  for update;

  if v_existing_role is not null
     and lower(trim(v_existing_role)) <> 'subtenant' then
    raise exception 'This account already has a % profile and cannot be activated as a city admin.', v_existing_role
      using errcode = '42501';
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

  insert into public.profiles (
    id,
    role,
    first_name,
    last_name,
    full_name,
    mobile,
    address,
    city,
    province
  ) values (
    v_user_id,
    'subtenant',
    coalesce(v_first_name, ''),
    coalesce(v_last_name, ''),
    v_registration.contact_person,
    v_registration.contact_number,
    v_registration.office_address,
    v_registration.city,
    'Bulacan'
  )
  on conflict (id) do update set
    first_name = excluded.first_name,
    last_name = excluded.last_name,
    full_name = excluded.full_name,
    mobile = excluded.mobile,
    address = excluded.address,
    city = excluded.city,
    province = excluded.province
  where public.profiles.role = 'subtenant';

  select role
  into v_existing_role
  from public.profiles
  where id = v_user_id;

  if lower(trim(coalesce(v_existing_role, ''))) <> 'subtenant' then
    raise exception 'Applicant profile could not be safely activated as a city admin.'
      using errcode = '42501';
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
    v_registration.office_name,
    v_registration.city,
    'Bulacan',
    v_registration.contact_person,
    v_registration.contact_number,
    v_registration.email,
    v_registration.office_address,
    'verified',
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

revoke all on function public.activate_approved_city_admin()
  from public, anon, authenticated;
grant execute on function public.activate_approved_city_admin()
  to authenticated;

commit;
