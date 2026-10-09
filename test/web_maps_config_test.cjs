const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {browserKey, fingerprint, inspectHtml, injectHtml} = require('../tool/configure_web_maps.cjs');
// Synthetic format fixtures; not Google credentials and never deployed.
const key = 'AIza' + 'a'.repeat(35);
const differentKey = 'AIza' + 'b'.repeat(35);
const template = fs.readFileSync('web/index.html', 'utf8');

test('web key never falls back to native configuration; malformed input fails', () => {
  assert.throws(() => browserKey({GOOGLE_MAPS_API_KEY: key}), /No mobile\/server fallback/);
  for (const value of ['YOUR_API_KEY', ` ${key}`, `${key}\n`, `"${key}"`, key.slice(1)]) {
    assert.throws(() => browserKey({GOOGLE_MAPS_BROWSER_API_KEY: value}), /invalid format/);
  }
  assert.equal(browserKey({GOOGLE_MAPS_BROWSER_API_KEY: key}), key);
});

test('generated loader sends exactly the supplied key once and records its fingerprint', () => {
  const html = injectHtml(template, key);
  const details = inspectHtml(html);
  assert.equal(details.fingerprint, fingerprint(key));
  assert.equal(details.declaredFingerprint, details.fingerprint);
  assert.equal(details.loaderCount, 1);
  assert.equal(details.unresolvedPlaceholder, false);
  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  const writes = [];
  vm.runInNewContext(scripts[0][1], {document: {write: html => writes.push(html)}});
  assert.equal(writes.length, 1);
  const src = writes[0].match(/src="([^"]+)"/)[1];
  assert.equal(new URL(src).searchParams.get('key'), key);
});

test('web route bridge uses Routes Library computeRoutes and preserves app response shape', async () => {
  const scripts = [...template.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  let request;
  const context = {JSON, Number};
  context.window = context;
  context.google = {
    maps: {
      importLibrary: async name => {
        assert.equal(name, 'routes');
        return {
          Route: {
            computeRoutes: async value => {
              request = value;
              return {
                routes: [{
                  path: [{lat: 14.95, lng: 120.9}, {lat: 14.96, lng: 120.91}],
                  durationMillis: 125000,
                  legs: [{durationMillis: 125000, distanceMeters: 2300}],
                }],
              };
            },
          },
        };
      },
    },
  };
  vm.runInNewContext(scripts[1][1], context);
  const result = JSON.parse(await context._flutterGetRoute(JSON.stringify({
    originLat: 14.95,
    originLng: 120.9,
    destLat: 14.96,
    destLng: 120.91,
    requestTraffic: true,
    stopovers: true,
    waypoints: [{lat: 14.955, lng: 120.905}],
  })));
  assert.equal(request.routingPreference, 'TRAFFIC_AWARE');
  assert.equal(request.intermediates[0].via, false);
  assert.deepEqual(Array.from(request.fields), [
    'path',
    'durationMillis',
    'distanceMeters',
    'legs.durationMillis',
    'legs.distanceMeters',
  ]);
  assert.equal(result.status, 'OK');
  assert.deepEqual(result.points, [[14.95, 120.9], [14.96, 120.91]]);
  assert.equal(result.eta, '3 min');
  assert.equal(result.routes[0].legs[0].duration.value, 125);
  assert.equal(result.routes[0].legs[0].distance.value, 2300);
});

test('old output or a missing placeholder cannot silently preserve a stale key', () => {
  assert.throws(() => injectHtml(injectHtml(template, key), differentKey), /fresh Flutter web build/);
  assert.throws(() => injectHtml('<script src="https://maps.googleapis.com/maps/api/js?key=x"></script>', key), /fresh Flutter web build/);
});

test('duplicate loaders are rejected', () => {
  assert.throws(
    () => injectHtml(template + '<script src="https://maps.googleapis.com/maps/api/js"></script>', key),
    /exactly one SDK loader|loaderCount \(must be 1\)/,
  );
});

test('audit recognizes the previous literal-key deployment without exposing its key', () => {
  const details = inspectHtml(`<script src="https://maps.googleapis.com/maps/api/js?key=${key}"></script>`);
  assert.equal(details.loader, 'literal script URL');
  assert.equal(details.fingerprint, fingerprint(key));
  assert.equal(JSON.stringify(details).includes(key), false);
  assert.notEqual(details.fingerprint, fingerprint(differentKey));
});
