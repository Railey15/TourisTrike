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

test('old output or a missing placeholder cannot silently preserve a stale key', () => {
  assert.throws(() => injectHtml(injectHtml(template, key), differentKey), /fresh Flutter web build/);
  assert.throws(() => injectHtml('<script src="https://maps.googleapis.com/maps/api/js?key=x"></script>', key), /fresh Flutter web build/);
});

test('duplicate loaders are rejected', () => {
  assert.throws(() => injectHtml(template + '<script src="https://maps.googleapis.com/maps/api/js"></script>', key), /exactly one SDK loader/);
});

test('audit recognizes the previous literal-key deployment without exposing its key', () => {
  const details = inspectHtml(`<script src="https://maps.googleapis.com/maps/api/js?key=${key}"></script>`);
  assert.equal(details.loader, 'literal script URL');
  assert.equal(details.fingerprint, fingerprint(key));
  assert.equal(JSON.stringify(details).includes(key), false);
  assert.notEqual(details.fingerprint, fingerprint(differentKey));
});
