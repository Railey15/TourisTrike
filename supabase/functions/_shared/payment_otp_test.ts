import { paymentCodeHash } from "./payment_otp.ts";

Deno.test("payment code proof is bound to the user, booking, and stage", async () => {
  const hash = (user: string, booking: string, stage: string, code: string) =>
    paymentCodeHash("server-only-secret-with-sufficient-length", user,
      booking, stage, code);
  const original = await hash("tourist-a", "booking-a", "down_payment", "123456");
  if (original.length !== 64 ||
      original === await hash("tourist-b", "booking-a", "down_payment", "123456") ||
      original === await hash("tourist-a", "booking-b", "down_payment", "123456") ||
      original === await hash("tourist-a", "booking-a", "remaining_balance", "123456") ||
      original === await hash("tourist-a", "booking-a", "down_payment", "123457")) {
    throw new Error("payment code was not scoped to its obligation");
  }
});
