-- Booking location coverage only. No historical data is rewritten.
-- GeoJSON is WGS84 longitude/latitude. Both client and server cover boundary
-- edges (1e-10 degree numeric tolerance), exclude holes, and include islands.
begin;

create or replace function public.service_area_geometry_valid(g jsonb)
returns boolean language plpgsql immutable set search_path = public as $$
declare polygons jsonb; p jsonb; r jsonb; c jsonb;
begin
  if g->>'type' = 'Polygon' then polygons := jsonb_build_array(g->'coordinates');
  elsif g->>'type' = 'MultiPolygon' then polygons := g->'coordinates';
  else return false; end if;
  if jsonb_typeof(polygons) is distinct from 'array' or jsonb_array_length(polygons) = 0 then return false; end if;
  for p in select value from jsonb_array_elements(polygons) loop
    if jsonb_typeof(p) is distinct from 'array' or jsonb_array_length(p) = 0 then return false; end if;
    for r in select value from jsonb_array_elements(p) loop
      if jsonb_typeof(r) is distinct from 'array' or jsonb_array_length(r) < 4 or r->0 <> r->-1 then return false; end if;
      for c in select value from jsonb_array_elements(r) loop
        if jsonb_typeof(c) is distinct from 'array' or jsonb_array_length(c) <> 2
          or jsonb_typeof(c->0) is distinct from 'number' or jsonb_typeof(c->1) is distinct from 'number'
          or not ((c->>0)::double precision between -180 and 180)
          or not ((c->>1)::double precision between -90 and 90) then return false; end if;
      end loop;
    end loop;
  end loop;
  return true;
exception when others then return false;
end $$;

create table public.booking_service_areas (
  id text primary key,
  municipality text not null,
  province text not null,
  municipality_aliases text[] not null check (cardinality(municipality_aliases) > 0),
  geometry jsonb not null check (public.service_area_geometry_valid(geometry)),
  version text not null,
  source_url text not null,
  source_license text not null,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.booking_service_areas enable row level security;
revoke all on public.booking_service_areas from anon, authenticated;
grant select on public.booking_service_areas to authenticated;
grant all on public.booking_service_areas to service_role;
create policy booking_service_areas_read on public.booking_service_areas
  for select to authenticated using (active);
-- Configuration writes intentionally require a trusted server/database role.

create or replace function public.service_area_ring_position(r jsonb, x double precision, y double precision)
returns integer language plpgsql immutable strict set search_path = public as $$
declare a jsonb; b jsonb; ax double precision; ay double precision;
  bx double precision; by_ double precision; dx double precision; dy double precision;
  inside boolean := false; epsilon constant double precision := 1e-10;
begin
  a := r->0;
  for i in 1..jsonb_array_length(r)-1 loop
    b := r->i;
    ax := (a->>0)::double precision; ay := (a->>1)::double precision;
    bx := (b->>0)::double precision; by_ := (b->>1)::double precision;
    dx := bx-ax; dy := by_-ay;
    if abs(dx*(y-ay)-dy*(x-ax)) <= epsilon*sqrt(dx*dx+dy*dy)
      and x between least(ax,bx)-epsilon and greatest(ax,bx)+epsilon
      and y between least(ay,by_)-epsilon and greatest(ay,by_)+epsilon then return 2; end if;
    if (ay>y) <> (by_>y) then
      if x < dx*(y-ay)/dy+ax then inside := not inside; end if;
    end if;
    a := b;
  end loop;
  return case when inside then 1 else 0 end;
end $$;

create or replace function public.service_area_covers(g jsonb, latitude double precision, longitude double precision)
returns boolean language plpgsql immutable set search_path = public as $$
declare polygons jsonb; p jsonb; hole jsonb; position integer; in_hole boolean;
begin
  if g is null or latitude is null or longitude is null
    or not (latitude between -90 and 90) or not (longitude between -180 and 180) then return false; end if;
  polygons := case when g->>'type' = 'Polygon' then jsonb_build_array(g->'coordinates') else g->'coordinates' end;
  for p in select value from jsonb_array_elements(polygons) loop
    position := public.service_area_ring_position(p->0, longitude, latitude);
    if position = 2 then return true; end if;
    if position = 0 then continue; end if;
    in_hole := false;
    for hole in select value from jsonb_array_elements(p) with ordinality r(value,n) where n>1 loop
      position := public.service_area_ring_position(hole, longitude, latitude);
      if position = 2 then return true; end if;
      if position = 1 then in_hole := true; end if;
    end loop;
    if not in_hole then return true; end if;
  end loop;
  return false;
end $$;

-- Resolve exclusively from the stored package and its owning subtenant.
-- Client-supplied municipality/province and address labels are never trusted.
create or replace function public.resolve_booking_service_area(p_package_id bigint)
returns public.booking_service_areas language plpgsql stable security definer set search_path = public as $$
declare area public.booking_service_areas;
begin
  select a.* into strict area from public.tour_packages p
    join public.subtenant_details s on s.id = p.submitted_by
    join public.booking_service_areas a on a.active
      and lower(trim(p.city)) = any(a.municipality_aliases)
      and lower(trim(s.city)) = any(a.municipality_aliases)
      and lower(trim(s.province)) = lower(trim(a.province))
    where p.id = p_package_id;
  return area;
exception when no_data_found or too_many_rows then
  raise exception 'The service area for this package is not configured. Please contact support.' using errcode = 'P0001';
end $$;

create or replace function public.booking_service_area(p_package_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare area public.booking_service_areas;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  area := public.resolve_booking_service_area(p_package_id);
  return jsonb_build_object('id',area.id,'municipality',area.municipality,
    'province',area.province,'geometry',area.geometry,'version',area.version);
end $$;

create or replace function public.validate_booking_service_area()
returns trigger language plpgsql security definer set search_path = public as $$
declare area public.booking_service_areas;
begin
  if tg_op = 'UPDATE' then
    if row(new.package_id,new.pickup_latitude,new.pickup_longitude,new.dropoff_latitude,new.dropoff_longitude)
      is not distinct from row(old.package_id,old.pickup_latitude,old.pickup_longitude,old.dropoff_latitude,old.dropoff_longitude)
      then return new; end if;
  end if;
  area := public.resolve_booking_service_area(new.package_id);
  if not public.service_area_covers(area.geometry,new.pickup_latitude,new.pickup_longitude) then
    raise exception 'Pickup outside service area. Please select a location within %.',area.municipality using errcode = 'P0001';
  end if;
  if not public.service_area_covers(area.geometry,new.dropoff_latitude,new.dropoff_longitude) then
    raise exception 'Drop-off outside service area. Please select a location within %.',area.municipality using errcode = 'P0001';
  end if;
  if tg_op = 'UPDATE' then
    if new.package_id is distinct from old.package_id and (
      exists(select 1 from public.booking_itinerary_items i where i.booking_id = old.id
        and not public.service_area_covers(area.geometry,i.latitude,i.longitude))
      or exists(select 1 from public.customized_package_spots s where s.booking_id = old.id
        and s.action_type is distinct from 'removed'
        and not public.service_area_covers(area.geometry,s.latitude,s.longitude))) then
      raise exception 'Destination outside service area. Please select a location within %.',area.municipality using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
create trigger trg_booking_service_area before insert or update of package_id,
  pickup_latitude,pickup_longitude,dropoff_latitude,dropoff_longitude on public.package_bookings
  for each row execute function public.validate_booking_service_area();

create or replace function public.validate_booking_destination_service_area()
returns trigger language plpgsql security definer set search_path = public as $$
declare area public.booking_service_areas; package_id bigint;
begin
  if tg_table_name = 'customized_package_spots' and to_jsonb(new)->>'action_type' = 'removed' then return new; end if;
  if tg_op = 'UPDATE' then
    if row(new.booking_id,new.latitude,new.longitude,to_jsonb(new)->>'action_type')
      is not distinct from row(old.booking_id,old.latitude,old.longitude,to_jsonb(old)->>'action_type')
      then return new; end if;
  end if;
  select b.package_id into package_id from public.package_bookings b where b.id = new.booking_id;
  area := public.resolve_booking_service_area(package_id);
  if not public.service_area_covers(area.geometry,new.latitude,new.longitude) then
    raise exception 'Destination outside service area. Please select a location within %.',area.municipality using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger trg_itinerary_service_area before insert or update of booking_id,latitude,longitude
  on public.booking_itinerary_items for each row execute function public.validate_booking_destination_service_area();
create trigger trg_customized_spot_service_area before insert or update of booking_id,latitude,longitude,action_type
  on public.customized_package_spots for each row execute function public.validate_booking_destination_service_area();

revoke all on function public.resolve_booking_service_area(bigint),
  public.validate_booking_service_area(),public.validate_booking_destination_service_area(),
  public.booking_service_area(bigint) from public,anon,authenticated;
grant execute on function public.booking_service_area(bigint) to authenticated;
commit;
