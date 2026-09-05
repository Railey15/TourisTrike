import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GOOGLE_MAPS_API_KEY = (Deno.env.get("GOOGLE_MAPS_API_KEY") ?? "").trim();
const SIGNING_SECRET = (
  Deno.env.get("GOOGLE_MAPS_PROXY_SIGNING_SECRET") ?? ""
).trim();
const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").trim();
const SUPABASE_ANON_KEY = (Deno.env.get("SUPABASE_ANON_KEY") ?? "").trim();

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

type Operation =
  | "textSearch"
  | "nearbySearch"
  | "details"
  | "autocomplete"
  | "geocode";

const operationConfig: Record<
  Operation,
  { path: string; allowed: ReadonlySet<string> }
> = {
  textSearch: {
    path: "/maps/api/place/textsearch/json",
    allowed: new Set(["query", "location", "radius", "region"]),
  },
  nearbySearch: {
    path: "/maps/api/place/nearbysearch/json",
    allowed: new Set(["location", "radius", "keyword", "region", "type"]),
  },
  details: {
    path: "/maps/api/place/details/json",
    allowed: new Set(["place_id", "fields", "region", "language"]),
  },
  autocomplete: {
    path: "/maps/api/place/autocomplete/json",
    allowed: new Set(["input", "components", "language", "location", "radius"]),
  },
  geocode: {
    path: "/maps/api/geocode/json",
    allowed: new Set(["latlng", "language", "region"]),
  },
};

function safeParameters(
  operation: Operation,
  input: unknown,
): URLSearchParams | null {
  if (!input || typeof input !== "object" || Array.isArray(input)) return null;
  const params = new URLSearchParams();
  for (const [key, rawValue] of Object.entries(input)) {
    if (!operationConfig[operation].allowed.has(key)) return null;
    if (typeof rawValue !== "string" || rawValue.length > 700) return null;
    params.set(key, rawValue);
  }
  if (
    (operation === "textSearch" && !params.get("query")) ||
    (operation === "nearbySearch" && !params.get("location")) ||
    (operation === "details" && !params.get("place_id")) ||
    (operation === "autocomplete" && !params.get("input")) ||
    (operation === "geocode" && !params.get("latlng"))
  ) return null;
  params.set("key", GOOGLE_MAPS_API_KEY);
  return params;
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

async function signature(value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(SIGNING_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const bytes = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(value),
  );
  return base64Url(new Uint8Array(bytes));
}

function sameSignature(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

function functionUrl(): string {
  return `${SUPABASE_URL.replace(/\/$/, "")}/functions/v1/google-places`;
}

async function photoProxyUrl(photoReference: string): Promise<string> {
  const maxWidth = 900;
  const signedValue = `photo:${photoReference}:${maxWidth}`;
  const url = new URL(functionUrl());
  url.searchParams.set("resource", "photo");
  url.searchParams.set("photo_reference", photoReference);
  url.searchParams.set("maxwidth", String(maxWidth));
  url.searchParams.set("signature", await signature(signedValue));
  return url.toString();
}

async function staticMapProxyUrl(lat: number, lng: number): Promise<string> {
  const latitude = lat.toFixed(6);
  const longitude = lng.toFixed(6);
  const zoom = 15;
  const signedValue = `static-map:${latitude}:${longitude}:${zoom}`;
  const url = new URL(functionUrl());
  url.searchParams.set("resource", "static-map");
  url.searchParams.set("lat", latitude);
  url.searchParams.set("lng", longitude);
  url.searchParams.set("zoom", String(zoom));
  url.searchParams.set("signature", await signature(signedValue));
  return url.toString();
}

async function decoratePlace(raw: unknown): Promise<unknown> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return raw;
  const place = { ...(raw as Record<string, unknown>) };
  const photos = Array.isArray(place.photos) ? place.photos : [];
  const firstPhoto = photos[0];
  if (firstPhoto && typeof firstPhoto === "object") {
    const photoReference = String(
      (firstPhoto as Record<string, unknown>).photo_reference ?? "",
    ).trim();
    if (photoReference) place._proxy_image_url = await photoProxyUrl(photoReference);
  }
  const geometry = place.geometry as Record<string, unknown> | undefined;
  const location = geometry?.location as Record<string, unknown> | undefined;
  const lat = Number(location?.lat);
  const lng = Number(location?.lng);
  if (Number.isFinite(lat) && Number.isFinite(lng)) {
    place._proxy_static_map_url = await staticMapProxyUrl(lat, lng);
  }
  return place;
}

async function decorateGoogleBody(
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const decorated = { ...body };
  if (Array.isArray(body.results)) {
    decorated.results = await Promise.all(body.results.map(decoratePlace));
  }
  if (body.result) decorated.result = await decoratePlace(body.result);
  return decorated;
}

function googleFailure(body: Record<string, unknown>, httpStatus: number): Response | null {
  const status = String(body.status ?? "");
  if (httpStatus === 429 || status === "OVER_QUERY_LIMIT") {
    return json(
      { error: "RATE_LIMITED", message: "Google Places request limit was reached. Please retry shortly." },
      429,
    );
  }
  if (httpStatus === 401 || httpStatus === 403 || status === "REQUEST_DENIED") {
    return json(
      { error: "GOOGLE_UNAUTHORIZED", message: "Google Places rejected the server API key or its API restrictions." },
      403,
    );
  }
  if (status === "INVALID_REQUEST") {
    return json({ error: "INVALID_REQUEST", message: "Google Places rejected this request." }, 400);
  }
  if (httpStatus < 200 || httpStatus >= 300 || (status !== "OK" && status !== "ZERO_RESULTS")) {
    return json({ error: "UPSTREAM_FAILURE", message: "Google Places is unavailable right now." }, 502);
  }
  return null;
}

async function proxyImage(requestUrl: URL): Promise<Response> {
  if (!GOOGLE_MAPS_API_KEY || !SIGNING_SECRET) {
    return json({ error: "NOT_CONFIGURED", message: "Google media proxy is not configured." }, 503);
  }
  const resource = requestUrl.searchParams.get("resource") ?? "";
  const suppliedSignature = requestUrl.searchParams.get("signature") ?? "";
  let upstream: URL;
  let signedValue: string;

  if (resource === "photo") {
    const photoReference = (requestUrl.searchParams.get("photo_reference") ?? "").trim();
    const maxWidth = Number(requestUrl.searchParams.get("maxwidth") ?? "900");
    if (!photoReference || photoReference.length > 1000 || !Number.isInteger(maxWidth) || maxWidth < 200 || maxWidth > 1200) {
      return json({ error: "INVALID_REQUEST", message: "Invalid photo request." }, 400);
    }
    signedValue = `photo:${photoReference}:${maxWidth}`;
    upstream = new URL("https://maps.googleapis.com/maps/api/place/photo");
    upstream.searchParams.set("photo_reference", photoReference);
    upstream.searchParams.set("maxwidth", String(maxWidth));
  } else if (resource === "static-map") {
    const lat = Number(requestUrl.searchParams.get("lat"));
    const lng = Number(requestUrl.searchParams.get("lng"));
    const zoom = Number(requestUrl.searchParams.get("zoom") ?? "15");
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < 4 || lat > 22 || lng < 115 || lng > 130 || !Number.isInteger(zoom) || zoom < 10 || zoom > 18) {
      return json({ error: "INVALID_REQUEST", message: "Invalid map request." }, 400);
    }
    const latitude = lat.toFixed(6);
    const longitude = lng.toFixed(6);
    signedValue = `static-map:${latitude}:${longitude}:${zoom}`;
    const marker = `${latitude},${longitude}`;
    upstream = new URL("https://maps.googleapis.com/maps/api/staticmap");
    upstream.searchParams.set("center", marker);
    upstream.searchParams.set("zoom", String(zoom));
    upstream.searchParams.set("size", "640x420");
    upstream.searchParams.set("scale", "2");
    upstream.searchParams.set("maptype", "roadmap");
    upstream.searchParams.set("markers", `color:red|${marker}`);
  } else {
    return json({ error: "INVALID_REQUEST", message: "Unknown media resource." }, 400);
  }

  const expectedSignature = await signature(signedValue);
  if (!suppliedSignature || !sameSignature(suppliedSignature, expectedSignature)) {
    return json({ error: "INVALID_SIGNATURE", message: "This media URL is not authorized." }, 403);
  }

  upstream.searchParams.set("key", GOOGLE_MAPS_API_KEY);
  let response: Response;
  try {
    response = await fetch(upstream, { redirect: "follow" });
  } catch {
    return json({ error: "UPSTREAM_NETWORK", message: "Google media could not be reached." }, 502);
  }
  const contentType = response.headers.get("content-type") ?? "";
  if (!response.ok || !contentType.startsWith("image/")) {
    return json(
      { error: response.status === 429 ? "RATE_LIMITED" : "MEDIA_UPSTREAM_FAILURE", message: "Google media is unavailable." },
      response.status === 429 ? 429 : 502,
    );
  }
  return new Response(response.body, {
    status: 200,
    headers: {
      ...corsHeaders,
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=86400, stale-while-revalidate=604800",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const requestUrl = new URL(request.url);
  if (request.method === "GET") return proxyImage(requestUrl);
  if (request.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);

  if (!GOOGLE_MAPS_API_KEY || !SIGNING_SECRET || !SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return json({ error: "NOT_CONFIGURED", message: "Google Places is not configured on the server." }, 503);
  }
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return json({ error: "UNAUTHENTICATED", message: "Sign in to use Google Places." }, 401);
  }
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await client.auth.getUser();
  if (userError || !userData.user) {
    return json({ error: "UNAUTHENTICATED", message: "Sign in to use Google Places." }, 401);
  }

  let input: Record<string, unknown>;
  try {
    input = await request.json();
  } catch {
    return json({ error: "INVALID_REQUEST", message: "Expected a JSON request." }, 400);
  }
  const operation = String(input.operation ?? "") as Operation;
  if (!(operation in operationConfig)) {
    return json({ error: "INVALID_REQUEST", message: "Unsupported Google Places operation." }, 400);
  }
  const params = safeParameters(operation, input.parameters);
  if (!params) return json({ error: "INVALID_REQUEST", message: "Invalid Google Places parameters." }, 400);

  const upstream = new URL(`https://maps.googleapis.com${operationConfig[operation].path}`);
  upstream.search = params.toString();
  let googleResponse: Response;
  try {
    googleResponse = await fetch(upstream);
  } catch {
    return json({ error: "UPSTREAM_NETWORK", message: "Could not reach Google Places." }, 502);
  }
  let googleBody: Record<string, unknown>;
  try {
    googleBody = await googleResponse.json();
  } catch {
    return json({ error: "UPSTREAM_FAILURE", message: "Google Places returned an unreadable response." }, 502);
  }
  const failure = googleFailure(googleBody, googleResponse.status);
  if (failure) return failure;
  return json(await decorateGoogleBody(googleBody));
});
