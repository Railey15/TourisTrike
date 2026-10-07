export async function paymentCodeHash(
  secret: string, userId: string, bookingId: string, stage: string, code: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" },
    false, ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC", key,
    new TextEncoder().encode(`${userId}:${bookingId}:${stage}:${code}`),
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}
