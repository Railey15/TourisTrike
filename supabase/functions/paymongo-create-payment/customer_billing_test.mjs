import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolveCheckoutBilling } from './customer_billing.ts';

const source = readFileSync(new URL('./index.ts', import.meta.url), 'utf8');

test('registered profile name and Auth email become hosted billing fields', () => {
  assert.deepEqual(resolveCheckoutBilling({
    profile: { full_name: 'Juan Dela Cruz', first_name: 'Different' },
    authEmail: 'tourist@example.com',
  }), { name: 'Juan Dela Cruz', email: 'tourist@example.com' });
  assert.match(source, /attributes\.billing = billing/);
  assert.match(source, /JSON\.stringify\(\{ data: \{ attributes \} \}\)/);
  assert.match(source, /"https:\/\/api\.paymongo\.com\/v1\/checkout_sessions"/);
});

test('payment-only edits override defaults; missing values are not fabricated', () => {
  assert.deepEqual(resolveCheckoutBilling({
    requestedName: 'Maria Santos',
    requestedEmail: 'maria@example.com',
    profile: { full_name: 'Juan Dela Cruz', mobile: '09171234567' },
    authEmail: 'tourist@example.com',
  }), { name: 'Maria Santos', email: 'maria@example.com', phone: '09171234567' });
  assert.deepEqual(resolveCheckoutBilling({
    requestedName: ' ',
    requestedEmail: ' ',
    profile: { first_name: 'Juan', last_name: 'Dela Cruz' },
    authEmail: 'tourist@example.com',
  }), { name: 'Juan Dela Cruz', email: 'tourist@example.com' });
  assert.deepEqual(resolveCheckoutBilling({ profile: null }), {});
  assert.ok(!source.includes('console.log(billing)'));
  assert.ok(!source.includes('console.info(billing)'));
});
