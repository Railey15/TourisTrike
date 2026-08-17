// Supabase Edge Function: paymongo-payment-webhook
//
// Receives PayMongo's payment.paid / payment.failed events (tourist side —
// this is separate from disbursement, and NOT stubbed: PayMongo's payment
// acceptance product works in test mode without the Wallet/KYB gating that
// blocks Disbursements, so this leg can be exercised for real against
// PayMongo's own test API keys).
//
// On payment.paid: verifies the signature, then calls
// record_payment_and_create_payouts (SQL) to write the payment_records row
// and fan out the N payout_records skeleton rows via compute_payout_split.
// Does NOT disburse anything itself — that only happens later, when the
// boarded/completed gate fires (see paymongo-disburse).
//
// Required secrets:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — provided automatically
//   PAYMONGO_WEBHOOK_SECRET — from the webhook's settings in the PayMongo
//     Dashboard (Developers → Webhooks → this endpoint → Secret Key)
//
// Deploy: supabase functions deploy paymongo-payment-webhook --no-verify-jwt
// (PayMongo has no Supabase JWT — its own HMAC signature is the auth.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Support environments where the global `Deno` identifier may not be present
function getEnv(name: string): string | undefined {
  if (typeof Deno !== "undefined" && Deno?.env?.get) return Deno.env.get(name);
  if (typeof process !== "undefined" && process?.env) return process.env[name];
  return undefined;
}

const SUPABASE_URL = getEnv("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = getEnv("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PAYMONGO_WEBHOOK_SECRET = getEnv("PAYMONGO_WEBHOOK_SECRET") ?? "";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// Header shape: "t=<timestamp>,te=<test_signature>,li=<live_signature>".
// Verify against BOTH te and li — the payload's own livemode flag tells us
// which mode it is, but comparing against whichever is present is simpler
// and just as safe (an attacker without the secret can't forge either).
async function verifySignature(rawBody: string, signatureHeader: string | null): Promise<boolean> {
  if (!PAYMONGO_WEBHOOK_SECRET || !signatureHeader) return false;

  const parts = Object.fromEntries(
    signatureHeader.split(",").map((kv) => {
      const [k, v] = kv.split("=");
      return [k?.trim(), v?.trim()];
    }),
  );
  const timestamp = parts["t"];
  const candidates = [parts["te"], parts["li"]].filter(Boolean) as string[];
  if (!timestamp || candidates.length === 0) return false;

  const expected = await hmacSha256Hex(PAYMONGO_WEBHOOK_SECRET, `${timestamp}.${rawBody}`);
  return candidates.some((c) => timingSafeEqual(c, expected));
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const rawBody = await req.text();
  const signatureHeader = req.headers.get("Paymongo-Signature");

  const verified = await verifySignature(rawBody, signatureHeader);
  if (!verified) {
    console.warn("[paymongo-payment-webhook] signature verification failed");
    return json({ error: "Invalid signature" }, 401);
  }

  let event: {
    data?: {
      attributes?: {
        type?: string;
        data?: {
          id?: string;
          attributes?: {
            amount?: number;
            status?: string;
            metadata?: { booking_id?: string; payment_stage?: string };
          };
        };
      };
    };
  };
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const eventType = event.data?.attributes?.type;
  const resource = event.data?.attributes?.data;
  const paymentId = resource?.id;
  const attrs = resource?.attributes;
  const bookingId = attrs?.metadata?.booking_id;
  const paymentStage = attrs?.metadata?.payment_stage ?? "full";
  const amountCentavos = attrs?.amount ?? 0;

  if (eventType !== "payment.paid") {
    // payment.failed and everything else — nothing to record on our side;
    // the tourist's UI already reflects the PayMongo Checkout failure state.
    return json({ ok: true, ignored: eventType });
  }

  if (!paymentId || !bookingId) {
    console.error("[paymongo-payment-webhook] missing payment id or booking_id metadata", event);
    return json({ error: "Missing payment id or booking_id metadata" }, 400);
  }

  const { data, error } = await supabase.rpc("record_payment_and_create_payouts", {
    p_provider_payment_id: paymentId,
    p_booking_id: bookingId,
    p_payment_stage: paymentStage,
    p_amount: amountCentavos / 100,
    p_payment_method: "gcash",
  });

  if (error) {
    console.error("[paymongo-payment-webhook] record_payment_and_create_payouts failed:", error);
    return json({ error: error.message }, 500);
  }

  return json({ ok: true, payment_record_id: data?.id });
});
