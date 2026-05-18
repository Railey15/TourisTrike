-- ============================================================
-- TourisTrike Wallet System Migration
-- Creates: wallets, wallet_transactions, package_activities
-- ============================================================

-- ── 1. WALLETS ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.wallets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  role text NOT NULL DEFAULT 'tourist' CHECK (role IN ('tourist', 'driver')),
  balance numeric NOT NULL DEFAULT 0 CHECK (balance >= 0),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT wallets_pkey PRIMARY KEY (id),
  CONSTRAINT wallets_user_id_role_key UNIQUE (user_id, role),
  CONSTRAINT wallets_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- ── 2. WALLET TRANSACTIONS ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  wallet_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role text NOT NULL DEFAULT 'tourist',
  type text NOT NULL CHECK (type IN ('cash_in', 'package_payment', 'driver_earning', 'withdrawal', 'refund')),
  amount numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'failed', 'completed')),
  payment_method text CHECK (payment_method IN ('gcash', 'maya', 'card', 'wallet', 'cash')),
  paymongo_reference_id text,
  checkout_url text,
  metadata jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT wallet_transactions_pkey PRIMARY KEY (id),
  CONSTRAINT wallet_transactions_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id) ON DELETE CASCADE,
  CONSTRAINT wallet_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Prevent double-crediting the same PayMongo reference
CREATE UNIQUE INDEX IF NOT EXISTS wallet_transactions_paymongo_ref_idx
  ON public.wallet_transactions (paymongo_reference_id)
  WHERE paymongo_reference_id IS NOT NULL AND status = 'paid';

-- ── 3. PACKAGE ACTIVITIES ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.package_activities (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL,
  tourist_id uuid NOT NULL,
  driver_id uuid,
  package_id bigint NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'ongoing', 'completed', 'cancelled')),
  price numeric NOT NULL DEFAULT 0,
  payment_status text NOT NULL DEFAULT 'unpaid'
    CHECK (payment_status IN ('unpaid', 'paid', 'refunded')),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT package_activities_pkey PRIMARY KEY (id),
  CONSTRAINT package_activities_booking_id_key UNIQUE (booking_id),
  CONSTRAINT package_activities_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.package_bookings(id) ON DELETE CASCADE,
  CONSTRAINT package_activities_tourist_id_fkey FOREIGN KEY (tourist_id) REFERENCES public.profiles(id),
  CONSTRAINT package_activities_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.profiles(id),
  CONSTRAINT package_activities_package_id_fkey FOREIGN KEY (package_id) REFERENCES public.tour_packages(id)
);

-- ── 4. ROW-LEVEL SECURITY ────────────────────────────────────
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_activities ENABLE ROW LEVEL SECURITY;

-- Wallets: users read their own wallet
CREATE POLICY "users_read_own_wallet" ON public.wallets
  FOR SELECT USING (auth.uid() = user_id);

-- Wallet transactions: users read their own
CREATE POLICY "users_read_own_wallet_transactions" ON public.wallet_transactions
  FOR SELECT USING (auth.uid() = user_id);

-- Package activities: tourist reads own
CREATE POLICY "tourist_read_own_activities" ON public.package_activities
  FOR SELECT USING (auth.uid() = tourist_id);

-- Package activities: driver reads assigned activities
CREATE POLICY "driver_read_assigned_activities" ON public.package_activities
  FOR SELECT USING (auth.uid() = driver_id);

-- ── 5. HELPER FUNCTIONS ──────────────────────────────────────

-- Get or create a wallet for a user/role pair
CREATE OR REPLACE FUNCTION public.get_or_create_wallet(
  p_user_id uuid,
  p_role text DEFAULT 'tourist'
)
RETURNS public.wallets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet public.wallets;
BEGIN
  SELECT * INTO v_wallet
  FROM public.wallets
  WHERE user_id = p_user_id AND role = p_role;

  IF v_wallet IS NULL THEN
    INSERT INTO public.wallets (user_id, role, balance)
    VALUES (p_user_id, p_role, 0)
    RETURNING * INTO v_wallet;
  END IF;

  RETURN v_wallet;
END;
$$;

-- Credit wallet balance (called by webhook edge function via service_role)
CREATE OR REPLACE FUNCTION public.credit_wallet(
  p_wallet_id uuid,
  p_amount numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.wallets
  SET balance = balance + p_amount,
      updated_at = now()
  WHERE id = p_wallet_id;
END;
$$;

-- Debit wallet balance; returns TRUE if successful, FALSE if insufficient funds
CREATE OR REPLACE FUNCTION public.debit_wallet(
  p_user_id uuid,
  p_role text,
  p_amount numeric
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet public.wallets;
BEGIN
  SELECT * INTO v_wallet
  FROM public.wallets
  WHERE user_id = p_user_id AND role = p_role
  FOR UPDATE;

  IF v_wallet IS NULL OR v_wallet.balance < p_amount THEN
    RETURN false;
  END IF;

  UPDATE public.wallets
  SET balance = balance - p_amount,
      updated_at = now()
  WHERE id = v_wallet.id;

  RETURN true;
END;
$$;

-- ── 6. TRIGGERS ──────────────────────────────────────────────

-- Sync package_activities when a booking is created/updated
CREATE OR REPLACE FUNCTION public.sync_package_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
BEGIN
  v_status := CASE NEW.status
    WHEN 'confirmed' THEN 'accepted'
    ELSE NEW.status
  END;

  INSERT INTO public.package_activities (
    booking_id, tourist_id, package_id, status, price, payment_status
  ) VALUES (
    NEW.id,
    NEW.tourist_id,
    NEW.package_id,
    v_status,
    NEW.total_amount,
    CASE WHEN NEW.payment_method = 'wallet' THEN 'paid' ELSE 'unpaid' END
  )
  ON CONFLICT (booking_id) DO UPDATE SET
    status         = EXCLUDED.status,
    price          = EXCLUDED.price,
    payment_status = EXCLUDED.payment_status,
    updated_at     = now();

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_package_activity
  AFTER INSERT OR UPDATE ON public.package_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_package_activity();

-- Sync driver_id to package_activities when driver is assigned
CREATE OR REPLACE FUNCTION public.sync_activity_driver()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.package_activities
  SET driver_id  = NEW.driver_id,
      updated_at = now()
  WHERE booking_id = NEW.booking_id;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_activity_driver
  AFTER INSERT OR UPDATE ON public.booking_driver_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_activity_driver();

-- ── 7. BACKFILL EXISTING BOOKINGS ────────────────────────────
INSERT INTO public.package_activities (
  booking_id, tourist_id, driver_id, package_id, status, price, payment_status
)
SELECT
  pb.id,
  pb.tourist_id,
  pb.assigned_driver_id,
  pb.package_id,
  CASE pb.status
    WHEN 'confirmed' THEN 'accepted'
    ELSE pb.status
  END,
  pb.total_amount,
  CASE WHEN pb.payment_method = 'wallet' THEN 'paid' ELSE 'unpaid' END
FROM public.package_bookings pb
ON CONFLICT (booking_id) DO NOTHING;
