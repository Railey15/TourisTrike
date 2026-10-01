-- Read and write checks are transactional; no Driver or MTO state persists.
begin;
do $$
declare
  v_driver uuid;
  v_session uuid := gen_random_uuid();
  v_at timestamptz := now() - interval '1 minute';
  v_mto_before text;
  v_type text;
begin
  select p.id into v_driver from public.profiles p
  where p.role = 'driver' and not exists (
    select 1 from public.driver_identity_verifications v
    where v.driver_id = p.id and v.status in
      ('creating','not_started','in_progress','in_review','approved')
  ) limit 1;
  if v_driver is null then raise exception 'No available Driver fixture'; end if;
  perform set_config('test.proof_driver', v_driver::text, true);
  select status into v_mto_before from public.driver_details where driver_id = v_driver;
  insert into public.driver_identity_verifications
    (driver_id, provider_session_id, status)
  values (v_driver, v_session, 'not_started');

  if public.record_driver_verified_document_type(v_session, v_at, 'Passport') then
    raise exception 'Unapproved ID class was stored';
  end if;
  perform public.apply_driver_identity_webhook_status(v_session, 'Approved', v_at);
  if not public.record_driver_verified_document_type(v_session, v_at, 'Passport') then
    raise exception 'Approved ID class was not stored';
  end if;
  if public.record_driver_verified_document_type(v_session, v_at, 'Other') then
    raise exception 'Unrecognized ID class was stored';
  end if;
  if public.record_driver_verified_document_type(
    v_session, v_at - interval '1 second', 'Identity Card') then
    raise exception 'Stale ID class replaced the verified one';
  end if;
  select verified_document_type into v_type from public.driver_identity_verifications
  where provider_session_id = v_session;
  if v_type <> 'Passport' then raise exception 'Verified class changed'; end if;
  if (select status from public.driver_details where driver_id = v_driver)
      is distinct from v_mto_before then
    raise exception 'Didit proof changed MTO approval';
  end if;
end;
$$;

do $$ begin
  perform set_config('request.jwt.claim.sub', current_setting('test.proof_driver'), true);
end; $$;
set local role authenticated;
do $$
declare v_status text; v_type text; v_at timestamptz;
begin
  select p.status, p.verified_document_type, p.verified_at
    into v_status, v_type, v_at
  from public.get_my_driver_identity_proof() p;
  if v_status <> 'approved' or v_type <> 'Passport' or v_at is null then
    raise exception 'Driver proof projection is incomplete';
  end if;
  begin
    perform public.record_driver_verified_document_type(
      gen_random_uuid(), now(), 'Passport');
    raise exception 'Driver could write verified document type';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
rollback;
