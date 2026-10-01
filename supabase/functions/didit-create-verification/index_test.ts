import { handleDiditCreateVerification } from "./index.ts";

const endpoint = "https://example.test/functions/v1/didit-create-verification";
const driverId = "11111111-1111-4111-8111-111111111111";
const attemptId = "22222222-2222-4222-8222-222222222222";
const sessionId = "33333333-3333-4333-8333-333333333333";
const workflowId = "44444444-4444-4444-8444-444444444444";
const url = `https://verify.didit.me/session/${sessionId}`;

Deno.test("session creator authenticates, reserves own attempt, persists before launch, and reuses active session", async () => {
  const previousFetch = globalThis.fetch;
  const previous = Object.fromEntries(
    [
      "SUPABASE_URL",
      "SUPABASE_ANON_KEY",
      "SUPABASE_SERVICE_ROLE_KEY",
      "DIDIT_API_KEY",
      "DIDIT_WORKFLOW_ID",
    ]
      .map((key) => [key, Deno.env.get(key)]),
  );
  Deno.env.set("SUPABASE_URL", "https://example.test");
  Deno.env.set("SUPABASE_ANON_KEY", "test-anon-key");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-key");
  Deno.env.set("DIDIT_API_KEY", "test-private-api-key");
  Deno.env.set("DIDIT_WORKFLOW_ID", workflowId);
  let role: "driver" | "tourist" = "driver";
  let existing = false;
  let existingStatus = "not_started";
  let linked = false;
  let earlyEvent = false;
  let savedDocumentType = false;
  let providerCalls = 0;
  let reserveCalls = 0;
  let providerFailure = false;
  const ok = (body: unknown, status = 200) => Response.json(body, { status });
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    const path = new URL(request.url).pathname;
    if (path === "/auth/v1/user") {
      return ok({
        id: driverId,
        aud: "authenticated",
        app_metadata: {},
        user_metadata: {},
        created_at: "2026-09-30T00:00:00Z",
      });
    }
    if (path === "/rest/v1/rpc/reserve_driver_identity_verification") {
      reserveCalls++;
      if (role === "tourist") {
        return ok({ code: "42501", message: "DRIVER_REQUIRED" }, 403);
      }
      return ok([{
        attempt_id: attemptId,
        internal_status: existing ? existingStatus : "creating",
        hosted_url: existing ? url : null,
        provider_session_id: existing ? sessionId : null,
      }]);
    }
    if (request.url === "https://verification.didit.me/v3/session/") {
      providerCalls++;
      const body = await request.json();
      if (
        body.vendor_data !== attemptId || body.workflow_id !== workflowId ||
        Object.keys(body).length !== 2 ||
        request.headers.get("x-api-key") !== "test-private-api-key"
      ) {
        throw new Error("Provider request contained wrong data");
      }
      if (providerFailure) {
        return ok({
          code: "invalid_workflow",
          errors: {
            workflow_id: [
              `No published version for ${workflowId}; key test-private-api-key; ` +
              `reference ${attemptId}; https://verify.didit.me/session/private`,
            ],
          },
        }, 400);
      }
      return ok({
        session_id: sessionId,
        workflow_id: workflowId,
        url,
        status: "Not Started",
      }, 201);
    }
    if (path === "/rest/v1/rpc/finalize_driver_identity_verification") {
      const body = await request.json();
      if (body.p_attempt_id !== attemptId || body.p_session_id !== sessionId) {
        throw new Error("Incorrect server-side session link");
      }
      linked = true;
      return ok(true);
    }
    if (path === "/rest/v1/didit_verification_events") {
      return ok(
        earlyEvent
          ? [{
            status: "Approved",
            event_created_at: "2026-10-01T00:00:00Z",
            verified_document_type: "Passport",
          }]
          : [],
      );
    }
    if (path === "/rest/v1/rpc/apply_driver_identity_webhook_status") {
      return ok(true);
    }
    if (path === "/rest/v1/rpc/record_driver_verified_document_type") {
      const body = await request.json();
      if (
        body.p_document_type !== "Passport" || body.p_session_id !== sessionId
      ) {
        throw new Error(
          "Early event document type was not limited to the linked session",
        );
      }
      savedDocumentType = true;
      return ok(true);
    }
    if (path === "/rest/v1/driver_identity_verifications") {
      if (!linked) throw new Error("URL read before session persisted");
      return ok({
        status: earlyEvent ? "approved" : "not_started",
        session_url: url,
      });
    }
    throw new Error(`Unexpected request: ${request.url}`);
  };
  try {
    const unauthenticated = await handleDiditCreateVerification(
      new Request(endpoint, { method: "POST" }),
    );
    if (unauthenticated.status !== 401) {
      throw new Error("Unauthenticated call passed");
    }
    role = "tourist";
    const tourist = await handleDiditCreateVerification(
      new Request(endpoint, {
        method: "POST",
        headers: { Authorization: "Bearer test-jwt" },
      }),
    );
    if (tourist.status !== 403 || providerCalls !== 0) {
      throw new Error("Tourist initiated session");
    }
    role = "driver";
    const response = await handleDiditCreateVerification(
      new Request(endpoint, {
        method: "POST",
        headers: { Authorization: "Bearer test-jwt" },
        body: JSON.stringify({
          driver_id: "55555555-5555-4555-8555-555555555555",
        }),
      }),
    );
    const body = await response.json();
    if (
      response.status !== 200 || !linked || body.url !== url ||
      Number(providerCalls) !== 1 ||
      JSON.stringify(body).includes("test-private-api-key")
    ) {
      throw new Error(
        `Driver session creation failed: ${response.status} ${
          JSON.stringify(body)
        }`,
      );
    }
    existing = true;
    const retry = await handleDiditCreateVerification(
      new Request(endpoint, {
        method: "POST",
        headers: { Authorization: "Bearer test-jwt" },
      }),
    );
    if (
      retry.status !== 200 || Number(providerCalls) !== 1 || reserveCalls !== 3
    ) {
      throw new Error("Existing active session was not reused");
    }
    existingStatus = "approved";
    const approved = await handleDiditCreateVerification(
      new Request(endpoint, {
        method: "POST",
        headers: { Authorization: "Bearer test-jwt" },
      }),
    );
    const approvedBody = await approved.json();
    if (
      approved.status !== 200 || approvedBody.status !== "approved" ||
      "url" in approvedBody || Number(providerCalls) !== 1
    ) {
      throw new Error("Approved Driver started another session");
    }
    existing = false;
    linked = false;
    providerFailure = true;
    const previousConsoleError = console.error;
    const logs: string[] = [];
    console.error = (...args: unknown[]) => logs.push(args.join(" "));
    let rejected: Response;
    try {
      rejected = await handleDiditCreateVerification(
        new Request(endpoint, {
          method: "POST",
          headers: { Authorization: "Bearer test-jwt" },
        }),
      );
    } finally {
      console.error = previousConsoleError;
    }
    const rejectedBody = await rejected.json();
    if (
      rejected.status !== 502 || rejectedBody.code !== "DIDIT_SESSION_FAILED" ||
      !logs[0]?.includes("code=invalid_workflow") ||
      !logs[0]?.includes("No published version") || linked ||
      logs.some((line) =>
        [
          workflowId,
          attemptId,
          "test-private-api-key",
          "https://verify.didit.me",
        ].some(
          (secret) => line.includes(secret),
        )
      )
    ) {
      throw new Error("Provider rejection was not safely diagnosed");
    }
    providerFailure = false;
    earlyEvent = true;
    const replay = await handleDiditCreateVerification(
      new Request(endpoint, {
        method: "POST",
        headers: { Authorization: "Bearer test-jwt" },
      }),
    );
    if (
      replay.status !== 200 || !savedDocumentType ||
      (await replay.json()).status !== "approved"
    ) {
      throw new Error(
        "Approved early event did not retain its minimal document type",
      );
    }
  } finally {
    globalThis.fetch = previousFetch;
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
});
