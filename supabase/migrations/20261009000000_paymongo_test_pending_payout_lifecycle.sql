-- PayMongo TEST booking-payment lifecycle.
--
-- A confirmed provider payment belongs to the booking. Driver allocations are
-- only payout instructions and remain pending until a qualifying booking
-- outcome occurs. No wallet, escrow, stored value, or custodial balance is
-- created by this migration.

begin;

alter table public.package_cancellation_policy
  add column if not exists replacement_window_minutes integer not null default 30
    check (replacement_window_minutes between 5 and 1440),
  add column if not exists no_show_grace_minutes integer not null default 15
    check (no_show_grace_minutes between 5 and 120);

-- Preserve an administrator's custom policy. Only migrate the former default.
update public.package_cancellation_policy
set free_cancellation_hours = 12,
    updated_at = now()
where id = 1 and free_cancellation_hours = 24;

alter table public.package_bookings
  add column if not exists cancellation_party text,
  add column if not exists cancellation_reason_code text,
  add column if not exists replacement_status text not null default 'none',
  add column if not exists replacement_search_started_at timestamptz,
  add column if not exists replacement_deadline_at timestamptz,
  add column if not exists payout_eligibility_reason text;

alter table public.package_bookings
  drop constraint if exists package_bookings_replacement_status_check;
alter table public.package_bookings
  add constraint package_bookings_replacement_status_check check (
    replacement_status in (
      'none', 'awaiting_replacement', 'replacement_assigned',
      'no_replacement', 'manual_review'
    )
  );

alter table public.package_bookings
  drop constraint if exists package_bookings_cancellation_party_check;
alter table public.package_bookings
  add constraint package_bookings_cancellation_party_check check (
    cancellation_party is null
    or cancellation_party in ('tourist', 'driver', 'system', 'administrator')
  );

alter table public.booking_drivers
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text,
  add column if not exists replacement_for_booking_driver_id uuid
    references public.booking_drivers(id) on delete set null;

alter table public.booking_drivers
  drop constraint if exists booking_drivers_status_check;
alter table public.booking_drivers
  add constraint booking_drivers_status_check check (
    status in ('pending', 'accepted', 'rejected', 'cancelled', 'no_show', 'completed')
  );

alter table public.payment_allocations
  add column if not exists eligible_at timestamptz,
  add column if not exists eligibility_reason text,
  add column if not exists replaces_allocation_id uuid
    references public.payment_allocations(id) on delete restrict;

create unique index if not exists payment_allocations_active_replacement_uidx
  on public.payment_allocations(replaces_allocation_id)
  where replaces_allocation_id is not null and status <> 'cancelled';

alter table public.payment_allocations
  drop constraint if exists payment_allocations_status_check;
alter table public.payment_allocations
  add constraint payment_allocations_status_check check (status in (
    'pending', 'held', 'eligible', 'processing', 'paid', 'failed',
    'cancelled', 'manual_review', 'awaiting_cash', 'cash_confirmed'
  ));

alter table public.payout_records
  add column if not exists eligible_at timestamptz,
  add column if not exists eligibility_reason text;

create table if not exists public.booking_no_show_reports (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.package_bookings(id) on delete restrict,
  booking_driver_id uuid references public.booking_drivers(id) on delete restrict,
  reported_by uuid not null references public.profiles(id) on delete restrict,
  reported_party text not null check (reported_party in ('driver', 'tourist')),
  status text not null default 'pending'
    check (status in ('pending', 'verified', 'rejected')),
  report_note text,
  arrival_evidence jsonb not null default '{}'::jsonb,
  progression_evidence jsonb not null default '{}'::jsonb,
  reported_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete set null,
  resolution_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (booking_id, booking_driver_id, reported_party)
);

drop trigger if exists set_booking_no_show_reports_updated_at
  on public.booking_no_show_reports;
create trigger set_booking_no_show_reports_updated_at
before update on public.booking_no_show_reports
for each row execute function public.set_updated_at();

alter table public.booking_no_show_reports enable row level security;
drop policy if exists booking_no_show_reports_participant_read
  on public.booking_no_show_reports;
create policy booking_no_show_reports_participant_read
on public.booking_no_show_reports for select to authenticated
using (public.is_package_booking_participant(booking_id));

-- This deployment is deliberately sandbox-only. It rejects new live-mode
-- PayMongo rows before any lifecycle logic can treat them as test payments.
create or replace function public.enforce_paymongo_test_mode()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.provider = 'paymongo' and coalesce(new.provider_livemode, false) then
    raise exception 'PAYMONGO_LIVE_MODE_DISABLED';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_paymongo_test_mode on public.payment_records;
create trigger enforce_paymongo_test_mode
before insert or update of provider, provider_livemode on public.payment_records
for each row execute function public.enforce_paymongo_test_mode();

-- The old webhook mapped a requested provider split directly to processing.
-- Normalize only the pre-eligibility transition. An eligible allocation may
-- still be claimed by the existing idempotent payout RPC.
create or replace function public.normalize_test_allocation_pending_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_test_confirmed boolean;
begin
  if new.status not in ('held', 'processing') then return new; end if;
  if tg_op = 'UPDATE' and old.status in ('eligible', 'processing', 'paid') then
    return new;
  end if;

  select pr.provider = 'paymongo'
         and not coalesce(pr.provider_livemode, false)
         and pr.status = 'confirmed'
    into v_test_confirmed
  from public.payment_records pr
  where pr.id = new.payment_record_id;

  if coalesce(v_test_confirmed, false) then new.status := 'pending'; end if;
  return new;
end;
$$;

drop trigger if exists normalize_test_allocation_pending_state
  on public.payment_allocations;
create trigger normalize_test_allocation_pending_state
before insert or update of status on public.payment_allocations
for each row execute function public.normalize_test_allocation_pending_state();

create or replace function public.sync_test_payment_pending_payouts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.provider <> 'paymongo'
     or coalesce(new.provider_livemode, false)
     or new.status <> 'confirmed'
     or (tg_op = 'UPDATE' and old.status = 'confirmed') then
    return new;
  end if;

  update public.payment_allocations
  set status = 'pending', eligible_at = null, eligibility_reason = null,
      last_error = null
  where payment_record_id = new.id and status = 'held';

  insert into public.payout_records (
    booking_id, driver_id, payment_stage, split_strategy, amount, status,
    source_payment_record_id, payment_allocation_id, provider_livemode
  )
  select pa.booking_id, pa.driver_id, new.payment_stage, 'equal_split',
         pa.driver_amount, 'pending', new.id, pa.id, false
  from public.payment_allocations pa
  where pa.payment_record_id = new.id and pa.status = 'pending'
  on conflict (booking_id, driver_id, payment_stage) do update
  set source_payment_record_id = excluded.source_payment_record_id,
      payment_allocation_id = excluded.payment_allocation_id,
      amount = excluded.amount,
      provider_livemode = false,
      status = case
        when payout_records.status in ('paid', 'processing', 'manual_review')
          then payout_records.status
        else 'pending'
      end;

  update public.package_bookings
  set refund_status = 'none', updated_at = now()
  where id = new.booking_id
    and refund_status in ('not_required', 'none');
  return new;
end;
$$;

drop trigger if exists sync_test_payment_pending_payouts
  on public.payment_records;
create trigger sync_test_payment_pending_payouts
after insert or update of status on public.payment_records
for each row execute function public.sync_test_payment_pending_payouts();

-- One internal outcome function is the authority for test payout state. It
-- never performs a transfer; the existing service-only claim/result RPCs do.
create or replace function public.apply_test_payout_outcome(
  p_booking_id uuid,
  p_outcome text,
  p_reason text,
  p_driver_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
begin
  if p_outcome not in ('pending', 'eligible', 'cancelled') then
    raise exception 'INVALID_PAYOUT_OUTCOME';
  end if;

  if p_outcome = 'pending' then
    update public.payment_allocations pa
    set status = 'pending', eligible_at = null, eligibility_reason = null,
        last_error = null
    from public.payment_records pr
    where pa.payment_record_id = pr.id
      and pa.booking_id = p_booking_id
      and (p_driver_id is null or pa.driver_id = p_driver_id)
      and pr.provider = 'paymongo' and not pr.provider_livemode
      and pr.status = 'confirmed'
      and pa.status in ('held', 'failed');
  elsif p_outcome = 'eligible' then
    update public.payment_allocations pa
    set status = 'eligible', eligible_at = coalesce(eligible_at, now()),
        eligibility_reason = p_reason, last_error = null
    from public.payment_records pr
    where pa.payment_record_id = pr.id
      and pa.booking_id = p_booking_id
      and (p_driver_id is null or pa.driver_id = p_driver_id)
      and pr.provider = 'paymongo' and not pr.provider_livemode
      and pr.status = 'confirmed'
      and pa.status in ('pending', 'held', 'failed', 'cancelled')
      and not exists (
        select 1 from public.payment_disputes pd
        where pd.payment_record_id = pr.id
          and pd.status in ('open', 'under_review', 'needs_review')
      )
      and not exists (
        select 1 from public.refund_requests rr
        where rr.payment_record_id = pr.id
          and rr.status in ('pending', 'approved')
      );
  else
    update public.payment_allocations pa
    set status = case when pa.status in ('paid', 'processing')
        then 'manual_review' else 'cancelled' end,
        last_error = p_reason
    where pa.booking_id = p_booking_id
      and (p_driver_id is null or pa.driver_id = p_driver_id)
      and pa.status not in ('cancelled', 'manual_review');
  end if;
  get diagnostics v_count = row_count;

  insert into public.payout_records (
    booking_id, driver_id, payment_stage, split_strategy, amount, status,
    source_payment_record_id, payment_allocation_id, provider_livemode,
    eligible_at, eligibility_reason, notes
  )
  select pa.booking_id, pa.driver_id, pr.payment_stage, 'equal_split',
         pa.driver_amount, pa.status, pr.id, pa.id, false,
         pa.eligible_at, pa.eligibility_reason,
         case when p_outcome = 'cancelled' then p_reason else null end
  from public.payment_allocations pa
  join public.payment_records pr on pr.id = pa.payment_record_id
  where pa.booking_id = p_booking_id
    and (p_driver_id is null or pa.driver_id = p_driver_id)
    and pr.provider = 'paymongo' and not pr.provider_livemode
    and pr.status = 'confirmed'
  on conflict (booking_id, driver_id, payment_stage) do update
  set source_payment_record_id = excluded.source_payment_record_id,
      payment_allocation_id = excluded.payment_allocation_id,
      amount = excluded.amount,
      status = case
        when payout_records.status = 'paid' and excluded.status <> 'paid'
          then 'manual_review'
        when payout_records.status = 'processing'
             and excluded.status = 'cancelled' then 'manual_review'
        else excluded.status
      end,
      eligible_at = excluded.eligible_at,
      eligibility_reason = excluded.eligibility_reason,
      notes = concat_ws(E'\n', nullif(payout_records.notes, ''), excluded.notes);

  return v_count;
end;
$$;
revoke all on function public.apply_test_payout_outcome(uuid,text,text,uuid)
  from public, anon, authenticated;

-- Reconcile a released slot without touching the booking-level payment. Each
-- replacement consumes exactly one cancelled allocation, which keeps group
-- booking shares stable and prevents duplicate active allocations.
create or replace function public.reconcile_allocations_after_roster_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_allocation public.payment_allocations;
  v_payment public.payment_records;
  v_replacement record;
  v_new_allocation_id uuid;
begin
  if tg_op = 'UPDATE'
     and old.status = 'accepted'
     and new.status in ('rejected', 'pending', 'cancelled', 'no_show') then
    for v_allocation in
      select * from public.payment_allocations
      where booking_driver_id = old.id
        and status in ('pending', 'held', 'eligible', 'failed', 'processing', 'paid')
      for update
    loop
      select * into v_payment from public.payment_records
      where id = v_allocation.payment_record_id for update;

      if v_allocation.status in ('pending', 'held', 'eligible', 'failed') then
        update public.payment_allocations
        set status = 'cancelled', eligible_at = null,
            eligibility_reason = null,
            last_error = 'Assignment released before payout.'
        where id = v_allocation.id;
        update public.payout_records
        set status = 'cancelled', eligible_at = null,
            eligibility_reason = null,
            notes = concat_ws(E'\n', nullif(notes, ''),
              'Assignment released before payout.')
        where payment_allocation_id = v_allocation.id and status <> 'paid';
      elsif v_allocation.status = 'processing' then
        update public.payment_allocations
        set status = 'manual_review',
            last_error = 'Assignment released while provider payout was processing.'
        where id = v_allocation.id;
        update public.payout_records
        set status = 'manual_review',
            last_error = 'Assignment released while payout was processing.'
        where payment_allocation_id = v_allocation.id;
        update public.payment_records set provider_status = 'roster_change_manual_review'
        where id = v_payment.id;
      else
        update public.payment_allocations
        set last_error = 'Assignment released after payout; manual resolution required.'
        where id = v_allocation.id;
        update public.payout_records
        set status = 'manual_review',
            last_error = 'Assignment released after payout; do not auto-reassign.'
        where payment_allocation_id = v_allocation.id;
        update public.payment_records
        set provider_status = 'paid_roster_change_manual_review'
        where id = v_payment.id;
      end if;
    end loop;
  end if;

  if new.status = 'accepted'
     and (tg_op = 'INSERT' or old.status is distinct from 'accepted') then
    for v_replacement in
      select distinct on (pa.payment_record_id)
        pa.*, pr.payment_stage, pr.provider_livemode,
        pr.status as payment_status
      from public.payment_allocations pa
      join public.payment_records pr on pr.id = pa.payment_record_id
      where pa.booking_id = new.booking_id
        and pa.status = 'cancelled'
        and pr.provider = 'paymongo'
        and pr.status in ('pending_confirmation', 'confirmed')
        and not coalesce(pr.provider_livemode, false)
        and not exists (
          select 1 from public.payment_allocations child
          where child.replaces_allocation_id = pa.id
            and child.status <> 'cancelled'
        )
        and not exists (
          select 1 from public.payment_allocations existing
          where existing.payment_record_id = pa.payment_record_id
            and existing.driver_id = new.driver_id
        )
      order by pa.payment_record_id, pa.updated_at, pa.id
    loop
      insert into public.payment_allocations (
        payment_record_id, booking_id, booking_driver_id, driver_id,
        gross_amount, platform_fee, driver_amount, split_basis_points,
        currency, status, provider_recipient_id, replaces_allocation_id
      ) values (
        v_replacement.payment_record_id, new.booking_id, new.id, new.driver_id,
        v_replacement.gross_amount, v_replacement.platform_fee,
        v_replacement.driver_amount, v_replacement.split_basis_points,
        v_replacement.currency,
        case when v_replacement.payment_status = 'confirmed'
          then 'pending' else 'held' end,
        (
          select dpa.provider_recipient_id
          from public.driver_payout_accounts dpa
          where dpa.driver_id = new.driver_id and dpa.provider = 'paymongo'
            and dpa.verification_status = 'verified' and dpa.is_default
            and dpa.provider_livemode = v_replacement.provider_livemode
          order by dpa.updated_at desc limit 1
        ),
        v_replacement.id
      ) returning id into v_new_allocation_id;

      update public.booking_drivers
      set replacement_for_booking_driver_id = v_replacement.booking_driver_id
      where id = new.id and replacement_for_booking_driver_id is null;

      if v_replacement.payment_status = 'confirmed' then
        insert into public.payout_records (
          booking_id, driver_id, payment_stage, split_strategy, amount, status,
          source_payment_record_id, payment_allocation_id, provider_livemode
        ) values (
          new.booking_id, new.driver_id, v_replacement.payment_stage,
          'equal_split', v_replacement.driver_amount, 'pending',
          v_replacement.payment_record_id, v_new_allocation_id, false
        )
        on conflict (booking_id, driver_id, payment_stage) do update
        set source_payment_record_id = excluded.source_payment_record_id,
            payment_allocation_id = excluded.payment_allocation_id,
            amount = excluded.amount,
            status = 'pending', provider_livemode = false;
      end if;
    end loop;
  end if;
  return new;
end;
$$;

-- Existing trigger name is retained, so this replacement takes effect without
-- creating a second race-prone roster writer.

create or replace function public.notify_eligible_replacement_drivers(
  p_booking_id uuid,
  p_excluded_driver_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into public.notifications (user_id, title, body, type, is_read)
  select p.id, 'Replacement driver needed',
    'An accredited tour in your service area needs a replacement Driver-Tour Guide.',
    'replacement_driver_available', false
  from public.profiles p
  join public.driver_details dd on dd.driver_id = p.id
  join public.package_bookings b on b.id = p_booking_id
  where p.role = 'driver' and p.id <> p_excluded_driver_id
    and coalesce(p.is_online, false) and coalesce(p.is_available, false)
    and public.cities_match(p.city, b.municipality)
    and lower(coalesce(dd.status, '')) in ('active', 'approved', 'verified')
    and not exists (
      select 1 from public.booking_drivers bd
      where bd.booking_id = p_booking_id and bd.driver_id = p.id
    );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.notify_eligible_replacement_drivers(uuid,uuid)
  from public, anon, authenticated;

do $$
begin
  if to_regprocedure('public.request_driver_withdrawal_lifecycle_impl(uuid,text,text)') is null then
    alter function public.request_driver_withdrawal(uuid,text,text)
      rename to request_driver_withdrawal_lifecycle_impl;
  end if;
end $$;

create or replace function public.request_driver_withdrawal(
  p_booking_id uuid,
  p_reason text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver uuid := auth.uid();
  v_result jsonb;
  v_window integer;
  v_assignment_id uuid;
begin
  select id into v_assignment_id
  from public.booking_drivers
  where booking_id = p_booking_id and driver_id = v_driver
    and status = 'accepted';

  v_result := public.request_driver_withdrawal_lifecycle_impl(
    p_booking_id, p_reason, p_note
  );

  select replacement_window_minutes into v_window
  from public.package_cancellation_policy where id = 1;

  update public.booking_drivers
  set status = 'cancelled', cancelled_at = now(),
      cancellation_reason = p_reason
  where id = v_assignment_id;

  update public.package_bookings
  set replacement_status = 'awaiting_replacement',
      replacement_search_started_at = now(),
      replacement_deadline_at = now() + make_interval(mins => coalesce(v_window, 30)),
      cancellation_party = 'driver',
      cancellation_reason_code = 'driver_withdrawal',
      refund_status = case when refund_status = 'not_required' then 'none'
        else refund_status end,
      updated_at = now()
  where id = p_booking_id;

  perform public.notify_eligible_replacement_drivers(p_booking_id, v_driver);
  return v_result || jsonb_build_object(
    'replacement_status', 'awaiting_replacement',
    'payment_preserved', true,
    'additional_downpayment_required', false
  );
end;
$$;
revoke all on function public.request_driver_withdrawal(uuid,text,text)
  from public, anon;
grant execute on function public.request_driver_withdrawal(uuid,text,text)
  to authenticated;

create or replace function public.finish_replacement_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_required integer;
  v_active integer;
  v_tourist uuid;
begin
  if new.status <> 'accepted'
     or (tg_op = 'UPDATE' and old.status = 'accepted') then return new; end if;

  select greatest(coalesce(required_drivers, 1), 1), tourist_id
    into v_required, v_tourist
  from public.package_bookings
  where id = new.booking_id and replacement_status = 'awaiting_replacement'
  for update;
  if not found then return new; end if;

  select count(*) into v_active from public.booking_drivers
  where booking_id = new.booking_id and status = 'accepted';

  if v_active >= v_required then
    update public.package_bookings
    set replacement_status = 'replacement_assigned',
        replacement_deadline_at = null,
        status = 'confirmed', booking_status = 'accepted',
        accepted_drivers_count = v_active,
        updated_at = now()
    where id = new.booking_id;

    insert into public.notifications (user_id, title, body, type, is_read)
    values (v_tourist, 'Replacement driver assigned',
      'A replacement Driver-Tour Guide has accepted. No additional downpayment is required.',
      'replacement_driver_assigned', false);
  end if;
  return new;
end;
$$;

drop trigger if exists finish_replacement_assignment on public.booking_drivers;
create trigger finish_replacement_assignment
after insert or update of status on public.booking_drivers
for each row execute function public.finish_replacement_assignment();

create or replace function public.create_full_test_refund_requests(
  p_booking_id uuid,
  p_reason text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tourist uuid;
  v_count integer;
begin
  select tourist_id into v_tourist from public.package_bookings
  where id = p_booking_id;

  insert into public.refund_requests (
    booking_id, payment_record_id, requested_by, payee_id, amount, reason,
    status, provider_refund_status
  )
  select p_booking_id, pr.id, v_tourist, v_tourist, pr.amount, p_reason,
         'pending', 'pending_submission'
  from public.payment_records pr
  where pr.booking_id = p_booking_id and pr.provider = 'paymongo'
    and not pr.provider_livemode and pr.status = 'confirmed'
  on conflict (booking_id, payment_record_id) do update
  set amount = excluded.amount, reason = excluded.reason,
      status = case when refund_requests.status = 'completed'
        then refund_requests.status else 'pending' end,
      provider_refund_status = case when refund_requests.status = 'completed'
        then refund_requests.provider_refund_status else 'pending_submission' end;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.create_full_test_refund_requests(uuid,text)
  from public, anon, authenticated;

create or replace function public.cancel_test_booking_for_service_failure(
  p_booking_id uuid,
  p_party text,
  p_reason text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_refunds integer;
begin
  update public.package_bookings
  set status = 'cancelled', booking_status = 'cancelled',
      cancelled_at = coalesce(cancelled_at, now()),
      cancellation_party = p_party,
      cancellation_reason_code = p_reason,
      cancelled_reason = p_reason,
      replacement_status = case when p_reason = 'no_replacement_driver'
        then 'no_replacement' else replacement_status end,
      refund_status = 'processing', updated_at = now()
  where id = p_booking_id;

  update public.booking_drivers
  set status = case when status = 'accepted' then 'rejected' else status end,
      cancelled_at = case when status = 'accepted' then now() else cancelled_at end,
      cancellation_reason = case when status = 'accepted' then p_reason
        else cancellation_reason end
  where booking_id = p_booking_id and status in ('pending', 'accepted');

  perform public.apply_test_payout_outcome(
    p_booking_id, 'cancelled', p_reason, null
  );
  v_refunds := public.create_full_test_refund_requests(p_booking_id, p_reason);
  return v_refunds;
end;
$$;
revoke all on function public.cancel_test_booking_for_service_failure(uuid,text,text)
  from public, anon, authenticated;

create or replace function public.process_expired_driver_replacements()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking record;
  v_count integer := 0;
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role'
     and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;

  for v_booking in
    select b.id
    from public.package_bookings b
    where b.replacement_status = 'awaiting_replacement'
      and b.replacement_deadline_at <= now()
      and (select count(*) from public.booking_drivers bd
           where bd.booking_id = b.id and bd.status = 'accepted')
          < greatest(coalesce(b.required_drivers, 1), 1)
    for update skip locked
  loop
    perform public.cancel_test_booking_for_service_failure(
      v_booking.id, 'system', 'no_replacement_driver'
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.process_expired_driver_replacements()
  from public, anon, authenticated;
grant execute on function public.process_expired_driver_replacements()
  to service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'touristrike-expired-driver-replacements',
      '* * * * *',
      'select public.process_expired_driver_replacements()'
    );
  else
    raise notice 'pg_cron unavailable: schedule process_expired_driver_replacements every minute';
  end if;
end $$;

-- Configurable 12-hour default. The scheduled timestamptz is the sole clock;
-- exactly at the cutoff is late and therefore non-refundable.
create or replace function public.package_booking_cancellation_eligibility(
  p_booking_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  b public.package_bookings;
  v_status text;
  v_hours numeric;
  v_paid numeric := 0;
  v_available numeric := 0;
  v_refundable numeric := 0;
  v_cutoff integer := 12;
  v_early boolean;
  v_assigned boolean;
begin
  select * into b from public.package_bookings where id = p_booking_id;
  if not found then return jsonb_build_object('can_cancel',false,
    'reason_code','BOOKING_NOT_FOUND','display_message','This booking could not be found.'); end if;
  if p_actor_id is null or b.tourist_id is distinct from p_actor_id then
    return jsonb_build_object('can_cancel',false,'reason_code','NOT_BOOKING_OWNER',
      'display_message','You are not allowed to cancel this booking.');
  end if;

  v_status := lower(coalesce(b.booking_status,b.status,''));
  if v_status = 'cancelled' or b.cancelled_at is not null then
    return jsonb_build_object('can_cancel',false,'reason_code','BOOKING_ALREADY_CANCELLED',
      'display_message','This booking has already been cancelled.');
  end if;
  if v_status in ('completed','done','refunded','tourist_no_show') then
    return jsonb_build_object('can_cancel',false,'reason_code','TOUR_ALREADY_COMPLETED',
      'display_message','Completed tours can no longer be cancelled.');
  end if;
  if b.picked_up_at is not null or v_status = 'on_tour' or exists (
    select 1 from public.package_activities pa where pa.booking_id=p_booking_id
      and lower(coalesce(pa.tour_status,pa.status,'')) in
      ('picked_up','on_tour','en_route_to_spot','at_spot','en_route_to_dropoff',
       'ready_to_complete','dropped_off','completed')) then
    return jsonb_build_object('can_cancel',false,'tour_started',true,
      'reason_code','TOUR_ALREADY_STARTED',
      'display_message','This tour has already started. Standard cancellation is unavailable; use Report Problem or Emergency Termination.');
  end if;
  if b.arrived_at is not null or exists (
    select 1 from public.package_activities pa where pa.booking_id=p_booking_id
      and lower(coalesce(pa.tour_status,''))='driver_arrived') then
    return jsonb_build_object('can_cancel',false,'reason_code','DRIVER_ALREADY_ARRIVED',
      'display_message','The Driver has arrived. Use Report Problem if assistance is required.');
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
  if exists (select 1 from public.payment_disputes d
      join public.payment_records pr on pr.id=d.payment_record_id
      where pr.booking_id=p_booking_id
        and d.status in ('open','under_review','needs_review')) then
    return jsonb_build_object('can_cancel',false,'reason_code','PAYMENT_DISPUTE_ACTIVE',
      'display_message','Cancellation is unavailable while a payment dispute is under review.');
  end if;

  select coalesce(free_cancellation_hours, 12) into v_cutoff
  from public.package_cancellation_policy where id = 1;
  select coalesce(sum(pr.amount),0),
    coalesce(sum(case when rr.id is null then pr.amount else 0 end),0)
    into v_paid,v_available
  from public.payment_records pr
  left join public.refund_requests rr on rr.booking_id=p_booking_id
    and rr.payment_record_id=pr.id and rr.status in ('pending','approved','completed')
  where pr.booking_id=p_booking_id and pr.status='confirmed';

  v_early := b.scheduled_start_at > now() + make_interval(hours => v_cutoff);
  v_hours := extract(epoch from b.scheduled_start_at-now())/3600;
  v_refundable := case when v_early then v_available else 0 end;
  v_assigned := b.assigned_driver_id is not null or exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id=p_booking_id and bd.status='accepted');

  return jsonb_build_object(
    'can_cancel',true,'reason_code','CANCELLATION_ALLOWED',
    'display_message',case when v_early
      then 'More than '||v_cutoff||' hours before the scheduled tour. Confirmed test payments are eligible for a full refund.'
      else 'Within '||v_cutoff||' hours of the scheduled tour. The payment is non-refundable and the assigned Driver payout may become eligible.' end,
    'cancellation_type',case when v_early then 'early' else 'late' end,
    'package_title',coalesce((select tp.title from public.tour_packages tp where tp.id=b.package_id),'Tour package'),
    'scheduled_at',b.scheduled_start_at,'hours_before_tour',v_hours,
    'free_cancellation_hours',v_cutoff,'tour_started',false,
    'amount_paid',v_paid,'confirmed_amount_paid',v_paid,
    'refundable_amount',v_refundable,'estimated_refundable_amount',v_refundable,
    'refund_eligible',v_refundable>0,'requires_review',false,
    'cancellation_fee',greatest(v_paid-v_refundable,0),
    'non_refundable_amount',greatest(v_paid-v_refundable,0),
    'refund_rate',case when v_early then 100 else 0 end,
    'refund_type',case when v_paid=0 then 'no_payment'
      when v_refundable=0 then 'non_refundable' else 'full_refund_request' end,
    'has_assigned_drivers',v_assigned);
end;
$$;
revoke all on function public.package_booking_cancellation_eligibility(uuid,uuid)
  from public, anon, authenticated;

do $$
begin
  if to_regprocedure('public.cancel_package_booking_pending_payout_impl(uuid,text,text,text)') is null then
    alter function public.cancel_package_booking(uuid,text,text,text)
      rename to cancel_package_booking_pending_payout_impl;
  end if;
end $$;

create or replace function public.cancel_package_booking(
  p_booking_id uuid,
  p_reason text,
  p_note text default null,
  p_category text default 'general'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_early boolean;
  v_paid numeric;
begin
  v_result := public.cancel_package_booking_pending_payout_impl(
    p_booking_id, p_reason, p_note, p_category
  );
  v_early := coalesce((v_result->>'refund_eligible')::boolean, false);
  v_paid := coalesce((v_result->>'amount_paid')::numeric, 0);

  update public.package_bookings
  set cancellation_party = 'tourist', cancellation_reason_code = p_reason,
      refund_status = case
        when v_paid = 0 then 'none'
        when v_early then 'processing'
        else 'not_eligible'
      end,
      payout_eligibility_reason = case when not v_early and v_paid > 0
        then 'tourist_late_cancellation' else null end,
      updated_at = now()
  where id = p_booking_id;

  if v_early and v_paid > 0 then
    update public.refund_requests rr
    set provider_refund_status = case when pr.provider = 'paymongo'
      and not pr.provider_livemode then 'pending_submission'
      else rr.provider_refund_status end
    from public.payment_records pr
    where rr.booking_id = p_booking_id and rr.payment_record_id = pr.id
      and rr.status = 'pending';
    perform public.apply_test_payout_outcome(
      p_booking_id, 'cancelled', 'tourist_early_cancellation', null
    );
  elsif not v_early and v_paid > 0 then
    perform public.apply_test_payout_outcome(
      p_booking_id, 'eligible', 'tourist_late_cancellation', null
    );
  end if;

  return v_result || jsonb_build_object(
    'refund_status', case when v_paid = 0 then 'none'
      when v_early then 'processing' else 'not_eligible' end,
    'payout_status', case when not v_early and v_paid > 0
      then 'eligible' else 'cancelled' end
  );
end;
$$;
revoke all on function public.cancel_package_booking(uuid,text,text,text)
  from public, anon;
grant execute on function public.cancel_package_booking(uuid,text,text,text)
  to authenticated;

create or replace function public.mark_completed_booking_payout_eligible()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if lower(coalesce(new.booking_status,new.status,'')) in ('completed','done')
     and lower(coalesce(old.booking_status,old.status,''))
       not in ('completed','done') then
    perform public.apply_test_payout_outcome(
      new.id, 'eligible', 'tour_completed', null
    );
    new.payout_eligibility_reason := 'tour_completed';
  end if;
  return new;
end;
$$;

drop trigger if exists mark_completed_booking_payout_eligible
  on public.package_bookings;
create trigger mark_completed_booking_payout_eligible
before update of status, booking_status on public.package_bookings
for each row execute function public.mark_completed_booking_payout_eligible();

create or replace function public.report_booking_no_show(
  p_booking_id uuid,
  p_reported_party text,
  p_note text default null
)
returns public.booking_no_show_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_booking public.package_bookings;
  v_driver public.booking_drivers;
  v_grace integer := 15;
  v_arrival boolean := false;
  v_report public.booking_no_show_reports;
begin
  if v_actor is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_reported_party not in ('driver','tourist') then
    raise exception 'INVALID_REPORTED_PARTY'; end if;
  select * into v_booking from public.package_bookings
  where id=p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  select coalesce(no_show_grace_minutes,15) into v_grace
  from public.package_cancellation_policy where id=1;
  if v_booking.scheduled_start_at is null
     or now() < v_booking.scheduled_start_at + make_interval(mins => v_grace) then
    raise exception 'NO_SHOW_GRACE_PERIOD_ACTIVE';
  end if;

  if p_reported_party='driver' then
    if v_booking.tourist_id <> v_actor then raise exception 'TOURIST_ROLE_REQUIRED'; end if;
    select * into v_driver from public.booking_drivers
    where booking_id=p_booking_id and status='accepted'
    order by accepted_at limit 1;
    if not found then raise exception 'ACTIVE_DRIVER_REQUIRED'; end if;
  else
    select * into v_driver from public.booking_drivers
    where booking_id=p_booking_id and driver_id=v_actor and status='accepted';
    if not found then raise exception 'ACTIVE_DRIVER_REQUIRED'; end if;
  end if;

  v_arrival := v_booking.arrived_at is not null or exists (
    select 1 from public.package_activities pa
    where pa.booking_id=p_booking_id
      and lower(coalesce(pa.tour_status,'')) in ('driver_arrived','picked_up','on_tour')
  ) or exists (
    select 1 from public.driver_live_locations dll
    join public.package_activities pa on pa.id=dll.activity_id
    where pa.booking_id=p_booking_id
      and dll.updated_at >= v_booking.scheduled_start_at - interval '30 minutes'
  );

  if p_reported_party='tourist' and not v_arrival then
    raise exception 'DRIVER_ARRIVAL_EVIDENCE_REQUIRED';
  end if;

  insert into public.booking_no_show_reports (
    booking_id, booking_driver_id, reported_by, reported_party, report_note,
    arrival_evidence, progression_evidence
  ) values (
    p_booking_id, v_driver.id, v_actor, p_reported_party,
    nullif(trim(coalesce(p_note,'')),''),
    jsonb_build_object('driver_arrival_recorded',v_arrival,
      'booking_arrived_at',v_booking.arrived_at),
    jsonb_build_object('booking_status',v_booking.booking_status,
      'scheduled_start_at',v_booking.scheduled_start_at,
      'grace_minutes',v_grace)
  )
  on conflict (booking_id,booking_driver_id,reported_party) do update
  set report_note=excluded.report_note,
      arrival_evidence=excluded.arrival_evidence,
      progression_evidence=excluded.progression_evidence,
      reported_at=now()
  returning * into v_report;
  return v_report;
end;
$$;
revoke all on function public.report_booking_no_show(uuid,text,text)
  from public, anon;
grant execute on function public.report_booking_no_show(uuid,text,text)
  to authenticated;

create or replace function public.resolve_booking_no_show_report(
  p_report_id uuid,
  p_verified boolean,
  p_resolution_note text default null,
  p_attempt_replacement boolean default true
)
returns public.booking_no_show_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_report public.booking_no_show_reports;
  v_booking public.package_bookings;
  v_window integer := 30;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role'
     and public.current_profile_role() not in ('admin','subtenant') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  select * into v_report from public.booking_no_show_reports
  where id=p_report_id for update;
  if not found then raise exception 'NO_SHOW_REPORT_NOT_FOUND'; end if;
  if v_report.status <> 'pending' then raise exception 'NO_SHOW_REPORT_ALREADY_RESOLVED'; end if;
  select * into v_booking from public.package_bookings
  where id=v_report.booking_id for update;

  update public.booking_no_show_reports
  set status=case when p_verified then 'verified' else 'rejected' end,
      resolved_at=now(), resolved_by=v_actor,
      resolution_note=nullif(trim(coalesce(p_resolution_note,'')),'')
  where id=p_report_id returning * into v_report;
  if not p_verified then return v_report; end if;

  if v_report.reported_party='driver' then
    update public.booking_drivers
    set status='no_show', cancelled_at=now(),
        cancellation_reason='verified_driver_no_show'
    where id=v_report.booking_driver_id and status='accepted';
    perform public.apply_test_payout_outcome(
      v_report.booking_id,'cancelled','verified_driver_no_show',
      (select driver_id from public.booking_drivers where id=v_report.booking_driver_id)
    );
    select coalesce(replacement_window_minutes,30) into v_window
    from public.package_cancellation_policy where id=1;
    if p_attempt_replacement
       and now() < v_booking.scheduled_start_at + make_interval(mins => v_window) then
      update public.package_bookings
      set status='pending', booking_status='waiting_for_drivers',
          replacement_status='awaiting_replacement',
          replacement_search_started_at=now(),
          replacement_deadline_at=now()+make_interval(mins => v_window),
          cancellation_party='driver',
          cancellation_reason_code='verified_driver_no_show',
          updated_at=now()
      where id=v_report.booking_id;
      perform public.notify_eligible_replacement_drivers(
        v_report.booking_id,
        (select driver_id from public.booking_drivers where id=v_report.booking_driver_id)
      );
    else
      perform public.cancel_test_booking_for_service_failure(
        v_report.booking_id,'driver','verified_driver_no_show'
      );
    end if;
  else
    update public.package_bookings
    set status='cancelled', booking_status='tourist_no_show',
        cancelled_at=now(), cancellation_party='tourist',
        cancellation_reason_code='verified_tourist_no_show',
        cancelled_reason='verified_tourist_no_show',
        refund_status='not_eligible',
        payout_eligibility_reason='verified_tourist_no_show',
        updated_at=now()
    where id=v_report.booking_id;
    perform public.apply_test_payout_outcome(
      v_report.booking_id,'eligible','verified_tourist_no_show',null
    );
  end if;
  return v_report;
end;
$$;
revoke all on function public.resolve_booking_no_show_report(uuid,boolean,text,boolean)
  from public, anon;
grant execute on function public.resolve_booking_no_show_report(uuid,boolean,text,boolean)
  to authenticated, service_role;

create or replace function public.sync_booking_refund_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'completed' and old.status <> 'completed' then
    update public.package_bookings b
    set refund_status = case when not exists (
          select 1 from public.refund_requests rr
          where rr.booking_id=new.booking_id and rr.status <> 'completed'
        ) then 'refunded' else 'processing' end,
        updated_at=now()
    where b.id=new.booking_id;
  elsif new.status in ('pending','approved') then
    update public.package_bookings
    set refund_status='processing', updated_at=now()
    where id=new.booking_id and refund_status <> 'refunded';
  end if;
  return new;
end;
$$;

drop trigger if exists sync_booking_refund_status on public.refund_requests;
create trigger sync_booking_refund_status
after insert or update of status on public.refund_requests
for each row execute function public.sync_booking_refund_status();

-- Keep the established service-only eligibility RPC, but recognize the
-- explicit outcomes introduced above in addition to tour completion.
create or replace function public.refresh_payment_allocation_eligibility(
  p_booking_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reason text;
begin
  select case
    when lower(coalesce(booking_status,status,'')) in ('completed','done')
      then 'tour_completed'
    when payout_eligibility_reason='tourist_late_cancellation'
      then 'tourist_late_cancellation'
    when payout_eligibility_reason='verified_tourist_no_show'
      then 'verified_tourist_no_show'
    else null end
  into v_reason from public.package_bookings where id=p_booking_id;
  if v_reason is null then return 0; end if;
  return public.apply_test_payout_outcome(
    p_booking_id,'eligible',v_reason,null
  );
end;
$$;
revoke all on function public.refresh_payment_allocation_eligibility(uuid)
  from public, anon, authenticated;
grant execute on function public.refresh_payment_allocation_eligibility(uuid)
  to service_role;

commit;
