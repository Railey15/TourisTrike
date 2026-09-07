import test from 'node:test';
import assert from 'node:assert/strict';
import {allEmailsSent, buildEmailHtml, parsePhoto, recipientsFor, maxPhotoBytes} from '../supabase/functions/send-emergency-email/email.ts';

test('optional photo and recipient normalization', () => {
  assert.equal(parsePhoto(undefined), undefined);
  assert.deepEqual(recipientsFor([' A@example.test '], ['a@example.test', '', 'invalid']), ['a@example.test']);
});
test('attachment only accepts supported image signatures, uses a safe filename and size limit', () => {
  const content = Buffer.from([255,216,255,224]).toString('base64');
  assert.deepEqual(parsePhoto({filename:'evil.html', content}), {filename:'emergency-photo.jpg', content});
  assert.throws(() => parsePhoto({content:Buffer.from('<script>').toString('base64')}), /INVALID_PHOTO/);
  assert.throws(() => parsePhoto({content:'!'}), /INVALID_PHOTO/);
  assert.throws(() => parsePhoto({content:Buffer.alloc(maxPhotoBytes+1).toString('base64')}), /INVALID_PHOTO/);
});
test('email output escapes notes and names; partial or zero delivery is not success', () => {
  const html = buildEmailHtml({Note:'<img src=x>', Tourist:'A & B', Latitude: null});
  assert(!html.includes('<img')); assert(html.includes('&lt;img')); assert(html.includes('A &amp; B'));
  assert.equal(allEmailsSent(0,0), false);
  assert.equal(allEmailsSent(1,2), false);
  assert.equal(allEmailsSent(2,2), true);
});
