import {
  hasDefensibleMunicipalityRelevance,
  mergePexelsSuggestions,
  municipalityQueries,
  parsePexelsResponse,
  pexelsConfigurationWarning,
  suggestionLimitFromPayload,
} from "./pexels.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

function pexelsPayload(
  alt: string,
  slug: string,
  { width = 2400, height = 1350 } = {},
) {
  return {
    photos: [{
      id: 42,
      width,
      height,
      url: `https://www.pexels.com/photo/${slug}/`,
      photographer: "Ana",
      alt,
      src: {
        landscape: "https://images.pexels.com/photos/42/cover.jpeg",
      },
    }],
  };
}

Deno.test("queries stay municipality-specific without broad fallbacks", () => {
  const baliwag = municipalityQueries("Baliwag", "Bulacan", "city");
  assert(
    baliwag.includes("Baliwag City Bulacan Philippines"),
    "city variant",
  );
  assert(
    baliwag.every((query) => query.includes("Baliwag")),
    "every query must contain the municipality",
  );
  assert(
    !baliwag.includes("Bulacan Philippines tourism"),
    "broad province fallback removed",
  );

  const bustos = municipalityQueries("Bustos", "Bulacan", "municipality");
  assert(
    bustos.every((query) => query.includes("Bustos")),
    "municipality query remains scoped",
  );
  assert(
    !bustos.some((query) => query.includes("Bustos City")),
    "municipalities do not get a false city label",
  );
});

Deno.test("Baliwag City landmark metadata is accepted", () => {
  const parsed = parsePexelsResponse(
    pexelsPayload(
      "Baliwag City landmark in Bulacan",
      "baliwag-city-landmark-42",
    ),
    0,
    "Baliwag",
  );
  assert(parsed.length === 1, "Baliwag landmark should be accepted");
  assert(parsed[0].attribution === "Photo by Ana on Pexels", "attribution");
});

Deno.test("Baliwag, Bulacan metadata is accepted", () => {
  const parsed = parsePexelsResponse(
    pexelsPayload("Baliwag, Bulacan heritage plaza", "baliwag-bulacan-plaza"),
    1,
    "Baliwag City",
  );
  assert(parsed.length === 1, "Baliwag, Bulacan should be accepted");
});

for (
  const [label, alt, slug] of [
    ["Cebu City", "Cebu City, Philippines skyline", "cebu-city-skyline"],
    ["Ilocos Region", "Ilocos Region, Philippines", "ilocos-region"],
    ["Bustos", "Bustos, Bulacan public plaza", "bustos-bulacan-plaza"],
    ["Malolos", "Malolos City, Bulacan landmark", "malolos-landmark"],
    ["Manila", "Manila, Philippines city view", "manila-city-view"],
    ["Baguio", "Baguio City park", "baguio-city-park"],
  ]
) {
  Deno.test(`${label} metadata is rejected for Baliwag`, () => {
    const parsed = parsePexelsResponse(
      pexelsPayload(alt, slug),
      0,
      "Baliwag",
    );
    assert(parsed.length === 0, `${label} must not be offered for Baliwag`);
  });
}

Deno.test("conflicting location is rejected even when target is also named", () => {
  assert(
    !hasDefensibleMunicipalityRelevance(
      { alt: "Travel from Baliwag to Cebu City, Philippines" },
      "Baliwag",
    ),
    "conflicting Cebu evidence wins",
  );
});

Deno.test("generic Philippines metadata without Baliwag evidence is rejected", () => {
  const parsed = parsePexelsResponse(
    pexelsPayload(
      "Beautiful Philippines landscape",
      "beautiful-philippines-landscape",
    ),
    0,
    "Baliwag",
  );
  assert(parsed.length === 0, "generic Philippines image must be excluded");
});

Deno.test("Bustos metadata is accepted only for Bustos", () => {
  const payload = pexelsPayload(
    "Bustos Bulacan municipal landmark",
    "bustos-bulacan-landmark",
  );
  assert(
    parsePexelsResponse(payload, 0, "Bustos").length === 1,
    "Bustos evidence accepted",
  );
  assert(
    parsePexelsResponse(payload, 0, "Baliwag").length === 0,
    "Bustos evidence rejected for Baliwag",
  );
});

Deno.test("Baliwag and generic Bulacan metadata are rejected for Bustos", () => {
  assert(
    parsePexelsResponse(
      pexelsPayload("Baliwag Bulacan plaza", "baliwag-bulacan-plaza"),
      0,
      "Bustos",
    ).length === 0,
    "Baliwag rejected for Bustos",
  );
  assert(
    parsePexelsResponse(
      pexelsPayload("Bulacan tourism landscape", "bulacan-tourism"),
      0,
      "Bustos",
    ).length === 0,
    "province-only evidence rejected",
  );
});

Deno.test("portrait and promotional results remain excluded", () => {
  assert(
    parsePexelsResponse(
      pexelsPayload("Baliwag City park", "baliwag-city-park", {
        width: 800,
        height: 1200,
      }),
      0,
      "Baliwag",
    ).length === 0,
    "portrait removed",
  );
  assert(
    parsePexelsResponse(
      pexelsPayload("Baliwag restaurant promotional poster", "baliwag-poster"),
      0,
      "Baliwag",
    ).length === 0,
    "promotional graphic removed",
  );
});

Deno.test("fewer than five and zero trustworthy results are allowed", () => {
  const one = parsePexelsResponse(
    pexelsPayload("Baliwag Bulacan heritage park", "baliwag-heritage-park"),
    0,
    "Baliwag",
  );
  const unrelated = parsePexelsResponse(
    pexelsPayload("Beautiful Philippines landscape", "philippines-landscape"),
    0,
    "Baliwag",
  );
  assert(mergePexelsSuggestions([one], 5).length === 1, "one is allowed");
  assert(
    mergePexelsSuggestions([unrelated], 5).length === 0,
    "zero is allowed",
  );
});

Deno.test("duplicates are removed", () => {
  const parsed = parsePexelsResponse(
    pexelsPayload("Baliwag Bulacan landmark", "baliwag-landmark"),
    0,
    "Baliwag",
  );
  assert(mergePexelsSuggestions([parsed, parsed]).length === 1, "deduplicated");
});

Deno.test("missing API key produces a non-fatal configuration warning", () => {
  assert(pexelsConfigurationWarning("").includes("not configured"), "warning");
  assert(pexelsConfigurationWarning("configured-key") === "", "configured");
});

Deno.test("remaining-slot request is safely clamped", () => {
  assert(suggestionLimitFromPayload({ limit: 3 }) === 3, "requested slots");
  assert(suggestionLimitFromPayload({ limit: 99 }) === 5, "maximum slots");
  assert(suggestionLimitFromPayload({ limit: -2 }) === 1, "minimum slots");
});
