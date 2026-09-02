begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(30);

select has_table('public', 'payment_provider_events',
  'provider webhook events are persisted');
select has_table('public', 'payment_allocations',
  'group payment allocations are persisted');
select has_table('public', 'driver_payout_accounts',
  'provider payout destinations are normalized');
select has_view('public', 'payment_allocation_summaries',
  'participants have a safe allocation summary view');
select has_column('public', 'payment_records', 'provider_checkout_id',
  'payment records store checkout session IDs');
select has_column('public', 'payment_records', 'provider_payment_id',
  'payment records store provider payment IDs');
select has_column('public', 'payment_records', 'provider_livemode',
  'test and live provider records cannot be silently mixed');
select has_column('public', 'refund_requests', 'provider_refund_id',
  'refund audit rows can link provider-confirmed refunds');

select has_function('public', 'prepare_paymongo_payment',
  array['uuid', 'text', 'text', 'uuid', 'boolean'],
  'trusted payment preparation RPC exists');
select ok(
  not has_function_privilege(
    'authenticated',
    'public.prepare_paymongo_payment(uuid,text,text,uuid,boolean)',
    'execute'
  ),
  'clients cannot call trusted payment preparation directly'
);
select has_function('public', 'process_paymongo_webhook_event',
  array['text','text','boolean','text','text','text','text','text',
        'bigint','bigint','bigint','jsonb'],
  'idempotent provider webhook RPC exists');
select ok(
  not has_function_privilege(
    'authenticated',
    'public.process_paymongo_webhook_event(text,text,boolean,text,text,text,text,text,bigint,bigint,bigint,jsonb)',
    'execute'
  ),
  'clients cannot forge webhook processing'
);
select ok(
  exists (
    select 1 from pg_indexes where schemaname = 'public'
      and tablename = 'payment_provider_events'
      and indexdef like '%UNIQUE%provider%provider_event_id%'
  ),
  'provider event IDs are unique per provider'
);
select ok(
  pg_get_functiondef('public.confirm_payment_record(uuid)'::regprocedure)
    like '%PROVIDER_WEBHOOK_REQUIRED%',
  'manual confirmation cannot confirm PayMongo payments'
);

select has_function('public', 'compute_equal_split_centavos',
  array['bigint', 'integer'], 'centavo-safe split helper exists');
select is(
  (select array_agg(amount_centavos order by recipient_position)
   from public.compute_equal_split_centavos(200000, 2)),
  array[100000,100000]::bigint[],
  'two drivers split PHP 2,000 evenly'
);
select is(
  (select array_agg(amount_centavos order by recipient_position)
   from public.compute_equal_split_centavos(360000, 2)),
  array[180000,180000]::bigint[],
  'PHP 3,600 stage splits into two exact PHP 1,800 shares'
);
select is(
  (select array_agg(basis_points order by recipient_position)
   from public.compute_equal_split_centavos(200000, 2)),
  array[5000,5000]::integer[],
  'two linked accounts split net payment evenly'
);
select is(
  (select array_agg(amount_centavos order by recipient_position)
   from public.compute_equal_split_centavos(100000, 3)),
  array[33334,33333,33333]::bigint[],
  'three-driver centavo remainder goes to the first accepted driver'
);
select is(
  (select sum(amount_centavos)
   from public.compute_equal_split_centavos(100000, 3)),
  100000::numeric,
  'three-driver allocations preserve the full amount'
);
select is(
  (select sum(basis_points)
   from public.compute_equal_split_centavos(100000, 3)),
  10000::bigint,
  'provider percentage splits total exactly 100 percent'
);
select is(
  (select array_agg(amount_centavos order by recipient_position)
   from public.compute_equal_split_centavos(360000, 4)),
  array[90000,90000,90000,90000]::bigint[],
  'four drivers split PHP 3,600 into exact PHP 900 shares'
);
select is(
  (select array_agg(amount_centavos order by recipient_position)
   from public.compute_equal_split_centavos(100001, 3)),
  array[33334,33334,33333]::bigint[],
  'multiple remainder centavos go one each to the first ordered drivers'
);

select has_function('public', 'claim_payment_allocation_for_payout',
  array['uuid'], 'payout claims have a locking state transition');
select ok(
  pg_get_functiondef(
    'public.claim_payment_allocation_for_payout(uuid)'::regprocedure
  ) like '%ALLOCATION_ALREADY_PAID%',
  'a paid allocation cannot be paid twice'
);
select ok(
  pg_get_functiondef(
    'public.claim_payment_allocation_for_payout(uuid)'::regprocedure
  ) like '%status not in (''eligible'', ''failed'')%',
  'only eligible payouts and explicit failed retries can be claimed'
);
select has_function('public', 'get_payment_reconciliation', array['uuid'],
  'staff reconciliation RPC exists');
select has_function('public', 'record_paymongo_refund_result',
  array['uuid', 'text', 'text', 'jsonb'],
  'provider refund result RPC exists');
select ok(
  pg_get_functiondef(
    'public.guard_paymongo_refund_completion()'::regprocedure
  ) like '%PROVIDER_REFUND_CONFIRMATION_REQUIRED%',
  'manual actors cannot mark a PayMongo refund completed'
);

select has_function('public', 'prepare_group_cash_remaining_balance',
  array['uuid', 'text'], 'tourists can prepare an authoritative cash balance');
select has_function('public', 'confirm_group_cash_share', array['uuid'],
  'assigned drivers confirm only their cash allocation');
select ok(
  pg_get_functiondef(
    'public.confirm_group_cash_share(uuid)'::regprocedure
  ) like '%driver_id = auth.uid()%cash_confirmed%',
  'cash receipt confirmation is scoped to the authenticated driver share'
);

select * from finish();
rollback;
