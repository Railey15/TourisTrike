-- Run in a transaction and always ROLLBACK. Synthetic auth/profile/office
-- fixtures exercise the real deployed schema; no existing account is edited.
create temporary table historical_gate_results(name text primary key) on commit drop;
do $$
declare
  v_main uuid := 'f0000000-0000-4000-8000-000000000001';
  v_sub uuid := 'f0000000-0000-4000-8000-000000000002';
  v_driver uuid := 'f0000000-0000-4000-8000-000000000003';
  v_tourist uuid := 'f0000000-0000-4000-8000-000000000004';
  v_other uuid := 'f0000000-0000-4000-8000-000000000005';
  v_actor uuid; v_item uuid; v_booking uuid; v_city text; v_province text;
begin
  if exists(select 1 from auth.users where id in (v_main,v_sub,v_driver,v_tourist,v_other)) then
    raise exception 'FIXTURE_IDS_ALREADY_EXIST';
  end if;
  select i.id,b.id,t.city,b.province into strict v_item,v_booking,v_city,v_province
  from public.booking_itinerary_items i join public.package_bookings b on b.id=i.booking_id
  join public.tour_packages t on t.id=b.package_id
  where nullif(trim(t.city),'') is not null and nullif(trim(b.province),'') is not null
  order by i.id limit 1;
  perform set_config('gate.item',v_item::text,true);
  perform set_config('gate.booking',v_booking::text,true);
  perform set_config('gate.city',v_city,true);
  perform set_config('gate.province',v_province,true);
  foreach v_actor in array array[v_main,v_sub,v_driver,v_tourist,v_other] loop
    insert into auth.users(id) values(v_actor);
  end loop;
  -- Normal provisioning is tested under authenticated below. Staff fixtures
  -- represent trusted provisioning, using the existing authoritative sources.
  insert into public.profiles(id,role,province) values(v_main,'main_tenant',v_province);
  insert into public.profiles(id,role) values(v_sub,'subtenant');
  insert into public.subtenant_details(id,city,province,is_active)
    values(v_sub,v_city,v_province,true);
end $$;
grant select,insert on historical_gate_results to authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
set local role authenticated;
do $$
declare
 v_driver uuid := 'f0000000-0000-4000-8000-000000000003';
 v_tourist uuid := 'f0000000-0000-4000-8000-000000000004';
 v_other uuid := 'f0000000-0000-4000-8000-000000000005';
 v_role text; v_field text; v_id uuid; v_count integer;
begin
 foreach v_id in array array[v_driver,v_tourist] loop
   perform set_config('request.jwt.claim.sub',v_id::text,true);
   v_role := case when v_id=v_driver then 'driver' else 'tourist' end;
   insert into public.profiles(id,role) values(v_id,v_role);
   if not exists(select 1 from public.profiles where id=v_id
       and not is_verified and not coalesce(is_approved,false)
       and verification_status='pending' and driver_status='pending') then
     raise exception 'PROVISIONING_DEFAULTS_WRONG';
   end if;
   insert into historical_gate_results values('legitimate_'||v_role||'_provisioning');
 end loop;
 perform set_config('request.jwt.claim.sub',v_other::text,true);
 begin
   insert into public.profiles(id,role) values(gen_random_uuid(),'tourist');
   raise exception 'CROSS_USER_INSERT_ALLOWED';
 exception when insufficient_privilege then null;
 end;
 insert into historical_gate_results values('cross_user_insert_denied');
 foreach v_role in array array['administrator','main_tenant','subtenant'] loop
   begin
     insert into public.profiles(id,role) values(v_other,v_role);
     raise exception 'PRIVILEGED_INSERT_ALLOWED: %',v_role;
   exception when insufficient_privilege then null;
   end;
   insert into historical_gate_results values('privileged_insert_denied_'||v_role);
 end loop;
 foreach v_field in array array['is_approved','is_verified','verification_status','driver_status'] loop
   begin
     execute format('insert into public.profiles(id,role,%I) values($1,''driver'',%s)',
       v_field,case when v_field in ('is_approved','is_verified') then 'true' else quote_literal('approved') end) using v_other;
     raise exception 'APPROVAL_INSERT_ALLOWED: %',v_field;
   exception when insufficient_privilege then null;
   end;
   insert into historical_gate_results values('approval_insert_denied_'||v_field);
 end loop;
 perform set_config('request.jwt.claim.sub',v_driver::text,true);
 insert into public.driver_details(driver_id) values(v_driver);
 if not exists(select 1 from public.driver_details where driver_id=v_driver and status='pending' and approved_by is null and approved_at is null)
   then raise exception 'DRIVER_DETAILS_DEFAULTS_WRONG'; end if;
 insert into historical_gate_results values('driver_details_onboarding');
 begin
   update public.driver_details set status='approved' where driver_id=v_driver;
   raise exception 'DRIVER_DETAILS_SELF_APPROVAL_ALLOWED';
 exception when insufficient_privilege then null;
 end;
 insert into historical_gate_results values('driver_details_self_approval_denied');
 insert into public.driver_applications(driver_id,city) values(v_driver,current_setting('gate.city'));
 begin
   update public.driver_applications set status='approved' where driver_id=v_driver;
   raise exception 'DRIVER_APPLICATION_SELF_APPROVAL_ALLOWED';
 exception when insufficient_privilege then null;
 end;
 insert into historical_gate_results values('driver_application_self_approval_denied');
 begin
   update public.profiles set is_approved=true where id=v_driver;
   raise exception 'PROFILE_SELF_APPROVAL_ALLOWED';
 exception when insufficient_privilege then null;
 end;
 insert into historical_gate_results values('profile_self_approval_denied');
 foreach v_id in array array[v_driver,v_tourist] loop
   perform set_config('request.jwt.claim.sub',v_id::text,true);
   select count(*) into v_count from public.booking_itinerary_items where id=current_setting('gate.item')::uuid;
   if v_count<>0 then raise exception 'UNRELATED_ITINERARY_VISIBLE'; end if;
   begin
     perform public.ensure_booking_itinerary(current_setting('gate.booking')::uuid);
     raise exception 'UNRELATED_INITIALIZER_ALLOWED';
   exception when insufficient_privilege then null;
   end;
   insert into historical_gate_results values('unrelated_itinerary_denied_'||v_id);
 end loop;
end $$;
reset role;
-- Change synthetic staff assignments only, then exercise actual RLS.
do $$
declare v_province text;
begin
 foreach v_province in array array[current_setting('gate.province'),'Another Province','','   ','#INVALID#',null] loop
   perform set_config('request.jwt.claim.sub','',true);
   update public.profiles set province=v_province where id='f0000000-0000-4000-8000-000000000001';
   perform set_config('request.jwt.claim.sub','f0000000-0000-4000-8000-000000000001',true);
   execute 'set local role authenticated';
   if (select count(*) from public.booking_itinerary_items where id=current_setting('gate.item')::uuid)
      <> (case when v_province=current_setting('gate.province') then 1 else 0 end) then
     raise exception 'MAIN_TENANT_PROVINCE_GATE_FAILED: %',v_province;
   end if;
   update public.booking_itinerary_items set updated_at=updated_at where id=current_setting('gate.item')::uuid;
   if found then raise exception 'MAIN_TENANT_ITINERARY_UPDATE_ALLOWED'; end if;
   delete from public.booking_itinerary_items where id=current_setting('gate.item')::uuid;
   if found then raise exception 'MAIN_TENANT_ITINERARY_DELETE_ALLOWED'; end if;
   execute 'reset role';
   insert into historical_gate_results values('main_province_'||coalesce(quote_nullable(v_province),'NULL'));
 end loop;
end $$;
do $$
declare v_case integer; v_count integer;
begin
 for v_case in 1..4 loop
   perform set_config('request.jwt.claim.sub','',true);
   update public.subtenant_details
     set city=case when v_case=3 then 'Other City' when v_case=4 then '' else current_setting('gate.city') end,
         province=case when v_case=2 then 'Another Province' else current_setting('gate.province') end
     where id='f0000000-0000-4000-8000-000000000002';
   perform set_config('request.jwt.claim.sub','f0000000-0000-4000-8000-000000000002',true);
   execute 'set local role authenticated';
   select count(*) into v_count from public.booking_itinerary_items where id=current_setting('gate.item')::uuid;
   if v_count <> (case when v_case=1 then 1 else 0 end) then raise exception 'SUBTENANT_SCOPE_GATE_FAILED: %',v_case; end if;
   -- Staff reads introduce no direct itinerary modification rights.
   update public.booking_itinerary_items set updated_at=updated_at where id=current_setting('gate.item')::uuid;
   get diagnostics v_count=row_count;
   if v_count<>0 then raise exception 'STAFF_ITINERARY_UPDATE_ALLOWED'; end if;
   delete from public.booking_itinerary_items where id=current_setting('gate.item')::uuid;
   get diagnostics v_count=row_count;
   if v_count<>0 then raise exception 'STAFF_ITINERARY_DELETE_ALLOWED'; end if;
   execute 'reset role';
   insert into historical_gate_results values('subtenant_scope_'||v_case);
 end loop;
end $$;
select set_config('request.jwt.claim.sub','',true);
