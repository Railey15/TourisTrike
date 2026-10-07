import { checkoutHasOnlyFailedPayments } from "./paymongo.ts";

function assertEqual(actual: boolean, expected: boolean, scenario: string) {
  if (actual !== expected) {
    throw new Error(`${scenario}: expected ${expected}, got ${actual}`);
  }
}

Deno.test("checkout recovery permits no payments or only failed attempts", () => {
  assertEqual(checkoutHasOnlyFailedPayments([]), true, "unused checkout");
  assertEqual(
    checkoutHasOnlyFailedPayments([
      { attributes: { status: "failed" } },
      { attributes: { status: "failed" } },
    ]),
    true,
    "failed attempts",
  );
});

Deno.test("checkout recovery blocks paid, pending, and unknown outcomes", () => {
  for (const status of ["paid", "pending", "processing", undefined]) {
    assertEqual(
      checkoutHasOnlyFailedPayments([
        { attributes: { status: "failed" } },
        { attributes: { status } },
      ]),
      false,
      String(status),
    );
  }
  assertEqual(
    checkoutHasOnlyFailedPayments(null),
    false,
    "missing payment list",
  );
  assertEqual(
    checkoutHasOnlyFailedPayments([null]),
    false,
    "malformed payment",
  );
});
