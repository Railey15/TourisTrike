-- Notification-only repair. Requires the deployed notification infrastructure.
-- Can be applied as this one SQL file when unrelated migration history is stale.
begin;
do $$ begin
  if to_regclass('public.notification_devices') is null
    or to_regprocedure('public.emit_tour_notification(uuid,uuid,text,text,text,text,boolean,jsonb)') is null then
    raise exception 'Apply the notification_delivery migration first; do not replay unrelated migrations';
  end if;
end $$;

alter table public.notifications add column if not exists in_app_enabled boolean not null default false;
update public.notifications set in_app_enabled = true where push_enabled and not in_app_enabled;
comment on column public.notifications.in_app_enabled is
  'Event is eligible for a foreground banner independently of FCM setup, permission, token, or push delivery.';

-- This legacy policy was found in the actual remote schema, not the local baseline.
-- Keep the existing staff-scoped INSERT policy; clients cannot invent recipient events.
drop policy if exists "Authenticated users can create notifications" on public.notifications;

create or replace function public.emit_tour_notification(
  p_user uuid, p_booking uuid, p_key text, p_type text, p_title text, p_body text,
  p_push boolean default true, p_data jsonb default '{}'::jsonb
) returns void language plpgsql security definer set search_path = public as $$
declare v_created integer;
begin
  if p_user is null then return; end if;
  if p_booking is not null and public.is_developer_test_booking(p_booking) then return; end if;
  insert into public.notifications(user_id,booking_id,dedupe_key,type,title,body,is_read,push_enabled,in_app_enabled,channel,data)
  values(p_user,p_booking,'tour:' || p_key || ':' || p_user,p_type,p_title,p_body,false,
    p_push and public.notification_push_allowed(p_user,p_type),p_push,
    case when p_type = 'emergency_alert' then 'emergency_alerts'
      when p_type like '%payment%' or p_type = 'cash_confirmation_required' then 'payment_updates'
      else 'tour_updates' end,p_data)
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
  get diagnostics v_created = row_count;
  if v_created > 0 then raise log '[NOTIFICATION] Event created: %',p_type; end if;
end $$;

create or replace function public.normalize_tour_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_booking uuid;
begin
  if new.type = 'itinerary_arrival'
    or (new.type = 'booking_cancelled' and new.dedupe_key is null)
    or (new.type = 'emergency' and new.dedupe_key is null) then return null; end if;
  if new.type = 'available_package_job' and new.dedupe_key like 'available_job:%' then
    v_booking := split_part(new.dedupe_key, ':', 2)::uuid;
    if public.is_developer_test_booking(v_booking) then return null; end if;
    new.booking_id := v_booking;
    new.title := 'New Tour Request'; new.body := 'A new tour request is available.';
    new.push_enabled := public.notification_push_allowed(new.user_id,new.type);
    new.in_app_enabled := true;
  end if;
  return new;
end $$;

create or replace function public.notification_device_status(p_installation_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  return jsonb_build_object(
    'registered',exists(select 1 from public.notification_devices where installation_id=p_installation_id
      and user_id=auth.uid() and active and length(token)>20),
    'active_device_count',(select count(*) from public.notification_devices where user_id=auth.uid() and active),
    'platform',(select platform from public.notification_devices where installation_id=p_installation_id and user_id=auth.uid()),
    'updated_at',(select updated_at from public.notification_devices where installation_id=p_installation_id and user_id=auth.uid())
  );
end $$;
revoke all on function public.notification_device_status(uuid) from public,anon;
grant execute on function public.notification_device_status(uuid) to authenticated;
revoke all on function public.emit_tour_notification(uuid,uuid,text,text,text,text,boolean,jsonb),
  public.normalize_tour_notification() from public,anon,authenticated;
commit;
