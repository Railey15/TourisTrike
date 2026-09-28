-- Forward repair for confirmed historical authorization gaps only.
-- Do not apply old migrations again. Includes the dedicated profile privacy
-- correction; the tour waiting feature is outside this migration.
begin;

-- OTP provisioning sends only id/role; accreditation is staff-managed.
-- Preserve owner edits to onboarding data without permitting owner approval
-- through either profile caches or the actual acceptance predicates.
create or replace function public.guard_self_provisioning_state()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_new jsonb := to_jsonb(new);
  v_old jsonb;
  v_fields text[];
  v_field text;
  v_owner uuid;
begin
  if auth.uid() is null or coalesce(auth.role(), '') = 'service_role' then return new; end if;
  v_owner := coalesce(v_new->>'driver_id', v_new->>'id')::uuid;
  if v_owner is distinct from auth.uid() then return new; end if;
  if tg_table_name = 'profiles' then
    v_fields := array['is_approved','is_verified','verification_status','driver_status'];
  elsif tg_table_name = 'driver_details' then
    v_fields := array['status','approved_by','approved_at'];
  else
    v_fields := array['status','reviewed_by','reviewed_at'];
  end if;
  if tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    foreach v_field in array v_fields loop
      if v_new->v_field is distinct from v_old->v_field then
        raise exception 'APPROVAL_STATE_IS_STAFF_MANAGED' using errcode='42501';
      end if;
    end loop;
  else
    foreach v_field in array v_fields loop
      if (v_field in ('is_approved','is_verified') and coalesce(v_new->>v_field,'false') <> 'false')
        or (v_field in ('status','verification_status','driver_status')
          and coalesce(v_new->>v_field,'pending') <> 'pending')
        or (v_field in ('approved_by','approved_at','reviewed_by','reviewed_at')
          and v_new->>v_field is not null) then
        raise exception 'APPROVAL_STATE_IS_STAFF_MANAGED' using errcode='42501';
      end if;
    end loop;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_self_provisioning_state() from public, anon, authenticated;
drop trigger if exists guard_self_provisioning_state on public.profiles;
create trigger guard_self_provisioning_state before insert or update on public.profiles
for each row execute function public.guard_self_provisioning_state();
drop trigger if exists guard_self_provisioning_state on public.driver_details;
create trigger guard_self_provisioning_state before insert or update on public.driver_details
for each row execute function public.guard_self_provisioning_state();
drop trigger if exists guard_self_provisioning_state on public.driver_applications;
create trigger guard_self_provisioning_state before insert or update on public.driver_applications
for each row execute function public.guard_self_provisioning_state();

-- 20260511000000 restricted self-created profiles to Tourist/Driver. The
-- surviving profiles_insert_own policy only checked id = auth.uid(), so an
-- authenticated account without a profile could choose a privileged role.
drop policy if exists profiles_insert_own on public.profiles;
drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
for insert to authenticated
with check (
  id = auth.uid()
  and role in ('tourist', 'driver')
);

-- Historical itinerary policies wrote bd.booking_id = booking_id (and the
-- same expression for package_activities). PostgreSQL resolved both sides
-- inside the subquery, yielding bd.booking_id = bd.booking_id. Bind every
-- participant test explicitly to the outer itinerary row.
create or replace function public.itinerary_staff_access(p_booking_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1 from public.profiles actor
    join public.package_bookings b on b.id = p_booking_id
    left join public.subtenant_details office on office.id = actor.id
    left join public.tour_packages package on package.id = b.package_id
    where actor.id = auth.uid() and (
      (actor.role = 'main_tenant'
        and nullif(trim(actor.province), '') is not null
        and trim(actor.province) ~ '^[[:alpha:]][[:alpha:] .''-]*$'
        and public.cities_match(b.province, actor.province))
      or (actor.role = 'subtenant' and office.is_active = true
        and nullif(trim(office.city), '') is not null
        and nullif(trim(office.province), '') is not null
        and public.cities_match(package.city, office.city)
        and public.cities_match(b.province, office.province))
    )
  );
$$;
revoke all on function public.itinerary_staff_access(uuid) from public, anon;
grant execute on function public.itinerary_staff_access(uuid) to authenticated;
-- Pending-job preview previously authorized every Driver to read itineraries.
-- Assigned/accepted Drivers are covered by the participant policy below.
drop policy if exists driver_read_pending_itinerary_items on public.booking_itinerary_items;
drop policy if exists booking_itinerary_items_select
  on public.booking_itinerary_items;
create policy booking_itinerary_items_select
on public.booking_itinerary_items for select to authenticated
using (
  (tourist_id = auth.uid() and exists (
    select 1 from public.package_bookings b
    where b.id = booking_itinerary_items.booking_id and b.tourist_id = auth.uid()
  ))
  or exists (
    select 1 from public.package_bookings b
    where b.id = booking_itinerary_items.booking_id
      and b.assigned_driver_id = auth.uid()
  )
  or exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = booking_itinerary_items.booking_id
      and bd.driver_id = auth.uid()
      and bd.status in ('accepted', 'completed')
  )
  or public.itinerary_staff_access(booking_itinerary_items.booking_id)
);

drop policy if exists booking_itinerary_items_update
  on public.booking_itinerary_items;
create policy booking_itinerary_items_update
on public.booking_itinerary_items for update to authenticated
using (
  exists (
    select 1 from public.package_bookings b
    where b.id = booking_itinerary_items.booking_id
      and b.tourist_id = auth.uid()
      and booking_itinerary_items.tourist_id = auth.uid()
  )
  or exists (
    select 1 from public.package_bookings b
    where b.id = booking_itinerary_items.booking_id
      and b.assigned_driver_id = auth.uid()
  )
  or exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = booking_itinerary_items.booking_id
      and bd.driver_id = auth.uid()
      and bd.status = 'accepted'
  )
  or exists (
    select 1 from public.package_activities pa
    where pa.booking_id = booking_itinerary_items.booking_id
      and pa.driver_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.package_bookings b
    where b.id = booking_itinerary_items.booking_id
      and b.tourist_id = auth.uid()
      and booking_itinerary_items.tourist_id = auth.uid()
  )
  or exists (
    select 1 from public.package_bookings b
    where b.id = booking_itinerary_items.booking_id
      and b.assigned_driver_id = auth.uid()
  )
  or exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = booking_itinerary_items.booking_id
      and bd.driver_id = auth.uid()
      and bd.status = 'accepted'
  )
  or exists (
    select 1 from public.package_activities pa
    where pa.booking_id = booking_itinerary_items.booking_id
      and pa.driver_id = auth.uid()
  )
);

-- The original INSERT and DELETE owner checks trusted an independently
-- writable tourist_id on the itinerary row. Require the linked booking to
-- belong to that same Tourist; trusted creation RPCs retain their access.
drop policy if exists booking_itinerary_items_insert
  on public.booking_itinerary_items;
create policy booking_itinerary_items_insert
on public.booking_itinerary_items for insert to authenticated
with check (
  tourist_id = auth.uid()
  and exists (
    select 1 from public.package_bookings b
    where b.id = booking_itinerary_items.booking_id
      and b.tourist_id = auth.uid()
  )
);

drop policy if exists booking_itinerary_items_delete
  on public.booking_itinerary_items;
create policy booking_itinerary_items_delete
on public.booking_itinerary_items for delete to authenticated
using (
  tourist_id = auth.uid()
  and exists (
    select 1 from public.package_bookings b
    where b.id = booking_itinerary_items.booking_id
      and b.tourist_id = auth.uid()
  )
);

-- Full profile rows are for self and geographically scoped operational staff.
-- Ordinary participant identity comes from the explicit column RPC below.
create or replace function public.profile_operational_access(p_profile_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1 from public.profiles actor cross join public.profiles target
    left join public.subtenant_details office on office.id = actor.id
    where actor.id = auth.uid() and target.id = p_profile_id
      and (
        (actor.role = 'main_tenant' and target.role <> 'administrator'
          and nullif(trim(actor.province), '') is not null
          and public.cities_match(target.province, actor.province))
        or (actor.role = 'subtenant' and office.is_active = true
          and target.role = 'driver'
          and nullif(trim(office.city), '') is not null
          and nullif(trim(office.province), '') is not null
          and public.cities_match(target.city, office.city)
          and public.cities_match(target.province, office.province))
      )
  );
$$;
revoke all on function public.profile_operational_access(uuid) from public, anon;
grant execute on function public.profile_operational_access(uuid) to authenticated;

drop policy if exists profiles_select_authenticated on public.profiles;
drop policy if exists profiles_select_driver_review_tourists on public.profiles;
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
using (id = auth.uid() or public.profile_operational_access(id));
-- Also cap any other permissive SELECT/ALL policy at the same boundary.
drop policy if exists profiles_select_scope_guard on public.profiles;
create policy profiles_select_scope_guard on public.profiles
as restrictive for select to authenticated
using (id = auth.uid() or public.profile_operational_access(id));
revoke all on public.profiles from public, anon;
revoke truncate, references, trigger, delete on public.profiles from authenticated;
-- Table revokes do not revoke an independently granted column privilege.
do $$
declare v_columns text;
begin
  select string_agg(quote_ident(attname), ',') into v_columns
  from pg_attribute where attrelid='public.profiles'::regclass
    and attnum > 0 and not attisdropped;
  execute format('revoke select (%s) on public.profiles from public, anon', v_columns);
end;
$$;

-- 0 = no identity, 1 = basic identity, 2 = operational contact. This helper is
-- private: callers cannot supply/impersonate an actor or execute it directly.
do $$
begin
  if not (select relrowsecurity from pg_class where oid='public.conversation_members'::regclass)
    or exists(select 1 from pg_policies where schemaname='public'
      and tablename='conversation_members' and cmd in ('INSERT','UPDATE','ALL')
      and roles && array['authenticated'::name,'public'::name]) then
    raise exception 'CONVERSATION_MEMBERSHIP_MUST_BE_TRUSTED';
  end if;
end;
$$;
create or replace function public.profile_identity_access_level(p_profile_id uuid)
returns integer language plpgsql stable security definer set search_path = ''
as $$
declare
  v_actor public.profiles;
  v_target public.profiles;
  v_level integer := 0;
begin
  if auth.uid() is null then return 0; end if;
  select * into v_actor from public.profiles where id = auth.uid();
  select * into v_target from public.profiles where id = p_profile_id;
  if v_actor.id is null or v_target.id is null then return 0; end if;
  if v_actor.id = v_target.id or public.profile_operational_access(v_target.id)
    then return 2; end if;
  if v_actor.role = 'administrator' then return 1; end if;

  select coalesce(max(case
    when lower(coalesce(b.booking_status, b.status, ''))
      in ('accepted','confirmed','driver_on_the_way','arrived','picked_up',
          'tour_started','on_tour','ongoing','in_progress','waiting_for_drivers')
      then 2 else 1 end), 0) into v_level
  from public.package_bookings b
  where (
    b.tourist_id = v_target.id or b.assigned_driver_id = v_target.id
    or exists (select 1 from public.booking_drivers target_driver
      where target_driver.booking_id = b.id and target_driver.driver_id = v_target.id
        and target_driver.status in ('accepted','completed'))
  ) and (
    (v_actor.role in ('tourist','driver') and (
      b.tourist_id = v_actor.id or b.assigned_driver_id = v_actor.id
      or exists (select 1 from public.booking_drivers own_driver
      where own_driver.booking_id = b.id and own_driver.driver_id = v_actor.id
        and own_driver.status in ('accepted','completed'))))
    or (v_actor.role = 'subtenant' and public.subtenant_can_access_booking(b.id)
      and exists (select 1 from public.subtenant_details office
        where office.id = v_actor.id and office.is_active = true
          and nullif(trim(office.province), '') is not null
          and public.cities_match(b.province, office.province)))
    or (v_actor.role = 'main_tenant'
      and nullif(trim(v_actor.province), '') is not null
      and public.cities_match(b.province, v_actor.province))
  );
  if v_level = 2 then return 2; end if;

  if exists (
    select 1 from public.rides r
    where r.driver_id is not null
      and ((v_actor.role in ('tourist','driver') and (
          (r.tourist_id = v_actor.id and r.driver_id = v_target.id)
          or (r.driver_id = v_actor.id and r.tourist_id = v_target.id)))
        or (v_actor.role in ('subtenant','main_tenant') and r.tourist_id = v_target.id
          and public.profile_operational_access(r.driver_id)))
      and lower(coalesce(r.status, '')) in ('accepted','arrived','ongoing','in_progress')
  ) then return 2; end if;
  if exists (select 1 from public.rides r
    where r.driver_id is not null
      and ((v_actor.role in ('tourist','driver') and (
          (r.tourist_id = v_actor.id and r.driver_id = v_target.id)
          or (r.driver_id = v_actor.id and r.tourist_id = v_target.id)))
        or (v_actor.role in ('subtenant','main_tenant') and r.tourist_id = v_target.id
          and public.profile_operational_access(r.driver_id))))
    then v_level := greatest(v_level, 1); end if;

  if v_actor.role in ('tourist','driver') and (exists (
    select 1 from public.conversation_members own_member
    join public.conversation_members other_member
      on other_member.conversation_id = own_member.conversation_id
    where own_member.user_id = v_actor.id and other_member.user_id = v_target.id
  ) or exists (
    select 1 from public.conversations c
    where (c.tourist_id = v_actor.id and c.driver_id = v_target.id)
       or (c.driver_id = v_actor.id and c.tourist_id = v_target.id)
  )) then v_level := greatest(v_level, 1); end if;

  if exists (
    select 1 from public.driver_reviews review
    where (v_actor.role in ('tourist','driver') and (
      (review.driver_id = v_actor.id and review.tourist_id = v_target.id)
       or (review.tourist_id = v_actor.id and review.driver_id = v_target.id)))
       or (review.tourist_id = v_target.id and v_actor.role = 'subtenant'
         and public.profile_operational_access(review.driver_id))
  ) then v_level := greatest(v_level, 1); end if;
  if exists (
    select 1 from public.ride_reviews review
    join public.rides r on r.id = review.ride_id
      and r.tourist_id = review.tourist_id and r.driver_id = review.driver_id
    where (v_actor.role in ('tourist','driver') and (
      (review.driver_id = v_actor.id and review.tourist_id = v_target.id)
       or (review.tourist_id = v_actor.id and review.driver_id = v_target.id)))
       or (review.tourist_id = v_target.id and v_actor.role in ('subtenant','main_tenant')
         and public.profile_operational_access(review.driver_id))
  ) then v_level := greatest(v_level, 1); end if;
  return v_level;
end;
$$;
revoke all on function public.profile_identity_access_level(uuid)
  from public, anon, authenticated;

create or replace function public.get_participant_profiles(p_profile_ids uuid[])
returns table (
  id uuid, role text, full_name text, first_name text, last_name text,
  avatar_url text, profile_image_url text, average_rating numeric,
  total_reviews integer, mobile text
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED' using errcode='42501'; end if;
  if coalesce(cardinality(p_profile_ids), 0) > 200
    then raise exception 'PROFILE_LOOKUP_LIMIT' using errcode='22023'; end if;
  return query
  select p.id, p.role, p.full_name, p.first_name, p.last_name,
    p.avatar_url, p.profile_image_url, p.average_rating, p.total_reviews,
    case when access.level = 2 then p.mobile else null::text end
  from public.profiles p
  cross join lateral (select public.profile_identity_access_level(p.id) as level) access
  where p.id = any(p_profile_ids) and access.level > 0;
end;
$$;
revoke all on function public.get_participant_profiles(uuid[]) from public, anon;
grant execute on function public.get_participant_profiles(uuid[]) to authenticated;

-- Direct conversations are identity links, so clients must not forge/repoint
-- those links. Existing historical pairs keep basic identity, never contact.
create or replace function public.guard_conversation_profile_identity()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or coalesce(auth.role(), '') = 'service_role' then return new; end if;
  if tg_op = 'UPDATE' then
    if new.tourist_id is distinct from old.tourist_id
      or new.driver_id is distinct from old.driver_id
      or new.booking_id is distinct from old.booking_id
      or new.conversation_type is distinct from old.conversation_type then
      raise exception 'CONVERSATION_PARTICIPANTS_ARE_READ_ONLY' using errcode='42501';
    end if;
    return new;
  end if;
  if exists (
    select 1 from public.package_bookings b
    where b.id = new.booking_id and b.tourist_id = new.tourist_id
      and (
        (new.conversation_type = 'booking_group' and new.driver_id is null
          and (b.tourist_id = auth.uid() or b.assigned_driver_id = auth.uid()
            or exists (select 1 from public.booking_drivers bd
              where bd.booking_id=b.id and bd.driver_id=auth.uid()
                and bd.status in ('accepted','completed'))
            or (public.current_app_role()='subtenant'
              and public.subtenant_can_access_booking(b.id)
              and exists(select 1 from public.subtenant_details office
                where office.id=auth.uid() and office.is_active
                  and nullif(trim(office.province),'') is not null
                  and public.cities_match(b.province,office.province)))
            or (public.is_main_tenant() and exists (
              select 1 from public.profiles actor where actor.id=auth.uid()
                and nullif(trim(actor.province),'') is not null
                and public.cities_match(b.province,actor.province)))))
        or (new.conversation_type = 'direct'
          and auth.uid() in (new.tourist_id, new.driver_id)
          and (b.assigned_driver_id = new.driver_id
            or exists (select 1 from public.booking_drivers bd
              where bd.booking_id=b.id and bd.driver_id=new.driver_id
                and bd.status in ('accepted','completed'))))
      )
  ) or (new.conversation_type = 'direct' and new.booking_id is null
    and auth.uid() in (new.tourist_id,new.driver_id)
    and exists (select 1 from public.rides r
      where r.tourist_id=new.tourist_id and r.driver_id=new.driver_id))
    then return new; end if;
  raise exception 'CONVERSATION_ASSIGNMENT_REQUIRED' using errcode='42501';
end;
$$;
revoke all on function public.guard_conversation_profile_identity()
  from public, anon, authenticated;
drop trigger if exists guard_conversation_profile_identity on public.conversations;
create trigger guard_conversation_profile_identity
before insert or update on public.conversations
for each row execute function public.guard_conversation_profile_identity();

-- Secure the existing lazy itinerary initialization RPC; keep its generation body.
CREATE OR REPLACE FUNCTION public.ensure_booking_itinerary(p_booking_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_count   integer;
  v_booking public.package_bookings;
BEGIN
  if auth.uid() is null and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'UNAUTHENTICATED' using errcode='42501';
  end if;
  if coalesce(auth.role(), '') <> 'service_role' and not exists (
    select 1 from public.package_bookings b where b.id=p_booking_id and (
      b.tourist_id=auth.uid() or b.assigned_driver_id=auth.uid()
      or exists(select 1 from public.booking_drivers d where d.booking_id=b.id
        and d.driver_id=auth.uid() and d.status in ('accepted','completed'))
    )
  ) then raise exception 'ITINERARY_PARTICIPATION_REQUIRED' using errcode='42501'; end if;
  SELECT COUNT(*) INTO v_count
  FROM public.booking_itinerary_items
  WHERE booking_id = p_booking_id;

  IF v_count > 0 THEN
    RETURN v_count;
  END IF;

  SELECT * INTO v_booking
  FROM public.package_bookings
  WHERE id = p_booking_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  -- Try customized_package_spots first
  INSERT INTO public.booking_itinerary_items (
    booking_id, tourist_id, spot_id, destination_name, destination_address,
    order_number, destination_order,
    latitude, longitude, google_place_id,
    source_type, itinerary_source, municipality, barangay, image_url
  )
  SELECT
    p_booking_id,
    v_booking.tourist_id,
    cps.spot_id,
    COALESCE(NULLIF(TRIM(cps.spot_title), ''), 'Unnamed Spot'),
    COALESCE(NULLIF(TRIM(cps.spot_address), ''), ''),
    (cps.sort_order + 1),
    (cps.sort_order + 1),
    cps.latitude,
    cps.longitude,
    cps.google_place_id,
    COALESCE(cps.source_type, 'manual'),
    COALESCE(cps.source_type, 'manual'),
    cps.municipality,
    cps.barangay,
    cps.image_url
  FROM public.customized_package_spots cps
  WHERE cps.booking_id = p_booking_id
    AND cps.action_type IN ('kept', 'added')
  ORDER BY cps.sort_order
  ON CONFLICT (booking_id, destination_order) DO NOTHING;

  SELECT COUNT(*) INTO v_count
  FROM public.booking_itinerary_items
  WHERE booking_id = p_booking_id;

  IF v_count > 0 THEN
    RETURN v_count;
  END IF;

  -- Fall back to tour_package_spots
  INSERT INTO public.booking_itinerary_items (
    booking_id, tourist_id, spot_id, destination_name, destination_address,
    order_number, destination_order,
    latitude, longitude, source_type, itinerary_source, municipality, barangay
  )
  SELECT
    p_booking_id,
    v_booking.tourist_id,
    tps.spot_id,
    COALESCE(NULLIF(TRIM(ts.title), ''), 'Unnamed Spot'),
    COALESCE(NULLIF(TRIM(ts.address), ''), ''),
    ROW_NUMBER() OVER (ORDER BY tps.sort_order, tps.spot_id),
    ROW_NUMBER() OVER (ORDER BY tps.sort_order, tps.spot_id),
    ts.latitude,
    ts.longitude,
    'package',
    'package',
    ts.municipality,
    ts.barangay
  FROM public.tour_package_spots tps
  LEFT JOIN public.tourist_spots ts ON ts.id = tps.spot_id
  WHERE tps.package_id = v_booking.package_id
  ORDER BY tps.sort_order
  ON CONFLICT (booking_id, destination_order) DO NOTHING;

  SELECT COUNT(*) INTO v_count
  FROM public.booking_itinerary_items
  WHERE booking_id = p_booking_id;

  RETURN v_count;
END;
$function$;

revoke all on function public.ensure_booking_itinerary(uuid) from public, anon;
grant execute on function public.ensure_booking_itinerary(uuid) to authenticated, service_role;

commit;
