-- Read-only post-deployment checks. No bookings, GPS events or lifecycle writes.
-- One result set so the CLI/Management API cannot hide earlier check results.
begin read only;
with checks(check_name, passed) as (
  select 'installed: ' || signature, to_regprocedure(signature) is not null
  from (values
    ('public.observe_driver_journey_location(uuid,double precision,double precision,double precision,double precision,timestamptz)'),
    ('public.recover_driver_journey(uuid,text,integer,text)'),
    ('public.get_tour_tracking_status(uuid)'),
    ('public.reconcile_stale_tour_tracking(uuid)')
  ) f(signature)
  union all
  select 'evidence RLS enabled', relrowsecurity
    from pg_class where oid='public.driver_journey_evidence'::regclass
  union all
  select 'evidence RPC-only for ' || role_name,
    not has_table_privilege(role_name,'public.driver_journey_evidence','select,insert,update,delete,truncate,references,trigger')
    from (values ('anon'),('authenticated')) r(role_name)
  union all
  select 'anonymous cannot call: ' || signature,
    not has_function_privilege('anon',signature,'execute')
    from (values
      ('public.observe_driver_journey_location(uuid,double precision,double precision,double precision,double precision,timestamptz)'),
      ('public.recover_driver_journey(uuid,text,integer,text)'),
      ('public.get_tour_tracking_status(uuid)'),
      ('public.reconcile_stale_tour_tracking(uuid)')
    ) f(signature)
  union all
  select 'authenticated can call: ' || signature,
    has_function_privilege('authenticated',signature,'execute')
    from (values
      ('public.observe_driver_journey_location(uuid,double precision,double precision,double precision,double precision,timestamptz)'),
      ('public.recover_driver_journey(uuid,text,integer,text)'),
      ('public.get_tour_tracking_status(uuid)')
    ) f(signature)
  union all
  select 'clients cannot reconcile arbitrary tours',
    not has_function_privilege('authenticated','public.reconcile_stale_tour_tracking(uuid)','execute')
  union all
  select 'enabled guard: ' || trigger_name, exists (
    select 1 from pg_trigger where tgrelid='public.booking_drivers'::regclass
      and tgname=trigger_name and tgenabled='O'
  ) from (values
    ('guard_verified_journey_transition'),
    ('trg_guard_live_driver_journey_proximity'),
    ('trg_guard_driver_completion_remaining_payment'),
    ('trg_persist_driver_stop_milestones')
  ) t(trigger_name)
  union all
  select 'server-owned interruption field guard', exists (
    select 1 from pg_trigger where tgrelid='public.package_bookings'::regclass
      and tgname='guard_tour_automation_fields' and tgenabled='O'
  )
  union all
  select 'nullable actual interruption timestamp', exists (
    select 1 from information_schema.columns where table_schema='public'
      and table_name='package_bookings' and column_name='tracking_interrupted_at'
      and data_type='timestamp with time zone' and is_nullable='YES'
      and column_default is null
  )
  union all
  select 'scheduled recovery active every five minutes', exists (
    select 1 from cron.job where jobname='touristrike-stale-tours'
      and schedule='*/5 * * * *' and active
      and command='select public.reconcile_stale_tour_tracking()'
  )
  union all
  select 'arrival/departure actual timestamps retained', count(*)=2
    from information_schema.columns where table_schema='public'
      and table_name='booking_driver_arrivals' and column_name in ('arrived_at','departed_at')
      and data_type='timestamp with time zone'
)
select check_name, passed from checks order by check_name;
commit;
