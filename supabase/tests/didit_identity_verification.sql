-- Transactional smoke test; every inserted verification and audit row is rolled back.
begin;
do $$
declare
  v_driver uuid;
  v_session uuid := gen_random_uuid();
  v_unknown uuid := gen_random_uuid();
  v_approval text;
  v_documents integer;
  v_time timestamptz := now() - interval '2 minutes';
  v_status text;
begin
  select p.id into v_driver from public.profiles p
  where p.role = 'driver' and not exists (
    select 1 from public.driver_identity_verifications v
    where v.driver_id = p.id and v.status in
      ('creating','not_started','in_progress','in_review','approved')
  ) limit 1;
  if v_driver is null then
    raise exception 'No available Driver fixture for transactional test';
  end if;
  select status into v_approval from public.driver_details where driver_id = v_driver;
  select count(*) into v_documents from public.driver_documents where driver_id = v_driver;

  if public.apply_driver_identity_webhook_status(v_unknown, 'Approved', v_time) then
    raise exception 'Unknown session modified a verification';
  end if;
  insert into public.driver_identity_verifications
    (driver_id, provider_session_id, status)
  values (v_driver, v_session, 'not_started');
  if not public.apply_driver_identity_webhook_status(v_session, 'Declined', v_time) then
    raise exception 'Linked declined result was not applied';
  end if;
  select status into v_status from public.driver_identity_verifications
  where provider_session_id = v_session;
  if v_status <> 'declined' then raise exception 'Declined mapping failed'; end if;
  if not public.apply_driver_identity_webhook_status(
    v_session, 'Approved', v_time + interval '1 minute') then
    raise exception 'Linked approved result was not applied';
  end if;
  perform public.apply_driver_identity_webhook_status(v_session, 'Declined', v_time);
  perform public.apply_driver_identity_webhook_status(
    v_session, 'Approved', v_time + interval '1 minute');
  select status into v_status from public.driver_identity_verifications
  where provider_session_id = v_session;
  if v_status <> 'approved' then
    raise exception 'Duplicate or out-of-order event regressed identity status';
  end if;
  if (select status from public.driver_details where driver_id = v_driver)
      is distinct from v_approval then
    raise exception 'Identity result changed MTO approval';
  end if;
  if (select count(*) from public.driver_documents where driver_id = v_driver)
      <> v_documents then
    raise exception 'Identity result changed Driver documents';
  end if;
  update public.driver_identity_verifications set status = 'declined'
  where provider_session_id = v_session;
  insert into public.driver_identity_verifications (driver_id, created_at)
  values (v_driver, clock_timestamp());
  perform public.apply_driver_identity_webhook_status(
    v_session, 'Resubmitted', v_time + interval '2 minutes');
  select status into v_status from public.driver_identity_verifications
  where provider_session_id = v_session;
  if v_status <> 'declined' then
    raise exception 'Late old-session event displaced a newer attempt';
  end if;
end;
$$;
do $$
begin
  perform set_config('request.jwt.claim.sub',
    (select id::text from public.profiles where role = 'driver' limit 1), true);
  perform set_config('test.other_driver',
    (select id::text from public.profiles where role = 'driver' offset 1 limit 1), true);
end;
$$;
set local role authenticated;
do $$
begin
  perform public.get_driver_identity_verification_status();
  begin
    perform public.get_driver_identity_verification_status(
      current_setting('test.other_driver')::uuid);
    raise exception 'Driver read another Driver identity status';
  exception when insufficient_privilege then null;
  end;
  begin
    execute 'update public.driver_identity_verifications set status = ''approved'' '
      || 'where driver_id = $1' using auth.uid();
    raise exception 'Driver self-approved identity';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
do $$
declare v_mto uuid; v_city text;
begin
  select sd.id, sd.city into v_mto, v_city
  from public.subtenant_details sd
  join public.profiles p on p.id = sd.id and p.role = 'subtenant'
  where sd.is_active = true
    and exists (select 1 from public.profiles d
      where d.role = 'driver' and public.cities_match(d.city, sd.city))
    and exists (select 1 from public.profiles d
      where d.role = 'driver' and not public.cities_match(d.city, sd.city))
  limit 1;
  if v_mto is null then raise exception 'No scoped MTO fixture'; end if;
  perform set_config('request.jwt.claim.sub', v_mto::text, true);
  perform set_config('test.in_scope_driver',
    (select d.id::text from public.profiles d
      where d.role = 'driver' and public.cities_match(d.city, v_city) limit 1), true);
  perform set_config('test.out_scope_driver',
    (select d.id::text from public.profiles d
      where d.role = 'driver' and not public.cities_match(d.city, v_city) limit 1), true);
end;
$$;
set local role authenticated;
do $$
begin
  perform public.get_driver_identity_verification_status(
    current_setting('test.in_scope_driver')::uuid);
  begin
    perform public.get_driver_identity_verification_status(
      current_setting('test.out_scope_driver')::uuid);
    raise exception 'MTO read an out-of-scope Driver identity status';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
rollback;
