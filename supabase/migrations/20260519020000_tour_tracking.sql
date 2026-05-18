-- ============================================================
-- Tour Tracking, Wallet Payment, and Activity RLS Migration
-- ============================================================

-- ── 1. Extend package_activities with tour tracking fields ───
ALTER TABLE public.package_activities
  ADD COLUMN IF NOT EXISTS tour_status text NOT NULL DEFAULT 'waiting_driver',
  ADD COLUMN IF NOT EXISTS current_spot_index integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS driver_latitude double precision,
  ADD COLUMN IF NOT EXISTS driver_longitude double precision,
  ADD COLUMN IF NOT EXISTS driver_last_seen timestamp with time zone,
  ADD COLUMN IF NOT EXISTS accepted_at timestamp with time zone,
  ADD COLUMN IF NOT EXISTS picked_up_at timestamp with time zone,
  ADD COLUMN IF NOT EXISTS dropped_off_at timestamp with time zone;

-- ── 2. Extend wallet_transactions ───────────────────────────
ALTER TABLE public.wallet_transactions
  ADD COLUMN IF NOT EXISTS booking_id uuid REFERENCES public.package_bookings(id),
  ADD COLUMN IF NOT EXISTS description text;

-- Extend type CHECK to include remaining_balance_payment
ALTER TABLE public.wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
ALTER TABLE public.wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check
  CHECK (type = ANY (ARRAY[
    'cash_in'::text,
    'package_payment'::text,
    'driver_earning'::text,
    'withdrawal'::text,
    'refund'::text,
    'remaining_balance_payment'::text
  ]));

-- ── 3. RLS: package_activities ───────────────────────────────
ALTER TABLE public.package_activities ENABLE ROW LEVEL SECURITY;

-- Tourists: view own
DROP POLICY IF EXISTS "Tourists can view own activities" ON public.package_activities;
CREATE POLICY "Tourists can view own activities"
  ON public.package_activities FOR SELECT TO authenticated
  USING (tourist_id = auth.uid());

-- Tourists: insert own
DROP POLICY IF EXISTS "Tourists can insert own activities" ON public.package_activities;
CREATE POLICY "Tourists can insert own activities"
  ON public.package_activities FOR INSERT TO authenticated
  WITH CHECK (tourist_id = auth.uid());

-- Drivers: view assigned OR pending/unassigned
DROP POLICY IF EXISTS "Drivers can view relevant activities" ON public.package_activities;
CREATE POLICY "Drivers can view relevant activities"
  ON public.package_activities FOR SELECT TO authenticated
  USING (
    driver_id = auth.uid()
    OR (
      driver_id IS NULL
      AND status = 'pending'
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid() AND p.role = 'driver'
      )
    )
  );

-- Drivers: update assigned OR accept pending
DROP POLICY IF EXISTS "Drivers can update relevant activities" ON public.package_activities;
CREATE POLICY "Drivers can update relevant activities"
  ON public.package_activities FOR UPDATE TO authenticated
  USING (
    driver_id = auth.uid()
    OR (
      driver_id IS NULL
      AND status = 'pending'
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid() AND p.role = 'driver'
      )
    )
  );

-- Admins/Subtenants: full access
DROP POLICY IF EXISTS "Admins can manage all activities" ON public.package_activities;
CREATE POLICY "Admins can manage all activities"
  ON public.package_activities FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role IN ('admin', 'subtenant')
    )
  );

-- ── 4. RLS: wallets ──────────────────────────────────────────
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own wallet" ON public.wallets;
CREATE POLICY "Users can view own wallet"
  ON public.wallets FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- ── 5. RLS: wallet_transactions ─────────────────────────────
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own transactions" ON public.wallet_transactions;
CREATE POLICY "Users can view own transactions"
  ON public.wallet_transactions FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert own transactions" ON public.wallet_transactions;
CREATE POLICY "Users can insert own transactions"
  ON public.wallet_transactions FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- ── 6. Wallet deduction DB function (SECURITY DEFINER) ──────
CREATE OR REPLACE FUNCTION public.deduct_wallet_balance(
  p_user_id      uuid,
  p_role         text,
  p_amount       numeric,
  p_booking_id   uuid,
  p_transaction_type text,
  p_description  text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet_id       uuid;
  v_current_balance numeric;
  v_transaction_id  uuid;
BEGIN
  SELECT id, balance
  INTO   v_wallet_id, v_current_balance
  FROM   public.wallets
  WHERE  user_id = p_user_id AND role = p_role
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'WALLET_NOT_FOUND';
  END IF;

  IF v_current_balance < p_amount THEN
    RAISE EXCEPTION 'INSUFFICIENT_BALANCE: balance=%, required=%',
      v_current_balance, p_amount;
  END IF;

  UPDATE public.wallets
  SET    balance = balance - p_amount,
         updated_at = now()
  WHERE  id = v_wallet_id;

  INSERT INTO public.wallet_transactions
    (wallet_id, user_id, role, type, amount, status,
     payment_method, booking_id, description)
  VALUES
    (v_wallet_id, p_user_id, p_role, p_transaction_type, p_amount,
     'completed', 'wallet', p_booking_id, p_description)
  RETURNING id INTO v_transaction_id;

  RETURN jsonb_build_object(
    'success',         true,
    'transaction_id',  v_transaction_id,
    'new_balance',     v_current_balance - p_amount
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.deduct_wallet_balance TO authenticated;

-- ── 7. Driver wallet credit function ────────────────────────
CREATE OR REPLACE FUNCTION public.credit_driver_wallet(
  p_driver_id   uuid,
  p_amount      numeric,
  p_booking_id  uuid,
  p_description text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet_id      uuid;
  v_transaction_id uuid;
BEGIN
  INSERT INTO public.wallets (user_id, role, balance)
  VALUES (p_driver_id, 'driver', 0)
  ON CONFLICT (user_id, role) DO NOTHING;

  SELECT id INTO v_wallet_id
  FROM   public.wallets
  WHERE  user_id = p_driver_id AND role = 'driver'
  FOR UPDATE;

  UPDATE public.wallets
  SET    balance = balance + p_amount,
         updated_at = now()
  WHERE  id = v_wallet_id;

  INSERT INTO public.wallet_transactions
    (wallet_id, user_id, role, type, amount, status,
     payment_method, booking_id, description)
  VALUES
    (v_wallet_id, p_driver_id, 'driver', 'driver_earning', p_amount,
     'completed', 'wallet', p_booking_id, p_description)
  RETURNING id INTO v_transaction_id;

  RETURN jsonb_build_object('success', true, 'transaction_id', v_transaction_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.credit_driver_wallet TO authenticated;

-- ── 8. Enable Supabase Realtime for package_activities ───────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname   = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename  = 'package_activities'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.package_activities;
  END IF;
END;
$$;
