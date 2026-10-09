-- Every persisted tourism package must contain 3 to 6 real municipality spots.
-- The save RPCs are SECURITY INVOKER so the existing package/spot RLS policies
-- remain authoritative for municipal ownership.

create or replace function public.enforce_tour_package_spot_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_package_id bigint;
  v_spot_count integer;
begin
  if tg_table_name = 'tour_packages' then
    v_package_id := coalesce(new.id, old.id);
  else
    v_package_id := coalesce(new.package_id, old.package_id);
  end if;

  -- Cascading child deletes run while deleting the parent and need no count.
  if not exists (
    select 1 from public.tour_packages where id = v_package_id
  ) then
    return null;
  end if;

  select count(*)::integer
  into v_spot_count
  from public.tour_package_spots
  where package_id = v_package_id;

  if v_spot_count < 3 or v_spot_count > 6 then
    raise exception using
      errcode = '23514',
      message = format(
        'Tour packages must contain between 3 and 6 spots (received %s).',
        v_spot_count
      ),
      constraint = 'tour_packages_spot_count_between_3_and_6';
  end if;

  return null;
end;
$$;

revoke all on function public.enforce_tour_package_spot_count() from public;

drop trigger if exists enforce_package_spot_count_on_package
  on public.tour_packages;
create constraint trigger enforce_package_spot_count_on_package
after insert or update on public.tour_packages
deferrable initially deferred
for each row execute function public.enforce_tour_package_spot_count();

drop trigger if exists enforce_package_spot_count_on_spot
  on public.tour_package_spots;
create constraint trigger enforce_package_spot_count_on_spot
after insert or update or delete on public.tour_package_spots
deferrable initially deferred
for each row execute function public.enforce_tour_package_spot_count();

create or replace function public.replace_tour_package_spots(
  p_package_id bigint,
  p_spots jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_city text;
  v_count integer;
  v_distinct_count integer;
begin
  if jsonb_typeof(p_spots) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'Package spots must be an array.';
  end if;

  v_count := jsonb_array_length(p_spots);
  if v_count < 3 or v_count > 6 then
    raise exception using
      errcode = '23514',
      message = format(
        'Tour packages must contain between 3 and 6 spots (received %s).',
        v_count
      ),
      constraint = 'tour_packages_spot_count_between_3_and_6';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_spots) item
    where jsonb_typeof(item) is distinct from 'object'
      or coalesce(item ->> 'spot_id', '') !~ '^[0-9]+$'
  ) then
    raise exception using errcode = '22023', message = 'Every package spot must have a valid spot ID.';
  end if;

  select count(distinct (item ->> 'spot_id')::bigint)::integer
  into v_distinct_count
  from jsonb_array_elements(p_spots) item;

  if v_distinct_count <> v_count then
    raise exception using errcode = '23505', message = 'A package cannot contain duplicate spots.';
  end if;

  select city
  into v_city
  from public.tour_packages
  where id = p_package_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Package not found or access denied.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_spots) item
    left join public.tourist_spots spot
      on spot.id = (item ->> 'spot_id')::bigint
    where spot.id is null
      or not public.cities_match(spot.city, v_city)
  ) then
    raise exception using errcode = '23514', message = 'Package spots must belong to the package municipality.';
  end if;

  delete from public.tour_package_spots
  where package_id = p_package_id;

  insert into public.tour_package_spots (
    package_id,
    spot_id,
    sort_order,
    opening_time,
    closing_time,
    estimated_arrival_time,
    estimated_duration_minutes,
    recommended_visit_duration_minutes
  )
  select
    p_package_id,
    (item ->> 'spot_id')::bigint,
    coalesce((item ->> 'sort_order')::integer, ordinal - 1),
    nullif(item ->> 'opening_time', '')::time,
    nullif(item ->> 'closing_time', '')::time,
    nullif(item ->> 'estimated_arrival_time', '')::time,
    coalesce((item ->> 'estimated_duration_minutes')::integer, 0),
    coalesce((item ->> 'recommended_visit_duration_minutes')::integer, 0)
  from jsonb_array_elements(p_spots) with ordinality as rows(item, ordinal);
end;
$$;

create or replace function public.save_tour_package_with_spots(
  p_package_id bigint,
  p_values jsonb,
  p_spots jsonb
)
returns bigint
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_package_id bigint;
  v_city text;
  v_affected integer;
begin
  if jsonb_typeof(p_values) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'Package values must be an object.';
  end if;

  v_city := nullif(trim(p_values ->> 'city'), '');
  if v_city is null then
    raise exception using errcode = '23502', message = 'Package municipality is required.';
  end if;

  if p_package_id is null then
    insert into public.tour_packages (
      title,
      subtitle,
      city,
      price_text,
      duration_text,
      image_url,
      status,
      description,
      submitted_by,
      submitted_by_name,
      visibility_status,
      estimated_budget,
      route_distance_km,
      cover_image_url,
      category_id
    ) values (
      trim(p_values ->> 'title'),
      p_values ->> 'subtitle',
      v_city,
      p_values ->> 'price_text',
      p_values ->> 'duration_text',
      p_values ->> 'image_url',
      coalesce(nullif(p_values ->> 'status', ''), 'draft'),
      p_values ->> 'description',
      auth.uid(),
      p_values ->> 'submitted_by_name',
      coalesce(nullif(p_values ->> 'visibility_status', ''), 'hidden'),
      coalesce((p_values ->> 'estimated_budget')::numeric, 0),
      coalesce((p_values ->> 'route_distance_km')::numeric, 0),
      p_values ->> 'cover_image_url',
      nullif(p_values ->> 'category_id', '')::bigint
    )
    returning id into v_package_id;
  else
    update public.tour_packages
    set title = trim(p_values ->> 'title'),
        subtitle = p_values ->> 'subtitle',
        price_text = p_values ->> 'price_text',
        duration_text = p_values ->> 'duration_text',
        image_url = p_values ->> 'image_url',
        status = coalesce(nullif(p_values ->> 'status', ''), status),
        description = p_values ->> 'description',
        submitted_by_name = p_values ->> 'submitted_by_name',
        visibility_status = coalesce(
          nullif(p_values ->> 'visibility_status', ''),
          visibility_status
        ),
        estimated_budget = coalesce(
          (p_values ->> 'estimated_budget')::numeric,
          estimated_budget
        ),
        route_distance_km = coalesce(
          (p_values ->> 'route_distance_km')::numeric,
          route_distance_km
        ),
        cover_image_url = p_values ->> 'cover_image_url',
        category_id = case
          when p_values ? 'category_id'
            then nullif(p_values ->> 'category_id', '')::bigint
          else category_id
        end,
        updated_at = now()
    where id = p_package_id
      and public.cities_match(city, v_city)
    returning id into v_package_id;

    get diagnostics v_affected = row_count;
    if v_affected <> 1 then
      raise exception using errcode = 'P0002', message = 'Package not found or access denied.';
    end if;
  end if;

  perform public.replace_tour_package_spots(v_package_id, p_spots);
  return v_package_id;
end;
$$;

revoke all on function public.replace_tour_package_spots(bigint, jsonb) from public;
revoke all on function public.save_tour_package_with_spots(bigint, jsonb, jsonb) from public;
grant execute on function public.replace_tour_package_spots(bigint, jsonb) to authenticated;
grant execute on function public.save_tour_package_with_spots(bigint, jsonb, jsonb) to authenticated;

comment on function public.replace_tour_package_spots(bigint, jsonb) is
  'Atomically replaces a package itinerary with 3 to 6 municipality-owned spots while preserving table RLS.';
comment on function public.save_tour_package_with_spots(bigint, jsonb, jsonb) is
  'Atomically creates or updates package metadata and its required 3 to 6 spots while preserving table RLS.';
