-- A minimal, private ledger for signed Didit session status callbacks.
-- Detailed identity documents and decision payloads are deliberately omitted.
create table if not exists public.didit_verification_events (
  event_id uuid primary key,
  session_id uuid not null,
  webhook_type text not null check (webhook_type = 'status.updated'),
  status text not null,
  event_created_at timestamptz not null,
  workflow_id uuid,
  application_id uuid,
  environment text check (environment in ('live', 'sandbox')),
  vendor_data text,
  received_at timestamptz not null default now()
);

create index if not exists didit_verification_events_session_time_idx
  on public.didit_verification_events (session_id, event_created_at desc);

alter table public.didit_verification_events enable row level security;
revoke all on public.didit_verification_events from anon, authenticated;
