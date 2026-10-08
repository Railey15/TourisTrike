begin;

alter table public.package_bookings
  add column additional_tricycle_request_status text not null default 'none'
    check (additional_tricycle_request_status in
      ('none', 'pending', 'approved', 'rejected')),
  add column additional_tricycle_approved_count smallint not null default 0
    check (additional_tricycle_approved_count between 0 and 3),
  add column additional_tricycle_reviewed_by uuid references public.profiles(id),
  add column additional_tricycle_reviewed_at timestamptz,
  add column additional_tricycle_review_note text;

update public.package_bookings
set additional_tricycle_request_status = 'pending'
where additional_tricycle_count > 0;

alter table public.package_bookings
  add constraint additional_tricycle_review_consistency check (
    additional_tricycle_approved_count <= additional_tricycle_count
    and (additional_tricycle_request_status <> 'approved'
         or additional_tricycle_approved_count = additional_tricycle_count)
    and (additional_tricycle_request_status <> 'none'
         or additional_tricycle_count = 0)
  );

create or replace function public.guard_additional_tricycle_review_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (new.additional_tricycle_request_status,
      new.additional_tricycle_approved_count,
      new.additional_tricycle_reviewed_by,
      new.additional_tricycle_reviewed_at,
      new.additional_tricycle_review_note) is distinct from
     (old.additional_tricycle_request_status,
      old.additional_tricycle_approved_count,
      old.additional_tricycle_reviewed_by,
      old.additional_tricycle_reviewed_at,
      old.additional_tricycle_review_note)
     and (current_user in ('authenticated', 'anon')
       or coalesce(current_setting('touristrike.additional_review_write', true), '')
         <> 'true') then
    raise exception 'ADDITIONAL_TRICYCLE_REVIEW_RPC_REQUIRED';
  end if;
  return new;
end $$;
create trigger guard_additional_tricycle_review_update
before update of additional_tricycle_request_status,
  additional_tricycle_approved_count, additional_tricycle_reviewed_by,
  additional_tricycle_reviewed_at, additional_tricycle_review_note
on public.package_bookings for each row
execute function public.guard_additional_tricycle_review_update();
revoke all on function public.guard_additional_tricycle_review_update()
  from public, anon, authenticated;

-- Custom session settings alone are caller-writable. Require the trusted
-- security-definer RPC context before accepting optional-request writes.
create or replace function public.guard_additional_tricycle_request_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (new.additional_tricycle_count, new.additional_tricycle_reason,
      new.additional_tricycle_explanation) is distinct from
     (old.additional_tricycle_count, old.additional_tricycle_reason,
      old.additional_tricycle_explanation)
     and (current_user in ('authenticated', 'anon')
       or coalesce(current_setting('touristrike.additional_request_write', true), '')
         <> 'true') then
    raise exception 'ADDITIONAL_TRICYCLE_REQUEST_IMMUTABLE';
  end if;
  return new;
end $$;

-- The existing booking RPC writes the optional count immediately after
-- insertion. Mark that request pending in the same protected transaction.
create or replace function public.initialize_additional_tricycle_review()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.additional_tricycle_count = 0
     and new.additional_tricycle_count > 0
     and coalesce(current_setting('touristrike.additional_request_write', true), '')
       = 'true' then
    new.additional_tricycle_request_status := 'pending';
  end if;
  return new;
end $$;
create trigger zz_initialize_additional_tricycle_review
before update of additional_tricycle_count on public.package_bookings
for each row execute function public.initialize_additional_tricycle_review();
revoke all on function public.initialize_additional_tricycle_review()
  from public, anon, authenticated;

-- The booking's real roster target is passenger capacity plus reviewed extras.
create or replace function public.validate_booking_schedule_and_capacity()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT'
     or new.scheduled_start_at is distinct from old.scheduled_start_at
     or new.estimated_end_at is distinct from old.estimated_end_at
     or new.travel_date is distinct from old.travel_date then
    if new.scheduled_start_at is null or new.estimated_end_at is null
       or new.estimated_end_at <= new.scheduled_start_at then
      raise exception 'INVALID_BOOKING_SCHEDULE_WINDOW';
    end if;
    if new.travel_date <> (new.scheduled_start_at at time zone 'Asia/Manila')::date then
      raise exception 'PICKUP_DATE_TIME_MISMATCH';
    end if;
  end if;
  if tg_op = 'INSERT'
     or new.total_passengers is distinct from old.total_passengers
     or new.required_drivers is distinct from old.required_drivers
     or new.adults is distinct from old.adults
     or new.children is distinct from old.children then
    if new.adults < 1 or new.children < 0
       or new.total_passengers < 1
       or new.total_passengers is distinct from new.adults + new.children then
      raise exception 'INVALID_PASSENGER_COUNT';
    end if;
    if new.required_drivers is distinct from
       public.minimum_required_tricycles(new.total_passengers)
         + coalesce(new.additional_tricycle_approved_count, 0) then
      raise exception 'TRICYCLE_COUNT_MUST_MATCH_APPROVED_REQUIREMENT';
    end if;
  end if;
  return new;
end $$;

-- A Tourist may submit a new request on an existing booking before the tour
-- starts, including after a confirmed downpayment. The request itself never
-- changes the driver roster or any monetary amount.
create function public.request_additional_tricycles(
  p_booking_id uuid, p_count smallint, p_reason text,
  p_explanation text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  b public.package_bookings;
  v_explanation text := nullif(btrim(coalesce(p_explanation, '')), '');
begin
  if auth.uid() is null or public.current_profile_role() <> 'tourist' then
    raise exception 'TOURIST_ROLE_REQUIRED' using errcode = '42501';
  end if;
  select * into b from public.package_bookings where id = p_booking_id
    for update;
  if not found or b.tourist_id is distinct from auth.uid() then
    raise exception 'BOOKING_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_count is null or p_count not between 1 and 3 then
    raise exception 'ADDITIONAL_TRICYCLE_COUNT_INVALID';
  end if;
  if p_reason not in ('extra_luggage', 'accessibility_needs',
      'additional_space', 'other') or p_reason is null then
    raise exception 'ADDITIONAL_TRICYCLE_REASON_REQUIRED';
  end if;
  if (p_reason = 'other' and char_length(coalesce(v_explanation, ''))
        not between 5 and 200)
     or (p_reason <> 'other' and v_explanation is not null) then
    raise exception 'ADDITIONAL_TRICYCLE_EXPLANATION_INVALID';
  end if;
  if b.additional_tricycle_request_status in ('pending', 'approved') then
    raise exception 'REQUEST_ALREADY_EXISTS';
  end if;
  if lower(coalesce(b.booking_status, b.status, '')) not in
       ('pending', 'waiting_for_drivers', 'accepted', 'confirmed')
     or b.arrived_at is not null or b.picked_up_at is not null
     or exists (select 1 from public.package_activities a
       where a.booking_id = b.id and a.tour_status in
         ('driver_arrived', 'picked_up', 'on_tour', 'en_route_to_spot',
          'at_spot', 'en_route_to_dropoff', 'ready_to_complete',
          'completed')) then
    raise exception 'TOUR_ALREADY_STARTED';
  end if;
  if b.total_passengers = 1 then
    raise exception 'SINGLE_PASSENGER_ONE_TRICYCLE_REQUIRED';
  end if;
  perform set_config('touristrike.additional_request_write', 'true', true);
  perform set_config('touristrike.additional_review_write', 'true', true);
  update public.package_bookings set
    additional_tricycle_count = p_count,
    additional_tricycle_reason = p_reason,
    additional_tricycle_explanation = v_explanation,
    additional_tricycle_request_status = 'pending',
    additional_tricycle_reviewed_by = null,
    additional_tricycle_reviewed_at = null,
    additional_tricycle_review_note = null,
    updated_at = clock_timestamp()
  where id = b.id;
  perform set_config('touristrike.additional_request_write', '', true);
  perform set_config('touristrike.additional_review_write', '', true);
  insert into public.audit_logs(actor_id, action, table_name, record_id,
    description) values (auth.uid(), 'request_additional_tricycles',
    'package_bookings', b.id::text, 'requested=' || p_count::text);
  return jsonb_build_object('booking_id', b.id, 'status', 'pending',
    'requested_count', p_count);
end $$;
revoke all on function public.request_additional_tricycles(
  uuid,smallint,text,text) from public, anon;
grant execute on function public.request_additional_tricycles(
  uuid,smallint,text,text) to authenticated;

create or replace function public.review_additional_tricycle_request(
  p_booking_id uuid, p_approve boolean, p_note text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  b public.package_bookings;
  v_office public.subtenant_details;
  v_actor uuid := auth.uid();
  v_accepted integer;
begin
  if v_actor is null or public.current_profile_role() is distinct from 'subtenant' then
    raise exception 'MTO_ROLE_REQUIRED' using errcode = '42501';
  end if;
  select * into b from public.package_bookings where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  select * into v_office from public.subtenant_details
    where id = v_actor and is_active;
  if not found or not public.cities_match(v_office.city, b.municipality)
     or not public.cities_match(v_office.province, b.province) then
    raise exception 'MTO_SCOPE_REQUIRED' using errcode = '42501';
  end if;
  if b.additional_tricycle_request_status <> 'pending'
     or b.additional_tricycle_count <= 0 then
    raise exception 'REQUEST_NOT_PENDING';
  end if;
  if lower(coalesce(b.booking_status, b.status, '')) not in
       ('pending', 'waiting_for_drivers', 'accepted', 'confirmed')
     or b.arrived_at is not null or b.picked_up_at is not null
     or exists (select 1 from public.package_activities a
       where a.booking_id = b.id and a.tour_status in
         ('driver_arrived', 'picked_up', 'on_tour', 'en_route_to_spot',
          'at_spot', 'en_route_to_dropoff', 'ready_to_complete', 'completed')) then
    raise exception 'TOUR_ALREADY_STARTED';
  end if;
  if p_approve then
    if b.total_passengers = 1 then
      raise exception 'SINGLE_PASSENGER_ONE_TRICYCLE_REQUIRED';
    end if;
    if coalesce(b.remaining_balance, 0) <= 0 then
      raise exception 'NO_UNPAID_BALANCE_FOR_NEW_DRIVERS';
    end if;
    if abs(coalesce(b.total_amount, 0) -
        coalesce(b.downpayment_amount, 0) -
        coalesce(b.remaining_balance, 0)) > 0.01
       or exists (select 1 from public.booking_payment_requirements q
         where q.booking_id = b.id and q.payment_stage = 'remaining_balance'
           and q.status = 'required' and q.amount <> b.remaining_balance) then
      raise exception 'UNPAID_BALANCE_REVIEW_REQUIRED';
    end if;
    if exists (select 1 from public.payment_records r
      where r.booking_id = b.id and r.payment_stage in
        ('remaining_balance', 'full') and r.status <> 'cancelled') then
      raise exception 'REMAINING_PAYMENT_ALREADY_STARTED';
    end if;
    if exists (select 1 from public.booking_payment_requirements q
      where q.booking_id = b.id and q.payment_stage = 'remaining_balance'
        and q.status in ('satisfied', 'waived')) then
      raise exception 'REMAINING_PAYMENT_ALREADY_SETTLED';
    end if;
    if exists (select 1 from public.payment_records r
      where r.booking_id = b.id and r.payment_stage = 'down_payment'
        and r.status <> 'cancelled' and r.status <> 'confirmed') then
      raise exception 'DOWNPAYMENT_STILL_PENDING';
    end if;
    if exists (select 1 from public.payment_records r
      where r.booking_id = b.id and r.status = 'confirmed'
        and r.payment_stage not in ('down_payment')) then
      raise exception 'SETTLED_PAYMENT_REVIEW_REQUIRED';
    end if;
    if exists (select 1 from public.payment_records r
      where r.booking_id = b.id and r.payment_stage = 'down_payment'
        and r.status = 'confirmed'
        and (coalesce((select sum(a.gross_amount)
          from public.payment_allocations a
          where a.payment_record_id = r.id), 0) <> r.amount
          or not exists (select 1
            from public.booking_payment_requirements q
            where q.booking_id = b.id and q.payment_stage = 'down_payment'
              and q.status = 'satisfied'
              and q.satisfied_by_payment_record_id = r.id))) then
      raise exception 'DOWNPAYMENT_ALLOCATION_REVIEW_REQUIRED';
    end if;
    select count(*) into v_accepted from public.booking_drivers d
      where d.booking_id = b.id and d.status = 'accepted';
  end if;
  perform set_config('touristrike.additional_review_write', 'true', true);
  perform set_config('touristrike.validated_transition', 'true', true);
  update public.package_bookings
  set additional_tricycle_request_status =
        case when p_approve then 'approved' else 'rejected' end,
      additional_tricycle_approved_count =
        case when p_approve then additional_tricycle_count else 0 end,
      additional_tricycle_reviewed_by = v_actor,
      additional_tricycle_reviewed_at = clock_timestamp(),
      additional_tricycle_review_note = nullif(trim(coalesce(p_note, '')), ''),
      required_drivers = required_drivers +
        case when p_approve then additional_tricycle_count else 0 end,
      accepted_drivers_count = case when p_approve then v_accepted
        else accepted_drivers_count end,
      status = case when p_approve then 'pending' else status end,
      booking_status = case when p_approve then 'waiting_for_drivers'
        else booking_status end,
      updated_at = clock_timestamp()
  where id = b.id;
  perform set_config('touristrike.additional_review_write', '', true);
  perform set_config('touristrike.validated_transition', '', true);
  if p_approve then
    -- Real booking_drivers rows are created by accept_package_booking, which
    -- locks the booking and driver and checks approval, area and availability.
    insert into public.notifications(
      user_id, title, body, type, is_read, dedupe_key
    )
    select p.id, 'Tour driver slots available',
      'Additional driver slots are open for a tour in your municipality.',
      'available_package_job', false,
      'additional_job:' || b.id::text || ':' || p.id::text
    from public.profiles p
    where p.role = 'driver'
      and (coalesce(p.is_online, false) or coalesce(p.is_available, false))
      and public.cities_match(p.city, b.municipality)
      and public.cities_match(p.province, b.province)
      and not exists (select 1 from public.driver_details d
        where d.driver_id = p.id and lower(coalesce(d.status, '')) in
          ('disabled', 'inactive', 'rejected', 'suspended'))
      and (exists (select 1 from public.driver_details d
        where d.driver_id = p.id and
          (lower(coalesce(d.status, '')) in ('active', 'approved', 'verified')
           or (coalesce(d.status, '') = '' and d.approved_at is not null)))
        or (select lower(a.status) from public.driver_applications a
          where a.driver_id = p.id order by a.submitted_at desc limit 1)
          in ('active', 'approved', 'verified'))
      and not exists (select 1 from public.booking_drivers d
        where d.booking_id = b.id and d.driver_id = p.id)
    on conflict (dedupe_key) where dedupe_key is not null do nothing;
  end if;
  insert into public.audit_logs(actor_id, action, table_name, record_id,
    description) values (v_actor, 'review_additional_tricycle_request',
    'package_bookings', b.id::text,
    case when p_approve then 'approved' else 'rejected' end ||
    ' requested=' || b.additional_tricycle_count::text);
  return jsonb_build_object('booking_id', b.id,
    'status', case when p_approve then 'approved' else 'rejected' end,
    'required_drivers', b.required_drivers +
      case when p_approve then b.additional_tricycle_count else 0 end,
    'accepted_drivers', coalesce(v_accepted, b.accepted_drivers_count));
end $$;
revoke all on function public.review_additional_tricycle_request(uuid,boolean,text)
  from public, anon;
grant execute on function public.review_additional_tricycle_request(uuid,boolean,text)
  to authenticated;

commit;
