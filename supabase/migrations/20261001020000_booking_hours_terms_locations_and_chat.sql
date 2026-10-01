begin;

-- New bookings use the municipality's local clock. Existing schedules are untouched.
create or replace function public.guard_tour_pickup_hours()
returns trigger language plpgsql set search_path = '' as $$
declare v_local time;
begin
  if new.scheduled_start_at is null then return new; end if;
  v_local := (new.scheduled_start_at at time zone 'Asia/Manila')::time;
  if v_local < time '05:00' or v_local >= time '17:00' then
    raise exception 'PICKUP_OUTSIDE_ALLOWED_HOURS';
  end if;
  return new;
end $$;
drop trigger if exists guard_tour_pickup_hours on public.package_bookings;
create trigger guard_tour_pickup_hours
before insert or update of scheduled_start_at on public.package_bookings
for each row execute function public.guard_tour_pickup_hours();

-- A confirmed booking has fixed endpoints for a tourist, including direct
-- table writes. Existing privileged office/support lifecycle paths are retained.
create or replace function public.guard_booked_endpoints()
returns trigger language plpgsql set search_path = '' as $$
begin
  if auth.uid() is not null and public.current_profile_role() = 'tourist'
    and (new.pickup_address,new.pickup_latitude,new.pickup_longitude,
      new.pickup_province,new.pickup_locality,new.pickup_country_code,
      new.dropoff_address,new.dropoff_latitude,new.dropoff_longitude,
      new.dropoff_province,new.dropoff_locality,new.dropoff_country_code)
      is distinct from
      (old.pickup_address,old.pickup_latitude,old.pickup_longitude,
      old.pickup_province,old.pickup_locality,old.pickup_country_code,
      old.dropoff_address,old.dropoff_latitude,old.dropoff_longitude,
      old.dropoff_province,old.dropoff_locality,old.dropoff_country_code) then
    raise exception 'BOOKED_ENDPOINTS_IMMUTABLE';
  end if;
  return new;
end $$;
drop trigger if exists guard_booked_endpoints on public.package_bookings;
create trigger guard_booked_endpoints before update on public.package_bookings
for each row execute function public.guard_booked_endpoints();

-- Keep the existing atomic booking RPC and acceptance timestamp. Only the
-- displayed terms version changes.
create or replace function public.stamp_booking_terms()
returns trigger language plpgsql set search_path = '' as $$
declare v_version text := current_setting('touristrike.booking_terms_version', true);
begin
  if v_version is distinct from '1.1' or new.tourist_id is distinct from auth.uid() then
    raise exception 'BOOKING_TERMS_REQUIRED';
  end if;
  new.terms_version := v_version;
  new.terms_accepted_at := now();
  return new;
end $$;
create or replace function public.create_package_booking(
  p_booking jsonb, p_customized_spots jsonb default '[]'::jsonb,
  p_itinerary_items jsonb default '[]'::jsonb
) returns public.package_bookings language plpgsql security definer set search_path = '' as $$
declare v_booking public.package_bookings;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_booking->>'terms_version' is distinct from '1.1' then
    raise exception 'BOOKING_TERMS_REQUIRED';
  end if;
  perform set_config('touristrike.booking_terms_version', '1.1', true);
  select * into v_booking from public.create_package_booking_accepted_terms_impl(
    p_booking, p_customized_spots, p_itinerary_items);
  return v_booking;
end $$;
revoke all on function public.create_package_booking(jsonb,jsonb,jsonb) from public,anon;
grant execute on function public.create_package_booking(jsonb,jsonb,jsonb) to authenticated;

-- Censor whole words and obvious punctuation-separated variants. Preserve URL
-- tokens verbatim so links continue to work. The original text is never stored.
create or replace function public.censor_chat_text(p_text text)
returns text language plpgsql immutable set search_path = '' as $$
declare v_token text; v_result text := ''; v_match text[];
begin
  if p_text is null then return null; end if;
  for v_match in select regexp_matches(p_text, '(\s+|\S+)', 'g') loop
    v_token := v_match[1];
    if v_token !~* '^(https?://|www\.)' then
      v_token := regexp_replace(v_token,
        '\m(f[[:punct:]]*u[[:punct:]]*c[[:punct:]]*k|s[[:punct:]]*h[[:punct:]]*i[[:punct:]]*t|b[[:punct:]]*i[[:punct:]]*t[[:punct:]]*c[[:punct:]]*h)\M',
        '****', 'gi');
    end if;
    v_result := v_result || v_token;
  end loop;
  return v_result;
end $$;
create or replace function public.censor_user_message()
returns trigger language plpgsql set search_path = '' as $$
begin
  if coalesce(new.message_type,'user') = 'user' then
    new.message_text := public.censor_chat_text(new.message_text);
  end if;
  return new;
end $$;
drop trigger if exists censor_user_message on public.messages;
create trigger censor_user_message before insert or update of message_text
on public.messages for each row execute function public.censor_user_message();
create or replace function public.censor_conversation_preview()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.last_message := public.censor_chat_text(new.last_message);
  return new;
end $$;
drop trigger if exists censor_conversation_preview on public.conversations;
create trigger censor_conversation_preview before insert or update of last_message
on public.conversations for each row execute function public.censor_conversation_preview();

-- The existing sender checks membership and client-id idempotency. Pass it
-- normalized text so an idempotent retry compares against the censored row.
do $$ begin
  if to_regprocedure('public.send_conversation_message_impl(uuid,text,uuid)') is null then
    alter function public.send_conversation_message(uuid,text,uuid)
      rename to send_conversation_message_impl;
  end if;
end $$;
revoke all on function public.send_conversation_message_impl(uuid,text,uuid)
from public,anon,authenticated;
create or replace function public.send_conversation_message(
  p_conversation_id uuid,p_message_text text,p_client_message_id uuid)
returns public.messages language plpgsql security definer set search_path = '' as $$
begin
  return public.send_conversation_message_impl(
    p_conversation_id, public.censor_chat_text(p_message_text),p_client_message_id);
end $$;
revoke all on function public.send_conversation_message(uuid,text,uuid) from public,anon;
grant execute on function public.send_conversation_message(uuid,text,uuid) to authenticated;

commit;
