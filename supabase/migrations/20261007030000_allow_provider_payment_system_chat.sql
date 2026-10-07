begin;

-- Verified PayMongo webhooks run as service_role without auth.uid(). Payment
-- confirmation emits a system chat message; that trigger must be able to
-- maintain the booking conversation in the same transaction. Tourist and
-- driver calls still require their own identity and booking membership.
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
  if auth.uid() is null and auth.role() is distinct from 'service_role' then
    raise exception 'UNAUTHENTICATED' using errcode = '42501';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if auth.role() is distinct from 'service_role'
     and not public.is_package_booking_participant(p_booking_id) then
    raise exception 'NOT_BOOKING_PARTICIPANT' using errcode = '42501';
  end if;

  select coalesce(nullif(trim(tp.title), ''), 'Tour Package')
  into v_package_name
  from public.tour_packages tp
  where tp.id = v_booking.package_id;
  v_package_name := coalesce(v_package_name, 'Tour Package');

  select coalesce(
    nullif(trim(p.full_name), ''),
    nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Tourist'
  )
  into v_tourist_name
  from public.profiles p
  where p.id = v_booking.tourist_id;
  v_tourist_name := coalesce(v_tourist_name, 'Tourist');
  v_title := v_package_name || ' - ' || v_tourist_name;

  perform set_config('touristrike.system_conversation_write', 'true', true);
  insert into public.conversations (
    tourist_id, driver_id, booking_id, conversation_type, title
  ) values (
    v_booking.tourist_id, null, p_booking_id, 'booking_group', v_title
  )
  on conflict (booking_id)
    where conversation_type = 'booking_group' and booking_id is not null
  do update set tourist_id = excluded.tourist_id, title = excluded.title
  returning id into v_conversation_id;

  insert into public.conversation_members (
    conversation_id, user_id, member_role
  ) values (
    v_conversation_id, v_booking.tourist_id, 'tourist'
  )
  on conflict do nothing;

  insert into public.conversation_members (
    conversation_id, user_id, member_role
  )
  select v_conversation_id, bd.driver_id, 'driver'
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id
    and bd.status in ('accepted', 'completed')
  on conflict do nothing;
  return v_conversation_id;
end;
$$;

commit;
