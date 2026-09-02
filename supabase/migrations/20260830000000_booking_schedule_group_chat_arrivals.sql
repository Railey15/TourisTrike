-- Booking schedule/capacity propagation, booking-group chat membership,
-- available-job notifications, and idempotent per-driver stop arrivals.

begin;

alter table public.booking_itinerary_items
  add column if not exists travel_duration_minutes integer not null default 0,
  add column if not exists route_distance_meters integer not null default 0;

alter table public.booking_itinerary_items
  drop constraint if exists booking_itinerary_travel_duration_check;
alter table public.booking_itinerary_items
  add constraint booking_itinerary_travel_duration_check
  check (travel_duration_minutes >= 0 and route_distance_meters >= 0);

create or replace function public.minimum_required_tricycles(
  p_total_passengers integer
)
returns integer
language sql
immutable
set search_path = public
as $$
  select greatest(ceil(greatest(coalesce(p_total_passengers, 1), 1) / 3.0)::integer, 1);
$$;

create or replace function public.validate_booking_schedule_and_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
     or new.required_drivers is distinct from old.required_drivers then
    if new.required_drivers < public.minimum_required_tricycles(new.total_passengers) then
      raise exception 'TRICYCLE_COUNT_BELOW_CAPACITY_MINIMUM';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_booking_schedule_and_capacity
  on public.package_bookings;
create trigger trg_validate_booking_schedule_and_capacity
before insert or update of scheduled_start_at, estimated_end_at, travel_date,
  total_passengers, required_drivers
on public.package_bookings
for each row execute function public.validate_booking_schedule_and_capacity();

create or replace function public.create_package_booking(
  p_booking jsonb,
  p_customized_spots jsonb default '[]'::jsonb,
  p_itinerary_items jsonb default '[]'::jsonb
)
returns public.package_bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tourist_id uuid := auth.uid();
  v_booking public.package_bookings;
  v_package_id bigint;
  v_total_passengers integer;
  v_required_drivers integer;
  v_scheduled_start_at timestamptz;
  v_estimated_end_at timestamptz;
begin
  if v_tourist_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if public.current_profile_role() <> 'tourist' then
    raise exception 'TOURIST_ROLE_REQUIRED';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_tourist_id::text, 0));
  if jsonb_typeof(coalesce(p_booking, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_customized_spots, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_itinerary_items, '[]'::jsonb)) <> 'array' then
    raise exception 'INVALID_BOOKING_PAYLOAD';
  end if;

  v_package_id := nullif(p_booking->>'package_id', '')::bigint;
  if v_package_id is null or not exists (
    select 1 from public.tour_packages where id = v_package_id
  ) then raise exception 'PACKAGE_NOT_FOUND'; end if;

  v_total_passengers := coalesce(
    nullif(p_booking->>'total_passengers', '')::integer,
    coalesce(nullif(p_booking->>'adults', '')::integer, 1)
      + coalesce(nullif(p_booking->>'children', '')::integer, 0)
  );
  v_required_drivers := coalesce(
    nullif(p_booking->>'required_drivers', '')::integer,
    public.minimum_required_tricycles(v_total_passengers)
  );
  if v_required_drivers < public.minimum_required_tricycles(v_total_passengers) then
    raise exception 'TRICYCLE_COUNT_BELOW_CAPACITY_MINIMUM';
  end if;

  v_scheduled_start_at := nullif(p_booking->>'scheduled_start_at', '')::timestamptz;
  v_estimated_end_at := nullif(p_booking->>'estimated_end_at', '')::timestamptz;
  if v_scheduled_start_at is null or v_estimated_end_at is null
     or v_estimated_end_at <= v_scheduled_start_at then
    raise exception 'INVALID_BOOKING_SCHEDULE_WINDOW';
  end if;

  insert into public.package_bookings (
    package_id, tourist_id, travel_date, scheduled_start_at, estimated_end_at,
    adults, children, payment_method, notes, total_amount, downpayment_amount,
    remaining_balance, booking_type, pickup_address, pickup_latitude,
    pickup_longitude, pickup_province, pickup_locality, pickup_country_code,
    dropoff_address, dropoff_latitude, dropoff_longitude, dropoff_province,
    dropoff_locality, dropoff_country_code, required_drivers, municipality,
    province, total_passengers, booking_status, status
  ) values (
    v_package_id, v_tourist_id, (p_booking->>'travel_date')::date,
    v_scheduled_start_at, v_estimated_end_at,
    coalesce(nullif(p_booking->>'adults', '')::integer, 1),
    coalesce(nullif(p_booking->>'children', '')::integer, 0),
    coalesce(nullif(p_booking->>'payment_method', ''), 'cash'),
    nullif(btrim(p_booking->>'notes'), ''),
    coalesce(nullif(p_booking->>'total_amount', '')::numeric, 0),
    coalesce(nullif(p_booking->>'downpayment_amount', '')::numeric, 0),
    coalesce(nullif(p_booking->>'remaining_balance', '')::numeric, 0),
    coalesce(nullif(p_booking->>'booking_type', ''), 'advanced'),
    nullif(btrim(p_booking->>'pickup_address'), ''),
    nullif(p_booking->>'pickup_latitude', '')::double precision,
    nullif(p_booking->>'pickup_longitude', '')::double precision,
    nullif(btrim(p_booking->>'pickup_province'), ''),
    nullif(btrim(p_booking->>'pickup_locality'), ''),
    coalesce(nullif(btrim(p_booking->>'pickup_country_code'), ''), 'PH'),
    nullif(btrim(p_booking->>'dropoff_address'), ''),
    nullif(p_booking->>'dropoff_latitude', '')::double precision,
    nullif(p_booking->>'dropoff_longitude', '')::double precision,
    nullif(btrim(p_booking->>'dropoff_province'), ''),
    nullif(btrim(p_booking->>'dropoff_locality'), ''),
    coalesce(nullif(btrim(p_booking->>'dropoff_country_code'), ''), 'PH'),
    v_required_drivers, nullif(btrim(p_booking->>'municipality'), ''),
    nullif(btrim(p_booking->>'province'), ''), v_total_passengers,
    'pending', 'pending'
  ) returning * into v_booking;

  insert into public.customized_package_spots (
    booking_id, tourist_id, package_id, spot_id, action_type, source_type,
    google_place_id, spot_title, spot_address, municipality, barangay,
    latitude, longitude, image_url, additional_fee, sort_order, opening_time,
    closing_time, estimated_arrival_time, estimated_duration_minutes,
    recommended_visit_duration_minutes
  )
  select v_booking.id, v_tourist_id, v_package_id,
    nullif(item->>'spot_id', '')::bigint,
    coalesce(nullif(item->>'action_type', ''), 'kept'),
    coalesce(nullif(item->>'source_type', ''), 'manual'),
    nullif(item->>'google_place_id', ''), item->>'spot_title',
    nullif(item->>'spot_address', ''), item->>'municipality',
    nullif(item->>'barangay', ''),
    nullif(item->>'latitude', '')::double precision,
    nullif(item->>'longitude', '')::double precision,
    nullif(item->>'image_url', ''),
    coalesce(nullif(item->>'additional_fee', '')::numeric, 0),
    nullif(item->>'sort_order', '')::integer,
    nullif(item->>'opening_time', '')::time,
    nullif(item->>'closing_time', '')::time,
    nullif(item->>'estimated_arrival_time', '')::time,
    nullif(item->>'estimated_duration_minutes', '')::integer,
    nullif(item->>'recommended_visit_duration_minutes', '')::integer
  from jsonb_array_elements(coalesce(p_customized_spots, '[]'::jsonb)) item;

  insert into public.booking_itinerary_items (
    booking_id, tourist_id, spot_id, destination_name, destination_address,
    order_number, destination_order, arrival_time,
    estimated_stay_duration_minutes, departure_time,
    travel_duration_minutes, route_distance_meters, activity_note,
    itinerary_source, source_type, google_place_id, municipality, barangay,
    latitude, longitude, image_url
  )
  select v_booking.id, v_tourist_id,
    nullif(item->>'spot_id', '')::bigint, item->>'destination_name',
    nullif(item->>'destination_address', ''),
    coalesce(nullif(item->>'order_number', '')::integer,
      nullif(item->>'destination_order', '')::integer, ordinal::integer),
    coalesce(nullif(item->>'destination_order', '')::integer, ordinal::integer),
    nullif(item->>'arrival_time', '')::time,
    coalesce(nullif(item->>'estimated_stay_duration_minutes', '')::integer, 0),
    nullif(item->>'departure_time', '')::time,
    coalesce(nullif(item->>'travel_duration_minutes', '')::integer, 0),
    coalesce(nullif(item->>'route_distance_meters', '')::integer, 0),
    nullif(item->>'activity_note', ''),
    coalesce(nullif(item->>'itinerary_source', ''),
      nullif(item->>'source_type', ''), 'ai_suggested'),
    coalesce(nullif(item->>'source_type', ''), 'ai_suggested'),
    nullif(item->>'google_place_id', ''), nullif(item->>'municipality', ''),
    nullif(item->>'barangay', ''),
    nullif(item->>'latitude', '')::double precision,
    nullif(item->>'longitude', '')::double precision,
    nullif(item->>'image_url', '')
  from jsonb_array_elements(coalesce(p_itinerary_items, '[]'::jsonb))
    with ordinality as rows(item, ordinal);

  return v_booking;
end;
$$;

revoke all on function public.create_package_booking(jsonb, jsonb, jsonb)
  from public;
grant execute on function public.create_package_booking(jsonb, jsonb, jsonb)
  to authenticated;

-- One group conversation per booking; membership is authoritative and can
-- represent any convoy size without duplicating chats per driver.
alter table public.conversations alter column driver_id drop not null;
alter table public.conversations
  add column if not exists conversation_type text not null default 'direct';
alter table public.conversations
  drop constraint if exists conversations_type_check;
alter table public.conversations
  add constraint conversations_type_check
  check (conversation_type in ('direct', 'booking_group'));
create unique index if not exists conversations_one_booking_group_uidx
  on public.conversations (booking_id)
  where conversation_type = 'booking_group' and booking_id is not null;

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  member_role text not null check (member_role in ('tourist', 'driver', 'admin')),
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index if not exists conversation_members_user_idx
  on public.conversation_members(user_id, joined_at desc);
alter table public.conversation_members enable row level security;

create or replace function public.is_conversation_member(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = p_conversation_id and cm.user_id = auth.uid()
  );
$$;
revoke all on function public.is_conversation_member(uuid) from public, anon;
grant execute on function public.is_conversation_member(uuid) to authenticated;

create or replace function public.can_access_conversation(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_conversation_member(p_conversation_id)
    or exists (
      select 1 from public.conversations c
      where c.id = p_conversation_id
        and (c.tourist_id = auth.uid() or c.driver_id = auth.uid())
    );
$$;
revoke all on function public.can_access_conversation(uuid) from public, anon;
grant execute on function public.can_access_conversation(uuid) to authenticated;

drop policy if exists conversation_members_select_participants
  on public.conversation_members;
create policy conversation_members_select_participants
on public.conversation_members for select to authenticated
using (public.is_conversation_member(conversation_id));

drop policy if exists conversations_select_group_members on public.conversations;
create policy conversations_select_group_members
on public.conversations for select to authenticated
using (public.is_conversation_member(id));

drop policy if exists conversations_update_group_members on public.conversations;
create policy conversations_update_group_members
on public.conversations for update to authenticated
using (public.is_conversation_member(id))
with check (public.is_conversation_member(id));

create or replace function public.guard_conversation_identity_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and (
    new.tourist_id is distinct from old.tourist_id
    or new.driver_id is distinct from old.driver_id
    or new.booking_id is distinct from old.booking_id
    or new.conversation_type is distinct from old.conversation_type
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'CONVERSATION_IDENTITY_IMMUTABLE';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_guard_conversation_identity_update
  on public.conversations;
create trigger trg_guard_conversation_identity_update
before update on public.conversations for each row
execute function public.guard_conversation_identity_update();

drop policy if exists messages_select_participants on public.messages;
create policy messages_select_participants on public.messages
for select to authenticated
using (public.can_access_conversation(conversation_id));
drop policy if exists messages_insert_participants on public.messages;
create policy messages_insert_participants on public.messages
for insert to authenticated
with check (
  sender_id = auth.uid() and public.can_access_conversation(conversation_id)
);
drop policy if exists messages_update_participants on public.messages;
create policy messages_update_participants on public.messages
for update to authenticated
using (public.can_access_conversation(conversation_id))
with check (public.can_access_conversation(conversation_id));

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
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'MESSAGE_CONTENT_IMMUTABLE';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_guard_message_identity_update on public.messages;
create trigger trg_guard_message_identity_update
before update on public.messages for each row
execute function public.guard_message_identity_update();

create or replace function public.ensure_booking_group_conversation(p_booking_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_booking public.package_bookings; v_conversation_id uuid;
begin
  select * into v_booking from public.package_bookings where id = p_booking_id;
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
  insert into public.conversations
    (tourist_id, driver_id, booking_id, conversation_type)
  values (v_booking.tourist_id, null, p_booking_id, 'booking_group')
  on conflict (booking_id)
    where conversation_type = 'booking_group' and booking_id is not null
  do update set tourist_id = excluded.tourist_id
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

create or replace function public.sync_booking_group_conversation()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_conversation_id uuid;
begin
  if tg_table_name = 'package_bookings' then
    perform public.ensure_booking_group_conversation(new.id);
    return new;
  end if;
  v_conversation_id := public.ensure_booking_group_conversation(new.booking_id);
  if new.status in ('accepted', 'completed') then
    insert into public.conversation_members(conversation_id, user_id, member_role)
    values (v_conversation_id, new.driver_id, 'driver') on conflict do nothing;
  elsif tg_op = 'UPDATE' and old.status = 'accepted' then
    delete from public.conversation_members
    where conversation_id = v_conversation_id and user_id = new.driver_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_package_booking_group_conversation on public.package_bookings;
create trigger trg_package_booking_group_conversation
after insert on public.package_bookings for each row
execute function public.sync_booking_group_conversation();
drop trigger if exists trg_booking_driver_group_membership on public.booking_drivers;
create trigger trg_booking_driver_group_membership
after insert or update of status on public.booking_drivers for each row
execute function public.sync_booking_group_conversation();

insert into public.conversations(tourist_id, driver_id, booking_id, conversation_type)
select pb.tourist_id, null, pb.id, 'booking_group'
from public.package_bookings pb
where not exists (
  select 1 from public.conversations c
  where c.booking_id = pb.id and c.conversation_type = 'booking_group'
)
on conflict do nothing;
insert into public.conversation_members(conversation_id, user_id, member_role)
select c.id, c.tourist_id, 'tourist' from public.conversations c
where c.conversation_type = 'booking_group' on conflict do nothing;
insert into public.conversation_members(conversation_id, user_id, member_role)
select c.id, bd.driver_id, 'driver'
from public.conversations c join public.booking_drivers bd on bd.booking_id = c.booking_id
where c.conversation_type = 'booking_group' and bd.status in ('accepted', 'completed')
on conflict do nothing;

alter table public.notifications add column if not exists dedupe_key text;
create unique index if not exists notifications_dedupe_uidx
  on public.notifications(dedupe_key) where dedupe_key is not null;

create or replace function public.notify_drivers_of_available_booking()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications(user_id, title, body, type, is_read, dedupe_key)
  select p.id, 'New package job available',
    concat(
      to_char(new.scheduled_start_at at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM'),
      ' | ', coalesce(new.pickup_address, new.municipality, 'Pickup pending'),
      ' | ', new.required_drivers, ' tricycle', case when new.required_drivers = 1 then '' else 's' end
    ),
    'available_package_job', false,
    'available_job:' || new.id::text || ':' || p.id::text
  from public.profiles p
  where p.role = 'driver'
    and (coalesce(p.is_online, false) or coalesce(p.is_available, false))
    and lower(trim(coalesce(p.city, ''))) = lower(trim(coalesce(new.municipality, '')))
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
  return new;
end;
$$;
drop trigger if exists trg_notify_available_package_job on public.package_bookings;
create trigger trg_notify_available_package_job after insert on public.package_bookings
for each row execute function public.notify_drivers_of_available_booking();

create table if not exists public.booking_driver_arrivals (
  booking_driver_id uuid not null references public.booking_drivers(id) on delete cascade,
  itinerary_item_id uuid not null references public.booking_itinerary_items(id) on delete cascade,
  arrived_at timestamptz not null default now(),
  latitude double precision,
  longitude double precision,
  primary key (booking_driver_id, itinerary_item_id)
);
alter table public.booking_driver_arrivals enable row level security;
drop policy if exists booking_driver_arrivals_participant_read
  on public.booking_driver_arrivals;
create policy booking_driver_arrivals_participant_read
on public.booking_driver_arrivals for select to authenticated
using (
  exists (
    select 1 from public.booking_drivers bd
    join public.package_bookings pb on pb.id = bd.booking_id
    where bd.id = booking_driver_id
      and (bd.driver_id = auth.uid() or pb.tourist_id = auth.uid()
        or public.current_profile_role() in ('admin', 'subtenant'))
  )
);

create or replace function public.mark_itinerary_stop_arrived(
  p_booking_id uuid,
  p_itinerary_item_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_booking_driver_id uuid;
  v_inserted integer;
  v_stop_latitude double precision;
  v_stop_longitude double precision;
  v_driver_latitude double precision;
  v_driver_longitude double precision;
  v_location_updated_at timestamptz;
  v_distance_meters double precision;
begin
  select bd.id into v_booking_driver_id
  from public.booking_drivers bd
  join public.package_bookings pb on pb.id = bd.booking_id
  where bd.booking_id = p_booking_id and bd.driver_id = v_driver_id
    and bd.status = 'accepted'
    and lower(coalesce(pb.booking_status, pb.status, ''))
      not in ('cancelled', 'completed', 'rejected', 'done');
  if not found then raise exception 'NOT_ACTIVE_BOOKING_DRIVER'; end if;
  select bii.latitude, bii.longitude
  into v_stop_latitude, v_stop_longitude
  from public.booking_itinerary_items bii
  where bii.id = p_itinerary_item_id and bii.booking_id = p_booking_id;
  if not found then raise exception 'ITINERARY_ITEM_NOT_FOUND'; end if;
  if v_stop_latitude is null or v_stop_longitude is null then
    raise exception 'ITINERARY_STOP_LOCATION_REQUIRED';
  end if;

  if exists (
    select 1 from public.booking_driver_arrivals bda
    where bda.booking_driver_id = v_booking_driver_id
      and bda.itinerary_item_id = p_itinerary_item_id
  ) then
    return false;
  end if;

  select dll.latitude, dll.longitude, dll.updated_at
  into v_driver_latitude, v_driver_longitude, v_location_updated_at
  from public.driver_live_locations dll
  where dll.driver_id = v_driver_id;
  if not found or v_location_updated_at is null
     or v_location_updated_at < now() - interval '5 minutes' then
    raise exception 'DRIVER_LOCATION_STALE';
  end if;

  v_distance_meters := 6371000 * 2 * asin(sqrt(least(1, greatest(0,
    power(sin(radians(v_driver_latitude - v_stop_latitude) / 2), 2)
    + cos(radians(v_stop_latitude)) * cos(radians(v_driver_latitude))
      * power(sin(radians(v_driver_longitude - v_stop_longitude) / 2), 2)
  ))));
  if v_distance_meters > 150 then
    raise exception 'NOT_WITHIN_ARRIVAL_RADIUS';
  end if;

  insert into public.booking_driver_arrivals(
    booking_driver_id, itinerary_item_id, latitude, longitude
  ) values (
    v_booking_driver_id, p_itinerary_item_id,
    v_driver_latitude, v_driver_longitude
  )
  on conflict do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then return false; end if;

  update public.booking_itinerary_items
  set actual_arrival_time = coalesce(actual_arrival_time, now()),
      spot_status = case when spot_status = 'completed' then spot_status else 'at_spot' end
  where id = p_itinerary_item_id;

  insert into public.notifications(user_id, title, body, type, is_read, dedupe_key)
  select recipient.user_id, 'Destination arrival',
    'Arrived at ' || bii.destination_name, 'itinerary_arrival', false,
    'arrival:' || v_booking_driver_id::text || ':' || p_itinerary_item_id::text || ':' || recipient.user_id::text
  from public.booking_itinerary_items bii
  join public.package_bookings pb on pb.id = bii.booking_id
  cross join lateral (
    select pb.tourist_id as user_id
    union
    select bd.driver_id from public.booking_drivers bd
    where bd.booking_id = pb.id and bd.status = 'accepted'
  ) recipient
  where bii.id = p_itinerary_item_id
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
  return true;
end;
$$;
revoke all on function public.mark_itinerary_stop_arrived(uuid, uuid)
  from public, anon;
grant execute on function public.mark_itinerary_stop_arrived(uuid, uuid)
  to authenticated;

commit;
