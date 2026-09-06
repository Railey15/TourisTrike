-- A test booking may reach drop-off using the authorized payment bypass.
-- If progression returns to normal mode, assignment completion must still
-- require the existing confirmed/waived remaining-payment requirement.
begin;

create or replace function public.guard_driver_completion_remaining_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.journey_state = 'completed'
     and old.journey_state is distinct from new.journey_state then
    if public.is_developer_test_booking(new.booking_id)
       and auth.uid() = new.driver_id
       and coalesce(current_setting('touristrike.debug_progression_bypass', true), '') = 'true' then
      return new;
    end if;
    if not public.is_booking_remaining_payment_satisfied(new.booking_id) then
      raise exception 'REMAINING_BALANCE_NOT_CONFIRMED';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.guard_driver_completion_remaining_payment()
  from public, anon, authenticated;

drop trigger if exists trg_guard_driver_completion_remaining_payment on public.booking_drivers;
create trigger trg_guard_driver_completion_remaining_payment
before update of journey_state on public.booking_drivers
for each row execute function public.guard_driver_completion_remaining_payment();

commit;
