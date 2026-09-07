Share Trip web Maps key audit — 7 September 2026

The production map is not yet fixed. The local build/configuration changes are ready, but a valid Google Cloud browser key and a production rebuild/redeploy are still required.

**Confirmed error and live configuration**

The user's captured console error is `Google Maps JavaScript API error: InvalidKeyMapError`. Google defines this error as the supplied script key not being found. The DirectionsService deprecation warning is not the map-loading cause. The console capture was supplied by the user; no browser was available to recapture it in this session. [Google error reference](https://developers.google.com/maps/documentation/javascript/error-messages#invalid-key-map-error).

I fetched `https://touris-trike.vercel.app/` directly, including a cache-busting query. It returns HTTP 200 and contains exactly one literal Maps JavaScript script URL with a `key` parameter. Its key fingerprint is `1aa4d7e572c5` (first 12 hex characters of SHA-256). The string has the expected 39-character format, but the captured Google error establishes that the browser's supplied key was rejected as unrecognized. Whether it was deleted, mistyped, or generated in a different project cannot be determined from its shape.

The live HTML uses the older literal script loader. Current `web/index.html` uses a build placeholder, so this deployment is not the current source/configuration output. Both fetches returned the same key fingerprint. This is not evidence that the browser cache alone caused the problem, nor does an HTTP 200 response from the SDK establish key authorization.

**Where keys come from**

| Surface | Source | Audit result |
| --- | --- | --- |
| Current production Share Trip | Literal key in deployed `/index.html` Maps script URL | Fingerprint `1aa4d7e572c5`; rejected according to captured console |
| Intended Vercel web build | `GOOGLE_MAPS_BROWSER_API_KEY` → `build.sh` → `tool/configure_web_maps.cjs` → `build/web/index.html` | Dedicated browser variable; Vercel environment value itself could not be inspected |
| Local web build | Same variable → `tool/build_web.ps1` → same injector | Variable is not set in this session; no replacement key injected |
| Source HTML | `web/index.html` placeholder `__GOOGLE_MAPS_BROWSER_API_KEY__` | Source template, not a credential |
| Android in this checkout | `.env` / `android/local.properties` / process `GOOGLE_MAPS_API_KEY` → Gradle manifest placeholder | Effective local `.env` fingerprint `c00dde49f3b8`, different from production web key; no local.properties override |

`SharedTripLink.shareUrl` uses `https://touris-trike.vercel.app/trip/<token>`. `lib/main.dart` routes that path to the guest access screen inside the same Flutter web app. There is no separate Supabase Edge Function HTML loader in this path. The JavaScript SDK key comes from the HTML, not the Dart route-service key resolver or AndroidManifest.

Different fingerprints establish different key strings. They do not establish application restrictions or owning projects. The deployed web key could still have Android restrictions; that cannot be verified offline.

**Checks requiring authenticated Google Cloud access**

| Check | Result |
| --- | --- |
| Key recognized by Google | Captured `InvalidKeyMapError` says it was not found |
| Owning/correct project | Unverified |
| Android versus Websites restriction | Unverified; production key differs from local Android key |
| Maps JavaScript API enabled in owning project | Unverified |
| Maps JavaScript API allowed by key API restrictions | Unverified |
| Billing active in owning project | Unverified |
| Production HTTP referrer authorized | Unverified |
| Production already using a replacement key | No replacement key available for comparison; live fingerprint remains `1aa4d7e572c5` |

No browser session is connected and no gcloud CLI is installed. An unauthenticated read-only Google API Keys lookup returned `401 UNAUTHENTICATED`; the lookup requires authenticated access. No Google Cloud credentials, billing, restrictions, or Vercel environment settings were changed. [Google key/project lookup documentation](https://docs.cloud.google.com/api-keys/docs/get-info-api-keys#looking_up_a_key_name_and_project_by_key_string).

**Exact Google Cloud and Vercel changes needed**

1. In [Google Cloud Credentials](https://console.cloud.google.com/apis/credentials), select the intended TourisTrike project and record its project ID. Verify that this same project has an active billing account. Do not assume the old free-trial project still has active billing.
2. Locate a valid dedicated web key in that project, or create one named `TourisTrike Share Trip Web`. Use **Application restrictions → Websites** with this production referrer:

   ```text
   https://touris-trike.vercel.app/*
   ```

   Do not add `*.vercel.app`, a Supabase domain, or localhost for this production-only surface. The guest frontend origin is the Vercel domain, even though it reads Supabase data. Use a separate development key if local testing needs another origin.
3. Enable **Maps JavaScript API** in that same project and include it under the key's **API restrictions**. Existing route drawing uses DirectionsService; if continuing to use that existing service, retain/authorize **Directions API (Legacy)** where available on this project. That route requirement is separate from the confirmed invalid-key loading error; no route-service migration was made. [Google's recommended application/API restrictions](https://developers.google.com/maps/api-security-best-practices#recommended-application-and-api-restrictions).
4. In the existing Vercel project for `touris-trike.vercel.app`, set **Settings → Environment Variables → `GOOGLE_MAPS_BROWSER_API_KEY`**, scoped to **Production**, to the complete dedicated key value, without added quotes or whitespace. Do not change `GOOGLE_MAPS_API_KEY` or Android package/SHA restrictions.
5. Deploy the reviewed source/configuration and trigger a new production build using `bash build.sh` (already configured by `vercel.json`). Updating an environment variable does not change previously generated HTML. The new build log must contain `Web Maps key fingerprint=... (injected and verified)`.

**Files changed for this focused follow-up**

- `web/index.html`: adds safe fingerprint metadata for the injected browser key; SDK loading order and route bridge are unchanged.
- `tool/configure_web_maps.cjs`: one injector for both web build scripts, format checks, exactly-one-loader checks, safe fingerprints, and a deployed-HTML verifier. No native/server key fallback. It rejects previously injected output so an old key cannot silently remain after an attempted substitution. Format checks do not certify Google authorization.
- `build.sh` and `tool/build_web.ps1`: run the same pre-build key check and post-build verified injection instead of separate substitution implementations.
- `test/web_maps_config_test.cjs`: five passing tests for missing/malformed key handling, exact loader input, duplicate SDK scripts, stale output, and redacted live-output inspection.
- This report.

Guest UI/state, share tokens, SQL, Tourist/Driver mobile map code, and DirectionsService code were not modified in this follow-up. The workspace retains changes from the earlier broader request.

**Rebuild and verify**

For a local production web build, set `GOOGLE_MAPS_BROWSER_API_KEY` securely in the shell, then run:

```powershell
powershell -NoProfile -File tool/build_web.ps1
```

After production deployment, use that same expected environment variable and run:

```powershell
node tool/configure_web_maps.cjs --verify-url https://touris-trike.vercel.app/
```

It downloads the served HTML with a cache-busting query, reports only fingerprints, and exits with an error if the deployed key differs from the selected environment key. If no expected key is set, it only reports the live fingerprint and explicitly says the comparison was not performed.

Open an actual shared link and hard-reload with DevTools Network **Disable cache** enabled. Verify exactly one `maps/api/js` request. Compare the build fingerprint with this console expression (no key value is printed):

```javascript
await (async () => {
  const scripts = [...document.scripts].filter(s => s.src.startsWith('https://maps.googleapis.com/maps/api/js?'));
  const key = scripts[0] && new URL(scripts[0].src).searchParams.get('key');
  const bytes = key && await crypto.subtle.digest('SHA-256', new TextEncoder().encode(key));
  return {
    sdkLoads: scripts.length,
    actualKeyFingerprint: bytes && [...new Uint8Array(bytes)].map(b => b.toString(16).padStart(2, '0')).join('').slice(0, 12),
    declaredFingerprint: document.querySelector('meta[name="touristrike-maps-key-fingerprint"]')?.content
  };
})();
```

The two fingerprints must match the new build log. Confirm map tiles actually appear and `InvalidKeyMapError` is absent. Check for any distinct activation, billing, or referrer error after correcting the invalid key. A fingerprint match alone is not a successful Maps authorization test.

Validation performed here: all five Node configuration tests passed; production HTML inspection succeeded; `git diff --check` passed. No replacement credential was available, so no production rebuild/redeploy or successful tile-render verification is claimed.
