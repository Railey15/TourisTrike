import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type JsonObject = Record<string, unknown>;

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const maxBodyBytes = 1024 * 1024;
const maxClockSkewSeconds = 300;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function reply(status: number, code: string): Response {
  return Response.json({ code }, { status });
}

function isObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function verifiedDocumentType(payload: JsonObject): string | null {
  if (
    payload.status !== "Approved" || !isObject(payload.decision) ||
    payload.decision.status !== "Approved" ||
    payload.decision.session_id !== payload.session_id
  ) return null;
  const reports = payload.decision.id_verifications;
  if (
    !Array.isArray(reports) || reports.length !== 1 || !isObject(reports[0]) ||
    reports[0].status !== "Approved" ||
    (reports[0].verification_method != null &&
      reports[0].verification_method !== "document")
  ) {
    return null;
  }
  const type = reports[0].document_type;
  return type === "Driver's License" || type === "Identity Card" ||
      type === "Passport" || type === "Residence Permit"
    ? type
    : null;
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (isObject(value)) {
    return `{${
      Object.keys(value).sort().map((key) =>
        `${JSON.stringify(key)}:${canonicalJson(value[key])}`
      ).join(",")
    }}`;
  }
  return JSON.stringify(value);
}

function signatureBytes(header: string | null): Uint8Array<ArrayBuffer> | null {
  if (!header || !/^[a-f0-9]{64}$/i.test(header)) return null;
  const bytes = new Uint8Array(new ArrayBuffer(32));
  header.match(/.{2}/g)!.forEach((pair, index) => {
    bytes[index] = parseInt(pair, 16);
  });
  return bytes;
}

async function verifySignature(
  request: Request,
  rawBody: Uint8Array<ArrayBuffer>,
  payload: JsonObject,
  secret: string,
): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const v2 = signatureBytes(request.headers.get("X-Signature-V2"));
  if (
    v2 &&
    await crypto.subtle.verify(
      "HMAC",
      key,
      v2,
      encoder.encode(canonicalJson(payload)),
    )
  ) {
    return true;
  }
  // The legacy full-body signature is safe when the exact request bytes are available.
  const raw = signatureBytes(request.headers.get("X-Signature"));
  return Boolean(raw && await crypto.subtle.verify("HMAC", key, raw, rawBody));
}

export async function handleDiditWebhook(request: Request): Promise<Response> {
  if (request.method !== "POST") return reply(405, "METHOD_NOT_ALLOWED");

  const secret = Deno.env.get("DIDIT_WEBHOOK_SECRET")?.trim();
  if (!secret) {
    console.error("[Didit] Destination signing secret is not configured");
    return reply(503, "WEBHOOK_NOT_CONFIGURED");
  }

  let rawBody: Uint8Array<ArrayBuffer>;
  let payload: JsonObject;
  try {
    rawBody = new Uint8Array(await request.arrayBuffer());
    if (rawBody.length > maxBodyBytes) return reply(413, "PAYLOAD_TOO_LARGE");
    const parsed: unknown = JSON.parse(decoder.decode(rawBody));
    if (!isObject(parsed)) return reply(400, "INVALID_PAYLOAD");
    payload = parsed;
  } catch {
    return reply(400, "INVALID_JSON");
  }

  const headerTimestamp = Number(request.headers.get("X-Timestamp"));
  if (
    !Number.isSafeInteger(headerTimestamp) ||
    Math.abs(Math.floor(Date.now() / 1000) - headerTimestamp) >
      maxClockSkewSeconds ||
    payload.timestamp !== headerTimestamp
  ) {
    return reply(401, "INVALID_WEBHOOK_TIMESTAMP");
  }
  if (!(await verifySignature(request, rawBody, payload, secret))) {
    return reply(401, "INVALID_WEBHOOK_SIGNATURE");
  }

  // This receiver records KYC session status changes from the existing workflow.
  if (
    payload.webhook_type !== "status.updated" ||
    payload.session_kind === "business"
  ) {
    return reply(200, "IGNORED_EVENT");
  }
  // Didit's signed console test uses synthetic identifiers. Require both the
  // signed body marker and Didit's test header before skipping persistence.
  if (
    request.headers.get("X-Didit-Test-Webhook")?.toLowerCase() === "true" &&
    isObject(payload.metadata) && payload.metadata.test_webhook === true
  ) {
    return reply(200, "TEST_WEBHOOK_VERIFIED");
  }
  const eventId = payload.event_id;
  const sessionId = payload.session_id;
  const status = payload.status;
  const createdAt = payload.created_at;
  if (
    typeof eventId !== "string" || !uuidPattern.test(eventId) ||
    typeof sessionId !== "string" || !uuidPattern.test(sessionId) ||
    typeof status !== "string" || status.length === 0 || status.length > 80 ||
    typeof createdAt !== "number" || !Number.isSafeInteger(createdAt) ||
    createdAt <= 0
  ) {
    return reply(400, "INVALID_SESSION_EVENT");
  }

  const workflowId = payload.workflow_id;
  if (
    workflowId != null &&
    (typeof workflowId !== "string" || !uuidPattern.test(workflowId))
  ) {
    return reply(400, "INVALID_WORKFLOW_ID");
  }
  const expectedWorkflowId = Deno.env.get("DIDIT_WORKFLOW_ID")?.trim();
  if (expectedWorkflowId && workflowId !== expectedWorkflowId) {
    return reply(200, "IGNORED_WORKFLOW");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return reply(503, "DATABASE_NOT_CONFIGURED");
  }
  const db = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const eventAt = new Date(createdAt * 1000).toISOString();
  const documentType = verifiedDocumentType(payload);
  const { error } = await db.from("didit_verification_events").insert({
    event_id: eventId,
    session_id: sessionId,
    webhook_type: "status.updated",
    status,
    event_created_at: eventAt,
    verified_document_type: documentType,
    workflow_id: workflowId ?? null,
    application_id: typeof payload.application_id === "string" &&
        uuidPattern.test(payload.application_id)
      ? payload.application_id
      : null,
    environment:
      payload.environment === "live" || payload.environment === "sandbox"
        ? payload.environment
        : null,
  });
  if (error && error.code !== "23505") {
    console.error(`[Didit] Event storage failed: ${error.code}`);
    return reply(503, "EVENT_STORAGE_FAILED");
  }
  // Resolve exclusively through the session ID linked by our session creator.
  // Unknown sessions stay in the private event ledger for possible early delivery.
  const { data: applied, error: applyError } = await db.rpc(
    "apply_driver_identity_webhook_status",
    {
      p_session_id: sessionId,
      p_provider_status: status,
      p_event_at: eventAt,
    },
  );
  if (applyError) {
    console.error(
      `[Didit] Identity status application failed: ${applyError.code}`,
    );
    return reply(503, "STATUS_APPLICATION_FAILED");
  }
  if (applied === true && documentType) {
    const { error: documentError } = await db.rpc(
      "record_driver_verified_document_type",
      {
        p_session_id: sessionId,
        p_event_at: eventAt,
        p_document_type: documentType,
      },
    );
    if (documentError) {
      console.error(
        `[Didit] Document class storage failed: ${documentError.code}`,
      );
      return reply(503, "DOCUMENT_CLASS_STORAGE_FAILED");
    }
  }
  return reply(200, error ? "ALREADY_RECEIVED" : "RECEIVED");
}

if (import.meta.main) Deno.serve(handleDiditWebhook);
