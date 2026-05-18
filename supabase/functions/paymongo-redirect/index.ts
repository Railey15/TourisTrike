// Supabase Edge Function: paymongo-redirect
// Serves an HTML page that redirects the browser to the touristrike:// deep link.
// MUST be deployed with --no-verify-jwt so the browser can reach it unauthenticated:
//   supabase functions deploy paymongo-redirect --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const ALLOWED_TARGETS = new Set(["success", "cancel"]);

serve(async (req) => {
  const url = new URL(req.url);
  const to = url.searchParams.get("to") ?? "";
  const transactionId = url.searchParams.get("transaction_id") ?? "";

  const target = ALLOWED_TARGETS.has(to) ? to : "success";
  const isSuccess = target === "success";

  const deepLink = transactionId
    ? `touristrike://wallet/${target}?transaction_id=${encodeURIComponent(transactionId)}`
    : `touristrike://wallet/${target}`;

  const title = isSuccess ? "Payment Successful" : "Payment Cancelled";
  const heading = isSuccess ? "Payment Successful!" : "Payment Cancelled";
  const message = isSuccess
    ? "Your payment was processed. Returning to TourisTrike…"
    : "Your payment was cancelled. Returning to TourisTrike…";
  const iconEmoji = isSuccess ? "✅" : "⚠️";
  const accentHex = isSuccess ? "#16A34A" : "#F59E0B";

  const html = [
    "<!DOCTYPE html>",
    '<html lang="en">',
    "<head>",
    '  <meta charset="UTF-8">',
    '  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">',
    `  <meta http-equiv="refresh" content="1;url=${deepLink}">`,
    `  <title>${title} – TourisTrike</title>`,
    "  <style>",
    "    * { box-sizing: border-box; margin: 0; padding: 0; }",
    "    body {",
    '      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;',
    "      background: #F0F7FF;",
    "      display: flex;",
    "      align-items: center;",
    "      justify-content: center;",
    "      min-height: 100vh;",
    "      padding: 24px;",
    "    }",
    "    .card {",
    "      background: #fff;",
    "      border-radius: 24px;",
    "      padding: 40px 32px;",
    "      max-width: 360px;",
    "      width: 100%;",
    "      text-align: center;",
    "      box-shadow: 0 8px 32px rgba(42,134,255,0.12);",
    "    }",
    "    .icon {",
    "      width: 72px;",
    "      height: 72px;",
    "      border-radius: 50%;",
    `      background: ${accentHex}1A;`,
    "      display: flex;",
    "      align-items: center;",
    "      justify-content: center;",
    "      margin: 0 auto 20px;",
    "      font-size: 36px;",
    "    }",
    "    h1 { font-size: 22px; color: #0F172A; font-weight: 900; margin-bottom: 10px; }",
    "    .msg { font-size: 14px; color: #64748B; font-weight: 600; line-height: 1.5; margin-bottom: 28px; }",
    "    .btn {",
    "      display: block;",
    "      background: #2A86FF;",
    "      color: #fff;",
    "      font-weight: 900;",
    "      font-size: 16px;",
    "      padding: 16px 24px;",
    "      border-radius: 14px;",
    "      text-decoration: none;",
    "      margin-bottom: 12px;",
    "    }",
    "    .note { font-size: 12px; color: #94A3B8; font-weight: 700; }",
    "  </style>",
    "</head>",
    "<body>",
    '  <div class="card">',
    `    <div class="icon">${iconEmoji}</div>`,
    `    <h1>${heading}</h1>`,
    `    <p class="msg">${message}</p>`,
    `    <a class="btn" href="${deepLink}">Open TourisTrike</a>`,
    '    <p class="note">Redirecting automatically…</p>',
    "  </div>",
    "  <script>",
    "    (function () {",
    `      var target = ${JSON.stringify(deepLink)};`,
    "      try { window.location.replace(target); } catch (e) {}",
    "    })();",
    "  </script>",
    "</body>",
    "</html>",
  ].join("\n");

  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "no-store",
    },
  });
});
