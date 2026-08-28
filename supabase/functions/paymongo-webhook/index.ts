import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonResponse } from "../_shared/http.ts";
import { sha256, verifyPayMongoSignature } from "../_shared/paymongo.ts";

type JsonMap = Record<string, any>;

serve(async (request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "METHOD_NOT_ALLOWED" }, 405);
  }
  const rawBody = await request.text();
  const secret = Deno.env.get("PAYMONGO_WEBHOOK_SECRET") ?? "";
  const environment = (Deno.env.get("PAYMONGO_ENVIRONMENT") ?? "test")
    .trim()
    .toLowerCase();
  const livemode = environment === "live";
  const signature = request.headers.get("Paymongo-Signature") ??
    request.headers.get("X-Paymongo-Signature") ?? "";
  const tolerance = Number(
    Deno.env.get("PAYMONGO_WEBHOOK_TOLERANCE_SECONDS") ?? "300",
  );
  if (
    !secret || !(await verifyPayMongoSignature({
      rawBody,
      signatureHeader: signature,
      webhookSecret: secret,
      livemode,
      toleranceSeconds: Number.isFinite(tolerance) ? tolerance : 300,
    }))
  ) {
    return jsonResponse({ error: "INVALID_WEBHOOK_SIGNATURE" }, 401);
  }

  let payload: JsonMap;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return jsonResponse({ error: "INVALID_JSON" }, 400);
  }

  const envelope = payload.data ?? {};
  const legacy = envelope.attributes?.type !== undefined;
  const eventType = legacy ? envelope.attributes.type : envelope.type;
  const resource = legacy ? envelope.attributes.data : envelope.data;
  const attributes = resource?.attributes ?? {};
  const payments = Array.isArray(attributes.payments)
    ? attributes.payments
    : [];
  const payment = resource?.type === "payment"
    ? resource
    : payments.find((item: JsonMap) => item?.attributes?.status === "paid") ??
      payments[payments.length - 1] ?? null;
  const paymentAttributes = payment?.attributes ?? {};
  const providerCheckoutId = resource?.type === "checkout_session"
    ? resource.id
    : attributes.checkout_session_id ?? null;
  const providerReference = attributes.reference_number ??
    attributes.metadata?.payment_record_id ??
    paymentAttributes.external_reference_number ?? null;
  const providerEventId = envelope.id ?? payload.id ??
    `sha256:${await sha256(rawBody)}`;
  const eventLivemode = Boolean(
    legacy
      ? envelope.attributes.livemode
      : envelope.livemode ?? attributes.livemode,
  );
  console.info(
    `[PayMongo] webhook received event=${providerEventId} type=${
      eventType ?? "unknown"
    }`,
  );

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "PAYMENT_BACKEND_NOT_CONFIGURED" }, 500);
  }
  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { data, error } = await serviceClient.rpc(
    "process_paymongo_webhook_event",
    {
      p_provider_event_id: String(providerEventId),
      p_event_type: String(eventType ?? "unknown"),
      p_provider_livemode: eventLivemode,
      p_provider_payment_id: payment?.id ?? null,
      p_provider_payment_intent_id: attributes.payment_intent?.id ??
        paymentAttributes.payment_intent_id ?? null,
      p_provider_checkout_id: providerCheckoutId,
      p_provider_reference: providerReference,
      p_provider_status: paymentAttributes.status ?? attributes.status ?? null,
      p_amount_centavos: paymentAttributes.amount ?? attributes.amount ?? null,
      p_fee_centavos: paymentAttributes.fee ?? null,
      p_net_centavos: paymentAttributes.net_amount ?? null,
      p_payload: payload,
    },
  );
  if (error) {
    console.error("[PayMongo] webhook database processing failed", error.code);
    // A verified event gets a retry on transient database failure. Idempotency
    // in payment_provider_events makes concurrent/redelivered events safe.
    return jsonResponse({ error: "WEBHOOK_PROCESSING_FAILED" }, 500);
  }
  console.info(
    `[PayMongo] webhook processed event=${providerEventId} confirmed=${
      Boolean(data?.confirmed)
    }`,
  );
  return jsonResponse(data ?? { ok: true });
});
