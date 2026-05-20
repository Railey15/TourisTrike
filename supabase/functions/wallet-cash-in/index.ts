// Supabase Edge Function: wallet-cash-in
// Creates a pending wallet transaction, then creates a PayMongo checkout
// session that returns to TourisTrike app deep links.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PAYMONGO_SECRET_KEY = Deno.env.get("PAYMONGO_SECRET_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

// HTTPS redirect function bridges PayMongo's HTTPS redirect requirement to the app deep link.
// Deploy paymongo-redirect with --no-verify-jwt so browsers can reach it unauthenticated.
const REDIRECT_FUNCTION = `${Deno.env.get("SUPABASE_URL") ?? ""}/functions/v1/paymongo-redirect`;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

const PM_TYPE: Record<string, string> = {
  gcash: "gcash",
  maya: "paymaya",
  card: "card",
};

const asRecord = (value: unknown): Record<string, unknown> =>
  value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};

const toTrimmedString = (value: unknown): string =>
  typeof value === "string" ? value.trim() : "";

const safeMetadataValue = (value: unknown): string | number | boolean | null => {
  if (
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return value;
  }
  return null;
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  try {
    if (!PAYMONGO_SECRET_KEY) {
      throw new Error("PAYMONGO_SECRET_KEY is not configured.");
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing authorization header" }, 401);
    }

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return json({ error: "Unauthorized" }, 401);
    }

    const body = (await req.json()) as {
      amount?: number;
      payment_method?: string;
      role?: string;
    };

    const amount = Number(body.amount ?? 0);
    const paymentMethod = toTrimmedString(body.payment_method).toLowerCase();
    const role = toTrimmedString(body.role).toLowerCase() || "tourist";

    if (!Number.isFinite(amount) || amount < 1) {
      return json({ error: "amount must be at least 1 PHP" }, 400);
    }

    const normalizedAmount = Number(amount.toFixed(2));
    const amountInCentavos = Math.round(normalizedAmount * 100);

    const pmType = PM_TYPE[paymentMethod];
    if (!pmType) {
      return json(
        { error: "payment_method must be gcash, maya, or card" },
        400,
      );
    }

    if (role !== "tourist" && role !== "driver") {
      return json({ error: "role must be tourist or driver" }, 400);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: walletData, error: walletError } = await supabase.rpc(
      "get_or_create_wallet",
      { p_user_id: user.id, p_role: role },
    );

    if (walletError) {
      throw new Error(`Wallet error: ${walletError.message}`);
    }

    const wallet = Array.isArray(walletData)
      ? asRecord(walletData[0])
      : asRecord(walletData);
    const walletId = toTrimmedString(wallet.id);

    if (!walletId) {
      throw new Error("Wallet could not be created or loaded.");
    }

    const baseMetadata = {
      user_id: user.id,
      wallet_id: walletId,
      type: "cash_in",
    };

    const { data: tx, error: txError } = await supabase
      .from("wallet_transactions")
      .insert({
        wallet_id: walletId,
        user_id: user.id,
        role,
        type: "cash_in",
        amount: normalizedAmount,
        status: "pending",
        payment_method: paymentMethod,
        metadata: baseMetadata,
      })
      .select("*")
      .single();

    if (txError || !tx) {
      throw new Error(`Transaction error: ${txError?.message ?? "Unknown"}`);
    }

    const transactionId = toTrimmedString(tx.id);
    if (!transactionId) {
      throw new Error("Transaction id was not returned.");
    }

    const successUrl =
      `${REDIRECT_FUNCTION}?to=success&transaction_id=${encodeURIComponent(transactionId)}`;
    const cancelUrl =
      `${REDIRECT_FUNCTION}?to=cancel&transaction_id=${encodeURIComponent(transactionId)}`;

    const customerMetadata = asRecord(user.user_metadata);
    const customerName =
      toTrimmedString(customerMetadata.full_name) ||
      toTrimmedString(customerMetadata.name) ||
      toTrimmedString(user.email?.split("@")[0]) ||
      "TourisTrike User";

    const paymongoMetadata = {
      ...baseMetadata,
      transaction_id: transactionId,
      role,
      payment_method: paymentMethod,
      amount: normalizedAmount,
      source: "touristrike_wallet_cash_in",
    };

    const pmResponse = await fetch("https://api.paymongo.com/v1/checkout_sessions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${btoa(`${PAYMONGO_SECRET_KEY}:`)}`,
      },
      body: JSON.stringify({
        data: {
          attributes: {
            billing: {
              name: customerName,
              email: toTrimmedString(user.email),
            },
            send_email_receipt: false,
            show_description: true,
            show_line_items: true,
            description: "TourisTrike Wallet Cash In",
            line_items: [
              {
                currency: "PHP",
                amount: amountInCentavos,
                name: "TourisTrike Wallet Cash In",
                quantity: 1,
              },
            ],
            payment_method_types: [pmType],
            success_url: successUrl,
            cancel_url: cancelUrl,
            metadata: paymongoMetadata,
          },
        },
      }),
    });

    const pmData = await pmResponse.json();

    if (!pmResponse.ok) {
      await supabase
        .from("wallet_transactions")
        .update({
          status: "failed",
          metadata: {
            ...paymongoMetadata,
            paymongo_error: safeMetadataValue(pmData?.errors) ??
              JSON.stringify(pmData?.errors ?? pmData),
          },
          updated_at: new Date().toISOString(),
        })
        .eq("id", transactionId);

      throw new Error(
        `PayMongo error: ${JSON.stringify(pmData?.errors ?? pmData)}`,
      );
    }

    const session = asRecord(pmData?.data);
    const sessionId = toTrimmedString(session.id);
    const sessionAttributes = asRecord(session.attributes);
    const checkoutUrl = toTrimmedString(sessionAttributes.checkout_url);

    if (!sessionId || !checkoutUrl) {
      await supabase
        .from("wallet_transactions")
        .update({
          status: "failed",
          metadata: {
            ...paymongoMetadata,
            paymongo_error: "Checkout session did not return session id or checkout URL.",
          },
          updated_at: new Date().toISOString(),
        })
        .eq("id", transactionId);

      throw new Error("PayMongo checkout session did not return a checkout URL.");
    }

    const storedMetadata = {
      ...paymongoMetadata,
      checkout_session_id: sessionId,
      checkout_url: checkoutUrl,
      success_url: successUrl,
      cancel_url: cancelUrl,
    };

    const { error: updateError } = await supabase
      .from("wallet_transactions")
      .update({
        paymongo_reference_id: sessionId,
        checkout_url: checkoutUrl,
        metadata: storedMetadata,
        updated_at: new Date().toISOString(),
      })
      .eq("id", transactionId);

    if (updateError) {
      throw new Error(`Transaction update error: ${updateError.message}`);
    }

    return json({
      checkout_url: checkoutUrl,
      checkout_session_id: sessionId,
      transaction_id: transactionId,
      success_url: successUrl,
      cancel_url: cancelUrl,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return json({ error: message }, 500);
  }
});
