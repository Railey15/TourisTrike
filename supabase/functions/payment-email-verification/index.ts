import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/http.ts";
import { paymentCodeHash } from "../_shared/payment_otp.ts";

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "METHOD_NOT_ALLOWED" }, 405);
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const secret = Deno.env.get("PAYMENT_OTP_HMAC_KEY") ?? "";
  if (!url || !anonKey || !serviceKey || secret.length < 32) {
    return jsonResponse({ error: "VERIFICATION_UNAVAILABLE" }, 503);
  }
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return jsonResponse({ error: "UNAUTHENTICATED" }, 401);
  }
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data, error } = await userClient.auth.getUser();
  const user = data.user;
  if (error || !user || !user.email || !user.email_confirmed_at) {
    return jsonResponse({ error: "UNAUTHENTICATED" }, 401);
  }
  let body: Record<string, unknown>;
  try { body = await request.json(); }
  catch { return jsonResponse({ error: "INVALID_REQUEST" }, 400); }
  const action = body.action;
  const bookingId = body.booking_id;
  const stage = body.payment_stage;
  if ((action !== "request" && action !== "verify") ||
    typeof bookingId !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(bookingId) ||
    (stage !== "down_payment" && stage !== "remaining_balance" &&
      stage !== "full_payment")) {
    return jsonResponse({ error: "INVALID_REQUEST" }, 400);
  }
  const service = createClient(url, serviceKey, { auth: { persistSession: false } });
  if (action === "request") {
    const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
    const from = Deno.env.get("FROM_EMAIL") ?? "";
    if (!resendKey || !from) {
      return jsonResponse({ error: "VERIFICATION_UNAVAILABLE" }, 503);
    }
    const numbers = new Uint32Array(1);
    crypto.getRandomValues(numbers);
    const code = String(numbers[0] % 1000000).padStart(6, "0");
    const hash = await paymentCodeHash(secret, user.id, bookingId, stage, code);
    const { error: challengeError } = await service.rpc(
      "request_payment_email_verification", {
        p_tourist_id: user.id, p_booking_id: bookingId,
        p_payment_stage: stage, p_code_hash: hash,
      },
    );
    if (challengeError) {
      const message = challengeError.message ?? "";
      return jsonResponse({ error: message.includes("RATE_LIMITED")
        ? "RATE_LIMITED" : "VERIFICATION_UNAVAILABLE" },
        message.includes("RATE_LIMITED") ? 429 : 400);
    }
    try {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST", signal: AbortSignal.timeout(15000),
        headers: {
          Authorization: `Bearer ${resendKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from, to: [user.email], subject: "Confirm Your Payment - TourisTrike",
          text: `Enter this verification code in TourisTrike to continue to payment: ${code}\n\nThis code expires in 10 minutes. It does not confirm a payment.`,
        }),
      });
      if (!response.ok) {
        console.error(`[Payment OTP] email provider rejected request status=${response.status}`);
        return jsonResponse({ error: "VERIFICATION_UNAVAILABLE" }, 503);
      }
    } catch (error) {
      console.error(`[Payment OTP] email provider request failed type=${error instanceof Error ? error.name : "unknown"}`);
      return jsonResponse({ error: "VERIFICATION_UNAVAILABLE" }, 503);
    }
    return jsonResponse({ status: "SENT" });
  }
  const code = body.code;
  if (typeof code !== "string" || !/^\d{6}$/.test(code)) {
    return jsonResponse({ error: "INCORRECT" }, 400);
  }
  const hash = await paymentCodeHash(secret, user.id, bookingId, stage, code);
  const { data: result, error: verifyError } = await service.rpc(
    "verify_payment_email_code", {
      p_tourist_id: user.id, p_booking_id: bookingId,
      p_payment_stage: stage, p_code_hash: hash,
    },
  );
  if (verifyError) return jsonResponse({ error: "VERIFICATION_UNAVAILABLE" }, 503);
  if (result !== "VERIFIED") {
    return jsonResponse({ error: result }, result === "RATE_LIMITED" ? 429 : 400);
  }
  return jsonResponse({ status: "VERIFIED" });
});
