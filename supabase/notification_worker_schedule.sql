-- Run AFTER deploying send-notifications and configuring the matching Edge secret.
-- Create these secrets in Supabase Vault first (Dashboard > Integrations > Vault):
-- notification_worker_url = https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-notifications
-- notification_worker_secret = same random value as NOTIFICATION_WORKER_SECRET
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

do $$ begin
  if not exists(select 1 from vault.decrypted_secrets where name = 'notification_worker_url')
    or not exists(select 1 from vault.decrypted_secrets where name = 'notification_worker_secret') then
    raise exception 'Configure notification_worker_url and notification_worker_secret in Vault first';
  end if;
end $$;

select cron.schedule('touristrike-notifications', '10 seconds', $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'notification_worker_url' limit 1),
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-notification-secret',(select decrypted_secret from vault.decrypted_secrets where name = 'notification_worker_secret' limit 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 90000
  ) where exists(select 1 from public.notification_deliveries
    where status = 'pending' and available_at <= now() or status = 'sending' and lease_until < now())
  or exists(select 1 from public.notifications n join public.notification_devices d
    on d.user_id = n.user_id and d.active and d.registered_at <= n.created_at
    where n.push_enabled and n.created_at > now() - interval '1 hour'
      and not exists(select 1 from public.notification_deliveries j
        where j.notification_id = n.id::text and j.installation_id = d.installation_id));
$job$);

-- History remains persistent; only terminal delivery attempts are aged out.
select cron.schedule('touristrike-notification-delivery-cleanup', '0 3 * * *', $job$
  delete from public.notification_deliveries
    where status in ('sent','failed','skipped') and created_at < now() - interval '30 days';
$job$);
