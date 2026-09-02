import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, enabled, jsonResponse } from "../_shared/http.ts";
import { basicAuth } from "../_shared/paymongo.ts";

type Allocation = {
  id: string;
  driver_id: string;
  provider_recipient_id: string | null;
  split_basis_points: number;
};

function isHttpsUrl(value: string): boolean {
  try {
    return new URL(value).protocol === "https:";
  } catch {
    return false;
  }
}

function safeLogText(value: unknown): string {
  return String(value ?? "")
    .replace(/[\r\n\t]+/g, " ")
    .slice(0, 240);
}

function returnUrlWithPaymentContext(
  configuredUrl: string,
  bookingId: string,
  paymentRecordId: string,
): string {
  const url = new URL(configuredUrl);
  url.searchParams.set("booking_id", bookingId);
  url.searchParams.set("payment_record_id", paymentRecordId);
  return url.toString();
}

serve(async (request) => {
  console.info("[PayMongo] create-payment Edge Function invoked");
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "METHOD_NOT_ALLOWED" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const payMongoKey = Deno.env.get("PAYMONGO_SECRET_KEY") ?? "";
  const environment = (Deno.env.get("PAYMONGO_ENVIRONMENT") ?? "test")
    .trim()
    .toLowerCase();
  const livemode = environment === "live";
  const splitEnabled = enabled("PAYMONGO_SPLIT_PAYMENTS_ENABLED");
  const checkoutEndpoint =
    "https://api.paymongo.com/v1/checkout_sessions";

  if (!enabled("PAYMONGO_ENABLED") || !payMongoKey) {
    return jsonResponse({ error: "PAYMENT_PROVIDER_NOT_CONFIGURED" }, 503);
  }
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse({ error: "PAYMENT_BACKEND_NOT_CONFIGURED" }, 503);
  }
  if (environment !== "test" && environment !== "live") {
    return jsonResponse({ error: "INVALID_PAYMONGO_ENVIRONMENT" }, 503);
  }
  if (
    (livemode && !payMongoKey.startsWith("sk_live_")) ||
    (!livemode && !payMongoKey.startsWith("sk_test_"))
  ) {
    return jsonResponse({ error: "PAYMONGO_KEY_ENVIRONMENT_MISMATCH" }, 503);
  }
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return jsonResponse({ error: "UNAUTHENTICATED" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "UNAUTHENTICATED" }, 401);
  }
  console.info(`[PayMongo] authenticated tourist=${userData.user.id}`);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "INVALID_JSON" }, 400);
  }
  const bookingId = typeof body.booking_id === "string" ? body.booking_id : "";
  const paymentStage = typeof body.payment_stage === "string"
    ? body.payment_stage
    : "";
  const idempotencyKey = request.headers.get("Idempotency-Key") ??
    (typeof body.idempotency_key === "string" ? body.idempotency_key : "");
  if (!bookingId || !paymentStage || idempotencyKey.length < 16) {
    return jsonResponse(
      { error: "BOOKING_STAGE_AND_IDEMPOTENCY_REQUIRED" },
      400,
    );
  }
  console.info(
    `[PayMongo] checkout requested booking=${bookingId} stage=${paymentStage}`,
  );

  const { data: booking, error: bookingError } = await userClient
    .from("package_bookings")
    .select("tourist_id")
    .eq("id", bookingId)
    .maybeSingle();
  if (bookingError) {
    console.error("[PayMongo] booking lookup failed", bookingError.code);
    return jsonResponse({ error: "BOOKING_LOOKUP_FAILED" }, 400);
  }
  if (!booking) {
    return jsonResponse({ error: "BOOKING_NOT_FOUND" }, 404);
  }
  console.info(`[PayMongo] booking tourist=${booking.tourist_id}`);
  if (booking.tourist_id !== userData.user.id) {
    return jsonResponse({ error: "NOT_BOOKING_TOURIST" }, 403);
  }

  const { data: prepared, error: prepareError } = await userClient.rpc(
    "prepare_paymongo_payment",
    {
      p_booking_id: bookingId,
      p_payment_stage: paymentStage,
      p_idempotency_key: idempotencyKey,
      p_tourist_id: userData.user.id,
      p_provider_livemode: livemode,
    },
  );
  if (prepareError || !prepared?.payment) {
    console.error("[PayMongo] payment preparation failed", prepareError?.code);
    return jsonResponse({
      error: prepareError?.message ?? "PAYMENT_PREPARATION_FAILED",
    }, 400);
  }

  const payment = prepared.payment as Record<string, unknown>;
  console.info(
    `[PayMongo] payment record created/prepared record=${payment.id} allocations=${
      Array.isArray(prepared.allocations) ? prepared.allocations.length : 0
    } reused=${Boolean(prepared.reused)}`,
  );
  if (payment.status === "confirmed") {
    console.info(`[PayMongo] duplicate checkout blocked record=${payment.id}`);
    return jsonResponse({
      error: "PAYMENT_ALREADY_CONFIRMED",
      payment_record_id: payment.id,
    }, 409);
  }
  if (typeof payment.checkout_url === "string" && payment.checkout_url) {
    console.info(`[PayMongo] existing checkout returned record=${payment.id}`);
    return jsonResponse({
      payment_record_id: payment.id,
      checkout_url: payment.checkout_url,
      reused: true,
      livemode,
    });
  }
  if (payment.status === "cancelled") {
    return jsonResponse({ error: "PAYMENT_ATTEMPT_ALREADY_FAILED" }, 409);
  }

  const successUrl = Deno.env.get("PAYMONGO_SUCCESS_URL") ?? "";
  const cancelUrl = Deno.env.get("PAYMONGO_CANCEL_URL") ?? "";
  if (!isHttpsUrl(successUrl) || !isHttpsUrl(cancelUrl)) {
    return jsonResponse({ error: "PAYMENT_REDIRECTS_NOT_CONFIGURED" }, 503);
  }
  const contextualSuccessUrl = returnUrlWithPaymentContext(
    successUrl,
    bookingId,
    String(payment.id),
  );
  const contextualCancelUrl = returnUrlWithPaymentContext(
    cancelUrl,
    bookingId,
    String(payment.id),
  );

  const allocations = (prepared.allocations ?? []) as Allocation[];
  const attributes: Record<string, unknown> = {
    line_items: [{
      name: `TourisTrike booking ${bookingId}`,
      description: `Payment stage: ${payment.payment_stage}`,
      amount: prepared.amount_centavos,
      currency: "PHP",
      quantity: 1,
    }],
    payment_method_types: ["gcash"],
    success_url: contextualSuccessUrl,
    cancel_url: contextualCancelUrl,
    reference_number: payment.provider_reference ?? payment.id,
    description: "TourisTrike package booking payment",
    send_email_receipt: true,
    show_description: true,
    show_line_items: true,
    metadata: {
      payment_record_id: payment.id,
      booking_id: bookingId,
      payment_stage: payment.payment_stage,
    },
  };

  if (splitEnabled) {
    if (
      allocations.length === 0 ||
      allocations.some((item) => !item.provider_recipient_id)
    ) {
      return jsonResponse({ error: "DRIVER_PAYOUT_ACCOUNT_NOT_READY" }, 409);
    }
    if (
      allocations.reduce(
        (total, item) => total + item.split_basis_points,
        0,
      ) !== 10000
    ) {
      return jsonResponse({ error: "INVALID_DRIVER_ALLOCATION_SPLIT" }, 500);
    }
    attributes.split_payment = {
      recipients: allocations.map((allocation) => ({
        merchant_id: allocation.provider_recipient_id,
        split_type: "percentage_net",
        value: allocation.split_basis_points,
      })),
    };
  }

  const response = await fetch(
    checkoutEndpoint,
    {
      method: "POST",
      headers: {
        Authorization: basicAuth(payMongoKey),
        "Content-Type": "application/json",
        "Idempotency-Key": `touristrike-checkout-${payment.id}`,
      },
      body: JSON.stringify({ data: { attributes } }),
    },
  );
  const providerBody = await response.json().catch(() => ({}));
  console.info(`[PayMongo] Checkout API HTTP status=${response.status}`);
  if (!response.ok) {
    const providerCode = providerBody?.errors?.[0]?.code ??
      `HTTP_${response.status}`;
    const providerDetail = providerBody?.errors?.[0]?.detail ??
      "Checkout creation failed";
    console.error(
      `[PayMongo] checkout creation failed code=${safeLogText(providerCode)} ` +
        `detail=${safeLogText(providerDetail)}`,
    );
    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    await serviceClient.rpc("record_paymongo_checkout_failure", {
      p_payment_record_id: payment.id,
      p_failure_code: String(providerCode),
      p_failure_message: String(providerDetail),
    });
    return jsonResponse({ error: "PAYMENT_PROVIDER_REQUEST_FAILED" }, 502);
  }

  const session = providerBody?.data;
  const checkoutUrl = session?.attributes?.checkout_url;
  if (!session?.id || !checkoutUrl) {
    return jsonResponse({ error: "INVALID_PAYMENT_PROVIDER_RESPONSE" }, 502);
  }
  console.info(
    `[PayMongo] checkout URL received host=${new URL(checkoutUrl).host}`,
  );
  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { error: persistError } = await serviceClient.rpc(
    "set_paymongo_checkout_session",
    {
      p_payment_record_id: payment.id,
      p_provider_checkout_id: session.id,
      p_checkout_url: checkoutUrl,
      p_provider_payment_intent_id: session.attributes?.payment_intent?.id ??
        null,
      p_provider_payload: providerBody,
      p_split_requested: splitEnabled,
    },
  );
  if (persistError) {
    console.error("[PayMongo] checkout persistence failed", persistError.code);
    return jsonResponse({ error: "PAYMENT_CHECKOUT_PERSISTENCE_FAILED" }, 500);
  }

  console.info(`[PayMongo] checkout URL returned record=${payment.id}`);

  return jsonResponse({
    success: true,
    payment_record_id: payment.id,
    checkout_url: checkoutUrl,
    reused: false,
    livemode,
  });
});
