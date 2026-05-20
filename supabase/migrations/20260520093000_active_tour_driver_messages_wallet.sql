create or replace function public.has_active_tour(p_tourist_id uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.package_bookings b
    where b.tourist_id = p_tourist_id
      and lower(coalesce(b.booking_status, b.status, '')) in (
        'pending',
        'confirmed',
        'accepted',
        'driver_on_the_way',
        'arrived',
        'picked_up',
        'tour_started',
        'ongoing',
        'in_progress'
      )
  )
  or exists (
    select 1
    from public.package_activities a
    where a.tourist_id = p_tourist_id
      and (
        lower(coalesce(a.tour_status, '')) in (
          'driver_on_the_way',
          'arrived',
          'picked_up',
          'tour_started',
          'ongoing',
          'in_progress'
        )
        or lower(coalesce(a.status, '')) in (
          'pending',
          'accepted',
          'ongoing'
        )
      )
  );
$$;

create or replace function public.ensure_single_active_tour_booking()
returns trigger
language plpgsql
as $$
begin
  if public.has_active_tour(new.tourist_id) then
    raise exception
      'You already have an active tour. Please complete or cancel it before booking another package.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_package_bookings_single_active_tour
on public.package_bookings;

create trigger trg_package_bookings_single_active_tour
before insert on public.package_bookings
for each row execute function public.ensure_single_active_tour_booking();

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

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversations'
  ) then
    alter publication supabase_realtime add table public.conversations;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'wallets'
  ) then
    alter publication supabase_realtime add table public.wallets;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'wallet_transactions'
  ) then
    alter publication supabase_realtime add table public.wallet_transactions;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'package_bookings'
  ) then
    alter publication supabase_realtime add table public.package_bookings;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'package_activities'
  ) then
    alter publication supabase_realtime add table public.package_activities;
  end if;
end $$;
