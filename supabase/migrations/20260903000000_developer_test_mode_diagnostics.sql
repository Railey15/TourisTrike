-- Read-only diagnostics for comparing Testing Mode identity and authorization
-- between debug installations. The result contains no tokens, keys, secrets,
-- or other users' identifiers.

begin;

create or replace function public.debug_get_test_mode_diagnostics(
  p_booking_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile_id uuid;
  v_profile_role text;
  v_is_trusted_user boolean := false;
  v_booking_found boolean := false;
  v_is_participant boolean := false;
  v_booking_enabled boolean := false;
begin
  if v_user_id is null then raise exception 'UNAUTHENTICATED'; end if;

  select p.id, p.role
  into v_profile_id, v_profile_role
  from public.profiles p
  where p.id = v_user_id;

  select exists (
    select 1
    from public.developer_test_users dtu
    where dtu.user_id = v_user_id
      and dtu.enabled
  ) into v_is_trusted_user;

  if p_booking_id is not null then
    select exists (
      select 1
      from public.package_bookings pb
      where pb.id = p_booking_id
    ) into v_booking_found;

    select exists (
      select 1
      from public.package_bookings pb
      where pb.id = p_booking_id
        and (
          pb.tourist_id = v_user_id
          or exists (
            select 1
            from public.booking_drivers bd
            where bd.booking_id = pb.id
              and bd.driver_id = v_user_id
              and bd.status in ('accepted', 'completed')
          )
        )
    ) into v_is_participant;

    v_booking_enabled := public.is_developer_test_booking(p_booking_id);
  end if;

  return jsonb_build_object(
    'server_auth_user_id', v_user_id,
    'profile_user_id', v_profile_id,
    'profile_role', v_profile_role,
    'tester_allowlist_enabled', v_is_trusted_user,
    'booking_found', v_booking_found,
    'booking_participant', v_is_participant,
    'booking_test_mode_enabled', v_booking_enabled,
    'authorization_allowed',
      v_is_participant and (v_is_trusted_user or v_booking_enabled)
  );
end;
$$;

revoke all on function public.debug_get_test_mode_diagnostics(uuid)
  from public, anon;
grant execute on function public.debug_get_test_mode_diagnostics(uuid)
  to authenticated;

commit;
