// Supabase Edge Function: paymongo-transfer-webhook
//
// Resolves a payout_records row from 'processing' to its terminal
// 'paid'/'failed' status. Reachable from TWO distinct callers, and cannot
// tell which one just by looking at the payload shape:
//
//   1. PayMongo's real callback_url (set per-transfer at creation, in
//      paymongo-disburse) — POSTs the updated transfer resource once it
//      settles. Signature scheme for callback_url payloads specifically
//      isn't confirmed in PayMongo's public docs (see the Phase B chat
//      report) — this defaults to verifying it the same way as the
//      account-level Paymongo-Signature header, using PAYMONGO_WEBHOOK_SECRET.
//      CONFIRM THIS before flipping PAYMONGO_MODE=live — if callback_url
//      payloads turn out to be signed differently (or unsigned), this
//      check needs to change.
//   2. The stub's own self-simulated delayed callback (see
//      _shared/paymongoClient.ts) — authenticated via X-Stub-Callback
//      matching INTERNAL_TRIGGER_SECRET instead, since there's no real
//      PayMongo signature to check in stub mode. Same handler either way
//      past the auth check — record_transfer_result doesn't know or care
//      which path got it there.
//
// Required secrets:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — provided automatically
//   PAYMONGO_WEBHOOK_SECRET — same one paymongo-payment-webhook uses
//   INTERNAL_TRIGGER_SECRET — same one the DB triggers use
//
// Deploy: supabase functions deploy paymongo-transfer-webhook --no-verify-jwt

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyPaymongoSignature } from "../_shared/paymongoSignature.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PAYMONGO_WEBHOOK_SECRET = Deno.env.get("PAYMONGO_WEBHOOK_SECRET") ?? "";
const INTERNAL_TRIGGER_SECRET = Deno.env.get("INTERNAL_TRIGGER_SECRET") ?? "";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const rawBody = await req.text();

  const stubHeader = req.headers.get("X-Stub-Callback");
  const isStubCallback =
    !!INTERNAL_TRIGGER_SECRET && stubHeader === INTERNAL_TRIGGER_SECRET;

  if (!isStubCallback) {
    const signatureHeader = req.headers.get("Paymongo-Signature");
    const verified = await verifyPaymongoSignature(rawBody, signatureHeader, PAYMONGO_WEBHOOK_SECRET);
    if (!verified) {
      console.warn("[paymongo-transfer-webhook] auth failed — neither stub secret nor valid signature");
      return json({ error: "Unauthorized" }, 401);
    }
  }

  let payload: {
    id?: string;
    status?: string; // "succeeded" | "failed" (stub also sends these)
    provider_reference_number?: string;
    failure_message?: string | null;
  };
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const transferId = payload.id;
  if (!transferId || !payload.status) {
    return json({ error: "Missing transfer id or status" }, 400);
  }

  const mappedStatus = payload.status === "succeeded" ? "paid" : payload.status === "failed" ? "failed" : null;
  if (!mappedStatus) {
    // "pending" or anything else — not a terminal state, nothing to record.
    return json({ ok: true, ignored: payload.status });
  }

  const { data, error } = await supabase.rpc("record_transfer_result", {
    p_paymongo_transfer_id: transferId,
    p_status: mappedStatus,
    p_provider_reference_number: payload.provider_reference_number ?? null,
    p_error_message: payload.failure_message ?? null,
  });

  if (error) {
    console.error("[paymongo-transfer-webhook] record_transfer_result failed:", error);
    return json({ error: error.message }, 500);
  }

  return json({ ok: true, payout_record_id: data?.id, status: mappedStatus });
});
