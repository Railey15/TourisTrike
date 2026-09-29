-- Municipality-aware office cover branding. The existing cover_image_url
-- remains authoritative; these columns preserve provenance and attribution.

begin;

alter table public.subtenant_details
  add column if not exists cover_image_source text,
  add column if not exists cover_image_attribution text,
  add column if not exists cover_image_source_url text,
  add column if not exists cover_image_updated_at timestamptz;

alter table public.subtenant_details
  drop constraint if exists subtenant_details_cover_image_source_check;
alter table public.subtenant_details
  add constraint subtenant_details_cover_image_source_check
  check (
    cover_image_source is null
    or cover_image_source in ('uploaded', 'touristrike', 'pexels', 'default')
  );

alter table public.subtenant_details
  drop constraint if exists subtenant_details_cover_image_consistency_check;
alter table public.subtenant_details
  add constraint subtenant_details_cover_image_consistency_check
  check (
    (cover_image_url is null and cover_image_source is null)
    or (
      nullif(btrim(cover_image_url), '') is not null
      and cover_image_source is not null
    )
  ) not valid;

update public.subtenant_details
set
  cover_image_url = null,
  cover_image_source = null,
  cover_image_attribution = null,
  cover_image_source_url = null
where nullif(btrim(cover_image_url), '') is null;

-- Existing cover URLs predate source metadata. Treat them as prior manual
-- selections without rewriting or replacing the URL itself.
update public.subtenant_details
set
  cover_image_source = 'uploaded',
  cover_image_updated_at = coalesce(updated_at, now())
where nullif(btrim(cover_image_url), '') is not null
  and cover_image_source is null;

alter table public.subtenant_details
  validate constraint subtenant_details_cover_image_consistency_check;

create or replace function public.validate_subtenant_cover_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_url text := nullif(btrim(new.cover_image_url), '');
  v_source text := nullif(btrim(new.cover_image_source), '');
  v_source_url text := nullif(btrim(new.cover_image_source_url), '');
begin
  if new.cover_image_url is not distinct from old.cover_image_url
     and new.cover_image_source is not distinct from old.cover_image_source
     and new.cover_image_attribution is not distinct from old.cover_image_attribution
     and new.cover_image_source_url is not distinct from old.cover_image_source_url
     and new.cover_image_updated_at is not distinct from old.cover_image_updated_at then
    return new;
  end if;

  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'subtenant' then
    return new;
  end if;

  if new.id is distinct from auth.uid() then
    raise exception 'SUBTENANT_COVER_NOT_OWNED' using errcode = '42501';
  end if;

  if v_url is null then
    new.cover_image_url := null;
    new.cover_image_source := null;
    new.cover_image_attribution := null;
    new.cover_image_source_url := null;
    new.cover_image_updated_at := now();
    return new;
  end if;

  if v_source not in ('uploaded', 'touristrike', 'pexels')
     or v_url !~ '^https://[^[:space:]]+$'
     or char_length(v_url) > 2048
     or char_length(coalesce(new.cover_image_attribution, '')) > 250
     or char_length(coalesce(new.cover_image_source_url, '')) > 2048 then
    raise exception 'INVALID_MUNICIPALITY_COVER' using errcode = '22023';
  end if;

  if v_source = 'uploaded' and v_url !~ (
    '^https://mvtqhsrdgtwdeootgjci\.supabase\.co/'
    || 'storage/v1/object/public/public-assets/'
    || 'municipality-covers/' || auth.uid()::text || '/'
  ) then
    raise exception 'INVALID_UPLOADED_COVER_PATH' using errcode = '22023';
  end if;

  if v_source = 'touristrike' and not exists (
    select 1
    from public.tourist_spots spot
    left join public.tourist_spot_images image on image.spot_id = spot.id
    where public.cities_match(
        coalesce(nullif(spot.municipality, ''), spot.city),
        new.city
      )
      and spot.status = 'active'
      and spot.verification_status in ('approved', 'verified')
      and (spot.image_url = v_url or image.image_url = v_url)
  ) then
    raise exception 'COVER_NOT_IN_MUNICIPALITY' using errcode = '42501';
  end if;

  if v_source = 'pexels' and (
    v_url !~ '^https://images\.pexels\.com/'
    or v_source_url is null
    or v_source_url !~ '^https://(www\.)?pexels\.com/'
    or nullif(btrim(new.cover_image_attribution), '') is null
  ) then
    raise exception 'INVALID_PEXELS_COVER_METADATA' using errcode = '22023';
  end if;

  if v_source in ('uploaded', 'touristrike') then
    new.cover_image_attribution := null;
    new.cover_image_source_url := null;
  end if;

  new.cover_image_url := v_url;
  new.cover_image_source := v_source;
  new.cover_image_attribution := nullif(btrim(new.cover_image_attribution), '');
  new.cover_image_source_url := v_source_url;
  new.cover_image_updated_at := now();
  return new;
end;
$$;

drop trigger if exists validate_subtenant_cover_change
  on public.subtenant_details;
create trigger validate_subtenant_cover_change
before update of
  cover_image_url,
  cover_image_source,
  cover_image_attribution,
  cover_image_source_url,
  cover_image_updated_at
on public.subtenant_details
for each row execute function public.validate_subtenant_cover_change();

create or replace function public.set_subtenant_municipality_cover(
  p_cover_image_url text,
  p_cover_image_source text,
  p_cover_image_attribution text default null,
  p_cover_image_source_url text default null
)
returns table (
  cover_image_url text,
  cover_image_source text,
  cover_image_attribution text,
  cover_image_source_url text,
  cover_image_updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;

  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'subtenant' then
    raise exception 'SUBTENANT_ROLE_REQUIRED' using errcode = '42501';
  end if;

  update public.subtenant_details office
  set
    cover_image_url = nullif(btrim(p_cover_image_url), ''),
    cover_image_source = nullif(btrim(p_cover_image_source), ''),
    cover_image_attribution = nullif(btrim(p_cover_image_attribution), ''),
    cover_image_source_url = nullif(btrim(p_cover_image_source_url), '')
  where office.id = auth.uid()
    and office.is_active = true
  returning
    office.cover_image_url,
    office.cover_image_source,
    office.cover_image_attribution,
    office.cover_image_source_url,
    office.cover_image_updated_at
  into
    cover_image_url,
    cover_image_source,
    cover_image_attribution,
    cover_image_source_url,
    cover_image_updated_at;

  if not found then
    raise exception 'ACTIVE_SUBTENANT_ASSIGNMENT_REQUIRED'
      using errcode = '42501';
  end if;

  insert into public.audit_logs (
    actor_id,
    action,
    table_name,
    record_id,
    description
  ) values (
    auth.uid(),
    case when cover_image_url is null
      then 'remove_municipality_cover'
      else 'select_municipality_cover'
    end,
    'subtenant_details',
    auth.uid()::text,
    case when cover_image_url is null
      then 'Removed the municipality cover.'
      else 'Selected a municipality cover from ' || cover_image_source || '.'
    end
  );

  return next;
end;
$$;

revoke all on function public.set_subtenant_municipality_cover(
  text, text, text, text
) from public, anon;
grant execute on function public.set_subtenant_municipality_cover(
  text, text, text, text
) to authenticated;

create or replace function public.get_municipality_cover(
  p_municipality text
)
returns table (
  municipality text,
  province text,
  cover_image_url text,
  cover_image_source text,
  cover_image_attribution text,
  cover_image_source_url text,
  cover_image_updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    office.city,
    office.province,
    office.cover_image_url,
    office.cover_image_source,
    office.cover_image_attribution,
    office.cover_image_source_url,
    office.cover_image_updated_at
  from public.subtenant_details office
  where auth.uid() is not null
    and office.is_active = true
    and public.cities_match(office.city, p_municipality)
  order by office.updated_at desc
  limit 1;
$$;

revoke all on function public.get_municipality_cover(text)
  from public, anon;
grant execute on function public.get_municipality_cover(text)
  to authenticated;

comment on function public.set_subtenant_municipality_cover(
  text, text, text, text
) is 'Sets only the authenticated active subtenant office cover after source-specific validation.';
comment on function public.get_municipality_cover(text)
  is 'Returns active public municipality cover branding for the selected tourist municipality.';

commit;
