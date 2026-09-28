import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

type SuspendRequest = {
  action: 'suspend';
  account_id: string;
  reason: string;
  notes?: string;
  is_permanent: boolean;
  suspended_until?: string | null;
};

type ReactivateRequest = {
  action: 'reactivate';
  account_id: string;
};

type AccountAccessRequest = SuspendRequest | ReactivateRequest;

class RequestError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

function requiredUuid(value: unknown, field: string): string {
  if (
    typeof value !== 'string' ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
  ) {
    throw new RequestError('INVALID_REQUEST', 400, `${field} must be a valid UUID.`);
  }
  return value;
}

function parseBody(value: unknown): AccountAccessRequest {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new RequestError('INVALID_REQUEST', 400, 'A JSON request body is required.');
  }

  const body = value as Record<string, unknown>;
  const accountId = requiredUuid(body.account_id, 'account_id');
  if (body.action === 'reactivate') {
    return { action: 'reactivate', account_id: accountId };
  }
  if (body.action !== 'suspend') {
    throw new RequestError('INVALID_ACTION', 400, 'Unsupported account action.');
  }
  if (typeof body.reason !== 'string' || body.reason.length > 64) {
    throw new RequestError('INVALID_REQUEST', 400, 'A valid suspension reason is required.');
  }
  if (typeof body.is_permanent !== 'boolean') {
    throw new RequestError('INVALID_REQUEST', 400, 'is_permanent must be a boolean.');
  }
  if (body.notes != null && (typeof body.notes !== 'string' || body.notes.length > 500)) {
    throw new RequestError('INVALID_REQUEST', 400, 'Suspension notes are invalid.');
  }
  if (
    body.suspended_until != null &&
    (typeof body.suspended_until !== 'string' || Number.isNaN(Date.parse(body.suspended_until)))
  ) {
    throw new RequestError('INVALID_REQUEST', 400, 'suspended_until is invalid.');
  }

  return {
    action: 'suspend',
    account_id: accountId,
    reason: body.reason,
    notes: typeof body.notes === 'string' ? body.notes : '',
    is_permanent: body.is_permanent,
    suspended_until: typeof body.suspended_until === 'string' ? body.suspended_until : null,
  };
}

function databaseMessage(error: { message?: string; details?: string } | null): string {
  const raw = error?.message?.trim() || error?.details?.trim() || 'Account access update failed.';
  const known: Record<string, string> = {
    SYSTEM_ADMINISTRATOR_REQUIRED: 'System Administrator access is required.',
    SELF_SUSPENSION_NOT_ALLOWED: 'You cannot suspend your own account.',
    LAST_USABLE_ADMINISTRATOR: 'The last usable System Administrator cannot be suspended.',
    TARGET_ACCOUNT_NOT_FOUND: 'The target account was not found.',
    ACCOUNT_ALREADY_SUSPENDED: 'This account is already suspended.',
    ACCOUNT_NOT_SUSPENDED: 'This account is not currently suspended.',
    INVALID_SUSPENSION_REASON: 'The suspension reason is invalid.',
    CUSTOM_SUSPENSION_REASON_REQUIRED: 'Enter the custom suspension reason.',
    INVALID_SUSPENSION_END: 'The suspension duration is invalid.',
  };
  for (const [code, message] of Object.entries(known)) {
    if (raw.includes(code)) return message;
  }
  return raw;
}

function banDuration(request: SuspendRequest): string {
  if (request.is_permanent) return '876000h';
  const end = Date.parse(request.suspended_until ?? '');
  const seconds = Math.ceil((end - Date.now()) / 1000);
  if (!Number.isFinite(seconds) || seconds <= 0) {
    throw new RequestError('INVALID_SUSPENSION_END', 400, 'The suspension duration is invalid.');
  }
  return `${seconds}s`;
}

function restoreBanDuration(permanent: boolean, suspendedUntil: string | null): string {
  if (permanent) return '876000h';
  const seconds = Math.max(1, Math.ceil((Date.parse(suspendedUntil ?? '') - Date.now()) / 1000));
  return `${seconds}s`;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405);

  let pendingId = '';
  let action: 'suspend' | 'reactivate' | '' = '';
  try {
    const authorization = request.headers.get('Authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) {
      throw new RequestError('UNAUTHENTICATED', 401, 'An authenticated session is required.');
    }

    const accessToken = authorization.slice('Bearer '.length).trim();
    const caller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authorization } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const service = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: userData, error: userError } = await caller.auth.getUser(accessToken);
    if (userError || !userData.user) {
      throw new RequestError('UNAUTHENTICATED', 401, 'The session is invalid or expired.');
    }

    const body = parseBody(await request.json().catch(() => null));
    action = body.action;

    if (body.action === 'suspend') {
      const { data: beginData, error: beginError } = await caller.rpc(
        'administrator_begin_account_suspension',
        {
          p_account_id: body.account_id,
          p_reason: body.reason,
          p_notes: body.notes ?? '',
          p_suspended_until: body.suspended_until ?? null,
          p_is_permanent: body.is_permanent,
        },
      );
      if (beginError || typeof beginData !== 'string') {
        throw new RequestError('SUSPENSION_REJECTED', 403, databaseMessage(beginError));
      }
      pendingId = beginData;

      const { error: authError } = await service.auth.admin.updateUserById(
        body.account_id,
        { ban_duration: banDuration(body) },
      );
      if (authError) {
        await service.rpc('administrator_cancel_account_suspension', {
          p_suspension_id: pendingId,
        });
        pendingId = '';
        throw new RequestError('AUTH_BAN_FAILED', 502, 'Supabase Auth could not suspend the account.');
      }

      const { error: finalizeError } = await caller.rpc(
        'administrator_finalize_account_suspension',
        { p_suspension_id: pendingId },
      );
      if (finalizeError) {
        await service.auth.admin.updateUserById(body.account_id, { ban_duration: 'none' });
        await service.rpc('administrator_cancel_account_suspension', {
          p_suspension_id: pendingId,
        });
        pendingId = '';
        throw new RequestError('SUSPENSION_FINALIZATION_FAILED', 500, databaseMessage(finalizeError));
      }

      return json({ ok: true, action: body.action, account_id: body.account_id });
    }

    const { data: beginRows, error: beginError } = await caller.rpc(
      'administrator_begin_account_reactivation',
      { p_account_id: body.account_id },
    );
    const pending = Array.isArray(beginRows) ? beginRows[0] : null;
    if (beginError || !pending || typeof pending.suspension_id !== 'string') {
      throw new RequestError('REACTIVATION_REJECTED', 403, databaseMessage(beginError));
    }
    pendingId = pending.suspension_id;

    const { error: authError } = await service.auth.admin.updateUserById(
      body.account_id,
      { ban_duration: 'none' },
    );
    if (authError) {
      await service.rpc('administrator_cancel_account_reactivation', {
        p_suspension_id: pendingId,
      });
      pendingId = '';
      throw new RequestError('AUTH_REACTIVATION_FAILED', 502, 'Supabase Auth could not reactivate the account.');
    }

    const { error: finalizeError } = await caller.rpc(
      'administrator_finalize_account_reactivation',
      { p_suspension_id: pendingId },
    );
    if (finalizeError) {
      await service.auth.admin.updateUserById(body.account_id, {
        ban_duration: restoreBanDuration(
          pending.is_permanent === true,
          typeof pending.suspended_until === 'string' ? pending.suspended_until : null,
        ),
      });
      await service.rpc('administrator_cancel_account_reactivation', {
        p_suspension_id: pendingId,
      });
      pendingId = '';
      throw new RequestError('REACTIVATION_FINALIZATION_FAILED', 500, databaseMessage(finalizeError));
    }

    return json({ ok: true, action: body.action, account_id: body.account_id });
  } catch (error) {
    if (pendingId) {
      console.error(JSON.stringify({ event: 'administrator_account_access_incomplete', action }));
    }
    if (error instanceof RequestError) {
      return json({ error: error.code, message: error.message }, error.status);
    }
    console.error(JSON.stringify({ event: 'administrator_account_access_failed', action }));
    return json({ error: 'ACCOUNT_ACCESS_UPDATE_FAILED', message: 'Account access update failed.' }, 500);
  }
});
