-- Reconcile verified historical schema/security drift without replaying old bundles.
-- This migration intentionally contains no production-row updates.
--
-- Historical source review:
--   20260508000000: RLS, write/read policies, indexes, updated_at triggers.
--   20260831010000: unified staged payments for same-day and advance bookings.
--   20260905030000: municipality scope hardening and supporting indexes.
--   20260926010000: settings/notification prerequisites for 20260927020000.
--
-- Superseded lifecycle and sharing implementations are deliberately excluded.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- The historical same-day repair would rewrite bookings. The reviewed live
-- preflight found zero eligible rows; abort instead of rewriting if that changes.
do $$
begin
  if exists (
    select 1
    from public.package_bookings pb
    where lower(coalesce(pb.booking_type, '')) = 'same_day'
      and coalesce(pb.total_amount, 0) > 0
      and coalesce(pb.downpayment_amount, 0) = 0
      and lower(coalesce(pb.booking_status, pb.status, '')) in (
        'pending', 'waiting_for_drivers', 'accepted', 'confirmed'
      )
      and not exists (
        select 1
        from public.payment_records pr
        where pr.booking_id = pb.id
          and pr.status <> 'cancelled'
      )
  ) then
    raise exception
      'RECONCILIATION_REQUIRES_REVIEW: eligible same-day rows now exist';
  end if;
end;
$$;

-- The later Main Tenant settings migration reads and then migrates these
-- office fields, and retains the notification preference fields. None of the
-- predecessor migration's columns/functions/triggers exist live. Reproduce
-- the reviewed predecessor behavior so 20260927020000 has a valid dependency.
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

drop policy if exists own_settings on public.admin_settings;
create policy own_settings on public.admin_settings
for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

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

-- These SECURITY DEFINER helpers are internal notification plumbing, not
-- client RPC endpoints. The later Main Tenant migration repeats the revokes.
revoke all on function public.notify_provincial_admins(text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.provincial_admin_notification_allowed(uuid, text)
  from public, anon, authenticated;

-- Restore enforcement on the eleven legacy tables whose policies already
-- existed but whose RLS switch was never represented in live history.
alter table public.admin_settings enable row level security;
alter table public.driver_details enable row level security;
alter table public.driver_documents enable row level security;
alter table public.ride_feedback enable row level security;
alter table public.ride_reviews enable row level security;
alter table public.tour_package_day_items enable row level security;
alter table public.tour_package_days enable row level security;
alter table public.tour_package_spots enable row level security;
alter table public.tour_package_views enable row level security;
alter table public.tourist_spot_images enable row level security;
alter table public.tourist_spot_views enable row level security;

-- Complete the operation coverage needed before enabling those tables.
drop policy if exists spot_views_insert_authenticated
  on public.tourist_spot_views;
create policy spot_views_insert_authenticated
on public.tourist_spot_views for insert to authenticated
with check (auth.uid() is not null and (user_id is null or user_id = auth.uid()));

drop policy if exists package_views_insert_authenticated
  on public.tour_package_views;
create policy package_views_insert_authenticated
on public.tour_package_views for insert to authenticated
with check (auth.uid() is not null and (user_id is null or user_id = auth.uid()));

drop policy if exists ride_reviews_insert_tourist
  on public.ride_reviews;
create policy ride_reviews_insert_tourist
on public.ride_reviews for insert to authenticated
with check (tourist_id = auth.uid());

drop policy if exists ride_feedback_insert_tourist
  on public.ride_feedback;
create policy ride_feedback_insert_tourist
on public.ride_feedback for insert to authenticated
with check (tourist_id = auth.uid());

-- Two RLS-enabled lookup/content tables had no policies at all.
drop policy if exists categories_read_authenticated
  on public.tourism_categories;
create policy categories_read_authenticated
on public.tourism_categories for select to authenticated
using (true);

drop policy if exists categories_admin_write
  on public.tourism_categories;
create policy categories_admin_write
on public.tourism_categories for all to authenticated
using (public.is_provincial_admin())
with check (public.is_provincial_admin());

drop policy if exists policies_select_published_staff
  on public.tourism_policies;
create policy policies_select_published_staff
on public.tourism_policies for select to authenticated
using (
  status = 'published'
  or public.is_provincial_admin()
  or public.current_profile_role() = 'subtenant'
);

drop policy if exists policies_admin_write
  on public.tourism_policies;
create policy policies_admin_write
on public.tourism_policies for all to authenticated
using (public.is_provincial_admin())
with check (public.is_provincial_admin());

-- Restore missing performance successors. Equivalent indexes already present
-- under other names are not duplicated.
create index if not exists profiles_role_city_idx
  on public.profiles(role, city);
create index if not exists tourist_spots_city_status_idx
  on public.tourist_spots(city, status);
create index if not exists tourist_spot_views_spot_created_idx
  on public.tourist_spot_views(spot_id, created_at desc);
create index if not exists tour_packages_city_status_idx
  on public.tour_packages(city, status);
create index if not exists tour_package_views_package_created_idx
  on public.tour_package_views(package_id, created_at desc);
create index if not exists package_bookings_package_status_idx
  on public.package_bookings(package_id, status);
create index if not exists package_bookings_tourist_idx
  on public.package_bookings(tourist_id);
create index if not exists rides_tourist_idx
  on public.rides(tourist_id);
create index if not exists rides_driver_idx
  on public.rides(driver_id);
create index if not exists notifications_user_idx
  on public.notifications(user_id);
create index if not exists audit_logs_actor_created_idx
  on public.audit_logs(actor_id, created_at desc);

-- Restore missing updated_at triggers, using the verified live helper.
drop trigger if exists set_admin_settings_updated_at
  on public.admin_settings;
create trigger set_admin_settings_updated_at
before update on public.admin_settings
for each row execute function public.set_updated_at();

drop trigger if exists set_subtenant_details_updated_at
  on public.subtenant_details;
create trigger set_subtenant_details_updated_at
before update on public.subtenant_details
for each row execute function public.set_updated_at();

drop trigger if exists set_tourism_categories_updated_at
  on public.tourism_categories;
create trigger set_tourism_categories_updated_at
before update on public.tourism_categories
for each row execute function public.set_updated_at();

drop trigger if exists set_tourist_spots_updated_at
  on public.tourist_spots;
create trigger set_tourist_spots_updated_at
before update on public.tourist_spots
for each row execute function public.set_updated_at();

drop trigger if exists set_tour_packages_updated_at
  on public.tour_packages;
create trigger set_tour_packages_updated_at
before update on public.tour_packages
for each row execute function public.set_updated_at();

drop trigger if exists set_package_bookings_updated_at
  on public.package_bookings;
create trigger set_package_bookings_updated_at
before update on public.package_bookings
for each row execute function public.set_updated_at();

drop trigger if exists set_saved_places_updated_at
  on public.saved_places;
create trigger set_saved_places_updated_at
before update on public.saved_places
for each row execute function public.set_updated_at();

drop trigger if exists set_city_announcements_updated_at
  on public.city_announcements;
create trigger set_city_announcements_updated_at
before update on public.city_announcements
for each row execute function public.set_updated_at();

drop trigger if exists set_tourism_policies_updated_at
  on public.tourism_policies;
create trigger set_tourism_policies_updated_at
before update on public.tourism_policies
for each row execute function public.set_updated_at();

-- Unified staged-payment behavior, selected from 20260831010000. The data
-- backfill and lifecycle functions superseded by later migrations are omitted.
create or replace function public.guard_package_booking_client_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Security-definer lifecycle/payment RPCs set this transaction-local flag.
  -- Direct tourist PostgREST writes never can.
  if coalesce(current_setting('touristrike.validated_transition', true), '') = 'true' then
    return new;
  end if;

  if public.current_profile_role() <> 'tourist' then return new; end if;

  if tg_op = 'INSERT' then
    if auth.uid() is null or new.tourist_id is distinct from auth.uid() then
      raise exception 'NOT_BOOKING_TOURIST';
    end if;
    if new.assigned_driver_id is not null then
      raise exception 'INVALID_INITIAL_ASSIGNED_DRIVER';
    end if;
    if coalesce(new.accepted_drivers_count, 0) <> 0 then
      raise exception 'INVALID_INITIAL_ACCEPTED_DRIVER_COUNT';
    end if;
    if new.required_drivers is null or new.required_drivers < 1 then
      raise exception 'INVALID_REQUIRED_DRIVERS';
    end if;
    if lower(coalesce(nullif(trim(new.status), ''), 'pending')) <> 'pending' then
      raise exception 'INVALID_INITIAL_STATUS';
    end if;
    if lower(coalesce(nullif(trim(new.booking_status), ''), 'waiting_for_drivers'))
       not in ('pending', 'waiting_for_drivers') then
      raise exception 'INVALID_INITIAL_BOOKING_STATE';
    end if;
    new.status := 'pending';
    new.booking_status := 'waiting_for_drivers';
    new.accepted_drivers_count := 0;

    -- Same-day and advance bookings share one staged PayMongo payment rule.
    if lower(coalesce(nullif(trim(new.payment_method), ''), '')) <> 'gcash' then
      raise exception 'PACKAGE_BOOKING_REQUIRES_GCASH';
    end if;
    if new.total_amount is null or new.downpayment_amount is null
       or new.remaining_balance is null then
      raise exception 'MISSING_PACKAGE_PAYMENT_AMOUNTS';
    end if;
    if new.downpayment_amount <> round(new.total_amount * 0.50, 2)
       or new.remaining_balance <> new.total_amount - new.downpayment_amount then
      raise exception 'INVALID_PACKAGE_PAYMENT_SPLIT';
    end if;
    return new;
  end if;

  if lower(coalesce(nullif(trim(new.booking_status), ''),
                    nullif(trim(new.status), ''), '')) = 'cancelled' then
    return new;
  end if;

  if new.status is distinct from old.status
     or new.booking_status is distinct from old.booking_status
     or new.assigned_driver_id is distinct from old.assigned_driver_id
     or new.accepted_drivers_count is distinct from old.accepted_drivers_count
     or new.required_drivers is distinct from old.required_drivers
     or new.booking_type is distinct from old.booking_type
     or new.payment_method is distinct from old.payment_method
     or new.total_amount is distinct from old.total_amount
     or new.downpayment_amount is distinct from old.downpayment_amount
     or new.remaining_balance is distinct from old.remaining_balance
     or new.travel_date is distinct from old.travel_date
     or new.scheduled_start_at is distinct from old.scheduled_start_at
     or new.estimated_end_at is distinct from old.estimated_end_at then
    raise exception 'BOOKING_UPDATE_RPC_REQUIRED';
  end if;
  return new;
end;
$$;
create or replace function public.finalize_package_booking_if_eligible(
  p_booking_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_activity_id uuid;
  v_total_items integer := 0;
  v_completed_items integer := 0;
  v_required_slots integer := 1;
  v_active_slots integer := 0;
  v_completed_slots integer := 0;
  v_physical_tour_finished boolean := false;
  v_payment_satisfied boolean := false;
  v_overall_completed boolean := false;
  v_completion_progress jsonb;
begin
  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
     in ('cancelled', 'rejected') then
    return jsonb_build_object(
      'success', false,
      'booking_id', p_booking_id,
      'terminal_status', lower(coalesce(v_booking.booking_status, v_booking.status, '')),
      'overall_completed', false
    );
  end if;

  select count(*),
         count(*) filter (
           where lower(coalesce(bii.spot_status, 'pending')) = 'completed'
         )
  into v_total_items, v_completed_items
  from public.booking_itinerary_items bii
  where bii.booking_id = p_booking_id;

  v_required_slots := greatest(coalesce(v_booking.required_drivers, 1), 1);
  v_completion_progress := public.compute_convoy_stage_progress(
    p_booking_id, 'completed', null
  );
  v_active_slots := coalesce(
    (v_completion_progress->>'required_driver_count')::integer, 0
  );
  v_completed_slots := coalesce(
    (v_completion_progress->>'satisfied_driver_count')::integer, 0
  );

  v_physical_tour_finished :=
    v_total_items > 0
    and v_completed_items = v_total_items
    and v_active_slots >= v_required_slots
    and v_completed_slots = v_active_slots;

  v_payment_satisfied :=
    coalesce(v_booking.remaining_balance, 0) <= 0
    or exists (
      select 1
      from public.booking_payment_requirements bpr
      where bpr.booking_id = p_booking_id
        and bpr.payment_stage = 'remaining_balance'
        and bpr.amount >= v_booking.remaining_balance
        and (
          bpr.status = 'waived'
          or (
            bpr.status = 'satisfied'
            and exists (
              select 1
              from public.payment_records pr
              where pr.id = bpr.satisfied_by_payment_record_id
                and pr.booking_id = p_booking_id
                and pr.payment_stage = 'remaining_balance'
                and pr.status = 'confirmed'
                and pr.amount >= v_booking.remaining_balance
            )
          )
        )
    );

  select pa.id into v_activity_id
  from public.package_activities pa
  where pa.booking_id = p_booking_id
  limit 1;

  if v_physical_tour_finished then
    perform set_config('touristrike.validated_transition', 'true', true);

    if v_payment_satisfied then
      v_overall_completed := true;

      update public.package_activities
      set status = 'completed',
          tour_status = 'completed',
          current_spot_index = v_total_items,
          dropped_off_at = coalesce(dropped_off_at, now()),
          updated_at = now()
      where id = v_activity_id;

      update public.package_bookings
      set status = 'completed',
          booking_status = 'completed',
          current_spot_index = v_total_items,
          completed_at = coalesce(completed_at, now()),
          updated_at = now()
      where id = p_booking_id;
    else
      update public.package_activities
      set status = 'ongoing',
          tour_status = 'ready_to_complete',
          current_spot_index = v_total_items,
          dropped_off_at = coalesce(dropped_off_at, now()),
          updated_at = now()
      where id = v_activity_id;

      update public.package_bookings
      set status = case when status = 'completed' then 'confirmed' else status end,
          booking_status = 'awaiting_final_payment',
          current_spot_index = v_total_items,
          completed_at = null,
          updated_at = now()
      where id = p_booking_id;
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'booking_id', p_booking_id,
    'physical_tour_finished', v_physical_tour_finished,
    'remaining_payment_satisfied', v_payment_satisfied,
    'awaiting_final_payment', v_physical_tour_finished and not v_payment_satisfied,
    'overall_completed', v_overall_completed,
    'completed_items', v_completed_items,
    'total_items', v_total_items,
    'completed_slots', v_completed_slots,
    'active_slots', v_active_slots,
    'required_slots', v_required_slots
  );
end;
$$;

revoke all on function public.finalize_package_booking_if_eligible(uuid)
  from public, anon, authenticated;
create or replace function public.ensure_booking_payment_requirements(
  p_booking_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_written integer := 0;
begin
  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if not public.is_booking_driver_roster_full(p_booking_id) then
    return 0;
  end if;
  if coalesce(v_booking.downpayment_amount, 0) > 0 then
    insert into public.booking_payment_requirements(
      booking_id, payment_stage, amount
    ) values (
      p_booking_id, 'down_payment', round(v_booking.downpayment_amount, 2)
    )
    on conflict (booking_id, payment_stage) do update
    set amount = excluded.amount,
        status = case
          when booking_payment_requirements.status in ('satisfied', 'waived')
            then booking_payment_requirements.status
          else 'required'
        end;
    v_written := v_written + 1;
  end if;

  if coalesce(v_booking.remaining_balance, 0) > 0 then
    insert into public.booking_payment_requirements(
      booking_id, payment_stage, amount
    ) values (
      p_booking_id, 'remaining_balance', round(v_booking.remaining_balance, 2)
    )
    on conflict (booking_id, payment_stage) do update
    set amount = excluded.amount,
        status = case
          when booking_payment_requirements.status in ('satisfied', 'waived')
            then booking_payment_requirements.status
          else 'required'
        end;
    v_written := v_written + 1;
  end if;

  return v_written;
end;
$$;

revoke all on function public.ensure_booking_payment_requirements(uuid)
  from public, anon, authenticated;

create or replace function public.is_booking_remaining_payment_satisfied(
  p_booking_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_booking public.package_bookings;
begin
  select * into v_booking
  from public.package_bookings
  where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if coalesce(v_booking.remaining_balance, 0) <= 0 then
    return true;
  end if;

  return exists (
    select 1
    from public.booking_payment_requirements bpr
    where bpr.booking_id = p_booking_id
      and bpr.payment_stage = 'remaining_balance'
      and (
        bpr.status = 'waived'
        or (
          bpr.status = 'satisfied'
          and exists (
            select 1
            from public.payment_records pr
            where pr.id = bpr.satisfied_by_payment_record_id
              and pr.booking_id = p_booking_id
              and pr.payment_stage = 'remaining_balance'
              and pr.status = 'confirmed'
              and pr.amount >= bpr.amount
          )
        )
      )
  );
end;
$$;

revoke all on function public.is_booking_remaining_payment_satisfied(uuid)
  from public, anon, authenticated;

create or replace function public.validate_booking_payment_submission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_required_amount numeric;
  v_trusted_group_cash boolean :=
    coalesce(current_setting('touristrike.trusted_group_cash', true), '') = 'true';
begin
  if new.booking_id is null then return new; end if;

  select * into v_booking from public.package_bookings
  where id = new.booking_id for key share;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if new.provider = 'paymongo' then
    if auth.uid() is null or new.payer_id <> auth.uid()
       or new.payer_id <> v_booking.tourist_id then
      raise exception 'NOT_BOOKING_TOURIST';
    end if;
    if new.payee_id is not null then
      raise exception 'PAYMONGO_PAYEE_MUST_BE_NULL';
    end if;
    if new.payment_method <> 'gcash' then
      raise exception 'PAYMONGO_GCASH_REQUIRED';
    end if;
  elsif new.payee_id is null then
    if not v_trusted_group_cash or new.payer_id <> v_booking.tourist_id
       or new.payment_method <> 'cash'
       or new.payment_stage <> 'remaining_balance'
       or new.provider_status <> 'awaiting_cash_receipt' then
      raise exception 'TRUSTED_GROUP_CASH_BACKEND_REQUIRED';
    end if;
  elsif auth.uid() is null or new.payer_id <> auth.uid()
        or new.payer_id <> v_booking.tourist_id then
    raise exception 'NOT_BOOKING_TOURIST';
  elsif not exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = new.booking_id
      and bd.driver_id = new.payee_id
      and bd.status in ('accepted', 'completed')
  ) then
    raise exception 'PAYEE_NOT_ASSIGNED_DRIVER';
  end if;

  if lower(coalesce(v_booking.booking_status, v_booking.status, 'pending'))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_PAYABLE';
  end if;

  if new.payment_stage = 'down_payment' then
    v_required_amount := v_booking.downpayment_amount;
    if new.provider <> 'paymongo' or new.payment_method <> 'gcash' then
      raise exception 'DOWN_PAYMENT_REQUIRES_PAYMONGO_GCASH';
    end if;
  elsif new.payment_stage = 'remaining_balance' then
    v_required_amount := v_booking.remaining_balance;
    if not (
      (new.provider = 'paymongo' and new.payment_method = 'gcash')
      or (new.provider = 'manual' and new.payment_method = 'cash')
    ) then
      raise exception 'INVALID_REMAINING_PAYMENT_ROUTE';
    end if;
  else
    raise exception 'INVALID_PACKAGE_PAYMENT_STAGE';
  end if;

  if coalesce(v_required_amount, 0) <= 0
     or new.amount <> round(v_required_amount, 2) then
    raise exception 'INVALID_PAYMENT_AMOUNT';
  end if;
  if not exists (
    select 1 from public.booking_payment_requirements bpr
    where bpr.booking_id = new.booking_id
      and bpr.payment_stage = new.payment_stage
      and bpr.status <> 'waived'
      and bpr.amount = new.amount
  ) then
    raise exception 'PAYMENT_STAGE_NOT_REQUIRED';
  end if;

  return new;
end;
$$;

-- Override the trusted implementation behind the authenticated wrapper from
-- 20260829010000, preserving auth.uid() in the tourist's JWT context.
create or replace function public.prepare_paymongo_payment_authenticated_impl(
  p_booking_id uuid,
  p_payment_stage text,
  p_idempotency_key text,
  p_tourist_id uuid,
  p_provider_livemode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_payment public.payment_records;
  v_stage text := case when p_payment_stage = 'full_payment'
    then 'full' else p_payment_stage end;
  v_amount numeric(14,2);
  v_roster_count integer;
begin
  if p_tourist_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 16
     or length(p_idempotency_key) > 255 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  select * into v_booking from public.package_bookings
  where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking.tourist_id <> p_tourist_id then
    raise exception 'NOT_BOOKING_TOURIST';
  end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_PAYABLE';
  end if;

  select * into v_payment from public.payment_records
  where provider = 'paymongo' and idempotency_key = p_idempotency_key;
  if found then
    if v_payment.booking_id <> p_booking_id
       or v_payment.payment_stage <> v_stage
       or v_payment.payer_id <> p_tourist_id then
      raise exception 'IDEMPOTENCY_KEY_REUSED';
    end if;
    return jsonb_build_object(
      'payment', to_jsonb(v_payment),
      'amount_centavos', (v_payment.amount * 100)::bigint,
      'allocations', coalesce((
        select jsonb_agg(to_jsonb(a) order by a.created_at, a.id)
        from public.payment_allocations a
        where a.payment_record_id = v_payment.id
      ), '[]'::jsonb),
      'reused', true
    );
  end if;

  select count(*) into v_roster_count
  from public.required_booking_driver_roster(p_booking_id);
  if not public.is_booking_driver_roster_full(p_booking_id) then
    raise exception 'DRIVER_ROSTER_NOT_FULL';
  end if;

  perform public.ensure_booking_payment_requirements(p_booking_id);
  if v_stage = 'down_payment' then
    v_amount := v_booking.downpayment_amount;
  elsif v_stage = 'remaining_balance' then
    if not public.is_booking_itinerary_complete(p_booking_id) then
      raise exception 'REMAINING_PAYMENT_NOT_DUE';
    end if;
    if not public.is_booking_downpayment_confirmed(p_booking_id) then
      raise exception 'DOWNPAYMENT_NOT_CONFIRMED';
    end if;
    v_amount := v_booking.remaining_balance;
  else
    raise exception 'INVALID_PACKAGE_PAYMENT_STAGE';
  end if;
  if not exists (
    select 1 from public.booking_payment_requirements
    where booking_id = p_booking_id and payment_stage = v_stage
      and status = 'required' and amount = v_amount
  ) then
    raise exception 'PAYMENT_STAGE_NOT_DUE';
  end if;
  v_amount := round(v_amount, 2);
  if coalesce(v_amount, 0) <= 0 then raise exception 'INVALID_PAYMENT_AMOUNT'; end if;

  select * into v_payment from public.payment_records
  where booking_id = p_booking_id and payment_stage = v_stage
    and status <> 'cancelled' for update;
  if found then
    if v_payment.provider <> 'paymongo' then
      raise exception 'PAYMENT_STAGE_ALREADY_HAS_MANUAL_RECORD';
    end if;
    return jsonb_build_object(
      'payment', to_jsonb(v_payment),
      'amount_centavos', (v_payment.amount * 100)::bigint,
      'allocations', coalesce((
        select jsonb_agg(to_jsonb(a) order by a.created_at, a.id)
        from public.payment_allocations a
        where a.payment_record_id = v_payment.id
      ), '[]'::jsonb),
      'reused', true
    );
  end if;

  insert into public.payment_records(
    booking_id, payer_id, payee_id, amount, payment_method, payment_stage,
    status, provider, currency, provider_reference, provider_status,
    provider_livemode, idempotency_key, service_description
  ) values (
    p_booking_id, p_tourist_id, null, v_amount, 'gcash', v_stage,
    'pending_confirmation', 'paymongo', 'PHP', gen_random_uuid()::text,
    'preparing_checkout', p_provider_livemode, p_idempotency_key,
    'TourisTrike package booking payment'
  ) returning * into v_payment;

  insert into public.payment_allocations(
    payment_record_id, booking_id, booking_driver_id, driver_id,
    gross_amount, platform_fee, driver_amount, split_basis_points,
    currency, status, provider_recipient_id
  )
  with ranked as (
    select bd.*,
      (row_number() over (order by bd.accepted_at, bd.id))::integer
        as recipient_position
    from public.required_booking_driver_roster(p_booking_id) bd
  )
  select v_payment.id, p_booking_id, bd.id, bd.driver_id,
         split.amount_centavos / 100.0, 0, split.amount_centavos / 100.0,
         split.basis_points, 'PHP', 'held', dpa.provider_recipient_id
  from ranked bd
  join public.compute_equal_split_centavos(
    (v_amount * 100)::bigint, v_roster_count
  ) split on split.recipient_position = bd.recipient_position
  left join lateral (
    select account.provider_recipient_id
    from public.driver_payout_accounts account
    where account.driver_id = bd.driver_id
      and account.provider = 'paymongo'
      and account.destination_type = 'linked_account'
      and account.verification_status = 'verified'
      and account.is_default
      and account.provider_livemode = p_provider_livemode
    order by account.updated_at desc limit 1
  ) dpa on true;

  perform public.assert_payment_allocation_total(v_payment.id);

  return jsonb_build_object(
    'payment', to_jsonb(v_payment),
    'amount_centavos', (v_amount * 100)::bigint,
    'allocations', (
      select jsonb_agg(
        ranked.allocation || jsonb_build_object(
          'split_basis_points', ranked.allocation->'split_basis_points'
        ) order by ranked.recipient_position
      )
      from (
        select to_jsonb(a) as allocation,
          row_number() over (order by bd.accepted_at, bd.id)
            as recipient_position
        from public.payment_allocations a
        join public.booking_drivers bd on bd.id = a.booking_driver_id
        where a.payment_record_id = v_payment.id
      ) ranked
    ),
    'reused', false
  );
end;
$$;

revoke all on function public.prepare_paymongo_payment_authenticated_impl(
  uuid, text, text, uuid, boolean
) from public, anon, authenticated, service_role;

create or replace function public.prepare_group_cash_remaining_balance(
  p_booking_id uuid,
  p_idempotency_key text
)
returns public.payment_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_payment public.payment_records;
  v_roster_count integer;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 16
     or length(p_idempotency_key) > 255 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  select * into v_booking from public.package_bookings
  where id = p_booking_id for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking.tourist_id <> auth.uid() then
    raise exception 'NOT_BOOKING_TOURIST';
  end if;
  if lower(coalesce(v_booking.booking_status, v_booking.status, ''))
       in ('cancelled', 'completed', 'rejected', 'done') then
    raise exception 'BOOKING_NOT_PAYABLE';
  end if;

  select count(*) into v_roster_count
  from public.required_booking_driver_roster(p_booking_id);
  if not public.is_booking_driver_roster_full(p_booking_id) then
    raise exception 'DRIVER_ROSTER_NOT_FULL';
  end if;

  perform public.ensure_booking_payment_requirements(p_booking_id);
  if not public.is_booking_itinerary_complete(p_booking_id) then
    raise exception 'REMAINING_PAYMENT_NOT_DUE';
  end if;
  if not public.is_booking_downpayment_confirmed(p_booking_id) then
    raise exception 'DOWNPAYMENT_NOT_CONFIRMED';
  end if;
  if not exists (
    select 1 from public.booking_payment_requirements
    where booking_id = p_booking_id and payment_stage = 'remaining_balance'
      and status = 'required' and amount = v_booking.remaining_balance
  ) then raise exception 'PAYMENT_STAGE_NOT_DUE'; end if;

  select * into v_payment from public.payment_records
  where booking_id = p_booking_id and payment_stage = 'remaining_balance'
    and status <> 'cancelled'
  order by created_at desc limit 1 for update;
  if found then
    if v_payment.provider = 'manual' and v_payment.payment_method = 'cash'
       and v_payment.payee_id is null then
      return v_payment;
    end if;
    raise exception 'PAYMENT_STAGE_ALREADY_STARTED';
  end if;

  perform set_config('touristrike.trusted_group_cash', 'true', true);
  insert into public.payment_records(
    booking_id, payer_id, payee_id, amount, payment_method, payment_stage,
    status, provider, currency, provider_status, idempotency_key,
    service_description
  ) values (
    p_booking_id, auth.uid(), null, round(v_booking.remaining_balance, 2),
    'cash', 'remaining_balance', 'pending_confirmation', 'manual', 'PHP',
    'awaiting_cash_receipt', p_idempotency_key,
    'Cash remaining balance for TourisTrike package booking'
  ) returning * into v_payment;

  insert into public.payment_allocations(
    payment_record_id, booking_id, booking_driver_id, driver_id,
    gross_amount, platform_fee, driver_amount, split_basis_points,
    currency, status
  )
  with ranked as (
    select bd.*,
      (row_number() over (order by bd.accepted_at, bd.id))::integer
        as recipient_position
    from public.required_booking_driver_roster(p_booking_id) bd
  )
  select v_payment.id, p_booking_id, bd.id, bd.driver_id,
         split.amount_centavos / 100.0, 0, split.amount_centavos / 100.0,
         split.basis_points, 'PHP', 'awaiting_cash'
  from ranked bd
  join public.compute_equal_split_centavos(
    (round(v_booking.remaining_balance, 2) * 100)::bigint, v_roster_count
  ) split on split.recipient_position = bd.recipient_position;

  if (select count(*) from public.payment_allocations
      where payment_record_id = v_payment.id) <> v_roster_count
     or (select coalesce(sum(gross_amount), 0)
         from public.payment_allocations
         where payment_record_id = v_payment.id)
        <> round(v_booking.remaining_balance, 2) then
    raise exception 'CASH_ALLOCATION_TOTAL_MISMATCH';
  end if;

  raise log '[TourisTrike payment] group cash prepared booking=%, payment=%, drivers=%',
    p_booking_id, v_payment.id, v_roster_count;
  return v_payment;
end;
$$;

revoke all on function public.prepare_group_cash_remaining_balance(uuid, text)
  from public, anon;
grant execute on function public.prepare_group_cash_remaining_balance(uuid, text)
  to authenticated;
create or replace function public.debug_mark_remaining_balance_paid(
  p_booking_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_booking public.package_bookings;
  v_payment public.payment_records;
  v_driver_count integer;
  v_result jsonb;
begin
  if v_user_id is null then raise exception 'UNAUTHENTICATED'; end if;
  if not public.is_developer_test_booking(p_booking_id) then
    raise exception 'TEST_BOOKING_NOT_REGISTERED';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  if v_booking.tourist_id <> v_user_id and not exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = p_booking_id and bd.driver_id = v_user_id
      and bd.status in ('accepted', 'completed')
  ) then raise exception 'NOT_TEST_BOOKING_PARTICIPANT'; end if;

  if coalesce(v_booking.remaining_balance, 0) <= 0 then
    return jsonb_build_object(
      'success', true, 'already_paid', true,
      'booking_id', p_booking_id, 'payment_required', false
    );
  end if;

  if not public.is_booking_itinerary_complete(p_booking_id) then
    raise exception 'REMAINING_PAYMENT_NOT_DUE';
  end if;

  perform public.ensure_booking_payment_requirements(p_booking_id);

  select * into v_payment
  from public.payment_records
  where booking_id = p_booking_id
    and payment_stage = 'remaining_balance'
    and status = 'confirmed'
    and amount >= v_booking.remaining_balance
  order by created_at desc limit 1;
  if found then
    update public.booking_payment_requirements
    set status = 'satisfied', satisfied_at = coalesce(satisfied_at, now()),
        satisfied_by_payment_record_id = coalesce(
          satisfied_by_payment_record_id, v_payment.id)
    where booking_id = p_booking_id and payment_stage = 'remaining_balance';
    v_result := public.finalize_package_booking_if_eligible(p_booking_id);
    return v_result || jsonb_build_object(
      'debug_bypass', true, 'already_paid', true,
      'payment_record_id', v_payment.id
    );
  end if;

  if exists (
    select 1 from public.payment_records
    where booking_id = p_booking_id
      and payment_stage = 'remaining_balance'
      and status <> 'cancelled'
  ) then raise exception 'PAYMENT_STAGE_ALREADY_STARTED'; end if;

  select count(*) into v_driver_count
  from public.required_booking_driver_roster(p_booking_id);
  if not public.is_booking_driver_roster_full(p_booking_id) then
    raise exception 'DRIVER_SLOTS_NOT_FILLED';
  end if;

  perform set_config('touristrike.trusted_group_cash', 'true', true);
  insert into public.payment_records(
    booking_id, payer_id, payee_id, amount, payment_method, payment_stage,
    status, provider, currency, provider_status, idempotency_key,
    service_description, notes, paid_at
  ) values (
    p_booking_id, v_booking.tourist_id, null,
    round(v_booking.remaining_balance, 2), 'cash', 'remaining_balance',
    'pending_confirmation', 'manual', 'PHP', 'awaiting_cash_receipt',
    'debug-test-remaining-' || p_booking_id::text,
    'TEST MODE remaining balance settlement',
    'Developer test payment simulation; no real funds transferred', null
  ) returning * into v_payment;

  insert into public.payment_allocations(
    payment_record_id, booking_id, booking_driver_id, driver_id,
    gross_amount, platform_fee, driver_amount, split_basis_points,
    currency, status
  )
  with ranked as (
    select bd.*,
      (row_number() over (order by bd.accepted_at, bd.id))::integer as position
    from public.required_booking_driver_roster(p_booking_id) bd
  )
  select v_payment.id, p_booking_id, bd.id, bd.driver_id,
         split.amount_centavos / 100.0, 0, split.amount_centavos / 100.0,
         split.basis_points, 'PHP', 'cash_confirmed'
  from ranked bd
  join public.compute_equal_split_centavos(
    (round(v_booking.remaining_balance, 2) * 100)::bigint, v_driver_count
  ) split on split.recipient_position = bd.position;

  if (select count(*) from public.payment_allocations
      where payment_record_id = v_payment.id) <> v_driver_count
     or (select coalesce(sum(gross_amount), 0)
         from public.payment_allocations
         where payment_record_id = v_payment.id)
        <> round(v_booking.remaining_balance, 2) then
    raise exception 'TEST_PAYMENT_ALLOCATION_TOTAL_MISMATCH';
  end if;

  update public.payment_records
  set status = 'confirmed', provider_status = 'cash_received', paid_at = now()
  where id = v_payment.id
  returning * into v_payment;

  update public.booking_payment_requirements
  set status = 'satisfied', satisfied_at = coalesce(satisfied_at, now()),
      satisfied_by_payment_record_id = v_payment.id
  where booking_id = p_booking_id
    and payment_stage = 'remaining_balance'
    and amount <= v_payment.amount;

  v_result := public.finalize_package_booking_if_eligible(p_booking_id);
  return v_result || jsonb_build_object(
    'debug_bypass', true, 'already_paid', false,
    'payment_record_id', v_payment.id,
    'payments_modified', true
  );
end;
$$;

revoke all on function public.debug_mark_remaining_balance_paid(uuid)
  from public, anon;
grant execute on function public.debug_mark_remaining_balance_paid(uuid)
  to authenticated;

-- Trigger functions must not be directly callable by API roles.
revoke all on function public.guard_package_booking_client_write()
  from public, anon, authenticated;
revoke all on function public.validate_booking_payment_submission()
  from public, anon, authenticated;

-- Phase 4 scope hardening. This intentionally reapplies only the reviewed
-- current security behavior and its supporting indexes.
create or replace function public.subtenant_can_access_payment_record(
  p_payment_record_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_subtenant_city() is not null
     and exists (
       select 1
       from public.payment_records pr
       where pr.id = p_payment_record_id
         and case
           when pr.booking_id is not null then
             public.subtenant_can_access_booking(pr.booking_id)
           when pr.ride_id is not null then exists (
             select 1
             from public.rides r
             where r.id = pr.ride_id
               and public.subtenant_can_access_driver(r.driver_id)
           )
           else false
         end
     );
$$;

revoke all on function public.subtenant_can_access_payment_record(uuid)
  from public, anon, authenticated;
grant execute on function public.subtenant_can_access_payment_record(uuid)
  to authenticated;

-- Public discovery remains available to Tourists, Drivers, and anonymous
-- users. A Subtenant, however, must not inherit that branch to inspect another
-- LGU's content through its staff session.
drop policy if exists spots_read on public.tourist_spots;
create policy spots_read on public.tourist_spots
for select
using (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
  or (
    public.current_profile_role() is distinct from 'subtenant'
    and status <> 'archived'
  )
);

drop policy if exists spot_images_read on public.tourist_spot_images;
create policy spot_images_read on public.tourist_spot_images
for select to authenticated
using (
  exists (
    select 1
    from public.tourist_spots spot
    where spot.id = spot_id
      and (
        public.is_provincial_admin()
        or public.cities_match(
          spot.city,
          public.current_subtenant_city()
        )
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and spot.status <> 'archived'
        )
      )
  )
);

drop policy if exists packages_read on public.tour_packages;
create policy packages_read on public.tour_packages
for select
using (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
  or (
    public.current_profile_role() is distinct from 'subtenant'
    and status = 'published'
    and visibility_status = 'visible'
  )
);

drop policy if exists package_children_read on public.tour_package_days;
create policy package_children_read on public.tour_package_days
for select to authenticated
using (
  exists (
    select 1
    from public.tour_packages package
    where package.id = package_id
      and (
        public.is_provincial_admin()
        or public.cities_match(
          package.city,
          public.current_subtenant_city()
        )
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and package.status = 'published'
          and package.visibility_status = 'visible'
        )
      )
  )
);

drop policy if exists package_day_items_read
  on public.tour_package_day_items;
create policy package_day_items_read on public.tour_package_day_items
for select to authenticated
using (
  exists (
    select 1
    from public.tour_package_days day
    join public.tour_packages package on package.id = day.package_id
    where day.id = day_id
      and (
        public.is_provincial_admin()
        or public.cities_match(
          package.city,
          public.current_subtenant_city()
        )
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and package.status = 'published'
          and package.visibility_status = 'visible'
        )
      )
  )
);

drop policy if exists package_spots_read on public.tour_package_spots;
create policy package_spots_read on public.tour_package_spots
for select to authenticated
using (
  exists (
    select 1
    from public.tour_packages package
    where package.id = package_id
      and (
        public.is_provincial_admin()
        or public.cities_match(
          package.city,
          public.current_subtenant_city()
        )
        or (
          public.current_profile_role() is distinct from 'subtenant'
          and package.status = 'published'
          and package.visibility_status = 'visible'
        )
      )
  )
);

drop policy if exists announcements_select on public.city_announcements;
create policy announcements_select on public.city_announcements
for select
using (
  public.is_provincial_admin()
  or public.cities_match(city, public.current_subtenant_city())
  or (
    public.current_profile_role() is distinct from 'subtenant'
    and status = 'published'
  )
);

-- WITH CHECK must inspect the proposed ownership keys directly. Depending on
-- a helper that re-reads the row by id can evaluate the pre-update row.
drop policy if exists package_bookings_update_staff_or_owner
  on public.package_bookings;
create policy package_bookings_update_staff_or_owner
on public.package_bookings for update to authenticated
using (
  tourist_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_booking(id)
)
with check (
  tourist_id = auth.uid()
  or public.is_provincial_admin()
  or exists (
    select 1
    from public.tour_packages package
    where package.id = package_bookings.package_id
      and public.cities_match(
        package.city,
        public.current_subtenant_city()
      )
  )
);

drop policy if exists payment_records_update on public.payment_records;
create policy payment_records_update
on public.payment_records for update to authenticated
using (
  payee_id = auth.uid()
  or public.is_provincial_admin()
  or public.subtenant_can_access_payment_record(id)
)
with check (
  payee_id = auth.uid()
  or public.is_provincial_admin()
  or (
    booking_id is not null
    and public.subtenant_can_access_booking(booking_id)
  )
  or (
    booking_id is null
    and ride_id is not null
    and exists (
      select 1
      from public.rides ride
      where ride.id = payment_records.ride_id
        and public.subtenant_can_access_driver(ride.driver_id)
    )
  )
);

-- The function is exposed only to authenticated users, but an explicit null
-- check also protects internal/database invocation paths.
create or replace function public.ensure_booking_group_conversation(
  p_booking_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.package_bookings;
  v_conversation_id uuid;
  v_package_name text;
  v_tourist_name text;
  v_title text;
begin
  if auth.uid() is null then
    raise exception 'UNAUTHENTICATED' using errcode = '42501';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if not public.is_package_booking_participant(p_booking_id) then
    raise exception 'NOT_BOOKING_PARTICIPANT' using errcode = '42501';
  end if;

  select coalesce(nullif(trim(tp.title), ''), 'Tour Package')
  into v_package_name
  from public.tour_packages tp
  where tp.id = v_booking.package_id;
  v_package_name := coalesce(v_package_name, 'Tour Package');

  select coalesce(
    nullif(trim(p.full_name), ''),
    nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Tourist'
  )
  into v_tourist_name
  from public.profiles p
  where p.id = v_booking.tourist_id;
  v_tourist_name := coalesce(v_tourist_name, 'Tourist');
  v_title := v_package_name || ' - ' || v_tourist_name;

  perform set_config('touristrike.system_conversation_write', 'true', true);
  insert into public.conversations (
    tourist_id, driver_id, booking_id, conversation_type, title
  ) values (
    v_booking.tourist_id, null, p_booking_id, 'booking_group', v_title
  )
  on conflict (booking_id)
    where conversation_type = 'booking_group' and booking_id is not null
  do update set tourist_id = excluded.tourist_id, title = excluded.title
  returning id into v_conversation_id;

  insert into public.conversation_members (
    conversation_id, user_id, member_role
  ) values (
    v_conversation_id, v_booking.tourist_id, 'tourist'
  )
  on conflict do nothing;

  insert into public.conversation_members (
    conversation_id, user_id, member_role
  )
  select v_conversation_id, bd.driver_id, 'driver'
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id
    and bd.status in ('accepted', 'completed')
  on conflict do nothing;
  return v_conversation_id;
end;
$$;

revoke all on function public.ensure_booking_group_conversation(uuid)
  from public, anon, authenticated;
grant execute on function public.ensure_booking_group_conversation(uuid)
  to authenticated;

-- Trigger functions do not need direct API execution privileges.
revoke all on function public.guard_subtenant_profile_scope()
  from public, anon, authenticated;
revoke all on function public.guard_subtenant_assignment_scope()
  from public, anon, authenticated;
revoke all on function public.sync_subtenant_assignment_profile()
  from public, anon, authenticated;
revoke all on function public.set_subtenant_local_government_type()
  from public, anon, authenticated;

-- Supporting indexes for RLS EXISTS checks and participant lookups. The live
-- idx_tourist_spot_images_spot_id index already covers spot_id, so the
-- historical duplicate tourist_spot_images_spot_idx is intentionally omitted.
create index if not exists tour_package_day_items_day_idx
  on public.tour_package_day_items(day_id);
create index if not exists booking_itinerary_items_booking_idx
  on public.booking_itinerary_items(booking_id);
create index if not exists payment_disputes_booking_idx
  on public.payment_disputes(booking_id);

-- Retire or repair broken historical functions found by the linked database
-- linter. Each retired entry has a verified current replacement and no caller
-- in the application; the two repaired RPCs remain in active use.

drop function if exists public.credit_driver_wallet(uuid, numeric, uuid, text);
drop function if exists public.deduct_wallet_balance(
  uuid, text, numeric, uuid, text, text
);
drop function if exists public.driver_accept_group_booking(uuid, uuid);
drop function if exists public.admin_list_users(text, text, text, integer, integer);
drop function if exists public.admin_get_user(uuid);

drop function if exists public.approve_city_registration(bigint, text, text);
drop function if exists public.approve_city_registration(uuid, text, text);

create or replace function public.approve_city_registration(
  p_registration_id text,
  p_status text,
  p_rejection_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
  v_user_id uuid;
  v_contact_person text;
  v_office_name text;
  v_city text;
  v_contact_number text;
  v_email text;
  v_office_address text;
  v_normalized_status text;
  v_reviewed_at timestamptz := now();
  v_first_name text;
  v_last_name text;
begin
  if v_admin_id is null then
    raise exception 'Authentication is required.' using errcode = '28000';
  end if;

  if not public.is_provincial_admin() then
    raise exception 'Only the Main Tenant can review registrations.' using errcode = '42501';
  end if;

  v_normalized_status := lower(trim(coalesce(p_status, '')));
  if v_normalized_status not in ('approved', 'rejected') then
    raise exception 'Invalid review status: %', p_status using errcode = '22023';
  end if;

  select
    user_id,
    contact_person,
    office_name,
    city,
    contact_number,
    email,
    office_address
  into
    v_user_id,
    v_contact_person,
    v_office_name,
    v_city,
    v_contact_number,
    v_email,
    v_office_address
  from public.city_tenant_registrations
  where id::text = p_registration_id;

  if not found then
    raise exception 'Registration not found.' using errcode = '22023';
  end if;

  if v_normalized_status = 'approved' then
    if v_user_id is null then
      raise exception 'Registration is not linked to a user account.' using errcode = '22023';
    end if;

    v_first_name := split_part(trim(coalesce(v_contact_person, '')), ' ', 1);
    v_last_name := nullif(
      trim(
        regexp_replace(
          trim(coalesce(v_contact_person, '')),
          '^[^[:space:]]+[[:space:]]*',
          ''
        )
      ),
      ''
    );

    update public.profiles
    set
      role = 'subtenant',
      first_name = coalesce(v_first_name, ''),
      last_name = coalesce(v_last_name, ''),
      full_name = v_contact_person,
      mobile = v_contact_number,
      address = v_office_address,
      city = v_city,
      province = 'Bulacan'
    where id = v_user_id;

    if not found then
      raise exception 'Applicant profile not found.' using errcode = '22023';
    end if;

    insert into public.subtenant_details (
      id,
      office_name,
      city,
      province,
      contact_person,
      contact_number,
      email,
      office_address,
      verification_status,
      is_active,
      approved_by,
      approved_at
    ) values (
      v_user_id,
      v_office_name,
      v_city,
      'Bulacan',
      v_contact_person,
      v_contact_number,
      v_email,
      v_office_address,
      'approved',
      true,
      v_admin_id,
      v_reviewed_at
    )
    on conflict (id) do update set
      office_name = excluded.office_name,
      city = excluded.city,
      province = excluded.province,
      contact_person = excluded.contact_person,
      contact_number = excluded.contact_number,
      email = excluded.email,
      office_address = excluded.office_address,
      verification_status = excluded.verification_status,
      is_active = excluded.is_active,
      approved_by = excluded.approved_by,
      approved_at = excluded.approved_at,
      updated_at = now();
  end if;

  update public.city_tenant_registrations
  set
    status = v_normalized_status,
    reviewed_by = v_admin_id,
    reviewed_at = v_reviewed_at,
    rejection_reason = case
      when v_normalized_status = 'rejected'
      then nullif(trim(coalesce(p_rejection_reason, '')), '')
      else null
    end
  where id::text = p_registration_id;

  return jsonb_build_object(
    'success', true,
    'status', v_normalized_status,
    'message', 'Registration status updated successfully.'
  );
end;
$$;

revoke all on function public.approve_city_registration(text, text, text)
  from public, anon, authenticated;
grant execute on function public.approve_city_registration(text, text, text)
  to authenticated;

create or replace function public.record_payment_allocation_transfer_result(
  p_allocation_id uuid,
  p_succeeded boolean,
  p_provider_transfer_id text,
  p_provider_status text,
  p_last_error text default null
)
returns public.payment_allocations
language plpgsql
security definer
set search_path = public
as $$
declare v_allocation public.payment_allocations;
begin
  select * into v_allocation from public.payment_allocations
  where id = p_allocation_id for update;
  if not found then raise exception 'PAYMENT_ALLOCATION_NOT_FOUND'; end if;
  if v_allocation.status = 'paid' then
    if p_provider_transfer_id is distinct from v_allocation.provider_transfer_id then
      raise exception 'ALLOCATION_ALREADY_PAID_WITH_DIFFERENT_REFERENCE';
    end if;
    return v_allocation;
  end if;
  if v_allocation.status <> 'processing' then raise exception 'PAYOUT_NOT_PROCESSING'; end if;
  if p_succeeded and nullif(p_provider_transfer_id, '') is null then
    raise exception 'PROVIDER_TRANSFER_REFERENCE_REQUIRED';
  end if;

  update public.payment_allocations set
    status = case when p_succeeded then 'paid' else 'failed' end,
    provider_transfer_id = case when p_succeeded
      then p_provider_transfer_id else provider_transfer_id end,
    provider_transfer_status = p_provider_status,
    last_error = case when p_succeeded then null else left(p_last_error, 1000) end,
    paid_at = case when p_succeeded then now() else paid_at end
  where id = p_allocation_id returning * into v_allocation;
  update public.payout_records set
    status = case when p_succeeded then 'paid' else 'failed' end,
    provider_transfer_id = case when p_succeeded
      then p_provider_transfer_id else provider_transfer_id end,
    provider_status = p_provider_status,
    last_error = case when p_succeeded then null else left(p_last_error, 1000) end,
    processed_at = now()
  where payment_allocation_id = p_allocation_id;
  return v_allocation;
end;
$$;
revoke all on function public.record_payment_allocation_transfer_result(
  uuid, boolean, text, text, text
) from public, anon, authenticated;
grant execute on function public.record_payment_allocation_transfer_result(
  uuid, boolean, text, text, text
) to service_role;


commit;
