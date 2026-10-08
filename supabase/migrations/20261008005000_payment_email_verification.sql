-- A prior schema change created these objects without recording this migration.
-- Reuse that table only when its security-critical shape is
-- exactly the shape this migration would create; never replace or clear data.
do $$
begin
  if to_regclass('public.payment_email_verifications') is null then
    create table public.payment_email_verifications (
      id uuid primary key default gen_random_uuid(),
      tourist_id uuid not null references auth.users(id) on delete cascade,
      booking_id uuid not null references public.package_bookings(id) on delete cascade,
      payment_stage text not null check (payment_stage in ('down_payment', 'remaining_balance')),
      amount numeric(14,2) not null check (amount > 0),
      code_hash text not null,
      sent_at timestamptz not null default now(),
      expires_at timestamptz not null,
      attempts integer not null default 0 check (attempts between 0 and 5),
      verified_until timestamptz,
      consumed_at timestamptz,
      unique (tourist_id, booking_id, payment_stage)
    );
  else
    if not exists (
      select 1 from pg_catalog.pg_class c
      where c.oid = 'public.payment_email_verifications'::regclass
        and c.relkind = 'r' and c.relrowsecurity
        and not c.relforcerowsecurity
        and pg_get_userbyid(c.relowner) = 'postgres'
    ) then raise exception 'PAYMENT_OTP_SCHEMA_MISMATCH: table or RLS'; end if;

    if exists (
      with expected(name, data_type, required, default_expr) as (values
        ('id', 'uuid', true, 'gen_random_uuid()'),
        ('tourist_id', 'uuid', true, null),
        ('booking_id', 'uuid', true, null),
        ('payment_stage', 'text', true, null),
        ('amount', 'numeric(14,2)', true, null),
        ('code_hash', 'text', true, null),
        ('sent_at', 'timestamp with time zone', true, 'now()'),
        ('expires_at', 'timestamp with time zone', true, null),
        ('attempts', 'integer', true, '0'),
        ('verified_until', 'timestamp with time zone', false, null),
        ('consumed_at', 'timestamp with time zone', false, null)
      ), actual as (
        select a.attname::text as name,
          pg_catalog.format_type(a.atttypid, a.atttypmod) as data_type,
          a.attnotnull as required,
          pg_catalog.pg_get_expr(d.adbin, d.adrelid) as default_expr,
          a.attidentity, a.attgenerated, a.attacl
        from pg_catalog.pg_attribute a
        left join pg_catalog.pg_attrdef d
          on d.adrelid = a.attrelid and d.adnum = a.attnum
        where a.attrelid = 'public.payment_email_verifications'::regclass
          and a.attnum > 0 and not a.attisdropped
      )
      select 1 from expected e full join actual a using (name)
      where e.name is null or a.name is null
        or e.data_type is distinct from a.data_type
        or e.required is distinct from a.required
        or e.default_expr is distinct from a.default_expr
        or a.attidentity <> '' or a.attgenerated <> '' or a.attacl is not null
    ) then raise exception 'PAYMENT_OTP_SCHEMA_MISMATCH: columns'; end if;

    if (select count(*) from pg_catalog.pg_constraint
        where conrelid = 'public.payment_email_verifications'::regclass
          and contype <> 'n') <> 7
      or (select count(distinct pg_catalog.pg_get_constraintdef(oid))
          from pg_catalog.pg_constraint
          where conrelid = 'public.payment_email_verifications'::regclass
            and contype <> 'n') <> 7
      or exists (
        select 1 from pg_catalog.pg_constraint c
        where c.conrelid = 'public.payment_email_verifications'::regclass
          and c.contype <> 'n'
          and (not c.convalidated or pg_catalog.pg_get_constraintdef(c.oid) not in (
            'PRIMARY KEY (id)',
            'UNIQUE (tourist_id, booking_id, payment_stage)',
            'FOREIGN KEY (tourist_id) REFERENCES auth.users(id) ON DELETE CASCADE',
            'FOREIGN KEY (booking_id) REFERENCES package_bookings(id) ON DELETE CASCADE',
            'CHECK ((payment_stage = ANY (ARRAY[''down_payment''::text, ''remaining_balance''::text])))',
            'CHECK ((amount > (0)::numeric))',
            'CHECK (((attempts >= 0) AND (attempts <= 5)))'
          )))
    then raise exception 'PAYMENT_OTP_SCHEMA_MISMATCH: constraints'; end if;

    if (select count(*) from pg_catalog.pg_index
        where indrelid = 'public.payment_email_verifications'::regclass) <> 2
      or (select count(distinct pg_catalog.pg_get_indexdef(indexrelid))
          from pg_catalog.pg_index
          where indrelid = 'public.payment_email_verifications'::regclass) <> 2
      or exists (
        select 1 from pg_catalog.pg_index i
        where i.indrelid = 'public.payment_email_verifications'::regclass
          and (not i.indisvalid or pg_catalog.pg_get_indexdef(i.indexrelid) not in (
            'CREATE UNIQUE INDEX payment_email_verifications_pkey ON public.payment_email_verifications USING btree (id)',
            'CREATE UNIQUE INDEX payment_email_verifications_tourist_id_booking_id_payment_s_key ON public.payment_email_verifications USING btree (tourist_id, booking_id, payment_stage)'
          )))
    then raise exception 'PAYMENT_OTP_SCHEMA_MISMATCH: indexes'; end if;

    if exists (select 1 from pg_catalog.pg_policy
        where polrelid = 'public.payment_email_verifications'::regclass)
      or exists (select 1 from pg_catalog.pg_trigger
        where tgrelid = 'public.payment_email_verifications'::regclass
          and not tgisinternal)
      or exists (
        select 1 from pg_catalog.pg_class c
        cross join lateral aclexplode(coalesce(c.relacl,
          acldefault('r', c.relowner))) acl
        where c.oid = 'public.payment_email_verifications'::regclass
          and acl.grantee not in (c.relowner, 'service_role'::regrole::oid)
      )
      or not (
        has_table_privilege('service_role', 'public.payment_email_verifications', 'SELECT')
        and has_table_privilege('service_role', 'public.payment_email_verifications', 'INSERT')
        and has_table_privilege('service_role', 'public.payment_email_verifications', 'UPDATE')
        and has_table_privilege('service_role', 'public.payment_email_verifications', 'DELETE')
      )
    then raise exception 'PAYMENT_OTP_SCHEMA_MISMATCH: policies or grants'; end if;
  end if;
end;
$$;
alter table public.payment_email_verifications enable row level security;
revoke all on public.payment_email_verifications from public, anon, authenticated;
grant select, insert, update, delete on public.payment_email_verifications to service_role;
create or replace function public.request_payment_email_verification(
  p_tourist_id uuid, p_booking_id uuid, p_payment_stage text, p_code_hash text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  v_amount numeric(14,2);
  v_previous public.payment_email_verifications;
begin
  if auth.role() <> 'service_role' then raise exception 'FORBIDDEN'; end if;
  if p_payment_stage not in ('down_payment', 'remaining_balance')
     or p_code_hash !~ '^[0-9a-f]{64}$' then raise exception 'INVALID_REQUEST'; end if;
  if not exists (select 1 from public.package_bookings b
                 where b.id = p_booking_id and b.tourist_id = p_tourist_id) then
    raise exception 'NOT_BOOKING_TOURIST';
  end if;
  select r.amount into v_amount from public.booking_payment_requirements r
  where r.booking_id = p_booking_id and r.payment_stage = p_payment_stage
    and r.status = 'required';
  if v_amount is null or v_amount <= 0 then raise exception 'PAYMENT_STAGE_NOT_DUE'; end if;
  if p_payment_stage = 'remaining_balance' and
     (not public.is_booking_itinerary_complete(p_booking_id) or
      not public.is_booking_downpayment_confirmed(p_booking_id)) then
    raise exception 'PAYMENT_STAGE_NOT_DUE';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_tourist_id::text || p_booking_id::text || p_payment_stage, 0));
  select * into v_previous from public.payment_email_verifications
  where tourist_id = p_tourist_id and booking_id = p_booking_id
    and payment_stage = p_payment_stage for update;
  if found and v_previous.sent_at > now() - interval '30 seconds' then
    raise exception 'RATE_LIMITED';
  end if;
  insert into public.payment_email_verifications
    (tourist_id, booking_id, payment_stage, amount, code_hash, expires_at)
  values (p_tourist_id, p_booking_id, p_payment_stage, v_amount,
          p_code_hash, now() + interval '10 minutes')
  on conflict (tourist_id, booking_id, payment_stage) do update
  set amount = excluded.amount, code_hash = excluded.code_hash,
      sent_at = now(), expires_at = excluded.expires_at, attempts = 0,
      verified_until = null, consumed_at = null;
  return 'SENT';
end;
$$;
create or replace function public.verify_payment_email_code(
  p_tourist_id uuid, p_booking_id uuid, p_payment_stage text, p_code_hash text
) returns text language plpgsql security definer set search_path = '' as $$
declare v_verification public.payment_email_verifications;
begin
  if auth.role() <> 'service_role' then raise exception 'FORBIDDEN'; end if;
  select * into v_verification from public.payment_email_verifications
  where tourist_id = p_tourist_id and booking_id = p_booking_id
    and payment_stage = p_payment_stage for update;
  if not found or v_verification.expires_at <= now() then return 'EXPIRED'; end if;
  if v_verification.attempts >= 5 then return 'RATE_LIMITED'; end if;
  if v_verification.code_hash <> p_code_hash then
    update public.payment_email_verifications set attempts = attempts + 1
    where id = v_verification.id;
    return 'INCORRECT';
  end if;
  update public.payment_email_verifications
  set verified_until = now() + interval '5 minutes', code_hash = '', attempts = 5
  where id = v_verification.id;
  return 'VERIFIED';
end;
$$;
create or replace function public.consume_payment_email_verification(
  p_tourist_id uuid, p_booking_id uuid, p_payment_stage text
) returns boolean language plpgsql security definer set search_path = '' as $$
declare v_amount numeric(14,2);
begin
  if auth.role() <> 'service_role' then raise exception 'FORBIDDEN'; end if;
  select amount into v_amount from public.booking_payment_requirements
  where booking_id = p_booking_id and payment_stage = p_payment_stage
    and status = 'required';
  if v_amount is null then return false; end if;
  update public.payment_email_verifications set consumed_at = now()
  where tourist_id = p_tourist_id and booking_id = p_booking_id
    and payment_stage = p_payment_stage and amount = v_amount
    and verified_until > now() and consumed_at is null;
  return found;
end;
$$;
revoke all on function public.request_payment_email_verification(uuid,uuid,text,text) from public, anon, authenticated;
revoke all on function public.verify_payment_email_code(uuid,uuid,text,text) from public, anon, authenticated;
revoke all on function public.consume_payment_email_verification(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.request_payment_email_verification(uuid,uuid,text,text) to service_role;
grant execute on function public.verify_payment_email_code(uuid,uuid,text,text) to service_role;
grant execute on function public.consume_payment_email_verification(uuid,uuid,text) to service_role;
-- The current registration screen records Privacy Notice 1.1. The previously
-- deployed registration RPC and trigger accepted only 1.0, rejecting new
-- Tourist profiles after OTP confirmation. Preserve historic 1.0 receipts.
create or replace function public.stamp_tourist_privacy_notice()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.role = 'tourist' and auth.uid() = new.id then
    if tg_op = 'INSERT' then
      if new.privacy_notice_version is null or
         new.privacy_notice_version not in ('1.0', '1.1') then
        raise exception 'PRIVACY_NOTICE_REQUIRED';
      end if;
      new.privacy_notice_acknowledged_at := now();
    elsif old.privacy_notice_version is null and new.privacy_notice_version is not null then
      if new.privacy_notice_version is null or
         new.privacy_notice_version not in ('1.0', '1.1') then
        raise exception 'PRIVACY_NOTICE_REQUIRED';
      end if;
      new.privacy_notice_acknowledged_at := now();
    elsif new.privacy_notice_version is distinct from old.privacy_notice_version
       or new.privacy_notice_acknowledged_at is distinct from old.privacy_notice_acknowledged_at then
      raise exception 'PRIVACY_ACKNOWLEDGMENT_IMMUTABLE';
    end if;
  elsif tg_op='UPDATE' and auth.uid() is not null
      and coalesce(auth.role(),'')<>'service_role'
      and (new.privacy_notice_version is distinct from old.privacy_notice_version
        or new.privacy_notice_acknowledged_at is distinct from old.privacy_notice_acknowledged_at) then
    raise exception 'PRIVACY_ACKNOWLEDGMENT_IMMUTABLE';
  end if;
  return new;
end;
$$;
create or replace function public.register_tourist_with_privacy_notice(p_version text)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare v_profile public.profiles;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_version is null or p_version not in ('1.0', '1.1') then
    raise exception 'PRIVACY_NOTICE_REQUIRED';
  end if;
  insert into public.profiles(id, role, privacy_notice_version)
  values (auth.uid(), 'tourist', p_version)
  on conflict (id) do update set privacy_notice_version = excluded.privacy_notice_version
    where public.profiles.role = 'tourist'
      and public.profiles.privacy_notice_version is null
  returning * into v_profile;
  if v_profile.id is null then
    select * into v_profile from public.profiles where id = auth.uid() and role = 'tourist';
  end if;
  if v_profile.id is null then raise exception 'TOURIST_ROLE_REQUIRED'; end if;
  return v_profile;
end;
$$;
