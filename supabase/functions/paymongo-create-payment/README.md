# PayMongo Edge Function configuration

Set these with `supabase secrets set`; never place them in Flutter assets or
source control:

- `PAYMONGO_ENABLED` (`false` until test-mode rollout is intentional)
- `PAYMONGO_SECRET_KEY` (`sk_test_...` first)
- `PAYMONGO_WEBHOOK_SECRET`
- `PAYMONGO_ENVIRONMENT` (`test` or `live`)
- `PAYMONGO_SUCCESS_URL`
- `PAYMONGO_CANCEL_URL`
- `PAYMONGO_CHECKOUT_API_VERSION` (`v2` by default for ordinary hosted
  checkout; enabled linked-account splitting uses the documented v1 shape)
- `PAYMONGO_SPLIT_PAYMENTS_ENABLED` (`false` until Platforms/linked accounts
  and Payment Splitting are approved and driver merchant IDs are verified)
- `PAYMONGO_DISBURSEMENTS_ENABLED` (`false`; no disbursement endpoint is called
  by this implementation)

`paymongo-create-payment` accepts only `booking_id`, `payment_stage`, and an
idempotency key. Amounts and driver allocations are loaded by the trusted
database RPC. When splitting is disabled, allocations remain
held/payout-pending; no provider transfer or disbursement is claimed. Enable
splitting only after PayMongo approves the merchant relationship and every
driver recipient is verified.

PayMongo redirect URLs should be fully-qualified HTTPS URLs. Deploy the
`paymongo-payment-return` function and configure, for example:

- `PAYMONGO_SUCCESS_URL=https://PROJECT.supabase.co/functions/v1/paymongo-payment-return?result=success`
- `PAYMONGO_CANCEL_URL=https://PROJECT.supabase.co/functions/v1/paymongo-payment-return?result=cancel`

That HTTPS page opens the registered `touristrike://wallet/payment/...` app
link and provides a manual return button if the browser blocks automatic app
opening. It never confirms payment; `paymongo-webhook` remains authoritative
and Realtime updates Tour Tracking.
