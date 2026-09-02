-- Automatic, server-authoritative registration for developer test bookings.
-- Only trusted test users who are real booking participants may toggle it.

begin;

create table if not exists public.developer_test_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  label text not null default '',
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.developer_test_users enable row level security;
revoke all on table public.developer_test_users
  from public, anon, authenticated;

-- Existing deliberately allowlisted bookings bootstrap trusted test users, so
-- future bookings can be registered without another manual SQL insert.
insert into public.developer_test_users(user_id, label)
select participant.user_id,
       'Bootstrapped from an existing developer test booking'
from (
  select pb.tourist_id as user_id
  from public.developer_test_bookings dtb
  join public.package_bookings pb on pb.id = dtb.booking_id
  where dtb.enabled and pb.tourist_id is not null

  union

  select bd.driver_id as user_id
  from public.developer_test_bookings dtb
  join public.booking_drivers bd on bd.booking_id = dtb.booking_id
  where dtb.enabled
    and bd.driver_id is not null
    and bd.status in ('accepted', 'completed')
) participant
on conflict (user_id) do nothing;

create or replace function public.is_developer_test_booking(
  p_booking_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.developer_test_bookings dtb
    where dtb.booking_id = p_booking_id
      and dtb.enabled
  );
$$;

revoke all on function public.is_developer_test_booking(uuid)
  from public, anon, authenticated;

create or replace function public.debug_get_test_booking_state(
  p_booking_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_is_participant boolean;
  v_enabled boolean;
begin
  if v_user_id is null then raise exception 'UNAUTHENTICATED'; end if;

  select (
    pb.tourist_id = v_user_id
    or exists (
      select 1
      from public.booking_drivers bd
      where bd.booking_id = pb.id
        and bd.driver_id = v_user_id
        and bd.status in ('accepted', 'completed')
    )
  )
  into v_is_participant
  from public.package_bookings pb
  where pb.id = p_booking_id;

  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if not coalesce(v_is_participant, false) then
    raise exception 'NOT_TEST_BOOKING_PARTICIPANT';
  end if;

  v_enabled := public.is_developer_test_booking(p_booking_id);

  return jsonb_build_object(
    'booking_id', p_booking_id,
    'enabled', v_enabled,
    'server_authoritative', true
  );
end;
$$;

revoke all on function public.debug_get_test_booking_state(uuid)
  from public, anon;
grant execute on function public.debug_get_test_booking_state(uuid)
  to authenticated;

create or replace function public.debug_set_test_booking_mode(
  p_booking_id uuid,
  p_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_booking public.package_bookings;
  v_is_trusted_user boolean;
  v_is_participant boolean;
  v_already_enabled boolean;
begin
  if v_user_id is null then raise exception 'UNAUTHENTICATED'; end if;

  select exists (
    select 1
    from public.developer_test_users dtu
    where dtu.user_id = v_user_id
      and dtu.enabled
  ) into v_is_trusted_user;

  select * into v_booking
  from public.package_bookings pb
  where pb.id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  v_is_participant := v_booking.tourist_id = v_user_id
    or exists (
      select 1
      from public.booking_drivers bd
      where bd.booking_id = p_booking_id
        and bd.driver_id = v_user_id
        and bd.status in ('accepted', 'completed')
    );

  if not v_is_participant then
    raise exception 'NOT_TEST_BOOKING_PARTICIPANT';
  end if;

  v_already_enabled := public.is_developer_test_booking(p_booking_id);

  -- A trusted tester must establish the booking's test state. Once enabled,
  -- every real convoy participant can synchronize the same server state on
  -- their own debug device without becoming globally trusted.
  if not coalesce(v_is_trusted_user, false)
     and not coalesce(v_already_enabled, false) then
    raise exception 'DEVELOPER_TEST_USER_NOT_AUTHORIZED';
  end if;

  if p_enabled then
    if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
       in ('cancelled', 'rejected') then
      raise exception 'CANCELLED_BOOKING_CANNOT_ENABLE_TEST_MODE';
    end if;

    insert into public.developer_test_bookings(
      booking_id, label, enabled, created_by
    ) values (
      p_booking_id, 'Automatically registered by Testing Mode', true, v_user_id
    )
    on conflict (booking_id) do update
    set enabled = true,
        label = excluded.label,
        created_by = coalesce(
          public.developer_test_bookings.created_by,
          excluded.created_by
        );
  else
    update public.developer_test_bookings
    set enabled = false
    where booking_id = p_booking_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'booking_id', p_booking_id,
    'enabled', public.is_developer_test_booking(p_booking_id),
    'server_authoritative', true
  );
end;
$$;

revoke all on function public.debug_set_test_booking_mode(uuid, boolean)
  from public, anon;
grant execute on function public.debug_set_test_booking_mode(uuid, boolean)
  to authenticated;

-- All progression endpoints already funnel authorization through this helper.
create or replace function public.debug_test_driver_assignment(
  p_booking_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_assignment_id uuid;
  v_booking_status text;
begin
  if v_driver_id is null then raise exception 'UNAUTHENTICATED'; end if;

  if not public.is_developer_test_booking(p_booking_id) then
    raise exception 'TEST_BOOKING_NOT_REGISTERED';
  end if;

  select lower(coalesce(pb.booking_status, pb.status, ''))
  into v_booking_status
  from public.package_bookings pb
  where pb.id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking_status in ('cancelled', 'rejected') then
    raise exception 'CANCELLED_BOOKING_CANNOT_ADVANCE';
  end if;

  select bd.id into v_assignment_id
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id
    and bd.driver_id = v_driver_id
    and bd.status in ('accepted', 'completed')
  for update;
  if not found then raise exception 'NOT_TEST_BOOKING_DRIVER'; end if;

  return v_assignment_id;
end;
$$;

revoke all on function public.debug_test_driver_assignment(uuid)
  from public, anon, authenticated;

commit;
