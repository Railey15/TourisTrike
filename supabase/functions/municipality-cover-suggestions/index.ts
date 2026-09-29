import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import {
  CoverSuggestion,
  mergePexelsSuggestions,
  municipalityQueries,
  parsePexelsResponse,
  pexelsConfigurationWarning,
  suggestionLimitFromPayload,
} from "./pexels.ts";

const PEXELS_API_KEY = (Deno.env.get("PEXELS_API_KEY") ?? "").trim();
const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").trim();
const SUPABASE_ANON_KEY = (Deno.env.get("SUPABASE_ANON_KEY") ?? "").trim();

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function upstreamFailure(status: number): Response | null {
  if (status === 429) {
    return json({
      error: "RATE_LIMITED",
      message:
        "Pexels request limit was reached. Local images remain available.",
    }, 429);
  }
  if (status === 401 || status === 403) {
    return json({
      error: "PEXELS_UNAUTHORIZED",
      message:
        "Pexels rejected the server API key. Local images remain available.",
    }, 503);
  }
  if (status < 200 || status >= 300) {
    return json({
      error: "UPSTREAM_FAILURE",
      message:
        "Pexels is temporarily unavailable. Local images remain available.",
    }, 502);
  }
  return null;
}

async function searchPexels(
  query: string,
  queryIndex: number,
  municipality: string,
) {
  const url = new URL("https://api.pexels.com/v1/search");
  url.searchParams.set("query", query);
  url.searchParams.set("orientation", "landscape");
  url.searchParams.set("size", "large");
  url.searchParams.set("locale", "en-US");
  url.searchParams.set("per_page", "8");

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 7000);
  try {
    const response = await fetch(url, {
      headers: { Authorization: PEXELS_API_KEY },
      signal: controller.signal,
    });
    const failure = upstreamFailure(response.status);
    if (failure) return { failure, suggestions: [] as CoverSuggestion[] };
    let body: unknown;
    try {
      body = await response.json();
    } catch {
      return {
        failure: json({
          error: "INVALID_RESPONSE",
          message:
            "Pexels returned an unreadable response. Local images remain available.",
        }, 502),
        suggestions: [] as CoverSuggestion[],
      };
    }
    return {
      failure: null,
      suggestions: parsePexelsResponse(body, queryIndex, municipality),
    };
  } catch (error) {
    const timedOut = error instanceof DOMException &&
      error.name === "AbortError";
    return {
      failure: json({
        error: timedOut ? "UPSTREAM_TIMEOUT" : "UPSTREAM_NETWORK",
        message: timedOut
          ? "Pexels timed out. Local images remain available."
          : "Could not reach Pexels. Local images remain available.",
      }, timedOut ? 504 : 502),
      suggestions: [] as CoverSuggestion[],
    };
  } finally {
    clearTimeout(timer);
  }
}

async function handleRequest(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  }
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return json({ error: "SERVER_NOT_CONFIGURED" }, 503);
  }

  let requestPayload: unknown = {};
  try {
    requestPayload = await request.json();
  } catch {
    // Empty or malformed bodies use the safe default. Municipality is never
    // accepted from the client.
  }
  const suggestionLimit = suggestionLimitFromPayload(requestPayload);

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return json({
      error: "UNAUTHENTICATED",
      message: "Sign in to load suggestions.",
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
      message: "Sign in to load suggestions.",
    }, 401);
  }

  const [{ data: profile }, { data: office }] = await Promise.all([
    client.from("profiles").select("role").eq("id", userData.user.id)
      .maybeSingle(),
    client.from("subtenant_details")
      .select("city, province, local_government_type, is_active")
      .eq("id", userData.user.id)
      .maybeSingle(),
  ]);
  if (profile?.role !== "subtenant" || !office?.is_active || !office?.city) {
    return json({
      error: "SUBTENANT_REQUIRED",
      message: "An active municipality tourism office is required.",
    }, 403);
  }

  const configurationWarning = pexelsConfigurationWarning(PEXELS_API_KEY);
  if (configurationWarning) {
    return json({ suggestions: [], warning: configurationWarning });
  }

  const queries = municipalityQueries(
    office.city,
    office.province,
    office.local_government_type,
  );
  const groups: CoverSuggestion[][] = [];
  for (let index = 0; index < queries.length; index++) {
    const result = await searchPexels(queries[index], index, office.city);
    if (result.failure) return result.failure;
    groups.push(result.suggestions);
    if (
      mergePexelsSuggestions(groups, suggestionLimit).length >= suggestionLimit
    ) {
      break;
    }
  }

  return json({
    municipality: office.city,
    province: office.province,
    suggestions: mergePexelsSuggestions(groups, suggestionLimit),
    warning: groups.every((group) => group.length === 0)
      ? "Pexels found no municipality-relevant cover photos. Local images remain available."
      : "",
  });
}

serve(async (request) => {
  try {
    return await handleRequest(request);
  } catch (error) {
    console.error("Unhandled municipality-cover-suggestions error", error);
    return json({
      error: "INTERNAL_ERROR",
      message: "External suggestions failed. Local images remain available.",
    }, 500);
  }
});
