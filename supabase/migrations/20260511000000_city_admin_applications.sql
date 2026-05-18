-- City admin application flow and role-approval guardrails.

create index if not exists city_tenant_registrations_user_status_idx
on public.city_tenant_registrations(user_id, status, submitted_at desc);

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
for insert with check (
  id = auth.uid()
  and role in ('tourist', 'driver')
);

drop policy if exists profiles_update_self_or_admin on public.profiles;
drop policy if exists profiles_update_self on public.profiles;
drop policy if exists profiles_update_admin on public.profiles;

create policy profiles_update_self on public.profiles
for update using (id = auth.uid())
with check (
  id = auth.uid()
  and role = public.current_profile_role()
);

create policy profiles_update_admin on public.profiles
for update using (public.current_profile_role() = 'admin')
with check (public.current_profile_role() = 'admin');
