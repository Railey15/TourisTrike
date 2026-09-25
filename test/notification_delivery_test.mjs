import test from 'node:test';
import assert from 'node:assert/strict';
import { fcmPayload, deliveryResult } from '../supabase/functions/send-notifications/delivery.ts';

test('Android payload handles background/tap and contains no booking/payment secrets', () => {
  const body=fcmPayload({delivery_id:'d',lease_id:'l',token:'t',notification_id:'42',title:'Driver Arrived',body:'At pickup.',channel:'tour_updates'});
  assert.deepEqual(body.message.data,{notification_id:'42'});
  assert.equal(body.message.android.notification.tag,'touristrike:42');
  assert.equal(body.message.android.notification.visibility,'PRIVATE');
  assert.equal(body.message.android.priority,'NORMAL');
  assert.equal(body.message.notification.title,'Driver Arrived');
});
test('emergencies use high priority and the dedicated channel', () => {
  const body=fcmPayload({notification_id:'1',channel:'emergency_alerts'});
  assert.equal(body.message.android.priority,'HIGH');
  assert.equal(body.message.android.notification.channel_id,'emergency_alerts');
});
test('only explicit UNREGISTERED disables tokens; transient failures retry', () => {
  assert.equal(deliveryResult(404,{error:{details:[{errorCode:'UNREGISTERED'}]}}).result,'invalid');
  assert.equal(deliveryResult(400,{error:{details:[{errorCode:'INVALID_ARGUMENT'}]}}).result,'failed');
  for(const status of [429,500,503,401]) assert.equal(deliveryResult(status,{}).result,'retry');
  assert.equal(deliveryResult(200,{}).result,'sent');
});
