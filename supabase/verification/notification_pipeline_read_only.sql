-- Safe to run before notification migration deployment. No mutations or secrets.
select jsonb_build_object(
  'checked_at', now(),
  'tables', (select jsonb_object_agg(name,to_regclass('public.' || name) is not null)
    from unnest(array['notifications','notification_devices','notification_deliveries','notification_events',
      'notification_settings','booking_driver_arrivals','developer_test_bookings']) name),
  'notification_columns', (select jsonb_agg(jsonb_build_object('table',table_name,'column',column_name,'type',data_type)
    order by table_name,ordinal_position) from information_schema.columns
    where table_schema='public' and table_name in ('notifications','notification_devices','notification_deliveries')),
  'functions', (select jsonb_agg(jsonb_build_object('name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),
    'security_definer',p.prosecdef)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
    and (p.proname like '%notification%' or p.proname in ('advance_driver_journey_state','persist_driver_stop_milestones',
      'required_booking_driver_roster','is_developer_test_booking','journey_state_order'))),
  'triggers', (select jsonb_agg(jsonb_build_object('table',c.relname,'name',t.tgname,'enabled',t.tgenabled,
    'definition',pg_get_triggerdef(t.oid))) from pg_trigger t join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace where not t.tgisinternal and n.nspname='public'
      and (t.tgname like '%notif%' or c.relname in ('notifications','booking_driver_arrivals'))),
  'policies', (select jsonb_agg(jsonb_build_object('table',tablename,'name',policyname,'command',cmd,'using',qual,'check',with_check))
    from pg_policies where schemaname='public' and tablename in ('notifications','notification_devices','notification_deliveries')),
  'indexes', (select jsonb_agg(jsonb_build_object('table',tablename,'name',indexname,'definition',indexdef))
    from pg_indexes where schemaname='public' and tablename in ('notifications','notification_devices','notification_deliveries')),
  'realtime', (select jsonb_agg(tablename) from pg_publication_tables where pubname='supabase_realtime' and tablename='notifications'),
  'extensions', (select jsonb_agg(extname) from pg_extension where extname in ('pg_cron','pg_net','supabase_vault')),
  'notification_migration_history', (select jsonb_agg(version) from supabase_migrations.schema_migrations
    where version >= '20260924000000')
) as notification_pipeline;
