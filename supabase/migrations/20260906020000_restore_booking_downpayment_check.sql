-- Restore the existing payment predicate from 20260831010000 for databases
-- where journey-transition RPCs were installed without this dependency.
-- This is an internal helper; the authenticated journey RPC owns access.
begin;

create or replace function public.is_booking_downpayment_confirmed(
  p_booking_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_required_amount numeric(14,2);
begin
  select round(
    case
      when coalesce(pb.downpayment_amount, 0) > 0
        then pb.downpayment_amount
      else coalesce(pb.total_amount, 0) * 0.50
    end,
    2
  )
  into v_required_amount
  from public.package_bookings pb
  where pb.id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if v_required_amount <= 0 then return true; end if;

  return exists (
    select 1
    from public.payment_records pr
    where pr.booking_id = p_booking_id
      and pr.payment_stage in ('down_payment', 'full')
      and pr.status = 'confirmed'
      and pr.amount >= v_required_amount
  );
end;
$$;

revoke all on function public.is_booking_downpayment_confirmed(uuid)
  from public, anon, authenticated;

commit;
