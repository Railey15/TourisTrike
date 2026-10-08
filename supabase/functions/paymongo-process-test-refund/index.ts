import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/http.ts";
import { basicAuth } from "../_shared/paymongo.ts";

type Json = Record<string, unknown>;

function refundAttributes(payload: Json): Json {
  const data = payload.data;
  if (!data || typeof data !== "object") return {};
  const attributes = (data as Json).attributes;
  return attributes && typeof attributes === "object" ? attributes as Json : {};
}

serve(async (request) => {
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
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !payMongoKey) {
    return jsonResponse({ error: "REFUND_BACKEND_NOT_CONFIGURED" }, 503);
  }
  if (environment !== "test" || !payMongoKey.startsWith("sk_test_")) {
    return jsonResponse({ error: "PAYMONGO_TEST_MODE_REQUIRED" }, 503);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return jsonResponse({ error: "UNAUTHENTICATED" }, 401);
  }
  const bearer = authorization.slice("Bearer ".length);
  if (bearer !== serviceRoleKey) {
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    if (userError || !userData.user) {
      return jsonResponse({ error: "UNAUTHENTICATED" }, 401);
    }
    const { data: profile } = await userClient.from("profiles")
      .select("role").eq("id", userData.user.id).maybeSingle();
    if (!profile || !["admin", "system_administrator"].includes(profile.role)) {
      return jsonResponse({ error: "NOT_AUTHORIZED" }, 403);
    }
  }

  let body: Json;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "INVALID_JSON" }, 400);
  }
  const refundRequestId = typeof body.refund_request_id === "string"
    ? body.refund_request_id
    : "";
  if (!refundRequestId) {
    return jsonResponse({ error: "REFUND_REQUEST_REQUIRED" }, 400);
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { data: refund, error: refundError } = await serviceClient
    .from("refund_requests")
    .select(
      "id,amount,status,reason,provider_refund_id," +
        "payment_records!inner(id,provider,provider_livemode,provider_payment_id)",
    )
    .eq("id", refundRequestId)
    .maybeSingle();
  if (refundError || !refund) {
    return jsonResponse({ error: "REFUND_REQUEST_NOT_FOUND" }, 404);
  }
  const refundRow = refund as unknown as Json;
  const relation = refundRow.payment_records;
  const payment = (Array.isArray(relation) ? relation[0] : relation) as
    | Json
    | undefined;
  if (
    !payment || payment.provider !== "paymongo" ||
    payment.provider_livemode === true || !payment.provider_payment_id
  ) {
    return jsonResponse({ error: "TEST_PAYMONGO_PAYMENT_REQUIRED" }, 409);
  }
  if (refundRow.status === "completed") {
    return jsonResponse({ completed: true, refund_request_id: refundRow.id });
  }

  const endpoint = refundRow.provider_refund_id
    ? `https://api.paymongo.com/v1/refunds/${
      encodeURIComponent(String(refundRow.provider_refund_id))
    }`
    : "https://api.paymongo.com/v1/refunds";
  const providerResponse = await fetch(endpoint, {
    method: refundRow.provider_refund_id ? "GET" : "POST",
    headers: {
      Authorization: basicAuth(payMongoKey),
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: refundRow.provider_refund_id ? undefined : JSON.stringify({
      data: {
        attributes: {
          amount: Math.round(Number(refundRow.amount) * 100),
          payment_id: payment.provider_payment_id,
          reason: "requested_by_customer",
          notes: `TourisTrike TEST refund: ${
            String(refundRow.reason).slice(0, 180)
          }`,
        },
      },
    }),
  });
  const providerPayload = await providerResponse.json().catch(
    () => ({}),
  ) as Json;
  if (!providerResponse.ok) {
    return jsonResponse(
      { error: "PAYMONGO_TEST_REFUND_FAILED", provider: providerPayload },
      502,
    );
  }

  const providerData = providerPayload.data as Json | undefined;
  const providerRefundId = String(
    providerData?.id ?? refundRow.provider_refund_id ?? "",
  );
  const attributes = refundAttributes(providerPayload);
  const providerStatus = String(attributes.status ?? "pending");
  const { data: recorded, error: recordError } = await serviceClient.rpc(
    "record_paymongo_refund_result",
    {
      p_refund_request_id: refundRow.id,
      p_provider_refund_id: providerRefundId,
      p_provider_status: providerStatus,
      p_provider_payload: providerPayload,
    },
  );
  if (recordError) {
    return jsonResponse({ error: recordError.message }, 409);
  }
  return jsonResponse({
    refund_request_id: refundRow.id,
    provider_refund_id: providerRefundId,
    provider_status: providerStatus,
    completed: recorded?.status === "completed",
    test_mode: true,
  });
});
