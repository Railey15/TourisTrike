import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import { accessToken, deliveryResult, fcmPayload, type Delivery } from './delivery.ts';

async function secretMatches(actual: string, expected: string) {
  const hash = async (value: string) => new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)));
  const [a, b] = await Promise.all([hash(actual), hash(expected)]);
  return a.reduce((diff, byte, i) => diff | (byte ^ b[i]), 0) === 0;
}

Deno.serve(async request => {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const secret = Deno.env.get('NOTIFICATION_WORKER_SECRET');
  if (!secret || !await secretMatches(request.headers.get('x-notification-secret') ?? '', secret)) {
    return new Response('Unauthorized', { status: 401 });
  }
  const credentials = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (!credentials) {
    console.error('[NOTIFICATION][ERROR] FIREBASE_SERVICE_ACCOUNT_JSON is not configured');
    return Response.json({ error: 'FIREBASE_NOT_CONFIGURED' }, { status: 503 });
  }
  try {
    const account = JSON.parse(credentials);
    if (!/^[a-z0-9-]+$/.test(account.project_id)) throw new Error('INVALID_PROJECT');
    // Authenticate before claiming: a credential outage doesn't consume retry attempts.
    const bearer = await accessToken(account);
    console.log('[NOTIFICATION] Firebase sender authorization succeeded');
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data, error } = await db.rpc('claim_notification_deliveries', { p_limit: 30 });
    if (error) throw new Error('CLAIM_FAILED');
    const jobs = (data ?? []) as Delivery[];
    console.log(`[NOTIFICATION] Delivery jobs claimed: ${jobs.length}`);
    // Bounded concurrency keeps all jobs inside the 2 minute lease.
    for (let offset = 0; offset < jobs.length; offset += 5) {
      await Promise.all(jobs.slice(offset, offset + 5).map(async job => {
        let outcome: { result: string; code: string | null };
        try {
          // Account switch/logout can invalidate a binding after a queue claim.
          const { data: devices, error: deviceError } = await db.from('notification_devices')
            .select('installation_id').eq('installation_id', job.installation_id)
            .eq('user_id', job.recipient_id).eq('token', job.token).eq('active', true);
          if (deviceError) throw new Error('DEVICE_LOOKUP_FAILED');
          if (!devices?.length) outcome = { result: 'failed', code: 'DEVICE_UNAVAILABLE' };
          else {
            const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
              method: 'POST', headers: { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json' },
              body: JSON.stringify(fcmPayload(job)), signal: AbortSignal.timeout(10000),
            });
            outcome = deliveryResult(response.status, await response.json().catch(() => ({})));
            console.log(JSON.stringify({ stage: 'fcm_response', notification_id: job.notification_id,
              status: response.status, result: outcome.result, code: outcome.code }));
          }
        } catch {
          console.error('[NOTIFICATION][ERROR] Delivery transport or device lookup failed');
          outcome = { result: 'retry', code: 'TRANSPORT_ERROR' };
        }
        const { error: finishError } = await db.rpc('finish_notification_delivery', {
          p_id: job.delivery_id, p_lease: job.lease_id, p_result: outcome.result, p_code: outcome.code,
        });
        if (finishError) console.error('[NOTIFICATION][ERROR] NOTIFICATION_ACK_FAILED'); // no tokens/payloads in logs
      }));
    }
    return Response.json({ processed: jobs.length });
  } catch {
    console.error('NOTIFICATION_WORKER_FAILED');
    return new Response('Delivery unavailable', { status: 503 });
  }
});
