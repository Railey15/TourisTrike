// Single source of truth for PayMongo's Paymongo-Signature verification —
// used by both paymongo-payment-webhook and paymongo-transfer-webhook so
// there's exactly one place implementing the HMAC check, not two copies
// that can drift.
//
// Header shape: "t=<timestamp>,te=<test_signature>,li=<live_signature>".
// Signed message is "{timestamp}.{raw_body}", HMAC-SHA256 with the
// webhook's secret key. MUST run against the raw body bytes before any
// JSON parsing/re-serialization — that's why every caller reads
// `await req.text()` first, never `await req.json()`.

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function verifyPaymongoSignature(
  rawBody: string,
  signatureHeader: string | null,
  secret: string,
): Promise<boolean> {
  if (!secret || !signatureHeader) return false;

  const parts = Object.fromEntries(
    signatureHeader.split(",").map((kv) => {
      const [k, v] = kv.split("=");
      return [k?.trim(), v?.trim()];
    }),
  );
  const timestamp = parts["t"];
  const candidates = [parts["te"], parts["li"]].filter(Boolean) as string[];
  if (!timestamp || candidates.length === 0) return false;

  const expected = await hmacSha256Hex(secret, `${timestamp}.${rawBody}`);
  return candidates.some((c) => timingSafeEqual(c, expected));
}
