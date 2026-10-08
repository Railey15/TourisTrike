-- Run against a linked test/staging database. All fixture writes roll back.
begin;
do $$
declare
  v_tourist uuid;
  v_other uuid;
  v_package bigint;
  v_standard uuid;
  v_exact uuid;
  v_late uuid;
  v_same_day uuid;
  v_paid uuid;
  v_started uuid;
  v_withdrawal uuid;
  v_release uuid;
  v_driver uuid;
  v_unrelated_driver uuid;
  v_foreign_office uuid;
  v_preview jsonb;
  v_result jsonb;
  v_rpc_booking public.package_bookings;
  v_rpc_payload jsonb;
begin
  select id into v_tourist from public.profiles where role='tourist' order by id limit 1;
  select id into v_other from public.profiles where role='tourist' and id<>v_tourist order by id limit 1;
  select id into v_driver from public.profiles where role='driver' and is_available=true order by id limit 1;
  select id into v_unrelated_driver from public.profiles where role='driver' and id<>v_driver order by id limit 1;
  select id into v_foreign_office from public.subtenant_details
    where city='Bustos' and is_active=true limit 1;
  select id into v_package from public.tour_packages where city='Baliwag' order by id limit 1;
  if v_tourist is null or v_other is null or v_package is null
      or v_driver is null or v_unrelated_driver is null or v_foreign_office is null then
    raise exception 'SQL_TEST_FIXTURE_MISSING';
  end if;
  perform set_config('request.jwt.claim.sub',v_tourist::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('touristrike.booking_terms_version','1.0',true);
  begin
    perform public.register_tourist_with_privacy_notice('wrong-version');
    raise exception 'WRONG_PRIVACY_VERSION_ACCEPTED';
  exception when others then
    if sqlerrm='WRONG_PRIVACY_VERSION_ACCEPTED' then raise; end if;
  end;
  perform public.register_tourist_with_privacy_notice('1.0');
  if (select privacy_notice_version from public.profiles where id=v_tourist)<>'1.0'
      or (select privacy_notice_acknowledged_at from public.profiles where id=v_tourist) is null
      or (select privacy_notice_version from public.profiles where id=v_other) is not null then
    raise exception 'PRIVACY_ACCOUNT_STAMP_FAILED';
  end if;

  v_rpc_payload := jsonb_build_object(
    'package_id',v_package,'travel_date',((now()+interval '48 hours') at time zone 'Asia/Manila')::date,
    'scheduled_start_at',now()+interval '48 hours',
    'estimated_end_at',now()+interval '54 hours',
    'adults',1,'children',0,'total_passengers',1,'required_drivers',1,
    'total_amount',1000,'downpayment_amount',500,'remaining_balance',500,
    'booking_type','advanced','payment_method','gcash',
    'municipality','Baliwag','province','Bulacan',
    'pickup_latitude',14.9599615,'pickup_longitude',120.8898492,
    'dropoff_latitude',14.9599615,'dropoff_longitude',120.8898492,
    'terms_version','1.0');
  begin
    perform public.create_package_booking(v_rpc_payload - 'terms_version');
    raise exception 'MISSING_TERMS_ACCEPTED';
  exception when others then
    if sqlerrm<>'BOOKING_TERMS_REQUIRED' then raise; end if;
  end;
  select * into v_rpc_booking from public.create_package_booking(v_rpc_payload);
  if v_rpc_booking.terms_version<>'1.0' or v_rpc_booking.terms_accepted_at is null then
    raise exception 'BOOKING_RPC_TERMS_STAMP_FAILED';
  end if;
  perform public.cancel_package_booking(v_rpc_booking.id,'change_of_plans');

  insert into public.package_bookings(package_id,tourist_id,travel_date,
    scheduled_start_at,estimated_end_at,total_amount,downpayment_amount,
    remaining_balance,booking_type,payment_method,municipality,province,
    pickup_latitude,pickup_longitude,dropoff_latitude,dropoff_longitude)
  values(v_package,v_tourist,((now()+interval '24 hours 1 minute') at time zone 'Asia/Manila')::date,
    now()+interval '24 hours 1 minute',now()+interval '30 hours',
    1000,500,500,'advanced','gcash','Baliwag','Bulacan',
    14.9599615,120.8898492,14.9599615,120.8898492) returning id into v_standard;
  select public.get_package_booking_cancellation_eligibility(v_standard) into v_preview;
  if v_preview->>'cancellation_type'<>'standard' or (v_preview->>'can_cancel')::boolean is not true
      or (v_preview->>'amount_paid')::numeric<>0 or (v_preview->>'refundable_amount')::numeric<>0 then
    raise exception 'STANDARD_BOUNDARY_FAILED: %',v_preview;
  end if;
  if (select terms_version from public.package_bookings where id=v_standard)<>'1.0'
      or (select terms_accepted_at from public.package_bookings where id=v_standard) is null then
    raise exception 'TERMS_STAMP_FAILED';
  end if;
  perform set_config('request.jwt.claim.sub',v_foreign_office::text,true);
  if public.subtenant_can_access_booking(v_standard) then
    raise exception 'CROSS_MUNICIPALITY_ACCESS_ALLOWED';
  end if;
  perform set_config('request.jwt.claim.sub',v_other::text,true);
  select public.get_package_booking_cancellation_eligibility(v_standard) into v_preview;
  if v_preview->>'reason_code'<>'NOT_BOOKING_OWNER' then
    raise exception 'CROSS_USER_PREVIEW_ALLOWED';
  end if;
  begin
    perform public.cancel_package_booking(v_standard,'change_of_plans');
    raise exception 'CROSS_USER_CANCELLATION_ALLOWED';
  exception when others then
    if sqlerrm='CROSS_USER_CANCELLATION_ALLOWED' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub',v_tourist::text,true);
  select public.cancel_package_booking(v_standard,'change_of_plans') into v_result;
  if v_result->>'cancellation_type'<>'standard'
      or exists(select 1 from public.refund_requests where booking_id=v_standard) then
    raise exception 'STANDARD_ZERO_REFUND_FAILED: %',v_result;
  end if;

  insert into public.package_bookings(package_id,tourist_id,travel_date,
    scheduled_start_at,estimated_end_at,total_amount,downpayment_amount,
    remaining_balance,booking_type,payment_method,municipality,province,
    pickup_latitude,pickup_longitude,dropoff_latitude,dropoff_longitude)
  values(v_package,v_tourist,((now()+interval '24 hours') at time zone 'Asia/Manila')::date,
    now()+interval '24 hours',now()+interval '29 hours',
    1000,500,500,'advanced','gcash','Baliwag','Bulacan',
    14.9599615,120.8898492,14.9599615,120.8898492) returning id into v_exact;
  select public.get_package_booking_cancellation_eligibility(v_exact) into v_preview;
  if v_preview->>'cancellation_type'<>'late' then
    raise exception 'EXACT_24H_BOUNDARY_FAILED: %',v_preview;
  end if;
  perform public.cancel_package_booking(v_exact,'schedule_conflict');

  insert into public.package_bookings(package_id,tourist_id,travel_date,
    scheduled_start_at,estimated_end_at,total_amount,downpayment_amount,
    remaining_balance,booking_type,payment_method,municipality,province,
    pickup_latitude,pickup_longitude,dropoff_latitude,dropoff_longitude)
  values(v_package,v_tourist,((now()+interval '23 hours 59 minutes') at time zone 'Asia/Manila')::date,
    now()+interval '23 hours 59 minutes',now()+interval '29 hours',
    1000,500,500,'advanced','gcash','Baliwag','Bulacan',
    14.9599615,120.8898492,14.9599615,120.8898492) returning id into v_late;
  select public.get_package_booking_cancellation_eligibility(v_late) into v_preview;
  if v_preview->>'cancellation_type'<>'late' or (v_preview->>'refundable_amount')::numeric<>0 then
    raise exception 'LATE_23H59M_FAILED: %',v_preview;
  end if;

  select public.cancel_package_booking(v_late,'health_emergency') into v_result;
  if v_result->>'cancellation_type'<>'exceptional'
      or (select status from public.package_bookings where id=v_late)<>'cancelled'
      or exists(select 1 from public.refund_requests where booking_id=v_late) then
    raise exception 'EXCEPTIONAL_CANCEL_FAILED: %',v_result;
  end if;
  select public.get_package_booking_cancellation_eligibility(v_late) into v_preview;
  if v_preview->>'reason_code'<>'BOOKING_ALREADY_CANCELLED' then
    raise exception 'DUPLICATE_CANCELLATION_ALLOWED';
  end if;

  insert into public.package_bookings(package_id,tourist_id,travel_date,
    scheduled_start_at,estimated_end_at,total_amount,downpayment_amount,
    remaining_balance,booking_type,payment_method,municipality,province,
    pickup_latitude,pickup_longitude,dropoff_latitude,dropoff_longitude)
  values(v_package,v_tourist,((now()+interval '6 hours') at time zone 'Asia/Manila')::date,
    now()+interval '6 hours',now()+interval '12 hours',
    1000,500,500,'same_day','gcash','Baliwag','Bulacan',
    14.9599615,120.8898492,14.9599615,120.8898492) returning id into v_same_day;
  if public.is_booking_downpayment_confirmed(v_same_day) then
    raise exception 'SAME_DAY_DOWNPAYMENT_BYPASS_REMAINED';
  end if;
  perform public.cancel_package_booking(v_same_day,'change_of_plans');
  if exists(select 1 from public.refund_requests where booking_id=v_same_day) then
    raise exception 'FAKE_SAME_DAY_REFUND_CREATED';
  end if;

  insert into public.package_bookings(package_id,tourist_id,travel_date,
    scheduled_start_at,estimated_end_at,total_amount,downpayment_amount,
    remaining_balance,booking_type,payment_method,municipality,province,
    pickup_latitude,pickup_longitude,dropoff_latitude,dropoff_longitude)
  values(v_package,v_tourist,((now()+interval '48 hours') at time zone 'Asia/Manila')::date,
    now()+interval '48 hours',now()+interval '54 hours',
    1000,500,500,'advanced','gcash','Baliwag','Bulacan',
    14.9599615,120.8898492,14.9599615,120.8898492) returning id into v_paid;
  insert into public.booking_payment_requirements(booking_id,payment_stage,amount)
    values(v_paid,'down_payment',500);
  insert into public.payment_records(booking_id,payer_id,amount,payment_method,
    payment_stage,status,provider,currency,provider_reference,provider_status,paid_at)
  values(v_paid,v_tourist,500,'gcash','down_payment','confirmed','paymongo','PHP',
    'sql-test-'||gen_random_uuid()::text,'paid',now());
  select public.get_package_booking_cancellation_eligibility(v_paid) into v_preview;
  if (v_preview->>'amount_paid')::numeric<>500
      or (v_preview->>'refundable_amount')::numeric<>500 then
    raise exception 'CONFIRMED_PAYMENT_PREVIEW_FAILED: %',v_preview;
  end if;
  perform public.cancel_package_booking(v_paid,'change_of_plans');
  if (select count(*) from public.refund_requests where booking_id=v_paid
      and amount=500 and status='pending')<>1
      or (select refund_status from public.package_bookings where id=v_paid)<>'pending' then
    raise exception 'REFUND_REQUEST_NOT_CREATED';
  end if;

  insert into public.package_bookings(package_id,tourist_id,travel_date,
    scheduled_start_at,estimated_end_at,total_amount,downpayment_amount,
    remaining_balance,booking_type,payment_method,municipality,province,
    pickup_latitude,pickup_longitude,dropoff_latitude,dropoff_longitude)
  values(v_package,v_tourist,((now()+interval '48 hours') at time zone 'Asia/Manila')::date,
    now()+interval '48 hours',now()+interval '54 hours',
    1000,500,500,'advanced','gcash','Baliwag','Bulacan',
    14.9599615,120.8898492,14.9599615,120.8898492) returning id into v_release;
  insert into public.booking_drivers(booking_id,driver_id,status)
    values(v_release,v_driver,'accepted');
  perform public.cancel_package_booking(v_release,'change_of_plans');
  if (select status from public.booking_drivers where booking_id=v_release
      and driver_id=v_driver)<>'rejected'
      or not exists(select 1 from public.notifications where user_id=v_driver
        and type='booking_cancelled')
      or not exists(select 1 from public.notifications where user_id=v_tourist
        and type='booking_cancelled')
      or not exists(select 1 from public.notifications where type='cancellation_review'
        and user_id not in (v_tourist,v_driver)) then
    raise exception 'TOURIST_CANCELLATION_RELEASE_OR_NOTICE_FAILED';
  end if;

  insert into public.package_bookings(package_id,tourist_id,travel_date,
    scheduled_start_at,estimated_end_at,total_amount,downpayment_amount,
    remaining_balance,booking_type,payment_method,municipality,province,
    pickup_latitude,pickup_longitude,dropoff_latitude,dropoff_longitude)
  values(v_package,v_tourist,((now()+interval '48 hours') at time zone 'Asia/Manila')::date,
    now()+interval '48 hours',now()+interval '54 hours',
    1000,500,500,'advanced','gcash','Baliwag','Bulacan',
    14.9599615,120.8898492,14.9599615,120.8898492) returning id into v_withdrawal;
  insert into public.booking_drivers(booking_id,driver_id,status)
    values(v_withdrawal,v_driver,'accepted');
  perform set_config('request.jwt.claim.sub',v_unrelated_driver::text,true);
  begin
    perform public.request_driver_withdrawal(v_withdrawal,'vehicle_problem');
    raise exception 'UNRELATED_DRIVER_WITHDREW';
  exception when others then
    if sqlerrm='UNRELATED_DRIVER_WITHDREW' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub',v_driver::text,true);
  begin
    perform public.cancel_driver_slot(v_withdrawal);
    raise exception 'LEGACY_DRIVER_CANCEL_ALLOWED';
  exception when others then
    if sqlerrm='LEGACY_DRIVER_CANCEL_ALLOWED' then raise; end if;
  end;
  perform public.request_driver_withdrawal(v_withdrawal,'vehicle_problem');
  if (select status from public.package_bookings where id=v_withdrawal)='cancelled'
      or (select status from public.booking_drivers where booking_id=v_withdrawal
          and driver_id=v_driver)<>'rejected'
      or (select withdrawal_reason_code from public.booking_drivers
          where booking_id=v_withdrawal and driver_id=v_driver)<>'vehicle_problem'
      or not exists(select 1 from public.notifications where user_id=v_tourist
          and type='driver_withdrawal')
      or not exists(select 1 from public.notifications where type='driver_withdrawal'
          and user_id<>v_tourist) then
    raise exception 'DRIVER_WITHDRAWAL_FAILED';
  end if;
  perform set_config('request.jwt.claim.sub',v_tourist::text,true);
  perform public.cancel_package_booking(v_withdrawal,'change_of_plans');

  insert into public.package_bookings(package_id,tourist_id,travel_date,
    scheduled_start_at,estimated_end_at,total_amount,downpayment_amount,
    remaining_balance,booking_type,payment_method,municipality,province,
    pickup_latitude,pickup_longitude,dropoff_latitude,dropoff_longitude)
  values(v_package,v_tourist,((now()+interval '48 hours') at time zone 'Asia/Manila')::date,
    now()+interval '48 hours',now()+interval '54 hours',
    1000,500,500,'advanced','gcash','Baliwag','Bulacan',
    14.9599615,120.8898492,14.9599615,120.8898492) returning id into v_started;
  update public.package_bookings set picked_up_at=now() where id=v_started;
  select public.get_package_booking_cancellation_eligibility(v_started) into v_preview;
  if v_preview->>'reason_code'<>'TOUR_ALREADY_STARTED' then
    raise exception 'STARTED_TOUR_CANCELLABLE: %',v_preview;
  end if;
  raise notice 'PASS: terms stamp, 24h boundaries, same-day, cross-user, exceptional, duplicate';
end;
$$;
rollback;
