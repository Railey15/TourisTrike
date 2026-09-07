// Web build configuration only. Never use the Android/server key as fallback.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const keyPlaceholder = '__GOOGLE_MAPS_BROWSER_API_KEY__';
const fingerprintPlaceholder = '__GOOGLE_MAPS_BROWSER_KEY_FINGERPRINT__';
const fingerprint = key => crypto.createHash('sha256').update(key).digest('hex').slice(0, 12);

function browserKey(env = process.env) {
  const key = env.GOOGLE_MAPS_BROWSER_API_KEY;
  if (!key) throw new Error('Set GOOGLE_MAPS_BROWSER_API_KEY in the web build environment. No mobile/server fallback is used.');
  // A syntax check cannot prove Google recognizes the key or allows this site.
  if (!/^AIza[A-Za-z0-9_-]{35}$/.test(key)) {
    throw new Error('GOOGLE_MAPS_BROWSER_API_KEY has an invalid format. Copy the complete key without quotes or whitespace.');
  }
  return key;
}

function inspectHtml(html) {
  const loaderCount = (html.match(/https:\/\/maps\.googleapis\.com\/maps\/api\/js/g) || []).length;
  const inline = html.match(/\b(?:const|let|var)\s+mapsBrowserKey\s*=\s*['"]([^'"]*)['"]/);
  const scripts = [...html.matchAll(/<script\b[^>]*\bsrc\s*=\s*['"]([^'"]+)['"]/gi)]
    .map(match => match[1].replaceAll('&amp;', '&'));
  const direct = scripts.find(src => src.startsWith('https://maps.googleapis.com/maps/api/js?'));
  const key = inline?.[1] ?? (direct ? new URL(direct).searchParams.get('key') : null);
  const declaredFingerprint = html.match(/name="touristrike-maps-key-fingerprint"\s+content="([^"]+)"/)?.[1];
  return {
    loaderCount,
    loader: inline ? 'build-injected inline loader' : direct ? 'literal script URL' : 'missing',
    loaderUsesKey: inline
      ? /https:\/\/maps\.googleapis\.com\/maps\/api\/js\?key=['"]\s*\+\s*encodeURIComponent\(mapsBrowserKey\)/.test(html)
      : !!direct && new URL(direct).searchParams.get('key') === key,
    unresolvedPlaceholder: html.includes(keyPlaceholder) || html.includes(fingerprintPlaceholder),
    plausibleFormat: !!key && /^AIza[A-Za-z0-9_-]{35}$/.test(key),
    fingerprint: key && key !== keyPlaceholder ? fingerprint(key) : null,
    declaredFingerprint: /^[a-f0-9]{12}$/.test(declaredFingerprint ?? '') ? declaredFingerprint : null,
  };
}

function injectHtml(html, key, log = () => {}) {
  const keyPlaceholderCount = html.split(keyPlaceholder).length - 1;
  const fingerprintPlaceholderCount = html.split(fingerprintPlaceholder).length - 1;
  log(`Web Maps before injection: ${JSON.stringify({loaderCount: inspectHtml(html).loaderCount, keyPlaceholderCount, fingerprintPlaceholderCount})}`);
  if (keyPlaceholderCount !== 1 || fingerprintPlaceholderCount !== 1) {
    throw new Error('Expected a fresh Flutter web build with the Maps placeholders. Rebuild before injecting; an old/hardcoded key will not be silently retained.');
  }
  const configured = html.replace(keyPlaceholder, key)
    .replace(fingerprintPlaceholder, fingerprint(key));
  const result = inspectHtml(configured);
  const keyMatched = result.fingerprint === fingerprint(key);
  const fingerprintMatched = result.declaredFingerprint === result.fingerprint;
  const passed = result.loaderCount === 1 && result.loaderUsesKey &&
    result.plausibleFormat && !result.unresolvedPlaceholder && keyMatched && fingerprintMatched;
  log(`Web Maps after injection: ${JSON.stringify({...result, keyMatched, fingerprintMatched, passed})}`);
  if (!passed) {
    throw new Error('Web Maps configuration verification failed. Check loaderCount (must be 1), loaderUsesKey, keyMatched, and fingerprintMatched above.');
  }
  return configured;
}

async function main(args) {
  if (args[0] === '--verify-url') {
    const url = new URL(args[1] || 'https://touris-trike.vercel.app/');
    url.searchParams.set('maps-config-check', Date.now().toString());
    const response = await fetch(url, {cache: 'no-store', signal: AbortSignal.timeout(15000)});
    if (!response.ok) throw new Error(`Deployment returned HTTP ${response.status}.`);
    const details = inspectHtml(await response.text());
    // Only origin, fingerprints and flags are logged; never tokens or key strings.
    console.log(JSON.stringify({origin: new URL(response.url).origin, ...details}, null, 2));
    if (!details.plausibleFormat || details.loaderCount !== 1 || !details.loaderUsesKey ||
        details.unresolvedPlaceholder || details.declaredFingerprint !== details.fingerprint) {
      throw new Error('Deployment has missing/invalid Maps configuration.');
    }
    if (process.env.GOOGLE_MAPS_BROWSER_API_KEY) {
      if (details.fingerprint !== fingerprint(browserKey())) {
        throw new Error('Deployment still uses a DIFFERENT key from GOOGLE_MAPS_BROWSER_API_KEY. Rebuild/redeploy the correct environment.');
      }
      console.log('Deployed key matches the selected browser key. Confirm Google authorization in the browser console.');
    } else {
      console.log('No expected browser key is set locally; fingerprint comparison was not performed. This does not verify Google authorization.');
    }
    return;
  }
  const key = browserKey();
  if (args[0] !== '--check-env') {
    const index = path.join(root, 'build/web/index.html');
    fs.writeFileSync(index, injectHtml(fs.readFileSync(index, 'utf8'), key, console.log));
    console.log('Web Maps final build/web/index.html: verification passed.');
  }
  console.log(`Web Maps key fingerprint=${fingerprint(key)} (${args[0] === '--check-env' ? 'format checked; Google authorization not checked' : 'injected and verified'}).`);
}

module.exports = {browserKey, fingerprint, inspectHtml, injectHtml};
if (require.main === module) main(process.argv.slice(2)).catch(error => {
  // Do not log fetch errors/URLs or arbitrary upstream bodies containing keys.
  console.error(error instanceof TypeError ? 'Web Maps configuration check failed (network or input error).' : error.message);
  process.exitCode = 1;
});
