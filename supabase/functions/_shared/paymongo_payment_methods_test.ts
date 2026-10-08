import {
  configuredPayMongoPaymentMethods,
  isPayMongoPaymentMethod,
  paymentFlow,
} from "./paymongo_payment_methods.ts";

Deno.test("all TourisTrike PayMongo methods are recognized", () => {
  for (const method of ["gcash", "paymaya", "qrph", "card"]) {
    if (!isPayMongoPaymentMethod(method)) {
      throw new Error(`Expected ${method} to be supported`);
    }
  }
  if (isPayMongoPaymentMethod("maya") || isPayMongoPaymentMethod("cash")) {
    throw new Error("Non-PayMongo identifiers must be rejected");
  }
});

Deno.test("configured allowlist ignores unsupported values", () => {
  const methods = configuredPayMongoPaymentMethods("gcash, qrph, bogus");
  if (methods.size !== 2 || !methods.has("gcash") || !methods.has("qrph")) {
    throw new Error("Unexpected configured method set");
  }
});

Deno.test("QR Ph exposes hosted QR state", () => {
  if (paymentFlow("qrph") !== "hosted_qr") {
    throw new Error("QR Ph must use the hosted QR state");
  }
  if (paymentFlow("card") !== "redirect") {
    throw new Error("Card must use redirect state");
  }
});
