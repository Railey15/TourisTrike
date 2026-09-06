-- Testing Mode bypasses operational gates, but arrival always uses the
-- canonical live-location proximity guard. Human fallback keeps its own RPC.
begin;

create or replace function public.debug_advance_driver_journey_state(
  p_booking_id uuid,
  p_target_state text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_result jsonb;
begin
  perform public.debug_test_driver_assignment(p_booking_id);
  perform set_config(
    'touristrike.debug_progression_bypass',
    case when p_target_state in ('at_pickup', 'at_stop', 'at_dropoff')
      then 'false' else 'true' end,
    true
  );
  v_result := public.advance_driver_journey_state(p_booking_id, p_target_state);
  perform set_config('touristrike.debug_progression_bypass', 'false', true);
  return v_result;
end;
$$;

revoke all on function public.debug_advance_driver_journey_state(uuid,text)
  from public, anon;
grant execute on function public.debug_advance_driver_journey_state(uuid,text)
  to authenticated;

commit;
