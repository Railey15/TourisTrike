-- Add schedule/duration columns to tourist_spots that the app already reads
-- (tour_package_spots and customized_package_spots already have these from
--  migration 20260519040000_tour_schedule_emergency_and_messages.sql)

alter table public.tourist_spots
  add column if not exists opening_time time,
  add column if not exists closing_time time,
  add column if not exists estimated_arrival_time time,
  add column if not exists estimated_duration_minutes integer not null default 0,
  add column if not exists recommended_visit_duration_minutes integer not null default 0;

-- Also add to tour_package_spots if somehow missing (idempotent)
alter table public.tour_package_spots
  add column if not exists opening_time time,
  add column if not exists closing_time time,
  add column if not exists estimated_arrival_time time,
  add column if not exists estimated_duration_minutes integer not null default 0,
  add column if not exists recommended_visit_duration_minutes integer not null default 0;

-- Also add to customized_package_spots if somehow missing (idempotent)
alter table public.customized_package_spots
  add column if not exists opening_time time,
  add column if not exists closing_time time,
  add column if not exists estimated_arrival_time time,
  add column if not exists estimated_duration_minutes integer not null default 0,
  add column if not exists recommended_visit_duration_minutes integer not null default 0;

-- Ensure emergency_contacts exists with all expected columns
create table if not exists public.emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  tourist_id uuid not null references public.profiles(id) on delete cascade,
  name text not null default '',
  phone_number text not null default '',
  relationship text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- RLS for emergency_contacts (idempotent)
alter table public.emergency_contacts enable row level security;

drop policy if exists emergency_contacts_select_own on public.emergency_contacts;
create policy emergency_contacts_select_own on public.emergency_contacts
  for select using (tourist_id = auth.uid());

drop policy if exists emergency_contacts_insert_own on public.emergency_contacts;
create policy emergency_contacts_insert_own on public.emergency_contacts
  for insert with check (tourist_id = auth.uid());

drop policy if exists emergency_contacts_update_own on public.emergency_contacts;
create policy emergency_contacts_update_own on public.emergency_contacts
  for update using (tourist_id = auth.uid())
  with check (tourist_id = auth.uid());

drop policy if exists emergency_contacts_delete_own on public.emergency_contacts;
create policy emergency_contacts_delete_own on public.emergency_contacts
  for delete using (tourist_id = auth.uid());

-- Ensure updated_at trigger on emergency_contacts
drop trigger if exists set_emergency_contacts_updated_at on public.emergency_contacts;
create trigger set_emergency_contacts_updated_at
  before update on public.emergency_contacts
  for each row execute function public.set_updated_at();

-- Ensure conversations/messages RLS reflects both driver_accepted and activity-assigned drivers
-- (supersedes earlier, stricter insert policy that only allowed assigned_driver_id)

alter table public.conversations enable row level security;
alter table public.messages enable row level security;

drop policy if exists conversations_select_participants on public.conversations;
create policy conversations_select_participants on public.conversations
  for select using (auth.uid() = tourist_id or auth.uid() = driver_id);

drop policy if exists conversations_insert_participants on public.conversations;
create policy conversations_insert_participants on public.conversations
  for insert with check (
    (auth.uid() = tourist_id or auth.uid() = driver_id)
    and booking_id is not null
    and (
      exists (
        select 1
        from public.package_bookings b
        where b.id = conversations.booking_id
          and b.tourist_id = conversations.tourist_id
          and coalesce(b.assigned_driver_id, conversations.driver_id) = conversations.driver_id
      )
      or exists (
        select 1
        from public.package_activities a
        where a.booking_id = conversations.booking_id
          and a.tourist_id = conversations.tourist_id
          and a.driver_id = conversations.driver_id
      )
    )
  );

drop policy if exists conversations_update_participants on public.conversations;
create policy conversations_update_participants on public.conversations
  for update using (auth.uid() = tourist_id or auth.uid() = driver_id)
  with check (auth.uid() = tourist_id or auth.uid() = driver_id);

drop policy if exists messages_select_participants on public.messages;
create policy messages_select_participants on public.messages
  for select using (
    exists (
      select 1
      from public.conversations c
      where c.id = messages.conversation_id
        and (c.tourist_id = auth.uid() or c.driver_id = auth.uid())
    )
  );

drop policy if exists messages_insert_participants on public.messages;
create policy messages_insert_participants on public.messages
  for insert with check (
    sender_id = auth.uid()
    and exists (
      select 1
      from public.conversations c
      where c.id = messages.conversation_id
        and (c.tourist_id = auth.uid() or c.driver_id = auth.uid())
    )
  );

drop policy if exists messages_update_participants on public.messages;
create policy messages_update_participants on public.messages
  for update using (
    exists (
      select 1
      from public.conversations c
      where c.id = messages.conversation_id
        and (c.tourist_id = auth.uid() or c.driver_id = auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.conversations c
      where c.id = messages.conversation_id
        and (c.tourist_id = auth.uid() or c.driver_id = auth.uid())
    )
  );

-- Allow tourists/drivers to see each other's profile via conversation or booking
drop policy if exists profiles_select_assigned_driver_or_chat on public.profiles;
create policy profiles_select_assigned_driver_or_chat on public.profiles
  for select using (
    exists (
      select 1
      from public.conversations c
      where (c.tourist_id = auth.uid() and c.driver_id = profiles.id)
         or (c.driver_id = auth.uid() and c.tourist_id = profiles.id)
    )
    or exists (
      select 1
      from public.package_bookings b
      where (b.tourist_id = auth.uid() and b.assigned_driver_id = profiles.id)
         or (b.assigned_driver_id = auth.uid() and b.tourist_id = profiles.id)
    )
    or exists (
      select 1
      from public.package_activities a
      where (a.tourist_id = auth.uid() and a.driver_id = profiles.id)
         or (a.driver_id = auth.uid() and a.tourist_id = profiles.id)
    )
  );
