-- Booking feedback is one atomic session. Driver state remains authoritative.
begin;

create or replace function public.tourist_has_reviewed_booking(p_booking_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.package_bookings pb
    where pb.id = p_booking_id and pb.tourist_id = auth.uid()
      and lower(coalesce(pb.booking_status, pb.status)) in ('completed', 'done')
  ) and exists (
    select 1 from public.package_reviews pr
    where pr.booking_id = p_booking_id and pr.tourist_id = auth.uid()
  ) and exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = p_booking_id and bd.status = 'completed'
  ) and not exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = p_booking_id and bd.status = 'completed'
      and not exists (
        select 1 from public.driver_reviews dr
        where dr.booking_id = bd.booking_id and dr.driver_id = bd.driver_id
          and dr.tourist_id = auth.uid()
      )
  );
$$;

create or replace function public.get_booking_feedback(p_booking_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_booking public.package_bookings;
begin
  select * into v_booking from public.package_bookings where id = p_booking_id;
  if auth.uid() is null or not found or not (
    v_booking.tourist_id = auth.uid() or exists (
      select 1 from public.booking_drivers where booking_id = p_booking_id
        and driver_id = auth.uid() and status in ('accepted', 'completed')
    )
  ) then
    raise exception 'NOT_BOOKING_PARTICIPANT';
  end if;
  return jsonb_build_object(
    'booking_id', p_booking_id, 'tourist_id', v_booking.tourist_id,
    'package_name', (select title from public.tour_packages where id = v_booking.package_id),
    'can_review', auth.uid() = v_booking.tourist_id
      and lower(coalesce(v_booking.booking_status, v_booking.status)) in ('completed', 'done'),
    'package_review', (select to_jsonb(pr) from public.package_reviews pr
      where pr.booking_id = p_booking_id and pr.tourist_id = v_booking.tourist_id),
    'drivers', coalesce((select jsonb_agg(jsonb_build_object(
      'driver_id', bd.driver_id,
      'name', coalesce(nullif(p.full_name, ''), concat_ws(' ', p.first_name, p.last_name)),
      'avatar_url', p.profile_image_url,
      'review', (select to_jsonb(dr) from public.driver_reviews dr
        where dr.booking_id = p_booking_id and dr.driver_id = bd.driver_id
          and dr.tourist_id = v_booking.tourist_id)
    ) order by bd.accepted_at, bd.id)
      from public.booking_drivers bd join public.profiles p on p.id = bd.driver_id
      where bd.booking_id = p_booking_id and bd.status = 'completed'), '[]'::jsonb)
  );
end;
$$;

-- The existing booking/tourist and booking/driver/tourist unique indexes are
-- reused. DO NOTHING preserves an already submitted review on network retries.
create or replace function public.submit_booking_feedback(
  p_booking_id uuid, p_package_rating integer default null,
  p_package_comment text default '', p_driver_reviews jsonb default '[]'::jsonb
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_booking public.package_bookings; v_review jsonb; v_driver uuid;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  select * into v_booking from public.package_bookings where id = p_booking_id for update;
  if not found or v_booking.tourist_id <> auth.uid() then raise exception 'NOT_BOOKING_OWNER'; end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status)) not in ('completed', 'done') then
    raise exception 'BOOKING_NOT_COMPLETED';
  end if;
  if public.tourist_has_reviewed_booking(p_booking_id) then
    return public.get_booking_feedback(p_booking_id);
  end if;
  if jsonb_typeof(p_driver_reviews) <> 'array' then raise exception 'INVALID_DRIVER_REVIEWS'; end if;
  if not exists (select 1 from public.package_reviews where booking_id = p_booking_id and tourist_id = auth.uid()) then
    if p_package_rating is null or p_package_rating not between 1 and 5 or length(p_package_comment) > 2000 then
      raise exception 'INVALID_PACKAGE_REVIEW';
    end if;
    insert into public.package_reviews(booking_id, tourist_id, package_id, rating, review_text)
    values (p_booking_id, auth.uid(), v_booking.package_id, p_package_rating, nullif(trim(p_package_comment), ''))
    on conflict (booking_id, tourist_id) do nothing;
  end if;
  for v_review in select value from jsonb_array_elements(p_driver_reviews) loop
    v_driver := (v_review->>'driver_id')::uuid;
    if v_driver is null or not exists (select 1 from public.booking_drivers
      where booking_id = p_booking_id and driver_id = v_driver and status = 'completed') then
      raise exception 'INVALID_REVIEW_DRIVER';
    end if;
    if (v_review->>'rating') is null or (v_review->>'rating')::integer not between 1 and 5
       or length(coalesce(v_review->>'review_text', '')) > 2000 then raise exception 'INVALID_DRIVER_RATING'; end if;
    insert into public.driver_reviews(booking_id, driver_id, tourist_id, rating, review_text)
    values (p_booking_id, v_driver, auth.uid(), (v_review->>'rating')::integer, nullif(trim(v_review->>'review_text'), ''))
    on conflict (booking_id, driver_id, tourist_id) do nothing;
  end loop;
  if not public.tourist_has_reviewed_booking(p_booking_id) then raise exception 'INCOMPLETE_BOOKING_FEEDBACK'; end if;
  return public.get_booking_feedback(p_booking_id);
end;
$$;

create or replace function public.get_driver_home_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_driver uuid := auth.uid(); v_start timestamptz;
begin
  if v_driver is null or public.current_profile_role() is distinct from 'driver' then raise exception 'DRIVER_ROLE_REQUIRED'; end if;
  v_start := date_trunc('day', now() at time zone 'Asia/Manila') at time zone 'Asia/Manila';
  return jsonb_build_object(
    'completed_tours', (select count(*) from public.booking_drivers where driver_id = v_driver and status = 'completed'),
    'today_trips', (select count(*) from public.booking_drivers where driver_id = v_driver and status = 'completed'
      and completed_at >= v_start and completed_at < v_start + interval '1 day'),
    'active_trips', (select count(*) from public.booking_drivers bd join public.package_bookings pb on pb.id = bd.booking_id
      where bd.driver_id = v_driver and bd.status = 'accepted' and pb.status not in ('completed', 'cancelled', 'rejected')
        and (pb.scheduled_start_at <= now() or bd.journey_state <> 'assigned')),
    'upcoming_trips', (select count(*) from public.booking_drivers bd join public.package_bookings pb on pb.id = bd.booking_id
      where bd.driver_id = v_driver and bd.status = 'accepted' and pb.status not in ('completed', 'cancelled', 'rejected')
        and pb.scheduled_start_at > now() and bd.journey_state = 'assigned'),
    'average_rating', (select coalesce(round(avg(rating), 2), 0) from public.driver_reviews where driver_id = v_driver and rating between 1 and 5),
    'review_count', (select count(*) from public.driver_reviews where driver_id = v_driver and rating between 1 and 5),
    'recent_reviews', coalesce((select jsonb_agg(r order by r.created_at desc) from (
      select booking_id, rating, review_text, created_at from public.driver_reviews
      where driver_id = v_driver and rating between 1 and 5 order by created_at desc limit 5
    ) r), '[]'::jsonb),
    'today_earnings', (select coalesce(sum(pa.driver_amount), 0) from public.payment_allocations pa
      join public.payment_records pr on pr.id = pa.payment_record_id
      where pa.driver_id = v_driver and pr.status = 'confirmed' and pa.status not in ('cancelled', 'manual_review')
        and coalesce(pr.paid_at, pa.paid_at) >= v_start and coalesce(pr.paid_at, pa.paid_at) < v_start + interval '1 day'),
    'assignments', coalesce((select jsonb_agg(a order by a.scheduled_start_at) from (
      select bd.booking_id, bd.journey_state, pb.scheduled_start_at, tp.title,
        (select id from public.package_activities where booking_id = pb.id limit 1) as activity_id
      from public.booking_drivers bd join public.package_bookings pb on pb.id = bd.booking_id
      join public.tour_packages tp on tp.id = pb.package_id
      where bd.driver_id = v_driver and bd.status = 'accepted' and pb.status not in ('completed', 'cancelled', 'rejected')
      order by pb.scheduled_start_at limit 10
    ) a), '[]'::jsonb)
  );
end;
$$;

-- Keep actual per-driver departures beside the existing per-driver arrivals.
alter table public.booking_driver_arrivals add column if not exists departed_at timestamptz;

create or replace function public.persist_driver_stop_milestones()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_item uuid;
begin
  if new.journey_state is not distinct from old.journey_state then return new; end if;
  if new.journey_state = 'at_stop' or (old.journey_state = 'stop_done' and new.journey_state in ('en_route_stop', 'en_route_dropoff')) then
    select id into v_item from public.booking_itinerary_items
    where booking_id = new.booking_id
    order by coalesce(order_number, 2147483647), coalesce(destination_order, 2147483647), arrival_time nulls last, created_at, id
    offset (case when new.journey_state = 'at_stop' then new.current_stop_index else old.current_stop_index end) limit 1;
    if v_item is null then raise exception 'ITINERARY_ITEM_NOT_FOUND'; end if;
    if new.journey_state = 'at_stop' then
      insert into public.booking_driver_arrivals(booking_driver_id, itinerary_item_id, arrived_at, latitude, longitude)
      select new.id, v_item, new.state_updated_at, dll.latitude, dll.longitude
      from (select 1) seed left join public.driver_live_locations dll on dll.driver_id = new.driver_id
      on conflict do nothing;
      update public.booking_itinerary_items set actual_arrival_time = coalesce(actual_arrival_time, new.state_updated_at),
        spot_status = case when spot_status = 'completed' then spot_status else 'at_spot' end where id = v_item;
      -- Preserve the existing arrival notification and its deduplication key.
      insert into public.notifications(user_id, title, body, type, is_read, dedupe_key)
      select recipient.user_id, 'Destination arrival',
        'Arrived at ' || bii.destination_name, 'itinerary_arrival', false,
        'arrival:' || new.id::text || ':' || v_item::text || ':' || recipient.user_id::text
      from public.booking_itinerary_items bii
      join public.package_bookings pb on pb.id = bii.booking_id
      cross join lateral (
        select pb.tourist_id as user_id
        union
        select bd.driver_id from public.booking_drivers bd
        where bd.booking_id = pb.id and bd.status = 'accepted'
      ) recipient
      where bii.id = v_item
      on conflict (dedupe_key) where dedupe_key is not null do nothing;
    else
      update public.booking_driver_arrivals set departed_at = coalesce(departed_at, new.state_updated_at)
      where booking_driver_id = new.id and itinerary_item_id = v_item;
      update public.booking_itinerary_items set actual_departure_time = new.state_updated_at where id = v_item;
    end if;
  end if;
  return new;
end;
$$;
create trigger trg_persist_driver_stop_milestones after update of journey_state on public.booking_drivers
for each row execute function public.persist_driver_stop_milestones();

revoke all on function public.get_booking_feedback(uuid), public.submit_booking_feedback(uuid, integer, text, jsonb),
  public.get_driver_home_overview() from public, anon;
grant execute on function public.get_booking_feedback(uuid), public.submit_booking_feedback(uuid, integer, text, jsonb),
  public.get_driver_home_overview() to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'package_reviews') then
    alter publication supabase_realtime add table public.package_reviews;
  end if;
end;
$$;

create or replace function public.complete_current_itinerary_item(
  p_activity_id uuid,
  p_itinerary_item_id uuid,
  p_remaining_payment_method text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_activity public.package_activities;
  v_booking public.package_bookings;
  v_assignment public.booking_drivers;
  v_item public.booking_itinerary_items;
  v_item_index integer;
  v_total_items integer := 0;
  v_completed_items integer := 0;
  v_stage_progress jsonb;
  v_latest_arrival timestamptz;
  v_is_test_booking boolean := false;
  v_remaining_payment_satisfied boolean := false;
  v_spot_status_list jsonb := '[]'::jsonb;
begin
  if v_driver_id is null then raise exception 'UNAUTHENTICATED'; end if;

  select * into v_activity
  from public.package_activities
  where id = p_activity_id;
  if not found then raise exception 'ACTIVITY_NOT_FOUND'; end if;

  select * into v_booking
  from public.package_bookings
  where id = v_activity.booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  v_is_test_booking := public.is_developer_test_booking(v_booking.id);
  if lower(coalesce(v_booking.booking_status, v_booking.status)) in ('cancelled', 'rejected', 'expired') then
    raise exception 'BOOKING_CLOSED';
  end if;

  select * into v_assignment
  from public.booking_drivers bd
  where bd.booking_id = v_booking.id
    and bd.driver_id = v_driver_id
    and bd.status in ('accepted', 'completed')
  for update;
  if not found then raise exception 'NOT_ASSIGNED_DRIVER'; end if;

  if p_itinerary_item_id is null then
    select item.* into v_item
    from public.booking_itinerary_items item
    where item.booking_id = v_booking.id
      and lower(coalesce(item.spot_status, 'pending')) <> 'completed'
    order by coalesce(item.order_number, 2147483647),
             coalesce(item.destination_order, 2147483647),
             item.arrival_time nulls last, item.created_at, item.id
    limit 1
    for update;
  else
    select item.* into v_item
    from public.booking_itinerary_items item
    where item.id = p_itinerary_item_id
      and item.booking_id = v_booking.id
    for update;
  end if;
  if not found then raise exception 'ITINERARY_ITEM_NOT_FOUND'; end if;

  select ordered.item_index into v_item_index
  from (
    select bii.id,
           (row_number() over (
             order by coalesce(bii.order_number, 2147483647),
                      coalesce(bii.destination_order, 2147483647),
                      bii.arrival_time nulls last, bii.created_at, bii.id
           ))::integer - 1 as item_index
    from public.booking_itinerary_items bii
    where bii.booking_id = v_booking.id
  ) ordered
  where ordered.id = v_item.id;

  select count(*) into v_total_items
  from public.booking_itinerary_items
  where booking_id = v_booking.id;

  if lower(coalesce(v_item.spot_status, 'pending')) = 'completed' then
    select count(*) into v_completed_items
    from public.booking_itinerary_items
    where booking_id = v_booking.id
      and lower(coalesce(spot_status, 'pending')) = 'completed';

    return jsonb_build_object(
      'success', true,
      'already_completed', true,
      'booking_id', v_booking.id,
      'activity_id', v_activity.id,
      'current_itinerary_item_id', v_item.id,
      'current_spot_index', v_item_index,
      'completed_items', v_completed_items,
      'total_items', v_total_items,
      'tour_completed', v_completed_items = v_total_items,
      'convoy_progress', public.compute_convoy_stage_progress(
        v_booking.id, 'stop_done', v_item_index
      )
    );
  end if;

  if v_assignment.journey_state = 'stop_done' and v_assignment.current_stop_index = v_item_index then
    return jsonb_build_object('success', true, 'driver_ready', true, 'already_completed', false);
  end if;
  if v_assignment.journey_state <> 'at_stop' then
    raise exception 'INVALID_TRANSITION: % -> stop_done', v_assignment.journey_state;
  end if;

  if v_assignment.current_stop_index <> v_item_index then
    raise exception 'STALE_ITINERARY_STOP';
  end if;

  select arrived_at into v_latest_arrival from public.booking_driver_arrivals
  where booking_driver_id = v_assignment.id and itinerary_item_id = v_item.id;
  if v_latest_arrival is null then raise exception 'DRIVER_ARRIVAL_NOT_RECORDED'; end if;

  if not v_is_test_booking
     and coalesce(v_item.estimated_stay_duration_minutes, 0) > 0
     and now() < v_latest_arrival
       + make_interval(mins => v_item.estimated_stay_duration_minutes) then
    raise exception 'STOP_DWELL_TIME_NOT_MET';
  end if;

  -- Each driver's ready confirmation changes only that assignment.
  update public.booking_drivers set journey_state = 'stop_done', state_updated_at = now()
  where id = v_assignment.id;
  insert into public.trip_status_logs(activity_id, booking_id, driver_id, status,
    previous_state, new_state, spot_index, logged_at, notes)
  values (v_activity.id, v_booking.id, v_driver_id, 'on_tour', 'at_stop', 'stop_done',
    v_item_index, now(), 'Driver confirmed passengers ready after actual stay');
  v_stage_progress := public.compute_convoy_stage_progress(v_booking.id, 'stop_done', v_item_index);
  if not coalesce((v_stage_progress->>'all_satisfied')::boolean, false) then
    return jsonb_build_object('success', true, 'driver_ready', true, 'already_completed', false,
      'convoy_progress', v_stage_progress, 'total_items', v_total_items);
  end if;
  -- The shared stop is complete only after every required driver is ready.
  update public.booking_itinerary_items set spot_status = 'completed', updated_at = now()
  where id = v_item.id;

  select count(*) into v_completed_items
  from public.booking_itinerary_items
  where booking_id = v_booking.id
    and lower(coalesce(spot_status, 'pending')) = 'completed';

  v_remaining_payment_satisfied :=
    public.is_booking_remaining_payment_satisfied(v_booking.id);

  perform set_config('touristrike.validated_transition', 'true', true);
  update public.package_activities
  set status = 'ongoing',
      tour_status = case
        when v_completed_items = v_total_items
             and not v_remaining_payment_satisfied
          then 'awaiting_remaining_payment'
        else 'on_tour'
      end,
      current_spot_index = v_item_index, updated_at = now()
  where id = v_activity.id;
  update public.package_bookings
  set booking_status = case
        when v_completed_items = v_total_items
             and not v_remaining_payment_satisfied
          then 'awaiting_remaining_payment'
        else 'on_tour'
      end,
      current_spot_index = v_item_index,
      updated_at = now()
  where id = v_booking.id;

  select coalesce(jsonb_agg(
    jsonb_build_object('id', id, 'order_number', order_number,
      'destination_order', destination_order, 'spot_status', spot_status)
    order by coalesce(order_number, 2147483647),
      coalesce(destination_order, 2147483647), arrival_time nulls last,
      created_at, id
  ), '[]'::jsonb)
  into v_spot_status_list
  from public.booking_itinerary_items
  where booking_id = v_booking.id;

  return jsonb_build_object(
    'success', true,
    'already_completed', false,
    'booking_id', v_booking.id,
    'activity_id', v_activity.id,
    'current_itinerary_item_id', v_item.id,
    'current_spot_index', v_item_index,
    'completed_items', v_completed_items,
    'total_items', v_total_items,
    'tour_completed', v_completed_items = v_total_items,
    'awaiting_remaining_payment', v_completed_items = v_total_items
      and not v_remaining_payment_satisfied,
    'convoy_state', 'stop_done',
    'convoy_progress', public.compute_convoy_stage_progress(
      v_booking.id, 'stop_done', v_item_index
    ),
    'spot_status_list', v_spot_status_list
  );
end;
$$;

create or replace function public.advance_driver_journey_state(
  p_booking_id uuid,
  p_target_state text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_booking public.package_bookings;
  v_current text;
  v_stop_index integer;
  v_is_gated boolean := false;
  v_new_stop_index integer;
  v_all_cleared boolean;
  v_slowest_state text;
  v_legacy_status text;
  v_activity_id uuid;
  v_accepted_count integer;
  v_total_items integer;
  v_completed_items integer;
  v_is_test_booking boolean := false;
  v_debug_bypass boolean := false;
  v_finalization jsonb;
  v_stage_progress jsonb;
begin
  if v_driver_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if public.journey_state_order(p_target_state) is null then
    raise exception 'INVALID_STATE: %', p_target_state;
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
     in ('cancelled', 'rejected') then
    raise exception 'CANCELLED_BOOKING_CANNOT_ADVANCE';
  end if;

  v_is_test_booking := public.is_developer_test_booking(p_booking_id);
  v_debug_bypass := v_is_test_booking and coalesce(
    current_setting('touristrike.debug_progression_bypass', true), ''
  ) = 'true';

  select journey_state, current_stop_index into v_current, v_stop_index
  from public.booking_drivers
  where booking_id = p_booking_id
    and driver_id = v_driver_id
    and status in ('accepted', 'completed')
  for update;
  if not found then raise exception 'NOT_IN_CONVOY'; end if;

  if v_current = p_target_state then
    v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);
    return jsonb_build_object(
      'success', true, 'no_op', true,
      'journey_state', v_current, 'current_stop_index', v_stop_index,
      'overall_completed', coalesce((v_finalization->>'overall_completed')::boolean, false),
      'awaiting_final_payment', coalesce((v_finalization->>'awaiting_final_payment')::boolean, false)
    );
  end if;

  if v_current = 'completed' then
    v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);
    return jsonb_build_object(
      'success', true, 'no_op', true,
      'journey_state', v_current, 'current_stop_index', v_stop_index,
      'assignment_completed', true,
      'overall_completed', coalesce((v_finalization->>'overall_completed')::boolean, false),
      'awaiting_final_payment', coalesce((v_finalization->>'awaiting_final_payment')::boolean, false)
    );
  end if;

  v_new_stop_index := v_stop_index;
  if v_current = 'assigned' and p_target_state = 'en_route_pickup' then
    v_is_gated := false;
  elsif v_current = 'en_route_pickup' and p_target_state = 'at_pickup' then
    v_is_gated := false;
  elsif v_current = 'at_pickup' and p_target_state = 'boarded' then
    v_is_gated := false;
  elsif v_current = 'boarded' and p_target_state in ('en_route_stop', 'en_route_dropoff') then
    v_is_gated := true;
    if p_target_state = 'en_route_stop' then v_new_stop_index := 0; end if;
  elsif v_current = 'en_route_stop' and p_target_state = 'at_stop' then
    v_is_gated := false;
  elsif v_current = 'stop_done' and p_target_state in ('en_route_stop', 'en_route_dropoff') then
    v_is_gated := true;
    if p_target_state = 'en_route_stop' then v_new_stop_index := v_stop_index + 1; end if;
  elsif v_current = 'en_route_dropoff' and p_target_state = 'at_dropoff' then
    v_is_gated := false;
  elsif v_current = 'at_dropoff' and p_target_state = 'completed' then
    v_is_gated := false;
  else
    if public.journey_state_order(v_current)
       > public.journey_state_order(p_target_state) then
      v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);
      return jsonb_build_object(
        'success', true, 'no_op', true, 'already_progressed', true,
        'journey_state', v_current, 'current_stop_index', v_stop_index,
        'overall_completed', coalesce((v_finalization->>'overall_completed')::boolean, false),
        'awaiting_final_payment', coalesce((v_finalization->>'awaiting_final_payment')::boolean, false)
      );
    end if;
    raise exception 'INVALID_TRANSITION: % -> %', v_current, p_target_state;
  end if;

  if p_target_state = 'en_route_stop' then
    select count(*) into v_total_items from public.booking_itinerary_items where booking_id = p_booking_id;
    if v_new_stop_index < 0 or v_new_stop_index >= v_total_items then
      raise exception 'ITINERARY_STOP_OUT_OF_RANGE';
    end if;
  end if;

  if v_current = 'assigned' and p_target_state = 'en_route_pickup' then
    select count(*) into v_accepted_count
    from public.booking_drivers
    where booking_id = p_booking_id and status in ('accepted', 'completed');
    if v_accepted_count < greatest(coalesce(v_booking.required_drivers, 1), 1) then
      raise exception 'DRIVER_SLOTS_NOT_FILLED';
    end if;
    if not v_debug_bypass
       and now() < lower(public.package_booking_schedule_window(v_booking)) then
      raise exception 'BOOKING_START_TOO_EARLY';
    end if;
    if not v_debug_bypass
       and not public.is_booking_downpayment_confirmed(p_booking_id) then
      raise exception 'DOWNPAYMENT_NOT_CONFIRMED';
    end if;
  end if;

  if v_current = 'at_dropoff' and p_target_state = 'completed' then
    select count(*), count(*) filter (
      where lower(coalesce(spot_status, 'pending')) = 'completed'
    ) into v_total_items, v_completed_items
    from public.booking_itinerary_items
    where booking_id = p_booking_id;
    if v_total_items = 0 or v_completed_items < v_total_items then
      raise exception 'INCOMPLETE_ITINERARY';
    end if;
  end if;

  -- Payment is a server-enforced precondition of the final navigation leg.
  -- Only the allowlisted debug RPC can bypass this payment check.
  if p_target_state = 'en_route_dropoff' then
    select count(*), count(*) filter (
      where lower(coalesce(spot_status, 'pending')) = 'completed'
    ) into v_total_items, v_completed_items
    from public.booking_itinerary_items
    where booking_id = p_booking_id;
    if v_total_items = 0 or v_completed_items < v_total_items then
      raise exception 'INCOMPLETE_ITINERARY';
    end if;
    if not v_debug_bypass and not public.is_booking_remaining_payment_satisfied(p_booking_id) then
      raise exception 'REMAINING_BALANCE_NOT_CONFIRMED';
    end if;
  end if;

  if v_is_gated and not v_debug_bypass then
    if v_current = 'boarded' then
      v_stage_progress := public.compute_convoy_stage_progress(
        p_booking_id, 'boarded', null
      );
    elsif v_current = 'stop_done' then
      v_stage_progress := public.compute_convoy_stage_progress(
        p_booking_id, 'stop_done', v_stop_index
      );
    elsif v_current = 'at_dropoff' then
      v_stage_progress := public.compute_convoy_stage_progress(
        p_booking_id, 'at_dropoff', null
      );
    end if;
    v_all_cleared := coalesce(
      (v_stage_progress->>'all_satisfied')::boolean, false
    );
    if not coalesce(v_all_cleared, false) then raise exception 'BARRIER_NOT_MET'; end if;
  end if;

  update public.booking_drivers
  set journey_state = p_target_state,
      current_stop_index = v_new_stop_index,
      state_updated_at = now(),
      status = case when p_target_state = 'completed' then 'completed' else status end,
      completed_at = case when p_target_state = 'completed'
        then coalesce(completed_at, now()) else completed_at end
  where booking_id = p_booking_id and driver_id = v_driver_id;

  select (array_agg(journey_state
    order by public.journey_state_order(journey_state), current_stop_index))[1]
  into v_slowest_state
  from public.booking_drivers
  where booking_id = p_booking_id and status in ('accepted', 'completed');

  v_legacy_status := case v_slowest_state
    when 'assigned' then 'driver_accepted'
    when 'en_route_pickup' then 'driver_en_route'
    when 'at_pickup' then 'driver_arrived'
    when 'boarded' then 'picked_up'
    when 'en_route_stop' then 'en_route_to_spot'
    when 'at_stop' then 'at_spot'
    when 'stop_done' then 'on_tour'
    when 'en_route_dropoff' then 'en_route_to_dropoff'
    when 'at_dropoff' then 'ready_to_complete'
    when 'completed' then 'ready_to_complete'
    else 'driver_accepted'
  end;

  select id into v_activity_id
  from public.package_activities where booking_id = p_booking_id limit 1;

  perform set_config('touristrike.validated_transition', 'true', true);
  if v_activity_id is not null then
    update public.package_activities
    set tour_status = v_legacy_status,
        status = case when v_legacy_status = 'driver_accepted'
          then 'accepted' else 'ongoing' end,
        current_spot_index = greatest(v_new_stop_index, current_spot_index),
        dropped_off_at = case when p_target_state = 'completed'
          then coalesce(dropped_off_at, now()) else dropped_off_at end,
        updated_at = now()
    where id = v_activity_id;

    insert into public.trip_status_logs(
      activity_id, booking_id, driver_id, status, previous_state, new_state,
      spot_index, logged_at, notes
    ) values (
      v_activity_id, p_booking_id, v_driver_id,
      case when p_target_state = 'completed' then 'assignment_completed'
           else v_legacy_status end,
      v_current, p_target_state, v_new_stop_index, now(),
      case when v_debug_bypass
        then 'Developer test booking journey transition; operational validations bypassed'
        else 'Server-validated journey transition' end
    );
  end if;

  update public.package_bookings
  set booking_status = case
        when v_legacy_status in ('driver_accepted', 'driver_en_route', 'driver_arrived')
          then 'driver_on_the_way'
        else 'on_tour'
      end,
      current_spot_index = greatest(v_new_stop_index, current_spot_index),
      updated_at = now()
  where id = p_booking_id;

  v_finalization := public.finalize_package_booking_if_eligible(p_booking_id);

  return jsonb_build_object(
    'success', true, 'no_op', false,
    'journey_state', p_target_state,
    'current_stop_index', v_new_stop_index,
    'legacy_tour_status', v_legacy_status,
    'assignment_completed', p_target_state = 'completed',
    'convoy_progress', case
      when p_target_state = 'boarded' then public.compute_convoy_stage_progress(
        p_booking_id, 'boarded', null
      )
      when p_target_state = 'stop_done' then public.compute_convoy_stage_progress(
        p_booking_id, 'stop_done', v_new_stop_index
      )
      when p_target_state in ('at_dropoff', 'completed') then
        public.compute_convoy_stage_progress(p_booking_id, 'at_dropoff', null)
      else null
    end,
    'overall_completed', coalesce((v_finalization->>'overall_completed')::boolean, false),
    'awaiting_final_payment', coalesce((v_finalization->>'awaiting_final_payment')::boolean, false),
    'debug_bypass', v_debug_bypass
  );
end;
$$;

create or replace function public.guard_live_driver_journey_proximity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_latitude double precision;
  v_target_longitude double precision;
  v_driver_latitude double precision;
  v_driver_longitude double precision;
  v_location_updated_at timestamptz;
  v_distance_meters double precision;
  v_allowed_radius_meters constant double precision := 150;
begin
  if new.journey_state is not distinct from old.journey_state then
    return new;
  end if;
  if auth.uid() = new.driver_id and current_setting('touristrike.arrival_fallback_verified', true) = 'true' then
    return new;
  end if;
  if public.is_developer_test_booking(new.booking_id) then
    return new;
  end if;

  if new.journey_state = 'at_pickup' then
    select pb.pickup_latitude, pb.pickup_longitude
    into v_target_latitude, v_target_longitude
    from public.package_bookings pb where pb.id = new.booking_id;
  elsif new.journey_state = 'at_stop' then
    select ordered.latitude, ordered.longitude
    into v_target_latitude, v_target_longitude
    from (
      select bii.latitude, bii.longitude,
        (row_number() over (
          order by coalesce(bii.order_number, 2147483647),
                   coalesce(bii.destination_order, 2147483647),
                   bii.arrival_time nulls last, bii.created_at, bii.id
        ))::integer - 1 as stop_index
      from public.booking_itinerary_items bii
      where bii.booking_id = new.booking_id
    ) ordered
    where ordered.stop_index = new.current_stop_index;
  elsif new.journey_state = 'at_dropoff' then
    select pb.dropoff_latitude, pb.dropoff_longitude
    into v_target_latitude, v_target_longitude
    from public.package_bookings pb where pb.id = new.booking_id;
  else
    return new;
  end if;

  if v_target_latitude is null or v_target_longitude is null then
    raise exception 'TARGET_LOCATION_REQUIRED';
  end if;

  select dll.latitude, dll.longitude, dll.updated_at
  into v_driver_latitude, v_driver_longitude, v_location_updated_at
  from public.driver_live_locations dll
  where dll.driver_id = new.driver_id;
  if not found or v_location_updated_at is null
     or v_location_updated_at < now() - interval '2 minutes' then
    raise exception 'DRIVER_LOCATION_STALE';
  end if;

  v_distance_meters := 6371000 * 2 * asin(sqrt(least(1, greatest(0,
    power(sin(radians(v_driver_latitude - v_target_latitude) / 2), 2)
    + cos(radians(v_target_latitude)) * cos(radians(v_driver_latitude))
      * power(sin(radians(v_driver_longitude - v_target_longitude) / 2), 2)
  ))));
  if v_distance_meters > v_allowed_radius_meters then
    raise exception 'NOT_WITHIN_ARRIVAL_RADIUS: % m > % m',
      round(v_distance_meters), round(v_allowed_radius_meters);
  end if;
  return new;
end;
$$;

create or replace function public.sync_driver_journey_milestones()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_number integer;
  v_stop_name text;
  v_all_ready boolean;
begin
  if new.journey_state is not distinct from old.journey_state then
    return new;
  end if;

  perform set_config('touristrike.validated_transition', 'true', true);
  if new.journey_state = 'at_pickup' then
    update public.package_bookings
    set arrived_at = coalesce(arrived_at, now()), updated_at = now()
    where id = new.booking_id;
    update public.package_activities
    set arrived_at = coalesce(arrived_at, now()), updated_at = now()
    where booking_id = new.booking_id;
  elsif new.journey_state = 'boarded' then
    update public.package_bookings
    set picked_up_at = coalesce(picked_up_at, now()), updated_at = now()
    where id = new.booking_id;
    update public.package_activities
    set picked_up_at = coalesce(picked_up_at, now()), updated_at = now()
    where booking_id = new.booking_id;
  elsif new.journey_state = 'completed' then
    update public.package_activities
    set dropped_off_at = coalesce(dropped_off_at, now()), updated_at = now()
    where booking_id = new.booking_id;
  end if;

  select ranked.position into v_driver_number
  from (
    select bd.id,
      row_number() over (order by bd.accepted_at, bd.id)::integer as position
    from public.booking_drivers bd
    where bd.booking_id = new.booking_id
      and bd.status in ('accepted', 'completed')
  ) ranked where ranked.id = new.id;
  v_driver_number := coalesce(v_driver_number, 1);

  if new.journey_state = 'en_route_pickup' then
    perform public.insert_booking_system_message(
      new.booking_id,
      'journey:' || new.id::text || ':en_route_pickup',
      'Driver ' || v_driver_number || ' is on the way to the pickup location.'
    );
  elsif new.journey_state = 'at_pickup' then
    perform public.insert_booking_system_message(
      new.booking_id,
      'journey:' || new.id::text || ':at_pickup',
      'Driver ' || v_driver_number || ' has arrived at the pickup location.'
    );
    select not exists (
      select 1 from public.booking_drivers bd
      where bd.booking_id = new.booking_id
        and bd.status in ('accepted', 'completed')
        and bd.status <> 'completed'
        and public.journey_state_order(bd.journey_state)
          < public.journey_state_order('at_pickup')
    ) into v_all_ready;
    if v_all_ready then
      perform public.insert_booking_system_message(
        new.booking_id, 'journey:' || new.booking_id::text || ':all_at_pickup',
        'All drivers have arrived at the pickup location.'
      );
    end if;
  elsif new.journey_state = 'boarded' then
    select not exists (
      select 1 from public.booking_drivers bd
      where bd.booking_id = new.booking_id
        and bd.status in ('accepted', 'completed')
        and bd.status <> 'completed'
        and public.journey_state_order(bd.journey_state)
          < public.journey_state_order('boarded')
    ) into v_all_ready;
    if v_all_ready then
      perform public.insert_booking_system_message(
        new.booking_id, 'journey:' || new.booking_id::text || ':tour_started',
        'The tour has started.'
      );
    end if;
  elsif new.journey_state = 'en_route_stop' then
    select ordered.destination_name into v_stop_name
    from (
      select bii.destination_name,
        row_number() over (
          order by coalesce(bii.order_number, 2147483647),
                   coalesce(bii.destination_order, 2147483647),
                   bii.arrival_time nulls last, bii.created_at, bii.id
        )::integer - 1 as stop_index
      from public.booking_itinerary_items bii
      where bii.booking_id = new.booking_id
    ) ordered where ordered.stop_index = new.current_stop_index;
    perform public.insert_booking_system_message(
      new.booking_id,
      'journey:' || new.booking_id::text || ':heading_stop:' || new.current_stop_index,
      'Heading to ' || coalesce(v_stop_name, 'the next destination') || '.'
    );
  elsif new.journey_state = 'at_stop' then
    select ordered.destination_name into v_stop_name
    from (
      select bii.destination_name,
        row_number() over (
          order by coalesce(bii.order_number, 2147483647),
                   coalesce(bii.destination_order, 2147483647),
                   bii.arrival_time nulls last, bii.created_at, bii.id
        )::integer - 1 as stop_index
      from public.booking_itinerary_items bii
      where bii.booking_id = new.booking_id
    ) ordered where ordered.stop_index = new.current_stop_index;
    perform public.insert_booking_system_message(
      new.booking_id,
      'journey:' || new.id::text || ':at_stop:' || new.current_stop_index,
      'Driver ' || v_driver_number || ' has arrived at '
        || coalesce(v_stop_name, 'the destination') || '.'
    );
  elsif new.journey_state = 'stop_done' then
    select coalesce(
      (public.compute_convoy_stage_progress(
        new.booking_id, 'stop_done', new.current_stop_index
      )->>'all_satisfied')::boolean,
      false
    ) into v_all_ready;
    if v_all_ready then
      select ordered.destination_name into v_stop_name
      from (
        select bii.destination_name,
          row_number() over (
            order by coalesce(bii.order_number, 2147483647),
                     coalesce(bii.destination_order, 2147483647),
                     bii.arrival_time nulls last, bii.created_at, bii.id
          )::integer - 1 as stop_index
        from public.booking_itinerary_items bii
        where bii.booking_id = new.booking_id
      ) ordered where ordered.stop_index = new.current_stop_index;
      perform public.insert_booking_system_message(
        new.booking_id,
        'journey:' || new.booking_id::text || ':departed_stop:'
          || new.current_stop_index,
        'Departed ' || coalesce(v_stop_name, 'the destination') || '.'
      );
      if public.is_booking_itinerary_complete(new.booking_id)
         and not public.is_booking_remaining_payment_satisfied(new.booking_id) then
        perform public.insert_booking_system_message(
          new.booking_id,
          'payment:' || new.booking_id::text || ':remaining_pending',
          'The itinerary is complete. Remaining payment confirmation is pending.'
        );
      end if;
    end if;
  elsif new.journey_state = 'en_route_dropoff' then
    perform public.insert_booking_system_message(
      new.booking_id,
      'journey:' || new.booking_id::text || ':en_route_dropoff',
      'Proceeding to the drop-off location.'
    );
  elsif new.journey_state = 'completed' then
    select not exists (
      select 1 from public.booking_drivers bd
      where bd.booking_id = new.booking_id
        and bd.status in ('accepted', 'completed')
        and not (bd.status = 'completed' and bd.journey_state = 'completed')
    ) into v_all_ready;
    if v_all_ready then
      perform public.insert_booking_system_message(
        new.booking_id, 'journey:' || new.booking_id::text || ':completed',
        'The tour has been completed.'
      );
    end if;
  end if;
  return new;
end;
$$;

-- Manual recovery still needs server-verifiable proximity. If driver GPS is
-- unavailable, a fresh, accurate tourist location can corroborate arrival.
create or replace function public.confirm_driver_arrival_fallback(p_booking_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_booking public.package_bookings; v_driver public.booking_drivers;
  v_lat double precision; v_lng double precision; v_target text; v_result jsonb;
begin
  if auth.uid() is null or length(trim(coalesce(p_reason, ''))) < 10 or length(p_reason) > 500 then
    raise exception 'ARRIVAL_FALLBACK_REASON_REQUIRED';
  end if;
  select * into v_booking from public.package_bookings where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  select * into v_driver from public.booking_drivers where booking_id = p_booking_id
    and driver_id = auth.uid() and status = 'accepted' for update;
  if not found then raise exception 'NOT_ACTIVE_BOOKING_DRIVER'; end if;
  if v_driver.journey_state in ('at_pickup', 'at_stop', 'at_dropoff') then
    return jsonb_build_object('success', true, 'no_op', true);
  end if;
  if v_driver.journey_state = 'en_route_pickup' then
    v_target := 'at_pickup'; v_lat := v_booking.pickup_latitude; v_lng := v_booking.pickup_longitude;
  elsif v_driver.journey_state = 'en_route_dropoff' then
    v_target := 'at_dropoff'; v_lat := v_booking.dropoff_latitude; v_lng := v_booking.dropoff_longitude;
  elsif v_driver.journey_state = 'en_route_stop' then
    v_target := 'at_stop';
    select latitude, longitude into v_lat, v_lng from public.booking_itinerary_items where booking_id = p_booking_id
    order by coalesce(order_number, 2147483647), coalesce(destination_order, 2147483647), arrival_time nulls last, created_at, id
    offset v_driver.current_stop_index limit 1;
  else raise exception 'NOT_EN_ROUTE'; end if;
  if v_lat is null or v_lng is null then raise exception 'TARGET_LOCATION_REQUIRED'; end if;
  if exists (
    select 1 from public.booking_participant_live_locations l
    where l.booking_id = p_booking_id and l.user_id = v_booking.tourist_id
      and l.updated_at >= now() - interval '2 minutes' and l.accuracy_meters <= 50
      and 6371000 * 2 * asin(sqrt(least(1, greatest(0,
        power(sin(radians(l.latitude - v_lat) / 2), 2) + cos(radians(v_lat)) * cos(radians(l.latitude))
        * power(sin(radians(l.longitude - v_lng) / 2), 2))))) <= 150
  ) then
    perform set_config('touristrike.arrival_fallback_verified', 'true', true);
  end if;
  -- Otherwise the usual fresh driver-location guard applies.
  v_result := public.advance_driver_journey_state(p_booking_id, v_target);
  perform set_config('touristrike.arrival_fallback_verified', 'false', true);
  insert into public.trip_status_logs(activity_id, booking_id, driver_id, status, previous_state, new_state, spot_index, notes)
  select id, p_booking_id, auth.uid(), 'arrival_manual_fallback', v_driver.journey_state, v_target,
    v_driver.current_stop_index, trim(p_reason) from public.package_activities where booking_id = p_booking_id;
  return v_result;
end;
$$;
revoke all on function public.confirm_driver_arrival_fallback(uuid, text) from public, anon;
grant execute on function public.confirm_driver_arrival_fallback(uuid, text) to authenticated;

commit;
