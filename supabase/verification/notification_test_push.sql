-- Explicit trusted-backend acceptance test, AFTER real Firebase setup.
-- Run in SQL Editor or: npx supabase db query --linked --file <this file>
-- Set the intended test recipient UUID and a unique key for each device/state.
-- Reusing the same key intentionally creates no duplicate.
do $$
declare
  v_recipient uuid := null; -- Set to the intended signed-in test user.
  v_test_key text := 'replace-with-unique-test-key';
begin
  if v_recipient is null or v_test_key = 'replace-with-unique-test-key' then
    raise exception 'Set an explicit test recipient and unique test key first';
  end if;
  if not exists(select 1 from public.notification_devices
    where user_id=v_recipient and active and platform='android'
      and length(token)>20 and updated_at>now()-interval '60 days') then
    raise exception 'No active registered Android device for this test recipient';
  end if;
  perform public.emit_tour_notification(v_recipient,null,'diagnostic:' || v_test_key,
    'notification_test','TourisTrike Test','Push notifications are configured correctly.',
    true,jsonb_build_object('diagnostic',true));
end $$;
