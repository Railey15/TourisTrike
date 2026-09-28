-- Separate provincial office identity/branding from per-account preferences.

begin;

create table if not exists public.provincial_office_details (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  province text not null default 'Bulacan',
  office_name text not null default 'Provincial Tourism Office of Bulacan',
  office_address text,
  contact_person text,
  contact_number text,
  official_email text,
  display_name text,
  logo_url text,
  cover_image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.provincial_office_details (
  user_id,
  province,
  office_name,
  office_address,
  contact_person,
  contact_number,
  official_email,
  display_name,
  logo_url,
  cover_image_url
)
select
  p.id,
  coalesce(nullif(trim(p.province), ''), 'Bulacan'),
  coalesce(
    nullif(trim(s.office_name), ''),
    'Provincial Tourism Office of ' ||
      coalesce(nullif(trim(p.province), ''), 'Bulacan')
  ),
  s.office_address,
  coalesce(nullif(trim(s.contact_person), ''), nullif(trim(p.full_name), '')),
  coalesce(nullif(trim(s.contact_number), ''), nullif(trim(p.mobile), '')),
  s.official_email,
  s.display_name,
  s.logo_url,
  s.cover_image_url
from public.profiles p
left join public.admin_settings s on s.user_id = p.id
where p.role = 'main_tenant'
on conflict (user_id) do update set
  province = excluded.province,
  office_name = excluded.office_name,
  office_address = excluded.office_address,
  contact_person = excluded.contact_person,
  contact_number = excluded.contact_number,
  official_email = excluded.official_email,
  display_name = excluded.display_name,
  logo_url = excluded.logo_url,
  cover_image_url = excluded.cover_image_url,
  updated_at = now();

alter table public.provincial_office_details enable row level security;

drop policy if exists provincial_office_select
  on public.provincial_office_details;
create policy provincial_office_select on public.provincial_office_details
for select to authenticated
using (
  (user_id = auth.uid() and public.is_main_tenant())
  or public.is_system_administrator()
);

drop policy if exists provincial_office_insert
  on public.provincial_office_details;
create policy provincial_office_insert on public.provincial_office_details
for insert to authenticated
with check (user_id = auth.uid() and public.is_main_tenant());

drop policy if exists provincial_office_update
  on public.provincial_office_details;
create policy provincial_office_update on public.provincial_office_details
for update to authenticated
using (user_id = auth.uid() and public.is_main_tenant())
with check (user_id = auth.uid() and public.is_main_tenant());

create or replace function public.guard_provincial_office_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assigned_province text;
begin
  if tg_op = 'INSERT' then
    select coalesce(nullif(btrim(p.province), ''), 'Bulacan')
    into v_assigned_province
    from public.profiles p
    where p.id = new.user_id and p.role = 'main_tenant';

    if not found then
      raise exception 'MAIN_TENANT_PROFILE_REQUIRED' using errcode = '42501';
    end if;

    new.province := v_assigned_province;
  elsif new.user_id is distinct from old.user_id
     or new.province is distinct from old.province then
    raise exception 'PROVINCIAL_OFFICE_SCOPE_IS_READ_ONLY'
      using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists guard_provincial_office_scope
  on public.provincial_office_details;
create trigger guard_provincial_office_scope
before insert or update on public.provincial_office_details
for each row execute function public.guard_provincial_office_scope();

-- The migrated columns no longer belong in per-user preference storage.
alter table public.admin_settings
  drop column if exists office_name,
  drop column if exists office_address,
  drop column if exists contact_person,
  drop column if exists contact_number,
  drop column if exists official_email,
  drop column if exists display_name,
  drop column if exists logo_url,
  drop column if exists cover_image_url;

create or replace function public.enforce_main_tenant_required_settings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.profiles p
    where p.id = new.user_id and p.role = 'main_tenant'
  ) then
    new.system_notices := true;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_provincial_admin_required_settings
  on public.admin_settings;
drop trigger if exists enforce_main_tenant_required_settings
  on public.admin_settings;
create trigger enforce_main_tenant_required_settings
before insert or update on public.admin_settings
for each row execute function public.enforce_main_tenant_required_settings();

create or replace function public.main_tenant_notification_allowed(
  p_user uuid,
  p_type text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when coalesce(p_type, '') in (
      'emergency_alert', 'system_security', 'security_alert', 'system_notice'
    ) then true
    when p_type = 'city_admin_application_received' then
      coalesce(s.city_application_notifications, true)
    when p_type = 'driver_status_update' then
      coalesce(s.driver_status_notifications, true)
    when p_type in ('cancellation_review', 'booking_issue') then
      coalesce(s.booking_issue_notifications, true)
    when p_type = 'payment_dispute_opened' then
      coalesce(s.payment_dispute_notifications, true)
    else true
  end
  from (select 1) seed
  left join public.admin_settings s on s.user_id = p_user;
$$;

create or replace function public.apply_main_tenant_notification_preference()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_allowed boolean;
begin
  if exists (
    select 1 from public.profiles p
    where p.id = new.user_id and p.role = 'main_tenant'
  ) then
    v_allowed := public.main_tenant_notification_allowed(new.user_id, new.type);
    new.push_enabled := v_allowed;
    new.in_app_enabled := v_allowed;
    new.channel := case
      when new.type = 'emergency_alert' then 'emergency_alerts'
      when new.type = 'payment_dispute_opened' then 'payment_updates'
      else 'admin_updates'
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists zz_provincial_admin_notification_preference
  on public.notifications;
drop trigger if exists zz_main_tenant_notification_preference
  on public.notifications;
create trigger zz_main_tenant_notification_preference
before insert on public.notifications
for each row execute function public.apply_main_tenant_notification_preference();

create or replace function public.notify_main_tenants(
  p_type text,
  p_title text,
  p_body text,
  p_dedupe_key text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (
    user_id, title, body, type, is_read, dedupe_key
  )
  select p.id, p_title, p_body, p_type, false,
    p_dedupe_key || ':' || p.id::text
  from public.profiles p
  where p.role = 'main_tenant'
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
$$;

create or replace function public.notify_main_tenant_city_application()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.notify_main_tenants(
    'city_admin_application_received',
    'New city account application',
    coalesce(new.office_name, new.city) || ' submitted an application for review.',
    'main-tenant:city-application:' || new.id::text
  );
  return new;
end;
$$;

drop trigger if exists notify_admin_city_application
  on public.city_tenant_registrations;
drop trigger if exists notify_main_tenant_city_application
  on public.city_tenant_registrations;
create trigger notify_main_tenant_city_application
after insert on public.city_tenant_registrations
for each row execute function public.notify_main_tenant_city_application();

create or replace function public.notify_main_tenant_driver_status()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    perform public.notify_main_tenants(
      'driver_status_update',
      'Driver accreditation update',
      'A driver application in ' || coalesce(new.city, 'an assigned municipality') ||
        ' is now ' || coalesce(new.status, 'pending') || '.',
      'main-tenant:driver-status:' || new.id::text || ':' ||
        coalesce(new.status, 'pending')
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notify_admin_driver_status on public.driver_applications;
drop trigger if exists notify_main_tenant_driver_status
  on public.driver_applications;
create trigger notify_main_tenant_driver_status
after insert or update of status on public.driver_applications
for each row execute function public.notify_main_tenant_driver_status();

create or replace function public.notify_main_tenant_payment_dispute()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.notify_main_tenants(
    'payment_dispute_opened',
    'Payment dispute opened',
    'A payment dispute requires administrative review.',
    'main-tenant:payment-dispute:' || new.id::text
  );
  return new;
end;
$$;

drop trigger if exists notify_admin_payment_dispute on public.payment_disputes;
drop trigger if exists notify_main_tenant_payment_dispute
  on public.payment_disputes;
create trigger notify_main_tenant_payment_dispute
after insert on public.payment_disputes
for each row execute function public.notify_main_tenant_payment_dispute();

create or replace function public.notify_main_tenant_emergency_alert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.notify_main_tenants(
    'emergency_alert',
    'Emergency alert',
    'An active trip emergency requires immediate attention.',
    'main-tenant:emergency:' || new.id::text
  );
  return new;
end;
$$;

drop trigger if exists notify_admin_emergency_alert on public.emergency_alerts;
drop trigger if exists notify_main_tenant_emergency_alert
  on public.emergency_alerts;
create trigger notify_main_tenant_emergency_alert
after insert on public.emergency_alerts
for each row execute function public.notify_main_tenant_emergency_alert();

create or replace function public.notify_main_tenant_booking_cancellation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if lower(coalesce(new.status, '')) = 'cancelled'
     and lower(coalesce(old.status, '')) <> 'cancelled' then
    perform public.notify_main_tenants(
      'cancellation_review',
      'Booking cancellation recorded',
      'A booking cancellation may require provincial review.',
      'main-tenant:booking-cancellation:' || new.id::text
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notify_main_tenant_booking_cancellation
  on public.package_bookings;
create trigger notify_main_tenant_booking_cancellation
after update of status on public.package_bookings
for each row execute function public.notify_main_tenant_booking_cancellation();

-- Notification emitters are trigger internals, not public RPC endpoints.
revoke all on function public.notify_main_tenants(text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.main_tenant_notification_allowed(uuid, text)
  from public, anon, authenticated;
revoke all on function public.notify_provincial_admins(text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.provincial_admin_notification_allowed(uuid, text)
  from public, anon, authenticated;

commit;
