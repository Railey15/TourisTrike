-- Atomic tourist package-booking cancellation and auditable direct-payment
-- refund requests. TourisTrike never represents a direct GCash transfer as
-- reversed until the payee/admin records that the refund was actually made.

alter table public.package_bookings
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid references public.profiles(id) on delete set null,
  add column if not exists cancellation_note text,
  add column if not exists cancellation_category text,
  add column if not exists cancellation_type text,
  add column if not exists cancellation_fee numeric not null default 0,
  add column if not exists refundable_amount numeric not null default 0,
  add column if not exists refund_status text not null default 'not_required';

alter table public.package_activities
  add column if not exists cancelled_at timestamptz;

create table if not exists public.package_cancellation_policy (
  id smallint primary key default 1 check (id = 1),
  free_cancellation_hours integer not null default 24 check (free_cancellation_hours > 0),
  late_cancellation_hours integer not null default 6 check (late_cancellation_hours >= 0),
  standard_refund_percent numeric not null default 50
    check (standard_refund_percent between 0 and 100),
  late_refund_percent numeric not null default 0
    check (late_refund_percent between 0 and 100),
  same_day_assigned_refund_percent numeric not null default 0
    check (same_day_assigned_refund_percent between 0 and 100),
  default_tour_start_time time not null default time '08:00',
  updated_at timestamptz not null default now()
);

insert into public.package_cancellation_policy (id)
values (1)
on conflict (id) do nothing;

create table if not exists public.refund_requests (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.package_bookings(id) on delete restrict,
  payment_record_id uuid not null references public.payment_records(id) on delete restrict,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  payee_id uuid not null references public.profiles(id) on delete restrict,
  amount numeric not null check (amount > 0),
  reason text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'completed', 'rejected')),
  requested_at timestamptz not null default now(),
  approved_at timestamptz,
  completed_at timestamptz,
  completed_by uuid references public.profiles(id) on delete set null,
  reference_no text,
  resolution_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (booking_id, payment_record_id)
);

create index if not exists refund_requests_booking_idx
  on public.refund_requests(booking_id, created_at desc);
create index if not exists refund_requests_payee_idx
  on public.refund_requests(payee_id, status, created_at desc);

drop trigger if exists set_package_cancellation_policy_updated_at
  on public.package_cancellation_policy;
create trigger set_package_cancellation_policy_updated_at
  before update on public.package_cancellation_policy
  for each row execute function public.set_updated_at();

drop trigger if exists set_refund_requests_updated_at
  on public.refund_requests;
create trigger set_refund_requests_updated_at
  before update on public.refund_requests
  for each row execute function public.set_updated_at();

alter table public.package_cancellation_policy enable row level security;
alter table public.refund_requests enable row level security;

drop policy if exists cancellation_policy_read on public.package_cancellation_policy;
create policy cancellation_policy_read on public.package_cancellation_policy
  for select to authenticated using (true);

drop policy if exists cancellation_policy_staff_update on public.package_cancellation_policy;
create policy cancellation_policy_staff_update on public.package_cancellation_policy
  for update to authenticated
  using (public.current_profile_role() in ('admin', 'subtenant'))
  with check (public.current_profile_role() in ('admin', 'subtenant'));

drop policy if exists refund_requests_read_involved on public.refund_requests;
create policy refund_requests_read_involved on public.refund_requests
  for select to authenticated using (
    requested_by = auth.uid()
    or payee_id = auth.uid()
    or public.current_profile_role() = 'admin'
  );

-- Refund rows contain immutable financial evidence. They are resolved through
-- a narrow RPC below instead of allowing arbitrary client-side updates.
drop policy if exists refund_requests_payee_or_staff_update on public.refund_requests;

create or replace function public.package_booking_cancellation_eligibility(
  p_booking_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings%rowtype;
  v_policy public.package_cancellation_policy%rowtype;
  v_status text;
  v_tour_status text;
  v_scheduled_at timestamp;
  v_hours_before numeric;
  v_amount_paid numeric := 0;
  v_refund_rate numeric := 0;
  v_fee numeric := 0;
  v_refundable numeric := 0;
  v_has_driver boolean := false;
  v_type text;
  v_message text;
begin
  select * into v_booking
  from public.package_bookings
  where id = p_booking_id;

  if not found then
    return jsonb_build_object(
      'can_cancel', false,
      'reason_code', 'BOOKING_NOT_FOUND',
      'display_message', 'This booking could not be found.'
    );
  end if;

  if p_actor_id is null or v_booking.tourist_id <> p_actor_id then
    return jsonb_build_object(
      'can_cancel', false,
      'reason_code', 'NOT_BOOKING_OWNER',
      'display_message', 'You are not allowed to cancel this booking.'
    );
  end if;

  v_status := lower(coalesce(v_booking.booking_status, v_booking.status, 'pending'));

  if v_status = 'cancelled' or v_booking.cancelled_at is not null then
    return jsonb_build_object(
      'can_cancel', false,
      'reason_code', 'BOOKING_ALREADY_CANCELLED',
      'display_message', 'This booking has already been cancelled.'
    );
  end if;

  if v_status in ('completed', 'done', 'refunded') then
    return jsonb_build_object(
      'can_cancel', false,
      'reason_code', 'TOUR_ALREADY_COMPLETED',
      'display_message', 'Completed bookings can no longer be cancelled.'
    );
  end if;

  if exists (
    select 1
    from public.payment_disputes d
    join public.payment_records pr on pr.id = d.payment_record_id
    where pr.booking_id = p_booking_id
      and d.status in ('open', 'under_review')
  ) then
    return jsonb_build_object(
      'can_cancel', false,
      'reason_code', 'PAYMENT_DISPUTE_ACTIVE',
      'display_message', 'Cancellation is unavailable while a payment dispute is under review.'
    );
  end if;

  select lower(coalesce(pa.tour_status, pa.status, 'waiting_driver'))
  into v_tour_status
  from public.package_activities pa
  where pa.booking_id = p_booking_id
  order by case lower(coalesce(pa.tour_status, pa.status, ''))
    when 'completed' then 100
    when 'ready_to_complete' then 90
    when 'en_route_to_dropoff' then 80
    when 'at_spot' then 70
    when 'en_route_to_spot' then 60
    when 'on_tour' then 50
    when 'picked_up' then 40
    when 'driver_arrived' then 30
    else 0 end desc
  limit 1;

  v_tour_status := coalesce(v_tour_status, 'waiting_driver');

  if v_tour_status = 'driver_arrived' or v_booking.arrived_at is not null then
    return jsonb_build_object(
      'can_cancel', false,
      'reason_code', 'DRIVER_ALREADY_ARRIVED',
      'display_message', 'This tour can no longer be cancelled because the driver has already arrived.'
    );
  end if;

  if v_tour_status in (
    'picked_up', 'on_tour', 'en_route_to_spot', 'at_spot',
    'en_route_to_dropoff', 'ready_to_complete', 'dropped_off', 'completed'
  ) or v_booking.picked_up_at is not null or v_status = 'on_tour' then
    return jsonb_build_object(
      'can_cancel', false,
      'reason_code', 'TOUR_ALREADY_STARTED',
      'display_message', 'This tour can no longer be cancelled because it has already started.'
    );
  end if;

  if v_status not in (
    'pending', 'confirmed', 'waiting_for_drivers', 'waiting_driver',
    'accepted', 'driver_accepted', 'driver_en_route', 'driver_on_the_way'
  ) then
    return jsonb_build_object(
      'can_cancel', false,
      'reason_code', 'CANCELLATION_NOT_ALLOWED',
      'display_message', 'This booking is not in a cancellable state.'
    );
  end if;

  select * into v_policy from public.package_cancellation_policy where id = 1;

  select coalesce(sum(amount), 0) into v_amount_paid
  from public.payment_records
  where booking_id = p_booking_id and status = 'confirmed';

  v_has_driver := coalesce(v_booking.accepted_drivers_count, 0) > 0
    or v_booking.assigned_driver_id is not null
    or exists (
      select 1 from public.booking_drivers
      where booking_id = p_booking_id and status = 'accepted'
    );

  -- The current booking UI stores a date, not a separate start time. Until a
  -- scheduled timestamp is added to booking creation, policy uses the single
  -- configurable default start time in Asia/Manila.
  v_scheduled_at := v_booking.travel_date::timestamp + v_policy.default_tour_start_time;
  v_hours_before := extract(epoch from (
    v_scheduled_at - timezone('Asia/Manila', now())
  )) / 3600;

  if lower(coalesce(v_booking.booking_type, 'advanced')) = 'same_day' then
    if not v_has_driver then
      v_type := 'free_cancellation';
      v_refund_rate := 100;
      v_message := 'No driver has accepted yet. Confirmed payments are eligible for a full refund request.';
    else
      v_type := 'driver_assigned_cancellation';
      v_refund_rate := v_policy.same_day_assigned_refund_percent;
      v_message := 'A driver is already assigned. This is treated as a late cancellation.';
    end if;
  elsif v_hours_before > v_policy.free_cancellation_hours then
    v_type := 'free_cancellation';
    v_refund_rate := 100;
    v_message := 'You are cancelling more than ' ||
      v_policy.free_cancellation_hours ||
      ' hours before the tour. Confirmed payments are eligible for a full refund request.';
  elsif v_hours_before >= v_policy.late_cancellation_hours then
    v_type := 'standard_cancellation';
    v_refund_rate := v_policy.standard_refund_percent;
    v_message := 'This is a late cancellation. A partial refund may apply to confirmed payments.';
  else
    v_refund_rate := v_policy.late_refund_percent;
    v_type := case when v_refund_rate > 0
      then 'late_cancellation' else 'non_refundable_cancellation' end;
    v_message := 'This booking is within ' || v_policy.late_cancellation_hours ||
      ' hours of the tour. ' || case when v_refund_rate > 0
        then 'Only a limited refund applies to confirmed payments.'
        else 'Confirmed payments are non-refundable.' end;
  end if;

  v_refundable := round(v_amount_paid * v_refund_rate / 100, 2);
  v_fee := greatest(v_amount_paid - v_refundable, 0);

  return jsonb_build_object(
    'can_cancel', true,
    'reason_code', 'CANCELLATION_ALLOWED',
    'display_message', v_message,
    'cancellation_type', v_type,
    'amount_paid', v_amount_paid,
    'cancellation_fee', v_fee,
    'refundable_amount', v_refundable,
    'non_refundable_amount', v_fee,
    'refund_rate', v_refund_rate,
    'refund_type', case
      when v_amount_paid = 0 then 'no_payment'
      when v_refundable = 0 then 'non_refundable'
      when v_refundable < v_amount_paid then 'partial_refund_request'
      else 'full_refund_request' end,
    'has_assigned_drivers', v_has_driver,
    'scheduled_at', v_scheduled_at,
    'hours_before_tour', v_hours_before
  );
end;
$$;

revoke all on function public.package_booking_cancellation_eligibility(uuid, uuid) from public;

create or replace function public.get_package_booking_cancellation_eligibility(
  p_booking_id uuid
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.package_booking_cancellation_eligibility(p_booking_id, auth.uid());
$$;

revoke all on function public.get_package_booking_cancellation_eligibility(uuid)
  from public;
grant execute on function public.get_package_booking_cancellation_eligibility(uuid) to authenticated;

create or replace function public.cancel_package_booking(
  p_booking_id uuid,
  p_reason text,
  p_note text default null,
  p_category text default 'general'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_booking public.package_bookings%rowtype;
  v_eligibility jsonb;
  v_refund_rate numeric;
  v_refundable numeric;
  v_amount_paid numeric;
  v_fee numeric;
  v_refund_status text;
  v_driver_ids uuid[] := array[]::uuid[];
  v_activity_ids uuid[] := array[]::uuid[];
  v_activity_driver_id uuid;
  v_package_title text := 'Tour package';
  v_refund_count integer := 0;
begin
  if v_actor is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  if nullif(trim(p_reason), '') is null then
    raise exception 'CANCELLATION_REASON_REQUIRED';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'BOOKING_NOT_FOUND';
  end if;

  if v_booking.tourist_id <> v_actor then
    raise exception 'NOT_BOOKING_OWNER';
  end if;

  -- Lock every row whose state participates in the decision. This serializes
  -- cancellation with driver arrival/progression and payment confirmation.
  perform 1 from public.package_activities
  where booking_id = p_booking_id for update;
  perform 1 from public.booking_drivers
  where booking_id = p_booking_id for update;
  perform 1 from public.payment_records
  where booking_id = p_booking_id for update;

  v_eligibility := public.package_booking_cancellation_eligibility(
    p_booking_id,
    v_actor
  );

  if not coalesce((v_eligibility->>'can_cancel')::boolean, false) then
    raise exception '%', coalesce(
      v_eligibility->>'reason_code',
      'CANCELLATION_NOT_ALLOWED'
    );
  end if;

  v_refund_rate := coalesce((v_eligibility->>'refund_rate')::numeric, 0);
  v_refundable := coalesce((v_eligibility->>'refundable_amount')::numeric, 0);
  v_amount_paid := coalesce((v_eligibility->>'amount_paid')::numeric, 0);
  v_fee := coalesce((v_eligibility->>'cancellation_fee')::numeric, 0);
  v_refund_status := case
    when v_amount_paid = 0 then 'not_required'
    when v_refundable > 0 then 'pending'
    else 'non_refundable'
  end;

  select coalesce(array_agg(distinct driver_id), array[]::uuid[])
  into v_driver_ids
  from (
    select driver_id from public.booking_drivers
    where booking_id = p_booking_id and status = 'accepted'
    union
    select assigned_driver_id from public.package_bookings
    where id = p_booking_id and assigned_driver_id is not null
    union
    select driver_id from public.package_activities
    where booking_id = p_booking_id and driver_id is not null
  ) drivers;

  select coalesce(array_agg(id), array[]::uuid[])
  into v_activity_ids
  from public.package_activities
  where booking_id = p_booking_id;

  select driver_id into v_activity_driver_id
  from public.package_activities
  where booking_id = p_booking_id
  order by created_at
  limit 1;

  select coalesce(tp.title, 'Tour package') into v_package_title
  from public.tour_packages tp where tp.id = v_booking.package_id;

  -- Cancel activities first. Existing booking-to-activity sync triggers run
  -- when the booking changes, so this ordering keeps those writes compatible
  -- with the cancelled-state guard below.
  update public.package_activities
  set status = 'cancelled',
      tour_status = 'cancelled',
      cancelled_at = now(),
      updated_at = now()
  where booking_id = p_booking_id
    and status not in ('completed', 'cancelled');

  update public.package_bookings
  set status = 'cancelled',
      booking_status = 'cancelled',
      assigned_driver_id = null,
      accepted_drivers_count = 0,
      cancelled_reason = trim(p_reason),
      cancelled_at = now(),
      cancelled_by = v_actor,
      cancellation_note = nullif(trim(coalesce(p_note, '')), ''),
      cancellation_category = coalesce(nullif(trim(p_category), ''), 'general'),
      cancellation_type = v_eligibility->>'cancellation_type',
      cancellation_fee = v_fee,
      refundable_amount = v_refundable,
      refund_status = v_refund_status,
      updated_at = now()
  where id = p_booking_id;

  update public.booking_drivers
  set status = 'rejected'
  where booking_id = p_booking_id and status in ('pending', 'accepted');

  update public.booking_driver_assignments
  set status = 'cancelled'
  where booking_id = p_booking_id and status not in ('completed', 'cancelled');

  -- The legacy assignment table has a driver-sync trigger. Restore the
  -- activity's historical driver link after cancelling legacy rows so the
  -- cancelled detail remains visible to the driver who handled it.
  update public.package_activities
  set driver_id = v_activity_driver_id,
      updated_at = now()
  where booking_id = p_booking_id;

  update public.payment_records
  set status = 'cancelled',
      notes = concat_ws(E'\n', nullif(notes, ''), 'Payment flow cancelled with booking.'),
      updated_at = now()
  where booking_id = p_booking_id and status = 'pending_confirmation';

  if v_refundable > 0 then
    insert into public.refund_requests (
      booking_id,
      payment_record_id,
      requested_by,
      payee_id,
      amount,
      reason,
      status
    )
    select
      p_booking_id,
      pr.id,
      v_actor,
      pr.payee_id,
      round(pr.amount * v_refund_rate / 100, 2),
      trim(p_reason),
      'pending'
    from public.payment_records pr
    where pr.booking_id = p_booking_id
      and pr.status = 'confirmed'
      and round(pr.amount * v_refund_rate / 100, 2) > 0
    on conflict (booking_id, payment_record_id) do nothing;

    get diagnostics v_refund_count = row_count;
  end if;

  if cardinality(v_activity_ids) > 0 then
    delete from public.driver_live_locations
    where activity_id = any(v_activity_ids);

    insert into public.trip_status_logs (activity_id, booking_id, status, notes)
    select unnest(v_activity_ids), p_booking_id, 'cancelled', trim(p_reason);
  end if;

  if cardinality(v_driver_ids) > 0 then
    update public.profiles p
    set is_available = true
    where p.id = any(v_driver_ids)
      and coalesce(p.is_online, false)
      and not exists (
        select 1 from public.package_activities pa
        where pa.driver_id = p.id
          and pa.status in ('accepted', 'ongoing')
      )
      and not exists (
        select 1
        from public.booking_drivers bd
        join public.package_bookings pb on pb.id = bd.booking_id
        where bd.driver_id = p.id
          and bd.status = 'accepted'
          and lower(coalesce(pb.booking_status, pb.status, ''))
            not in ('cancelled', 'completed', 'done')
      );

    insert into public.notifications (user_id, title, body, type, is_read)
    select
      driver_id,
      'Booking cancelled',
      'The tourist cancelled the ' || v_package_title || ' booking scheduled for ' ||
        to_char(v_booking.travel_date, 'Mon DD, YYYY') || '.',
      'booking_cancelled',
      false
    from unnest(v_driver_ids) as d(driver_id);
  end if;

  insert into public.notifications (user_id, title, body, type, is_read)
  values (
    v_actor,
    'Booking cancelled',
    'Your ' || v_package_title || ' booking for ' ||
      to_char(v_booking.travel_date, 'Mon DD, YYYY') || ' has been cancelled.' ||
      case when v_refundable > 0
        then ' Your refund request for PHP ' || to_char(v_refundable, 'FM999999990.00') ||
          ' is pending.' else '' end,
    'booking_cancelled',
    false
  );

  if lower(trim(p_reason)) in ('driver asked me to cancel', 'safety concern') then
    insert into public.notifications (user_id, title, body, type, is_read)
    select
      p.id,
      'Cancellation requires review',
      'Booking ' || p_booking_id || ' was cancelled for: ' || trim(p_reason),
      'cancellation_review',
      false
    from public.profiles p
    where p.role = 'admin'
       or (
         p.role = 'subtenant'
         and exists (
           select 1 from public.subtenant_details sd
           where sd.id = p.id
             and lower(sd.city) = lower(coalesce(v_booking.municipality, ''))
         )
       );
  end if;

  insert into public.audit_logs (
    actor_id, action, table_name, record_id, description
  ) values (
    v_actor,
    'cancel_package_booking',
    'package_bookings',
    p_booking_id::text,
    'Tourist cancelled booking. Type=' ||
      (v_eligibility->>'cancellation_type') || ', reason=' || trim(p_reason)
  );

  return v_eligibility || jsonb_build_object(
    'success', true,
    'booking_id', p_booking_id,
    'cancelled_at', now(),
    'cancellation_reason', trim(p_reason),
    'cancellation_note', nullif(trim(coalesce(p_note, '')), ''),
    'refund_status', v_refund_status,
    'refund_request_count', v_refund_count,
    'released_driver_count', cardinality(v_driver_ids)
  );
end;
$$;

revoke all on function public.cancel_package_booking(uuid, text, text, text)
  from public;
grant execute on function public.cancel_package_booking(uuid, text, text, text)
  to authenticated;

create or replace function public.resolve_package_refund_request(
  p_refund_request_id uuid,
  p_status text,
  p_reference_no text default null,
  p_note text default null
)
returns public.refund_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_request public.refund_requests%rowtype;
begin
  if v_actor is null then raise exception 'UNAUTHENTICATED'; end if;
  if lower(trim(p_status)) not in ('approved', 'completed', 'rejected') then
    raise exception 'INVALID_REFUND_STATUS';
  end if;

  select * into v_request
  from public.refund_requests
  where id = p_refund_request_id
  for update;

  if not found then raise exception 'REFUND_REQUEST_NOT_FOUND'; end if;
  if v_request.payee_id <> v_actor
     and public.current_profile_role() is distinct from 'admin' then
    raise exception 'REFUND_REQUEST_NOT_AUTHORIZED';
  end if;
  if v_request.status in ('completed', 'rejected') then
    raise exception 'REFUND_REQUEST_ALREADY_RESOLVED';
  end if;
  if lower(trim(p_status)) = 'completed'
     and nullif(trim(coalesce(p_reference_no, '')), '') is null then
    raise exception 'REFUND_REFERENCE_REQUIRED';
  end if;

  update public.refund_requests
  set status = lower(trim(p_status)),
      approved_at = case
        when lower(trim(p_status)) in ('approved', 'completed')
          then coalesce(approved_at, now()) else approved_at end,
      completed_at = case when lower(trim(p_status)) = 'completed' then now() end,
      completed_by = case when lower(trim(p_status)) = 'completed' then v_actor end,
      reference_no = case when lower(trim(p_status)) = 'completed'
        then trim(p_reference_no) else reference_no end,
      resolution_note = nullif(trim(coalesce(p_note, '')), ''),
      updated_at = now()
  where id = p_refund_request_id
  returning * into v_request;

  if not exists (
    select 1 from public.refund_requests rr
    where rr.booking_id = v_request.booking_id
      and rr.status in ('pending', 'approved')
  ) then
    update public.package_bookings
    set refund_status = case
          when exists (
            select 1 from public.refund_requests rr
            where rr.booking_id = v_request.booking_id and rr.status = 'completed'
          ) then 'completed'
          else 'rejected'
        end,
        updated_at = now()
    where id = v_request.booking_id;
  end if;

  insert into public.notifications (user_id, title, body, type, is_read)
  select
    pb.tourist_id,
    case when v_request.status = 'completed'
      then 'Refund completed' else 'Refund request updated' end,
    case when v_request.status = 'completed'
      then 'Your refund of PHP ' || to_char(v_request.amount, 'FM999999990.00') ||
        ' was marked completed.'
      else 'Your refund request is now ' || v_request.status || '.' end,
    'refund_' || v_request.status,
    false
  from public.package_bookings pb
  where pb.id = v_request.booking_id;

  insert into public.audit_logs (
    actor_id, action, table_name, record_id, description
  ) values (
    v_actor,
    'resolve_package_refund_request',
    'refund_requests',
    v_request.id::text,
    'status=' || v_request.status || ', amount=' || v_request.amount
  );

  return v_request;
end;
$$;

revoke all on function public.resolve_package_refund_request(uuid, text, text, text)
  from public;
grant execute on function public.resolve_package_refund_request(uuid, text, text, text)
  to authenticated;

-- Prevent a driver progression write or late payment confirmation from
-- resurrecting state after cancellation commits.
create or replace function public.guard_cancelled_package_activity_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.package_bookings pb
    where pb.id = new.booking_id
      and lower(coalesce(pb.booking_status, pb.status, '')) = 'cancelled'
  ) and (
    lower(coalesce(new.status, '')) <> 'cancelled'
    or lower(coalesce(new.tour_status, '')) <> 'cancelled'
  ) then
    raise exception 'BOOKING_CANCELLED';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_cancelled_package_activity on public.package_activities;
create trigger trg_guard_cancelled_package_activity
  before update on public.package_activities
  for each row execute function public.guard_cancelled_package_activity_update();

create or replace function public.guard_cancelled_booking_payment_confirmation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.booking_id is not null
     and new.status = 'confirmed'
     and old.status <> 'confirmed'
     and exists (
       select 1 from public.package_bookings pb
       where pb.id = new.booking_id
         and lower(coalesce(pb.booking_status, pb.status, '')) = 'cancelled'
     ) then
    raise exception 'BOOKING_CANCELLED';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_cancelled_booking_payment on public.payment_records;
create trigger trg_guard_cancelled_booking_payment
  before update on public.payment_records
  for each row execute function public.guard_cancelled_booking_payment_confirmation();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'refund_requests'
  ) then
    alter publication supabase_realtime add table public.refund_requests;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
