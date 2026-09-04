-- Authorize the intended tourist QA auth account for server-side Testing Mode.
-- The UUID is the authority; the email assertion prevents this migration from
-- silently authorizing an unrelated UUID if it is run against another project.

begin;

do $$
begin
  if not exists (
    select 1
    from auth.users u
    where u.id = '9c7091f5-8797-4e72-a85d-585d65b3b312'::uuid
      and lower(u.email) = 'tourist1@gmail.com'
  ) then
    raise exception 'EXPECTED_TOURIST_TEST_ACCOUNT_NOT_FOUND';
  end if;

  insert into public.developer_test_users(user_id, label, enabled)
  values (
    '9c7091f5-8797-4e72-a85d-585d65b3b312'::uuid,
    'TourisTrike tourist QA account',
    true
  )
  on conflict (user_id) do update
  set label = excluded.label,
      enabled = true;
end;
$$;

commit;
