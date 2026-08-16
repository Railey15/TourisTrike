// Supabase Edge Function: paymongo-disburse
//
// The only function that ever calls PayMongo (or the stub) to move money
// out. Invoked two ways:
//   1. Automatically, by the DB triggers in
//      20260817010000_paymongo_disbursement_rpcs_and_triggers.sql, when a
//      driver reaches 'boarded' (down_payment) or a booking reaches
//      'completed' (remaining_balance, fanned out to every accepted driver).
//      Authenticated via the X-Internal-Secret header.
//   2. Manually, as a "Retry Disbursement" action from the app (driver on
//      their own payout, or admin/subtenant on any). Authenticated via a
//      normal Supabase user JWT.
//
// Never trusts the caller about WHETHER the gate is actually satisfied —
// claim_payout_for_disbursement (SQL) re-derives that itself from
// booking_drivers/package_bookings. This function's own auth only decides
// WHO is allowed to ask; the SQL layer decides whether the ask is valid.
//
// Required secrets (Supabase Dashboard → Edge Functions → Secrets):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — provided automatically
//   INTERNAL_TRIGGER_SECRET — shared secret the DB triggers send
//   PAYMONGO_MODE — "stub" (default) or "live"
//   PAYMONGO_SECRET_KEY — only needed once PAYMONGO_MODE=live
//
// Deploy: supabase functions deploy paymongo-disburse --no-verify-jwt
// (--no-verify-jwt because the DB-trigger caller has no Supabase JWT at
// all — auth is handled manually below instead.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createTransfer } from "../_shared/paymongoClient.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const INTERNAL_TRIGGER_SECRET = Deno.env.get("INTERNAL_TRIGGER_SECRET") ?? "";
const DISBURSEMENT_MODE = (Deno.env.get("PAYMONGO_MODE") ?? "stub").toLowerCase();

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

interface DisburseRequest {
  booking_id: string;
  driver_id?: string;
  payment_stage: "down_payment" | "remaining_balance" | "full";
}

async function authorize(req: Request, body: DisburseRequest): Promise<string | null> {
  // Internal trigger call.
  const internalHeader = req.headers.get("X-Internal-Secret");
  if (INTERNAL_TRIGGER_SECRET && internalHeader === INTERNAL_TRIGGER_SECRET) {
    return null; // authorized, no error
  }

  // App-initiated retry — needs a real user.
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return "UNAUTHENTICATED";

  const { data: userData, error: userErr } = await supabase.auth.getUser(token);
  if (userErr || !userData?.user) return "UNAUTHENTICATED";

  const { data: profile } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", userData.user.id)
    .maybeSingle();

  const isAdmin = profile?.role === "admin" || profile?.role === "subtenant";
  const isTheDriver = !!body.driver_id && body.driver_id === userData.user.id;

  if (isAdmin || isTheDriver) return null;
  return "NOT_AUTHORIZED";
}

async function disburseOne(bookingId: string, driverId: string, paymentStage: string) {
  const { data: claimed, error: claimErr } = await supabase.rpc(
    "claim_payout_for_disbursement",
    { p_booking_id: bookingId, p_driver_id: driverId, p_payment_stage: paymentStage },
  );

  if (claimErr || !claimed) {
    // GATE_NOT_MET / NOT_CLAIMABLE / not found — expected, not fatal.
    // A duplicate trigger fire or a premature retry both land here safely.
    console.log(
      `[paymongo-disburse] not claimed booking=${bookingId} driver=${driverId} stage=${paymentStage}: ${claimErr?.message}`,
    );
    return { driverId, claimed: false, reason: claimErr?.message ?? "unknown" };
  }

  // Verification gate — checked fresh, not from the amount-time snapshot,
  // since a driver can change their GCash number/name after the split was
  // computed (that resets verification via trg_reset_gcash_verification).
  const { data: driverDetails } = await supabase
    .from("driver_details")
    .select("gcash_number, gcash_name, gcash_verification_status")
    .eq("driver_id", driverId)
    .maybeSingle();

  if (driverDetails?.gcash_verification_status !== "verified") {
    await supabase.rpc("fail_payout_precheck", {
      p_payout_record_id: claimed.id,
      p_error_message:
        "Driver's GCash account is not verified yet — cannot disburse until onboarding verification is approved.",
    });
    return { driverId, claimed: true, disbursed: false, reason: "GCASH_UNVERIFIED" };
  }

  const referenceNumber = `booking_${bookingId}_driver_${driverId}_${paymentStage}`;
  const idempotencyKey = `${referenceNumber}_attempt_${claimed.retry_count}`;

  const transfer = await createTransfer({
    destinationNumber: driverDetails.gcash_number ?? claimed.gcash_number_snapshot ?? "",
    destinationName: driverDetails.gcash_name ?? claimed.gcash_name_snapshot ?? "",
    amountCentavos: Math.round(Number(claimed.amount) * 100),
    referenceNumber,
    idempotencyKey,
    description: `TourisTrike booking ${bookingId} — ${paymentStage}`,
  });

  await supabase.rpc("record_transfer_submitted", {
    p_payout_record_id: claimed.id,
    p_paymongo_transfer_id: transfer.transferId,
    p_reference_number: referenceNumber,
    p_provider_reference_number: transfer.providerReferenceNumber,
    p_disbursement_mode: DISBURSEMENT_MODE,
  });

  return { driverId, claimed: true, disbursed: true, transferId: transfer.transferId };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: DisburseRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (!body.booking_id || !body.payment_stage) {
    return json({ error: "booking_id and payment_stage are required" }, 400);
  }

  const authError = await authorize(req, body);
  if (authError) return json({ error: authError }, authError === "UNAUTHENTICATED" ? 401 : 403);

  try {
    let driverIds: string[];
    if (body.driver_id) {
      driverIds = [body.driver_id];
    } else {
      const { data: drivers, error } = await supabase
        .from("booking_drivers")
        .select("driver_id")
        .eq("booking_id", body.booking_id)
        .eq("status", "accepted");
      if (error) throw error;
      driverIds = (drivers ?? []).map((d) => d.driver_id as string);
    }

    const results = await Promise.all(
      driverIds.map((driverId) => disburseOne(body.booking_id, driverId, body.payment_stage)),
    );

    return json({ ok: true, booking_id: body.booking_id, payment_stage: body.payment_stage, results });
  } catch (e) {
    console.error("[paymongo-disburse] Unhandled error:", e);
    return json({ error: String(e) }, 500);
  }
});
