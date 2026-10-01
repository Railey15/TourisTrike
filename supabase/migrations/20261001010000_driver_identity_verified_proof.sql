-- Store only a recognized ID class from a signed, approved Didit decision.
-- Existing approved sessions have no stored document class and display a fallback.
alter table public.driver_identity_verifications
  add column verified_document_type text
  check (verified_document_type in (
    'Driver''s License', 'Identity Card', 'Passport', 'Residence Permit'
  ));

-- An approved webhook can arrive before its session is linked. Retain only the
-- normalized class in the private replay ledger, never the provider decision.
alter table public.didit_verification_events
  add column verified_document_type text
  check (verified_document_type in (
    'Driver''s License', 'Identity Card', 'Passport', 'Residence Permit'
  ));

create function public.record_driver_verified_document_type(
  p_session_id uuid, p_event_at timestamptz, p_document_type text
)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if p_document_type not in (
    'Driver''s License', 'Identity Card', 'Passport', 'Residence Permit'
  ) then return false; end if;
  update public.driver_identity_verifications v
  set verified_document_type = p_document_type
  where v.provider_session_id = p_session_id
    and v.status = 'approved'
    and v.provider_event_at = p_event_at
    and (v.verified_document_type is null or v.verified_document_type = p_document_type)
    and not exists (
      select 1 from public.driver_identity_verifications newer
      where newer.driver_id = v.driver_id and newer.created_at > v.created_at
    );
  return found;
end;
$$;
revoke all on function public.record_driver_verified_document_type(uuid,timestamptz,text)
  from public, anon, authenticated;
grant execute on function public.record_driver_verified_document_type(uuid,timestamptz,text)
  to service_role;

-- Driver-only projection: no media, document number, URL, provider metadata,
-- or license/MTO decision can cross into Flutter through this RPC.
create function public.get_my_driver_identity_proof()
returns table(status text, verified_at timestamptz, verified_document_type text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'driver'
  ) then
    raise exception 'DRIVER_REQUIRED' using errcode = '42501';
  end if;
  return query
    select v.status,
      case when v.status = 'approved' then v.verified_at else null end,
      case when v.status = 'approved' then v.verified_document_type else null end
    from public.driver_identity_verifications v
    where v.driver_id = auth.uid()
    order by v.created_at desc limit 1;
end;
$$;
revoke all on function public.get_my_driver_identity_proof()
  from public, anon;
grant execute on function public.get_my_driver_identity_proof()
  to authenticated;
