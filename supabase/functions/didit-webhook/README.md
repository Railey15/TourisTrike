# Didit webhook

This Edge Function receives `status.updated` KYC session callbacks for the existing
Compliance workflow. It verifies `X-Signature-V2` (or the full raw-body
`X-Signature`), checks the signed timestamp, and stores minimal event metadata in
`public.didit_verification_events`. Duplicate `event_id` deliveries are safe.
Identity documents, `vendor_data`, and the detailed `decision` payload are not stored here.

Endpoint:

`https://mvtqhsrdgtwdeootgjci.supabase.co/functions/v1/didit-webhook`

The existing Didit destination already points to this URL with webhook version
**v3** and subscribed event **`status.updated`**. Do not create another destination
or workflow. Its signing secret is stored as the Supabase Edge Function secret
`DIDIT_WEBHOOK_SECRET`, separate from the Didit Integration API key. Never add
either secret to Flutter, `.env`, or source control.

Set `DIDIT_WORKFLOW_ID` to the existing Compliance workflow's stable ID when
enabling real session creation. The webhook then also restricts callbacks to
that workflow. Didit's signed synthetic **Test Webhook** has been accepted with
HTTP 200 without writing production verification records.

The event ledger is private to the service role. For a real signed callback,
the receiver updates identity verification only when `session_id` matches a
server-created Driver verification record. An unknown session remains unlinked.
Neither a Didit result nor a synthetic test changes MTO Driver approval.
