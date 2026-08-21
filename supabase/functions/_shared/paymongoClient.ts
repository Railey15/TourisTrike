// The ONLY module that knows whether disbursements are real or simulated.
// paymongo-disburse imports createTransfer() and nothing else from here —
// it has no idea which mode it's running in. That's the whole point: one
// boundary, swapped by an env var, not two parallel implementations.
//
// PAYMONGO_MODE=live  — calls the real PayMongo Transfers API.
// PAYMONGO_MODE=stub  — fabricates a transfer id/reference and schedules a
//   delayed self-callback to paymongo-transfer-webhook, reproducing the
//   same async "submitted now, resolved later via callback" shape a real
//   transfer has. paymongo-transfer-webhook cannot tell the difference
//   between a real PayMongo callback and this one — same handler, same code.
//
// Defaults to "stub" — a live disbursement should never happen because an
// env var was merely left unset.

export interface CreateTransferInput {
  destinationNumber: string;
  destinationName: string;
  amountCentavos: number;
  referenceNumber: string;
  idempotencyKey: string;
  description: string;
}

export interface CreateTransferResult {
  transferId: string;
  providerReferenceNumber: string;
  status: "processing";
}

// Access environment variables in a runtime-agnostic way (Deno or Node).
const envGet = (k: string): string | undefined => {
  try {
    // Deno
    // @ts-ignore
    if (typeof globalThis?.Deno?.env?.get === "function") return globalThis.Deno.env.get(k);
  } catch (_) {}
  try {
    // Node/process
    // @ts-ignore
    if (typeof process?.env === "object") return process.env[k];
  } catch (_) {}
  return undefined;
};

const MODE = (envGet("PAYMONGO_MODE") ?? "stub").toLowerCase();
const SECRET_KEY = envGet("PAYMONGO_SECRET_KEY") ?? "";
const SUPABASE_URL = envGet("SUPABASE_URL") ?? "";
const INTERNAL_TRIGGER_SECRET = envGet("INTERNAL_TRIGGER_SECRET") ?? "";

// Same shape as the driver_details.gcash_number DB check constraint
// (20260725000000_gcash_payment_trail.sql) — the stub's "will this fail"
// rule is deliberately the same validation a real rail would reject on,
// not an arbitrary flag, so the failure path is explainable, not magic.
const PH_MOBILE_RE = /^(09|\+639)\d{9}$/;

console.log(`[PayMongo] client initialized in ${MODE.toUpperCase()} mode`);
if (MODE === "live" && !SECRET_KEY) {
  console.error(
    "[PayMongo] PAYMONGO_MODE=live but PAYMONGO_SECRET_KEY is unset — every live transfer will fail fast.",
  );
}

export async function createTransfer(
  input: CreateTransferInput,
): Promise<CreateTransferResult> {
  return MODE === "live" ? createLiveTransfer(input) : createStubTransfer(input);
}

// ── Checkout (Collection leg) ────────────────────────────────────────────
// Same "one boundary" shape as createTransfer() above, for the tourist-pays
// side. Stub mode has no hosted page to redirect to (checkoutUrl is null) —
// paymongo-create-checkout's caller shows a local stand-in screen instead
// and calls back through the "resolve" action, which only that Edge
// Function's stub branch allows (see getMode() below).

export interface CreateCheckoutInput {
  bookingId: string;
  paymentStage: "down_payment" | "remaining_balance" | "full";
  amount: number;
  description: string;
}

export interface CreateCheckoutResult {
  checkoutId: string;
  checkoutUrl: string | null;
  mode: "live" | "stub";
}

export function getMode(): "live" | "stub" {
  return MODE === "live" ? "live" : "stub";
}

export async function createCheckoutSession(
  input: CreateCheckoutInput,
): Promise<CreateCheckoutResult> {
  return MODE === "live" ? createLiveCheckout(input) : createStubCheckout(input);
}

async function createLiveCheckout(
  _input: CreateCheckoutInput,
): Promise<CreateCheckoutResult> {
  if (!SECRET_KEY) {
    throw new Error("PAYMONGO_MODE=live but PAYMONGO_SECRET_KEY is not set");
  }
  // NOT WIRED UP YET: PayMongo Checkout Session creation
  // (POST /v1/checkout_sessions) isn't implemented. Left unimplemented on
  // purpose until PayMongo support confirms test-mode Checkout availability
  // for this account (see docs/payment-architecture.md open questions).
  // Flipping PAYMONGO_MODE=live before then fails loudly here, not silently.
  throw new Error(
    "PAYMONGO_MODE=live is not implemented yet — Checkout API integration " +
      "is unresolved. Use PAYMONGO_MODE=stub.",
  );
}

async function createStubCheckout(
  input: CreateCheckoutInput,
): Promise<CreateCheckoutResult> {
  const checkoutId = `stub_chk_${crypto.randomUUID()}`;
  void input; // nothing to fabricate beyond the id — the amount/stage are
  // echoed back by the caller when it resolves the checkout, same as a real
  // Checkout Session would be looked up by id.
  return { checkoutId, checkoutUrl: null, mode: "stub" };
}

async function createLiveTransfer(
  _input: CreateTransferInput,
): Promise<CreateTransferResult> {
  if (!SECRET_KEY) {
    throw new Error("PAYMONGO_MODE=live but PAYMONGO_SECRET_KEY is not set");
  }
  // NOT WIRED UP YET: destination_account.bic for a GCash recipient must
  // come from GET /v2/transfers/receiving_institutions?provider=instapay —
  // matching "GCash" by name to get the correct BIC. Left unimplemented on
  // purpose until that lookup + PayMongo's KYB/test-mode answers are
  // confirmed (see the Phase B chat report's open questions). Flipping
  // PAYMONGO_MODE=live before then will fail loudly here instead of
  // silently misbehaving.
  throw new Error(
    "PAYMONGO_MODE=live is not implemented yet — GCash receiving-institution " +
      "lookup is unresolved. Use PAYMONGO_MODE=stub.",
  );
}

async function createStubTransfer(
  input: CreateTransferInput,
): Promise<CreateTransferResult> {
  const transferId = `stub_tr_${crypto.randomUUID()}`;
  const providerReferenceNumber = `STUB-${Date.now()}`;
  const willSucceed = PH_MOBILE_RE.test(input.destinationNumber.trim());

  const delayMs = 4000 + Math.floor(Math.random() * 4000);

  // Fire-and-forget: don't make the caller (paymongo-disburse) wait for
  // the simulated settlement delay — a real transfer wouldn't either.
  // EdgeRuntime is a Supabase-provided global, not in standard Deno types.
  // deno-lint-ignore no-explicit-any
  const runtime = globalThis as any;
  const scheduleCallback = async () => {
    await new Promise((resolve) => setTimeout(resolve, delayMs));
    try {
      await fetch(`${SUPABASE_URL}/functions/v1/paymongo-transfer-webhook`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Stub-Callback": INTERNAL_TRIGGER_SECRET,
        },
        body: JSON.stringify({
          id: transferId,
          status: willSucceed ? "succeeded" : "failed",
          provider_reference_number: providerReferenceNumber,
          failure_message: willSucceed
            ? null
            : "Invalid GCash number format (stub validation)",
        }),
      });
    } catch (e) {
      console.error(`[PayMongo:stub] delayed callback failed for ${transferId}:`, e);
    }
  };

  if (typeof runtime.EdgeRuntime?.waitUntil === "function") {
    runtime.EdgeRuntime.waitUntil(scheduleCallback());
  } else {
    // Local `supabase functions serve` doesn't always expose EdgeRuntime —
    // fall back to a detached promise so stub mode still works there.
    scheduleCallback();
  }

  return { transferId, providerReferenceNumber, status: "processing" };
}
