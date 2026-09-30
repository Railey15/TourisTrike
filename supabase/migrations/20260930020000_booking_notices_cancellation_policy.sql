-- Versioned acknowledgments and the 24-hour, server-authoritative cancellation policy.
-- Existing bookings/accounts remain readable; new self-service actions use these guards.
begin;

alter table public.profiles
  add column if not exists privacy_notice_version text,
  add column if not exists privacy_notice_acknowledged_at timestamptz;
alter table public.package_bookings
  add column if not exists terms_version text,
  add column if not exists terms_accepted_at timestamptz;
alter table public.booking_drivers
  add column if not exists withdrawal_reason_code text,
  add column if not exists withdrawal_note text,
  add column if not exists withdrawn_at timestamptz;

-- Restore the established same-day no-downpayment rule at both the booking
-- guard and journey gate. Keep the other initial-state checks intact.
do $$
declare v_definition text := pg_get_functiondef(
  'public.guard_package_booking_client_write()'::regprocedure);
begin
  if position('new.downpayment_amount <> round(new.total_amount * 0.50, 2)' in v_definition) > 0 then
    v_definition := replace(v_definition,
      'new.downpayment_amount <> round(new.total_amount * 0.50, 2)',
      'new.downpayment_amount <> (case when lower(coalesce(new.booking_type, '''')) = ''same_day'' then 0 else round(new.total_amount * 0.50, 2) end)');
    execute v_definition || ';';
  end if;
end;
$$;
create or replace function public.is_booking_downpayment_confirmed(p_booking_id uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare b public.package_bookings;
begin
  select * into b from public.package_bookings where id=p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if lower(coalesce(b.booking_type,''))='same_day' or coalesce(b.downpayment_amount,0)<=0 then
    return true;
  end if;
  return exists(select 1 from public.payment_records pr
    where pr.booking_id=p_booking_id and pr.payment_stage in ('down_payment','full')
      and pr.status='confirmed' and pr.amount>=b.downpayment_amount);
end;
$$;
revoke all on function public.is_booking_downpayment_confirmed(uuid)
  from public, anon, authenticated;

create or replace function public.stamp_tourist_privacy_notice()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.role = 'tourist' and auth.uid() = new.id then
    if tg_op = 'INSERT' then
      if new.privacy_notice_version is distinct from '1.0' then
        raise exception 'PRIVACY_NOTICE_REQUIRED';
      end if;
      new.privacy_notice_acknowledged_at := now();
    elsif old.privacy_notice_version is null and new.privacy_notice_version is not null then
      if new.privacy_notice_version is distinct from '1.0' then
        raise exception 'PRIVACY_NOTICE_REQUIRED';
      end if;
      new.privacy_notice_acknowledged_at := now();
    elsif new.privacy_notice_version is distinct from old.privacy_notice_version
       or new.privacy_notice_acknowledged_at is distinct from old.privacy_notice_acknowledged_at then
      raise exception 'PRIVACY_ACKNOWLEDGMENT_IMMUTABLE';
    end if;
  elsif tg_op='UPDATE' and auth.uid() is not null
      and coalesce(auth.role(),'')<>'service_role'
      and (new.privacy_notice_version is distinct from old.privacy_notice_version
        or new.privacy_notice_acknowledged_at is distinct from old.privacy_notice_acknowledged_at) then
    raise exception 'PRIVACY_ACKNOWLEDGMENT_IMMUTABLE';
  end if;
  return new;
end;
$$;
drop trigger if exists stamp_tourist_privacy_notice on public.profiles;
create trigger stamp_tourist_privacy_notice
before insert or update on public.profiles
for each row execute function public.stamp_tourist_privacy_notice();

create or replace function public.register_tourist_with_privacy_notice(p_version text)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare v_profile public.profiles;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_version is distinct from '1.0' then raise exception 'PRIVACY_NOTICE_REQUIRED'; end if;
  insert into public.profiles(id, role, privacy_notice_version)
  values (auth.uid(), 'tourist', p_version)
  on conflict (id) do update set privacy_notice_version = excluded.privacy_notice_version
    where public.profiles.role = 'tourist'
      and public.profiles.privacy_notice_version is null
  returning * into v_profile;
  if v_profile.id is null then
    select * into v_profile from public.profiles where id = auth.uid() and role = 'tourist';
  end if;
  if v_profile.id is null then raise exception 'TOURIST_ROLE_REQUIRED'; end if;
  return v_profile;
end;
$$;
revoke all on function public.register_tourist_with_privacy_notice(text) from public, anon;
grant execute on function public.register_tourist_with_privacy_notice(text) to authenticated;

-- The existing booking RPC inserts the row atomically with its itinerary. Keep
-- that implementation and stamp its insert from a transaction-local version.
create or replace function public.stamp_booking_terms()
returns trigger language plpgsql set search_path = '' as $$
declare v_version text := current_setting('touristrike.booking_terms_version', true);
begin
  if v_version is distinct from '1.0' or new.tourist_id is distinct from auth.uid() then
    raise exception 'BOOKING_TERMS_REQUIRED';
  end if;
  new.terms_version := v_version;
  new.terms_accepted_at := now();
  return new;
end;
$$;
drop trigger if exists stamp_booking_terms on public.package_bookings;
create trigger stamp_booking_terms before insert on public.package_bookings
for each row execute function public.stamp_booking_terms();
create or replace function public.guard_booking_terms_immutable()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.terms_version is distinct from old.terms_version
      or new.terms_accepted_at is distinct from old.terms_accepted_at then
    raise exception 'BOOKING_TERMS_IMMUTABLE';
  end if;
  return new;
end;
$$;
drop trigger if exists guard_booking_terms_immutable on public.package_bookings;
create trigger guard_booking_terms_immutable
before update of terms_version,terms_accepted_at on public.package_bookings
for each row execute function public.guard_booking_terms_immutable();

do $$ begin
  if to_regprocedure('public.create_package_booking_accepted_terms_impl(jsonb,jsonb,jsonb)') is null then
    alter function public.create_package_booking(jsonb,jsonb,jsonb)
      rename to create_package_booking_accepted_terms_impl;
  end if;
end $$;
revoke all on function public.create_package_booking_accepted_terms_impl(jsonb,jsonb,jsonb)
  from public, anon, authenticated;
create or replace function public.create_package_booking(
  p_booking jsonb, p_customized_spots jsonb default '[]'::jsonb,
  p_itinerary_items jsonb default '[]'::jsonb
) returns public.package_bookings language plpgsql security definer set search_path = '' as $$
declare v_booking public.package_bookings;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_booking->>'terms_version' is distinct from '1.0' then
    raise exception 'BOOKING_TERMS_REQUIRED';
  end if;
  perform set_config('touristrike.booking_terms_version', '1.0', true);
  select * into v_booking from public.create_package_booking_accepted_terms_impl(
    p_booking, p_customized_spots, p_itinerary_items);
  return v_booking;
end;
$$;
revoke all on function public.create_package_booking(jsonb,jsonb,jsonb) from public, anon;
grant execute on function public.create_package_booking(jsonb,jsonb,jsonb) to authenticated;

-- The sole cutoff is scheduled_start_at as a timestamptz, compared with the
-- database clock. At exactly 24 hours the late policy applies.
create or replace function public.package_booking_cancellation_eligibility(
  p_booking_id uuid, p_actor_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  b public.package_bookings;
  v_status text;
  v_hours numeric;
  v_paid numeric := 0;
  v_available numeric := 0;
  v_refundable numeric := 0;
  v_standard boolean;
  v_assigned boolean;
  v_type text;
  v_message text;
begin
  select * into b from public.package_bookings where id = p_booking_id;
  if not found then
    return jsonb_build_object('can_cancel',false,'reason_code','BOOKING_NOT_FOUND',
      'display_message','This booking could not be found.');
  end if;
  if p_actor_id is null or b.tourist_id is distinct from p_actor_id then
    return jsonb_build_object('can_cancel',false,'reason_code','NOT_BOOKING_OWNER',
      'display_message','You are not allowed to cancel this booking.');
  end if;
  v_status := lower(coalesce(b.booking_status,b.status,''));
  if v_status = 'cancelled' or b.cancelled_at is not null then
    return jsonb_build_object('can_cancel',false,'reason_code','BOOKING_ALREADY_CANCELLED',
      'display_message','This booking has already been cancelled.');
  end if;
  if v_status in ('completed','done','refunded') then
    return jsonb_build_object('can_cancel',false,'reason_code','TOUR_ALREADY_COMPLETED',
      'display_message','Completed tours cannot be cancelled.');
  end if;
  if exists (select 1 from public.payment_disputes d
      join public.payment_records pr on pr.id=d.payment_record_id
      where pr.booking_id=p_booking_id and d.status in ('open','under_review')) then
    return jsonb_build_object('can_cancel',false,'reason_code','PAYMENT_DISPUTE_ACTIVE',
      'display_message','Cancellation is unavailable while a payment dispute is under review.');
  end if;
  if b.picked_up_at is not null or v_status = 'on_tour' or exists (
      select 1 from public.package_activities pa where pa.booking_id=p_booking_id
      and lower(coalesce(pa.tour_status,pa.status,'')) in
      ('picked_up','on_tour','en_route_to_spot','at_spot','en_route_to_dropoff',
       'ready_to_complete','dropped_off','completed')) then
    return jsonb_build_object('can_cancel',false,'tour_started',true,
      'reason_code','TOUR_ALREADY_STARTED',
      'display_message','This tour has already started. Standard booking cancellation is no longer available. Use the support/emergency process if assistance is required.');
  end if;
  if b.arrived_at is not null or exists (select 1 from public.package_activities pa
      where pa.booking_id=p_booking_id and pa.tour_status='driver_arrived') then
    return jsonb_build_object('can_cancel',false,'reason_code','DRIVER_ALREADY_ARRIVED',
      'display_message','The Driver has arrived. Use support if assistance is required.');
  end if;
  if v_status not in ('pending','confirmed','waiting_for_drivers','waiting_driver',
      'accepted','driver_accepted','driver_en_route','driver_on_the_way') then
    return jsonb_build_object('can_cancel',false,'reason_code','CANCELLATION_NOT_ALLOWED',
      'display_message','This booking is not in a cancellable state.');
  end if;
  if b.scheduled_start_at is null then
    return jsonb_build_object('can_cancel',false,'reason_code','SCHEDULE_UNAVAILABLE',
      'display_message','The scheduled tour start is unavailable. Contact support.');
  end if;
  select coalesce(sum(pr.amount),0),
    coalesce(sum(case when rr.id is null then pr.amount else 0 end),0)
    into v_paid,v_available
  from public.payment_records pr
  left join public.refund_requests rr on rr.booking_id=p_booking_id
    and rr.payment_record_id=pr.id and rr.status in ('pending','approved','completed')
  where pr.booking_id=p_booking_id and pr.status='confirmed';
  v_standard := b.scheduled_start_at > now() + interval '24 hours';
  v_hours := extract(epoch from b.scheduled_start_at-now())/3600;
  v_type := case when v_standard then 'standard' else 'late' end;
  v_refundable := case when v_standard then v_available else 0 end;
  v_assigned := b.assigned_driver_id is not null or exists (
    select 1 from public.booking_drivers bd where bd.booking_id=p_booking_id
    and bd.status='accepted');
  v_message := case when v_standard
    then 'More than 24 hours before the scheduled tour. Confirmed payments may be eligible for refund processing.'
    else 'Late cancellation: within 24 hours of the scheduled tour. Confirmed payments are normally non-refundable. Exceptional circumstances may be reviewed.' end;
  return jsonb_build_object(
    'can_cancel',true,'reason_code','CANCELLATION_ALLOWED',
    'display_message',v_message,'cancellation_type',v_type,
    'package_title',coalesce((select tp.title from public.tour_packages tp where tp.id=b.package_id),'Tour package'),
    'scheduled_at',b.scheduled_start_at,'hours_before_tour',v_hours,
    'tour_started',false,'amount_paid',v_paid,'confirmed_amount_paid',v_paid,
    'refundable_amount',v_refundable,'estimated_refundable_amount',v_refundable,
    'refund_eligible',v_refundable>0,'requires_review',not v_standard,
    'cancellation_fee',greatest(v_paid-v_refundable,0),
    'non_refundable_amount',greatest(v_paid-v_refundable,0),
    'refund_rate',case when v_standard then 100 else 0 end,
    'refund_type',case when v_paid=0 then 'no_payment'
      when v_refundable=0 then 'non_refundable' else 'full_refund_request' end,
    'has_assigned_drivers',v_assigned);
end;
$$;
revoke all on function public.package_booking_cancellation_eligibility(uuid,uuid)
  from public, anon, authenticated;

-- The established mutation locks the booking and financial rows, rechecks the
-- helper above, releases assignments, and creates unique pending refund requests.
do $$ begin
  if to_regprocedure('public.cancel_package_booking_policy_impl(uuid,text,text,text)') is null then
    alter function public.cancel_package_booking(uuid,text,text,text)
      rename to cancel_package_booking_policy_impl;
  end if;
end $$;
revoke all on function public.cancel_package_booking_policy_impl(uuid,text,text,text)
  from public, anon, authenticated;
create or replace function public.cancel_package_booking(
  p_booking_id uuid, p_reason text, p_note text default null,
  p_category text default 'general'
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_result jsonb;
  v_type text;
  v_municipality text;
  v_province text;
begin
  if p_reason not in ('change_of_plans','schedule_conflict','health_emergency',
      'weather_concern','incorrect_booking','transportation_issue','other') then
    raise exception 'CANCELLATION_REASON_REQUIRED';
  end if;
  if p_reason='other' and length(trim(coalesce(p_note,''))) < 3 then
    raise exception 'CANCELLATION_EXPLANATION_REQUIRED';
  end if;
  v_result := public.cancel_package_booking_policy_impl(
    p_booking_id,p_reason,p_note,p_category);
  v_type := v_result->>'cancellation_type';
  update public.notifications n
  set body=n.body||' Your assignment has been released.'
  where n.type='booking_cancelled' and n.title='Booking cancelled'
    and n.created_at=now()
    and exists(select 1 from public.booking_drivers bd
      where bd.booking_id=p_booking_id and bd.driver_id=n.user_id
        and bd.status='rejected');
  if v_type='late' and p_reason in ('health_emergency','weather_concern','other') then
    update public.package_bookings set cancellation_type='exceptional',
      refund_status=case when (v_result->>'amount_paid')::numeric>0
        then 'review_required' else 'not_required' end
    where id=p_booking_id;
    v_result := v_result || jsonb_build_object('cancellation_type','exceptional',
      'requires_review',true,'refund_status',
      case when (v_result->>'amount_paid')::numeric>0
        then 'review_required' else 'not_required' end);
  end if;
  select b.municipality,b.province into v_municipality,v_province from public.package_bookings b
    where b.id=p_booking_id;
  insert into public.notifications(user_id,title,body,type,is_read)
  select office.id,'Booking cancellation',
    'Booking '||p_booking_id::text||' was cancelled. Review the cancellation and any exceptional circumstances.',
    'cancellation_review',false
  from public.subtenant_details office
  join public.profiles p on p.id=office.id and p.role='subtenant'
  where office.is_active=true and public.cities_match(office.city,v_municipality)
    and public.cities_match(office.province,v_province);
  return v_result;
end;
$$;
revoke all on function public.cancel_package_booking(uuid,text,text,text)
  from public, anon;
grant execute on function public.cancel_package_booking(uuid,text,text,text)
  to authenticated;

-- Driver withdrawal reuses the existing slot-release transaction. Reasons are
-- recorded on the historical assignment; the Tourist booking stays assignable.
-- Keep the original participant boundary. Membership cleanup during withdrawal
-- skips conversation creation because the withdrawing Driver ceases to be a
-- participant as soon as the assignment becomes rejected.
create or replace function public.is_package_booking_participant(p_booking_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (
    exists(select 1 from public.package_bookings b
      where b.id=p_booking_id and b.tourist_id=auth.uid())
    or exists(select 1 from public.booking_drivers bd
      where bd.booking_id=p_booking_id and bd.driver_id=auth.uid()
        and bd.status in ('accepted','completed'))
    or public.is_provincial_admin()
    or public.subtenant_can_access_booking(p_booking_id)
  );
$$;
create or replace function public.sync_booking_group_conversation()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_conversation_id uuid;
begin
  if coalesce(current_setting('touristrike.driver_withdrawal',true),'')='true' then
    if tg_table_name='booking_drivers' and tg_op='UPDATE'
        and old.status='accepted' and new.status='rejected' then
      delete from public.conversation_members member
      using public.conversations convo
      where member.conversation_id=convo.id and convo.booking_id=new.booking_id
        and convo.conversation_type='booking_group' and member.user_id=new.driver_id;
    end if;
    return new;
  end if;
  if tg_table_name='package_bookings' then
    perform public.ensure_booking_group_conversation(new.id);
    return new;
  end if;
  v_conversation_id := public.ensure_booking_group_conversation(new.booking_id);
  if new.status in ('accepted','completed') then
    insert into public.conversation_members(conversation_id,user_id,member_role)
    values(v_conversation_id,new.driver_id,'driver') on conflict do nothing;
  elsif tg_op='UPDATE' and old.status='accepted' then
    delete from public.conversation_members
    where conversation_id=v_conversation_id and user_id=new.driver_id;
  end if;
  return new;
end;
$$;
do $$ begin
  if to_regprocedure('public.withdraw_driver_slot_impl(uuid)') is null then
    alter function public.cancel_driver_slot(uuid) rename to withdraw_driver_slot_impl;
  end if;
end $$;
revoke all on function public.withdraw_driver_slot_impl(uuid)
  from public, anon, authenticated;
create or replace function public.cancel_driver_slot(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'WITHDRAWAL_REASON_REQUIRED';
end;
$$;
revoke all on function public.cancel_driver_slot(uuid) from public, anon;
grant execute on function public.cancel_driver_slot(uuid) to authenticated;

create or replace function public.request_driver_withdrawal(
  p_booking_id uuid, p_reason text, p_note text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_driver uuid := auth.uid();
  v_booking public.package_bookings;
  v_result jsonb;
begin
  if v_driver is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_reason not in ('vehicle_problem','medical_emergency','personal_emergency',
      'unable_to_reach_pickup','safety_concern','other') then
    raise exception 'WITHDRAWAL_REASON_REQUIRED';
  end if;
  if p_reason='other' and length(trim(coalesce(p_note,'')))<3 then
    raise exception 'WITHDRAWAL_EXPLANATION_REQUIRED';
  end if;
  select * into v_booking from public.package_bookings
    where id=p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if not exists (select 1 from public.booking_drivers bd
      where bd.booking_id=p_booking_id and bd.driver_id=v_driver and bd.status='accepted') then
    raise exception 'NOT_IN_CONVOY';
  end if;
  if v_booking.picked_up_at is not null or v_booking.arrived_at is not null
     or exists(select 1 from public.package_activities pa
       where pa.booking_id=p_booking_id and lower(coalesce(pa.tour_status,'')) in
       ('driver_arrived','picked_up','on_tour','en_route_to_spot','at_spot',
        'en_route_to_dropoff','ready_to_complete','dropped_off','completed')) then
    raise exception 'TOUR_ALREADY_STARTED';
  end if;
  perform set_config('touristrike.driver_withdrawal','true',true);
  v_result := public.withdraw_driver_slot_impl(p_booking_id);
  perform set_config('touristrike.driver_withdrawal','false',true);
  update public.booking_drivers set withdrawal_reason_code=p_reason,
    withdrawal_note=nullif(trim(coalesce(p_note,'')),''),withdrawn_at=now()
  where booking_id=p_booking_id and driver_id=v_driver;
  insert into public.notifications(user_id,title,body,type,is_read)
  values(v_booking.tourist_id,'Driver reassignment',
    'Your assigned Driver is no longer available. TourisTrike is processing the driver reassignment.',
    'driver_withdrawal',false);
  insert into public.notifications(user_id,title,body,type,is_read)
  select office.id,'Driver withdrawal',
    'Booking '||p_booking_id::text||' needs Driver reassignment ('||p_reason||').',
    'driver_withdrawal',false
  from public.subtenant_details office
  join public.profiles p on p.id=office.id and p.role='subtenant'
  where office.is_active=true and public.cities_match(office.city,v_booking.municipality)
    and public.cities_match(office.province,v_booking.province);
  insert into public.audit_logs(actor_id,action,table_name,record_id,description)
  values(v_driver,'request_driver_withdrawal','booking_drivers',p_booking_id::text,p_reason);
  return v_result || jsonb_build_object('booking_cancelled',false,'reason',p_reason);
end;
$$;
revoke all on function public.request_driver_withdrawal(uuid,text,text)
  from public, anon;
grant execute on function public.request_driver_withdrawal(uuid,text,text)
  to authenticated;

commit;
