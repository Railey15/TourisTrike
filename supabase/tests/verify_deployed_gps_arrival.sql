-- Read-only deployment verification. All four rows must exist and match.
with expected(signature, body_md5) as (
  values
    ('public.debug_advance_driver_journey_state(uuid,text)', 'b0f06127fa0693b06a0f2a834bc45caa'),
    ('public.driver_arrival_radius_meters()', 'fe184bd8ee1513d0340490ba47d20738'),
    ('public.guard_live_driver_journey_proximity()', '1efb7964256b24851e5837361f0007d6'),
    ('public.confirm_driver_arrival_fallback(uuid,text)', '404e4a8ba5f6fbdee3db3c4a9de8dd3d')
)
select e.signature,
       p.oid is not null as function_exists,
       pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_function_result(p.oid) as returns,
       md5(replace(p.prosrc, chr(13), '')) = e.body_md5 as matches_prepared_sql,
       pg_get_functiondef(p.oid) as deployed_definition
from expected e
left join pg_proc p on p.oid = to_regprocedure(e.signature);

-- Expected: 150.
select public.driver_arrival_radius_meters() as arrival_radius_meters;

-- Expected: uses_shared_radius=true for BOTH functions.
select proname,
       position('public.driver_arrival_radius_meters()' in prosrc) > 0
         as uses_shared_radius
from pg_proc
where oid in (
  to_regprocedure('public.guard_live_driver_journey_proximity()'),
  to_regprocedure('public.confirm_driver_arrival_fallback(uuid,text)')
);

-- Expected: the proximity trigger is enabled on public.booking_drivers.
select tgname, tgenabled, pg_get_triggerdef(oid) as trigger_definition
from pg_trigger
where tgrelid = 'public.booking_drivers'::regclass
  and tgfoid = to_regprocedure('public.guard_live_driver_journey_proximity()');

-- Expected: all four tables are in the realtime publication.
select tablename
from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public'
  and tablename in (
    'booking_drivers', 'package_activities',
    'booking_itinerary_items', 'driver_live_locations'
  )
order by tablename;
