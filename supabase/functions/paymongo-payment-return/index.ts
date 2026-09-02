import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

serve((request) => {
  if (request.method !== "GET") {
    return new Response("Method not allowed", { status: 405 });
  }

  const returnUrl = new URL(request.url);
  const requestedResult = returnUrl.searchParams.get("result");
  const result = requestedResult === "success" ? "success" : "cancel";
  const bookingId = returnUrl.searchParams.get("booking_id") ?? "";
  const paymentRecordId = returnUrl.searchParams.get("payment_record_id") ?? "";
  const uuidPattern =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const appUrl = new URL(`touristrike://wallet/payment/${result}`);
  if (uuidPattern.test(bookingId)) {
    appUrl.searchParams.set("booking_id", bookingId);
  }
  if (uuidPattern.test(paymentRecordId)) {
    appUrl.searchParams.set("payment_record_id", paymentRecordId);
  }
  const appUrlString = appUrl.toString();
  console.info(
    `[PayMongo] payment return result=${result} booking=${
      uuidPattern.test(bookingId) ? bookingId : "missing"
    }`,
  );
  // Supabase's hosted Edge gateway deliberately renders HTML responses from
  // the default project domain as text/plain with a sandbox CSP. Redirecting
  // directly to the registered Android custom scheme avoids exposing raw HTML
  // and lets Chrome hand control back to TourisTrike.
  return new Response(null, {
    status: 302,
    headers: {
      "Location": appUrlString,
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
    },
  });
});
