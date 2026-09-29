-- Municipality-scoped Disputes & Cases. The historical payment_disputes table
-- remains the canonical store so existing payment submissions keep working.

begin;

alter table public.payment_disputes
  alter column payment_record_id drop not null,
  alter column reason drop not null,
  add column if not exists municipality text,
  add column if not exists package_id bigint references public.tour_packages(id) on delete set null,
  add column if not exists reported_user_id uuid references public.profiles(id) on delete set null,
  add column if not exists category text not null default 'payment',
  add column if not exists subject text,
  add column if not exists priority text not null default 'normal',
  add column if not exists resolution_type text,
  add column if not exists custom_resolution text,
  add column if not exists assigned_to uuid references public.profiles(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

alter table public.payment_disputes
  drop constraint if exists payment_disputes_status_check,
  drop constraint if exists payment_disputes_category_check,
  drop constraint if exists payment_disputes_priority_check;

update public.payment_disputes
set status = case
  when status = 'open' then 'needs_review'
  when status in ('resolved_valid', 'resolved_refund_arranged', 'rejected') then 'closed'
  else status
end,
resolution_type = coalesce(
  resolution_type,
  case status
    when 'resolved_valid' then 'payment_issue_resolved'
    when 'resolved_refund_arranged' then 'payment_issue_resolved'
    when 'rejected' then 'dismissed_insufficient_evidence'
  end
),
subject = coalesce(nullif(trim(subject), ''), case reason
  when 'not_received' then 'Payment not received'
  when 'wrong_amount' then 'Incorrect payment amount'
  when 'duplicate' then 'Duplicate payment'
  when 'fake_reference' then 'Invalid payment reference'
  else 'Payment dispute'
end),
updated_at = coalesce(updated_at, created_at, now());

update public.payment_disputes dispute
set package_id = booking.package_id
from public.package_bookings booking
where booking.id = dispute.booking_id
  and dispute.package_id is null;

update public.payment_disputes dispute
set reported_user_id = case
  when record.payer_id = dispute.raised_by then record.payee_id
  else record.payer_id
end
from public.payment_records record
where record.id = dispute.payment_record_id
  and dispute.reported_user_id is null;

update public.payment_disputes dispute
set municipality = coalesce(
  (select package.city from public.tour_packages package
    where package.id = dispute.package_id),
  (select package.city
     from public.package_bookings booking
     join public.tour_packages package on package.id = booking.package_id
    where booking.id = dispute.booking_id),
  (select driver.city
     from public.rides ride
     join public.profiles driver on driver.id = ride.driver_id
    where ride.id = dispute.ride_id),
  (select profile.city from public.profiles profile
    where profile.id = dispute.reported_user_id),
  (select profile.city from public.profiles profile
    where profile.id = dispute.raised_by),
  'Unassigned'
)
where nullif(trim(dispute.municipality), '') is null;

alter table public.payment_disputes
  alter column municipality set not null,
  alter column subject set not null,
  alter column status set default 'needs_review',
  add constraint payment_disputes_status_check
    check (status in ('needs_review', 'under_review', 'closed')),
  add constraint payment_disputes_category_check
    check (category in (
      'payment', 'booking', 'driver', 'tourist', 'tour_package',
      'fare_charge', 'safety_incident', 'other'
    )),
  add constraint payment_disputes_priority_check
    check (priority in ('low', 'normal', 'high', 'urgent'));

create index if not exists payment_disputes_municipality_status_idx
  on public.payment_disputes(lower(municipality), status, created_at desc);
create index if not exists payment_disputes_category_idx
  on public.payment_disputes(category, created_at desc);

drop trigger if exists set_payment_disputes_updated_at on public.payment_disputes;
create trigger set_payment_disputes_updated_at
before update on public.payment_disputes
for each row execute function public.set_updated_at();

create table if not exists public.dispute_evidence (
  id uuid primary key default gen_random_uuid(),
  dispute_id uuid not null references public.payment_disputes(id) on delete cascade,
  uploaded_by uuid references public.profiles(id) on delete set null,
  file_url text not null,
  file_name text,
  content_type text,
  created_at timestamptz not null default now()
);
create index if not exists dispute_evidence_dispute_idx
  on public.dispute_evidence(dispute_id, created_at);

insert into public.dispute_evidence (
  dispute_id, uploaded_by, file_url, file_name, content_type, created_at
)
select id, raised_by, evidence_url, 'Payment dispute evidence', 'image/*', created_at
from public.payment_disputes dispute
where nullif(trim(evidence_url), '') is not null
  and not exists (
    select 1 from public.dispute_evidence evidence
    where evidence.dispute_id = dispute.id
      and evidence.file_url = dispute.evidence_url
  );

create or replace function public.can_manage_dispute_case(p_dispute_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.payment_disputes dispute
    where dispute.id = p_dispute_id
      and (
        public.is_main_tenant()
        or (
          public.current_subtenant_city() is not null
          and public.cities_match(
            dispute.municipality,
            public.current_subtenant_city()
          )
        )
      )
  );
$$;

revoke all on function public.can_manage_dispute_case(uuid) from public, anon;
grant execute on function public.can_manage_dispute_case(uuid) to authenticated;

alter table public.dispute_evidence enable row level security;

drop policy if exists payment_disputes_select on public.payment_disputes;
create policy payment_disputes_select on public.payment_disputes
for select to authenticated
using (
  raised_by = auth.uid()
  or reported_user_id = auth.uid()
  or exists (
    select 1 from public.payment_records record
    where record.id = payment_record_id
      and auth.uid() in (record.payer_id, record.payee_id)
  )
  or exists (
    select 1 from public.package_bookings booking
    where booking.id = booking_id and booking.tourist_id = auth.uid()
  )
  or public.can_manage_dispute_case(id)
);

drop policy if exists dispute_evidence_select on public.dispute_evidence;
create policy dispute_evidence_select on public.dispute_evidence
for select to authenticated
using (
  exists (
    select 1 from public.payment_disputes dispute
    where dispute.id = dispute_id
      and (
        dispute.raised_by = auth.uid()
        or dispute.reported_user_id = auth.uid()
        or public.can_manage_dispute_case(dispute.id)
      )
  )
);

-- Scope and identity fields are immutable outside the trusted case RPCs.
create or replace function public.guard_dispute_case_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.municipality is distinct from old.municipality
     or new.raised_by is distinct from old.raised_by
     or new.reported_user_id is distinct from old.reported_user_id
     or new.payment_record_id is distinct from old.payment_record_id
     or new.booking_id is distinct from old.booking_id
     or new.ride_id is distinct from old.ride_id
     or new.package_id is distinct from old.package_id
     or new.created_at is distinct from old.created_at then
    raise exception 'CASE_IDENTITY_FIELDS_ARE_IMMUTABLE' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists guard_dispute_case_identity on public.payment_disputes;
create trigger guard_dispute_case_identity
before update on public.payment_disputes
for each row execute function public.guard_dispute_case_identity();

create or replace function public.prepare_dispute_case()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.category := coalesce(nullif(new.category, ''), 'payment');
  new.status := case when new.status = 'open' then 'needs_review' else new.status end;
  new.subject := coalesce(nullif(trim(new.subject), ''), case new.reason
    when 'not_received' then 'Payment not received'
    when 'wrong_amount' then 'Incorrect payment amount'
    when 'duplicate' then 'Duplicate payment'
    when 'fake_reference' then 'Invalid payment reference'
    else 'Reported issue'
  end);
  if new.payment_record_id is not null then
    select coalesce(new.booking_id, record.booking_id),
           coalesce(new.ride_id, record.ride_id),
           coalesce(new.reported_user_id, case
             when record.payer_id = new.raised_by then record.payee_id
             else record.payer_id
           end)
    into new.booking_id, new.ride_id, new.reported_user_id
    from public.payment_records record where record.id = new.payment_record_id;
  end if;
  if new.package_id is null and new.booking_id is not null then
    select booking.package_id into new.package_id
    from public.package_bookings booking where booking.id = new.booking_id;
  end if;
  new.municipality := coalesce(nullif(trim(new.municipality), ''),
    (select package.city from public.tour_packages package where package.id = new.package_id),
    (select driver.city from public.rides ride join public.profiles driver
       on driver.id = ride.driver_id where ride.id = new.ride_id),
    (select profile.city from public.profiles profile where profile.id = new.reported_user_id),
    (select profile.city from public.profiles profile where profile.id = new.raised_by));
  if nullif(trim(new.municipality), '') is null then
    raise exception 'CASE_MUNICIPALITY_REQUIRED';
  end if;
  return new;
end;
$$;
drop trigger if exists prepare_dispute_case on public.payment_disputes;
create trigger prepare_dispute_case
before insert on public.payment_disputes
for each row execute function public.prepare_dispute_case();

create or replace function public.get_dispute_cases(p_case_id uuid default null)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', dispute.id,
    'municipality', dispute.municipality,
    'booking_id', dispute.booking_id,
    'package_id', dispute.package_id,
    'payment_record_id', dispute.payment_record_id,
    'reporter_id', dispute.raised_by,
    'reported_user_id', dispute.reported_user_id,
    'category', dispute.category,
    'subject', dispute.subject,
    'description', dispute.description,
    'priority', dispute.priority,
    'status', dispute.status,
    'resolution_type', dispute.resolution_type,
    'custom_resolution', dispute.custom_resolution,
    'resolution_notes', dispute.resolution_note,
    'assigned_to', dispute.assigned_to,
    'reviewed_at', dispute.reviewed_at,
    'resolved_at', dispute.resolved_at,
    'created_at', dispute.created_at,
    'updated_at', dispute.updated_at,
    'reason', dispute.reason,
    'reporter', jsonb_build_object(
      'id', reporter.id, 'name', coalesce(nullif(reporter.full_name, ''),
        nullif(trim(concat_ws(' ', reporter.first_name, reporter.last_name)), ''), 'Unknown user'),
      'role', reporter.role, 'mobile', reporter.mobile
    ),
    'reported_user', case when reported.id is null then null else jsonb_build_object(
      'id', reported.id, 'name', coalesce(nullif(reported.full_name, ''),
        nullif(trim(concat_ws(' ', reported.first_name, reported.last_name)), ''), 'Unknown user'),
      'role', reported.role, 'mobile', reported.mobile
    ) end,
    'assignee', case when assignee.id is null then null else jsonb_build_object(
      'id', assignee.id, 'name', coalesce(nullif(assignee.full_name, ''),
        nullif(trim(concat_ws(' ', assignee.first_name, assignee.last_name)), ''), 'Municipality staff')
    ) end,
    'booking', case when booking.id is null then null else jsonb_build_object(
      'id', booking.id, 'status', booking.status, 'travel_date', booking.travel_date,
      'total_amount', booking.total_amount
    ) end,
    'tour_package', case when package.id is null then null else jsonb_build_object(
      'id', package.id, 'title', package.title, 'city', package.city
    ) end,
    'payment', case when payment.id is null then null else jsonb_build_object(
      'id', payment.id, 'amount', payment.amount, 'payment_method', payment.payment_method,
      'status', payment.status, 'reference', payment.external_reference_no,
      'receipt_no', payment.receipt_no, 'stage', payment.payment_stage
    ) end,
    'evidence', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', evidence.id, 'url', evidence.file_url, 'name', evidence.file_name,
        'content_type', evidence.content_type, 'created_at', evidence.created_at
      ) order by evidence.created_at)
      from public.dispute_evidence evidence where evidence.dispute_id = dispute.id
    ), '[]'::jsonb),
    'timeline', jsonb_build_array(
      jsonb_build_object('label', 'Case submitted', 'at', dispute.created_at),
      case when dispute.reviewed_at is null then null else
        jsonb_build_object('label', 'Review started', 'at', dispute.reviewed_at) end,
      case when dispute.resolved_at is null then null else
        jsonb_build_object('label', 'Case closed', 'at', dispute.resolved_at) end
    )
  )
  from public.payment_disputes dispute
  join public.profiles reporter on reporter.id = dispute.raised_by
  left join public.profiles reported on reported.id = dispute.reported_user_id
  left join public.profiles assignee on assignee.id = dispute.assigned_to
  left join public.package_bookings booking on booking.id = dispute.booking_id
  left join public.tour_packages package on package.id = coalesce(dispute.package_id, booking.package_id)
  left join public.payment_records payment on payment.id = dispute.payment_record_id
  where (p_case_id is null or dispute.id = p_case_id)
    and public.can_manage_dispute_case(dispute.id)
  order by dispute.created_at desc;
$$;

revoke all on function public.get_dispute_cases(uuid) from public, anon;
grant execute on function public.get_dispute_cases(uuid) to authenticated;

create or replace function public.start_dispute_case(p_case_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.payment_disputes;
  v_recipient uuid;
begin
  if not public.can_manage_dispute_case(p_case_id) then
    raise exception 'NOT_AUTHORIZED' using errcode = '42501';
  end if;
  update public.payment_disputes
  set status = 'under_review', reviewed_at = coalesce(reviewed_at, now()),
      assigned_to = coalesce(assigned_to, auth.uid())
  where id = p_case_id and status = 'needs_review'
  returning * into v_case;
  if not found then raise exception 'CASE_NOT_AVAILABLE_FOR_REVIEW'; end if;

  insert into public.audit_logs(actor_id, action, table_name, record_id, description)
  values (auth.uid(), 'start_case_review', 'payment_disputes', v_case.id::text,
    'Review started for ' || v_case.category || ' case in ' || v_case.municipality);
  foreach v_recipient in array array[v_case.raised_by, v_case.reported_user_id] loop
    if v_recipient is not null and v_recipient <> auth.uid() then
      insert into public.notifications(user_id, title, body, type)
      values (v_recipient, 'Case review started',
        'Your TourisTrike case ' || upper(left(v_case.id::text, 8)) || ' is under review.',
        'dispute_case');
    end if;
  end loop;
  return to_jsonb(v_case);
end;
$$;

create or replace function public.resolve_dispute_case(
  p_case_id uuid,
  p_resolution_type text,
  p_resolution_notes text,
  p_custom_resolution text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.payment_disputes;
  v_recipient uuid;
begin
  if not public.can_manage_dispute_case(p_case_id) then
    raise exception 'NOT_AUTHORIZED' using errcode = '42501';
  end if;
  if p_resolution_type not in (
    'no_action_required', 'warning_issued', 'driver_suspended',
    'booking_issue_resolved', 'payment_issue_resolved',
    'referred_tourism_office', 'dismissed_insufficient_evidence',
    'other_resolution'
  ) then raise exception 'INVALID_RESOLUTION_TYPE'; end if;
  if nullif(trim(p_resolution_notes), '') is null then
    raise exception 'RESOLUTION_NOTES_REQUIRED';
  end if;
  if p_resolution_type = 'other_resolution'
     and nullif(trim(coalesce(p_custom_resolution, '')), '') is null then
    raise exception 'CUSTOM_RESOLUTION_REQUIRED';
  end if;

  update public.payment_disputes
  set status = 'closed', resolution_type = p_resolution_type,
      custom_resolution = nullif(trim(coalesce(p_custom_resolution, '')), ''),
      resolution_note = trim(p_resolution_notes), resolved_by = auth.uid(),
      resolved_at = now(), reviewed_at = coalesce(reviewed_at, now()),
      assigned_to = coalesce(assigned_to, auth.uid())
  where id = p_case_id and status = 'under_review'
  returning * into v_case;
  if not found then raise exception 'CASE_NOT_AVAILABLE_FOR_RESOLUTION'; end if;

  -- Administrative outcome only. No cash/GCash transfer and no automatic
  -- driver suspension is performed here.
  if v_case.payment_record_id is not null then
    update public.payment_records set status = case
      when p_resolution_type = 'dismissed_insufficient_evidence' then 'confirmed'
      when p_resolution_type = 'payment_issue_resolved' then status
      else status end
    where id = v_case.payment_record_id;
  end if;
  insert into public.audit_logs(actor_id, action, table_name, record_id, description)
  values (auth.uid(), 'resolve_dispute_case', 'payment_disputes', v_case.id::text,
    'Case closed: ' || p_resolution_type || ' | notes=' || trim(p_resolution_notes));
  foreach v_recipient in array array[v_case.raised_by, v_case.reported_user_id] loop
    if v_recipient is not null and v_recipient <> auth.uid() then
      insert into public.notifications(user_id, title, body, type)
      values (v_recipient, 'Case resolved',
        'TourisTrike case ' || upper(left(v_case.id::text, 8)) || ' has been closed.',
        'dispute_case');
    end if;
  end loop;
  return to_jsonb(v_case);
end;
$$;

revoke all on function public.start_dispute_case(uuid) from public, anon;
revoke all on function public.resolve_dispute_case(uuid, text, text, text) from public, anon;
grant execute on function public.start_dispute_case(uuid) to authenticated;
grant execute on function public.resolve_dispute_case(uuid, text, text, text) to authenticated;

-- Keep the public payment submission contract unchanged. The insert trigger
-- fills the generic case fields and derives municipality ownership.
create or replace function public.raise_payment_dispute(
  p_payment_record_id uuid,
  p_reason text,
  p_description text default null,
  p_evidence_url text default null
)
returns public.payment_disputes
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_record public.payment_records;
  v_case public.payment_disputes;
begin
  select * into v_record from public.payment_records
  where id = p_payment_record_id for update;
  if not found then raise exception 'PAYMENT_RECORD_NOT_FOUND'; end if;
  if auth.uid() is null or auth.uid() not in (v_record.payer_id, v_record.payee_id) then
    raise exception 'NOT_A_PARTICIPANT';
  end if;
  if p_reason not in ('not_received', 'wrong_amount', 'duplicate', 'fake_reference', 'other') then
    raise exception 'INVALID_REASON';
  end if;
  insert into public.payment_disputes(
    payment_record_id, booking_id, ride_id, raised_by, reason,
    description, evidence_url, category, priority
  ) values (
    p_payment_record_id, v_record.booking_id, v_record.ride_id, auth.uid(), p_reason,
    p_description, p_evidence_url, 'payment', 'normal'
  ) returning * into v_case;
  if nullif(trim(coalesce(p_evidence_url, '')), '') is not null then
    insert into public.dispute_evidence(dispute_id, uploaded_by, file_url, content_type)
    values (v_case.id, auth.uid(), p_evidence_url, 'image/*');
  end if;
  update public.payment_records set status = 'disputed' where id = p_payment_record_id;
  return v_case;
end;
$$;

-- Legacy staff clients can still call this RPC/status vocabulary. It delegates
-- to the generic lifecycle and returns the same table row type.
create or replace function public.resolve_payment_dispute(
  p_dispute_id uuid,
  p_new_status text,
  p_resolution_note text default null
)
returns public.payment_disputes
language plpgsql
security definer
set search_path = ''
as $$
declare v_case public.payment_disputes;
begin
  if p_new_status = 'under_review' then
    perform public.start_dispute_case(p_dispute_id);
  elsif p_new_status in ('resolved_valid', 'resolved_refund_arranged', 'rejected') then
    perform public.resolve_dispute_case(
      p_dispute_id,
      case when p_new_status = 'rejected' then 'dismissed_insufficient_evidence'
           else 'payment_issue_resolved' end,
      coalesce(nullif(trim(p_resolution_note), ''), 'Resolved through the payment dispute workflow.'),
      null
    );
    if p_new_status = 'resolved_valid' or p_new_status = 'rejected' then
      update public.payment_records record set status = 'confirmed'
      from public.payment_disputes dispute
      where dispute.id = p_dispute_id and record.id = dispute.payment_record_id;
    elsif p_new_status = 'resolved_refund_arranged' then
      update public.payment_records record set status = 'cancelled'
      from public.payment_disputes dispute
      where dispute.id = p_dispute_id and record.id = dispute.payment_record_id;
    end if;
  else
    raise exception 'INVALID_STATUS';
  end if;
  select * into v_case from public.payment_disputes where id = p_dispute_id;
  return v_case;
end;
$$;

revoke all on function public.raise_payment_dispute(uuid, text, text, text) from public, anon;
revoke all on function public.resolve_payment_dispute(uuid, text, text) from public, anon;
grant execute on function public.raise_payment_dispute(uuid, text, text, text) to authenticated;
grant execute on function public.resolve_payment_dispute(uuid, text, text) to authenticated;
grant select on public.dispute_evidence to authenticated;

commit;
