alter table public.package_bookings
  add column if not exists pickup_province text,
  add column if not exists pickup_locality text,
  add column if not exists pickup_country_code text default 'PH',
  add column if not exists dropoff_province text,
  add column if not exists dropoff_locality text,
  add column if not exists dropoff_country_code text default 'PH';

alter table public.booking_itinerary_items
  add column if not exists order_number integer,
  add column if not exists itinerary_source text;

update public.booking_itinerary_items
set
  order_number = coalesce(order_number, destination_order),
  itinerary_source = coalesce(itinerary_source, source_type, 'ai_suggested')
where order_number is null
   or itinerary_source is null;

alter table public.booking_itinerary_items
  alter column order_number set not null;

alter table public.booking_itinerary_items
  alter column itinerary_source set default 'ai_suggested';

alter table public.booking_itinerary_items
  drop constraint if exists booking_itinerary_items_itinerary_source_check;

alter table public.booking_itinerary_items
  add constraint booking_itinerary_items_itinerary_source_check
  check (itinerary_source in ('ai_suggested', 'customized'));

create unique index if not exists booking_itinerary_items_booking_order_number_unique
  on public.booking_itinerary_items(booking_id, order_number);
