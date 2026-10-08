import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

type Job = {
  id: string;
  lease_id: string;
  event_key: string;
  event_type: 'drivers_accepted' | 'downpayment_receipt' |
    'remaining_receipt' | 'tour_completed';
  booking_id: string;
  recipient_id: string;
  payload: Record<string, unknown>;
};

async function secretMatches(actual: string, expected: string): Promise<boolean> {
  const digest = async (value: string) => new Uint8Array(await crypto.subtle.digest(
    'SHA-256', new TextEncoder().encode(value)));
  const [a, b] = await Promise.all([digest(actual), digest(expected)]);
  return a.reduce((diff, byte, index) => diff | (byte ^ b[index]), 0) === 0;
}

function message(job: Job): { subject: string; text: string; html: string } {
  const amount = Number(job.payload.amount);
  const money = Number.isFinite(amount) && amount >= 0
    ? new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' }).format(amount)
    : 'the confirmed amount';
  let subject: string;
  let detail: string;
  let receipt = '';
  switch (job.event_type) {
    case 'drivers_accepted':
      subject = 'Your TourisTrike drivers are confirmed';
      detail = 'All required drivers have accepted your tour. You can review the confirmed roster and next steps in TourisTrike.';
      break;
    case 'downpayment_receipt':
      subject = 'TourisTrike downpayment receipt';
      detail = `Your downpayment of ${money} is confirmed. Your booking remains available in TourisTrike.`;
      receipt = receiptDetails(job.payload);
      break;
    case 'remaining_receipt':
      subject = 'TourisTrike remaining balance receipt';
      detail = `Your remaining balance payment of ${money} is confirmed. This receipt includes any finalized waiting charges in that payment.`;
      receipt = receiptDetails(job.payload);
      break;
    case 'tour_completed':
      subject = 'Thank you for touring with TourisTrike';
      detail = 'Your tour is officially complete. Thank you for travelling with TourisTrike. Your trip details and receipts remain available in the app.';
      break;
  }
  const text = `${subject}\n\n${detail}${receipt}\n\nBooking reference: ${job.booking_id}\n\nTourisTrike`;
  const html = `<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;color:#0f172a">
    <div style="background:#2563eb;color:white;padding:22px 26px;border-radius:16px 16px 0 0;font-size:22px;font-weight:700">TourisTrike</div>
    <div style="padding:26px;border:1px solid #e2e8f0;border-top:0;border-radius:0 0 16px 16px">
      <h1 style="font-size:21px;margin:0 0 16px">${subject}</h1>
      <p style="line-height:1.6">${detail}</p>
      ${receipt ? `<p style="line-height:1.6;white-space:pre-line">${receipt.trim()}</p>` : ''}
      <p style="color:#64748b;font-size:13px">Booking reference: ${job.booking_id}</p>
      <p style="color:#64748b;font-size:13px">View your booking in the TourisTrike app for the current status.</p>
    </div></div>`;
  return { subject, text, html };
}

function receiptDetails(payload: Record<string, unknown>): string {
  const method = payload.method === 'cash' ? 'Cash'
    : payload.method === 'gcash' ? 'GCash'
    : payload.method === 'maya' ? 'Maya' : '';
  const number = typeof payload.receipt_no === 'string' &&
    /^[A-Za-z0-9-]{1,64}$/.test(payload.receipt_no)
    ? payload.receipt_no : '';
  return `${method ? `\nPayment method: ${method}` : ''}${number ? `\nReceipt number: ${number}` : ''}`;
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const workerSecret = Deno.env.get('TRANSACTIONAL_EMAIL_WORKER_SECRET') ?? '';
  if (!workerSecret || !await secretMatches(
    request.headers.get('x-transactional-email-secret') ?? '', workerSecret)) {
    return new Response('Unauthorized', { status: 401 });
  }
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const resendKey = Deno.env.get('RESEND_API_KEY') ?? '';
  const from = Deno.env.get('FROM_EMAIL') ?? '';
  if (!url || !serviceKey || !resendKey || !from) {
    return Response.json({ error: 'EMAIL_CONFIGURATION_REQUIRED' }, { status: 503 });
  }
  const db = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data, error } = await db.rpc('claim_transactional_emails', { p_limit: 20 });
  if (error) return Response.json({ error: 'EMAIL_CLAIM_FAILED' }, { status: 503 });
  const jobs = (data ?? []) as Job[];
  for (const job of jobs) {
    let result: 'sent' | 'retry' | 'dead' = 'retry';
    let providerId: string | null = null;
    let errorCode: string | null = null;
    try {
      const { data: user, error: userError } = await db.auth.admin.getUserById(
        job.recipient_id);
      const to = user?.user?.email;
      if (userError || !to) {
        result = 'dead';
        errorCode = 'RECIPIENT_UNAVAILABLE';
      } else {
        const body = message(job);
        const response = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          signal: AbortSignal.timeout(15000),
          headers: {
            Authorization: `Bearer ${resendKey}`,
            'Content-Type': 'application/json',
            'Idempotency-Key': job.event_key,
          },
          body: JSON.stringify({ from, to: [to], ...body }),
        });
        if (response.ok) {
          const sent = await response.json();
          providerId = typeof sent?.id === 'string' ? sent.id : null;
          result = 'sent';
        } else {
          const errorBody = response.status === 409
            ? await response.text() : '';
          const concurrent = response.status === 409 &&
            errorBody.includes('concurrent_idempotent_requests');
          errorCode = concurrent ? 'RESEND_409_CONCURRENT'
            : `RESEND_${response.status}`;
          result = concurrent || response.status === 429 || response.status >= 500
            ? 'retry' : 'dead';
        }
      }
    } catch {
      errorCode = 'TRANSPORT_ERROR';
    }
    const { error: finishError } = await db.rpc('finish_transactional_email', {
      p_id: job.id,
      p_lease: job.lease_id,
      p_result: result,
      p_provider_id: providerId,
      p_error: errorCode,
    });
    if (finishError) console.error('TRANSACTIONAL_EMAIL_ACK_FAILED');
  }
  return Response.json({ processed: jobs.length });
});
