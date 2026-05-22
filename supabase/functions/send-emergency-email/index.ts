// Supabase Edge Function: send-emergency-email
// Triggered by the Flutter app after inserting an emergency_alerts row.
// Reads alert details, then emails all recipients via Resend API.
//
// Required secrets (set in Supabase Dashboard → Edge Functions → Secrets):
//   RESEND_API_KEY       — from resend.com (free tier: 3,000 emails/month)
//   FROM_EMAIL           — verified sender, e.g. "TourisTrike <alerts@yourdomain.com>"
//
// Deploy: supabase functions deploy send-emergency-email

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const FROM_EMAIL =
  Deno.env.get("FROM_EMAIL") ?? "TourisTrike Alerts <noreply@touristrike.app>";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

async function sendEmail(to: string, subject: string, html: string) {
  if (!RESEND_API_KEY) {
    console.warn("[Emergency] RESEND_API_KEY not set — skipping email");
    return false;
  }
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: FROM_EMAIL, to, subject, html }),
  });
  if (!res.ok) {
    const err = await res.text();
    console.error(`[Emergency] Resend error for ${to}: ${err}`);
    return false;
  }
  return true;
}

function buildEmailHtml(params: {
  touristName: string;
  mapsLink: string | null;
  driverName: string | null;
  packageTitle: string | null;
  tripStatus: string | null;
  currentSpot: string | null;
  note: string | null;
  triggeredAt: string;
  bookingId: string | null;
}) {
  const {
    touristName,
    mapsLink,
    driverName,
    packageTitle,
    tripStatus,
    currentSpot,
    note,
    triggeredAt,
    bookingId,
  } = params;

  const locationHtml = mapsLink
    ? `<p>📍 <a href="${mapsLink}" style="color:#DC2626;font-weight:bold;">View Location on Google Maps</a></p>`
    : `<p>📍 Location: Not available</p>`;

  const noteHtml = note
    ? `<p><strong>Tourist Note:</strong> ${note}</p>`
    : "";

  return `
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="font-family:Arial,sans-serif;background:#f9fafb;margin:0;padding:0;">
  <div style="max-width:600px;margin:24px auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.10);">
    <div style="background:linear-gradient(135deg,#DC2626,#B91C1C);padding:28px 32px;text-align:center;">
      <div style="font-size:48px;margin-bottom:8px;">🚨</div>
      <h1 style="color:#fff;margin:0;font-size:24px;font-weight:900;letter-spacing:1px;">EMERGENCY ALERT</h1>
      <p style="color:#fca5a5;margin:6px 0 0;font-size:14px;">TourisTrike Safety System</p>
    </div>
    <div style="padding:28px 32px;">
      <div style="background:#FEF2F2;border:1.5px solid #FCA5A5;border-radius:12px;padding:16px 20px;margin-bottom:24px;">
        <p style="margin:0;color:#7F1D1D;font-size:15px;font-weight:700;">
          <strong>${touristName}</strong> has triggered an emergency alert during a tourism trip.
        </p>
      </div>

      <table style="width:100%;border-collapse:collapse;">
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #f1f5f9;color:#64748b;font-size:13px;width:130px;vertical-align:top;">📍 Location</td>
          <td style="padding:10px 0;border-bottom:1px solid #f1f5f9;font-size:13px;color:#0f172a;font-weight:600;">
            ${mapsLink ? `<a href="${mapsLink}" style="color:#DC2626;">Open in Google Maps</a>` : "Not available"}
          </td>
        </tr>
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #f1f5f9;color:#64748b;font-size:13px;vertical-align:top;">🚗 Driver</td>
          <td style="padding:10px 0;border-bottom:1px solid #f1f5f9;font-size:13px;color:#0f172a;font-weight:600;">${driverName ?? "Not assigned"}</td>
        </tr>
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #f1f5f9;color:#64748b;font-size:13px;vertical-align:top;">📦 Package</td>
          <td style="padding:10px 0;border-bottom:1px solid #f1f5f9;font-size:13px;color:#0f172a;font-weight:600;">${packageTitle ?? "Tour Package"}</td>
        </tr>
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #f1f5f9;color:#64748b;font-size:13px;vertical-align:top;">🗺 Current Stop</td>
          <td style="padding:10px 0;border-bottom:1px solid #f1f5f9;font-size:13px;color:#0f172a;font-weight:600;">${currentSpot ?? "In transit"}</td>
        </tr>
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #f1f5f9;color:#64748b;font-size:13px;vertical-align:top;">⚡ Trip Status</td>
          <td style="padding:10px 0;border-bottom:1px solid #f1f5f9;font-size:13px;color:#0f172a;font-weight:600;">${(tripStatus ?? "unknown").replaceAll("_", " ")}</td>
        </tr>
        <tr>
          <td style="padding:10px 0;color:#64748b;font-size:13px;vertical-align:top;">🕐 Time</td>
          <td style="padding:10px 0;font-size:13px;color:#0f172a;font-weight:600;">${triggeredAt}</td>
        </tr>
      </table>

      ${noteHtml ? `
      <div style="background:#FFF7ED;border:1px solid #FED7AA;border-radius:10px;padding:14px;margin-top:20px;">
        <p style="margin:0;color:#9A3412;font-size:13px;"><strong>Tourist Note:</strong> ${note}</p>
      </div>` : ""}

      <div style="background:#FEF2F2;border-radius:12px;padding:20px;margin-top:24px;text-align:center;">
        <p style="margin:0;color:#7F1D1D;font-weight:900;font-size:15px;">
          ⚠️ Please contact the Tourism Office and assist immediately.
        </p>
        ${bookingId ? `<p style="margin:8px 0 0;color:#9A3412;font-size:12px;">Booking ID: ${bookingId}</p>` : ""}
      </div>
    </div>
    <div style="background:#f8fafc;padding:16px 32px;text-align:center;">
      <p style="margin:0;color:#94a3b8;font-size:12px;">
        This is an automated emergency alert from TourisTrike Safety System.
      </p>
    </div>
  </div>
</body>
</html>`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const { alert_id } = await req.json();
    if (!alert_id) return json({ error: "alert_id required" }, 400);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ── Fetch alert details ──────────────────────────────────────
    const { data: alert, error: alertErr } = await supabase
      .from("emergency_alerts")
      .select("*")
      .eq("id", alert_id)
      .single();

    if (alertErr || !alert) {
      console.error("[Emergency] Alert fetch error:", alertErr);
      return json({ error: "Alert not found" }, 404);
    }

    // ── Tourist name ─────────────────────────────────────────────
    const { data: touristProfile } = await supabase
      .from("profiles")
      .select("full_name, first_name, last_name")
      .eq("id", alert.tourist_id)
      .maybeSingle();

    const touristName =
      touristProfile?.full_name?.trim() ||
      [touristProfile?.first_name, touristProfile?.last_name]
        .filter(Boolean)
        .join(" ")
        .trim() ||
      "Tourist";

    // ── Driver name ──────────────────────────────────────────────
    let driverName: string | null = null;
    if (alert.driver_id) {
      const { data: driverProfile } = await supabase
        .from("profiles")
        .select("full_name, first_name, last_name")
        .eq("id", alert.driver_id)
        .maybeSingle();

      driverName =
        driverProfile?.full_name?.trim() ||
        [driverProfile?.first_name, driverProfile?.last_name]
          .filter(Boolean)
          .join(" ")
          .trim() ||
        null;
    }

    // ── Package title ────────────────────────────────────────────
    let packageTitle: string | null = null;
    if (alert.booking_id) {
      const { data: booking } = await supabase
        .from("package_bookings")
        .select("tour_packages(title)")
        .eq("id", alert.booking_id)
        .maybeSingle();
      packageTitle =
        (booking?.tour_packages as { title?: string } | null)?.title ?? null;
    }

    // ── Build email HTML ─────────────────────────────────────────
    const triggeredAt = new Date(alert.created_at).toLocaleString("en-PH", {
      timeZone: "Asia/Manila",
      dateStyle: "full",
      timeStyle: "short",
    });

    const html = buildEmailHtml({
      touristName,
      mapsLink: alert.maps_link,
      driverName,
      packageTitle,
      tripStatus: alert.trip_status,
      currentSpot: alert.current_spot_name,
      note: alert.tourist_note,
      triggeredAt,
      bookingId: alert.booking_id,
    });

    const subject = `🚨 TourisTrike Emergency Alert — ${touristName}`;
    const recipients: string[] = [];

    // ── Emergency contact emails ─────────────────────────────────
    const { data: contacts } = await supabase
      .from("emergency_contacts")
      .select("email, name")
      .eq("tourist_id", alert.tourist_id)
      .not("email", "is", null);

    for (const c of contacts ?? []) {
      if (c.email?.trim()) recipients.push(c.email.trim());
    }

    // ── Subtenant/admin emails ───────────────────────────────────
    const { data: subtenants } = await supabase
      .from("subtenant_details")
      .select("email")
      .eq("is_active", true)
      .not("email", "is", null);

    for (const s of subtenants ?? []) {
      if (s.email?.trim()) recipients.push(s.email.trim());
    }

    // ── Send emails ──────────────────────────────────────────────
    let sentCount = 0;
    const uniqueRecipients = [...new Set(recipients)];

    for (const email of uniqueRecipients) {
      const ok = await sendEmail(email, subject, html);
      if (ok) sentCount++;
    }

    console.log(
      `[Emergency] Alert ${alert_id}: sent to ${sentCount}/${uniqueRecipients.length} recipients`
    );

    // ── Mark email_sent on alert ─────────────────────────────────
    await supabase
      .from("emergency_alerts")
      .update({
        email_sent: sentCount > 0,
        notifications_sent: true,
      })
      .eq("id", alert_id);

    return json({
      ok: true,
      alert_id,
      emails_sent: sentCount,
      recipients: uniqueRecipients.length,
    });
  } catch (e) {
    console.error("[Emergency] Unhandled error:", e);
    return json({ error: String(e) }, 500);
  }
});
