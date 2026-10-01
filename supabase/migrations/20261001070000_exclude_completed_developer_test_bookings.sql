-- Completed bookings are not reusable Developer Testing candidates. Exclude
-- them in the base dataset so search, filters, total_count, and pagination all
-- operate on the same non-completed population.
begin;

create or replace function public.administrator_list_testable_bookings(
  p_search text default null,
  p_booking_filter text default 'all',
  p_test_filter text default 'all',
  p_limit integer default 25,
  p_offset integer default 0
)
returns table (
  booking_id uuid,
  booking_reference text,
  tourist_id uuid,
  tourist_name text,
  package_id bigint,
  package_name text,
  municipality text,
  scheduled_start_at timestamptz,
  estimated_end_at timestamptz,
  booking_status text,
  tour_status text,
  drivers jsonb,
  required_drivers integer,
  assigned_driver_count integer,
  downpayment_ready boolean,
  remaining_payment_ready boolean,
  valid_tourist boolean,
  drivers_ready boolean,
  booking_state_valid boolean,
  eligible boolean,
  eligibility_reason text,
  test_session_id uuid,
  test_session_active boolean,
  activated_by uuid,
  activated_by_name text,
  activated_at timestamptz,
  expires_at timestamptz,
  reason text,
  bypass_scheduled_start boolean,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_system_administrator() then
    raise exception 'SYSTEM_ADMINISTRATOR_REQUIRED' using errcode = '42501';
  end if;
  if p_booking_filter not in ('all', 'upcoming', 'active', 'completed', 'cancelled')
     or p_test_filter not in ('all', 'active', 'inactive')
     or p_limit not between 1 and 100
     or p_offset < 0 then
    raise exception 'INVALID_DEVELOPER_BOOKING_FILTERS' using errcode = '22023';
  end if;

  return query
  with booking_rows as (
    select
      b.id as row_booking_id,
      '#' || upper(substr(b.id::text, 1, 8)) as row_booking_reference,
      b.tourist_id as row_tourist_id,
      coalesce(nullif(btrim(t.full_name), ''),
        nullif(btrim(concat_ws(' ', t.first_name, t.last_name)), ''),
        'Unnamed tourist') as row_tourist_name,
      b.package_id as row_package_id,
      coalesce(nullif(btrim(tp.title), ''), 'Untitled package') as row_package_name,
      coalesce(nullif(btrim(b.municipality), ''), nullif(btrim(tp.city), ''), '') as row_municipality,
      b.scheduled_start_at,
      b.estimated_end_at,
      lower(coalesce(b.booking_status, b.status, 'unknown')) as row_booking_status,
      coalesce(activity.tour_status, activity.status, 'pending') as row_tour_status,
      coalesce(driver_info.drivers, '[]'::jsonb) as row_drivers,
      greatest(coalesce(b.required_drivers, 1), 1) as row_required_drivers,
      coalesce(driver_info.driver_count, 0)::integer as row_driver_count,
      public.is_booking_downpayment_confirmed(b.id) as row_downpayment_ready,
      public.is_booking_remaining_payment_satisfied(b.id) as row_remaining_payment_ready,
      t.id is not null and t.role = 'tourist' as row_valid_tourist,
      coalesce(driver_info.driver_count, 0) >= greatest(coalesce(b.required_drivers, 1), 1)
        as row_drivers_ready,
      lower(coalesce(b.booking_status, b.status, ''))
        not in ('cancelled', 'rejected', 'completed', 'expired')
        as row_booking_state_valid,
      t.id is not null
        and t.role = 'tourist'
        and lower(coalesce(b.booking_status, b.status, ''))
          not in ('cancelled', 'rejected', 'completed', 'expired')
        and coalesce(driver_info.driver_count, 0) >= greatest(coalesce(b.required_drivers, 1), 1)
        as row_eligible,
      case
        when t.id is null or t.role is distinct from 'tourist' then 'A valid Tourist is required.'
        when lower(coalesce(b.booking_status, b.status, ''))
          in ('cancelled', 'rejected', 'completed', 'expired') then 'The booking is in a terminal state.'
        when coalesce(driver_info.driver_count, 0) < greatest(coalesce(b.required_drivers, 1), 1)
          then 'All required Driver slots must be accepted.'
        else ''
      end as row_eligibility_reason,
      session_info.id as row_session_id,
      session_info.id is not null as row_session_active,
      session_info.activated_by as row_activated_by,
      coalesce(nullif(btrim(admin_profile.full_name), ''),
        nullif(btrim(concat_ws(' ', admin_profile.first_name, admin_profile.last_name)), ''),
        '') as row_activated_by_name,
      session_info.activated_at as row_activated_at,
      session_info.expires_at as row_expires_at,
      session_info.reason as row_reason,
      coalesce(session_info.bypass_scheduled_start, false) as row_bypass_scheduled_start,
      concat_ws(' ', b.id::text, t.full_name, t.first_name, t.last_name,
        tp.title, b.municipality, tp.city, driver_info.search_names) as search_text
    from public.package_bookings b
    left join public.profiles t on t.id = b.tourist_id
    left join public.tour_packages tp on tp.id = b.package_id
    left join lateral (
      select pa.status, pa.tour_status
      from public.package_activities pa
      where pa.booking_id = b.id
      order by pa.updated_at desc nulls last, pa.created_at desc nulls last
      limit 1
    ) activity on true
    left join lateral (
      select
        count(*)::integer as driver_count,
        jsonb_agg(jsonb_build_object(
          'id', driver.id,
          'name', coalesce(nullif(btrim(driver.full_name), ''),
            nullif(btrim(concat_ws(' ', driver.first_name, driver.last_name)), ''),
            'Unnamed driver')
        ) order by coalesce(driver.full_name, driver.first_name, driver.id::text)) as drivers,
        string_agg(concat_ws(' ', driver.full_name, driver.first_name, driver.last_name), ' ') as search_names
      from public.booking_drivers bd
      join public.profiles driver on driver.id = bd.driver_id
      where bd.booking_id = b.id and bd.status in ('accepted', 'completed')
    ) driver_info on true
    left join lateral (
      select dts.*
      from public.developer_test_sessions dts
      where dts.booking_id = b.id
        and dts.status = 'active'
        and dts.expires_at > now()
      order by dts.activated_at desc
      limit 1
    ) session_info on true
    left join public.profiles admin_profile on admin_profile.id = session_info.activated_by
    where lower(coalesce(b.booking_status, b.status, '')) <> 'completed'
  ), filtered as (
    select * from booking_rows br
    where (nullif(btrim(coalesce(p_search, '')), '') is null
      or br.search_text ilike '%' || btrim(p_search) || '%')
      and case p_booking_filter
        when 'upcoming' then br.scheduled_start_at > now()
          and br.row_booking_status not in ('cancelled', 'rejected', 'completed', 'expired')
        when 'active' then br.row_booking_status in (
          'confirmed', 'driver_accepted', 'driver_on_the_way', 'ongoing', 'on_tour'
        )
        when 'completed' then br.row_booking_status = 'completed'
        when 'cancelled' then br.row_booking_status in ('cancelled', 'rejected', 'expired')
        else true
      end
      and case p_test_filter
        when 'active' then br.row_session_active
        when 'inactive' then not br.row_session_active
        else true
      end
  )
  select
    f.row_booking_id, f.row_booking_reference, f.row_tourist_id,
    f.row_tourist_name, f.row_package_id, f.row_package_name,
    f.row_municipality, f.scheduled_start_at, f.estimated_end_at,
    f.row_booking_status, f.row_tour_status, f.row_drivers,
    f.row_required_drivers, f.row_driver_count, f.row_downpayment_ready,
    f.row_remaining_payment_ready, f.row_valid_tourist, f.row_drivers_ready,
    f.row_booking_state_valid, f.row_eligible, f.row_eligibility_reason,
    f.row_session_id, f.row_session_active, f.row_activated_by,
    f.row_activated_by_name, f.row_activated_at, f.row_expires_at,
    f.row_reason, f.row_bypass_scheduled_start,
    count(*) over ()
  from filtered f
  order by f.row_session_active desc,
    (f.scheduled_start_at >= now()) desc,
    f.scheduled_start_at asc nulls last,
    f.row_booking_id
  limit p_limit offset p_offset;
end;
$$;

revoke all on function public.administrator_list_testable_bookings(
  text, text, text, integer, integer
) from public, anon;
grant execute on function public.administrator_list_testable_bookings(
  text, text, text, integer, integer
) to authenticated;

commit;
