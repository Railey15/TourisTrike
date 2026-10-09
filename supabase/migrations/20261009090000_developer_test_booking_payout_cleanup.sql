-- Administrator Developer Tools: purge booking-scoped TEST payout records
-- together with an authorized TEST booking. Production and in-flight provider
-- money movement stays protected. All changes run in one transaction.
begin;

create or replace function public.administrator_delete_test_booking_legacy(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_booking public.package_bookings;
  v_activity_ids uuid[];
begin
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  select * into v_booking from public.package_bookings
  where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  -- Match the unfiltered Developer Tools list scope, independent of whether
  -- this booking ever had a test session or its session has expired.
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
      in ('cancelled', 'rejected', 'completed', 'expired') then
    raise exception 'BOOKING_NOT_ELIGIBLE_FOR_DEVELOPER_CLEANUP';
  end if;

  -- Lock financial rows while classifying them. The booking row lock also blocks
  -- new booking-scoped FK inserts until this transaction finishes.
  perform 1 from public.payment_records where booking_id=p_booking_id for update;
  perform 1 from public.payment_allocations where booking_id=p_booking_id for update;
  perform 1 from public.payout_records where booking_id=p_booking_id for update;
  perform 1 from public.payment_provider_events e where exists (
    select 1 from public.payment_records p where p.booking_id=p_booking_id
      and (e.payment_record_id=p.id
        or (e.payment_record_id is null and e.provider=p.provider and p.provider_checkout_id is not null and e.provider_checkout_id=p.provider_checkout_id)
        or (e.payment_record_id is null and e.provider=p.provider and p.provider_payment_id is not null and e.provider_payment_id=p.provider_payment_id))
  ) for update;

  if exists(select 1 from public.refund_requests where booking_id=p_booking_id) then
    raise exception 'BOOKING_HAS_REFUND';
  end if;
  if exists(select 1 from public.payment_disputes where booking_id=p_booking_id) then
    raise exception 'BOOKING_HAS_DISPUTE';
  end if;
  if exists(select 1 from public.booking_payment_requirements r
      join public.payment_records p on p.id=r.satisfied_by_payment_record_id
      where r.booking_id=p_booking_id and p.booking_id is distinct from p_booking_id)
     or exists(select 1 from public.payment_allocations a
      join public.payment_records p on p.id=a.payment_record_id
      where a.booking_id=p_booking_id and p.booking_id is distinct from p_booking_id) then
    raise exception 'BOOKING_HAS_PAYMENT_EVIDENCE';
  end if;
  -- Delete only TEST payout records. A processing payout may still have an
  -- in-flight provider request, so it is never purged by this RPC.
  if exists(select 1 from public.payout_records payout
      where payout.booking_id=p_booking_id
        and (payout.provider_livemode is distinct from false
          or payout.status='processing'
          or (payout.source_payment_record_id is not null and not exists(
            select 1 from public.payment_records p
            where p.id=payout.source_payment_record_id
              and p.booking_id=p_booking_id))
          or (payout.payment_allocation_id is not null and not exists(
            select 1 from public.payment_allocations a
            where a.id=payout.payment_allocation_id
              and a.booking_id=p_booking_id)))) then
    raise exception 'BOOKING_HAS_PRODUCTION_PAYOUT';
  end if;
  -- A pending allocation is an internal payout instruction. A recorded
  -- sandbox transfer may be purged only with its TEST PayMongo payment.
  if exists(select 1 from public.payment_allocations a
      left join public.payment_records p on p.id=a.payment_record_id
      where a.booking_id=p_booking_id
        and (a.status='processing'
          or ((coalesce(a.status,'') not in
                ('held','eligible','failed','cancelled','pending')
              or a.provider_transfer_id is not null
              or a.provider_transfer_status is not null
              or a.paid_at is not null)
            and (p.booking_id is distinct from p_booking_id
              or p.provider is distinct from 'paymongo'
              or p.provider_livemode is distinct from false)))) then
    raise exception 'BOOKING_HAS_PRODUCTION_TRANSFER';
  end if;
  -- A PayMongo receipt is disposable only when both the payment and every
  -- associated provider event explicitly identify the sandbox environment.
  if exists(select 1 from public.payment_provider_events e where e.provider_livemode is distinct from false
      and exists(select 1 from public.payment_records p where p.booking_id=p_booking_id
        and (e.payment_record_id=p.id
          or (e.payment_record_id is null and e.provider=p.provider and p.provider_checkout_id is not null and e.provider_checkout_id=p.provider_checkout_id)
          or (e.payment_record_id is null and e.provider=p.provider and p.provider_payment_id is not null and e.provider_payment_id=p.provider_payment_id))))
     or exists(select 1 from public.payment_records p where p.booking_id=p_booking_id
      and coalesce(p.provider,'manual') <> 'manual' and p.provider_livemode is distinct from false) then
    raise exception 'BOOKING_HAS_LIVE_PROVIDER_PAYMENT';
  end if;
  if exists(select 1 from public.payment_records p where p.booking_id=p_booking_id
      and not ((p.provider='paymongo' and p.provider_livemode is false)
        or (coalesce(p.provider,'manual')='manual'
          and p.status in ('pending_confirmation','cancelled')
          and p.provider_livemode is null and p.paid_at is null
          and p.payee_confirmed_at is null and p.receipt_no is null
          and p.external_reference_no is null and p.proof_image_url is null
          and p.provider_payment_id is null and p.provider_checkout_id is null
          and p.provider_reference is null))) then
    raise exception 'BOOKING_HAS_PAYMENT_EVIDENCE';
  end if;
  if exists(select 1 from public.emergency_alerts where booking_id=p_booking_id) then
    raise exception 'BOOKING_HAS_EMERGENCY_RECORD';
  end if;
  if exists(select 1 from public.driver_reviews where booking_id=p_booking_id)
     or exists(select 1 from public.package_reviews where booking_id=p_booking_id)
     or exists(select 1 from public.tourist_reviews where booking_id=p_booking_id) then
    raise exception 'BOOKING_HAS_REVIEW';
  end if;

  insert into public.audit_logs(actor_id,action,table_name,record_id,description)
  values(auth.uid(),'DEVELOPER_TEST_BOOKING_DELETE','package_bookings',
    p_booking_id::text,jsonb_build_object('booking_id',p_booking_id,
    'scope','developer_tools_booking_cleanup')::text);

  select array_agg(id) into v_activity_ids from public.package_activities
  where booking_id=p_booking_id;
  -- These are shared Driver rows; remove only the link to this booking's activity.
  update public.driver_live_locations set activity_id=null
  where activity_id=any(coalesce(v_activity_ids,array[]::uuid[]));
  -- Notification delivery rows have a text identifier rather than an FK.
  delete from public.notification_deliveries delivery
  using public.notifications notice
  where delivery.notification_id=notice.id::text
    and notice.booking_id=p_booking_id;
  delete from public.notifications where booking_id=p_booking_id;
  -- Booking conversations have SET NULL on booking deletion; remove their
  -- messages and members through the conversation's own declared cascades.
  delete from public.conversations where booking_id=p_booking_id;
  -- Test trip events can be removed; the separate administrator audit stays.
  delete from public.trip_status_logs where booking_id=p_booking_id;
  -- Requirements and allocations reference payment records without cascade.
  -- Delete sandbox events before their payment FK would otherwise become null.
  delete from public.booking_payment_requirements where booking_id=p_booking_id;
  delete from public.payout_records where booking_id=p_booking_id;
  delete from public.payment_allocations where booking_id=p_booking_id;
  delete from public.payment_provider_events e where exists (
    select 1 from public.payment_records p where p.booking_id=p_booking_id
      and (e.payment_record_id=p.id
        or (e.payment_record_id is null and e.provider=p.provider and p.provider_checkout_id is not null and e.provider_checkout_id=p.provider_checkout_id)
        or (e.payment_record_id is null and e.provider=p.provider and p.provider_payment_id is not null and e.provider_payment_id=p.provider_payment_id))
  );
  delete from public.payment_records where booking_id=p_booking_id;
  delete from public.booking_stop_waiting_charges where booking_id=p_booking_id;
  delete from public.booking_custom_fare_quotes where booking_id=p_booking_id;
  -- Other dependent test rows use their declared FK cascades. Assignment rows
  -- must go first because they also reference package_activities without cascade.
  delete from public.booking_drivers where booking_id=p_booking_id;
  delete from public.package_bookings where id=p_booking_id;
  return jsonb_build_object('success',true,'booking_id',p_booking_id);
exception when foreign_key_violation then
  raise exception 'BOOKING_HAS_OTHER_REFERENCE';
end;
$$;
revoke all on function public.administrator_delete_test_booking_legacy(uuid)
  from public, anon, authenticated;

create or replace function public.administrator_delete_test_booking(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.booking_test_admin_authorized(p_booking_id) then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if not coalesce((select s.developer_testing_enabled
      from public.system_settings s where s.singleton),false)
      or not exists(select 1 from public.developer_test_sessions d
        where d.booking_id=p_booking_id and d.status='active'
          and d.expires_at>now()) then
    raise exception 'ACTIVE_DEVELOPER_TEST_SESSION_REQUIRED';
  end if;
  return public.administrator_delete_test_booking_legacy(p_booking_id);
end $$;
revoke all on function public.administrator_delete_test_booking(uuid)
  from public, anon;
grant execute on function public.administrator_delete_test_booking(uuid)
  to authenticated;

commit;
