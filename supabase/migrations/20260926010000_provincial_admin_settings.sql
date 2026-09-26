-- Provincial Admin Settings extends the existing per-user admin_settings row.
-- Existing tourism_policies, package_cancellation_policy, profiles, and the
-- public-assets bucket remain the authoritative sources for their domains.

begin;

alter table public.admin_settings
  add column if not exists office_name text,
  add column if not exists office_address text,
  add column if not exists contact_person text,
  add column if not exists contact_number text,
  add column if not exists official_email text,
  add column if not exists display_name text,
  add column if not exists logo_url text,
  add column if not exists cover_image_url text,
  add column if not exists city_application_notifications boolean not null default true,
  add column if not exists driver_status_notifications boolean not null default true,
  add column if not exists booking_issue_notifications boolean not null default true,
  add column if not exists payment_dispute_notifications boolean not null default true;

-- Settings rows are account preferences. A Provincial Admin does not need to
-- edit another tenant's preferences merely because the role can administer
-- operational data.
drop policy if exists own_settings on public.admin_settings;
create policy own_settings on public.admin_settings
for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Role and tenant scope cannot be changed through a self-profile update. This
-- leaves the existing admin activation workflow intact because it updates a
-- different user's row.
create or replace function public.protect_own_profile_scope()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() = old.id and coalesce(auth.role(), '') <> 'service_role' then
    if new.role is distinct from old.role
      or new.city is distinct from old.city
      or new.province is distinct from old.province then
      raise exception 'ROLE_AND_TENANT_SCOPE_ARE_READ_ONLY';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_own_profile_scope on public.profiles;
create trigger protect_own_profile_scope
before update on public.profiles
for each row execute function public.protect_own_profile_scope();

-- Critical Provincial Admin notices stay enabled even if a crafted client
-- bypasses the Flutter controls.
create or replace function public.enforce_provincial_admin_required_settings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.profiles p
    where p.id = new.user_id and p.role = 'admin'
  ) then
    new.system_notices := true;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_provincial_admin_required_settings
  on public.admin_settings;
create trigger enforce_provincial_admin_required_settings
before insert or update on public.admin_settings
for each row execute function public.enforce_provincial_admin_required_settings();

-- Preferences suppress push and foreground banners, while durable notification
-- history remains available in the notification center.
create or replace function public.provincial_admin_notification_allowed(
  p_user uuid,
  p_type text
)
returns boolean
language sql
stable
security definer
set search_path = public
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

create or replace function public.apply_provincial_admin_notification_preference()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allowed boolean;
begin
  if exists (
    select 1 from public.profiles p
    where p.id = new.user_id and p.role = 'admin'
  ) then
    v_allowed := public.provincial_admin_notification_allowed(
      new.user_id,
      new.type
    );
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
create trigger zz_provincial_admin_notification_preference
before insert on public.notifications
for each row execute function public.apply_provincial_admin_notification_preference();

create or replace function public.notify_provincial_admins(
  p_type text,
  p_title text,
  p_body text,
  p_dedupe_key text
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (
    user_id, title, body, type, is_read, dedupe_key
  )
  select p.id, p_title, p_body, p_type, false,
    p_dedupe_key || ':' || p.id::text
  from public.profiles p
  where p.role = 'admin'
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
$$;

create or replace function public.notify_admin_city_application()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.notify_provincial_admins(
    'city_admin_application_received',
    'New city account application',
    coalesce(new.office_name, new.city) || ' submitted an application for review.',
    'provincial:city-application:' || new.id::text
  );
  return new;
end;
$$;

drop trigger if exists notify_admin_city_application
  on public.city_tenant_registrations;
create trigger notify_admin_city_application
after insert on public.city_tenant_registrations
for each row execute function public.notify_admin_city_application();

create or replace function public.notify_admin_driver_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    perform public.notify_provincial_admins(
      'driver_status_update',
      'Driver accreditation update',
      'A driver application in ' || coalesce(new.city, 'an assigned municipality') ||
        ' is now ' || coalesce(new.status, 'pending') || '.',
      'provincial:driver-status:' || new.id::text || ':' || coalesce(new.status, 'pending')
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notify_admin_driver_status on public.driver_applications;
create trigger notify_admin_driver_status
after insert or update of status on public.driver_applications
for each row execute function public.notify_admin_driver_status();

create or replace function public.notify_admin_payment_dispute()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.notify_provincial_admins(
    'payment_dispute_opened',
    'Payment dispute opened',
    'A payment dispute requires administrative review.',
    'provincial:payment-dispute:' || new.id::text
  );
  return new;
end;
$$;

drop trigger if exists notify_admin_payment_dispute on public.payment_disputes;
create trigger notify_admin_payment_dispute
after insert on public.payment_disputes
for each row execute function public.notify_admin_payment_dispute();

create or replace function public.notify_admin_emergency_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.notify_provincial_admins(
    'emergency_alert',
    'Emergency alert',
    'An active trip emergency requires immediate attention.',
    'provincial:emergency:' || new.id::text
  );
  return new;
end;
$$;

drop trigger if exists notify_admin_emergency_alert on public.emergency_alerts;
create trigger notify_admin_emergency_alert
after insert on public.emergency_alerts
for each row execute function public.notify_admin_emergency_alert();

commit;
