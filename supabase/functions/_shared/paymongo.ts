const encoder = new TextEncoder();

function toHex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacSha256(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return toHex(await crypto.subtle.sign("HMAC", key, encoder.encode(value)));
}

function constantTimeEqual(left: string, right: string): boolean {
  const a = encoder.encode(left.toLowerCase());
  const b = encoder.encode(right.toLowerCase());
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let index = 0; index < length; index++) {
    difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return difference === 0;
}

export async function verifyPayMongoSignature(params: {
  rawBody: string;
  signatureHeader: string;
  webhookSecret: string;
  livemode: boolean;
  toleranceSeconds?: number;
}): Promise<boolean> {
  const {
    rawBody,
    signatureHeader,
    webhookSecret,
    livemode,
    toleranceSeconds = 300,
  } = params;
  if (!signatureHeader || !webhookSecret) return false;

  // PayMongo's endpoint-management guide documents t/te/li and signs
  // `${timestamp}.${rawBody}`. The newer generic guide shows a direct raw-body
  // signature. Accept both official formats during their documentation/API
  // transition, while always using HMAC-SHA256 and constant-time comparison.
  if (signatureHeader.includes("t=") && signatureHeader.includes(",")) {
    const parts = Object.fromEntries(
      signatureHeader.split(",").map((part) => {
        const [key, ...value] = part.trim().split("=");
        return [key, value.join("=")];
      }),
    );
    const timestamp = Number(parts.t);
    const supplied = livemode ? parts.li : parts.te;
    if (!Number.isFinite(timestamp) || !supplied) return false;
    if (
      Math.abs(Math.floor(Date.now() / 1000) - timestamp) > toleranceSeconds
    ) {
      return false;
    }
    const expected = await hmacSha256(
      webhookSecret,
      `${parts.t}.${rawBody}`,
    );
    return constantTimeEqual(expected, supplied);
  }

  const expected = await hmacSha256(webhookSecret, rawBody);
  return constantTimeEqual(expected, signatureHeader.trim());
}

export async function sha256(value: string): Promise<string> {
  return toHex(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
}

export function basicAuth(secretKey: string): string {
  return `Basic ${btoa(`${secretKey}:`)}`;
}
