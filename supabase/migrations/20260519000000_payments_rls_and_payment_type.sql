-- Add payment_type column to payments
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS payment_type text NOT NULL DEFAULT 'full_payment'
    CHECK (payment_type = ANY (ARRAY[
      'full_payment'::text,
      'down_payment'::text,
      'remaining_balance'::text
    ]));

-- Enable RLS on payments (safe to call even if already enabled)
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- Tourists: insert their own payment records
DROP POLICY IF EXISTS "Tourists can insert own payments" ON public.payments;
CREATE POLICY "Tourists can insert own payments"
  ON public.payments
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Tourists: view their own payment records
DROP POLICY IF EXISTS "Tourists can view own payments" ON public.payments;
CREATE POLICY "Tourists can view own payments"
  ON public.payments
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Admins and subtenants: view all payments (e.g. for the booking management screens)
DROP POLICY IF EXISTS "Admins and subtenants can view all payments" ON public.payments;
CREATE POLICY "Admins and subtenants can view all payments"
  ON public.payments
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('admin', 'subtenant')
    )
  );

-- Admins: update payments (e.g. marking remaining balance as paid)
DROP POLICY IF EXISTS "Admins can update payments" ON public.payments;
CREATE POLICY "Admins can update payments"
  ON public.payments
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
    )
  );
