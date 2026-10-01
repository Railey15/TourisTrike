begin;

do $tests$
declare v_actual integer; v_text text;
begin
  -- One full configured interval is free; the first fee starts exactly at
  -- the threshold, followed by one charge per full interval.
  select public.tour_waiting_chargeable_intervals(0,15) into v_actual;
  if v_actual <> 0 then raise exception 'stay-end boundary failed'; end if;
  select public.tour_waiting_chargeable_intervals(899,15) into v_actual;
  if v_actual <> 0 then raise exception 'grace-minus-one boundary failed'; end if;
  select public.tour_waiting_chargeable_intervals(900,15) into v_actual;
  if v_actual <> 1 then raise exception 'grace threshold failed'; end if;
  select public.tour_waiting_chargeable_intervals(1800,15) into v_actual;
  if v_actual <> 2 then raise exception 'next interval failed'; end if;
  select public.tour_waiting_chargeable_intervals(3600,15) into v_actual;
  if v_actual <> 4 then raise exception 'multiple intervals failed'; end if;
  select public.tour_waiting_chargeable_intervals(1199,20) into v_actual;
  if v_actual <> 0 then raise exception 'custom interval grace failed'; end if;
  select public.tour_waiting_chargeable_intervals(1200,20) into v_actual;
  if v_actual <> 1 then raise exception 'custom interval threshold failed'; end if;

  select public.censor_chat_text('F.u.c.k this, but not Scunthorpe. https://example.com/fuck')
    into v_text;
  if v_text <> '**** this, but not Scunthorpe. https://example.com/fuck' then
    raise exception 'profanity boundary or URL protection failed: %',v_text;
  end if;
  select public.censor_chat_text('That is SHIT!') into v_text;
  if v_text <> 'That is ****!' then raise exception 'case-insensitive censorship failed'; end if;
  if not exists(select 1 from pg_trigger where tgname='guard_booked_endpoints'
      and not tgisinternal) then raise exception 'endpoint guard missing'; end if;
  if not exists(select 1 from pg_trigger where tgname='censor_user_message'
      and not tgisinternal) then raise exception 'message guard missing'; end if;
end $tests$;

create temp table pickup_hours_test (scheduled_start_at timestamptz);
create trigger guard_hours before insert on pickup_hours_test
for each row execute function public.guard_tour_pickup_hours();
insert into pickup_hours_test values
  ('2026-10-01 05:00:00+08'),('2026-10-01 16:59:00+08');
do $hours$
begin
  begin
    insert into pickup_hours_test values ('2026-10-01 04:59:00+08');
    raise exception 'early pickup accepted';
  exception when raise_exception then
    if sqlerrm <> 'PICKUP_OUTSIDE_ALLOWED_HOURS' then raise; end if;
  end;
  begin
    insert into pickup_hours_test values ('2026-10-01 17:00:00+08');
    raise exception 'late pickup accepted';
  exception when raise_exception then
    if sqlerrm <> 'PICKUP_OUTSIDE_ALLOWED_HOURS' then raise; end if;
  end;
end $hours$;

rollback;
