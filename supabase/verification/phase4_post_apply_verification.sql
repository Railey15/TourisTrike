-- Phase 4 post-apply verification (read-only).
-- Run in Supabase SQL Editor after applying Phase 1, 2, 3, then 4.

-- 1. Migration order. Rows are present when migrations were applied through
-- the CLI; SQL Editor applications should rely on the structural checks below.
select version
from supabase_migrations.schema_migrations
where version in (
  '20260905000000',
  '20260905010000',
  '20260905020000',
  '20260905030000'
)
order by version;

-- 2. PostgreSQL/extension readiness. Supabase PostgreSQL 15+ is expected for
-- security_invoker views used by Phase 1.
select current_setting('server_version_num')::integer as server_version_num,
       extname,
       extnamespace::regnamespace as extension_schema
from pg_extension
where extname in ('pgcrypto', 'pg_trgm')
order by extname;

-- 3. All required relations. This query must return zero rows.
with required_relation(name) as (
  values
    ('public.profiles'), ('public.admin_settings'),
    ('public.subtenant_details'), ('public.subtenant_fare_settings'),
    ('public.tourist_spots'), ('public.tourist_spot_images'),
    ('public.tourist_spot_views'), ('public.tour_packages'),
    ('public.tour_package_days'), ('public.tour_package_day_items'),
    ('public.tour_package_spots'), ('public.tour_package_views'),
    ('public.package_bookings'), ('public.booking_itinerary_items'),
    ('public.customized_package_spots'),
    ('public.booking_driver_assignments'), ('public.booking_drivers'),
    ('public.driver_details'), ('public.driver_documents'),
    ('public.driver_applications'), ('public.rides'),
    ('public.package_activities'), ('public.driver_reviews'),
    ('public.ride_reviews'), ('public.ride_feedback'),
    ('public.package_reviews'), ('public.city_announcements'),
    ('public.notifications'), ('public.audit_logs'),
    ('public.booking_payment_requirements'), ('public.trip_status_logs'),
    ('public.driver_live_locations'), ('public.booking_driver_arrivals'),
    ('public.emergency_alerts'), ('public.package_cancellation_policy'),
    ('public.payment_records'), ('public.payment_disputes'),
    ('public.payment_provider_events'), ('public.driver_payout_accounts'),
    ('public.payment_allocations'), ('public.payout_records'),
    ('public.refund_requests'), ('public.conversations'),
    ('public.conversation_members'), ('storage.objects')
)
select name as missing_relation
from required_relation
where to_regclass(name) is null;

-- 4. UUID transaction schema required by Phase 1. Every actual_type must be
-- uuid. A bigint result means the older migration baseline is incompatible.
with expected(table_schema, table_name, column_name, expected_type) as (
  values
    ('public', 'package_bookings', 'id', 'uuid'),
    ('public', 'booking_driver_assignments', 'booking_id', 'uuid'),
    ('public', 'booking_drivers', 'booking_id', 'uuid'),
    ('public', 'booking_itinerary_items', 'booking_id', 'uuid'),
    ('public', 'package_activities', 'booking_id', 'uuid'),
    ('public', 'package_reviews', 'booking_id', 'uuid'),
    ('public', 'booking_payment_requirements', 'booking_id', 'uuid'),
    ('public', 'trip_status_logs', 'booking_id', 'uuid'),
    ('public', 'emergency_alerts', 'booking_id', 'uuid'),
    ('public', 'conversations', 'booking_id', 'uuid'),
    ('public', 'rides', 'id', 'uuid'),
    ('public', 'payment_records', 'id', 'uuid'),
    ('public', 'payment_records', 'booking_id', 'uuid'),
    ('public', 'payment_records', 'ride_id', 'uuid'),
    ('public', 'payment_disputes', 'payment_record_id', 'uuid'),
    ('public', 'payment_disputes', 'booking_id', 'uuid'),
    ('public', 'payment_provider_events', 'payment_record_id', 'uuid'),
    ('public', 'payment_allocations', 'booking_id', 'uuid'),
    ('public', 'payout_records', 'booking_id', 'uuid'),
    ('public', 'refund_requests', 'booking_id', 'uuid')
)
select expected.table_name,
       expected.column_name,
       expected.expected_type,
       columns.data_type as actual_type
from expected
left join information_schema.columns columns
  using (table_schema, table_name, column_name)
where columns.data_type is distinct from expected.expected_type;

-- 5. Required Phase 1-4 columns. This query must return zero rows.
with expected(table_name, column_name) as (
  values
    ('subtenant_details', 'local_government_type'),
    ('subtenant_details', 'office_name_customized'),
    ('subtenant_details', 'local_government_type_reviewed'),
    ('admin_settings', 'enable_ai_suggestions'),
    ('admin_settings', 'default_package_visibility'),
    ('admin_settings', 'default_spot_status')
)
select expected.*
from expected
left join information_schema.columns columns
  on columns.table_schema = 'public'
 and columns.table_name = expected.table_name
 and columns.column_name = expected.column_name
where columns.column_name is null;

-- 6. RLS must be enabled on all scoped data tables. relrowsecurity must be true.
select namespace.nspname as schema_name,
       class.relname as table_name,
       class.relrowsecurity,
       class.relforcerowsecurity
from pg_class class
join pg_namespace namespace on namespace.oid = class.relnamespace
where namespace.nspname = 'public'
  and class.relname in (
    'profiles', 'subtenant_details', 'subtenant_fare_settings',
    'tourist_spots', 'tour_packages', 'package_bookings',
    'booking_drivers', 'driver_details', 'driver_documents',
    'payment_records', 'payment_disputes', 'payment_allocations',
    'payout_records', 'city_announcements', 'notifications'
  )
order by class.relname;

-- 7. No obsolete broad policies should remain. Returns zero rows.
select schemaname, tablename, policyname, cmd, qual, with_check
from pg_policies
where (tablename = 'booking_drivers'
       and policyname = 'booking_drivers_read_all')
   or (tablename = 'driver_live_locations'
       and policyname = 'live_loc_read_all')
   or (tablename = 'trip_status_logs'
       and policyname in ('trip_logs_read_all', 'trip_logs_insert_any'))
   or (tablename = '_deprecated_payments'
       and policyname = 'Admins and subtenants can view all payments');

-- 8. Review effective policies on the highest-risk tables.
select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname in ('public', 'storage')
  and tablename in (
    'subtenant_details', 'tourist_spots', 'tour_packages',
    'package_bookings', 'driver_details', 'payment_records',
    'payment_disputes', 'objects'
  )
order by schemaname, tablename, policyname;

-- 9. SECURITY DEFINER posture and fixed search_path.
select namespace.nspname as schema_name,
       procedure.proname,
       pg_get_function_identity_arguments(procedure.oid) as arguments,
       procedure.prosecdef as security_definer,
       procedure.proconfig,
       procedure.proacl
from pg_proc procedure
join pg_namespace namespace on namespace.oid = procedure.pronamespace
where namespace.nspname = 'public'
  and procedure.proname in (
    'is_provincial_admin', 'current_subtenant_city',
    'subtenant_can_access_driver', 'subtenant_can_access_booking',
    'subtenant_can_access_payment_record',
    'is_package_booking_participant', 'confirm_payment_record',
    'resolve_payment_dispute', 'get_payment_reconciliation',
    'ensure_booking_group_conversation', 'get_convoy_stage_progress'
  )
order by procedure.proname;

-- 10. API function grants. Anonymous execution should be false except for the
-- two read-policy helpers explicitly needed by public spot/package policies.
select
  has_function_privilege(
    'anon', 'public.is_provincial_admin()', 'execute'
  ) as anon_admin_helper,
  has_function_privilege(
    'anon', 'public.current_subtenant_city()', 'execute'
  ) as anon_city_helper,
  has_function_privilege(
    'anon', 'public.subtenant_can_access_booking(uuid)', 'execute'
  ) as anon_booking_helper_must_be_false,
  has_function_privilege(
    'authenticated',
    'public.subtenant_can_access_booking(uuid)',
    'execute'
  ) as authenticated_booking_helper,
  has_function_privilege(
    'anon',
    'public.ensure_booking_group_conversation(uuid)',
    'execute'
  ) as anon_conversation_rpc_must_be_false;

-- 11. Assignment guard/sync triggers. All four names must be present and enabled.
select event_object_table,
       trigger_name,
       action_timing,
       event_manipulation,
       action_statement
from information_schema.triggers
where trigger_schema = 'public'
  and trigger_name in (
    'guard_subtenant_profile_scope',
    'guard_subtenant_assignment_scope',
    'sync_subtenant_assignment_profile',
    'set_subtenant_local_government_type'
  )
order by trigger_name, event_manipulation;

-- 12. Required supporting indexes. All names must be returned.
select schemaname, tablename, indexname
from pg_indexes
where schemaname = 'public'
  and indexname in (
    'subtenant_details_admin_search_idx',
    'tourist_spots_admin_search_idx',
    'tour_packages_admin_search_idx',
    'profiles_driver_admin_search_idx',
    'tourist_spot_images_spot_idx',
    'tour_package_day_items_day_idx',
    'booking_itinerary_items_booking_idx',
    'payment_disputes_booking_idx'
  )
order by indexname;

-- 13. Data-quality review queues.
select id, city, office_name, local_government_type
from public.subtenant_details
where local_government_type_reviewed is not true
order by city;

select settings.user_id
from public.admin_settings settings
join public.profiles profile on profile.id = settings.user_id
where profile.role = 'subtenant'
  and settings.enable_ai_suggestions is distinct from true;
