-- Allocation roster reconciliation and an idempotent payout state machine.
-- This does not invent a disbursement API: live transfer calls stay disabled
-- until the merchant has the corresponding PayMongo product approval.

create or replace function public.reconcile_allocations_after_roster_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allocation public.payment_allocations;
  v_payment public.payment_records;
  v_replacement record;
begin
  if tg_op = 'UPDATE' and old.status = 'accepted' and new.status in ('rejected', 'pending') then
    for v_allocation in
      select * from public.payment_allocations
      where booking_driver_id = old.id
        and status in ('held', 'eligible', 'failed', 'processing', 'paid')
      for update
    loop
      select * into v_payment from public.payment_records
      where id = v_allocation.payment_record_id for update;

      if v_allocation.status in ('held', 'eligible', 'failed') then
        update public.payment_allocations set status = 'cancelled',
          last_error = 'Assignment released before payout.'
        where id = v_allocation.id;
        update public.payout_records set status = 'cancelled',
          notes = concat_ws(E'\n', nullif(notes, ''),
            'Assignment released before payout.')
        where payment_allocation_id = v_allocation.id
          and status <> 'paid';
      elsif v_allocation.status = 'processing' then
        update public.payment_allocations set status = 'manual_review',
          last_error = 'Assignment released while provider payout was processing.'
        where id = v_allocation.id;
        update public.payout_records set status = 'manual_review',
          last_error = 'Assignment released while payout was processing.'
        where payment_allocation_id = v_allocation.id;
        update public.payment_records set
          provider_status = 'roster_change_manual_review'
        where id = v_payment.id;
      else
        update public.payment_allocations set
          last_error = 'Assignment released after payout; manual resolution required.'
        where id = v_allocation.id;
        update public.payout_records set status = 'manual_review',
          last_error = 'Assignment released after payout; do not auto-reassign.'
        where payment_allocation_id = v_allocation.id;
        update public.payment_records set
          provider_status = 'paid_roster_change_manual_review'
        where id = v_payment.id;
      end if;
    end loop;
  end if;

  if new.status = 'accepted'
     and (tg_op = 'INSERT' or old.status is distinct from 'accepted') then
    for v_replacement in
      select distinct on (pa.payment_record_id)
        pa.*, pr.payment_stage, pr.provider_livemode
      from public.payment_allocations pa
      join public.payment_records pr on pr.id = pa.payment_record_id
      where pa.booking_id = new.booking_id and pa.status = 'cancelled'
        and pr.provider = 'paymongo' and pr.status = 'confirmed'
        and not exists (
          select 1 from public.payment_allocations existing
          where existing.payment_record_id = pa.payment_record_id
            and existing.driver_id = new.driver_id
        )
      order by pa.payment_record_id, pa.updated_at
    loop
      insert into public.payment_allocations (
        payment_record_id, booking_id, booking_driver_id, driver_id,
        gross_amount, platform_fee, driver_amount, split_basis_points,
        currency, status,
        provider_recipient_id
      ) values (
        v_replacement.payment_record_id, new.booking_id, new.id, new.driver_id,
        v_replacement.gross_amount, v_replacement.platform_fee,
        v_replacement.driver_amount, v_replacement.split_basis_points,
        v_replacement.currency, 'held',
        (
          select dpa.provider_recipient_id
          from public.driver_payout_accounts dpa
          where dpa.driver_id = new.driver_id and dpa.provider = 'paymongo'
            and dpa.verification_status = 'verified' and dpa.is_default
            and dpa.provider_livemode = v_replacement.provider_livemode
          order by dpa.updated_at desc limit 1
        )
      );
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_reconcile_allocations_after_roster_change
  on public.booking_drivers;
create trigger trg_reconcile_allocations_after_roster_change
after insert or update of status on public.booking_drivers
for each row execute function public.reconcile_allocations_after_roster_change();

create or replace function public.refresh_payment_allocation_eligibility(
  p_booking_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_count integer;
begin
  -- Conservative release rule: money is not eligible merely because it was
  -- received. The booking/convoy must be complete and free of refund/dispute.
  update public.payment_allocations pa
  set status = 'eligible', last_error = null
  from public.payment_records pr, public.package_bookings pb
  where pa.payment_record_id = pr.id and pa.booking_id = pb.id
    and pa.booking_id = p_booking_id
    and pa.status in ('held', 'failed')
    and pr.status = 'confirmed'
    and lower(coalesce(pb.booking_status, pb.status, '')) in ('completed', 'done')
    and exists (
      select 1 from public.booking_drivers bd
      where bd.id = pa.booking_driver_id and bd.driver_id = pa.driver_id
        and bd.status = 'completed'
    )
    and not exists (
      select 1 from public.payment_disputes pd
      where pd.payment_record_id = pr.id and pd.status in ('open', 'under_review')
    )
    and not exists (
      select 1 from public.refund_requests rr
      where rr.payment_record_id = pr.id and rr.status in ('pending', 'approved')
    );
  get diagnostics v_count = row_count;

  insert into public.payout_records (
    booking_id, driver_id, payment_stage, split_strategy, amount, status,
    source_payment_record_id, payment_allocation_id, provider_livemode
  )
  select pa.booking_id, pa.driver_id, pr.payment_stage, 'equal_split',
         pa.driver_amount, pa.status, pr.id, pa.id, pr.provider_livemode
  from public.payment_allocations pa
  join public.payment_records pr on pr.id = pa.payment_record_id
  where pa.booking_id = p_booking_id and pa.status = 'eligible'
  on conflict (booking_id, driver_id, payment_stage) do update
    set payment_allocation_id = excluded.payment_allocation_id,
        source_payment_record_id = excluded.source_payment_record_id,
        amount = excluded.amount,
        status = excluded.status,
        provider_livemode = excluded.provider_livemode;
  return v_count;
end;
$$;
revoke all on function public.refresh_payment_allocation_eligibility(uuid)
  from public, anon, authenticated;
grant execute on function public.refresh_payment_allocation_eligibility(uuid)
  to service_role;

create or replace function public.claim_payment_allocation_for_payout(
  p_allocation_id uuid
)
returns public.payment_allocations
language plpgsql
security definer
set search_path = public
as $$
declare v_allocation public.payment_allocations; v_payment public.payment_records;
begin
  select * into v_allocation from public.payment_allocations
  where id = p_allocation_id for update;
  if not found then raise exception 'PAYMENT_ALLOCATION_NOT_FOUND'; end if;
  if v_allocation.status = 'paid' then raise exception 'ALLOCATION_ALREADY_PAID'; end if;
  if v_allocation.status = 'processing' then raise exception 'PAYOUT_ALREADY_PROCESSING'; end if;
  if v_allocation.status not in ('eligible', 'failed') then
    raise exception 'ALLOCATION_NOT_ELIGIBLE';
  end if;
  select * into v_payment from public.payment_records
  where id = v_allocation.payment_record_id for key share;
  if v_payment.status <> 'confirmed' then raise exception 'PAYMENT_NOT_CONFIRMED'; end if;
  if exists (
    select 1 from public.payment_disputes
    where payment_record_id = v_payment.id and status in ('open', 'under_review')
  ) or exists (
    select 1 from public.refund_requests
    where payment_record_id = v_payment.id and status in ('pending', 'approved')
  ) then raise exception 'PAYOUT_HELD_FOR_REVIEW'; end if;

  update public.payment_allocations set status = 'processing',
    attempt_count = attempt_count + 1, last_error = null
  where id = p_allocation_id returning * into v_allocation;
  update public.payout_records set status = 'processing',
    attempt_count = attempt_count + 1, last_error = null
  where payment_allocation_id = p_allocation_id;
  return v_allocation;
end;
$$;
revoke all on function public.claim_payment_allocation_for_payout(uuid)
  from public, anon, authenticated;
grant execute on function public.claim_payment_allocation_for_payout(uuid)
  to service_role;

create or replace function public.record_payment_allocation_transfer_result(
  p_allocation_id uuid,
  p_succeeded boolean,
  p_provider_transfer_id text,
  p_provider_status text,
  p_last_error text default null
)
returns public.payment_allocations
language plpgsql
security definer
set search_path = public
as $$
declare v_allocation public.payment_allocations;
begin
  select * into v_allocation from public.payment_allocations
  where id = p_allocation_id for update;
  if not found then raise exception 'PAYMENT_ALLOCATION_NOT_FOUND'; end if;
  if v_allocation.status = 'paid' then
    if p_provider_transfer_id is distinct from v_allocation.provider_transfer_id then
      raise exception 'ALLOCATION_ALREADY_PAID_WITH_DIFFERENT_REFERENCE';
    end if;
    return v_allocation;
  end if;
  if v_allocation.status <> 'processing' then raise exception 'PAYOUT_NOT_PROCESSING'; end if;
  if p_succeeded and nullif(p_provider_transfer_id, '') is null then
    raise exception 'PROVIDER_TRANSFER_REFERENCE_REQUIRED';
  end if;

  update public.payment_allocations set
    status = case when p_succeeded then 'paid' else 'failed' end,
    provider_transfer_id = case when p_succeeded
      then p_provider_transfer_id else provider_transfer_id end,
    provider_transfer_status = p_provider_status,
    last_error = case when p_succeeded then null else left(p_last_error, 1000) end,
    paid_at = case when p_succeeded then now() else paid_at end
  where id = p_allocation_id returning * into v_allocation;
  update public.payout_records set
    status = case when p_succeeded then 'paid' else 'failed' end,
    provider_transfer_id = case when p_succeeded
      then p_provider_transfer_id else provider_transfer_id end,
    provider_status = p_provider_status,
    paymongo_reference = case when p_succeeded
      then p_provider_transfer_id else paymongo_reference end,
    last_error = case when p_succeeded then null else left(p_last_error, 1000) end,
    processed_at = now()
  where payment_allocation_id = p_allocation_id;
  return v_allocation;
end;
$$;
revoke all on function public.record_payment_allocation_transfer_result(
  uuid, boolean, text, text, text
) from public, anon, authenticated;
grant execute on function public.record_payment_allocation_transfer_result(
  uuid, boolean, text, text, text
) to service_role;

create or replace function public.get_payment_reconciliation(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_profile_role() not in ('admin', 'subtenant') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  return jsonb_build_object(
    'booking', (select to_jsonb(pb) from public.package_bookings pb
      where pb.id = p_booking_id),
    'payments', coalesce((select jsonb_agg(to_jsonb(pr) order by pr.created_at)
      from public.payment_records pr where pr.booking_id = p_booking_id), '[]'::jsonb),
    'allocations', coalesce((select jsonb_agg(to_jsonb(pa) order by pa.created_at)
      from public.payment_allocations pa where pa.booking_id = p_booking_id), '[]'::jsonb),
    'payouts', coalesce((select jsonb_agg(to_jsonb(po) order by po.created_at)
      from public.payout_records po where po.booking_id = p_booking_id), '[]'::jsonb),
    'disputes', coalesce((select jsonb_agg(to_jsonb(pd) order by pd.created_at)
      from public.payment_disputes pd where pd.booking_id = p_booking_id), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(to_jsonb(rr) order by rr.created_at)
      from public.refund_requests rr where rr.booking_id = p_booking_id), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_payment_reconciliation(uuid) from public;
grant execute on function public.get_payment_reconciliation(uuid) to authenticated;

create or replace function public.guard_paymongo_refund_completion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'completed' and old.status <> 'completed'
     and exists (
       select 1 from public.payment_records pr
       where pr.id = new.payment_record_id and pr.provider = 'paymongo'
     ) and (
       coalesce(auth.jwt()->>'role', '') <> 'service_role'
       or lower(coalesce(new.provider_refund_status, ''))
            not in ('succeeded', 'completed', 'refunded')
       or new.provider_confirmed_at is null
       or new.provider_refund_id is null
     ) then
    raise exception 'PROVIDER_REFUND_CONFIRMATION_REQUIRED';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_paymongo_refund_completion
  on public.refund_requests;
create trigger trg_guard_paymongo_refund_completion
before update on public.refund_requests
for each row execute function public.guard_paymongo_refund_completion();

create or replace function public.record_paymongo_refund_result(
  p_refund_request_id uuid,
  p_provider_refund_id text,
  p_provider_status text,
  p_provider_payload jsonb
)
returns public.refund_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_refund public.refund_requests;
  v_success boolean := lower(p_provider_status)
    in ('succeeded', 'completed', 'refunded');
begin
  select rr.* into v_refund
  from public.refund_requests rr
  join public.payment_records pr on pr.id = rr.payment_record_id
  where rr.id = p_refund_request_id and pr.provider = 'paymongo'
  for update of rr;
  if not found then raise exception 'PAYMONGO_REFUND_REQUEST_NOT_FOUND'; end if;
  if v_refund.status = 'completed' then
    if p_provider_refund_id is distinct from v_refund.provider_refund_id then
      raise exception 'REFUND_ALREADY_COMPLETED_WITH_DIFFERENT_REFERENCE';
    end if;
    return v_refund;
  end if;

  update public.refund_requests set
    provider_refund_id = coalesce(provider_refund_id, p_provider_refund_id),
    provider_refund_status = p_provider_status,
    provider_payload = p_provider_payload,
    provider_confirmed_at = case when v_success then now()
      else provider_confirmed_at end,
    status = case when v_success then 'completed' else status end,
    completed_at = case when v_success then now() else completed_at end
  where id = p_refund_request_id returning * into v_refund;

  if v_success then
    update public.payment_records set status = 'cancelled',
      provider_status = 'refunded', provider_payload = p_provider_payload
    where id = v_refund.payment_record_id;
    update public.payment_allocations set
      status = case when status = 'paid' then 'manual_review' else 'cancelled' end,
      provider_transfer_status = 'refund_confirmed',
      last_error = case when status = 'paid'
        then 'Provider refund confirmed after linked-account payout; reconcile proportional clawback.'
        else last_error end
    where payment_record_id = v_refund.payment_record_id;
  end if;
  return v_refund;
end;
$$;
revoke all on function public.record_paymongo_refund_result(uuid, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.record_paymongo_refund_result(uuid, text, text, jsonb)
  to service_role;
