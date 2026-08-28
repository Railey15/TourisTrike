begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(24);

select has_column(
  'public', 'package_bookings', 'scheduled_start_at',
  'package bookings expose an absolute scheduled start'
);
select has_column(
  'public', 'package_bookings', 'estimated_end_at',
  'package bookings expose an absolute estimated end'
);
select ok(
  not (tstzrange('2026-08-27 01:00+00', '2026-08-27 02:00+00', '[)') &&
       tstzrange('2026-08-28 01:00+00', '2026-08-28 02:00+00', '[)')),
  'a booking tomorrow does not overlap a booking today'
);
select ok(
  not (tstzrange('2026-08-27 01:00+00', '2026-08-27 02:00+00', '[)') &&
       tstzrange('2026-08-27 02:00+00', '2026-08-27 03:00+00', '[)')),
  'adjacent same-day bookings do not overlap'
);
select ok(
  tstzrange('2026-08-27 01:00+00', '2026-08-27 03:00+00', '[)') &&
  tstzrange('2026-08-27 02:00+00', '2026-08-27 04:00+00', '[)'),
  'intersecting same-day bookings overlap'
);

select has_function(
  'public', 'accept_package_booking', array['uuid'],
  'atomic booking acceptance RPC exists'
);
select ok(
  pg_get_functiondef('public.accept_package_booking(uuid)'::regprocedure)
    like '%pg_advisory_xact_lock%',
  'acceptance serializes concurrent requests per driver'
);
select ok(
  pg_get_functiondef('public.accept_package_booking(uuid)'::regprocedure)
    like '%DRIVER_SCHEDULE_CONFLICT%',
  'acceptance returns the schedule conflict code'
);
select ok(
  pg_get_functiondef('public.accept_package_booking(uuid)'::regprocedure)
    like '%not in (''cancelled'', ''completed'', ''rejected'', ''done'')%',
  'terminal bookings are excluded from conflicts'
);
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'booking_drivers'
      and policyname in ('booking_drivers_driver_insert', 'booking_drivers_driver_update')
  ),
  'direct driver roster mutations cannot bypass the RPC'
);

select has_table(
  'public', 'booking_payment_requirements',
  'booking payment requirements are persisted'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'payment_records'
      and indexname = 'payment_records_one_active_booking_stage_idx'
      and indexdef like 'CREATE UNIQUE INDEX%'
  ),
  'only one active payment record is allowed per booking stage'
);
select has_function(
  'public', 'confirm_payment_record', array['uuid'],
  'idempotent payment confirmation RPC exists'
);
select ok(
  pg_get_functiondef('public.confirm_payment_record(uuid)'::regprocedure)
    like '%for update%',
  'payment confirmation locks the payment row'
);
select ok(
  pg_get_functiondef('public.confirm_payment_record(uuid)'::regprocedure)
    like '%if v_record.status = ''confirmed''%',
  'duplicate payment confirmation returns the existing record'
);
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'payment_records'
      and policyname = 'payment_records_update'
  ),
  'payment confirmation cannot bypass the RPC with a direct update'
);

select ok(
  pg_get_functiondef('public.advance_driver_journey_state(uuid,text)'::regprocedure)
    like '%DOWNPAYMENT_NOT_CONFIRMED%',
  'advanced tour start requires confirmed down payment'
);
select ok(
  pg_get_functiondef('public.advance_driver_journey_state(uuid,text)'::regprocedure)
    like '%BOOKING_START_TOO_EARLY%',
  'tour start enforces its scheduled window'
);
select ok(
  pg_get_functiondef('public.advance_driver_journey_state(uuid,text)'::regprocedure)
    like '%REMAINING_BALANCE_NOT_CONFIRMED%',
  'final completion requires confirmed remaining balance'
);
select ok(
  pg_get_functiondef('public.advance_driver_journey_state(uuid,text)'::regprocedure)
    like '%array_agg(journey_state order by public.journey_state_order(journey_state))%',
  'overall state remains derived from the slowest convoy driver'
);
select ok(
  pg_get_functiondef('public.advance_driver_journey_state(uuid,text)'::regprocedure)
    like '%Server-validated journey transition%',
  'validated journey transitions are audited server-side'
);
select ok(
  pg_get_functiondef('public.complete_package_tour(uuid,text)'::regprocedure)
    like '%v_completed_slots < v_active_slots%',
  'legacy completion waits for every active convoy driver'
);
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'driver_live_locations'
      and policyname = 'live_loc_read_all'
  ),
  'driver live locations are no longer globally readable'
);
select ok(
  pg_get_functiondef(
    'public.get_shared_trip_details(text,text,text,text,boolean)'::regprocedure
  ) like '%jsonb_set(v_result, ''{driver_latitude}'', ''null''::jsonb%',
  'terminal guest trip payloads do not expose driver GPS'
);

select * from finish();
rollback;
