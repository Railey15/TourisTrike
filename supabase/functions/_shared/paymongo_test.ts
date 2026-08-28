import {
  assert,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { verifyPayMongoSignature } from "./paymongo.ts";

const encoder = new TextEncoder();

async function sign(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, encoder.encode(value)),
  );
  return [...bytes]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("verifies PayMongo t/te test-mode signature over timestamp.raw", async () => {
  const secret = "whsec_test";
  const rawBody = '{"data":{"id":"evt_test"}}';
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const signature = await sign(secret, `${timestamp}.${rawBody}`);
  assert(
    await verifyPayMongoSignature({
      rawBody,
      signatureHeader: `t=${timestamp},te=${signature},li=`,
      webhookSecret: secret,
      livemode: false,
    }),
  );
});

Deno.test("rejects a tampered structured webhook body", async () => {
  const secret = "whsec_test";
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const signature = await sign(secret, `${timestamp}.{"ok":true}`);
  assertFalse(
    await verifyPayMongoSignature({
      rawBody: '{"ok":false}',
      signatureHeader: `t=${timestamp},te=${signature},li=`,
      webhookSecret: secret,
      livemode: false,
    }),
  );
});

Deno.test("supports PayMongo direct raw-body signature format", async () => {
  const secret = "whsec_test";
  const rawBody = '{"data":{"type":"checkout_session.payment.paid"}}';
  assert(
    await verifyPayMongoSignature({
      rawBody,
      signatureHeader: await sign(secret, rawBody),
      webhookSecret: secret,
      livemode: false,
    }),
  );
});
