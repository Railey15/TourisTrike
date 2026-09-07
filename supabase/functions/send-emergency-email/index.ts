// Supabase Edge Function: send-emergency-email.
// Secrets: RESEND_API_KEY, FROM_EMAIL (verified sender). Service role stays here.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { emergencyEmails } from "./config.ts";
import {
  allEmailsSent,
  buildEmailHtml,
  parsePhoto,
  recipientsFor,
} from "./email.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "UNAUTHORIZED" }, 401);
    const { data: auth, error: authError } = await supabase.auth.getUser(token);
    if (authError || !auth.user) return json({ error: "UNAUTHORIZED" }, 401);
    const body = await req.json();
    if (typeof body.alert_id !== "string") {
      return json({ error: "ALERT_ID_REQUIRED" }, 400);
    }
    const { data: alert, error: alertError } = await supabase.from(
      "emergency_alerts",
    )
      .select("*").eq("id", body.alert_id).eq("tourist_id", auth.user.id)
      .single();
    if (alertError || !alert) return json({ error: "ALERT_NOT_FOUND" }, 404);
    // Never let an authenticated caller email another tourist's private alert.
    if (alert.email_sent) return json({ email_sent: true, already_sent: true });
    let photo;
    try {
      photo = parsePhoto(body.photo);
    } catch {
      return json({ email_sent: false, error: "INVALID_PHOTO" }, 400);
    }

    const name = (p: Record<string, string> | null) =>
      p?.full_name?.trim() ||
      [p?.first_name, p?.last_name].filter(Boolean).join(" ").trim();
    const { data: tourist } = await supabase.from("profiles")
      .select("full_name, first_name, last_name").eq("id", alert.tourist_id)
      .maybeSingle();
    let driverName = "Not assigned";
    if (alert.driver_id) {
      const { data: driver } = await supabase.from("profiles")
        .select("full_name, first_name, last_name").eq("id", alert.driver_id)
        .maybeSingle();
      driverName = name(driver) || driverName;
    }
    let packageTitle = "Tour Package";
    if (alert.booking_id) {
      const { data: booking } = await supabase.from("package_bookings")
        .select("tour_packages(title)").eq("id", alert.booking_id)
        .maybeSingle();
      const tour: unknown = booking?.tour_packages;
      if (Array.isArray(tour)) {
        packageTitle = String(tour[0]?.title || packageTitle);
      } else if (tour && typeof tour === "object" && "title" in tour) {
        packageTitle = String(tour.title || packageTitle);
      }
    }
    const { data: contacts, error: contactError } = await supabase.from(
      "emergency_contacts",
    )
      .select("email").eq("tourist_id", alert.tourist_id).not(
        "email",
        "is",
        null,
      );
    const { data: offices, error: officeError } = await supabase.from(
      "subtenant_details",
    )
      .select("email").eq("is_active", true).not("email", "is", null);
    const recipients = recipientsFor(
      [...emergencyEmails],
      (contacts ?? []).map((c) => c.email ?? ""),
      (offices ?? []).map((c) => c.email ?? ""),
    );
    const html = buildEmailHtml({
      "Tourist": name(tourist) || "Tourist",
      "Booking ID": alert.booking_id,
      "Package": packageTitle,
      "Trip status": alert.trip_status,
      "Latitude": alert.latitude,
      "Longitude": alert.longitude,
      "Location": alert.maps_link,
      "Current destination": alert.current_spot_name,
      "Driver": driverName,
      "Note": alert.tourist_note,
      "Alert timestamp": alert.created_at,
      ...(photo ? { "Photo": "See attached emergency photo." } : {}),
    });
    const apiKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("FROM_EMAIL");
    if (!apiKey || !from || !recipients.length) {
      console.warn(
        "[Emergency] Email configuration or recipients unavailable; database alert retained.",
      );
      return json({ email_sent: false, error: "EMAIL_CONFIGURATION_REQUIRED" });
    }
    let sent = 0;
    for (const to of recipients) {
      try {
        const hash = await crypto.subtle.digest(
          "SHA-256",
          new TextEncoder().encode(to),
        );
        const recipientKey = [...new Uint8Array(hash)].map((b) =>
          b.toString(16).padStart(2, "0")
        ).join("");
        const response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          signal: AbortSignal.timeout(15000),
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
            "Idempotency-Key": `emergency-${alert.id}-${recipientKey}`,
          },
          body: JSON.stringify({
            from,
            to,
            subject: "TourisTrike Emergency Alert",
            html,
            ...(photo ? { attachments: [photo] } : {}),
          }),
        });
        if (response.ok) sent++;
        else {console.warn(
            `[Emergency] Email provider returned HTTP ${response.status}.`,
          );}
      } catch {
        console.warn(
          "[Emergency] Email request failed; database alert retained.",
        );
      }
    }
    const emailSent = allEmailsSent(sent, recipients.length) && !contactError &&
      !officeError;
    const { error: updateError } = await supabase.from("emergency_alerts")
      .update({ email_sent: emailSent, notifications_sent: true }).eq(
        "id",
        alert.id,
      );
    if (updateError) {
      console.warn("[Emergency] Could not record email delivery status.");
    }
    return json({
      email_sent: emailSent,
      emails_sent: sent,
      recipients: recipients.length,
    });
  } catch {
    console.error("[Emergency] Request failed; existing alert retained.");
    return json({ email_sent: false, error: "EMAIL_REQUEST_FAILED" }, 500);
  }
});
