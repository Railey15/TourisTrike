alter table public.tour_package_spots
  add column if not exists opening_time time,
  add column if not exists closing_time time,
  add column if not exists estimated_arrival_time time,
  add column if not exists estimated_duration_minutes integer,
  add column if not exists recommended_visit_duration_minutes integer;

alter table public.customized_package_spots
  add column if not exists opening_time time,
  add column if not exists closing_time time,
  add column if not exists estimated_arrival_time time,
  add column if not exists estimated_duration_minutes integer,
  add column if not exists recommended_visit_duration_minutes integer;

create table if not exists public.emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  tourist_id uuid not null references public.profiles(id) on delete cascade,
  name text not null default '',
  phone_number text not null default '',
  relationship text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists set_emergency_contacts_updated_at on public.emergency_contacts;
create trigger set_emergency_contacts_updated_at
before update on public.emergency_contacts
for each row execute function public.set_updated_at();

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  tourist_id uuid not null references public.profiles(id) on delete cascade,
  driver_id uuid not null references public.profiles(id) on delete cascade,
  booking_id bigint not null references public.package_bookings(id) on delete cascade,
  last_message text not null default '',
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index if not exists conversations_unique_booking_pair_idx
  on public.conversations (tourist_id, driver_id, booking_id);

create index if not exists conversations_tourist_idx
  on public.conversations (tourist_id, last_message_at desc);

create index if not exists conversations_driver_idx
  on public.conversations (driver_id, last_message_at desc);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid references public.profiles(id) on delete set null,
  message_text text not null default '',
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists messages_conversation_idx
  on public.messages (conversation_id, created_at asc);

create index if not exists messages_sender_idx
  on public.messages (sender_id, created_at desc);

alter table public.emergency_contacts enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

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

drop policy if exists conversations_select_participants on public.conversations;
create policy conversations_select_participants on public.conversations
for select using (auth.uid() = tourist_id or auth.uid() = driver_id);

drop policy if exists conversations_insert_participants on public.conversations;
create policy conversations_insert_participants on public.conversations
for insert with check (
  (auth.uid() = tourist_id or auth.uid() = driver_id)
  and exists (
    select 1
    from public.package_bookings b
    where b.id = booking_id
      and b.tourist_id = conversations.tourist_id
      and b.assigned_driver_id = conversations.driver_id
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
);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversations'
  ) then
    alter publication supabase_realtime add table public.conversations;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;
