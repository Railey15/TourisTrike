-- Preserve the authoritative remaining-balance components with each payment.
-- Older records remain null: their historical component split cannot safely be
-- reconstructed from the booking's current balance.
begin;

alter table public.payment_records
  add column if not exists remaining_package_component numeric(14,2),
  add column if not exists additional_waiting_component numeric(14,2);

alter table public.payment_records
  add constraint payment_remaining_components_valid check (
    (remaining_package_component is null and additional_waiting_component is null)
    or (remaining_package_component >= 0 and additional_waiting_component >= 0
      and payment_stage = 'remaining_balance'
      and remaining_package_component + additional_waiting_component = amount)
  );

create or replace function public.snapshot_remaining_payment_components()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_waiting numeric(14,2); v_last_paid timestamptz;
begin
  if tg_op = 'UPDATE' then
    if new.remaining_package_component is distinct from old.remaining_package_component
       or new.additional_waiting_component is distinct from old.additional_waiting_component then
      raise exception 'PAYMENT_COMPONENT_SNAPSHOT_IMMUTABLE';
    end if;
    return new;
  end if;

  new.remaining_package_component := null;
  new.additional_waiting_component := null;
  if new.booking_id is null or new.payment_stage <> 'remaining_balance' then
    return new;
  end if;

  -- A later tour charge can reopen the remaining stage after an earlier
  -- confirmed payment. The ledger keeps those older finalized charges, but
  -- this receipt must snapshot only charges incurred since that settlement.
  select max(coalesce(p.paid_at,p.created_at)) into v_last_paid
  from public.payment_records p
  where p.booking_id=new.booking_id and p.status='confirmed'
    and p.payment_stage in ('remaining_balance','full');
  select coalesce(sum(c.additional_amount),0)::numeric(14,2)
    into v_waiting
  from public.booking_stop_waiting_charges c
  where c.booking_id = new.booking_id and c.status = 'finalized'
    and (v_last_paid is null or c.finalized_at > v_last_paid);
  if v_waiting < 0 or v_waiting > new.amount then
    raise exception 'PAYMENT_COMPONENTS_OUT_OF_SYNC';
  end if;
  if exists (
    select 1 from public.booking_stop_waiting_charges c
    where c.booking_id = new.booking_id and c.status = 'active'
  ) then
    raise exception 'WAITING_CHARGE_NOT_FINALIZED';
  end if;
  new.additional_waiting_component := v_waiting;
  new.remaining_package_component := new.amount - v_waiting;
  return new;
end $$;

revoke all on function public.snapshot_remaining_payment_components()
  from public, anon, authenticated;
drop trigger if exists zzz_snapshot_remaining_payment_components on public.payment_records;
create trigger zzz_snapshot_remaining_payment_components
before insert or update of remaining_package_component, additional_waiting_component
on public.payment_records for each row
execute function public.snapshot_remaining_payment_components();

commit;
