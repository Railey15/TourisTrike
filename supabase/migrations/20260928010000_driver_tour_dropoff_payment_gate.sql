-- Separate final-stop departure from deliberate drop-off navigation. Keep all
-- amounts, payment collection, waiting calculations, and historical rows intact.
begin;

create or replace function public.is_booking_dropoff_payment_satisfied(p_booking_id uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare b public.package_bookings;
begin
  select * into b from public.package_bookings where id=p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  -- A historical confirmed receipt must never cover a newer net obligation.
  if coalesce(b.remaining_balance,0) > 0 then return false; end if;
  return not exists (
    select 1 from public.booking_payment_requirements r
    where r.booking_id=b.id and r.payment_stage='remaining_balance' and r.amount>0
      and not (
        r.status='waived' or (
          r.status='satisfied' and exists (
            select 1 from public.payment_records p
            where p.id=r.satisfied_by_payment_record_id and p.booking_id=b.id
              and p.payment_stage='remaining_balance' and p.status='confirmed'
              and p.amount>=r.amount
          )
        )
      )
  );
end $$;
revoke all on function public.is_booking_dropoff_payment_satisfied(uuid) from public,anon,authenticated;

create or replace function public.get_driver_tour_payment_gate(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare b public.package_bookings; s jsonb;
begin
  select * into b from public.package_bookings where id=p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if auth.uid() is null or not public.can_read_tour_booking(b.id) then
    raise exception 'BOOKING_ACCESS_DENIED' using errcode='42501';
  end if;
  s := public.get_booking_waiting_summary(b.id);
  return jsonb_build_object(
    'booking_id',b.id,
    'package_remaining',s->'package_remaining',
    'finalized_waiting',s->'finalized_waiting',
    -- Drop-off only evaluates finalized obligations, never live preview debt.
    'total_remaining',greatest(0,coalesce(b.remaining_balance,0)),
    'payment_satisfied',public.is_booking_dropoff_payment_satisfied(b.id)
  );
end $$;
revoke all on function public.get_driver_tour_payment_gate(uuid) from public,anon;
grant execute on function public.get_driver_tour_payment_gate(uuid) to authenticated;

create or replace function public.guard_driver_dropoff_payment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.journey_state in ('en_route_dropoff','completed')
    and (tg_op='INSERT' or new.journey_state is distinct from old.journey_state) then
    -- Serialize with the existing journey and collection RPC booking locks.
    perform 1 from public.package_bookings where id=new.booking_id for update;
    if exists (select 1 from public.booking_itinerary_items i
      where i.booking_id=new.booking_id and
        (lower(coalesce(i.spot_status,'pending')) <> 'completed' or i.actual_departure_time is null)) then
      raise exception 'ITINERARY_NOT_FINALIZED';
    end if;
    if not public.is_booking_dropoff_payment_satisfied(new.booking_id) then
      raise exception 'REMAINING_BALANCE_NOT_CONFIRMED';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.guard_driver_dropoff_payment() from public,anon,authenticated;
create trigger trg_guard_driver_dropoff_payment
before insert or update of journey_state on public.booking_drivers
for each row execute function public.guard_driver_dropoff_payment();

create or replace function public.advance_driver_tour_action(
  p_booking_id uuid,p_expected_state text,p_stop_index integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d public.booking_drivers; v_activity uuid; v_item uuid;
  v_count integer; v_result jsonb; v_target text;
begin
  if auth.uid() is null or public.current_profile_role() is distinct from 'driver' then
    raise exception 'DRIVER_ROLE_REQUIRED'; end if;
  perform 1 from public.package_bookings where id=p_booking_id for update;
  select * into d from public.booking_drivers where booking_id=p_booking_id
    and driver_id=auth.uid() and status in ('accepted','completed') for update;
  if not found then raise exception 'NOT_ASSIGNED_DRIVER'; end if;
  if d.journey_state is distinct from p_expected_state or d.current_stop_index is distinct from p_stop_index then
    return jsonb_build_object('no_op',true,'journey_state',d.journey_state,
      'current_stop_index',d.current_stop_index);
  end if;
  select id into v_activity from public.package_activities where booking_id=p_booking_id limit 1;
  perform set_config('touristrike.driver_slide','true',true);
  if d.journey_state='at_pickup' then
    v_result := public.advance_driver_journey_state(p_booking_id,'boarded');
  elsif d.journey_state='boarded' then
    select count(*) into v_count from public.booking_itinerary_items where booking_id=p_booking_id;
    v_result := public.advance_driver_journey_state(p_booking_id,
      case when v_count>0 then 'en_route_stop' else 'en_route_dropoff' end);
  elsif d.journey_state in ('at_stop','stop_done') then
    select id into v_item from public.booking_itinerary_items where booking_id=p_booking_id
      order by coalesce(order_number,2147483647),coalesce(destination_order,2147483647),
        arrival_time nulls last,created_at,id offset d.current_stop_index limit 1;
    if v_item is null then raise exception 'ITINERARY_ITEM_NOT_FOUND'; end if;
    if d.journey_state='at_stop' then
      v_result := public.complete_current_itinerary_item(v_activity,v_item,null);
    end if;
    update public.booking_driver_arrivals
      set departed_at=coalesce(departed_at,clock_timestamp())
      where booking_driver_id=d.id and itinerary_item_id=v_item;
    -- Finalize the shared stop when every required driver has slid. This must
    -- precede the remaining-payment gate on the final navigation leg.
    update public.booking_itinerary_items i
      set actual_departure_time=(select max(a.departed_at)
        from public.booking_driver_arrivals a where a.itinerary_item_id=v_item)
      where i.id=v_item and i.spot_status='completed'
        and i.actual_departure_time is null;
    select count(*) into v_count from public.booking_itinerary_items where booking_id=p_booking_id;
    -- Leaving the final destination is its own idempotent action. Persist the
    -- final departure/waiting ledger even while payment remains outstanding.
    if p_expected_state='at_stop' and d.current_stop_index+1>=v_count then
      return jsonb_build_object('success',true,'journey_state','stop_done',
        'current_stop_index',d.current_stop_index,'final_stop_finalized',
          (select i.spot_status='completed' and i.actual_departure_time is not null
            from public.booking_itinerary_items i where i.id=v_item),
        'payment_required',not public.is_booking_dropoff_payment_satisfied(p_booking_id));
    end if;
    select journey_state into d.journey_state from public.booking_drivers where id=d.id;
    if d.journey_state='stop_done' then
      select count(*) into v_count from public.booking_itinerary_items where booking_id=p_booking_id;
      v_target := case when d.current_stop_index+1<v_count then 'en_route_stop'
        else 'en_route_dropoff' end;
      begin
        v_result := public.advance_driver_journey_state(p_booking_id,v_target);
      exception when raise_exception then
        if sqlerrm like '%BARRIER_NOT_MET%' or sqlerrm like '%REMAINING_BALANCE_NOT_CONFIRMED%' then
          return jsonb_build_object('success',true,'waiting_for_convoy_or_payment',true,
            'journey_state','stop_done','current_stop_index',d.current_stop_index);
        end if;
        raise;
      end;
    end if;
  elsif d.journey_state='at_dropoff' then
    v_result := public.advance_driver_journey_state(p_booking_id,'completed');
  else
    raise exception 'SLIDE_NOT_AVAILABLE_IN_STATE: %',d.journey_state;
  end if;
  return v_result;
end $$;
revoke all on function public.advance_driver_tour_action(uuid,text,integer) from public,anon;
grant execute on function public.advance_driver_tour_action(uuid,text,integer) to authenticated;

notify pgrst, 'reload schema';
commit;
