-- Read-only evidence for the reported iPlant Cafe arrival; no credentials.
select jsonb_build_object(
  'checked_at',now(),
  'arrival', (select jsonb_agg(jsonb_build_object('id',id,'title',title,'type',type,
    'created_at',created_at,'user_id',user_id,'booking_id',booking_id,
    'is_read',is_read,'push_enabled',push_enabled,'dedupe_key',dedupe_key))
    from public.notifications where booking_id='b19410d6-a64c-4676-8690-80b78b7c68ca' and type='spot_arrived'),
  'devices', (select count(*) from public.notification_devices),
  'deliveries', (select count(*) from public.notification_deliveries),
  'test_accounts', (select jsonb_agg(jsonb_build_object('user_id',u,'active_devices',
    (select count(*) from public.notification_devices d where d.user_id=u and d.active)))
    from unnest(array['9c7091f5-8797-4e72-a85d-585d65b3b312'::uuid,'bec9af99-aff4-4742-991f-756d37da76b0'::uuid]) u)
) as evidence;
