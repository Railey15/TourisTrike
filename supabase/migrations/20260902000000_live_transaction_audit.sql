-- Production live-transaction hardening: GPS validation, participant tracking,
-- atomic group chat, milestone timestamps, and convoy-safe driver reviews.

begin;

-- ---------------------------------------------------------------------------
-- Location integrity and tourist location sharing
-- ---------------------------------------------------------------------------

alter table public.driver_live_locations
  drop constraint if exists driver_live_locations_coordinate_check;
alter table public.driver_live_locations
  add constraint driver_live_locations_coordinate_check check (
    latitude between -90 and 90
    and longitude between -180 and 180
    and heading between 0 and 360
    and speed >= 0
  ) not valid;

create table if not exists public.booking_participant_live_locations (
  booking_id uuid not null
    references public.package_bookings(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  participant_role text not null check (participant_role in ('tourist', 'driver')),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  heading double precision not null default 0 check (heading between 0 and 360),
  speed double precision not null default 0 check (speed >= 0),
  accuracy_meters double precision check (
    accuracy_meters is null or accuracy_meters between 0 and 500
  ),
  updated_at timestamptz not null default now(),
  primary key (booking_id, user_id)
);

create index if not exists booking_participant_live_locations_user_idx
  on public.booking_participant_live_locations(user_id, updated_at desc);

alter table public.booking_participant_live_locations enable row level security;

create or replace function public.is_package_booking_participant(
  p_booking_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and (
    exists (
      select 1 from public.package_bookings pb
      where pb.id = p_booking_id and pb.tourist_id = auth.uid()
    )
    or exists (
      select 1 from public.booking_drivers bd
      where bd.booking_id = p_booking_id
        and bd.driver_id = auth.uid()
        and bd.status in ('accepted', 'completed')
    )
    or coalesce(public.current_profile_role(), '') in ('admin', 'subtenant')
  );
$$;

revoke all on function public.is_package_booking_participant(uuid)
  from public, anon;
grant execute on function public.is_package_booking_participant(uuid)
  to authenticated;

drop policy if exists participant_live_locations_read
  on public.booking_participant_live_locations;
create policy participant_live_locations_read
on public.booking_participant_live_locations for select to authenticated
using (public.is_package_booking_participant(booking_id));

drop policy if exists participant_live_locations_write_tourist
  on public.booking_participant_live_locations;
create policy participant_live_locations_write_tourist
on public.booking_participant_live_locations for insert to authenticated
with check (
  user_id = auth.uid()
  and participant_role = 'tourist'
  and exists (
    select 1 from public.package_bookings pb
    where pb.id = booking_participant_live_locations.booking_id
      and pb.tourist_id = auth.uid()
  )
);

drop policy if exists participant_live_locations_update_tourist
  on public.booking_participant_live_locations;
create policy participant_live_locations_update_tourist
on public.booking_participant_live_locations for update to authenticated
using (user_id = auth.uid() and participant_role = 'tourist')
with check (
  user_id = auth.uid()
  and participant_role = 'tourist'
  and exists (
    select 1 from public.package_bookings pb
    where pb.id = booking_participant_live_locations.booking_id
      and pb.tourist_id = auth.uid()
  )
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
set search_path = public
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
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
     in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_TRACKABLE';
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
  uuid, double precision, double precision, double precision,
  double precision, double precision
) from public, anon;
grant execute on function public.upsert_tourist_live_location(
  uuid, double precision, double precision, double precision,
  double precision, double precision
) to authenticated;

-- ---------------------------------------------------------------------------
-- Server-side live-mode proximity checks
-- ---------------------------------------------------------------------------

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

drop trigger if exists trg_guard_live_driver_journey_proximity
  on public.booking_drivers;
create trigger trg_guard_live_driver_journey_proximity
before update of journey_state, current_stop_index on public.booking_drivers
for each row execute function public.guard_live_driver_journey_proximity();

-- ---------------------------------------------------------------------------
-- Atomic booking group chat and stable sender identities
-- ---------------------------------------------------------------------------

alter table public.conversations
  add column if not exists title text not null default '';

alter table public.messages alter column sender_id drop not null;
alter table public.messages
  add column if not exists message_type text not null default 'user';
alter table public.messages
  drop constraint if exists messages_type_check;
alter table public.messages
  add constraint messages_type_check
  check (message_type in ('user', 'system'));
alter table public.messages
  add column if not exists client_message_id uuid;
alter table public.messages
  add column if not exists system_event_key text;

create unique index if not exists messages_sender_client_uidx
  on public.messages(sender_id, client_message_id)
  where sender_id is not null and client_message_id is not null;
create unique index if not exists messages_system_event_uidx
  on public.messages(system_event_key)
  where system_event_key is not null;

create or replace function public.guard_conversation_identity_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(
       current_setting('touristrike.system_conversation_write', true), ''
     ) = 'true' then
    return new;
  end if;
  if auth.uid() is not null and (
    new.tourist_id is distinct from old.tourist_id
    or new.driver_id is distinct from old.driver_id
    or new.booking_id is distinct from old.booking_id
    or new.conversation_type is distinct from old.conversation_type
    or new.title is distinct from old.title
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'CONVERSATION_IDENTITY_IMMUTABLE';
  end if;
  return new;
end;
$$;

create or replace function public.guard_message_identity_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and (
    new.conversation_id is distinct from old.conversation_id
    or new.sender_id is distinct from old.sender_id
    or new.receiver_id is distinct from old.receiver_id
    or new.message_text is distinct from old.message_text
    or new.message_type is distinct from old.message_type
    or new.client_message_id is distinct from old.client_message_id
    or new.system_event_key is distinct from old.system_event_key
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'MESSAGE_CONTENT_IMMUTABLE';
  end if;
  return new;
end;
$$;

drop policy if exists messages_insert_participants on public.messages;
create policy messages_insert_participants on public.messages
for insert to authenticated
with check (
  sender_id = auth.uid()
  and message_type = 'user'
  and system_event_key is null
  and public.can_access_conversation(conversation_id)
);

create or replace function public.ensure_booking_group_conversation(
  p_booking_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_conversation_id uuid;
  v_package_name text;
  v_tourist_name text;
  v_title text;
begin
  select * into v_booking
  from public.package_bookings where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if auth.uid() is not null
     and auth.uid() <> v_booking.tourist_id
     and coalesce(public.current_profile_role(), '') not in ('admin', 'subtenant')
     and not exists (
       select 1 from public.booking_drivers bd
       where bd.booking_id = p_booking_id and bd.driver_id = auth.uid()
         and bd.status in ('accepted', 'completed')
     ) then
    raise exception 'NOT_BOOKING_PARTICIPANT';
  end if;

  select coalesce(nullif(trim(tp.title), ''), 'Tour Package')
  into v_package_name
  from public.tour_packages tp where tp.id = v_booking.package_id;
  v_package_name := coalesce(v_package_name, 'Tour Package');

  select coalesce(
    nullif(trim(p.full_name), ''),
    nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Tourist'
  ) into v_tourist_name
  from public.profiles p where p.id = v_booking.tourist_id;
  v_tourist_name := coalesce(v_tourist_name, 'Tourist');
  v_title := v_package_name || ' • ' || v_tourist_name;

  perform set_config('touristrike.system_conversation_write', 'true', true);
  insert into public.conversations(
    tourist_id, driver_id, booking_id, conversation_type, title
  ) values (
    v_booking.tourist_id, null, p_booking_id, 'booking_group', v_title
  )
  on conflict (booking_id)
    where conversation_type = 'booking_group' and booking_id is not null
  do update set tourist_id = excluded.tourist_id, title = excluded.title
  returning id into v_conversation_id;

  insert into public.conversation_members(conversation_id, user_id, member_role)
  values (v_conversation_id, v_booking.tourist_id, 'tourist')
  on conflict do nothing;
  insert into public.conversation_members(conversation_id, user_id, member_role)
  select v_conversation_id, bd.driver_id, 'driver'
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id and bd.status in ('accepted', 'completed')
  on conflict do nothing;
  return v_conversation_id;
end;
$$;

revoke all on function public.ensure_booking_group_conversation(uuid)
  from public, anon;
grant execute on function public.ensure_booking_group_conversation(uuid)
  to authenticated;

create or replace function public.send_conversation_message(
  p_conversation_id uuid,
  p_message_text text,
  p_client_message_id uuid
)
returns public.messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_text text := trim(coalesce(p_message_text, ''));
  v_message public.messages;
begin
  if v_user_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if not public.can_access_conversation(p_conversation_id) then
    raise exception 'NOT_CONVERSATION_MEMBER';
  end if;
  if v_text = '' or length(v_text) > 2000 then
    raise exception 'INVALID_MESSAGE_TEXT';
  end if;
  if p_client_message_id is null then
    raise exception 'CLIENT_MESSAGE_ID_REQUIRED';
  end if;

  select * into v_message from public.messages
  where sender_id = v_user_id and client_message_id = p_client_message_id;
  if found then
    if v_message.conversation_id <> p_conversation_id
       or v_message.message_text <> v_text then
      raise exception 'CLIENT_MESSAGE_ID_REUSED';
    end if;
    return v_message;
  end if;

  insert into public.messages(
    conversation_id, sender_id, receiver_id, message_text, is_read,
    message_type, client_message_id
  ) values (
    p_conversation_id, v_user_id, null, v_text, false,
    'user', p_client_message_id
  )
  on conflict (sender_id, client_message_id)
    where sender_id is not null and client_message_id is not null
  do nothing
  returning * into v_message;

  if not found then
    select * into v_message from public.messages
    where sender_id = v_user_id and client_message_id = p_client_message_id;
    if not found
       or v_message.conversation_id <> p_conversation_id
       or v_message.message_text <> v_text then
      raise exception 'CLIENT_MESSAGE_ID_REUSED';
    end if;
    return v_message;
  end if;

  update public.conversations
  set last_message = v_text, last_message_at = v_message.created_at
  where id = p_conversation_id;
  return v_message;
end;
$$;

revoke all on function public.send_conversation_message(uuid, text, uuid)
  from public, anon;
grant execute on function public.send_conversation_message(uuid, text, uuid)
  to authenticated;

create or replace function public.get_conversation_message_feed(
  p_conversation_id uuid
)
returns table (
  id uuid,
  sender_id uuid,
  message_text text,
  is_read boolean,
  created_at timestamptz,
  message_type text,
  client_message_id uuid,
  sender_display_name text,
  sender_role text,
  driver_number integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if not public.can_access_conversation(p_conversation_id) then
    raise exception 'NOT_CONVERSATION_MEMBER';
  end if;

  return query
  with conversation_context as (
    select c.booking_id from public.conversations c
    where c.id = p_conversation_id
  ), ranked_drivers as (
    select bd.driver_id,
      row_number() over (order by bd.accepted_at, bd.id)::integer as position
    from public.booking_drivers bd
    join conversation_context cc on cc.booking_id = bd.booking_id
    where bd.status in ('accepted', 'completed')
  )
  select m.id, m.sender_id, m.message_text, m.is_read, m.created_at,
    m.message_type, m.client_message_id,
    case when m.message_type = 'system' then 'TourisTrike'
      else coalesce(
        nullif(trim(p.full_name), ''),
        nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''),
        'Participant'
      ) end,
    case when m.message_type = 'system' then 'system'
      else coalesce(p.role, 'participant') end,
    rd.position
  from public.messages m
  left join public.profiles p on p.id = m.sender_id
  left join ranked_drivers rd on rd.driver_id = m.sender_id
  where m.conversation_id = p_conversation_id
  order by m.created_at, m.id;
end;
$$;

revoke all on function public.get_conversation_message_feed(uuid)
  from public, anon;
grant execute on function public.get_conversation_message_feed(uuid)
  to authenticated;

create or replace function public.insert_booking_system_message(
  p_booking_id uuid,
  p_event_key text,
  p_message_text text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conversation_id uuid;
  v_message_id uuid;
begin
  if p_event_key is null or trim(p_event_key) = ''
     or p_message_text is null or trim(p_message_text) = '' then
    raise exception 'INVALID_SYSTEM_MESSAGE';
  end if;
  v_conversation_id := public.ensure_booking_group_conversation(p_booking_id);

  insert into public.messages(
    conversation_id, sender_id, receiver_id, message_text, is_read,
    message_type, system_event_key
  ) values (
    v_conversation_id, null, null, trim(p_message_text), false,
    'system', p_event_key
  )
  on conflict (system_event_key) where system_event_key is not null
  do nothing returning id into v_message_id;

  if v_message_id is not null then
    update public.conversations
    set last_message = trim(p_message_text), last_message_at = now()
    where id = v_conversation_id;
  end if;
  return v_message_id;
end;
$$;

revoke all on function public.insert_booking_system_message(uuid, text, text)
  from public, anon, authenticated;

-- Persist actual milestones and emit idempotent chat events from the same
-- authoritative assignment transition that changed the trip state.
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
  elsif new.journey_state = 'at_dropoff' then
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

drop trigger if exists trg_sync_driver_journey_milestones
  on public.booking_drivers;
create trigger trg_sync_driver_journey_milestones
after update of journey_state on public.booking_drivers
for each row execute function public.sync_driver_journey_milestones();

create or replace function public.sync_booking_payment_chat_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.payment_stage = 'remaining_balance'
     and new.status in ('satisfied', 'waived') then
    if tg_op = 'INSERT' then
      perform public.insert_booking_system_message(
        new.booking_id,
        'payment:' || new.booking_id::text || ':remaining_confirmed',
        'The remaining payment has been confirmed.'
      );
    elsif new.status is distinct from old.status
          or new.satisfied_by_payment_record_id
             is distinct from old.satisfied_by_payment_record_id then
      perform public.insert_booking_system_message(
        new.booking_id,
        'payment:' || new.booking_id::text || ':remaining_confirmed',
        'The remaining payment has been confirmed.'
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_booking_payment_chat_event
  on public.booking_payment_requirements;
create trigger trg_sync_booking_payment_chat_event
after insert or update on public.booking_payment_requirements
for each row execute function public.sync_booking_payment_chat_event();

-- Refresh titles and membership for existing booking conversations.
do $$
declare v_booking_id uuid;
begin
  for v_booking_id in
    select c.booking_id from public.conversations c
    where c.conversation_type = 'booking_group' and c.booking_id is not null
  loop
    perform public.ensure_booking_group_conversation(v_booking_id);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- One package review plus one independent review per participating driver
-- ---------------------------------------------------------------------------

alter table public.driver_reviews
  drop constraint if exists driver_reviews_booking_id_tourist_id_key;
drop index if exists public.driver_reviews_booking_id_tourist_id_key;
create unique index if not exists driver_reviews_booking_driver_tourist_uidx
  on public.driver_reviews(booking_id, driver_id, tourist_id);

drop policy if exists driver_reviews_insert on public.driver_reviews;
create policy driver_reviews_insert on public.driver_reviews
for insert to authenticated
with check (
  tourist_id = auth.uid()
  and exists (
    select 1 from public.package_bookings pb
    where pb.id = driver_reviews.booking_id and pb.tourist_id = auth.uid()
      and lower(coalesce(pb.booking_status, pb.status, ''))
        in ('completed', 'done')
  )
  and exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = driver_reviews.booking_id
      and bd.driver_id = driver_reviews.driver_id
      and bd.status = 'completed'
  )
);

drop policy if exists driver_reviews_update on public.driver_reviews;
create policy driver_reviews_update on public.driver_reviews
for update to authenticated
using (tourist_id = auth.uid())
with check (
  tourist_id = auth.uid()
  and exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = driver_reviews.booking_id
      and bd.driver_id = driver_reviews.driver_id
      and bd.status = 'completed'
  )
);

create or replace function public.tourist_has_reviewed_booking(
  p_booking_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.package_reviews pr
    where pr.booking_id = p_booking_id and pr.tourist_id = auth.uid()
  ) and (
    select count(*) from public.driver_reviews dr
    where dr.booking_id = p_booking_id and dr.tourist_id = auth.uid()
  ) = (
    select count(*) from public.booking_drivers bd
    where bd.booking_id = p_booking_id and bd.status = 'completed'
  ) and exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = p_booking_id and bd.status = 'completed'
  );
$$;

revoke all on function public.tourist_has_reviewed_booking(uuid)
  from public, anon;
grant execute on function public.tourist_has_reviewed_booking(uuid)
  to authenticated;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'booking_participant_live_locations', 'conversation_members',
    'conversations', 'messages', 'driver_reviews'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I', v_table
      );
    end if;
  end loop;
end;
$$;

notify pgrst, 'reload schema';

commit;
