-- Preserve the package identity shown in booking history. Booking itinerary
-- items are already immutable booking-time snapshots; these columns prevent a
-- later package rename/city edit from rewriting historical booking context.

alter table public.package_bookings
  add column if not exists package_title_snapshot text,
  add column if not exists package_city_snapshot text;

update public.package_bookings booking
set package_title_snapshot = coalesce(
      nullif(btrim(booking.package_title_snapshot), ''),
      nullif(btrim(package.title), ''),
      'Tour Package'
    ),
    package_city_snapshot = coalesce(
      nullif(btrim(booking.package_city_snapshot), ''),
      nullif(btrim(booking.municipality), ''),
      nullif(btrim(package.city), '')
    )
from public.tour_packages package
where package.id = booking.package_id
  and (
    nullif(btrim(booking.package_title_snapshot), '') is null
    or nullif(btrim(booking.package_city_snapshot), '') is null
  );

create or replace function public.snapshot_package_booking_display_details()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text;
  v_city text;
begin
  if nullif(btrim(new.package_title_snapshot), '') is null
     or nullif(btrim(new.package_city_snapshot), '') is null then
    select nullif(btrim(package.title), ''), nullif(btrim(package.city), '')
    into v_title, v_city
    from public.tour_packages package
    where package.id = new.package_id;

    new.package_title_snapshot := coalesce(
      nullif(btrim(new.package_title_snapshot), ''),
      v_title,
      'Tour Package'
    );
    new.package_city_snapshot := coalesce(
      nullif(btrim(new.package_city_snapshot), ''),
      nullif(btrim(new.municipality), ''),
      v_city
    );
  end if;
  return new;
end;
$$;

revoke all on function public.snapshot_package_booking_display_details()
  from public, anon, authenticated;

drop trigger if exists snapshot_package_booking_display_details
  on public.package_bookings;
create trigger snapshot_package_booking_display_details
before insert on public.package_bookings
for each row execute function public.snapshot_package_booking_display_details();

