import { handleDiditWebhook } from "./index.ts";

const endpoint = "https://example.test/functions/v1/didit-webhook";
const secret = "local-test-signing-secret";
const encoder = new TextEncoder();

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const object = value as Record<string, unknown>;
    return `{${
      Object.keys(object).sort().map((key) =>
        `${JSON.stringify(key)}:${canonical(object[key])}`
      ).join(",")
    }}`;
  }
  return JSON.stringify(value);
}

async function hmac(body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return Array.from(
    new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(body))),
  )
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

Deno.test("Didit rejects unsigned and stale callbacks, accepts signed V2 and raw signatures", async () => {
  Deno.env.set("DIDIT_WEBHOOK_SECRET", secret);
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    timestamp: now,
    webhook_type: "data.updated",
    status: "In Review",
    name: "José",
  };
  const raw = JSON.stringify(payload, null, 2);

  const unsigned = await handleDiditWebhook(
    new Request(endpoint, {
      method: "POST",
      body: raw,
      headers: { "X-Timestamp": String(now) },
    }),
  );
  if (unsigned.status !== 401) {
    throw new Error("Unsigned callback was accepted");
  }

  const v2 = await handleDiditWebhook(
    new Request(endpoint, {
      method: "POST",
      body: raw,
      headers: {
        "X-Timestamp": String(now),
        "X-Signature-V2": await hmac(canonical(payload)),
      },
    }),
  );
  if (v2.status !== 200) {
    throw new Error(`Valid V2 callback failed: ${v2.status}`);
  }

  const rawSigned = await handleDiditWebhook(
    new Request(endpoint, {
      method: "POST",
      body: raw,
      headers: { "X-Timestamp": String(now), "X-Signature": await hmac(raw) },
    }),
  );
  if (rawSigned.status !== 200) {
    throw new Error(`Valid raw callback failed: ${rawSigned.status}`);
  }

  const stale = await handleDiditWebhook(
    new Request(endpoint, {
      method: "POST",
      body: raw,
      headers: {
        "X-Timestamp": String(now - 301),
        "X-Signature-V2": await hmac(canonical(payload)),
      },
    }),
  );
  if (stale.status !== 401) throw new Error("Stale callback was accepted");
});

Deno.test("signed synthetic Test Webhook is accepted without writing a verification event", async () => {
  Deno.env.set("DIDIT_WEBHOOK_SECRET", secret);
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    event_id: "synthetic-event",
    session_id: "synthetic-session",
    workflow_id: "synthetic-workflow",
    webhook_type: "status.updated",
    timestamp: now,
    created_at: now,
    status: "Approved",
    vendor_data: "test-vendor-data-123",
    metadata: { test_webhook: true },
    decision: { status: "Approved" },
  };
  const body = JSON.stringify(payload);
  const request = (
    signature: string,
    testHeader: string | null,
    markedBody = body,
  ) =>
    new Request(endpoint, {
      method: "POST",
      body: markedBody,
      headers: {
        "X-Timestamp": String(now),
        "X-Signature-V2": signature,
        ...(testHeader ? { "X-Didit-Test-Webhook": testHeader } : {}),
      },
    });

  const validSignature = await hmac(canonical(payload));
  const valid = await handleDiditWebhook(request(validSignature, "true"));
  if (
    valid.status !== 200 ||
    (await valid.json()).code !== "TEST_WEBHOOK_VERIFIED"
  ) {
    throw new Error("Signed Didit test callback was not safely accepted");
  }

  const unsigned = await handleDiditWebhook(request("0".repeat(64), "true"));
  if (unsigned.status !== 401) {
    throw new Error("Test marker bypassed signature verification");
  }

  const headerOnlyPayload = { ...payload, metadata: {} };
  const headerOnlyBody = JSON.stringify(headerOnlyPayload);
  const headerOnly = await handleDiditWebhook(request(
    await hmac(canonical(headerOnlyPayload)),
    "true",
    headerOnlyBody,
  ));
  if (headerOnly.status !== 400) {
    throw new Error("Unsigned test marker bypassed event validation");
  }

  const bodyOnly = await handleDiditWebhook(request(validSignature, null));
  if (bodyOnly.status !== 400) {
    throw new Error("Body marker alone bypassed event validation");
  }
});

Deno.test("real signed events resolve by session ID, including unknown and duplicate deliveries", async () => {
  const previousFetch = globalThis.fetch;
  const previousUrl = Deno.env.get("SUPABASE_URL");
  const previousKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  Deno.env.set("DIDIT_WEBHOOK_SECRET", secret);
  Deno.env.set("SUPABASE_URL", "https://example.test");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-key");
  const now = Math.floor(Date.now() / 1000);
  let duplicate = false;
  let linked = false;
  let applied = 0;
  let inserted = 0;
  let savedDocumentType: string | null = null;
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    const path = new URL(request.url).pathname;
    if (path === "/rest/v1/didit_verification_events") {
      const body = await request.json();
      if (
        body.session_id !== "33333333-3333-4333-8333-333333333333" ||
        "vendor_data" in body || "decision" in body || "document_number" in body
      ) {
        throw new Error("Event was not minimized to the provider session ID");
      }
      savedDocumentType = body.verified_document_type;
      inserted++;
      return duplicate
        ? Response.json({ code: "23505", message: "duplicate" }, {
          status: 409,
        })
        : new Response(null, { status: 201 });
    }
    if (path === "/rest/v1/rpc/apply_driver_identity_webhook_status") {
      const body = await request.json();
      if (
        body.p_session_id !== "33333333-3333-4333-8333-333333333333" ||
        body.p_provider_status !== "Approved" || "p_driver_id" in body
      ) {
        throw new Error("Webhook trusted unlinked payload data");
      }
      applied++;
      return Response.json(linked); // Unknown session: private ledger only.
    }
    if (path === "/rest/v1/rpc/record_driver_verified_document_type") {
      const body = await request.json();
      if (
        !linked || body.p_document_type !== "Driver's License" ||
        body.p_session_id !== "33333333-3333-4333-8333-333333333333" ||
        "document_number" in body
      ) {
        throw new Error("Untrusted or sensitive document data was stored");
      }
      return Response.json(true);
    }
    throw new Error(`Unexpected request: ${request.url}`);
  };
  try {
    const payload = {
      event_id: "22222222-2222-4222-8222-222222222222",
      session_id: "33333333-3333-4333-8333-333333333333",
      workflow_id: "44444444-4444-4444-8444-444444444444",
      webhook_type: "status.updated",
      timestamp: now,
      created_at: now,
      status: "Approved",
      vendor_data: "untrusted-driver-reference",
    };
    const request = () =>
      new Request(endpoint, {
        method: "POST",
        body: JSON.stringify(payload),
        headers: { "X-Timestamp": String(now), "X-Signature-V2": "" },
      });
    const signature = await hmac(canonical(payload));
    const send = () => {
      const req = request();
      req.headers.set("X-Signature-V2", signature);
      return handleDiditWebhook(req);
    };
    const first = await send();
    if (first.status !== 200 || (await first.json()).code !== "RECEIVED") {
      throw new Error("Signed unknown session was rejected");
    }
    duplicate = true;
    const second = await send();
    if (
      second.status !== 200 ||
      (await second.json()).code !== "ALREADY_RECEIVED" ||
      inserted !== 2 || applied !== 2
    ) {
      throw new Error("Duplicate event was not handled idempotently");
    }
    linked = true;
    duplicate = false;
    const approvedWithDocument = {
      ...payload,
      event_id: "66666666-6666-4666-8666-666666666666",
      decision: {
        status: "Approved",
        session_id: payload.session_id,
        id_verifications: [{
          status: "Approved",
          verification_method: "document",
          document_type: "Driver's License",
          document_number: "PRIVATE-NUMBER",
          portrait_image: "https://private.example/image",
        }],
      },
    };
    const recognized = await handleDiditWebhook(
      new Request(endpoint, {
        method: "POST",
        body: JSON.stringify(approvedWithDocument),
        headers: {
          "X-Timestamp": String(now),
          "X-Signature-V2": await hmac(canonical(approvedWithDocument)),
        },
      }),
    );
    if (recognized.status !== 200 || savedDocumentType !== "Driver's License") {
      throw new Error("Approved document class was not safely normalized");
    }
    const ambiguous = {
      ...approvedWithDocument,
      event_id: "77777777-7777-4777-8777-777777777777",
      decision: {
        ...approvedWithDocument.decision,
        id_verifications: [
          ...approvedWithDocument.decision.id_verifications,
          { status: "Approved", document_type: "Passport" },
        ],
      },
    };
    const ignoredType = await handleDiditWebhook(
      new Request(endpoint, {
        method: "POST",
        body: JSON.stringify(ambiguous),
        headers: {
          "X-Timestamp": String(now),
          "X-Signature-V2": await hmac(canonical(ambiguous)),
        },
      }),
    );
    if (ignoredType.status !== 200 || savedDocumentType !== null) {
      throw new Error("Ambiguous ID type was treated as verified");
    }
  } finally {
    globalThis.fetch = previousFetch;
    if (previousUrl === undefined) Deno.env.delete("SUPABASE_URL");
    else Deno.env.set("SUPABASE_URL", previousUrl);
    if (previousKey === undefined) Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
    else Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", previousKey);
  }
});
