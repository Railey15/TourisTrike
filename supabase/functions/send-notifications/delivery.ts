export type Delivery = {
  delivery_id: string; lease_id: string; token: string; notification_id: string;
  title: string; body: string; channel: string;
  recipient_id: string; installation_id: string;
};

export function fcmPayload(job: Delivery) {
  return { message: {
    token: job.token,
    notification: { title: job.title, body: job.body },
    // Only a persistent ID goes to the device. Navigation fetches authorized data.
    data: { notification_id: job.notification_id },
    android: {
      priority: job.channel === 'emergency_alerts' ? 'HIGH' : 'NORMAL',
      ttl: job.channel === 'emergency_alerts' ? '900s' : '3600s',
      notification: {
        channel_id: job.channel, tag: `touristrike:${job.notification_id}`,
        icon: 'ic_notification', visibility: 'PRIVATE',
        default_sound: true, default_vibrate_timings: true,
      },
    },
  } };
}

// INVALID_ARGUMENT can be a bad payload; never invalidate a token on that alone.
export function deliveryResult(status: number, response: unknown) {
  const body = response as { error?: { details?: { errorCode?: string }[] } };
  const code = body?.error?.details?.find(d => d.errorCode)?.errorCode;
  if (status >= 200 && status < 300) return { result: 'sent', code: null };
  if (code === 'UNREGISTERED') return { result: 'invalid', code };
  if (status === 429 || status >= 500 || status === 401) {
    return { result: 'retry', code: code ?? `HTTP_${status}` };
  }
  return { result: 'failed', code: code ?? `HTTP_${status}` };
}

const encode = (value: Uint8Array) => btoa(String.fromCharCode(...value))
  .replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
const json = (value: unknown) => encode(new TextEncoder().encode(JSON.stringify(value)));

export async function accessToken(account: { client_email: string; private_key: string }) {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${json({ alg: 'RS256', typ: 'JWT' })}.${json({
    iss: account.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600,
  })}`;
  const pem = account.private_key.replace(/-----[^-]+-----|\s/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), c => c.charCodeAt(0)),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned));
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', signal: AbortSignal.timeout(10000),
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${encode(new Uint8Array(signature))}` }),
  });
  if (!res.ok) throw new Error('FCM_AUTH_FAILED');
  const token = await res.json();
  if (typeof token.access_token !== 'string') throw new Error('FCM_AUTH_FAILED');
  return token.access_token as string;
}
