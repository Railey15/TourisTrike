import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>): Response {
  return Response.json(body, { status, headers: cors });
}

function launchData(row: Record<string, unknown>): Record<string, unknown> {
  const status = String(row.status ?? row.internal_status ?? "creating");
  return {
    status,
    ...(status === "not_started" || status === "in_progress"
      ? { url: row.session_url ?? row.hosted_url ?? null }
      : {}),
  };
}

function diditErrorDiagnostic(
  body: unknown,
  secrets: string[],
): { code: string; message: string } {
  const safe = (value: unknown): string => {
    if (typeof value !== "string") return "unavailable";
    let result = value;
    for (const secret of secrets) {
      if (secret) result = result.replaceAll(secret, "[redacted]");
    }
    return result
      .replace(/https?:\/\/\S+/gi, "[url]")
      .replace(/\b[^\s@]+@[^\s@]+\.[^\s@]+\b/g, "[email]")
      .replace(/\b[0-9a-f]{8}-[0-9a-f-]{27,}\b/gi, "[id]")
      .replace(/\b[A-Za-z0-9_-]{20,}\b/g, "[token]")
      .replace(/[^\w\s.,:;()\[\]/-]/g, " ")
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 160) || "unavailable";
  };
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { code: "unavailable", message: "unavailable" };
  }
  const error = body as Record<string, unknown>;
  const code = error.code ?? error.error_code ?? error.error;
  let message = error.message ?? error.detail;
  if (
    message === undefined && error.errors && typeof error.errors === "object" &&
    !Array.isArray(error.errors)
  ) {
    const [field, detail] = Object.entries(error.errors)[0] ?? [];
    message = typeof detail === "string"
      ? `${field}: ${detail}`
      : Array.isArray(detail) && typeof detail[0] === "string"
      ? `${field}: ${detail[0]}`
      : field;
  }
  return { code: safe(code), message: safe(message) };
}

export async function handleDiditCreateVerification(
  request: Request,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (request.method !== "POST") {
    return json(405, { code: "METHOD_NOT_ALLOWED" });
  }
  const bearer = request.headers.get("Authorization")?.match(/^Bearer\s+(.+)$/i)
    ?.[1];
  if (!bearer) return json(401, { code: "AUTH_REQUIRED" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json(503, { code: "BACKEND_NOT_CONFIGURED" });
  }
  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${bearer}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await caller.auth.getUser(
    bearer,
  );
  if (authError || !authData.user) return json(401, { code: "AUTH_REQUIRED" });

  const apiKey = Deno.env.get("DIDIT_API_KEY")?.trim();
  const workflowId = Deno.env.get("DIDIT_WORKFLOW_ID")?.trim();
  if (!apiKey || !workflowId || !uuid.test(workflowId)) {
    return json(503, { code: "DIDIT_NOT_CONFIGURED" });
  }

  // No client-supplied driver_id is used. The RPC reserves an attempt using auth.uid().
  const { data: reservations, error: reserveError } = await caller.rpc(
    "reserve_driver_identity_verification",
  );
  if (reserveError) {
    return json(reserveError.code === "42501" ? 403 : 503, {
      code: reserveError.code === "42501"
        ? "DRIVER_NOT_ELIGIBLE"
        : "RESERVATION_FAILED",
    });
  }
  const reservation = reservations?.[0] as Record<string, unknown> | undefined;
  const attemptId = reservation?.attempt_id;
  if (!reservation || typeof attemptId !== "string" || !uuid.test(attemptId)) {
    return json(503, { code: "RESERVATION_FAILED" });
  }
  if (
    reservation.provider_session_id ||
    reservation.internal_status !== "creating"
  ) {
    return json(200, launchData(reservation));
  }

  // Didit reuses an unfinished session for the same workflow and vendor_data.
  // The opaque reservation UUID keeps retries and concurrent taps idempotent.
  let provider: Record<string, unknown>;
  try {
    const response = await fetch("https://verification.didit.me/v3/session/", {
      method: "POST",
      headers: { "x-api-key": apiKey, "Content-Type": "application/json" },
      body: JSON.stringify({ workflow_id: workflowId, vendor_data: attemptId }),
      signal: AbortSignal.timeout(10000),
    });
    if (response.status !== 201) {
      let diagnostic = { code: "unavailable", message: "unavailable" };
      try {
        diagnostic = diditErrorDiagnostic(await response.json(), [
          apiKey,
          workflowId,
          attemptId,
        ]);
      } catch {
        // A non-JSON provider error must not be logged verbatim.
      }
      console.error(
        `[Didit] Session creation failed: HTTP ${response.status}; ` +
          `code=${diagnostic.code}; message=${diagnostic.message}`,
      );
      return json(502, { code: "DIDIT_SESSION_FAILED" });
    }
    const body: unknown = await response.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json(502, { code: "DIDIT_RESPONSE_INVALID" });
    }
    provider = body as Record<string, unknown>;
  } catch {
    return json(502, { code: "DIDIT_SESSION_UNAVAILABLE" });
  }
  const sessionId = provider.session_id;
  const url = provider.url;
  let safeUrl: URL;
  try {
    safeUrl = new URL(String(url));
  } catch {
    return json(502, { code: "DIDIT_RESPONSE_INVALID" });
  }
  if (
    typeof sessionId !== "string" || !uuid.test(sessionId) ||
    safeUrl.protocol !== "https:" || !safeUrl.hostname.endsWith(".didit.me") ||
    (provider.workflow_id && provider.workflow_id !== workflowId) ||
    provider.session_kind === "business"
  ) {
    return json(502, { code: "DIDIT_RESPONSE_INVALID" });
  }

  const db = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: finalized, error: finalizeError } = await db.rpc(
    "finalize_driver_identity_verification",
    {
      p_attempt_id: attemptId,
      p_session_id: sessionId,
      p_workflow_id: workflowId,
      p_url: safeUrl.toString(),
    },
  );
  if (finalizeError || finalized !== true) {
    console.error(
      `[Didit] Session linking failed: ${finalizeError?.code ?? "conflict"}`,
    );
    return json(503, { code: "SESSION_LINK_FAILED" });
  }

  // A webhook may have arrived between provider creation and persistence.
  const { data: earlyEvents, error: replayError } = await db
    .from("didit_verification_events")
    .select("status,event_created_at,verified_document_type")
    .eq("session_id", sessionId)
    .order("event_created_at", { ascending: false })
    .limit(20);
  if (replayError) return json(503, { code: "SESSION_RECONCILIATION_FAILED" });
  for (const event of earlyEvents ?? []) {
    const { data: applied, error } = await db.rpc(
      "apply_driver_identity_webhook_status",
      {
        p_session_id: sessionId,
        p_provider_status: event.status,
        p_event_at: event.event_created_at,
      },
    );
    if (error) return json(503, { code: "SESSION_RECONCILIATION_FAILED" });
    if (applied === true && typeof event.verified_document_type === "string") {
      const { error: documentError } = await db.rpc(
        "record_driver_verified_document_type",
        {
          p_session_id: sessionId,
          p_event_at: event.event_created_at,
          p_document_type: event.verified_document_type,
        },
      );
      if (documentError) {
        return json(503, { code: "SESSION_RECONCILIATION_FAILED" });
      }
    }
  }

  const { data: linked, error: readError } = await db
    .from("driver_identity_verifications")
    .select("status,session_url")
    .eq("id", attemptId)
    .single();
  if (readError || !linked) return json(503, { code: "SESSION_LINK_FAILED" });
  return json(200, launchData(linked));
}

if (import.meta.main) Deno.serve(handleDiditCreateVerification);
