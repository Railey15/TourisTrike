-- Run only inside the explicit rollback preflight after the forward migration.
-- Real accounts are impersonated for read-only checks; fixture expectations are
-- temporary. No account, booking, application, message or payment is changed.
do $$
begin
  if exists(select 1 from pg_policies where schemaname='public' and tablename='profiles'
    and policyname in ('profiles_select_authenticated','profiles_select_driver_review_tourists'))
    then raise exception 'BROAD_PROFILE_POLICY_REMAINS'; end if;
  if has_table_privilege('anon','public.profiles','SELECT')
    or has_function_privilege('anon','public.get_participant_profiles(uuid[])','EXECUTE')
    or has_function_privilege('authenticated','public.profile_identity_access_level(uuid)','EXECUTE')
    or has_table_privilege('authenticated','public.profiles','TRUNCATE')
    then raise exception 'EXCESS_PROFILE_PRIVILEGE'; end if;
  if exists(select 1 from pg_proc where oid in (
      'public.profile_operational_access(uuid)'::regprocedure,
      'public.profile_identity_access_level(uuid)'::regprocedure,
      'public.get_participant_profiles(uuid[])'::regprocedure,
      'public.guard_conversation_profile_identity()'::regprocedure)
    and not (prosecdef and proconfig @> array['search_path=""']))
    then raise exception 'UNSAFE_PROFILE_FUNCTION'; end if;
end;
$$;

create temporary table profile_expected_full on commit drop as
select actor.id as actor_id,target.id as target_id
from public.profiles actor cross join public.profiles target
left join public.subtenant_details office on office.id=actor.id
where actor.id=target.id
  or (actor.role='main_tenant' and target.role<>'administrator'
    and nullif(trim(actor.province),'') is not null
    and public.cities_match(target.province,actor.province))
  or (actor.role='subtenant' and office.is_active and target.role='driver'
    and nullif(trim(office.city),'') is not null
    and nullif(trim(office.province),'') is not null
    and public.cities_match(target.city,office.city)
    and public.cities_match(target.province,office.province));
create temporary table profile_actors on commit drop as select id,role from public.profiles;
create temporary table profile_expected_participants on commit drop as
select distinct actor.id as actor_id,target.id as target_id
from public.profiles actor cross join public.profiles target
where actor.id<>target.id and actor.role in ('tourist','driver') and exists(
  select 1 from public.package_bookings b
  where (b.tourist_id=actor.id or b.assigned_driver_id=actor.id
    or exists(select 1 from public.booking_drivers bd where bd.booking_id=b.id
      and bd.driver_id=actor.id and bd.status in ('accepted','completed')))
  and (b.tourist_id=target.id or b.assigned_driver_id=target.id
    or exists(select 1 from public.booking_drivers bd where bd.booking_id=b.id
      and bd.driver_id=target.id and bd.status in ('accepted','completed')))
);
create temporary table profile_expected_messaging on commit drop as
select distinct own_member.user_id as actor_id,other_member.user_id as target_id
from public.conversation_members own_member join public.conversation_members other_member
  on other_member.conversation_id=own_member.conversation_id
join public.profiles actor on actor.id=own_member.user_id
join public.profiles target on target.id=other_member.user_id
where actor.id<>target.id and actor.role in ('tourist','driver')
union
select c.tourist_id,c.driver_id from public.conversations c
join public.profiles a on a.id=c.tourist_id join public.profiles t on t.id=c.driver_id
where a.role in ('tourist','driver')
union
select c.driver_id,c.tourist_id from public.conversations c
join public.profiles a on a.id=c.tourist_id join public.profiles t on t.id=c.driver_id
where t.role in ('tourist','driver');
create temporary table profile_unrelated on commit drop as
select actor.id as actor_id,target.id as target_id
from public.profiles actor cross join public.profiles target
where actor.id<>target.id and actor.role in ('tourist','driver')
  and not exists(select 1 from profile_expected_participants p where p.actor_id=actor.id and p.target_id=target.id)
  and not exists(select 1 from profile_expected_messaging m where m.actor_id=actor.id and m.target_id=target.id)
  and not exists(select 1 from public.rides r where (r.tourist_id=actor.id and r.driver_id=target.id)
    or (r.driver_id=actor.id and r.tourist_id=target.id))
  and not exists(select 1 from public.driver_reviews r where (r.tourist_id=actor.id and r.driver_id=target.id)
    or (r.driver_id=actor.id and r.tourist_id=target.id))
  and not exists(select 1 from public.ride_reviews r where (r.tourist_id=actor.id and r.driver_id=target.id)
    or (r.driver_id=actor.id and r.tourist_id=target.id));
grant select on profile_expected_full,profile_actors,profile_expected_participants,
  profile_expected_messaging,profile_unrelated to authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
set local role authenticated;
do $$
declare actor record; pair record; actual_ids uuid[]; expected_ids uuid[]; identity jsonb;
begin
  for actor in select * from profile_actors loop
    perform set_config('request.jwt.claim.sub',actor.id::text,true);
    select array_agg(id order by id) into actual_ids from public.profiles;
    select array_agg(target_id order by target_id) into expected_ids from profile_expected_full where actor_id=actor.id;
    if actual_ids is distinct from expected_ids then raise exception 'PROFILE_SCOPE_MISMATCH: %',actor.role; end if;
    if not exists(select 1 from public.profiles where id=actor.id) then raise exception 'OWN_PROFILE_MISSING'; end if;
    if actor.role='administrator' and (select count(*) from public.administrator_list_accounts())
      <> (select count(*) from profile_actors) then raise exception 'ADMINISTRATOR_OVERSIGHT_CHANGED'; end if;
  end loop;
  for pair in select * from profile_expected_participants union select * from profile_expected_messaging loop
    perform set_config('request.jwt.claim.sub',pair.actor_id::text,true);
    select to_jsonb(p) into identity from public.get_participant_profiles(array[pair.target_id]) p;
    if identity is null then raise exception 'REQUIRED_PARTICIPANT_IDENTITY_MISSING'; end if;
    if identity ?| array['birthdate','address','barangay','middle_name','postal_code','driver_status',
      'is_approved','is_verified','verification_status','province','city']
      then raise exception 'PRIVATE_PROFILE_COLUMN_EXPOSED'; end if;
  end loop;
  for pair in select * from profile_unrelated loop
    perform set_config('request.jwt.claim.sub',pair.actor_id::text,true);
    if exists(select 1 from public.get_participant_profiles(array[pair.target_id]))
      or exists(select 1 from public.profiles where id=pair.target_id)
      then raise exception 'UNRELATED_PROFILE_VISIBLE'; end if;
  end loop;
end;
$$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$
begin
  begin
    perform id from public.profiles limit 1;
    raise exception 'ANONYMOUS_PROFILE_READ_ALLOWED';
  exception when insufficient_privilege then null; end;
  begin
    perform * from public.get_participant_profiles(null);
    raise exception 'ANONYMOUS_IDENTITY_LOOKUP_ALLOWED';
  exception when insufficient_privilege then null; end;
end;
$$;
reset role;
select (select count(*) from profile_actors) as profile_actors_checked,
       (select count(*) from profile_unrelated) as unrelated_pairs_checked,
       (select count(*) from profile_expected_participants) as booking_identity_pairs_checked,
       (select count(*) from profile_expected_messaging) as messaging_identity_pairs_checked;
