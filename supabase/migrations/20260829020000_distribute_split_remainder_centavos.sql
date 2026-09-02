-- Keep equal splits deterministic while distributing indivisible centavos one
-- at a time across the accepted-driver order (accepted_at ASC, id ASC).

create or replace function public.compute_equal_split_centavos(
  p_total_centavos bigint,
  p_recipient_count integer
)
returns table (
  recipient_position integer,
  amount_centavos bigint,
  basis_points integer
)
language plpgsql
immutable
set search_path = public
as $$
declare
  v_amount_base bigint;
  v_amount_remainder bigint;
  v_bps_base integer;
  v_bps_remainder integer;
begin
  if p_total_centavos <= 0 or p_recipient_count <= 0 then
    raise exception 'INVALID_SPLIT_INPUT';
  end if;

  v_amount_base := p_total_centavos / p_recipient_count;
  v_amount_remainder := p_total_centavos % p_recipient_count;
  v_bps_base := 10000 / p_recipient_count;
  v_bps_remainder := 10000 % p_recipient_count;

  return query
  select series,
    v_amount_base + case when series <= v_amount_remainder then 1 else 0 end,
    v_bps_base + case when series <= v_bps_remainder then 1 else 0 end
  from generate_series(1, p_recipient_count) series;
end;
$$;
