-- Apply manually after deploying send-transactional-emails and configuring:
-- Edge: TRANSACTIONAL_EMAIL_WORKER_SECRET, RESEND_API_KEY, FROM_EMAIL.
-- Vault: transactional_email_worker_url = function URL;
--        transactional_email_worker_secret = same worker secret.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

do $$ begin
  if not exists(select 1 from vault.decrypted_secrets
      where name = 'transactional_email_worker_url')
     or not exists(select 1 from vault.decrypted_secrets
      where name = 'transactional_email_worker_secret') then
    raise exception 'Configure transactional email worker Vault secrets first';
  end if;
end $$;

select cron.schedule('touristrike-transactional-emails', '* * * * *', $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets
      where name = 'transactional_email_worker_url' limit 1),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-transactional-email-secret',
      (select decrypted_secret from vault.decrypted_secrets
        where name = 'transactional_email_worker_secret' limit 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 90000
  ) where exists(select 1 from public.transactional_email_outbox
    where (status = 'pending' and next_attempt_at <= now())
       or (status = 'leased' and lease_until < now()));
$job$);
