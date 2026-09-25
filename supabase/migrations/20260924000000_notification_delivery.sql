-- Notification-only observers: existing journey/payment RPCs remain authoritative.
begin;

alter table public.notifications
  add column if not exists booking_id uuid references public.package_bookings(id) on delete set null,
  add column if not exists data jsonb not null default '{}'::jsonb,
  add column if not exists read_at timestamptz,
  add column if not exists push_enabled boolean not null default false,
  add column if not exists channel text not null default 'tour_updates';

-- History is private, including from other staff accounts. Only read state is editable.
drop policy if exists own_notifications on public.notifications;
create policy own_notifications on public.notifications for select to authenticated
  using (user_id = auth.uid());
revoke update on public.notifications from authenticated, anon;
grant update (is_read, read_at) on public.notifications to authenticated;
-- Staff can still create ordinary center messages, but only trusted functions
-- may select push delivery, routing metadata, or a deduplication identity.
revoke insert on public.notifications from authenticated, anon;
grant insert (user_id,title,body,type,is_read) on public.notifications to authenticated;

create table public.notification_devices (
  installation_id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null default 'android' check (platform = 'android'),
  registered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  active boolean not null default true
);
alter table public.notification_devices enable row level security;
revoke all on public.notification_devices from anon, authenticated;

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  -- Existing installations have both UUID and bigint notification primary keys.
  notification_id text not null,
  installation_id uuid not null references public.notification_devices on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  token text not null,
  status text not null default 'pending' check (status in ('pending','sending','sent','failed','skipped')),
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  lease_id uuid,
  lease_until timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique (notification_id, installation_id)
);
create index notification_delivery_pending on public.notification_deliveries(available_at)
  where status in ('pending','sending');
alter table public.notification_deliveries enable row level security;
revoke all on public.notification_deliveries from anon, authenticated;
grant all on public.notification_devices, public.notification_deliveries to service_role;

create or replace function public.register_notification_device(p_installation_id uuid, p_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if length(p_token) not between 20 and 4096 then raise exception 'INVALID_TOKEN'; end if;
  -- A refreshed token or account switch replaces the binding on this installation.
  delete from public.notification_devices where token = p_token and installation_id <> p_installation_id;
  insert into public.notification_devices(installation_id,user_id,token)
    values(p_installation_id,auth.uid(),p_token)
  on conflict (installation_id) do update set user_id = auth.uid(), token = excluded.token,
    registered_at = case when notification_devices.user_id = auth.uid() then notification_devices.registered_at else now() end,
    active = true, updated_at = now();
end $$;
create or replace function public.unregister_notification_device(p_installation_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.notification_devices set active = false, updated_at = now()
    where installation_id = p_installation_id and user_id = auth.uid();
$$;

-- Some deployed installations have the profile screen's legacy preferences
-- table (it is absent from the checked-in baseline). Respect existing opt-outs.
create or replace function public.notification_push_allowed(p_user uuid,p_type text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_settings jsonb; v_key text;
begin
  if p_type = 'emergency_alert' then return true; end if;
  if to_regclass('public.notification_settings') is null then return true; end if;
  execute 'select to_jsonb(s) from public.notification_settings s where tourist_id = $1'
    into v_settings using p_user;
  v_key := case when p_type like '%payment%' or p_type = 'cash_confirmation_required' then 'payment_updates'
    when p_type like 'driver%' or p_type in ('heading_to_spot','spot_arrived','heading_dropoff','arrived_dropoff','convoy_ready','tour_started') then 'driver_updates'
    else 'booking_updates' end;
  return coalesce((v_settings->>v_key)::boolean,true);
end $$;

create or replace function public.emit_tour_notification(
  p_user uuid, p_booking uuid, p_key text, p_type text, p_title text, p_body text,
  p_push boolean default true, p_data jsonb default '{}'::jsonb
) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user is null then return; end if;
  -- Developer simulations are never real push events.
  if p_booking is not null and public.is_developer_test_booking(p_booking) then return; end if;
  insert into public.notifications(user_id,booking_id,dedupe_key,type,title,body,is_read,push_enabled,channel,data)
  values(p_user,p_booking,'tour:' || p_key || ':' || p_user,p_type,p_title,p_body,false,
    p_push and public.notification_push_allowed(p_user,p_type),
    case when p_type = 'emergency_alert' then 'emergency_alerts'
      when p_type like '%payment%' or p_type = 'cash_confirmation_required' then 'payment_updates'
      else 'tour_updates' end,p_data)
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
end $$;

-- Neutralize only legacy notification inserts now owned by the observers below.
-- No existing business function, GPS guard, email, or transaction is rewritten.
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
    new.title := 'New Tour Request';
    new.body := 'A new tour request is available.';
    new.push_enabled := public.notification_push_allowed(new.user_id,new.type);
  end if;
  return new;
end $$;
create trigger notification_normalize before insert on public.notifications
  for each row execute function public.normalize_tour_notification();

-- Let automatic developer-test registration finish before dispatch notifications
-- are evaluated. Recipient selection in the existing function is unchanged.
create or replace function public.notify_drivers_of_available_booking()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_developer_test_booking(new.id) then return new; end if;
  insert into public.notifications(user_id,title,body,type,is_read,dedupe_key)
  select p.id,'New Tour Request','A new tour request is available.','available_package_job',false,
    'available_job:' || new.id::text || ':' || p.id::text
  from public.profiles p where p.role = 'driver'
    and (coalesce(p.is_online,false) or coalesce(p.is_available,false))
    and lower(trim(coalesce(p.city,''))) = lower(trim(coalesce(new.municipality,'')))
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
  return new;
exception when others then raise warning 'Job notification failed [%]',sqlstate; return new;
end $$;
drop trigger if exists trg_notify_available_package_job on public.package_bookings;
create constraint trigger trg_notify_available_package_job after insert on public.package_bookings
  deferrable initially deferred for each row execute function public.notify_drivers_of_available_booking();

create or replace function public.enqueue_notification_delivery()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.push_enabled then
    insert into public.notification_deliveries(notification_id,installation_id,recipient_id,token)
    select new.id::text,d.installation_id,new.user_id,d.token from public.notification_devices d
    where d.user_id = new.user_id and d.active and d.updated_at > now() - interval '60 days'
    on conflict do nothing;
  end if;
  return new;
exception when others then
  raise warning 'Notification push enqueue failed [%]', sqlstate;
  return new;
end $$;
create trigger notification_enqueue after insert on public.notifications
  for each row execute function public.enqueue_notification_delivery();

create or replace function public.observe_booking_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_type text; v_title text; v_body text; v_status text; v_driver record;
begin
  if tg_op = 'INSERT' then
    perform public.emit_tour_notification(new.tourist_id,new.id,new.id || ':submitted',
      'booking_submitted','Booking Submitted','Your tour booking has been submitted.',false);
    return new;
  end if;
  v_status := lower(coalesce(new.booking_status,new.status));
  if new.status is not distinct from old.status and new.booking_status is not distinct from old.booking_status then
    if new.status in ('cancelled','rejected','completed') then return new; end if;
    -- A schedule edit is a meaningful change; coordinates/ETA never reach this observer.
    if new.scheduled_start_at is distinct from old.scheduled_start_at then
      perform public.emit_tour_notification(new.tourist_id,new.id,new.id || ':schedule:' || new.scheduled_start_at,
        'schedule_changed','Tour Schedule Updated','Your tour schedule has changed. Check your booking for details.');
      for v_driver in select driver_id from public.required_booking_driver_roster(new.id) loop
        perform public.emit_tour_notification(v_driver.driver_id,new.id,new.id || ':schedule:' || new.scheduled_start_at,
          'schedule_changed','Tour Schedule Updated','The schedule for your assigned tour has changed.');
      end loop;
    end if;
    return new;
  end if;
  if v_status in ('cancelled','rejected') or new.status in ('cancelled','rejected') then
    v_type := 'booking_cancelled'; v_title := 'Booking Cancelled'; v_body := 'Your tour booking has been cancelled.';
  elsif v_status in ('completed','done') then
    v_type := 'tour_completed'; v_title := 'Tour Completed';
    v_body := 'Your TourisTrike trip has been completed. Thank you for riding with us.';
  elsif v_status = 'awaiting_remaining_payment' then
    v_type := 'remaining_payment_required'; v_title := 'Remaining Balance Due';
    v_body := 'Complete your remaining payment to continue to drop-off.';
  elsif v_status = 'approved' or new.status = 'approved' then
    v_type := 'booking_approved'; v_title := 'Booking Approved'; v_body := 'Your tour booking has been approved.';
  else return new;
  end if;
  perform public.emit_tour_notification(new.tourist_id,new.id,new.id || ':' || v_type,v_type,v_title,v_body);
  if v_type = 'booking_cancelled' then
    for v_driver in select distinct driver_id from public.booking_drivers where booking_id = new.id
      and (accepted_at is not null or status in ('accepted','completed')) loop
      perform public.emit_tour_notification(v_driver.driver_id,new.id,new.id || ':' || v_type,
        v_type,v_title,'A tour assigned to you has been cancelled.');
    end loop;
  end if;
  return new;
exception when others then raise warning 'Booking notification failed [%]', sqlstate; return new;
end $$;
create trigger notification_booking after update of status,booking_status,scheduled_start_at
  on public.package_bookings for each row execute function public.observe_booking_notification();
create constraint trigger notification_booking_created after insert on public.package_bookings
  deferrable initially deferred for each row execute function public.observe_booking_notification();

create or replace function public.observe_driver_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare b public.package_bookings; v_count integer; v_total integer; v_required integer;
  v_key text; v_type text; v_title text; v_body text; v_push boolean := true; v_item record; r record;
begin
  select * into b from public.package_bookings where id = new.booking_id;
  if not found or b.status in ('cancelled','rejected','completed') then return new; end if;
  v_required := greatest(coalesce(b.required_drivers,1),1);
  select count(*) into v_total from public.required_booking_driver_roster(b.id);
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    if new.status = 'pending' then
      perform public.emit_tour_notification(new.driver_id,b.id,new.id || ':assigned',
        'tour_assigned','Tour Assigned','You have been assigned to a tour.');
    elsif new.status = 'accepted' and v_total >= v_required then
      perform public.emit_tour_notification(b.tourist_id,b.id,b.id || ':drivers_assigned',
        'drivers_assigned',case when v_required > 1 then 'Drivers Assigned' else 'Driver Assigned' end,
        format('%s driver%s assigned to your tour.',v_total,case when v_total > 1 then 's are' else ' is' end),false);
      perform public.emit_tour_notification(b.tourist_id,b.id,b.id || ':confirmed','booking_confirmed',
        case when v_required > 1 then 'Your Drivers Are Ready' else 'Your Tour Is Confirmed' end,
        'All required drivers have accepted your tour.');
    elsif new.status in ('cancelled','rejected') and tg_op = 'UPDATE' and old.status = 'accepted' then
      perform public.emit_tour_notification(b.tourist_id,b.id,new.id || ':released',
        'driver_changed','Driver Assignment Changed','Your driver roster has changed. Check your booking for details.');
    end if;
  end if;
  if tg_op = 'INSERT' or new.journey_state is not distinct from old.journey_state
    or new.status not in ('accepted','completed') then return new; end if;
  v_key := b.id || ':' || new.journey_state;
  if new.journey_state in ('en_route_pickup','at_pickup','boarded','en_route_dropoff','at_dropoff') then
    select count(*) into v_count from public.required_booking_driver_roster(b.id) d
      where public.journey_state_order(d.journey_state) >= public.journey_state_order(new.journey_state);
    if new.journey_state = 'at_pickup' and (v_count < v_required or v_count < v_total) then
      perform public.emit_tour_notification(b.tourist_id,b.id,v_key || ':partial:' || new.id,
        'driver_arrived','Driver Arrived',format('%s of %s drivers have arrived at the pickup point.',v_count,greatest(v_total,v_required)),false);
      return new;
    end if;
    if v_total < v_required or v_count < v_total then return new; end if;
    case new.journey_state
      when 'en_route_pickup' then
        v_type := 'driver_on_the_way'; v_title := case when v_required > 1 then 'Drivers On the Way' else 'Driver On the Way' end;
        v_body := case when v_required > 1 then 'Your drivers are heading to the pickup point.' else 'Your driver is heading to the pickup point.' end;
      when 'at_pickup' then
        v_type := 'drivers_arrived'; v_title := case when v_required > 1 then 'All Drivers Arrived' else 'Driver Arrived' end;
        v_body := case when v_required > 1 then 'All drivers are now at the pickup point.' else 'Your driver has arrived at the pickup point.' end;
      when 'boarded' then v_type := 'tour_started'; v_title := 'Tour Started'; v_body := 'You have been picked up. Your tour is now underway.';
      when 'en_route_dropoff' then v_type := 'heading_dropoff'; v_title := 'Heading to Drop-off'; v_body := 'Your driver is taking you to the drop-off point.';
      when 'at_dropoff' then v_type := 'arrived_dropoff'; v_title := 'Arrived at Drop-off'; v_body := 'You have arrived at your drop-off point.';
    end case;
  elsif new.journey_state in ('en_route_stop','at_stop','stop_done') then
    select id,destination_name into v_item from public.booking_itinerary_items where booking_id = b.id
      order by coalesce(order_number,2147483647),coalesce(destination_order,2147483647),arrival_time nulls last,created_at,id
      offset new.current_stop_index limit 1;
    if not found then return new; end if;
    v_key := b.id || ':spot:' || v_item.id || ':' || new.journey_state;
    select count(*) into v_count from public.required_booking_driver_roster(b.id) d where
      d.current_stop_index > new.current_stop_index or (d.current_stop_index = new.current_stop_index
        and public.journey_state_order(d.journey_state) >= public.journey_state_order(new.journey_state));
    if v_total < v_required or v_count < v_total then return new; end if;
    if new.journey_state = 'stop_done' then
      if v_required > 1 then
        for r in select driver_id from public.required_booking_driver_roster(b.id) where driver_id <> new.driver_id loop
          perform public.emit_tour_notification(r.driver_id,b.id,v_key,'convoy_ready','Convoy Ready',
            'All drivers are ready to continue.');
        end loop;
      end if;
      return new; -- No redundant tourist "spot completed" alert.
    elsif new.journey_state = 'en_route_stop' then
      v_type := 'heading_to_spot'; v_title := case when new.current_stop_index > 0 then 'Next Destination' else 'Heading to ' || v_item.destination_name end;
      v_body := 'Your tour is now heading to ' || v_item.destination_name || '.';
    else
      v_type := 'spot_arrived'; v_title := 'Arrived at ' || v_item.destination_name;
      v_body := 'You have arrived at your next tour destination.';
    end if;
  else return new;
  end if;
  perform public.emit_tour_notification(b.tourist_id,b.id,v_key,v_type,v_title,v_body,v_push);
  return new;
exception when others then raise warning 'Driver notification failed [%]', sqlstate; return new;
end $$;
-- Deferred evaluation sees the final roster for a multi-row assignment transaction.
create constraint trigger notification_driver after insert or update on public.booking_drivers
  deferrable initially deferred for each row execute function public.observe_driver_notification();

-- The legacy GPS-arrival RPC records this milestone without always advancing
-- journey_state. Observe it too, sharing the same event key as the journey path.
create or replace function public.observe_stop_arrival_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare b public.package_bookings; v_name text; v_roster integer; v_arrived integer;
begin
  select pb.* into b from public.package_bookings pb
    join public.booking_itinerary_items bii on bii.booking_id = pb.id where bii.id = new.itinerary_item_id;
  select destination_name into v_name from public.booking_itinerary_items where id = new.itinerary_item_id;
  select count(*),count(a.booking_driver_id) into v_roster,v_arrived
    from public.required_booking_driver_roster(b.id) d left join public.booking_driver_arrivals a
      on a.booking_driver_id = d.id and a.itinerary_item_id = new.itinerary_item_id;
  if b.status not in ('cancelled','rejected','completed') and v_roster >= greatest(coalesce(b.required_drivers,1),1)
    and v_arrived = v_roster then
    perform public.emit_tour_notification(b.tourist_id,b.id,b.id || ':spot:' || new.itinerary_item_id || ':at_stop',
      'spot_arrived','Arrived at ' || v_name,'You have arrived at your next tour destination.');
  end if;
  return new;
exception when others then raise warning 'Stop notification failed [%]', sqlstate; return new;
end $$;
create constraint trigger notification_stop_arrival after insert on public.booking_driver_arrivals
  deferrable initially deferred for each row execute function public.observe_stop_arrival_notification();

create or replace function public.observe_payment_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare b public.package_bookings; r record;
begin
  select * into b from public.package_bookings where id = new.booking_id;
  if not found then return new; end if;
  if tg_table_name = 'booking_payment_requirements' then
    if new.payment_stage = 'down_payment' and new.status = 'required'
      and (tg_op = 'INSERT' or old.status is distinct from new.status) then
      perform public.emit_tour_notification(b.tourist_id,b.id,b.id || ':down_payment_required',
        'down_payment_required','Downpayment Required','Complete your downpayment to continue your booking.');
    end if;
  elsif tg_op = 'INSERT' or new.status is distinct from old.status
    or new.provider_status is distinct from old.provider_status then
    if new.status = 'confirmed' then
      perform public.emit_tour_notification(b.tourist_id,b.id,b.id || ':paid:' || new.payment_stage,
        'payment_confirmed',case when new.payment_stage = 'down_payment' then 'Downpayment Confirmed' else 'Payment Complete' end,
        case when new.payment_stage = 'down_payment' then 'Your downpayment has been received.' else 'Your remaining balance has been received.' end);
      if new.payment_stage = 'down_payment' then
        for r in select driver_id from public.required_booking_driver_roster(b.id) loop
          perform public.emit_tour_notification(r.driver_id,b.id,b.id || ':paid:down_payment',
            'payment_confirmed','Downpayment Confirmed','The tourist''s downpayment has been confirmed.');
        end loop;
      end if;
    elsif new.status <> 'confirmed' and new.provider = 'paymongo'
      and new.provider_status in ('failed','checkout_failed','cancelled','expired') then
      perform public.emit_tour_notification(b.tourist_id,b.id,new.id || ':failed',
        'payment_failed','Payment Unsuccessful','Your payment could not be completed. Please try again.');
    end if;
  end if;
  return new;
exception when others then raise warning 'Payment notification failed [%]', sqlstate; return new;
end $$;
create trigger notification_payment after insert or update of status,provider_status on public.payment_records
  for each row execute function public.observe_payment_notification();
create trigger notification_requirement after insert or update of status on public.booking_payment_requirements
  for each row execute function public.observe_payment_notification();

create or replace function public.observe_cash_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_booking uuid;
begin
  if new.status = 'awaiting_cash' and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    select booking_id into v_booking from public.payment_records where id = new.payment_record_id;
    perform public.emit_tour_notification(new.driver_id,v_booking,new.id || ':cash',
      'cash_confirmation_required','Payment Confirmation Required','Confirm the cash payment to continue.');
  end if;
  return new;
exception when others then raise warning 'Cash notification failed [%]', sqlstate; return new;
end $$;
create trigger notification_cash after insert or update of status on public.payment_allocations
  for each row execute function public.observe_cash_notification();

create or replace function public.observe_emergency_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.alert_status <> 'active' then return new; end if;
  -- Validate the association: emergency insert RLS alone only checks tourist_id.
  if new.booking_id is not null and not exists(select 1 from public.package_bookings
    where id = new.booking_id and tourist_id = new.tourist_id
      and status not in ('cancelled','rejected','completed')) then return new; end if;
  for r in
    select bd.driver_id as user_id from public.booking_drivers bd
      where bd.booking_id = new.booking_id and bd.status = 'accepted'
    union select p.id from public.profiles p where p.role = 'admin'
      or (p.role = 'subtenant' and exists(select 1 from public.package_bookings pb
        where pb.id = new.booking_id and lower(trim(p.city)) = lower(trim(pb.municipality))))
  loop
    perform public.emit_tour_notification(r.user_id,new.booking_id,new.id || ':emergency',
      'emergency_alert','Emergency Alert','An emergency alert was triggered for an active tour.',true,
      jsonb_build_object('alert_id',new.id));
  end loop;
  return new;
exception when others then raise warning 'Emergency notification failed [%]', sqlstate; return new;
end $$;
create trigger notification_emergency after insert on public.emergency_alerts
  for each row execute function public.observe_emergency_notification();

-- Claims are leased and fenced: concurrent workers cannot acknowledge each other's work.
create or replace function public.claim_notification_deliveries(p_limit integer default 30)
returns table(delivery_id uuid,lease_id uuid,token text,notification_id text,title text,body text,channel text,recipient_id uuid,installation_id uuid)
language plpgsql security definer set search_path = public as $$
begin
  -- Recover an enqueue failure from durable history without replaying history to
  -- a device/account that registered after the event.
  insert into public.notification_deliveries(notification_id,installation_id,recipient_id,token)
  select n.id::text,d.installation_id,n.user_id,d.token from public.notifications n
    join public.notification_devices d on d.user_id = n.user_id and d.active
      and d.registered_at <= n.created_at and d.updated_at > now() - interval '60 days'
  where n.push_enabled and n.created_at > now() - interval '1 hour'
    and (n.channel <> 'emergency_alerts' or n.created_at > now() - interval '15 minutes')
  on conflict do nothing;
  update public.notification_deliveries j set status = 'skipped',last_error = 'EXPIRED'
    from public.notifications n where n.id::text = j.notification_id and j.status in ('pending','sending')
      and n.created_at < now() - case when n.channel = 'emergency_alerts' then interval '15 minutes' else interval '1 hour' end;
  update public.notification_deliveries j set status = 'skipped', last_error = 'DEVICE_UNAVAILABLE'
    where j.status in ('pending','sending') and not exists(select 1 from public.notification_devices d
      where d.installation_id = j.installation_id and d.user_id = j.recipient_id and d.token = j.token and d.active);
  update public.notification_deliveries set status = 'failed',last_error = 'RETRY_LIMIT'
    where status in ('pending','sending') and attempts >= 8 and (lease_until is null or lease_until < now());
  return query
  with picked as (
    select j.id from public.notification_deliveries j where
      (j.status = 'pending' and j.available_at <= now() or j.status = 'sending' and j.lease_until < now())
      and j.attempts < 8 order by j.available_at for update skip locked limit least(greatest(p_limit,1),100)
  ), claimed as (
    update public.notification_deliveries j set status = 'sending',attempts = attempts + 1,
      lease_id = gen_random_uuid(),lease_until = now() + interval '2 minutes'
    from picked where j.id = picked.id returning j.*
  ) select c.id,c.lease_id,c.token,c.notification_id,n.title,n.body,n.channel,c.recipient_id,c.installation_id
    from claimed c join public.notifications n on n.id::text = c.notification_id and n.user_id = c.recipient_id;
end $$;

create or replace function public.finish_notification_delivery(p_id uuid,p_lease uuid,p_result text,p_code text default null)
returns void language plpgsql security definer set search_path = public as $$
declare j public.notification_deliveries;
begin
  select * into j from public.notification_deliveries where id = p_id and lease_id = p_lease and status = 'sending' for update;
  if not found then return; end if;
  if p_result not in ('sent','invalid','retry','failed') then raise exception 'INVALID_RESULT'; end if;
  if p_result = 'invalid' then
    update public.notification_devices set active = false where installation_id = j.installation_id
      and token = j.token and user_id = j.recipient_id;
  end if;
  update public.notification_deliveries set status = case when p_result = 'sent' then 'sent'
    when p_result = 'retry' and attempts < 8 then 'pending' else 'failed' end,
    available_at = now() + make_interval(secs => least(3600,30 * power(2,j.attempts)::integer)),
    lease_until = null,last_error = left(p_code,100) where id = p_id;
end $$;

-- Payload IDs are only a lookup hint. Re-check notification ownership AND current booking access.
create or replace function public.notification_destination(p_notification_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n public.notifications; b public.package_bookings; v_activity uuid;
begin
  select * into n from public.notifications where id::text = p_notification_id and user_id = auth.uid();
  if not found then return null; end if;
  if n.booking_id is null then return jsonb_build_object('screen','notifications'); end if;
  select * into b from public.package_bookings where id = n.booking_id;
  if not found then return null; end if;
  if b.tourist_id = auth.uid() then
    return jsonb_build_object('screen','tourist_booking','booking_id',b.id);
  end if;
  if exists(select 1 from public.booking_drivers where booking_id = b.id and driver_id = auth.uid() and status in ('accepted','completed')) then
    select id into v_activity from public.package_activities where booking_id = b.id limit 1;
    if v_activity is not null then return jsonb_build_object('screen','driver_tracking','activity_id',v_activity); end if;
    return jsonb_build_object('screen','driver_jobs');
  end if;
  if n.type in ('available_package_job','tour_assigned') and public.current_profile_role() = 'driver' then
    -- Job list applies existing dispatch/eligibility rules again; no booking data returned.
    return jsonb_build_object('screen','driver_jobs');
  end if;
  return jsonb_build_object('screen','notifications');
end $$;

-- Explicit grants: SECURITY DEFINER helpers are never callable by clients.
revoke all on function public.emit_tour_notification(uuid,uuid,text,text,text,text,boolean,jsonb),
  public.notification_push_allowed(uuid,text),
  public.notify_drivers_of_available_booking(),
  public.normalize_tour_notification(),public.enqueue_notification_delivery(),public.observe_booking_notification(),
  public.observe_driver_notification(),public.observe_payment_notification(),public.observe_cash_notification(),
  public.observe_stop_arrival_notification(),
  public.observe_emergency_notification(),public.claim_notification_deliveries(integer),
  public.finish_notification_delivery(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.claim_notification_deliveries(integer),public.finish_notification_delivery(uuid,uuid,text,text) to service_role;
revoke all on function public.register_notification_device(uuid,text),public.unregister_notification_device(uuid),
  public.notification_destination(text) from public,anon;
grant execute on function public.register_notification_device(uuid,text),public.unregister_notification_device(uuid),
  public.notification_destination(text) to authenticated;

do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'notifications') then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
commit;
