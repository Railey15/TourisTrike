import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

serve((request) => {
  if (request.method !== "GET") {
    return new Response("Method not allowed", { status: 405 });
  }

  const requestedResult = new URL(request.url).searchParams.get("result");
  const result = requestedResult === "success" ? "success" : "cancel";
  const appUrl = `touristrike://wallet/payment/${result}`;
  const title = result === "success"
    ? "Payment submitted"
    : "Payment cancelled";
  const message = result === "success"
    ? "Return to TourisTrike while we verify your payment."
    : "Return to TourisTrike to choose another payment option.";

  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="0;url=${appUrl}">
  <title>${title}</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 0; min-height: 100vh;
      display: grid; place-items: center; background: #f5f7fb; color: #0f172a; }
    main { max-width: 28rem; margin: 1.5rem; padding: 2rem; text-align: center;
      background: white; border-radius: 1rem; box-shadow: 0 12px 32px #0f172a18; }
    a { display: inline-block; margin-top: 1rem; padding: .8rem 1.2rem;
      border-radius: .75rem; background: #2563eb; color: white;
      font-weight: 700; text-decoration: none; }
  </style>
</head>
<body>
  <main>
    <h1>${title}</h1>
    <p>${message}</p>
    <a href="${appUrl}">Return to TourisTrike</a>
  </main>
  <script>window.location.replace(${JSON.stringify(appUrl)});</script>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Security-Policy":
        "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
    },
  });
});
