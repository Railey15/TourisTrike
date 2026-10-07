-- Run after 20261007050000. No persistent booking data is changed.
begin;

do $$
declare
  v_check text;
  v_rejected boolean;
begin
  select pg_get_constraintdef(c.oid) into v_check
  from pg_constraint c
  where c.conrelid = 'public.package_bookings'::regclass
    and c.conname = 'package_booking_additional_tricycle_request_check';
  if v_check is null then raise exception 'REQUEST_CHECK_MISSING'; end if;

  create temporary table additional_tricycle_probe as
  select additional_tricycle_count, additional_tricycle_reason,
         additional_tricycle_explanation
  from public.package_bookings where false;
  alter table additional_tricycle_probe
    alter column additional_tricycle_count set not null;
  execute 'alter table additional_tricycle_probe add constraint request_check '
    || v_check;

  insert into additional_tricycle_probe values (0, null, null);
  insert into additional_tricycle_probe values (1, 'extra_luggage', null);
  insert into additional_tricycle_probe values (2, 'accessibility_needs', null);
  insert into additional_tricycle_probe values (3, 'additional_space', null);
  insert into additional_tricycle_probe values (1, 'other', 'Large instrument case');

  create trigger request_immutable before update of
    additional_tricycle_count, additional_tricycle_reason,
    additional_tricycle_explanation on additional_tricycle_probe
    for each row execute function public.guard_additional_tricycle_request_update();
  v_rejected := false;
  begin
    update additional_tricycle_probe
    set additional_tricycle_count = 1,
        additional_tricycle_reason = 'extra_luggage'
    where additional_tricycle_count = 0;
  exception when others then
    v_rejected := sqlerrm = 'ADDITIONAL_TRICYCLE_REQUEST_IMMUTABLE';
  end;
  if not v_rejected then raise exception 'POST_BOOKING_EDIT_ACCEPTED'; end if;

  v_rejected := false;
  begin
    insert into additional_tricycle_probe values (-1, 'extra_luggage', null);
  exception when check_violation then v_rejected := true;
  end;
  if not v_rejected then raise exception 'NEGATIVE_EXTRA_ACCEPTED'; end if;

  v_rejected := false;
  begin
    insert into additional_tricycle_probe values (4, 'extra_luggage', null);
  exception when check_violation then v_rejected := true;
  end;
  if not v_rejected then raise exception 'MORE_THAN_THREE_EXTRAS_ACCEPTED'; end if;

  v_rejected := false;
  begin
    insert into additional_tricycle_probe values (0, 'extra_luggage', null);
  exception when check_violation then v_rejected := true;
  end;
  if not v_rejected then raise exception 'ZERO_WITH_REASON_ACCEPTED'; end if;

  v_rejected := false;
  begin
    insert into additional_tricycle_probe values (2, null, null);
  exception when check_violation then v_rejected := true;
  end;
  if not v_rejected then raise exception 'MISSING_REASON_ACCEPTED'; end if;

  v_rejected := false;
  begin
    insert into additional_tricycle_probe values (3, 'other', null);
  exception when check_violation then v_rejected := true;
  end;
  if not v_rejected then raise exception 'MISSING_OTHER_EXPLANATION_ACCEPTED'; end if;
end;
$$;

rollback;
