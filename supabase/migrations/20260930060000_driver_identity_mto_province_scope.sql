-- Apply the MTO's active municipality and province assignment to identity results.
create or replace function public.get_driver_identity_verification_status(
  p_driver_id uuid default null
)
returns table(status text, provider_status text, updated_at timestamptz, verified_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_target uuid := coalesce(p_driver_id, auth.uid());
  v_role text;
begin
  if auth.uid() is null or v_target is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select p.role into v_role from public.profiles p where p.id = auth.uid();
  if not (
    (v_role = 'driver' and v_target = auth.uid())
    or (v_role = 'subtenant' and public.subtenant_can_access_driver(v_target)
      and exists (
        select 1 from public.subtenant_details sd
        join public.profiles driver on driver.id = v_target
        where sd.id = auth.uid() and sd.is_active = true
          and driver.role = 'driver'
          and nullif(trim(sd.province), '') is not null
          and lower(trim(sd.province)) = lower(trim(driver.province))
      ))
    or (v_role = 'main_tenant' and exists (
      select 1 from public.profiles viewer join public.profiles driver on driver.id = v_target
      where viewer.id = auth.uid() and driver.role = 'driver'
        and nullif(trim(viewer.province), '') is not null
        and lower(trim(viewer.province)) = lower(trim(driver.province))
    ))
    or v_role = 'administrator'
  ) then
    raise exception 'IDENTITY_STATUS_FORBIDDEN' using errcode = '42501';
  end if;
  return query select v.status, v.provider_status, v.updated_at, v.verified_at
  from public.driver_identity_verifications v
  where v.driver_id = v_target
  order by v.created_at desc limit 1;
end;
$$;
