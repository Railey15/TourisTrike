-- Scoped live verification. Failed INSERT probes reuse an existing primary key
-- and must fail BEFORE insertion. Everything is additionally rolled back.
-- Does not update bookings, send notifications, or expose personal details.
begin;
do $$
declare b public.package_bookings; area public.booking_service_areas; point jsonb;
begin
  select pb.* into b from public.package_bookings pb
    join public.tour_packages p on p.id=pb.package_id
    where lower(p.city) in ('baliwag','baliuag') limit 1;
  if not found then raise exception 'No existing Baliwag booking available for safe negative probes'; end if;
  area := public.resolve_booking_service_area(b.package_id);
  point := case when area.geometry->>'type' = 'Polygon' then area.geometry->'coordinates'->0->0
    else area.geometry->'coordinates'->0->0->0 end;
  begin
    insert into public.package_bookings select (jsonb_populate_record(null::public.package_bookings,
      to_jsonb(b)||jsonb_build_object('pickup_latitude',0,'pickup_longitude',0))).*;
    raise exception 'Expected pickup rejection was missing';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'Pickup outside service area.%' then raise; end if;
  end;
  begin
    insert into public.package_bookings select (jsonb_populate_record(null::public.package_bookings,
      to_jsonb(b)||jsonb_build_object('pickup_latitude',(point->>1)::double precision,
        'pickup_longitude',(point->>0)::double precision,'dropoff_latitude',0,'dropoff_longitude',0))).*;
    raise exception 'Expected drop-off rejection was missing';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'Drop-off outside service area.%' then raise; end if;
  end;
end $$;
select jsonb_build_object(
  'invalid_pickup_and_dropoff_rejected',true,
  'active_areas',(select count(*) from public.booking_service_areas where active),
  'protected_tables',(select count(*) from pg_trigger where not tgisinternal and tgname in
    ('trg_booking_service_area','trg_itinerary_service_area','trg_customized_spot_service_area')),
  'package_coverage',(select jsonb_agg(jsonb_build_object('id',p.id,'area',(public.resolve_booking_service_area(p.id)).id)) from public.tour_packages p),
  'outside_package_spots',(select jsonb_agg(jsonb_build_object('package_id',p.id,'spot_id',s.id,'title',to_jsonb(s)->>'title'))
    from public.tour_packages p join public.tour_package_spots ps on ps.package_id=p.id
    join public.tourist_spots s on s.id=ps.spot_id
    where not public.service_area_covers((public.resolve_booking_service_area(p.id)).geometry,s.latitude,s.longitude))
) as verification;
rollback;
