-- PayMongo provider metadata and a normalized per-driver allocation ledger.
-- Provider secrets never belong in these tables; only opaque IDs and webhook
-- evidence are persisted.

alter table public.payment_records
  add column if not exists provider text not null default 'manual',
  add column if not exists currency text not null default 'PHP',
  add column if not exists provider_payment_id text,
  add column if not exists provider_payment_intent_id text,
  add column if not exists provider_checkout_id text,
  add column if not exists provider_reference text,
  add column if not exists provider_status text,
  add column if not exists provider_payload jsonb,
  add column if not exists provider_livemode boolean,
  add column if not exists provider_fee_amount numeric(14,2),
  add column if not exists provider_net_amount numeric(14,2),
  add column if not exists checkout_url text,
  add column if not exists idempotency_key text,
  add column if not exists paid_at timestamptz,
  add column if not exists provider_failure_code text,
  add column if not exists provider_failure_message text;

alter table public.payment_records alter column payee_id drop not null;

alter table public.payment_records
  drop constraint if exists payment_records_provider_check;
alter table public.payment_records
  add constraint payment_records_provider_check
  check (provider in ('manual', 'paymongo'));

alter table public.payment_records
  drop constraint if exists payment_records_currency_check;
alter table public.payment_records
  add constraint payment_records_currency_check check (currency = 'PHP');

alter table public.payment_records
  drop constraint if exists payment_records_provider_party_check;
alter table public.payment_records
  add constraint payment_records_provider_party_check check (
    (provider = 'manual' and payee_id is not null)
    or (provider = 'paymongo' and booking_id is not null)
  );

alter table public.payment_records
  drop constraint if exists payment_records_provider_amounts_check;
alter table public.payment_records
  add constraint payment_records_provider_amounts_check check (
    (provider_fee_amount is null or provider_fee_amount >= 0)
    and (provider_net_amount is null or provider_net_amount >= 0)
  );

create unique index if not exists payment_records_provider_checkout_uidx
  on public.payment_records(provider, provider_checkout_id)
  where provider_checkout_id is not null;
create unique index if not exists payment_records_provider_payment_uidx
  on public.payment_records(provider, provider_payment_id)
  where provider_payment_id is not null;
create unique index if not exists payment_records_provider_idempotency_uidx
  on public.payment_records(provider, idempotency_key)
  where idempotency_key is not null;

create table if not exists public.payment_provider_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('paymongo')),
  provider_event_id text not null,
  event_type text not null,
  provider_livemode boolean,
  provider_payment_id text,
  provider_checkout_id text,
  payment_record_id uuid references public.payment_records(id) on delete set null,
  processing_status text not null default 'received'
    check (processing_status in ('received', 'processed', 'ignored', 'rejected', 'failed')),
  process_error text,
  payload jsonb not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (provider, provider_event_id)
);

create index if not exists payment_provider_events_payment_idx
  on public.payment_provider_events(payment_record_id, received_at desc);

create table if not exists public.driver_payout_accounts (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null check (provider in ('paymongo')),
  destination_type text not null
    check (destination_type in ('linked_account', 'disbursement')),
  destination_provider text,
  account_name text,
  account_number_masked text,
  provider_recipient_id text,
  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'verified', 'rejected', 'disabled')),
  provider_livemode boolean not null default false,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (driver_id, provider, provider_livemode, provider_recipient_id)
);

create unique index if not exists driver_payout_accounts_one_default_uidx
  on public.driver_payout_accounts(driver_id, provider, provider_livemode)
  where is_default and verification_status = 'verified';

drop trigger if exists set_driver_payout_accounts_updated_at
  on public.driver_payout_accounts;
create trigger set_driver_payout_accounts_updated_at
before update on public.driver_payout_accounts
for each row execute function public.set_updated_at();

create table if not exists public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  payment_record_id uuid not null references public.payment_records(id) on delete restrict,
  booking_id uuid not null references public.package_bookings(id) on delete restrict,
  booking_driver_id uuid not null references public.booking_drivers(id) on delete restrict,
  driver_id uuid not null references public.profiles(id) on delete restrict,
  gross_amount numeric(14,2) not null check (gross_amount > 0),
  platform_fee numeric(14,2) not null default 0 check (platform_fee >= 0),
  driver_amount numeric(14,2) not null check (driver_amount >= 0),
  split_basis_points integer not null check (split_basis_points between 1 and 10000),
  currency text not null default 'PHP' check (currency = 'PHP'),
  status text not null default 'held'
    check (status in (
      'held', 'eligible', 'processing', 'paid', 'failed', 'cancelled',
      'manual_review'
    )),
  provider_recipient_id text,
  provider_transfer_id text,
  provider_transfer_status text,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (payment_record_id, driver_id)
);

create index if not exists payment_allocations_booking_idx
  on public.payment_allocations(booking_id, status);
create index if not exists payment_allocations_driver_idx
  on public.payment_allocations(driver_id, status);
create unique index if not exists payment_allocations_provider_transfer_uidx
  on public.payment_allocations(provider_transfer_id)
  where provider_transfer_id is not null;

drop trigger if exists set_payment_allocations_updated_at
  on public.payment_allocations;
create trigger set_payment_allocations_updated_at
before update on public.payment_allocations
for each row execute function public.set_updated_at();

alter table public.refund_requests
  add column if not exists provider_refund_id text,
  add column if not exists provider_refund_status text,
  add column if not exists provider_payload jsonb,
  add column if not exists provider_confirmed_at timestamptz;

-- Direct/manual refunds still carry the driver's payee_id. A PayMongo refund
-- is against the platform payment and therefore has no single driver payee.
alter table public.refund_requests alter column payee_id drop not null;

create unique index if not exists refund_requests_provider_refund_uidx
  on public.refund_requests(provider_refund_id)
  where provider_refund_id is not null;

alter table public.payout_records
  add column if not exists payment_allocation_id uuid
    references public.payment_allocations(id) on delete restrict,
  add column if not exists provider_transfer_id text,
  add column if not exists provider_status text,
  add column if not exists attempt_count integer not null default 0,
  add column if not exists last_error text,
  add column if not exists processed_at timestamptz,
  add column if not exists provider_livemode boolean;

alter table public.payout_records drop constraint if exists payout_records_status_check;
alter table public.payout_records add constraint payout_records_status_check
  check (status in (
    'pending', 'held', 'eligible', 'processing', 'paid', 'failed',
    'cancelled', 'manual_review'
  ));

create unique index if not exists payout_records_allocation_uidx
  on public.payout_records(payment_allocation_id)
  where payment_allocation_id is not null;
create unique index if not exists payout_records_provider_transfer_uidx
  on public.payout_records(provider_transfer_id)
  where provider_transfer_id is not null;

alter table public.payment_provider_events enable row level security;
alter table public.driver_payout_accounts enable row level security;
alter table public.payment_allocations enable row level security;

drop policy if exists payment_provider_events_staff_read
  on public.payment_provider_events;
create policy payment_provider_events_staff_read
on public.payment_provider_events for select to authenticated
using (public.current_profile_role() in ('admin', 'subtenant'));

drop policy if exists driver_payout_accounts_owner_or_staff_read
  on public.driver_payout_accounts;
create policy driver_payout_accounts_owner_or_staff_read
on public.driver_payout_accounts for select to authenticated
using (
  driver_id = auth.uid()
  or public.current_profile_role() in ('admin', 'subtenant')
);

drop policy if exists payment_allocations_participant_read
  on public.payment_allocations;
create policy payment_allocations_participant_read
on public.payment_allocations for select to authenticated
using (
  driver_id = auth.uid()
  or public.current_profile_role() in ('admin', 'subtenant')
);

create or replace view public.payment_allocation_summaries
with (security_barrier = true)
as
select pa.id, pa.payment_record_id, pa.booking_id, pa.driver_id,
       pa.gross_amount, pa.platform_fee, pa.driver_amount,
       pa.split_basis_points, pa.currency,
       pa.status, pa.provider_transfer_status, pa.created_at, pa.updated_at
from public.payment_allocations pa
where pa.driver_id = auth.uid()
   or exists (
     select 1 from public.package_bookings pb
     where pb.id = pa.booking_id and pb.tourist_id = auth.uid()
   )
   or public.current_profile_role() in ('admin', 'subtenant');

revoke all on public.payment_allocation_summaries from public, anon;
grant select on public.payment_allocation_summaries to authenticated;

-- No authenticated INSERT/UPDATE/DELETE policies: provider evidence,
-- destinations, allocations, and payout state are trusted-backend writes.

drop policy if exists payment_records_select on public.payment_records;
create policy payment_records_select
on public.payment_records for select to authenticated
using (
  payer_id = auth.uid()
  or payee_id = auth.uid()
  or exists (
    select 1 from public.payment_allocations pa
    where pa.payment_record_id = payment_records.id
      and pa.driver_id = auth.uid()
  )
  or public.current_profile_role() in ('admin', 'subtenant')
);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'payment_allocations'
  ) then
    alter publication supabase_realtime add table public.payment_allocations;
  end if;
end $$;
