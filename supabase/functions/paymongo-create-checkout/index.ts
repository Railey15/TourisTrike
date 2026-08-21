// Supabase Edge Function: paymongo-create-checkout
//
// Collection-leg counterpart to paymongo-disburse. Phase 1 of the Checkout
// integration (see docs/payment-architecture.md, Phase C3): the tourist app
// always calls this one function; it has no idea whether PAYMONGO_MODE is
// "live" or "stub" — createCheckoutSession() in _shared/paymongoClient.ts is
// the only place that branches.
//
// Two actions, both requiring the caller's own Supabase user JWT (this is
// always tourist-initiated, unlike paymongo-disburse which also accepts a
// trigger-internal secret):
//
//   action: "create"  — mirrors what a real PayMongo Checkout Session
//     creation call would do: returns a checkout_id (+ checkout_url once
//     live mode is implemented). No DB row yet — same as real Checkout,
//     which doesn't write payment_records until the payment.paid webhook
//     fires.
//
//   action: "resolve" — stub-mode-only stand-in for the real hosted
//     Checkout page + payment.paid webhook, which don't exist yet. Only
//     allowed when getMode() === "stub" (rejected in live mode — a real
//     integration resolves via paymongo-payment-webhook, never a client
//     call). On outcome "success", calls the SAME
//     record_payment_and_create_payouts RPC the real webhook calls,
//     keyed on the stub checkout_id as provider_payment_id — so the
//     resulting payment_records/payout_records rows are indistinguishable
//     from ones a real webhook would have produced. On "failure", writes
//     nothing, mirroring paymongo-payment-webhook's handling of
//     payment.failed (see that function's comment at line ~127).
//
// Required secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (automatic),
//   PAYMONGO_MODE ("stub" default / "live").
//
// Deploy: supabase functions deploy paymongo-create-checkout --no-verify-jwt
// (JWT is verified manually below so both actions can share one function
// without Supabase's platform-level verification rejecting the internal
// shape of either request.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createCheckoutSession, getMode } from "../_shared/paymongoClient.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

type PaymentStage = "down_payment" | "remaining_balance" | "full";

interface CreateBody {
  action: "create";
  booking_id: string;
  payment_stage: PaymentStage;
  amount: number;
  description?: string;
}

interface ResolveBody {
  action: "resolve";
  checkout_id: string;
  booking_id: string;
  payment_stage: PaymentStage;
  amount: number;
  outcome: "success" | "failure";
}

async function authorizeTourist(req: Request, bookingId: string): Promise<string | null> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return "UNAUTHENTICATED";

  const { data: userData, error: userErr } = await supabase.auth.getUser(token);
  if (userErr || !userData?.user) return "UNAUTHENTICATED";

  const { data: booking, error: bookingErr } = await supabase
    .from("package_bookings")
    .select("tourist_id")
    .eq("id", bookingId)
    .maybeSingle();

  if (bookingErr || !booking) return "BOOKING_NOT_FOUND";
  if (booking.tourist_id !== userData.user.id) return "NOT_AUTHORIZED";

  return null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: CreateBody | ResolveBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (body.action !== "create" && body.action !== "resolve") {
    return json({ error: "action must be 'create' or 'resolve'" }, 400);
  }
  if (!body.booking_id || !body.payment_stage || !body.amount) {
    return json({ error: "booking_id, payment_stage and amount are required" }, 400);
  }

  const authError = await authorizeTourist(req, body.booking_id);
  if (authError) {
    return json({ error: authError }, authError === "UNAUTHENTICATED" ? 401 : 403);
  }

  if (body.action === "create") {
    try {
      const session = await createCheckoutSession({
        bookingId: body.booking_id,
        paymentStage: body.payment_stage,
        amount: body.amount,
        description: body.description ?? `TourisTrike booking ${body.booking_id} — ${body.payment_stage}`,
      });
      return json({
        ok: true,
        mode: session.mode,
        checkout_id: session.checkoutId,
        checkout_url: session.checkoutUrl,
      });
    } catch (e) {
      console.error("[paymongo-create-checkout] create failed:", e);
      return json({ error: String(e) }, 500);
    }
  }

  // action === "resolve"
  if (getMode() !== "stub") {
    return json(
      { error: "RESOLVE_NOT_AVAILABLE_IN_LIVE_MODE — real Checkout resolves via paymongo-payment-webhook, not a client call" },
      400,
    );
  }

  if (body.outcome !== "success" && body.outcome !== "failure") {
    return json({ error: "outcome must be 'success' or 'failure'" }, 400);
  }

  if (body.outcome === "failure") {
    // Mirrors paymongo-payment-webhook's payment.failed handling: nothing
    // to record on our side, the tourist's UI reflects the failure directly.
    return json({ ok: true, resolved: "failed" });
  }

  const { data, error } = await supabase.rpc("record_payment_and_create_payouts", {
    p_provider_payment_id: body.checkout_id,
    p_booking_id: body.booking_id,
    p_payment_stage: body.payment_stage,
    p_amount: body.amount,
    p_payment_method: "gcash",
  });

  if (error) {
    console.error("[paymongo-create-checkout] resolve(success) RPC failed:", error);
    return json({ error: error.message }, 500);
  }

  // Booking was created hidden from drivers (booking_status='pending_payment')
  // for the down-payment gate — a no-op for any other stage/booking state
  // (see activate_booking_after_down_payment's own idempotency guard).
  const { error: activateError } = await supabase.rpc("activate_booking_after_down_payment", {
    p_booking_id: body.booking_id,
  });
  if (activateError) {
    console.error("[paymongo-create-checkout] activate_booking_after_down_payment failed:", activateError);
  }

  return json({ ok: true, resolved: "paid", payment_record_id: data?.id });
});
