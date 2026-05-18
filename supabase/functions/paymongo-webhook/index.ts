// Supabase Edge Function: paymongo-webhook
// Handles PayMongo payment events for wallet cash-ins.
// Deploy with: supabase functions deploy paymongo-webhook --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const WEBHOOK_SECRET = Deno.env.get("PAYMONGO_WEBHOOK_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

type JsonRecord = Record<string, unknown>;

const isRecord = (value: unknown): value is JsonRecord =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);

const asRecord = (value: unknown): JsonRecord =>
  isRecord(value) ? value : {};

const asArray = (value: unknown): unknown[] => Array.isArray(value) ? value : [];

const asString = (value: unknown): string =>
  typeof value === "string" ? value.trim() : "";

const asNumber = (value: unknown): number | null => {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
};

async function verifySignature(
  rawBody: string,
  signatureHeader: string | null,
): Promise<boolean> {
  if (!WEBHOOK_SECRET || !signatureHeader) {
    return true;
  }

  const entries = signatureHeader.split(",").map((part) => part.trim());
  const pairs = new Map<string, string>();
  for (const entry of entries) {
    const [key, ...rest] = entry.split("=");
    if (!key || rest.length === 0) continue;
    pairs.set(key, rest.join("="));
  }

  const timestamp = pairs.get("t");
  const testSignature = pairs.get("te");
  const liveSignature = pairs.get("li");

  if (!timestamp || (!testSignature && !liveSignature)) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(WEBHOOK_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const payload = new TextEncoder().encode(`${timestamp}.${rawBody}`);
  const signatureBuffer = await crypto.subtle.sign("HMAC", key, payload);
  const computedSignature = Array.from(new Uint8Array(signatureBuffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

  return [testSignature, liveSignature].some((c) => c === computedSignature);
}

async function findWalletTransaction(
  supabase: ReturnType<typeof createClient>,
  transactionId: string,
  checkoutSessionId: string,
  paymentId: string,
) {
  if (transactionId) {
    console.log(`[webhook] Looking up transaction by id: ${transactionId}`);
    const { data } = await supabase
      .from("wallet_transactions")
      .select("*")
      .eq("id", transactionId)
      .maybeSingle();
    if (data) return data;
  }

  if (checkoutSessionId) {
    console.log(`[webhook] Looking up transaction by checkout_session_id: ${checkoutSessionId}`);
    const { data } = await supabase
      .from("wallet_transactions")
      .select("*")
      .eq("paymongo_reference_id", checkoutSessionId)
      .maybeSingle();
    if (data) return data;
  }

  if (paymentId) {
    console.log(`[webhook] Looking up transaction by payment_id in metadata: ${paymentId}`);
    const { data } = await supabase
      .from("wallet_transactions")
      .select("*")
      .contains("metadata", { payment_id: paymentId })
      .maybeSingle();
    if (data) return data;
  }

  return null;
}

async function processSettlement(
  supabase: ReturnType<typeof createClient>,
  opts: {
    eventId: string;
    eventType: string;
    transactionId: string;
    checkoutSessionId: string;
    paymentId: string;
    paymentAttributes: JsonRecord;
    extraMetadata: JsonRecord;
  },
): Promise<Response> {
  const {
    eventId,
    eventType,
    transactionId,
    checkoutSessionId,
    paymentId,
    paymentAttributes,
    extraMetadata,
  } = opts;

  const tx = await findWalletTransaction(
    supabase,
    transactionId,
    checkoutSessionId,
    paymentId,
  );

  if (!tx) {
    console.error("[webhook] Could not match wallet transaction", {
      eventId,
      eventType,
      transactionId,
      checkoutSessionId,
      paymentId,
    });
    return ok({ received: true, skipped: "transaction not found" });
  }

  console.log(`[webhook] Matched transaction: ${tx.id} status=${tx.status}`);

  const paidAmountCentavos = asNumber(paymentAttributes.amount);
  const paidAmount = paidAmountCentavos == null
    ? null
    : Number((paidAmountCentavos / 100).toFixed(2));

  const webhookMetadata: JsonRecord = {
    webhook_event_id: eventId,
    webhook_event_type: eventType,
    webhook_received_at: new Date().toISOString(),
    checkout_session_id: checkoutSessionId || null,
    payment_id: paymentId || null,
    payment_status: asString(paymentAttributes.status),
    paid_at: paymentAttributes.paid_at ?? null,
    ...extraMetadata,
  };

  const { data: completionData, error: completionError } = await supabase.rpc(
    "complete_wallet_cash_in",
    {
      p_transaction_id: tx.id,
      p_paymongo_reference_id: checkoutSessionId || paymentId || null,
      p_metadata: webhookMetadata,
      p_paid_amount: paidAmount,
      p_final_status: "paid",
    },
  );

  if (completionError) {
    console.error("[webhook] complete_wallet_cash_in failed", {
      error: completionError.message,
      transactionId: tx.id,
      eventId,
    });
    return new Response(
      JSON.stringify({ error: "Failed to complete wallet cash-in" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const completion = Array.isArray(completionData)
    ? asRecord(completionData[0])
    : asRecord(completionData);
  const applied = completion.applied === true;

  console.log(`[webhook] complete_wallet_cash_in applied=${applied} for tx=${tx.id}`);

  if (applied) {
    const txAmount = asNumber(completion.amount) ?? asNumber(tx.amount) ?? 0;
    await supabase.from("notifications").insert({
      user_id: tx.user_id,
      title: "TourisTrike Cash In Successful",
      body: `PHP ${txAmount.toLocaleString("en-PH", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })} has been added to your wallet.`,
      type: "wallet_cash_in",
      is_read: false,
    });
  }

  return ok({ received: true, event_type: eventType, transaction_id: tx.id, applied });
}

function ok(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const rawBody = await req.text();
  const signatureHeader = req.headers.get("Paymongo-Signature");
  const valid = await verifySignature(rawBody, signatureHeader);

  if (!valid) {
    console.error("[webhook] Invalid signature");
    return new Response(JSON.stringify({ error: "Invalid signature" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let eventBody: JsonRecord;
  try {
    eventBody = asRecord(JSON.parse(rawBody));
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const eventData = asRecord(eventBody.data);
  const eventId = asString(eventData.id);
  const eventAttributes = asRecord(eventData.attributes);
  const eventType = asString(eventAttributes.type);

  console.log(`[webhook] Received event: ${eventType} (id=${eventId})`);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // ── checkout_session.payment.paid ────────────────────────────────────────
  if (eventType === "checkout_session.payment.paid") {
    const checkoutSession = asRecord(eventAttributes.data);
    const checkoutSessionId = asString(checkoutSession.id);
    const checkoutAttributes = asRecord(checkoutSession.attributes);
    const checkoutMetadata = asRecord(checkoutAttributes.metadata);

    const payments = asArray(checkoutAttributes.payments);
    const firstPayment = payments.find(isRecord);
    const payment = asRecord(firstPayment);
    const paymentId = asString(payment.id);
    const paymentAttributes = asRecord(payment.attributes);
    const paymentMetadata = asRecord(paymentAttributes.metadata);

    const transactionId =
      asString(checkoutMetadata.transaction_id) ||
      asString(paymentMetadata.transaction_id);

    console.log(
      `[webhook] checkout_session.payment.paid — session=${checkoutSessionId} tx=${transactionId} payment=${paymentId}`,
    );

    if (!transactionId && !checkoutSessionId) {
      console.error("[webhook] Missing identifiers in checkout_session.payment.paid", { eventId });
      return ok({ received: true, skipped: "missing identifiers" });
    }

    return processSettlement(supabase, {
      eventId,
      eventType,
      transactionId,
      checkoutSessionId,
      paymentId,
      paymentAttributes,
      extraMetadata: {
        paymongo_metadata: {
          checkout_session: checkoutMetadata,
          payment: paymentMetadata,
        },
      },
    });
  }

  // ── payment.paid ─────────────────────────────────────────────────────────
  if (eventType === "payment.paid") {
    const paymentObj = asRecord(eventAttributes.data);
    const paymentId = asString(paymentObj.id);
    const paymentAttributes = asRecord(paymentObj.attributes);
    const paymentMetadata = asRecord(paymentAttributes.metadata);

    // PayMongo may include checkout_session_id on the payment attributes.
    const checkoutSessionId =
      asString(paymentAttributes.checkout_session_id) ||
      asString(paymentMetadata.checkout_session_id);

    const transactionId =
      asString(paymentMetadata.transaction_id) ||
      asString(paymentAttributes.external_reference_number);

    console.log(
      `[webhook] payment.paid — payment=${paymentId} session=${checkoutSessionId} tx=${transactionId}`,
    );

    if (!transactionId && !checkoutSessionId && !paymentId) {
      console.error("[webhook] Missing identifiers in payment.paid", { eventId });
      return ok({ received: true, skipped: "missing identifiers" });
    }

    return processSettlement(supabase, {
      eventId,
      eventType,
      transactionId,
      checkoutSessionId,
      paymentId,
      paymentAttributes,
      extraMetadata: {
        paymongo_metadata: { payment: paymentMetadata },
      },
    });
  }

  // ── all other events ──────────────────────────────────────────────────────
  console.log(`[webhook] Ignored event: ${eventType}`);
  return ok({ received: true, ignored: eventType });
});
