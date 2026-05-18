-- Add booking_type, downpayment_amount, remaining_balance to package_bookings
ALTER TABLE public.package_bookings
  ADD COLUMN IF NOT EXISTS booking_type text NOT NULL DEFAULT 'advanced'
    CHECK (booking_type = ANY (ARRAY['same_day'::text, 'advanced'::text])),
  ADD COLUMN IF NOT EXISTS downpayment_amount numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS remaining_balance numeric NOT NULL DEFAULT 0;

-- Extend payments.payment_status to support dp_paid and fully_paid
ALTER TABLE public.payments
  DROP CONSTRAINT IF EXISTS payments_payment_status_check;
ALTER TABLE public.payments
  ADD CONSTRAINT payments_payment_status_check
  CHECK (payment_status = ANY (ARRAY[
    'pending'::text, 'paid'::text, 'failed'::text,
    'cancelled'::text, 'refunded'::text,
    'dp_paid'::text, 'fully_paid'::text
  ]));
