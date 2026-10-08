-- Keep participant live locations private until the authoritative scheduled
-- start, while preserving the separate journey-state rule for withdrawal.
begin;

create or replace function public.can_access_live_tour_tracking(
  p_booking_id uuid,
  p_actor_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.package_bookings b
    where b.id = p_booking_id
      and p_actor_id is not null
      and p_actor_id = auth.uid()
      and b.scheduled_start_at is not null
      and now() >= b.scheduled_start_at
      and lower(coalesce(b.booking_status, b.status, '')) not in (
        'cancelled', 'completed', 'done', 'rejected', 'expired', 'failed',
        'closed', 'refunded', 'tourist_no_show'
      )
      and (
        b.tourist_id = p_actor_id
        or exists (
          select 1
          from public.booking_drivers bd
          where bd.booking_id = b.id
            and bd.driver_id = p_actor_id
            and bd.status = 'accepted'
        )
      )
  );
$$;

revoke all on function public.can_access_live_tour_tracking(uuid,uuid)
  from public, anon;
grant execute on function public.can_access_live_tour_tracking(uuid,uuid)
  to authenticated;

create or replace function public.get_live_tour_tracking_eligibility(
  p_booking_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_booking public.package_bookings;
  v_participant boolean;
  v_can_access boolean;
  v_reason text;
begin
  if v_actor is null then raise exception 'UNAUTHENTICATED'; end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  v_participant := v_booking.tourist_id = v_actor or exists (
    select 1
    from public.booking_drivers bd
    where bd.booking_id = p_booking_id
      and bd.driver_id = v_actor
      and bd.status = 'accepted'
  );
  if not v_participant then raise exception 'NOT_BOOKING_PARTICIPANT'; end if;

  v_can_access := public.can_access_live_tour_tracking(p_booking_id, v_actor);
  v_reason := case
    when lower(coalesce(v_booking.booking_status, v_booking.status, '')) in (
      'cancelled', 'completed', 'done', 'rejected', 'expired', 'failed',
      'closed', 'refunded', 'tourist_no_show'
    ) then 'BOOKING_NOT_TRACKABLE'
    when v_booking.scheduled_start_at is null then 'SCHEDULE_UNAVAILABLE'
    when now() < v_booking.scheduled_start_at then 'BEFORE_SCHEDULED_START'
    when v_can_access then 'ELIGIBLE'
    else 'NOT_ACTIVE_PARTICIPANT'
  end;

  return jsonb_build_object(
    'can_access', v_can_access,
    'reason_code', v_reason,
    'server_now', now(),
    'scheduled_start_at', v_booking.scheduled_start_at
  );
end;
$$;

revoke all on function public.get_live_tour_tracking_eligibility(uuid)
  from public, anon;
grant execute on function public.get_live_tour_tracking_eligibility(uuid)
  to authenticated;

drop policy if exists live_loc_select_active_trip
  on public.driver_live_locations;
create policy live_loc_select_active_trip on public.driver_live_locations
for select to authenticated
using (
  public.is_provincial_admin()
  or public.subtenant_can_access_driver(driver_id)
  or exists (
    select 1
    from public.package_activities pa
    where pa.id = driver_live_locations.activity_id
      and public.can_access_live_tour_tracking(pa.booking_id, auth.uid())
  )
);

drop policy if exists "live_loc_driver_upsert"
  on public.driver_live_locations;
create policy "live_loc_driver_upsert" on public.driver_live_locations
for insert to authenticated
with check (
  auth.uid() = driver_id
  and exists (
    select 1
    from public.package_activities pa
    where pa.id = driver_live_locations.activity_id
      and public.can_access_live_tour_tracking(pa.booking_id, auth.uid())
  )
);

drop policy if exists "live_loc_driver_update"
  on public.driver_live_locations;
create policy "live_loc_driver_update" on public.driver_live_locations
for update to authenticated
using (
  auth.uid() = driver_id
  and exists (
    select 1
    from public.package_activities pa
    where pa.id = driver_live_locations.activity_id
      and public.can_access_live_tour_tracking(pa.booking_id, auth.uid())
  )
)
with check (
  auth.uid() = driver_id
  and exists (
    select 1
    from public.package_activities pa
    where pa.id = driver_live_locations.activity_id
      and public.can_access_live_tour_tracking(pa.booking_id, auth.uid())
  )
);

drop policy if exists participant_live_locations_read
  on public.booking_participant_live_locations;
create policy participant_live_locations_read
on public.booking_participant_live_locations for select to authenticated
using (
  public.is_provincial_admin()
  or public.subtenant_can_access_booking(booking_id)
  or public.can_access_live_tour_tracking(booking_id, auth.uid())
);

drop policy if exists participant_live_locations_write_tourist
  on public.booking_participant_live_locations;
create policy participant_live_locations_write_tourist
on public.booking_participant_live_locations for insert to authenticated
with check (
  user_id = auth.uid()
  and participant_role = 'tourist'
  and public.can_access_live_tour_tracking(booking_id, auth.uid())
);

drop policy if exists participant_live_locations_update_tourist
  on public.booking_participant_live_locations;
create policy participant_live_locations_update_tourist
on public.booking_participant_live_locations for update to authenticated
using (
  user_id = auth.uid()
  and participant_role = 'tourist'
  and public.can_access_live_tour_tracking(booking_id, auth.uid())
)
with check (
  user_id = auth.uid()
  and participant_role = 'tourist'
  and public.can_access_live_tour_tracking(booking_id, auth.uid())
);

create or replace function public.upsert_tourist_live_location(
  p_booking_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_heading double precision default 0,
  p_speed double precision default 0,
  p_accuracy_meters double precision default null
)
returns public.booking_participant_live_locations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_booking public.package_bookings;
  v_existing public.booking_participant_live_locations;
  v_result public.booking_participant_live_locations;
  v_distance_meters double precision;
begin
  if v_user_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90
     or p_longitude not between -180 and 180
     or p_latitude::text in ('NaN', 'Infinity', '-Infinity')
     or p_longitude::text in ('NaN', 'Infinity', '-Infinity') then
    raise exception 'INVALID_LIVE_LOCATION';
  end if;
  if p_accuracy_meters is not null
     and (p_accuracy_meters < 0 or p_accuracy_meters > 500) then
    raise exception 'INVALID_LOCATION_ACCURACY';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking.tourist_id <> v_user_id then
    raise exception 'NOT_BOOKING_TOURIST';
  end if;
  if not public.can_access_live_tour_tracking(p_booking_id, v_user_id) then
    raise exception 'LIVE_TRACKING_NOT_AVAILABLE';
  end if;

  select * into v_existing
  from public.booking_participant_live_locations
  where booking_id = p_booking_id and user_id = v_user_id
  for update;

  if found then
    v_distance_meters := 6371000 * 2 * asin(sqrt(least(1, greatest(0,
      power(sin(radians(p_latitude - v_existing.latitude) / 2), 2)
      + cos(radians(v_existing.latitude)) * cos(radians(p_latitude))
        * power(sin(radians(p_longitude - v_existing.longitude) / 2), 2)
    ))));
    if now() - v_existing.updated_at < interval '3 seconds'
       and v_distance_meters < 3 then
      return v_existing;
    end if;
  end if;

  insert into public.booking_participant_live_locations(
    booking_id, user_id, participant_role, latitude, longitude,
    heading, speed, accuracy_meters, updated_at
  ) values (
    p_booking_id, v_user_id, 'tourist', p_latitude, p_longitude,
    greatest(0, least(coalesce(p_heading, 0), 360)),
    greatest(0, coalesce(p_speed, 0)), p_accuracy_meters, now()
  )
  on conflict (booking_id, user_id) do update
  set latitude = excluded.latitude,
      longitude = excluded.longitude,
      heading = excluded.heading,
      speed = excluded.speed,
      accuracy_meters = excluded.accuracy_meters,
      updated_at = excluded.updated_at
  returning * into v_result;

  return v_result;
end;
$$;

revoke all on function public.upsert_tourist_live_location(
  uuid,double precision,double precision,double precision,double precision,
  double precision
) from public, anon;
grant execute on function public.upsert_tourist_live_location(
  uuid,double precision,double precision,double precision,double precision,
  double precision
) to authenticated;

-- Payment state is deliberately absent from this guard. A confirmed payment
-- belongs to the booking; withdrawing only terminates the driver's assignment.
create or replace function public.request_driver_withdrawal(
  p_booking_id uuid,
  p_reason text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver uuid := auth.uid();
  v_booking public.package_bookings;
  v_assignment public.booking_drivers;
  v_remaining integer;
  v_required integer;
  v_window integer;
  v_next_driver uuid;
begin
  if v_driver is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_reason not in (
    'vehicle_problem', 'medical_emergency', 'personal_emergency',
    'unable_to_reach_pickup', 'safety_concern', 'other'
  ) then
    raise exception 'WITHDRAWAL_REASON_REQUIRED';
  end if;
  if p_reason = 'other' and length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'WITHDRAWAL_EXPLANATION_REQUIRED';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  select * into v_assignment
  from public.booking_drivers
  where booking_id = p_booking_id
    and driver_id = v_driver
    and status = 'accepted'
  for update;
  if not found then raise exception 'NOT_IN_CONVOY'; end if;

  if lower(coalesce(v_booking.booking_status, v_booking.status, '')) in (
       'cancelled', 'completed', 'done', 'rejected', 'expired', 'failed',
       'closed', 'refunded', 'tourist_no_show'
     ) then
    raise exception 'BOOKING_NOT_WITHDRAWABLE';
  end if;

  if v_booking.picked_up_at is not null
     or v_booking.completed_at is not null
     or lower(coalesce(v_booking.booking_status, '')) in ('on_tour', 'completed', 'done')
     or exists (
       select 1
       from public.package_activities pa
       where pa.booking_id = p_booking_id
         and lower(coalesce(pa.tour_status, pa.status, '')) in (
           'picked_up', 'on_tour', 'en_route_to_spot', 'at_spot',
           'en_route_to_dropoff', 'ready_to_complete', 'dropped_off',
           'completed'
         )
     )
     or exists (
       select 1
       from public.booking_drivers bd
       where bd.booking_id = p_booking_id
         and bd.status in ('accepted', 'completed')
         and bd.journey_state in (
           'boarded', 'en_route_stop', 'at_stop', 'stop_done',
           'en_route_dropoff', 'at_dropoff', 'completed'
         )
     ) then
    raise exception 'TOUR_ALREADY_STARTED';
  end if;

  perform set_config('touristrike.driver_withdrawal', 'true', true);
  update public.booking_drivers
  set status = 'cancelled',
      cancelled_at = now(),
      cancellation_reason = p_reason,
      withdrawal_reason_code = p_reason,
      withdrawal_note = nullif(trim(coalesce(p_note, '')), ''),
      withdrawn_at = now()
  where id = v_assignment.id;
  perform set_config('touristrike.driver_withdrawal', 'false', true);

  select count(*) into v_remaining
  from public.booking_drivers
  where booking_id = p_booking_id and status = 'accepted';
  select driver_id into v_next_driver
  from public.booking_drivers
  where booking_id = p_booking_id and status = 'accepted'
  order by accepted_at, id
  limit 1;
  v_required := greatest(coalesce(v_booking.required_drivers, 1), 1);

  select replacement_window_minutes into v_window
  from public.package_cancellation_policy
  where id = 1;

  update public.package_bookings
  set accepted_drivers_count = v_remaining,
      assigned_driver_id = v_next_driver,
      status = 'pending',
      booking_status = 'waiting_for_drivers',
      replacement_status = 'awaiting_replacement',
      replacement_search_started_at = now(),
      replacement_deadline_at = now() + make_interval(mins => coalesce(v_window, 30)),
      cancellation_party = 'driver',
      cancellation_reason_code = 'driver_withdrawal',
      refund_status = case when refund_status = 'not_required' then 'none'
        else refund_status end,
      updated_at = now()
  where id = p_booking_id;

  update public.package_activities
  set driver_id = v_next_driver,
      status = case when v_remaining > 0 then 'accepted' else 'pending' end,
      tour_status = case when v_remaining > 0
        then 'driver_accepted' else 'waiting_driver' end,
      driver_latitude = null,
      driver_longitude = null,
      driver_last_seen = null,
      updated_at = now()
  where booking_id = p_booking_id;

  insert into public.notifications(user_id, title, body, type, is_read)
  values (
    v_booking.tourist_id,
    'Driver reassignment',
    'Your assigned Driver is no longer available. TourisTrike is processing the driver reassignment.',
    'driver_withdrawal',
    false
  );

  insert into public.notifications(user_id, title, body, type, is_read)
  select office.id,
    'Driver withdrawal',
    'Booking ' || p_booking_id::text || ' needs Driver reassignment (' || p_reason || ').',
    'driver_withdrawal',
    false
  from public.subtenant_details office
  join public.profiles p on p.id = office.id and p.role = 'subtenant'
  where office.is_active = true
    and public.cities_match(office.city, v_booking.municipality)
    and public.cities_match(office.province, v_booking.province);

  insert into public.audit_logs(actor_id, action, table_name, record_id, description)
  values (
    v_driver,
    'request_driver_withdrawal',
    'booking_drivers',
    p_booking_id::text,
    p_reason
  );

  perform public.notify_eligible_replacement_drivers(p_booking_id, v_driver);

  return jsonb_build_object(
    'success', true,
    'booking_id', p_booking_id,
    'booking_cancelled', false,
    'reason', p_reason,
    'accepted_count', v_remaining,
    'required_count', v_required,
    'replacement_status', 'awaiting_replacement',
    'payment_preserved', true,
    'additional_downpayment_required', false
  );
end;
$$;

revoke all on function public.request_driver_withdrawal(uuid,text,text)
  from public, anon;
grant execute on function public.request_driver_withdrawal(uuid,text,text)
  to authenticated;

commit;
