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
  "Access-Control-Max-Age": "86400",
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
  { allowed: ReadonlySet<string> }
> = {
  textSearch: {
    allowed: new Set(["query", "location", "radius", "region"]),
  },
  nearbySearch: {
    allowed: new Set(["location", "radius", "keyword", "region", "type"]),
  },
  details: {
    allowed: new Set(["place_id", "fields", "region", "language"]),
  },
  autocomplete: {
    allowed: new Set([
      "input",
      "components",
      "language",
      "location",
      "radius",
      "strictbounds",
    ]),
  },
  geocode: {
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
  return params;
}

const searchFieldMask = [
  "places.id",
  "places.displayName",
  "places.formattedAddress",
  "places.location",
  "places.rating",
  "places.userRatingCount",
  "places.photos",
  "places.types",
  "places.businessStatus",
].join(",");

const detailsFieldMask = [
  "id",
  "displayName",
  "formattedAddress",
  "location",
  "rating",
  "userRatingCount",
  "websiteUri",
  "nationalPhoneNumber",
  "editorialSummary",
  "regularOpeningHours.weekdayDescriptions",
  "addressComponents",
  "photos",
  "types",
  "businessStatus",
].join(",");

function locationCircle(params: URLSearchParams) {
  const parts = (params.get("location") ?? "").split(",");
  const latitude = Number(parts[0]);
  const longitude = Number(parts[1]);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  const requestedRadius = Number(params.get("radius") ?? "25000");
  const radius = Math.min(50000, Math.max(1, requestedRadius || 25000));
  return { center: { latitude, longitude }, radius };
}

function nearbyType(params: URLSearchParams): string {
  const value = (params.get("type") ?? params.get("keyword") ?? "")
    .trim().toLowerCase().replaceAll(" ", "_");
  return [
      "museum",
      "park",
      "church",
      "restaurant",
      "cafe",
      "tourist_attraction",
    ]
      .includes(value)
    ? value
    : "tourist_attraction";
}

function placesRequest(
  operation: Operation,
  params: URLSearchParams,
): { url: URL; init: RequestInit } {
  if (operation === "geocode") {
    const url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
    params.forEach((value, key) => url.searchParams.set(key, value));
    url.searchParams.set("key", GOOGLE_MAPS_API_KEY);
    return { url, init: { method: "GET" } };
  }

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "X-Goog-Api-Key": GOOGLE_MAPS_API_KEY,
  };
  const languageCode = params.get("language") ?? "en";
  const regionCode = (params.get("region") ?? "ph").toUpperCase();
  let url: URL;
  let body: Record<string, unknown> | undefined;
  if (operation === "textSearch") {
    url = new URL("https://places.googleapis.com/v1/places:searchText");
    headers["X-Goog-FieldMask"] = searchFieldMask;
    const circle = locationCircle(params);
    body = {
      textQuery: params.get("query") ?? "",
      languageCode,
      regionCode,
      pageSize: 20,
      ...(circle ? { locationBias: { circle } } : {}),
    };
  } else if (operation === "nearbySearch") {
    url = new URL("https://places.googleapis.com/v1/places:searchNearby");
    headers["X-Goog-FieldMask"] = searchFieldMask;
    const circle = locationCircle(params);
    body = {
      languageCode,
      regionCode,
      maxResultCount: 20,
      rankPreference: "POPULARITY",
      includedTypes: [nearbyType(params)],
      ...(circle ? { locationRestriction: { circle } } : {}),
    };
  } else if (operation === "autocomplete") {
    url = new URL("https://places.googleapis.com/v1/places:autocomplete");
    const circle = locationCircle(params);
    body = {
      input: params.get("input") ?? "",
      languageCode,
      regionCode,
      includedRegionCodes: ["ph"],
      ...(circle
        ? params.get("strictbounds") === "true"
          ? { locationRestriction: { circle } }
          : { locationBias: { circle } }
        : {}),
    };
  } else {
    const placeId = encodeURIComponent(params.get("place_id") ?? "");
    url = new URL(`https://places.googleapis.com/v1/places/${placeId}`);
    url.searchParams.set("languageCode", languageCode);
    url.searchParams.set("regionCode", regionCode);
    headers["X-Goog-FieldMask"] = detailsFieldMask;
  }
  return {
    url,
    init: {
      method: operation === "details" ? "GET" : "POST",
      headers,
      ...(body ? { body: JSON.stringify(body) } : {}),
    },
  };
}

function legacyPlace(raw: Record<string, unknown>): Record<string, unknown> {
  const displayName = raw.displayName as Record<string, unknown> | undefined;
  const location = raw.location as Record<string, unknown> | undefined;
  const editorial = raw.editorialSummary as Record<string, unknown> | undefined;
  const hours = raw.regularOpeningHours as Record<string, unknown> | undefined;
  const components = Array.isArray(raw.addressComponents)
    ? raw.addressComponents.map((item) => {
      const component = item as Record<string, unknown>;
      return {
        long_name: component.longText,
        short_name: component.shortText,
        types: component.types,
      };
    })
    : [];
  const photos = Array.isArray(raw.photos)
    ? raw.photos.map((item) => ({
      photo_reference: (item as Record<string, unknown>).name,
    }))
    : [];
  return {
    place_id: raw.id,
    name: displayName?.text,
    formatted_address: raw.formattedAddress,
    ...(location
      ? {
        geometry: {
          location: { lat: location.latitude, lng: location.longitude },
        },
      }
      : {}),
    rating: raw.rating,
    user_ratings_total: raw.userRatingCount,
    website: raw.websiteUri,
    formatted_phone_number: raw.nationalPhoneNumber,
    ...(editorial ? { editorial_summary: { overview: editorial.text } } : {}),
    ...(hours
      ? { opening_hours: { weekday_text: hours.weekdayDescriptions } }
      : {}),
    address_components: components,
    photos,
    types: raw.types,
    business_status: raw.businessStatus,
  };
}

function normalizePlacesBody(
  operation: Operation,
  body: Record<string, unknown>,
): Record<string, unknown> {
  if (operation === "geocode") return body;
  if (operation === "textSearch" || operation === "nearbySearch") {
    const places = Array.isArray(body.places) ? body.places : [];
    return {
      status: places.length ? "OK" : "ZERO_RESULTS",
      results: places.map((place) =>
        legacyPlace(place as Record<string, unknown>)
      ),
      ...(body.nextPageToken ? { next_page_token: body.nextPageToken } : {}),
    };
  }
  if (operation === "details") {
    return { status: "OK", result: legacyPlace(body) };
  }
  const suggestions = Array.isArray(body.suggestions) ? body.suggestions : [];
  const predictions = suggestions.flatMap((item) => {
    const suggestion = item as Record<string, unknown>;
    const prediction = suggestion.placePrediction as
      | Record<string, unknown>
      | undefined;
    const text = prediction?.text as Record<string, unknown> | undefined;
    return prediction?.placeId && text?.text
      ? [{ place_id: prediction.placeId, description: text.text }]
      : [];
  });
  return {
    status: predictions.length ? "OK" : "ZERO_RESULTS",
    predictions,
  };
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
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

async function decoratePlace(raw: unknown): Promise<unknown> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return raw;
  const place = { ...(raw as Record<string, unknown>) };
  const photos = Array.isArray(place.photos) ? place.photos : [];
  const firstPhoto = photos[0];
  if (firstPhoto && typeof firstPhoto === "object") {
    const photoReference = String(
      (firstPhoto as Record<string, unknown>).photo_reference ?? "",
    ).trim();
    if (photoReference) {
      place._proxy_image_url = await photoProxyUrl(photoReference);
    }
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

function googleFailure(
  body: Record<string, unknown>,
  httpStatus: number,
): Response | null {
  const error = body.error as Record<string, unknown> | undefined;
  const status = String(error?.status ?? body.status ?? "");
  const upstreamMessage = String(error?.message ?? body.error_message ?? "");
  const diagnostic = `${status} ${upstreamMessage}`.toLowerCase();
  if (
    httpStatus === 429 || status === "OVER_QUERY_LIMIT" ||
    diagnostic.includes("quota")
  ) {
    return json(
      {
        error: "RATE_LIMITED",
        message:
          "Google Places request limit was reached. Please retry shortly.",
      },
      429,
    );
  }
  if (diagnostic.includes("field mask")) {
    return json({
      error: "MISSING_FIELD_MASK",
      message: "Google Places rejected a missing or invalid field mask.",
    }, 400);
  }
  if (diagnostic.includes("billing")) {
    return json({
      error: "BILLING_REQUIRED",
      message:
        "Google Maps Platform billing is not available for this project.",
    }, 403);
  }
  if (
    diagnostic.includes("legacy api") ||
    diagnostic.includes("legacy endpoint")
  ) {
    return json({
      error: "LEGACY_ENDPOINT",
      message:
        "Google Places rejected a legacy endpoint. Update the deployed client or server.",
    }, 400);
  }
  if (
    diagnostic.includes("not enabled") ||
    diagnostic.includes("has not been used") ||
    diagnostic.includes("disabled")
  ) {
    return json({
      error: "API_NOT_ENABLED",
      message: "Places API (New) is not enabled for this project.",
    }, 403);
  }
  if (
    diagnostic.includes("api key not valid") ||
    diagnostic.includes("invalid api key")
  ) {
    return json({
      error: "INVALID_API_KEY",
      message: "Google Places rejected the configured server API key.",
    }, 403);
  }
  if (
    diagnostic.includes("referer") || diagnostic.includes("restriction") ||
    diagnostic.includes("not authorized")
  ) {
    return json({
      error: "API_RESTRICTION_MISMATCH",
      message:
        "The server API key restrictions do not allow this Places request.",
    }, 403);
  }
  if (httpStatus === 401 || httpStatus === 403 || status === "REQUEST_DENIED") {
    return json(
      {
        error: "GOOGLE_UNAUTHORIZED",
        message:
          "Google Places rejected the server API key or its API restrictions.",
      },
      403,
    );
  }
  if (status === "INVALID_REQUEST") {
    return json({
      error: "INVALID_REQUEST",
      message: "Google Places rejected this request.",
    }, 400);
  }
  if (
    httpStatus < 200 || httpStatus >= 300 ||
    (status && status !== "OK" && status !== "ZERO_RESULTS")
  ) {
    return json({
      error: "UPSTREAM_FAILURE",
      message: "Google Places is unavailable right now.",
    }, 502);
  }
  return null;
}

async function proxyImage(requestUrl: URL): Promise<Response> {
  if (!GOOGLE_MAPS_API_KEY || !SIGNING_SECRET) {
    return json({
      error: "NOT_CONFIGURED",
      message: "Google media proxy is not configured.",
    }, 503);
  }
  const resource = requestUrl.searchParams.get("resource") ?? "";
  const suppliedSignature = requestUrl.searchParams.get("signature") ?? "";
  let upstream: URL;
  let signedValue: string;

  if (resource === "photo") {
    const photoReference =
      (requestUrl.searchParams.get("photo_reference") ?? "").trim();
    const maxWidth = Number(requestUrl.searchParams.get("maxwidth") ?? "900");
    if (
      !photoReference || photoReference.length > 1000 ||
      !Number.isInteger(maxWidth) || maxWidth < 200 || maxWidth > 1200
    ) {
      return json({
        error: "INVALID_REQUEST",
        message: "Invalid photo request.",
      }, 400);
    }
    signedValue = `photo:${photoReference}:${maxWidth}`;
    if (
      !photoReference.startsWith("places/") ||
      !photoReference.includes("/photos/")
    ) {
      return json({
        error: "INVALID_REQUEST",
        message: "Invalid Places API (New) photo resource.",
      }, 400);
    }
    upstream = new URL(
      `https://places.googleapis.com/v1/${
        photoReference.replace(/^\/+/, "")
      }/media`,
    );
    upstream.searchParams.set("maxWidthPx", String(maxWidth));
  } else {
    return json({
      error: "INVALID_REQUEST",
      message: "Unknown media resource.",
    }, 400);
  }

  const expectedSignature = await signature(signedValue);
  if (
    !suppliedSignature || !sameSignature(suppliedSignature, expectedSignature)
  ) {
    return json({
      error: "INVALID_SIGNATURE",
      message: "This media URL is not authorized.",
    }, 403);
  }

  const placePhoto = resource === "photo";
  if (!placePhoto) upstream.searchParams.set("key", GOOGLE_MAPS_API_KEY);
  let response: Response;
  try {
    response = await fetch(upstream, {
      redirect: "follow",
      ...(placePhoto
        ? { headers: { "X-Goog-Api-Key": GOOGLE_MAPS_API_KEY } }
        : {}),
    });
  } catch {
    return json({
      error: "UPSTREAM_NETWORK",
      message: "Google media could not be reached.",
    }, 502);
  }
  const contentType = response.headers.get("content-type") ?? "";
  if (!response.ok || !contentType.startsWith("image/")) {
    return json(
      {
        error: response.status === 429
          ? "RATE_LIMITED"
          : "MEDIA_UPSTREAM_FAILURE",
        message: "Google media is unavailable.",
      },
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

async function handleRequest(request: Request): Promise<Response> {
  // Browser preflight requests do not contain a user access token. Handle them
  // before parsing the URL, validating the method, or authenticating the user.
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const requestUrl = new URL(request.url);
  if (request.method === "GET") return proxyImage(requestUrl);
  if (request.method !== "POST") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  }

  if (
    !GOOGLE_MAPS_API_KEY || !SIGNING_SECRET || !SUPABASE_URL ||
    !SUPABASE_ANON_KEY
  ) {
    return json({
      error: "NOT_CONFIGURED",
      message: "Google Places is not configured on the server.",
    }, 503);
  }
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return json({
      error: "UNAUTHENTICATED",
      message: "Sign in to use Google Places.",
    }, 401);
  }
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await client.auth.getUser();
  if (userError || !userData.user) {
    return json({
      error: "UNAUTHENTICATED",
      message: "Sign in to use Google Places.",
    }, 401);
  }

  let input: Record<string, unknown>;
  try {
    input = await request.json();
  } catch {
    return json({
      error: "INVALID_REQUEST",
      message: "Expected a JSON request.",
    }, 400);
  }
  const requestedOperation = String(input.operation ?? "");
  const rawParameters = input.parameters;
  if (
    requestedOperation === "photoProxyUrl" &&
    (!rawParameters || typeof rawParameters !== "object" ||
      Array.isArray(rawParameters))
  ) {
    return json({
      error: "INVALID_REQUEST",
      message: "Invalid media parameters.",
    }, 400);
  }
  const mediaParameters = rawParameters as Record<string, unknown>;
  if (requestedOperation === "photoProxyUrl") {
    const photoReference = String(mediaParameters.photo_reference ?? "").trim();
    if (!photoReference || photoReference.length > 1000) {
      return json({
        error: "INVALID_REQUEST",
        message: "Invalid photo reference.",
      }, 400);
    }
    return json({ url: await photoProxyUrl(photoReference) });
  }

  const operation = requestedOperation as Operation;
  if (!(operation in operationConfig)) {
    return json({
      error: "INVALID_REQUEST",
      message: "Unsupported Google Places operation.",
    }, 400);
  }
  const params = safeParameters(operation, input.parameters);
  if (!params) {
    return json({
      error: "INVALID_REQUEST",
      message: "Invalid Google Places parameters.",
    }, 400);
  }

  const upstreamRequest = placesRequest(operation, params);
  let googleResponse: Response;
  try {
    googleResponse = await fetch(upstreamRequest.url, upstreamRequest.init);
  } catch {
    return json({
      error: "UPSTREAM_NETWORK",
      message: "Could not reach Google Places.",
    }, 502);
  }
  let googleBody: Record<string, unknown>;
  try {
    googleBody = await googleResponse.json();
  } catch {
    return json({
      error: "UPSTREAM_FAILURE",
      message: "Google Places returned an unreadable response.",
    }, 502);
  }
  const failure = googleFailure(googleBody, googleResponse.status);
  if (failure) return failure;
  return json(
    await decorateGoogleBody(normalizePlacesBody(operation, googleBody)),
  );
}

serve(async (request) => {
  try {
    return await handleRequest(request);
  } catch (error) {
    console.error("Unhandled google-places error", error);
    return json(
      {
        error: "INTERNAL_ERROR",
        message: "The Places service failed unexpectedly.",
      },
      500,
    );
  }
});
