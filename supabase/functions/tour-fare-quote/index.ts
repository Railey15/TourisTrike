import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { calculateRouteFareAdjustment } from "./fare.ts";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Content-Type": "application/json",
};
const reply = (status: number, code: string, extra: Record<string, unknown> = {}) =>
  new Response(JSON.stringify({ code, ...extra }), { status, headers });
type Point = [number, number];
const validPoint = (value: unknown): value is Point =>
  Array.isArray(value) && value.length === 2 &&
  value.every((n) => typeof n === "number" && Number.isFinite(n)) &&
  value[0] >= -90 && value[0] <= 90 && value[1] >= -180 && value[1] <= 180;

async function routeMeters(points: Point[], apiKey: string): Promise<number> {
  const coords = (point: Point) => `${point[0]},${point[1]}`;
  const url = new URL("https://maps.googleapis.com/maps/api/directions/json");
  url.searchParams.set("origin", coords(points[0]));
  url.searchParams.set("destination", coords(points[points.length - 1]));
  url.searchParams.set("waypoints", points.slice(1, -1).map(coords).join("|"));
  url.searchParams.set("mode", "driving");
  url.searchParams.set("key", apiKey);
  const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error("DIRECTIONS_UNAVAILABLE");
  const body = await response.json();
  const legs = body?.routes?.[0]?.legs;
  if (body?.status !== "OK" || !Array.isArray(legs) ||
      legs.length !== points.length - 1 ||
      !legs.every((leg: { distance?: { value?: number } }) =>
        Number.isFinite(leg?.distance?.value) && leg.distance!.value! >= 0)) {
    throw new Error("DIRECTIONS_UNAVAILABLE");
  }
  return legs.reduce((sum: number, leg: { distance: { value: number } }) =>
    sum + leg.distance.value, 0);
}

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers });
  if (request.method !== "POST") return reply(405, "METHOD_NOT_ALLOWED");
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const mapsKey = Deno.env.get("GOOGLE_MAPS_API_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceKey || !mapsKey) {
    return reply(503, "QUOTE_NOT_CONFIGURED");
  }
  const bearer = request.headers.get("authorization")?.match(/^Bearer (.+)$/i)?.[1];
  if (!bearer) return reply(401, "AUTH_REQUIRED");
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${bearer}` } },
    auth: { persistSession: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser(bearer);
  if (authError || !authData.user) return reply(401, "AUTH_REQUIRED");
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });
  const { data: profile } = await admin.from("profiles").select("role")
    .eq("id", authData.user.id).maybeSingle();
  if (profile?.role !== "tourist") return reply(403, "TOURIST_REQUIRED");

  let input: Record<string, unknown>;
  try {
    input = await request.json();
  } catch {
    return reply(400, "INVALID_JSON");
  }
  const packageId = input?.packageId;
  const points = input?.points;
  if (!Number.isSafeInteger(packageId) || Number(packageId) < 1 ||
      !Array.isArray(points) || points.length < 5 || points.length > 8 ||
      !points.every(validPoint)) return reply(400, "INVALID_ROUTE");
  const route = points as Point[];
  const { data: pkg } = await admin.from("tour_packages")
    .select("id,city,submitted_by,status,visibility_status,estimated_budget,price_text,updated_at")
    .eq("id", packageId).maybeSingle();
  if (!pkg || pkg.status !== "published" || pkg.visibility_status !== "visible") {
    return reply(404, "PACKAGE_UNAVAILABLE");
  }
  const { data: office } = await admin.from("subtenant_details")
    .select("city,province,is_active").eq("id", pkg.submitted_by).maybeSingle();
  if (!office?.is_active || office.city?.trim().toLowerCase() !== pkg.city.trim().toLowerCase()) {
    return reply(409, "FARE_MATRIX_UNAVAILABLE");
  }
  const { data: matrixRows } = await admin.from("subtenant_fare_settings")
    .select("base_fare,fare_per_km,minimum_fare,updated_at")
    .eq("subtenant_id", pkg.submitted_by).eq("is_active", true)
    .eq("city", office.city);
  if (!matrixRows || matrixRows.length !== 1) return reply(409, "FARE_MATRIX_UNAVAILABLE");
  const matrix = matrixRows[0];
  const baseFare = Number(matrix.base_fare);
  const perKm = Number(matrix.fare_per_km);
  const minimum = Number(matrix.minimum_fare);
  if (![baseFare, perKm, minimum].every((n) => Number.isFinite(n) && n >= 0)) {
    return reply(409, "FARE_MATRIX_UNAVAILABLE");
  }
  const { data: area, error: areaError } = await admin.rpc("resolve_booking_service_area",
    { p_package_id: packageId });
  if (areaError || !area) return reply(409, "SERVICE_AREA_UNAVAILABLE");
  const covered = await Promise.all(route.map((point) => admin.rpc("service_area_covers", {
    g: area.geometry, latitude: point[0], longitude: point[1],
  })));
  if (covered.some((result) => result.error || result.data !== true)) {
    return reply(400, "LOCATION_OUTSIDE_SERVICE_AREA");
  }
  const { data: packageStops } = await admin.from("tour_package_spots")
    .select("spot_id,sort_order").eq("package_id", packageId)
    .order("sort_order", { ascending: true });
  const ids = (packageStops ?? []).map((row) => row.spot_id);
  // Published packages can contain fewer stops than the customized booking
  // minimum; the Tourist may add destinations to reach the booking minimum.
  if (ids.length < 1 || ids.length > 25) return reply(409, "PACKAGE_ROUTE_UNAVAILABLE");
  const { data: spotRows } = await admin.from("tourist_spots")
    .select("id,latitude,longitude").in("id", ids);
  const byId = new Map((spotRows ?? []).map((row) => [row.id, row]));
  const originalStops = ids.map((id) => byId.get(id));
  if (originalStops.some((spot) => !spot || !Number.isFinite(Number(spot.latitude)) ||
      !Number.isFinite(Number(spot.longitude)))) {
    return reply(409, "PACKAGE_ROUTE_UNAVAILABLE");
  }
  const originalRoute: Point[] = [route[0],
    ...originalStops.map((spot) => [Number(spot!.latitude), Number(spot!.longitude)] as Point),
    route[route.length - 1]];
  let customMeters: number;
  let originalMeters: number;
  try {
    [customMeters, originalMeters] = await Promise.all([
      routeMeters(route, mapsKey), routeMeters(originalRoute, mapsKey),
    ]);
  } catch {
    return reply(502, "DIRECTIONS_UNAVAILABLE");
  }
  const configuredBase = Number(pkg.estimated_budget);
  const fallback = pkg.price_text?.replaceAll(",", "").match(/(\d+(?:\.\d+)?)/)?.[1];
  const packagePrice = configuredBase > 0 ? configuredBase : Number(fallback ?? 0);
  if (!Number.isFinite(packagePrice) || packagePrice < 0) {
    return reply(409, "PACKAGE_PRICE_UNAVAILABLE");
  }
  const baseUnitPrice = Math.round((packagePrice + Number.EPSILON) * 100) / 100;
  const { unitPrice, surcharge } = calculateRouteFareAdjustment(
    baseFare, perKm, minimum, originalMeters, customMeters, baseUnitPrice,
  );
  const { data: quote, error: quoteError } = await admin
    .from("booking_custom_fare_quotes").insert({
      tourist_id: authData.user.id,
      package_id: packageId,
      route_points: route,
      route_distance_meters: customMeters,
      original_distance_meters: originalMeters,
      base_unit_price: baseUnitPrice,
      route_surcharge: surcharge,
      unit_price: unitPrice,
      fare_settings_updated_at: matrix.updated_at,
      package_updated_at: pkg.updated_at,
    }).select("id,expires_at").single();
  if (quoteError || !quote) return reply(503, "QUOTE_SAVE_FAILED");
  return reply(200, "OK", {
    quoteId: quote.id, expiresAt: quote.expires_at,
    unitPrice, surcharge, distanceKm: customMeters / 1000,
  });
});
