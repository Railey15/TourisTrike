-- Restore the owner-only UPDATE policy required by notification read actions.
-- The notification-delivery migration retained narrow column grants but the
-- deployed schema reconciliation found this RLS policy missing.
begin;

alter table public.notifications enable row level security;

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- A client may update read state only; recipient and notification content stay
-- immutable regardless of role. RLS additionally restricts rows to auth.uid().
revoke update on public.notifications from public, anon, authenticated;
grant update (is_read, read_at) on public.notifications to authenticated;

commit;
