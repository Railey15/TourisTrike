# PayMongo Edge Function configuration

Set these with `supabase secrets set`; never place them in Flutter assets or
source control:

- `PAYMONGO_ENABLED` (`false` until test-mode rollout is intentional)
- `PAYMONGO_SECRET_KEY` (`sk_test_...` first)
- `PAYMONGO_WEBHOOK_SECRET`
- `PAYMONGO_ENVIRONMENT` (`test` or `live`)
- `PAYMONGO_SUCCESS_URL`
- `PAYMONGO_CANCEL_URL`
- `PAYMONGO_PAYMENT_METHOD_TYPES` (comma-separated allowlist; set to
  `gcash,paymaya,qrph,card` after enabling those methods in the PayMongo
  merchant account)
- `PAYMONGO_SPLIT_PAYMENTS_ENABLED` (`false` until Platforms/linked accounts
  and Payment Splitting are approved and driver merchant IDs are verified)
- `PAYMONGO_DISBURSEMENTS_ENABLED` (`false`; no disbursement endpoint is called
  by this implementation)

`paymongo-create-payment` accepts `booking_id`, `payment_stage`,
`payment_method`, and an idempotency key. Supported method identifiers are
`gcash`, `paymaya`, `qrph`, and `card`. Amounts and driver allocations are
loaded by the trusted database RPC. When splitting is disabled, allocations remain
held/payout-pending; no provider transfer or disbursement is claimed. Enable
splitting only after PayMongo approves the merchant relationship and every
driver recipient is verified.

PayMongo redirect URLs should be fully-qualified HTTPS URLs. Deploy the
`paymongo-payment-return` function and configure, for example:

- `PAYMONGO_SUCCESS_URL=https://PROJECT.supabase.co/functions/v1/paymongo-payment-return?result=success`
- `PAYMONGO_CANCEL_URL=https://PROJECT.supabase.co/functions/v1/paymongo-payment-return?result=cancel`
- `PAYMONGO_PAYMENT_METHOD_TYPES=gcash,paymaya,qrph,card`

That HTTPS page opens the registered `touristrike://wallet/payment/...` app
link and provides a manual return button if the browser blocks automatic app
opening. It never confirms payment; the webhook remains authoritative and
Realtime updates Tour Tracking.

Configure PayMongo webhooks to post to either deployed webhook endpoint:

- `https://PROJECT.supabase.co/functions/v1/paymongo-webhook`
- `https://PROJECT.supabase.co/functions/v1/paymongo-payment-webhook`

Both endpoints use the same signed webhook handler.
