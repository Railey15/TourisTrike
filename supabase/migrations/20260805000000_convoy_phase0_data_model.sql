-- ============================================================
-- Convoy Sync — Phase 0: data model only. No Dart changes ride on
-- this migration; it is purely additive (new columns with safe
-- defaults, one new table, one new pure function). Existing solo
-- (required_drivers = 1) bookings are unaffected.
--
-- Context: package_activities has exactly one driver_id column
-- (UNIQUE(booking_id) — see 20260517000000_wallet_system.sql) so it
-- can only ever represent ONE driver per booking. accept_package_booking
-- only writes to it once the group's LAST slot is filled. booking_drivers
-- is the table that actually holds one row per accepted driver, and it
-- becomes the new source of truth for per-driver journey/barrier state
-- (package_activities.driver_id / tour_status are being deprecated —
-- Phase 2+ will move the driver + tourist screens off of them).
-- ============================================================

-- ── 1. Per-driver journey state + barrier timing on booking_drivers ──
-- journey_state is intentionally `text` + CHECK, not a Postgres ENUM —
-- enum types are painful to extend later (ALTER TYPE ADD VALUE can't run
-- inside the same transaction as its first use on some PG versions).
-- The Dart-side single source of truth (Phase 2, lib/core/models/
-- convoy_state.dart) must mirror this exact list of values.
alter table public.booking_drivers
  add column if not exists journey_state text not null default 'assigned',
  add column if not exists state_updated_at timestamptz not null default now(),
  add column if not exists current_stop_index integer not null default 0,
  add column if not exists assigned_passengers integer not null default 0;

alter table public.booking_drivers
  drop constraint if exists booking_drivers_journey_state_check;
alter table public.booking_drivers
  add constraint booking_drivers_journey_state_check
  check (journey_state in (
    'assigned',
    'en_route_pickup', 'at_pickup', 'boarded',
    'en_route_stop', 'at_stop', 'stop_done',
    'en_route_dropoff', 'at_dropoff',
    'completed'
  ));

-- state_updated_at must only move when journey_state actually changes —
-- the >10min / >20min deadlock timers (Phase 2) read this column, so a
-- touch on an unrelated column (e.g. a future position ping) must not
-- silently reset a driver's "stuck" timer.
create or replace function public.set_booking_driver_state_updated_at()
returns trigger
language plpgsql
as $$
begin
  if new.journey_state is distinct from old.journey_state then
    new.state_updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_booking_driver_state_updated_at on public.booking_drivers;
create trigger trg_booking_driver_state_updated_at
before update on public.booking_drivers
for each row execute function public.set_booking_driver_state_updated_at();

-- ── 2. Passenger auto-split helper (pure function, not wired to any
--    trigger/RPC yet — Phase 2 decides when it's called). Floor division,
--    remainder to the first-accepted driver, per your answer to Open
--    Question 2. This is the ONE place that logic lives.
create or replace function public.compute_passenger_split(
  p_booking_id uuid,
  p_total_passengers integer
)
returns table (driver_id uuid, passenger_count integer)
language plpgsql
stable
set search_path = public
as $$
declare
  v_driver_count integer;
  v_base_count integer;
  v_remainder integer;
  v_first_driver uuid;
begin
  select count(*) into v_driver_count
  from public.booking_drivers
  where booking_id = p_booking_id and status = 'accepted';

  if v_driver_count = 0 or p_total_passengers <= 0 then
    return;
  end if;

  v_base_count := p_total_passengers / v_driver_count;
  v_remainder := p_total_passengers % v_driver_count;

  select bd.driver_id into v_first_driver
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id and bd.status = 'accepted'
  order by bd.accepted_at asc
  limit 1;

  return query
  select bd.driver_id,
         case when bd.driver_id = v_first_driver
              then v_base_count + v_remainder
              else v_base_count
         end
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id and bd.status = 'accepted';
end;
$$;

-- ── 3. payout_records: per-driver share of a booking's payment ──
-- Schema + split-math helper ONLY (Requirement B). Nothing in the app
-- writes here yet, and this design deliberately stays neutral about HOW
-- money physically reaches the driver (direct GCash-to-GCash settlement,
-- same non-custodial model as payment_records, vs a future PayMongo
-- Disbursement/Platforms payout) until the open PayMongo questions in
-- the chat report are resolved. paymongo_reference is nullable and only
-- gets populated if/when that integration actually lands.
create table if not exists public.payout_records (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.package_bookings(id),
  driver_id  uuid not null references public.profiles(id),
  payment_stage text not null default 'full'
    check (payment_stage in ('down_payment', 'remaining_balance', 'full')),
  split_strategy text not null default 'equal_split'
    check (split_strategy in ('equal_split', 'per_passenger')),
  amount numeric not null default 0 check (amount >= 0),
  gcash_number_snapshot text,
  gcash_name_snapshot text,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'paid', 'failed')),
  paymongo_reference text,
  source_payment_record_id uuid references public.payment_records(id),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (booking_id, driver_id, payment_stage)
);

create index if not exists idx_payout_records_booking on public.payout_records(booking_id);
create index if not exists idx_payout_records_driver on public.payout_records(driver_id);
create index if not exists idx_payout_records_status on public.payout_records(status);

drop trigger if exists set_payout_records_updated_at on public.payout_records;
create trigger set_payout_records_updated_at before update on public.payout_records
for each row execute function public.set_updated_at();

alter table public.payout_records enable row level security;

drop policy if exists payout_records_select on public.payout_records;
create policy payout_records_select
on public.payout_records
for select
using (
  auth.uid() = driver_id
  or public.current_profile_role() in ('admin', 'subtenant')
);

-- No insert/update policy for `authenticated` on purpose — Phase 0 has no
-- integration, so only a future SECURITY DEFINER RPC (or service_role)
-- should ever write to this table.

-- ── 4. Money split helper (mirrors compute_passenger_split above) ──
-- Also unused by any trigger/RPC yet. This is the single place to change
-- if the split rule moves from equal_split to per_passenger later.
create or replace function public.compute_payout_split(
  p_booking_id uuid,
  p_total_amount numeric,
  p_strategy text default 'equal_split'
)
returns table (driver_id uuid, amount numeric)
language plpgsql
stable
set search_path = public
as $$
declare
  v_driver_count integer;
  v_base_share numeric;
  v_remainder numeric;
  v_first_driver uuid;
begin
  select count(*) into v_driver_count
  from public.booking_drivers
  where booking_id = p_booking_id and status = 'accepted';

  if v_driver_count = 0 then
    return;
  end if;

  if p_strategy <> 'equal_split' then
    raise exception 'UNSUPPORTED_SPLIT_STRATEGY: %', p_strategy;
  end if;

  v_base_share := trunc(p_total_amount / v_driver_count, 2);
  v_remainder := p_total_amount - (v_base_share * v_driver_count);

  select bd.driver_id into v_first_driver
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id and bd.status = 'accepted'
  order by bd.accepted_at asc
  limit 1;

  return query
  select bd.driver_id,
         case when bd.driver_id = v_first_driver
              then v_base_share + v_remainder
              else v_base_share
         end
  from public.booking_drivers bd
  where bd.booking_id = p_booking_id and bd.status = 'accepted';
end;
$$;
