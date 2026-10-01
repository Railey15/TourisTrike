-- Make case lifecycle mutations idempotent and keep notification delivery a
-- best-effort side effect. Audit history remains part of the authoritative
-- transaction: an audit failure rolls the status transition back.

begin;

create or replace function public.start_dispute_case(p_case_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.payment_disputes;
  v_recipient uuid;
  v_notification_failures integer := 0;
begin
  if not public.can_manage_dispute_case(p_case_id) then
    raise exception 'NOT_AUTHORIZED' using errcode = '42501';
  end if;

  select * into v_case
  from public.payment_disputes
  where id = p_case_id
  for update;

  if not found then
    raise exception 'CASE_NOT_FOUND';
  end if;

  -- A retry after a committed response loss is a successful no-op. It must
  -- not create another audit event or another notification.
  if v_case.status = 'under_review'
     and v_case.reviewed_at is not null
     and v_case.assigned_to is not null then
    return to_jsonb(v_case) || jsonb_build_object(
      'transitioned', false,
      'notification_failures', 0
    );
  end if;
  if v_case.status <> 'needs_review' then
    raise exception 'CASE_NOT_AVAILABLE_FOR_REVIEW';
  end if;

  update public.payment_disputes
  set status = 'under_review',
      reviewed_at = now(),
      assigned_to = auth.uid()
  where id = p_case_id
    and status = 'needs_review'
  returning * into v_case;

  if not found then
    raise exception 'CASE_REVIEW_TRANSITION_CONFLICT';
  end if;

  insert into public.audit_logs(
    actor_id, action, table_name, record_id, description
  ) values (
    auth.uid(),
    'start_case_review',
    'payment_disputes',
    v_case.id::text,
    'Review started for ' || v_case.category || ' case in ' || v_case.municipality
  );

  foreach v_recipient in array array[v_case.raised_by, v_case.reported_user_id] loop
    if v_recipient is not null and v_recipient <> auth.uid() then
      begin
        insert into public.notifications(
          user_id, title, body, type, is_read, dedupe_key
        ) values (
          v_recipient,
          'Case review started',
          'Your TourisTrike case ' || upper(left(v_case.id::text, 8)) ||
            ' is under review.',
          'dispute_case',
          false,
          'dispute:' || v_case.id::text || ':review_started:' || v_recipient::text
        ) on conflict do nothing;
      exception when others then
        v_notification_failures := v_notification_failures + 1;
        raise warning 'CASE_NOTIFICATION_FAILED case=% phase=review state=% message=%',
          v_case.id, sqlstate, sqlerrm;
      end;
    end if;
  end loop;

  return to_jsonb(v_case) || jsonb_build_object(
    'transitioned', true,
    'notification_failures', v_notification_failures
  );
end;
$$;

create or replace function public.resolve_dispute_case(
  p_case_id uuid,
  p_resolution_type text,
  p_resolution_notes text,
  p_custom_resolution text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.payment_disputes;
  v_recipient uuid;
  v_custom_resolution text := nullif(trim(coalesce(p_custom_resolution, '')), '');
  v_notification_failures integer := 0;
begin
  if p_resolution_type not in (
    'no_action_required', 'warning_issued', 'driver_suspended',
    'booking_issue_resolved', 'payment_issue_resolved',
    'referred_tourism_office', 'dismissed_insufficient_evidence',
    'other_resolution'
  ) then
    raise exception 'INVALID_RESOLUTION_TYPE';
  end if;
  if nullif(trim(p_resolution_notes), '') is null then
    raise exception 'RESOLUTION_NOTES_REQUIRED';
  end if;
  if p_resolution_type = 'other_resolution' and v_custom_resolution is null then
    raise exception 'CUSTOM_RESOLUTION_REQUIRED';
  end if;

  if not public.can_manage_dispute_case(p_case_id) then
    raise exception 'NOT_AUTHORIZED' using errcode = '42501';
  end if;

  select * into v_case
  from public.payment_disputes
  where id = p_case_id
  for update;

  if not found then
    raise exception 'CASE_NOT_FOUND';
  end if;

  -- Exact retries are successful no-ops. A conflicting second resolution is
  -- rejected and cannot overwrite the authoritative outcome.
  if v_case.status = 'closed' then
    if v_case.resolution_type = p_resolution_type
       and trim(coalesce(v_case.resolution_note, '')) = trim(p_resolution_notes)
       and v_case.custom_resolution is not distinct from v_custom_resolution
       and v_case.resolved_at is not null then
      return to_jsonb(v_case) || jsonb_build_object(
        'transitioned', false,
        'notification_failures', 0
      );
    end if;
    raise exception 'CASE_ALREADY_RESOLVED';
  end if;
  if v_case.status <> 'under_review' then
    raise exception 'CASE_NOT_AVAILABLE_FOR_RESOLUTION';
  end if;

  update public.payment_disputes
  set status = 'closed',
      resolution_type = p_resolution_type,
      custom_resolution = v_custom_resolution,
      resolution_note = trim(p_resolution_notes),
      resolved_by = auth.uid(),
      resolved_at = now(),
      reviewed_at = coalesce(reviewed_at, now()),
      assigned_to = coalesce(assigned_to, auth.uid())
  where id = p_case_id
    and status = 'under_review'
  returning * into v_case;

  if not found then
    raise exception 'CASE_RESOLUTION_TRANSITION_CONFLICT';
  end if;

  -- This remains part of the authoritative payment-case transaction. It never
  -- transfers funds and does not invoke driver suspension.
  if v_case.payment_record_id is not null then
    update public.payment_records
    set status = case
      when p_resolution_type = 'dismissed_insufficient_evidence' then 'confirmed'
      else status
    end
    where id = v_case.payment_record_id;
  end if;

  insert into public.audit_logs(
    actor_id, action, table_name, record_id, description
  ) values (
    auth.uid(),
    'resolve_dispute_case',
    'payment_disputes',
    v_case.id::text,
    'Case closed: ' || p_resolution_type ||
      ' | notes=' || trim(p_resolution_notes)
  );

  foreach v_recipient in array array[v_case.raised_by, v_case.reported_user_id] loop
    if v_recipient is not null and v_recipient <> auth.uid() then
      begin
        insert into public.notifications(
          user_id, title, body, type, is_read, dedupe_key
        ) values (
          v_recipient,
          'Case resolved',
          'TourisTrike case ' || upper(left(v_case.id::text, 8)) ||
            ' has been closed.',
          'dispute_case',
          false,
          'dispute:' || v_case.id::text || ':resolved:' || v_recipient::text
        ) on conflict do nothing;
      exception when others then
        v_notification_failures := v_notification_failures + 1;
        raise warning 'CASE_NOTIFICATION_FAILED case=% phase=resolve state=% message=%',
          v_case.id, sqlstate, sqlerrm;
      end;
    end if;
  end loop;

  return to_jsonb(v_case) || jsonb_build_object(
    'transitioned', true,
    'notification_failures', v_notification_failures
  );
end;
$$;

revoke all on function public.start_dispute_case(uuid) from public, anon;
revoke all on function public.resolve_dispute_case(uuid, text, text, text)
  from public, anon;
grant execute on function public.start_dispute_case(uuid) to authenticated;
grant execute on function public.resolve_dispute_case(uuid, text, text, text)
  to authenticated;

commit;
