-- Finalize driver earnings independently from the provider payout transport,
-- and let an authorized developer TEST MODE session bypass only the schedule
-- boundary used by live tracking.
begin;

alter table public.payment_allocations
  add column if not exists earning_status text not null default 'pending',
  add column if not exists earning_completed_at timestamptz;

alter table public.payment_allocations
  drop constraint if exists payment_allocations_earning_status_check;
alter table public.payment_allocations
  add constraint payment_allocations_earning_status_check check (
    earning_status in (
      'pending', 'completed', 'refund_pending', 'refunded', 'disputed',
      'failed', 'cancelled', 'manual_review'
    )
  );

comment on column public.payment_allocations.earning_status is
  'Authoritative earned-income lifecycle. This is separate from payment_allocations.status, which tracks provider payout transport.';
comment on column public.payment_allocations.earning_completed_at is
  'Set only after the tour and every required tourist payment are successfully completed.';

create or replace function public.recompute_booking_driver_earnings(
  p_booking_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
begin
  update public.payment_allocations pa
  set earning_status = case
        when pr.status = 'disputed' or exists (
          select 1 from public.payment_disputes pd
          where pd.payment_record_id = pr.id
            and pd.status <> 'rejected'
        ) then 'disputed'
        when exists (
          select 1 from public.refund_requests rr
          where rr.payment_record_id = pr.id and rr.status = 'completed'
        ) then 'refunded'
        when exists (
          select 1 from public.refund_requests rr
          where rr.payment_record_id = pr.id
            and rr.status in ('pending', 'approved')
        ) then 'refund_pending'
        when pr.status = 'failed' then 'failed'
        when pr.status = 'cancelled' then 'cancelled'
        when pa.status = 'manual_review' then 'manual_review'
        when lower(coalesce(pb.booking_status, pb.status, '')) in (
               'completed', 'done'
             )
         and pr.status = 'confirmed'
         and bd.status = 'completed'
         and not exists (
           select 1 from public.booking_payment_requirements bpr
           where bpr.booking_id = pb.id and bpr.status = 'required'
         )
         and not exists (
           select 1
           from public.booking_payment_requirements bpr
           left join public.payment_records satisfied
             on satisfied.id = bpr.satisfied_by_payment_record_id
           where bpr.booking_id = pb.id
             and bpr.status = 'satisfied'
             and (satisfied.id is null or satisfied.status <> 'confirmed')
         ) then 'completed'
        else 'pending'
      end,
      earning_completed_at = case
        when lower(coalesce(pb.booking_status, pb.status, '')) in (
               'completed', 'done'
             )
         and pr.status = 'confirmed'
         and bd.status = 'completed'
         and pa.status <> 'manual_review'
         and not exists (
           select 1 from public.payment_disputes pd
           where pd.payment_record_id = pr.id and pd.status <> 'rejected'
         )
         and not exists (
           select 1 from public.refund_requests rr
           where rr.payment_record_id = pr.id
             and rr.status in ('pending', 'approved', 'completed')
         )
         and not exists (
           select 1 from public.booking_payment_requirements bpr
           where bpr.booking_id = pb.id and bpr.status = 'required'
         )
         and not exists (
           select 1
           from public.booking_payment_requirements bpr
           left join public.payment_records satisfied
             on satisfied.id = bpr.satisfied_by_payment_record_id
           where bpr.booking_id = pb.id
             and bpr.status = 'satisfied'
             and (satisfied.id is null or satisfied.status <> 'confirmed')
         ) then coalesce(pa.earning_completed_at, pb.completed_at, now())
        else null
      end,
      updated_at = now()
  from public.payment_records pr,
       public.package_bookings pb,
       public.booking_drivers bd
  where pa.booking_id = p_booking_id
    and pr.id = pa.payment_record_id
    and pb.id = pa.booking_id
    and bd.id = pa.booking_driver_id
    and (
      pa.earning_status is distinct from case
        when pr.status = 'disputed' or exists (
          select 1 from public.payment_disputes pd
          where pd.payment_record_id = pr.id and pd.status <> 'rejected'
        ) then 'disputed'
        when exists (
          select 1 from public.refund_requests rr
          where rr.payment_record_id = pr.id and rr.status = 'completed'
        ) then 'refunded'
        when exists (
          select 1 from public.refund_requests rr
          where rr.payment_record_id = pr.id
            and rr.status in ('pending', 'approved')
        ) then 'refund_pending'
        when pr.status = 'failed' then 'failed'
        when pr.status = 'cancelled' then 'cancelled'
        when pa.status = 'manual_review' then 'manual_review'
        when lower(coalesce(pb.booking_status, pb.status, '')) in ('completed', 'done')
         and pr.status = 'confirmed' and bd.status = 'completed'
         and not exists (
           select 1 from public.booking_payment_requirements bpr
           where bpr.booking_id = pb.id and bpr.status = 'required'
         )
         and not exists (
           select 1
           from public.booking_payment_requirements bpr
           left join public.payment_records satisfied
             on satisfied.id = bpr.satisfied_by_payment_record_id
           where bpr.booking_id = pb.id and bpr.status = 'satisfied'
             and (satisfied.id is null or satisfied.status <> 'confirmed')
         ) then 'completed'
        else 'pending'
      end
      or (
        pa.earning_completed_at is null
        and lower(coalesce(pb.booking_status, pb.status, '')) in ('completed', 'done')
        and pr.status = 'confirmed' and bd.status = 'completed'
      )
    );

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.recompute_booking_driver_earnings(uuid)
  from public, anon, authenticated;

create or replace function public.sync_booking_driver_earnings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking_id uuid;
begin
  if tg_table_name = 'package_bookings' then
    if tg_op = 'DELETE' then
      v_booking_id := old.id;
    else
      v_booking_id := new.id;
    end if;
  elsif tg_op = 'DELETE' then
    v_booking_id := old.booking_id;
  else
    v_booking_id := new.booking_id;
  end if;
  if v_booking_id is not null then
    perform public.recompute_booking_driver_earnings(v_booking_id);
  end if;
  return coalesce(new, old);
end;
$$;

revoke all on function public.sync_booking_driver_earnings()
  from public, anon, authenticated;

drop trigger if exists sync_driver_earnings_from_booking on public.package_bookings;
create trigger sync_driver_earnings_from_booking
after insert or update of status, booking_status, completed_at
on public.package_bookings
for each row execute function public.sync_booking_driver_earnings();

drop trigger if exists sync_driver_earnings_from_requirement
  on public.booking_payment_requirements;
create trigger sync_driver_earnings_from_requirement
after insert or update of status, satisfied_by_payment_record_id or delete
on public.booking_payment_requirements
for each row execute function public.sync_booking_driver_earnings();

drop trigger if exists sync_driver_earnings_from_payment on public.payment_records;
create trigger sync_driver_earnings_from_payment
after insert or update of status, paid_at or delete on public.payment_records
for each row execute function public.sync_booking_driver_earnings();

drop trigger if exists sync_driver_earnings_from_dispute on public.payment_disputes;
create trigger sync_driver_earnings_from_dispute
after insert or update of status or delete on public.payment_disputes
for each row execute function public.sync_booking_driver_earnings();

drop trigger if exists sync_driver_earnings_from_refund on public.refund_requests;
create trigger sync_driver_earnings_from_refund
after insert or update of status or delete on public.refund_requests
for each row execute function public.sync_booking_driver_earnings();

drop trigger if exists sync_driver_earnings_from_assignment on public.booking_drivers;
create trigger sync_driver_earnings_from_assignment
after insert or update of status, journey_state, completed_at or delete
on public.booking_drivers
for each row execute function public.sync_booking_driver_earnings();

create or replace view public.payment_allocation_summaries
with (security_barrier = true, security_invoker = true)
as
select pa.id, pa.payment_record_id, pa.booking_id, pa.driver_id,
       pa.gross_amount, pa.platform_fee, pa.driver_amount,
       pa.split_basis_points, pa.currency,
       pa.status, pa.provider_transfer_status,
       pa.created_at, pa.updated_at,
       pa.earning_status, pa.earning_completed_at
from public.payment_allocations pa
where pa.driver_id = auth.uid()
   or exists (
     select 1
     from public.package_bookings pb
     where pb.id = pa.booking_id
       and pb.tourist_id = auth.uid()
   )
   or public.is_provincial_admin()
   or public.subtenant_can_access_booking(pa.booking_id);

revoke all on public.payment_allocation_summaries from public, anon;
grant select on public.payment_allocation_summaries to authenticated;

create or replace function public.get_my_completed_driver_earnings(
  p_limit integer default 500
)
returns table (
  id uuid,
  payment_record_id uuid,
  booking_id uuid,
  booking_driver_id uuid,
  driver_id uuid,
  gross_amount numeric,
  platform_fee numeric,
  driver_amount numeric,
  split_basis_points integer,
  currency text,
  status text,
  earning_status text,
  earning_completed_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  payment_record_status text,
  provider text,
  payment_method text,
  payment_stage text,
  payment_paid_at timestamptz,
  receipt_no text,
  provider_payment_id text,
  provider_reference text,
  external_reference_no text,
  package_name text,
  tourist_first_name text,
  tourist_last_name text,
  booking_reference text,
  transaction_reference text
)
language sql
stable
security definer
set search_path = ''
as $$
  select pa.id, pa.payment_record_id, pa.booking_id, pa.booking_driver_id,
         pa.driver_id, pa.gross_amount, pa.platform_fee, pa.driver_amount,
         pa.split_basis_points, pa.currency, pa.status, pa.earning_status,
         pa.earning_completed_at, pa.paid_at, pa.created_at, pa.updated_at,
         pr.status, pr.provider, pr.payment_method, pr.payment_stage,
         pr.paid_at, pr.receipt_no, pr.provider_payment_id,
         pr.provider_reference, pr.external_reference_no,
         coalesce(tp.title, 'Tour Package'),
         coalesce(t.first_name, split_part(coalesce(t.full_name, ''), ' ', 1)),
         coalesce(t.last_name, nullif(regexp_replace(
           coalesce(t.full_name, ''), '^\\S+\\s*', ''), '')),
         '#' || upper(substr(pb.id::text, 1, 8)),
         coalesce(nullif(pr.provider_reference, ''),
                  nullif(pr.provider_payment_id, ''),
                  nullif(pr.receipt_no, ''),
                  nullif(pr.external_reference_no, ''), pr.id::text)
  from public.payment_allocations pa
  join public.payment_records pr on pr.id = pa.payment_record_id
  join public.package_bookings pb on pb.id = pa.booking_id
  left join public.tour_packages tp on tp.id = pb.package_id
  left join public.profiles t on t.id = pb.tourist_id
  where pa.driver_id = auth.uid()
    and pr.status = 'confirmed'
    and pa.earning_status not in ('cancelled', 'manual_review')
  order by coalesce(pa.earning_completed_at, pr.paid_at, pa.created_at) desc
  limit least(greatest(coalesce(p_limit, 500), 1), 1000);
$$;

revoke all on function public.get_my_completed_driver_earnings(integer)
  from public, anon;
grant execute on function public.get_my_completed_driver_earnings(integer)
  to authenticated;

-- TEST MODE remains participant-scoped and server-authoritative. Only the
-- schedule boundary changes; terminal booking and assignment checks remain.
create or replace function public.can_access_live_tour_tracking(
  p_booking_id uuid,
  p_actor_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.package_bookings b
    where b.id = p_booking_id
      and p_actor_id is not null
      and p_actor_id = auth.uid()
      and b.scheduled_start_at is not null
      and (
        now() >= b.scheduled_start_at
        or public.developer_test_schedule_bypass_authorized(b.id, p_actor_id)
      )
      and lower(coalesce(b.booking_status, b.status, '')) not in (
        'cancelled', 'completed', 'done', 'rejected', 'expired', 'failed',
        'closed', 'refunded', 'tourist_no_show'
      )
      and (
        b.tourist_id = p_actor_id
        or exists (
          select 1 from public.booking_drivers bd
          where bd.booking_id = b.id
            and bd.driver_id = p_actor_id
            and bd.status = 'accepted'
        )
      )
  );
$$;

revoke all on function public.can_access_live_tour_tracking(uuid,uuid)
  from public, anon;
grant execute on function public.can_access_live_tour_tracking(uuid,uuid)
  to authenticated;

create or replace function public.get_live_tour_tracking_eligibility(
  p_booking_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_booking public.package_bookings;
  v_participant boolean;
  v_can_access boolean;
  v_test_bypass boolean := false;
  v_reason text;
begin
  if v_actor is null then raise exception 'UNAUTHENTICATED'; end if;
  select * into v_booking from public.package_bookings where id = p_booking_id;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;

  v_participant := v_booking.tourist_id = v_actor or exists (
    select 1 from public.booking_drivers bd
    where bd.booking_id = p_booking_id
      and bd.driver_id = v_actor and bd.status = 'accepted'
  );
  if not v_participant then raise exception 'NOT_BOOKING_PARTICIPANT'; end if;

  v_test_bypass := now() < v_booking.scheduled_start_at
    and public.developer_test_schedule_bypass_authorized(p_booking_id, v_actor);
  v_can_access := public.can_access_live_tour_tracking(p_booking_id, v_actor);
  v_reason := case
    when lower(coalesce(v_booking.booking_status, v_booking.status, '')) in (
      'cancelled', 'completed', 'done', 'rejected', 'expired', 'failed',
      'closed', 'refunded', 'tourist_no_show'
    ) then 'BOOKING_NOT_TRACKABLE'
    when v_booking.scheduled_start_at is null then 'SCHEDULE_UNAVAILABLE'
    when v_test_bypass and v_can_access then 'TEST_MODE_SCHEDULE_BYPASS'
    when now() < v_booking.scheduled_start_at then 'BEFORE_SCHEDULED_START'
    when v_can_access then 'ELIGIBLE'
    else 'NOT_ACTIVE_PARTICIPANT'
  end;

  return jsonb_build_object(
    'can_access', v_can_access,
    'reason_code', v_reason,
    'server_now', now(),
    'scheduled_start_at', v_booking.scheduled_start_at,
    'test_mode_schedule_bypass', v_test_bypass and v_can_access
  );
end;
$$;

revoke all on function public.get_live_tour_tracking_eligibility(uuid)
  from public, anon;
grant execute on function public.get_live_tour_tracking_eligibility(uuid)
  to authenticated;

do $$
declare
  v_booking_id uuid;
begin
  for v_booking_id in
    select distinct booking_id from public.payment_allocations
  loop
    perform public.recompute_booking_driver_earnings(v_booking_id);
  end loop;
end;
$$;

commit;
