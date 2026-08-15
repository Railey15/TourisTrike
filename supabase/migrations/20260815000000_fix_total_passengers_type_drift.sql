-- ============================================================
-- Fix schema drift: package_bookings.total_passengers is `text` on the
-- live database instead of the `integer not null default 0` declared by
-- 20260520170000_dispatch_and_group_booking_fix.sql:5. Confirmed live
-- via information_schema.columns:
--   total_passengers -> data_type: text, is_nullable: YES, default: NULL
--   adults            -> integer, NOT NULL, default 1
--   children          -> integer, NOT NULL, default 0
-- The column was added to the live DB by hand through the Supabase Table
-- Editor at some point, bypassing migrations entirely — this is the root
-- cause, not a mistake in the RPC. This is the exact reason the 2nd
-- driver's accept_package_booking call fails with "Failed to accept
-- booking": its CASE expression returns `text` (v_booking.total_passengers)
-- on one branch and `integer` (adults + children) on the other, which
-- only actually executes once the roster is full — i.e. only on the LAST
-- driver's accept.
--
-- Before applying: run this read-only check for values that are neither
-- null/blank nor purely numeric text (e.g. "12 pax", "abc") — anything
-- it returns needs a manual look before you proceed, since the coercion
-- below silently drops non-numeric text to NULL/0:
--
--   select id, total_passengers
--   from public.package_bookings
--   where total_passengers is not null
--     and trim(total_passengers) <> ''
--     and trim(total_passengers) !~ '^\d+$';
-- ============================================================

-- ── 1. Column fix ──────────────────────────────────────────────
-- USING clause is deliberately defensive rather than a bare ::integer
-- cast: a bare cast raises and aborts the whole migration on the first
-- non-numeric value (blank string, stray whitespace, or genuinely dirty
-- text). null/blank collapses to NULL here, then the UPDATE below
-- backfills every NULL to 0 — matches the column's original declared
-- default. Run the pre-check above FIRST so dirty text doesn't silently
-- disappear into a 0 without you having seen it.
alter table public.package_bookings
  alter column total_passengers type integer
  using (
    case
      when total_passengers is null then null
      when trim(total_passengers) = '' then null
      when trim(total_passengers) ~ '^\d+$' then trim(total_passengers)::integer
      else null
    end
  );

update public.package_bookings
set total_passengers = 0
where total_passengers is null;

alter table public.package_bookings
  alter column total_passengers set default 0;

alter table public.package_bookings
  alter column total_passengers set not null;

-- ── 2. accept_package_booking: defensive cast, not the fix itself ──
-- Byte-for-byte the version from 20260805030000_convoy_phase3_
-- passenger_split_and_slot_release.sql, EXCEPT both CASE branches now
-- carry an explicit ::integer cast. The real fix is section 1 above —
-- once the column is genuinely `integer`, this cast is a no-op. It is
-- deliberately left in anyway as a defensive guard: if this exact drift
-- ever reoccurs (column hand-edited back to text), this CASE would
-- immediately break group-booking accepts again in a way that only
-- reproduces on the LAST driver of a group, which is exactly what made
-- it slow to diagnose the first time. Do not remove this cast in a
-- future "cleanup" refactor without also adding a regression test or a
-- CI check that fails on column-type drift for this table.
create or replace function public.accept_package_booking(
  p_booking_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id     uuid := auth.uid();
  v_driver        public.profiles;
  v_booking       public.package_bookings;
  v_activity_id   uuid;
  v_live_count    integer;
  v_new_count     integer;
begin
  if v_driver_id is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select * into v_driver from public.profiles where id = v_driver_id;
  if not found then
    raise exception 'DRIVER_NOT_FOUND';
  end if;
  if v_driver.role <> 'driver' then
    raise exception 'DRIVER_ROLE_REQUIRED';
  end if;
  if not (coalesce(v_driver.is_online, false) or coalesce(v_driver.is_available, false)) then
    raise exception 'DRIVER_NOT_AVAILABLE';
  end if;

  select * into v_booking
  from public.package_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'BOOKING_NOT_FOUND';
  end if;

  if v_booking.booking_status not in ('pending', 'waiting_for_drivers') then
    raise exception 'BOOKING_NOT_AVAILABLE';
  end if;

  if v_booking.municipality is not null
     and trim(v_booking.municipality) <> ''
  then
    if trim(lower(coalesce(v_driver.city, ''))) <> trim(lower(v_booking.municipality)) then
      raise exception 'MUNICIPALITY_MISMATCH: Booking is for % only.', v_booking.municipality;
    end if;
  end if;

  select count(*) into v_live_count
  from public.booking_drivers
  where booking_id = p_booking_id and status = 'accepted';

  if v_live_count >= coalesce(v_booking.required_drivers, 1) then
    raise exception 'BOOKING_ALREADY_FULL';
  end if;

  if exists (
    select 1 from public.booking_drivers
    where booking_id = p_booking_id and driver_id = v_driver_id
  ) then
    raise exception 'ALREADY_ACCEPTED';
  end if;

  select id into v_activity_id
  from public.package_activities
  where booking_id = p_booking_id
  limit 1;

  insert into public.booking_drivers
    (booking_id, driver_id, status, accepted_at)
  values
    (p_booking_id, v_driver_id, 'accepted', now());

  v_new_count := v_live_count + 1;

  if v_new_count >= coalesce(v_booking.required_drivers, 1) then
    if v_activity_id is not null then
      update public.package_activities
      set driver_id   = v_driver_id,
          status      = 'accepted',
          tour_status = 'driver_accepted',
          accepted_at = now(),
          updated_at  = now()
      where id = v_activity_id;
    end if;

    update public.package_bookings
    set assigned_driver_id     = v_driver_id,
        accepted_drivers_count = v_new_count,
        status                 = 'confirmed',
        booking_status         = 'accepted',
        accepted_at            = now(),
        updated_at             = now()
    where id = p_booking_id;

    -- Defensive ::integer cast on both branches — see header comment.
    update public.booking_drivers bd
    set assigned_passengers = split.passenger_count
    from public.compute_passenger_split(
      p_booking_id,
      case when coalesce(v_booking.total_passengers, 0) > 0
           then v_booking.total_passengers::integer
           else (v_booking.adults + coalesce(v_booking.children, 0))::integer
      end
    ) as split
    where bd.booking_id = p_booking_id
      and bd.driver_id = split.driver_id;
  else
    update public.package_bookings
    set accepted_drivers_count = v_new_count,
        booking_status         = 'waiting_for_drivers',
        updated_at             = now()
    where id = p_booking_id;
  end if;

  return jsonb_build_object(
    'success',        true,
    'booking_id',     p_booking_id,
    'accepted_count', v_new_count,
    'required_count', coalesce(v_booking.required_drivers, 1),
    'all_filled',     v_new_count >= coalesce(v_booking.required_drivers, 1)
  );
end;
$$;

grant execute on function public.accept_package_booking(uuid) to authenticated;
