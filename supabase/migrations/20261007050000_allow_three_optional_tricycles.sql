-- Expand the already present optional request from 0-1 to 0-3.
-- Fare and capacity-required drivers remain owned by the existing booking RPC.
begin;

alter table public.package_bookings
  drop constraint package_booking_additional_tricycle_request_check;
alter table public.package_bookings
  add constraint package_booking_additional_tricycle_request_check
  check (coalesce((
    (additional_tricycle_count = 0
      and additional_tricycle_reason is null
      and additional_tricycle_explanation is null)
    or
    (additional_tricycle_count between 1 and 3
      and additional_tricycle_reason in (
        'extra_luggage', 'accessibility_needs', 'additional_space', 'other'
      )
      and (
        (additional_tricycle_reason = 'other'
          and char_length(btrim(additional_tricycle_explanation)) between 5 and 200)
        or
        (additional_tricycle_reason <> 'other'
          and additional_tricycle_explanation is null)
      ))
  ), false));

create or replace function public.create_package_booking(
  p_booking jsonb,
  p_customized_spots jsonb default '[]'::jsonb,
  p_itinerary_items jsonb default '[]'::jsonb
)
returns public.package_bookings
language plpgsql security definer set search_path = '' as $$
declare
  v_booking public.package_bookings;
  v_count integer;
  v_reason text;
  v_explanation text;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  v_count := coalesce((p_booking->>'additional_tricycle_count')::integer, 0);
  v_reason := nullif(btrim(p_booking->>'additional_tricycle_reason'), '');
  v_explanation := nullif(btrim(p_booking->>'additional_tricycle_explanation'), '');
  if v_count < 0 or v_count > 3 then
    raise exception 'INVALID_ADDITIONAL_TRICYCLE_COUNT';
  end if;
  if (v_count = 0 and (v_reason is not null or v_explanation is not null))
     or (v_count > 0 and (
       v_reason not in ('extra_luggage', 'accessibility_needs',
         'additional_space', 'other')
       or v_reason is null
       or (v_reason = 'other' and
         (v_explanation is null or char_length(v_explanation) not between 5 and 200))
       or (v_reason <> 'other' and v_explanation is not null))) then
    raise exception 'INVALID_ADDITIONAL_TRICYCLE_REASON';
  end if;

  select * into v_booking
  from public.create_package_booking_additional_request_impl(
    p_booking, p_customized_spots, p_itinerary_items
  );

  if v_count > 0 then
    perform set_config('touristrike.additional_request_write', 'true', true);
    update public.package_bookings
    set additional_tricycle_count = v_count,
        additional_tricycle_reason = v_reason,
        additional_tricycle_explanation = v_explanation
    where id = v_booking.id and tourist_id = auth.uid()
    returning * into v_booking;
    if not found then raise exception 'ADDITIONAL_TRICYCLE_SAVE_FAILED'; end if;
    perform set_config('touristrike.additional_request_write', '', true);
  end if;
  return v_booking;
end;
$$;

commit;
