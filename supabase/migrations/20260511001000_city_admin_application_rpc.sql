-- Submit city admin applications through a server-side auth.uid() check.
-- This avoids client-side RLS timing issues immediately after OTP verification.

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
  v_registration_id uuid;
  v_city text := nullif(trim(coalesce(p_city, '')), '');
  v_office_name text := nullif(trim(coalesce(p_office_name, '')), '');
  v_contact_person text := nullif(trim(coalesce(p_contact_person, '')), '');
  v_contact_number text := nullif(trim(coalesce(p_contact_number, '')), '');
  v_email text := lower(nullif(trim(coalesce(p_email, '')), ''));
  v_office_address text := nullif(trim(coalesce(p_office_address, '')), '');
  v_first_name text := nullif(trim(coalesce(p_first_name, '')), '');
  v_last_name text := nullif(trim(coalesce(p_last_name, '')), '');
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

  if v_email is null then
    raise exception 'Official email address is required.'
      using errcode = '22023';
  end if;

  select role
  into v_existing_role
  from public.profiles
  where id = v_user_id;

  if v_existing_role is null then
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
    )
    values (
      v_user_id,
      'tourist',
      v_first_name,
      v_last_name,
      v_contact_person,
      v_contact_number,
      v_office_address,
      v_city,
      'Bulacan'
    );
  elsif lower(trim(v_existing_role)) = 'subtenant' then
    return jsonb_build_object(
      'status', 'approved',
      'message', 'This account is already approved as a city admin.'
    );
  elsif lower(trim(v_existing_role)) <> 'tourist' then
    raise exception 'This email already belongs to a % account. Use a dedicated office email or contact the main admin.', v_existing_role
      using errcode = '42501';
  else
    update public.profiles
    set
      first_name = v_first_name,
      last_name = v_last_name,
      full_name = v_contact_person,
      mobile = v_contact_number,
      address = v_office_address,
      city = v_city,
      province = 'Bulacan'
    where id = v_user_id;
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
  returning id into v_registration_id;

  return jsonb_build_object(
    'status', 'pending',
    'registration_id', v_registration_id
  );
end;
$$;

revoke all on function public.submit_city_admin_application(
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text
) from public;

grant execute on function public.submit_city_admin_application(
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text
) to authenticated;
