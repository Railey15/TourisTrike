import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, enabled, jsonResponse } from "../_shared/http.ts";
import {
  basicAuth,
  checkoutHasOnlyFailedPayments,
} from "../_shared/paymongo.ts";
import {
  configuredPayMongoPaymentMethods,
  isPayMongoPaymentMethod,
  paymentFlow,
} from "../_shared/paymongo_payment_methods.ts";
import { resolveCheckoutBilling } from "./customer_billing.ts";

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
  const livemode = false;
  const splitEnabled = enabled("PAYMONGO_SPLIT_PAYMENTS_ENABLED");
  const enabledPaymentMethods = configuredPayMongoPaymentMethods(
    Deno.env.get("PAYMONGO_PAYMENT_METHOD_TYPES"),
  );
  const checkoutEndpoint = "https://api.paymongo.com/v1/checkout_sessions";

  if (!enabled("PAYMONGO_ENABLED") || !payMongoKey) {
    return jsonResponse({ error: "PAYMENT_PROVIDER_NOT_CONFIGURED" }, 503);
  }
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse({ error: "PAYMENT_BACKEND_NOT_CONFIGURED" }, 503);
  }
  // TourisTrike's current payment lifecycle is intentionally TEST-only. A
  // live key must never be accepted by this endpoint until a separately
  // reviewed production settlement design is introduced.
  if (environment !== "test") {
    return jsonResponse({ error: "PAYMONGO_TEST_MODE_REQUIRED" }, 503);
  }
  if (!payMongoKey.startsWith("sk_test_")) {
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
  const paymentMethod = typeof body.payment_method === "string"
    ? body.payment_method.trim().toLowerCase()
    : "";
  const idempotencyKey = request.headers.get("Idempotency-Key") ??
    (typeof body.idempotency_key === "string" ? body.idempotency_key : "");
  if (!bookingId || !paymentStage || !paymentMethod || idempotencyKey.length < 16) {
    return jsonResponse(
      { error: "BOOKING_STAGE_AND_IDEMPOTENCY_REQUIRED" },
      400,
    );
  }
  if (!isPayMongoPaymentMethod(paymentMethod)) {
    return jsonResponse({ error: "INVALID_PAYMENT_METHOD" }, 400);
  }
  if (!enabledPaymentMethods.has(paymentMethod)) {
    return jsonResponse({ error: "PAYMENT_METHOD_NOT_ENABLED" }, 409);
  }
  console.info(
    `[PayMongo] checkout requested booking=${bookingId} stage=${paymentStage} ` +
      `method=${paymentMethod}`,
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

  // Consume the recent, obligation-scoped proof before preparing or reusing a
  // checkout. A direct call to this function cannot skip email verification.
  const verificationClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { data: authorized, error: verificationError } =
    await verificationClient.rpc(
      "consume_payment_email_verification",
      {
        p_tourist_id: userData.user.id,
        p_booking_id: bookingId,
        p_payment_stage: paymentStage,
      },
    );
  if (verificationError || authorized !== true) {
    return jsonResponse({ error: "PAYMENT_EMAIL_VERIFICATION_REQUIRED" }, 403);
  }

  const { data: touristProfile, error: profileError } = await userClient
    .from("profiles")
    .select("first_name,last_name,full_name,mobile")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (profileError) {
    console.warn("[PayMongo] tourist profile lookup failed", profileError.code);
  }

  const billing = resolveCheckoutBilling({
    requestedName: typeof body.customer_name === "string"
      ? body.customer_name
      : undefined,
    requestedEmail: typeof body.customer_email === "string"
      ? body.customer_email
      : undefined,
    profile: touristProfile,
    authEmail: userData.user.email,
    authPhone: userData.user.phone,
  });
  const customerName = billing.name ?? "";
  const customerEmail = billing.email ?? "";
  if (
    customerName.length > 200 || customerEmail.length > 254 ||
    (customerEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customerEmail))
  ) {
    return jsonResponse({ error: "INVALID_PAYMENT_CONTACT" }, 400);
  }

  let { data: prepared, error: prepareError } = await userClient.rpc(
    "prepare_paymongo_payment",
    {
      p_booking_id: bookingId,
      p_payment_stage: paymentStage,
      p_idempotency_key: idempotencyKey,
      p_tourist_id: userData.user.id,
      p_provider_livemode: livemode,
      p_payment_method: paymentMethod,
    },
  );
  if (prepareError || !prepared?.payment) {
    console.error("[PayMongo] payment preparation failed", prepareError?.code);
    return jsonResponse({
      error: prepareError?.message ?? "PAYMENT_PREPARATION_FAILED",
    }, 400);
  }

  let payment = prepared.payment as Record<string, unknown>;
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
    if (
      typeof payment.provider_checkout_id !== "string" ||
      !payment.provider_checkout_id
    ) {
      return jsonResponse({ error: "PAYMENT_STATE_UNAVAILABLE" }, 503);
    }
    const sessionEndpoint = `${checkoutEndpoint}/${
      encodeURIComponent(payment.provider_checkout_id)
    }`;
    let session: Record<string, unknown>;
    try {
      const result = await fetch(sessionEndpoint, {
        headers: {
          Authorization: basicAuth(payMongoKey),
          Accept: "application/json",
        },
      });
      if (!result.ok) {
        return jsonResponse({ error: "PAYMENT_PROVIDER_UNAVAILABLE" }, 503);
      }
      session = await result.json();
    } catch {
      return jsonResponse({ error: "PAYMENT_PROVIDER_UNAVAILABLE" }, 503);
    }
    const attributes = (session.data as Record<string, unknown> | undefined)
      ?.attributes as Record<string, unknown> | undefined;
    if (!checkoutHasOnlyFailedPayments(attributes?.payments)) {
      return jsonResponse({ error: "PAYMENT_STAGE_IN_PROGRESS" }, 409);
    }
    if (attributes?.status === "active") {
      console.info(
        `[PayMongo] existing checkout returned record=${payment.id}`,
      );
      return jsonResponse({
        payment_record_id: payment.id,
        checkout_url: payment.checkout_url,
        reused: true,
        livemode,
        payment_method: paymentMethod,
        payment_flow: paymentFlow(paymentMethod),
        qr_payment: paymentMethod === "qrph"
          ? {
            checkout_url: payment.checkout_url,
            presentation: "paymongo_hosted_checkout",
          }
          : null,
      });
    }
    if (attributes?.status !== "expired") {
      return jsonResponse({ error: "PAYMENT_STATE_UNAVAILABLE" }, 503);
    }
    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const { error: markError } = await serviceClient.rpc(
      "mark_paymongo_checkout_expired",
      {
        p_payment_record_id: payment.id,
        p_provider_checkout_id: payment.provider_checkout_id,
      },
    );
    if (markError) {
      return jsonResponse({ error: "PAYMENT_STAGE_IN_PROGRESS" }, 409);
    }
    const { data: retried, error: retryError } = await userClient.rpc(
      "prepare_paymongo_payment",
      {
        p_booking_id: bookingId,
        p_payment_stage: paymentStage,
        p_idempotency_key:
          `touristrike-retry:${bookingId}:${crypto.randomUUID()}`,
        p_tourist_id: userData.user.id,
        p_provider_livemode: livemode,
        p_payment_method: paymentMethod,
      },
    );
    if (retryError || !retried?.payment) {
      return jsonResponse({
        error: retryError?.message ?? "PAYMENT_PREPARATION_FAILED",
      }, 409);
    }
    payment = retried.payment as Record<string, unknown>;
    prepared = retried;
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
    payment_method_types: [paymentMethod],
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
      payment_method: paymentMethod,
    },
  };

  if (Object.keys(billing).length > 0) {
    attributes.billing = billing;
  }

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
    payment_method: paymentMethod,
    payment_flow: paymentFlow(paymentMethod),
    qr_payment: paymentMethod === "qrph"
      ? {
        checkout_url: checkoutUrl,
        presentation: "paymongo_hosted_checkout",
      }
      : null,
  });
});
