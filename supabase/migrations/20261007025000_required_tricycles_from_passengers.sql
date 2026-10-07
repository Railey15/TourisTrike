-- Keep the existing three-passenger rule in one backend function. Both the
-- booking guard and the client read this value.
begin;

create or replace function public.tricycle_passenger_capacity()
returns integer language sql immutable set search_path = public as $$
  select 3;
$$;
revoke all on function public.tricycle_passenger_capacity() from public, anon;
grant execute on function public.tricycle_passenger_capacity() to authenticated;

create or replace function public.minimum_required_tricycles(
  p_total_passengers integer
)
returns integer language sql immutable set search_path = public as $$
  select greatest(
    ceil(greatest(coalesce(p_total_passengers, 1), 1)::numeric
      / public.tricycle_passenger_capacity())::integer,
    1
  );
$$;

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
       public.minimum_required_tricycles(new.total_passengers) then
      raise exception 'TRICYCLE_COUNT_MUST_MATCH_PASSENGERS';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_booking_schedule_and_capacity
  on public.package_bookings;
create trigger trg_validate_booking_schedule_and_capacity
before insert or update of scheduled_start_at, estimated_end_at, travel_date,
  adults, children, total_passengers, required_drivers
on public.package_bookings
for each row execute function public.validate_booking_schedule_and_capacity();

commit;
