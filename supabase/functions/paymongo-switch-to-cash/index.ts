import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/http.ts";
import {
  basicAuth,
  checkoutHasOnlyFailedPayments,
} from "../_shared/paymongo.ts";

type Checkout = {
  data?: {
    id?: string;
    attributes?: {
      status?: string;
      livemode?: boolean;
      payments?: unknown[];
      payment_intent?: { id?: string };
      reference_number?: string;
      metadata?: Record<string, unknown>;
    };
  };
};

function hasServiceRoleClaim(authorization: string): boolean {
  try {
    const encoded = authorization.slice(7).split(".")[1];
    if (!encoded) return false;
    const normalized = encoded.replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(
      atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")),
    );
    return payload.role === "service_role" &&
      typeof payload.exp === "number" && payload.exp * 1000 > Date.now();
  } catch {
    return false;
  }
}

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "METHOD_NOT_ALLOWED" }, 405);
  }
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return jsonResponse({ error: "UNAUTHENTICATED" }, 401);
  }
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !anon || !serviceKey) {
    return jsonResponse({ error: "PAYMENT_BACKEND_NOT_CONFIGURED" }, 503);
  }
  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "INVALID_JSON" }, 400);
  }
  const bookingId = typeof body.booking_id === "string" ? body.booking_id : "";
  const key = typeof body.idempotency_key === "string"
    ? body.idempotency_key
    : "";
  const maintenanceAction = body.maintenance_action;
  const maintenance = maintenanceAction === "expire_sandbox_checkout" ||
    maintenanceAction === "reconcile_sandbox_checkout";
  const reconcileOnly = body.action === "reconcile";
  // The platform verifies the JWT before this handler runs. The legacy
  // service-role API key can differ from the runtime's service key after key rotation.
  if (maintenance && !hasServiceRoleClaim(authorization)) {
    return jsonResponse({ error: "SERVICE_ROLE_REQUIRED" }, 403);
  }
  if (
    !bookingId ||
    (!maintenance && !reconcileOnly && (key.length < 16 || key.length > 255)) ||
    (maintenance && typeof body.payment_record_id !== "string")
  ) {
    return jsonResponse({ error: "INVALID_PAYMENT_REQUEST" }, 400);
  }
  const user = createClient(url, anon, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const service = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });
  const reader = maintenance ? service : user;
  if (!maintenance) {
    const { data: identity, error: identityError } = await user.auth.getUser();
    if (identityError || !identity.user) {
      return jsonResponse({ error: "UNAUTHENTICATED" }, 401);
    }
    const { data: booking, error: bookingError } = await user.from(
      "package_bookings",
    )
      .select("tourist_id").eq("id", bookingId).maybeSingle();
    if (bookingError || !booking || booking.tourist_id !== identity.user.id) {
      return jsonResponse({ error: "NOT_BOOKING_TOURIST" }, 403);
    }
  }
  const { data: attempts, error: attemptError } = await reader.from(
    "payment_records",
  )
    .select(
      "id,amount,provider,provider_reference,payment_stage,status,provider_status,provider_checkout_id,provider_livemode,provider_payment_id,paid_at",
    )
    .eq("booking_id", bookingId).eq("payment_stage", "remaining_balance")
    .eq("status", "pending_confirmation").order("created_at", {
      ascending: false,
    }).limit(1);
  if (attemptError) {
    return jsonResponse({ error: "PAYMENT_STATE_UNAVAILABLE" }, 503);
  }
  const attempt = attempts?.[0];
  if (
    reconcileOnly &&
    (!attempt || attempt.provider !== "paymongo" ||
      !attempt.provider_checkout_id)
  ) {
    return jsonResponse({ reconciled: false });
  }
  if (
    maintenance && (
      !attempt || attempt.id !== body.payment_record_id ||
      attempt.provider !== "paymongo" || attempt.provider_livemode !== false ||
      attempt.provider_payment_id || attempt.paid_at ||
      !attempt.provider_checkout_id
    )
  ) {
    return jsonResponse({ error: "SANDBOX_CHECKOUT_NOT_RECOVERABLE" }, 409);
  }
  if (attempt?.provider === "paymongo" && attempt.provider_checkout_id) {
    const environment = (Deno.env.get("PAYMONGO_ENVIRONMENT") ?? "test").trim()
      .toLowerCase();
    const secret = Deno.env.get("PAYMONGO_SECRET_KEY") ?? "";
    if (
      !secret || !["test", "live"].includes(environment) ||
      (environment === "live") !== Boolean(attempt.provider_livemode) ||
      !secret.startsWith(environment === "live" ? "sk_live_" : "sk_test_")
    ) {
      return jsonResponse({ error: "PAYMENT_PROVIDER_NOT_CONFIGURED" }, 503);
    }
    const endpoint = `https://api.paymongo.com/v1/checkout_sessions/${
      encodeURIComponent(attempt.provider_checkout_id)
    }`;
    const headers = {
      Authorization: basicAuth(secret),
      Accept: "application/json",
    };
    try {
      const read = async (): Promise<Checkout | null> => {
        const response = await fetch(endpoint, { headers });
        return response.ok ? await response.json() as Checkout : null;
      };
      let checkout = await read();
      if (
        !checkout?.data || checkout.data.id !== attempt.provider_checkout_id ||
        checkout.data.attributes?.livemode !== attempt.provider_livemode
      ) {
        return jsonResponse(
          { error: "PAYMENT_PROVIDER_IDENTITY_MISMATCH" },
          409,
        );
      }
      const paidPayments =
        checkout.data.attributes?.payments?.filter((payment) =>
          (payment as { attributes?: { status?: string } })?.attributes
            ?.status === "paid"
        ) ?? [];
      if (paidPayments.length > 0) {
        if (
          paidPayments.length !== 1 ||
          maintenanceAction === "expire_sandbox_checkout"
        ) {
          return jsonResponse({ error: "PAYMENT_STAGE_IN_PROGRESS" }, 409);
        }
        const payment = paidPayments[0] as {
          id?: string;
          attributes?: {
            amount?: number;
            currency?: string;
            fee?: number;
            net_amount?: number;
            payment_intent_id?: string;
          };
        };
        const attributes = checkout.data.attributes;
        const metadata = attributes?.metadata;
        const matchedReference =
          attributes?.reference_number === attempt.provider_reference ||
          (metadata?.booking_id === bookingId &&
            metadata?.payment_record_id === attempt.id &&
            metadata?.payment_stage === "remaining_balance");
        if (
          !payment.id || !Number.isInteger(payment.attributes?.amount) ||
          payment.attributes?.amount !==
            Math.round(Number(attempt.amount) * 100) ||
          payment.attributes?.currency !== "PHP" || !matchedReference
        ) {
          return jsonResponse(
            { error: "PAYMENT_PROVIDER_IDENTITY_MISMATCH" },
            409,
          );
        }
        const { data: reconciled, error: reconcileError } = await service.rpc(
          "process_paymongo_webhook_event",
          {
            p_provider_event_id:
              `provider-verified-checkout:${attempt.provider_checkout_id}:${payment.id}`,
            p_event_type: "checkout_session.payment.paid",
            p_provider_livemode: attempt.provider_livemode,
            p_provider_payment_id: payment.id,
            p_provider_payment_intent_id: attributes?.payment_intent?.id ??
              payment.attributes?.payment_intent_id ?? null,
            p_provider_checkout_id: attempt.provider_checkout_id,
            p_provider_reference: attempt.provider_reference,
            p_provider_status: "paid",
            p_amount_centavos: payment.attributes?.amount,
            p_fee_centavos: payment.attributes?.fee ?? null,
            p_net_centavos: payment.attributes?.net_amount ?? null,
            p_payload: { source: "verified_paymongo_checkout_read", checkout },
          },
        );
        if (reconcileError || !reconciled?.confirmed) {
          return jsonResponse({
            error: "PAYMENT_RECONCILIATION_REQUIRES_REVIEW",
            ...(maintenance
              ? {
                reason: reconciled?.reason ?? reconcileError?.code ?? null,
                database_message: reconcileError?.message ?? null,
              }
              : {}),
          }, 409);
        }
        return maintenance || reconcileOnly
          ? jsonResponse({ reconciled: true, payment_record_id: attempt.id })
          : jsonResponse({ error: "PAYMENT_ALREADY_CONFIRMED" }, 409);
      }
      if (maintenanceAction === "reconcile_sandbox_checkout" || reconcileOnly) {
        return jsonResponse({ reconciled: false });
      }
      if (
        !checkout ||
        !checkoutHasOnlyFailedPayments(checkout.data?.attributes?.payments)
      ) {
        return jsonResponse({
          error: "PAYMENT_STAGE_IN_PROGRESS",
          ...(maintenance
            ? {
              reason: checkout
                ? "provider_payment_unresolved"
                : "checkout_lookup_failed",
              checkout_status: checkout?.data?.attributes?.status ?? null,
              payment_statuses:
                checkout?.data?.attributes?.payments?.map((payment) =>
                  (payment as { attributes?: { status?: string } })?.attributes
                    ?.status ?? "unknown"
                ) ?? null,
            }
            : {}),
        }, 409);
      }
      if (checkout.data?.attributes?.status === "active") {
        const expired = await fetch(`${endpoint}/expire`, {
          method: "POST",
          headers,
        });
        if (!expired.ok) {
          return jsonResponse({
            error: "PAYMENT_STAGE_IN_PROGRESS",
            ...(maintenance
              ? {
                reason: "checkout_expiry_failed",
                provider_status: expired.status,
              }
              : {}),
          }, 409);
        }
        checkout = await read();
      }
      if (
        checkout?.data?.attributes?.status !== "expired" ||
        !checkoutHasOnlyFailedPayments(checkout.data.attributes.payments)
      ) {
        return jsonResponse({
          error: "PAYMENT_STAGE_IN_PROGRESS",
          ...(maintenance
            ? {
              reason: "checkout_not_expired",
              checkout_status: checkout?.data?.attributes?.status ?? null,
            }
            : {}),
        }, 409);
      }
    } catch {
      return jsonResponse({ error: "PAYMENT_PROVIDER_UNAVAILABLE" }, 503);
    }
    const { error: markError } = await service.rpc(
      "mark_paymongo_checkout_expired",
      {
        p_payment_record_id: attempt.id,
        p_provider_checkout_id: attempt.provider_checkout_id,
      },
    );
    if (markError) {
      return jsonResponse({
        error: "PAYMENT_STAGE_IN_PROGRESS",
        ...(maintenance
          ? { reason: "database_mark_rejected", database_code: markError.code }
          : {}),
      }, 409);
    }
  }
  if (maintenance) {
    return jsonResponse({ recovered: true, payment_record_id: attempt.id });
  }
  const { data: payment, error } = await user.rpc(
    "prepare_group_cash_remaining_balance",
    {
      p_booking_id: bookingId,
      p_idempotency_key: key,
    },
  );
  if (error) return jsonResponse({ error: error.message }, 409);
  return jsonResponse({ payment });
});
