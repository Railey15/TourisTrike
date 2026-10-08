begin;
create table public.transactional_email_outbox (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  event_type text not null check (event_type in
    ('drivers_accepted', 'downpayment_receipt',
     'remaining_receipt', 'tour_completed')),
  booking_id uuid not null references public.package_bookings(id) on delete cascade,
  payment_record_id uuid references public.payment_records(id) on delete set null,
  recipient_id uuid not null references public.profiles(id),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'leased', 'sent', 'dead')),
  attempts integer not null default 0,
  first_attempt_at timestamptz,
  next_attempt_at timestamptz not null default now(),
  lease_id uuid,
  lease_until timestamptz,
  provider_email_id text,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
create index transactional_email_due_idx
on public.transactional_email_outbox(next_attempt_at, created_at)
where status in ('pending', 'leased');
alter table public.transactional_email_outbox enable row level security;
revoke all on public.transactional_email_outbox
  from public, anon, authenticated;
create function public.queue_booking_transactional_email()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_type text;
  v_key text;
  v_recipient uuid;
  v_booking uuid;
  v_payment uuid;
  v_payload jsonb;
begin
  if tg_table_name = 'payment_records' then
    if new.status <> 'confirmed'
       or (tg_op = 'UPDATE' and old.status = 'confirmed')
       or new.booking_id is null
       or new.payment_stage not in ('down_payment', 'remaining_balance')
       or new.payee_id is not null then
      return new;
    end if;
    select b.tourist_id into v_recipient from public.package_bookings b
      where b.id = new.booking_id;
    v_booking := new.booking_id;
    v_payment := new.id;
    v_type := case when new.payment_stage = 'down_payment'
      then 'downpayment_receipt' else 'remaining_receipt' end;
    v_key := 'receipt:' || new.id::text;
    v_payload := jsonb_build_object(
      'amount', new.amount, 'stage', new.payment_stage,
      'method', new.payment_method, 'receipt_no', new.receipt_no,
      'paid_at', coalesce(new.paid_at, new.payee_confirmed_at,
        clock_timestamp()));
  else
    v_booking := new.id;
    v_recipient := new.tourist_id;
    if lower(coalesce(new.booking_status, new.status, ''))
         in ('accepted', 'confirmed')
       and new.accepted_drivers_count >= new.required_drivers
       and (lower(coalesce(old.booking_status, old.status, ''))
              not in ('accepted', 'confirmed')
            or old.accepted_drivers_count < old.required_drivers) then
      v_type := 'drivers_accepted';
      -- A later approved tricycle request creates a new roster milestone.
      v_key := 'drivers_accepted:' || new.id::text || ':' ||
        new.required_drivers::text;
      v_payload := jsonb_build_object(
        'accepted_drivers', new.accepted_drivers_count,
        'required_drivers', new.required_drivers);
    elsif lower(coalesce(new.booking_status, new.status, ''))
        in ('completed', 'done')
      and lower(coalesce(old.booking_status, old.status, ''))
        not in ('completed', 'done') then
      v_type := 'tour_completed';
      v_key := 'tour_completed:' || new.id::text;
      v_payload := jsonb_build_object('completed_at',
        coalesce(new.completed_at, clock_timestamp()));
    else
      return new;
    end if;
  end if;
  if v_recipient is null then return new; end if;
  begin
    insert into public.transactional_email_outbox(
      event_key, event_type, booking_id, payment_record_id,
      recipient_id, payload)
    values(v_key, v_type, v_booking, v_payment, v_recipient, v_payload)
    on conflict (event_key) do nothing;
  exception when others then
    -- Delivery infrastructure cannot undo an authorized payment or tour event.
    raise warning 'TRANSACTIONAL_EMAIL_QUEUE_FAILED: %', sqlstate;
  end;
  return new;
end $$;
create trigger queue_confirmed_payment_email
after insert or update of status on public.payment_records
for each row execute function public.queue_booking_transactional_email();
create trigger queue_booking_milestone_email
after update of booking_status, status, accepted_drivers_count,
  required_drivers on public.package_bookings
for each row execute function public.queue_booking_transactional_email();
revoke all on function public.queue_booking_transactional_email()
  from public, anon, authenticated;
create function public.claim_transactional_emails(p_limit integer default 20)
returns setof public.transactional_email_outbox
language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  -- Resend retains its idempotency key for 24 hours. An uncertain delivery
  -- older than that must be reconciled manually, never retried automatically.
  update public.transactional_email_outbox
  set status = 'dead', last_error = 'IDEMPOTENCY_WINDOW_EXPIRED',
      lease_id = null, lease_until = null
  where status in ('pending', 'leased')
    and first_attempt_at <= clock_timestamp() - interval '23 hours';
  return query
  with due as (
    select id from public.transactional_email_outbox
    where ((status = 'pending' and next_attempt_at <= clock_timestamp())
       or (status = 'leased' and lease_until < clock_timestamp()))
      and (first_attempt_at is null
        or first_attempt_at > clock_timestamp() - interval '23 hours')
    order by created_at, id
    limit greatest(1, least(coalesce(p_limit, 20), 50))
    for update skip locked
  )
  update public.transactional_email_outbox o
  set status = 'leased', lease_id = gen_random_uuid(),
      lease_until = clock_timestamp() + interval '2 minutes',
      first_attempt_at = coalesce(o.first_attempt_at, clock_timestamp()),
      attempts = o.attempts + 1
  from due where o.id = due.id
  returning o.*;
end $$;
revoke all on function public.claim_transactional_emails(integer)
  from public, anon, authenticated;
grant execute on function public.claim_transactional_emails(integer)
  to service_role;
create function public.finish_transactional_email(
  p_id uuid, p_lease uuid, p_result text,
  p_provider_id text default null, p_error text default null
) returns boolean language plpgsql security definer set search_path = '' as $$
declare v_updated integer;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if p_result not in ('sent', 'retry', 'dead') then
    raise exception 'INVALID_EMAIL_DELIVERY_RESULT';
  end if;
  update public.transactional_email_outbox
  set status = case when p_result = 'retry'
        and first_attempt_at > clock_timestamp() - interval '23 hours'
        then 'pending'
        when p_result = 'retry' then 'dead'
        else p_result end,
      next_attempt_at = case when p_result = 'retry' then
        clock_timestamp() + make_interval(secs =>
          least(3600, 60 * power(2, least(attempts, 6)))::integer)
        else next_attempt_at end,
      sent_at = case when p_result = 'sent' then clock_timestamp()
        else sent_at end,
      provider_email_id = case when p_result = 'sent' then p_provider_id
        else provider_email_id end,
      last_error = left(p_error, 120),
      lease_id = null, lease_until = null
  where id = p_id and lease_id = p_lease and status = 'leased';
  get diagnostics v_updated = row_count;
  return v_updated = 1;
end $$;
revoke all on function public.finish_transactional_email(
  uuid,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.finish_transactional_email(
  uuid,uuid,text,text,text) to service_role;
commit;
