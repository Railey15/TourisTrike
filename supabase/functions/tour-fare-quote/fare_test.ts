import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { calculateRouteFareAdjustment } from "./fare.ts";

Deno.test("custom route increase follows the configured fare per km", () => {
  assertEquals(calculateRouteFareAdjustment(50, 40, 0, 5000, 7500, 800), {
    surcharge: 100,
    unitPrice: 900,
  });
  assertEquals(calculateRouteFareAdjustment(50, 60, 0, 5000, 7500, 800), {
    surcharge: 150,
    unitPrice: 950,
  });
});

Deno.test("minimum fare and shorter route preserve the package price", () => {
  assertEquals(calculateRouteFareAdjustment(50, 40, 300, 5000, 6000, 800), {
    surcharge: 0,
    unitPrice: 800,
  });
  assertEquals(calculateRouteFareAdjustment(50, 40, 0, 5000, 3000, 800), {
    surcharge: 0,
    unitPrice: 800,
  });
});
