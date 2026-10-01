-- A late event from an older attempt must not replace a newer Driver attempt.
create or replace function public.apply_driver_identity_webhook_status(
  p_session_id uuid, p_provider_status text, p_event_at timestamptz
)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare
  v_driver_id uuid;
  v_row public.driver_identity_verifications%rowtype;
  v_status text;
  v_current_rank integer;
  v_new_rank integer;
begin
  v_status := case p_provider_status
    when 'Not Started' then 'not_started'
    when 'In Progress' then 'in_progress'
    when 'Awaiting User' then 'in_progress'
    when 'Resubmitted' then 'in_progress'
    when 'In Review' then 'in_review'
    when 'Approved' then 'approved'
    when 'Declined' then 'declined'
    when 'Expired' then 'expired'
    when 'Abandoned' then 'expired'
    when 'Kyc Expired' then 'expired'
    else null end;
  if v_status is null then return false; end if;
  select driver_id into v_driver_id from public.driver_identity_verifications
  where provider_session_id = p_session_id;
  if not found then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_driver_id::text, 4096));
  select * into v_row from public.driver_identity_verifications
  where provider_session_id = p_session_id for update;
  if not found then return false; end if;
  if exists (
    select 1 from public.driver_identity_verifications newer
    where newer.driver_id = v_row.driver_id and newer.created_at > v_row.created_at
  ) then return true; end if;
  v_current_rank := case v_row.status
    when 'approved' then 5 when 'declined' then 4 when 'expired' then 4
    when 'in_review' then 3 when 'in_progress' then 2 else 1 end;
  v_new_rank := case v_status
    when 'approved' then 5 when 'declined' then 4 when 'expired' then 4
    when 'in_review' then 3 when 'in_progress' then 2 else 1 end;
  if v_row.provider_event_at is not null and
    (p_event_at < v_row.provider_event_at or
      (p_event_at = v_row.provider_event_at and v_new_rank <= v_current_rank)) then
    return true;
  end if;
  update public.driver_identity_verifications
  set status = v_status, provider_status = p_provider_status,
      provider_event_at = p_event_at, updated_at = now(),
      verified_at = case when v_status = 'approved' then p_event_at else verified_at end,
      declined_at = case when v_status = 'declined' then p_event_at else declined_at end
  where id = v_row.id;
  if v_status in ('approved','declined') and v_status is distinct from v_row.status then
    insert into public.audit_logs (action, table_name, record_id, description)
    values ('driver_identity_verification_' || v_status,
      'driver_identity_verifications', v_row.id::text,
      'Didit identity result recorded.');
  end if;
  return true;
end;
$$;
