import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { isExactSelectedDestinationOrder } from "./validation.mjs";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Content-Type": "application/json",
};
const reply = (status: number, code: string, extra = {}) =>
  new Response(JSON.stringify({ code, ...extra }), { status, headers });
const point = (value: unknown): value is [number, number] =>
  Array.isArray(value) && value.length === 2 &&
  value.every((n) => typeof n === "number" && Number.isFinite(n)) &&
  Math.abs(value[0]) <= 90 && Math.abs(value[1]) <= 180;
const stayOptions = new Set([15, 30, 45, 60, 90, 120, 150, 180]);

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers });
  if (request.method !== "POST") return reply(405, "METHOD_NOT_ALLOWED");
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const gemini = Deno.env.get("GEMINI_API_KEY") ?? "";
  if (!url || !anon || !service || !gemini) return reply(503, "AI_UNAVAILABLE");
  const bearer = request.headers.get("authorization")?.match(/^Bearer (.+)$/i)?.[1];
  if (!bearer) return reply(401, "AUTH_REQUIRED");
  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${bearer}` } },
    auth: { persistSession: false },
  });
  const { data: auth, error: authError } = await userClient.auth.getUser(bearer);
  if (authError || !auth.user) return reply(401, "AUTH_REQUIRED");
  const admin = createClient(url, service, { auth: { persistSession: false } });
  const { data: profile } = await admin.from("profiles").select("role")
    .eq("id", auth.user.id).maybeSingle();
  if (profile?.role !== "tourist") return reply(403, "TOURIST_REQUIRED");

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return reply(400, "INVALID_INPUT"); }
  const destinations = body.destinations;
  const legs = body.current_route_legs;
  const ids = Array.isArray(destinations)
    ? destinations.map((d) => d?.id) : [];
  if (!Number.isSafeInteger(body.package_id) || Number(body.package_id) < 1 ||
      !point(body.pickup) || !point(body.dropoff) ||
      !Number.isInteger(body.pickup_minutes) ||
      Number(body.pickup_minutes) < 300 || Number(body.pickup_minutes) >= 1020 ||
      !Array.isArray(destinations) || destinations.length < 3 ||
      destinations.length > 6 || new Set(ids).size !== ids.length ||
      !destinations.every((d) => typeof d?.id === "string" &&
        d.id.length > 0 && d.id.length <= 150 &&
        typeof d.name === "string" && d.name.length <= 150 &&
        point(d.coordinates) && stayOptions.has(d.stay_minutes) &&
        stayOptions.has(d.recommended_stay_minutes)) ||
      !Array.isArray(legs) || legs.length !== destinations.length + 1 ||
      !legs.every((leg) => Number.isInteger(leg?.duration_minutes) &&
        leg.duration_minutes >= 0 && Number.isInteger(leg?.distance_meters) &&
        leg.distance_meters >= 0)) return reply(400, "INVALID_INPUT");
  const { data: pkg } = await admin.from("tour_packages")
    .select("id,status,visibility_status").eq("id", body.package_id).maybeSingle();
  if (!pkg || pkg.status !== "published" || pkg.visibility_status !== "visible") {
    return reply(404, "PACKAGE_UNAVAILABLE");
  }

  const prompt = {
    task: "Recommend a practical destination order. Return JSON with ordered_destination_ids (an array of every given ID exactly once), explanation (a short string), and stay_recommendations (an optional array of {destination_id, minutes}). Never add or remove a destination. Use coordinates and the supplied current route legs as context. Travel times for alternative orders will be calculated by Google Maps after your response. Do not state exact time savings, distances, opening hours, availability, or other unsupported facts. Stay recommendations must use the provided recommended stay or current stay and allowed minutes.",
    pickup: body.pickup,
    dropoff: body.dropoff,
    pickup_minutes: body.pickup_minutes,
    destinations,
    current_route_legs: legs,
  };
  try {
    const model = Deno.env.get("GEMINI_ITINERARY_MODEL") ?? "gemini-3.5-flash";
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": gemini },
        body: JSON.stringify({
          contents: [{ parts: [{ text: JSON.stringify(prompt) }] }],
          generationConfig: {
            temperature: 0.2,
            responseFormat: {
              text: {
                mimeType: "APPLICATION_JSON",
                schema: {
                  type: "object",
                  properties: {
                    ordered_destination_ids: {
                      type: "array",
                      items: { type: "string", enum: ids },
                      minItems: ids.length,
                      maxItems: ids.length,
                    },
                    explanation: { type: "string" },
                    stay_recommendations: {
                      type: "array",
                      items: {
                        type: "object",
                        properties: {
                          destination_id: { type: "string", enum: ids },
                          minutes: { type: "integer", enum: [...stayOptions] },
                        },
                        required: ["destination_id", "minutes"],
                      },
                    },
                  },
                  required: ["ordered_destination_ids", "explanation"],
                },
              },
            },
          },
        }),
        signal: AbortSignal.timeout(20000),
      },
    );
    if (!response.ok) return reply(503, "AI_UNAVAILABLE");
    const generated = await response.json();
    const text = generated?.candidates?.[0]?.content?.parts?.[0]?.text;
    const suggestion = JSON.parse(text);
    const ordered = suggestion?.ordered_destination_ids;
    if (!isExactSelectedDestinationOrder(ordered, ids) ||
        typeof suggestion.explanation !== "string" ||
        !suggestion.explanation.trim() || suggestion.explanation.length > 500) {
      return reply(503, "AI_UNAVAILABLE");
    }
    // Explanations never carry unverified numbers or operating claims.
    const explanation = /\d|\b(open|closed|available|unavailable|hours?)\b/i
      .test(suggestion.explanation)
      ? "This order may reduce backtracking. Compare Google Maps timings before applying it."
      : suggestion.explanation.trim();
    const stays = Array.isArray(suggestion.stay_recommendations)
      ? suggestion.stay_recommendations.filter((item: Record<string, unknown>) =>
        ids.includes(item?.destination_id) && stayOptions.has(Number(item?.minutes)))
        .map((item: Record<string, unknown>) => ({
          destination_id: item.destination_id, minutes: item.minutes,
        })) : [];
    return reply(200, "OK", {
      ordered_destination_ids: ordered,
      explanation,
      stay_recommendations: stays,
    });
  } catch {
    return reply(503, "AI_UNAVAILABLE");
  }
});
