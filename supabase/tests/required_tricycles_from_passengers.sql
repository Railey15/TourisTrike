-- Run after 20261007025000. The transaction leaves no booking data behind.
begin;

do $$
declare
  v_rejected boolean;
begin
  if public.tricycle_passenger_capacity() <> 3
     or public.minimum_required_tricycles(1) <> 1
     or public.minimum_required_tricycles(3) <> 1
     or public.minimum_required_tricycles(4) <> 2
     or public.minimum_required_tricycles(6) <> 2
     or public.minimum_required_tricycles(7) <> 3 then
    raise exception 'CAPACITY_CALCULATION_FAILED';
  end if;

  create temporary table booking_capacity_probe (
    scheduled_start_at timestamptz,
    estimated_end_at timestamptz,
    travel_date date,
    adults integer,
    children integer,
    total_passengers integer,
    required_drivers integer
  );
  create trigger booking_capacity_probe_guard before insert or update
    on booking_capacity_probe for each row
    execute function public.validate_booking_schedule_and_capacity();

  insert into booking_capacity_probe values (
    '2026-10-08 01:00:00+00', '2026-10-08 03:00:00+00',
    '2026-10-08', 1, 0, 1, 1
  );
  v_rejected := false;
  begin
    insert into booking_capacity_probe values (
      '2026-10-08 01:00:00+00', '2026-10-08 03:00:00+00',
      '2026-10-08', 1, 0, 1, 10
    );
  exception when others then
    v_rejected := sqlerrm = 'TRICYCLE_COUNT_MUST_MATCH_PASSENGERS';
  end;
  if not v_rejected then raise exception 'EXTRA_TRICYCLES_ACCEPTED'; end if;

  v_rejected := false;
  begin
    insert into booking_capacity_probe values (
      '2026-10-08 01:00:00+00', '2026-10-08 03:00:00+00',
      '2026-10-08', 1, 0, 2, 1
    );
  exception when others then
    v_rejected := sqlerrm = 'INVALID_PASSENGER_COUNT';
  end;
  if not v_rejected then raise exception 'PASSENGER_MISMATCH_ACCEPTED'; end if;
end;
$$;

rollback;
