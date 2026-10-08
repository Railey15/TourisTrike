export const PAYMONGO_PAYMENT_METHODS = [
  "gcash",
  "paymaya",
  "qrph",
  "card",
] as const;

export type PayMongoPaymentMethod = typeof PAYMONGO_PAYMENT_METHODS[number];

export function isPayMongoPaymentMethod(
  value: unknown,
): value is PayMongoPaymentMethod {
  return typeof value === "string" &&
    PAYMONGO_PAYMENT_METHODS.includes(value as PayMongoPaymentMethod);
}

export function configuredPayMongoPaymentMethods(
  raw: string | undefined,
): ReadonlySet<PayMongoPaymentMethod> {
  const configured = (raw ?? "gcash,paymaya,qrph,card")
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(isPayMongoPaymentMethod);
  return new Set(configured);
}

export function paymentFlow(method: PayMongoPaymentMethod): string {
  return method === "qrph" ? "hosted_qr" : "redirect";
}
