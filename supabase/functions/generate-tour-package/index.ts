// supabase/functions/generate-tour-package/index.ts

import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

type CandidateSpot = {
  id: string;
  name: string;
  category?: string | null;
  address?: string | null;
  description?: string | null;
};

type GeneratePackageRequest = {
  request: string;
  spotCount: number;
  municipality: string;
  preferences?: string | null;
  candidates: CandidateSpot[];
};

type GeminiPackageResult = {
  title: string;
  subtitle: string;
  description: string;
  category: string;
  selectedSpotIds: string[];
  orderedSpotIds?: string[];
  suggestedStayMinutes?: Record<string, number>;
};

const jsonHeaders = {
  "Content-Type": "application/json",
};

function errorResponse(message: string, status = 400) {
  return new Response(
    JSON.stringify({
      error: message,
    }),
    {
      status,
      headers: jsonHeaders,
    },
  );
}

function cleanJsonResponse(text: string): string {
  return text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}

function configuredClientKeys(): string[] {
  const keys = new Set<string>();
  const compatibleClientKey = Deno.env.get(
    "TOURISTRIKE_CLIENT_API_KEY",
  )?.trim();
  if (compatibleClientKey) keys.add(compatibleClientKey);

  const legacyAnonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim();
  if (legacyAnonKey) keys.add(legacyAnonKey);

  const publishableKeys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (publishableKeys) {
    try {
      const parsed = JSON.parse(publishableKeys);
      if (typeof parsed === "string" && parsed.trim()) {
        keys.add(parsed.trim());
      } else if (parsed && typeof parsed === "object") {
        for (const value of Object.values(parsed)) {
          if (typeof value === "string" && value.trim()) {
            keys.add(value.trim());
          }
        }
      }
    } catch {
      if (publishableKeys.trim()) keys.add(publishableKeys.trim());
    }
  }

  return [...keys];
}

function hasConfiguredClientKey(req: Request): boolean {
  const suppliedKey = req.headers.get("apikey")?.trim();
  return Boolean(
    suppliedKey && configuredClientKeys().includes(suppliedKey),
  );
}

export default {
  fetch: withSupabase(
    {
      // Client key compatibility is checked inside the handler so the current
      // Flutter legacy anon key and newer publishable keys are both supported.
      // GEMINI_API_KEY remains server-side only.
      auth: "none",
    },
    async (req, _ctx) => {
      try {
        if (req.method !== "POST") {
          return errorResponse("Method not allowed.", 405);
        }

        if (!hasConfiguredClientKey(req)) {
          return errorResponse("Unauthorized.", 401);
        }

        const geminiApiKey = Deno.env.get("GEMINI_API_KEY");

        if (!geminiApiKey) {
          console.error("GEMINI_API_KEY is not configured.");

          return errorResponse(
            "AI package generation is not configured.",
            500,
          );
        }

        const body = (await req.json()) as Partial<GeneratePackageRequest>;

        const requestText = body.request?.trim();
        const municipality = body.municipality?.trim();
        const preferences = body.preferences?.trim() || "";
        const spotCount = Number(body.spotCount);
        const candidates = Array.isArray(body.candidates)
          ? body.candidates
          : [];

        if (!requestText) {
          return errorResponse(
            "Please describe the package you want to create.",
          );
        }

        if (!municipality) {
          return errorResponse("Municipality is required.");
        }

        if (
          !Number.isInteger(spotCount) ||
          spotCount < 3 ||
          spotCount > 6
        ) {
          return errorResponse(
            "Spot count must be between 3 and 6.",
          );
        }

        if (candidates.length === 0) {
          return errorResponse(
            `No available tourist spots were found in ${municipality}.`,
          );
        }

        /*
         * IMPORTANT:
         * Gemini is ONLY allowed to choose IDs from this list.
         *
         * The Flutter/TourisTrike side should continue obtaining this
         * candidate list through the existing municipality-scoped
         * database/Google Places logic.
         */
        const validCandidates = candidates
          .filter(
            (spot) =>
              typeof spot?.id === "string" &&
              spot.id.trim().length > 0 &&
              typeof spot?.name === "string" &&
              spot.name.trim().length > 0,
          )
          .map((spot) => ({
            id: spot.id.trim(),
            name: spot.name.trim(),
            category: spot.category?.trim() || null,
            address: spot.address?.trim() || null,
            description: spot.description?.trim() || null,
          }));

        if (validCandidates.length === 0) {
          return errorResponse(
            "No valid candidate spots are available.",
          );
        }

        const requestedCount = Math.min(
          spotCount,
          validCandidates.length,
        );

        const candidateIds = new Set(
          validCandidates.map((spot) => spot.id),
        );

        const candidateText = validCandidates
          .map(
            (spot, index) =>
              `${index + 1}. ID: ${spot.id}
Name: ${spot.name}
Category: ${spot.category ?? "Unspecified"}
Address: ${spot.address ?? "Unspecified"}
Description: ${spot.description ?? "None"}`,
          )
          .join("\n\n");

        const prompt = `
You are the AI package-building assistant for TourisTrike.

The tourism officer wants to create a tourism package.

Municipality:
${municipality}

Request:
${requestText}

Requested number of spots:
${spotCount}

Preferences:
${preferences || "None"}

IMPORTANT RULES:

1. You may ONLY select destinations from the candidate list below.
2. NEVER invent a business, cafe, tourist attraction, place, or ID.
3. selectedSpotIds MUST contain only IDs exactly provided below.
4. Select at most ${requestedCount} spots.
5. Do not calculate fares, prices, route distance, or transportation fees.
6. TourisTrike calculates authoritative routes and fares separately.
7. Make the package title, subtitle, and description professional and tourist-friendly.
8. Keep the package relevant to the user's request.
9. If fewer appropriate destinations exist than requested, return only the appropriate available destinations.
10. Do not include markdown.

AVAILABLE REAL DESTINATIONS:

${candidateText}

Return ONLY valid JSON using exactly this structure:

{
  "title": "Package title",
  "subtitle": "Short tourist-friendly subtitle",
  "description": "Concise package description",
  "category": "Most appropriate package category",
  "selectedSpotIds": ["real-id-1", "real-id-2"],
  "orderedSpotIds": ["real-id-1", "real-id-2"],
  "suggestedStayMinutes": {
    "real-id-1": 60,
    "real-id-2": 60
  }
}
`.trim();

        const model =
          Deno.env.get("GEMINI_MODEL") || "gemini-3.5-flash-lite";

        const geminiResponse = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "x-goog-api-key": geminiApiKey,
            },
            body: JSON.stringify({
              contents: [
                {
                  role: "user",
                  parts: [
                    {
                      text: prompt,
                    },
                  ],
                },
              ],
              generationConfig: {
                temperature: 0.4,
                responseMimeType: "application/json",
              },
            }),
          },
        );

        if (!geminiResponse.ok) {
          const providerError = await geminiResponse.text();

          console.error(
            "Gemini API request failed:",
            geminiResponse.status,
            providerError,
          );

          return errorResponse(
            "AI package generation is temporarily unavailable.",
            502,
          );
        }

        const geminiData = await geminiResponse.json();

        const generatedText =
          geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;

        if (
          typeof generatedText !== "string" ||
          generatedText.trim().length === 0
        ) {
          console.error(
            "Gemini returned no usable package content.",
            geminiData,
          );

          return errorResponse(
            "AI returned an invalid package response.",
            502,
          );
        }

        let generated: GeminiPackageResult;

        try {
          generated = JSON.parse(
            cleanJsonResponse(generatedText),
          ) as GeminiPackageResult;
        } catch (error) {
          console.error(
            "Unable to parse Gemini JSON:",
            error,
            generatedText,
          );

          return errorResponse(
            "AI returned an invalid package format.",
            502,
          );
        }

        /*
         * SERVER-SIDE ALLOW-LIST VALIDATION
         *
         * Even if Gemini hallucinates an ID, it is removed here.
         */
        const selectedSpotIds = Array.from(
          new Set(
            (generated.selectedSpotIds ?? []).filter(
              (id): id is string =>
                typeof id === "string" &&
                candidateIds.has(id),
            ),
          ),
        ).slice(0, requestedCount);

        const orderedSpotIds = Array.from(
          new Set(
            (generated.orderedSpotIds ?? selectedSpotIds).filter(
              (id): id is string =>
                typeof id === "string" &&
                selectedSpotIds.includes(id),
            ),
          ),
        );

        // Ensure every selected spot appears in the order.
        for (const id of selectedSpotIds) {
          if (!orderedSpotIds.includes(id)) {
            orderedSpotIds.push(id);
          }
        }

        const suggestedStayMinutes: Record<string, number> = {};

        for (const id of selectedSpotIds) {
          const rawMinutes =
            generated.suggestedStayMinutes?.[id];

          const minutes =
            typeof rawMinutes === "number" &&
              Number.isFinite(rawMinutes)
              ? Math.round(rawMinutes)
              : 60;

          suggestedStayMinutes[id] = Math.max(
            15,
            Math.min(minutes, 240),
          );
        }

        /*
         * Safe fallback:
         * If Gemini returned no valid IDs, use valid candidates.
         *
         * These are STILL real allow-listed candidates.
         */
        if (selectedSpotIds.length === 0) {
          for (
            const spot of validCandidates.slice(0, requestedCount)
          ) {
            selectedSpotIds.push(spot.id);
            orderedSpotIds.push(spot.id);
            suggestedStayMinutes[spot.id] = 60;
          }
        }

        const selectedSpots = selectedSpotIds
          .map((id) =>
            validCandidates.find((spot) => spot.id === id)
          )
          .filter(Boolean);

        return Response.json({
          package: {
            title:
              generated.title?.trim() ||
              `${municipality} Tour Package`,

            subtitle:
              generated.subtitle?.trim() ||
              `Explore ${municipality}`,

            description:
              generated.description?.trim() ||
              `Discover selected destinations around ${municipality}.`,

            category:
              generated.category?.trim() ||
              "Tour",

            selectedSpotIds,
            orderedSpotIds,
            suggestedStayMinutes,
          },

          selectedSpots,

          meta: {
            requestedSpotCount: spotCount,
            generatedSpotCount: selectedSpotIds.length,
            availableCandidateCount: validCandidates.length,

            shortage:
              selectedSpotIds.length < spotCount,

            shortageMessage:
              selectedSpotIds.length < spotCount
                ? `Only ${selectedSpotIds.length} suitable spot${
                    selectedSpotIds.length === 1 ? "" : "s"
                  } were available for this package.`
                : null,

            aiAssisted: true,
          },
        });
      } catch (error) {
        console.error(
          "generate-tour-package unexpected error:",
          error,
        );

        return errorResponse(
          "Unable to generate the package right now.",
          500,
        );
      }
    },
  ),
};
