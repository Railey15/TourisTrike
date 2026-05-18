-- Atomic wallet cash-in completion for PayMongo webhooks.

CREATE OR REPLACE FUNCTION public.complete_wallet_cash_in(
  p_transaction_id uuid,
  p_paymongo_reference_id text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb,
  p_paid_amount numeric DEFAULT NULL,
  p_final_status text DEFAULT 'paid'
)
RETURNS TABLE (
  applied boolean,
  transaction_id uuid,
  wallet_id uuid,
  user_id uuid,
  amount numeric,
  status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx public.wallet_transactions;
  v_amount numeric;
  v_status text;
BEGIN
  IF p_transaction_id IS NULL THEN
    RETURN;
  END IF;

  SELECT *
  INTO v_tx
  FROM public.wallet_transactions
  WHERE id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_tx.type <> 'cash_in' THEN
    RETURN QUERY
    SELECT false, v_tx.id, v_tx.wallet_id, v_tx.user_id, v_tx.amount, v_tx.status;
    RETURN;
  END IF;

  IF v_tx.status IN ('paid', 'completed') THEN
    RETURN QUERY
    SELECT false, v_tx.id, v_tx.wallet_id, v_tx.user_id, v_tx.amount, v_tx.status;
    RETURN;
  END IF;

  IF v_tx.status <> 'pending' THEN
    RETURN QUERY
    SELECT false, v_tx.id, v_tx.wallet_id, v_tx.user_id, v_tx.amount, v_tx.status;
    RETURN;
  END IF;

  v_amount := COALESCE(p_paid_amount, v_tx.amount);

  IF v_amount IS NULL OR v_amount <= 0 THEN
    v_amount := v_tx.amount;
  END IF;

  v_status := CASE
    WHEN p_final_status IN ('paid', 'completed') THEN p_final_status
    ELSE 'paid'
  END;

  UPDATE public.wallet_transactions
  SET status = v_status,
      paymongo_reference_id = COALESCE(
        NULLIF(btrim(p_paymongo_reference_id), ''),
        paymongo_reference_id
      ),
      metadata = COALESCE(metadata, '{}'::jsonb) || COALESCE(p_metadata, '{}'::jsonb),
      updated_at = now()
  WHERE id = v_tx.id;

  UPDATE public.wallets
  SET balance = balance + v_amount,
      updated_at = now()
  WHERE id = v_tx.wallet_id;

  RETURN QUERY
  SELECT true, v_tx.id, v_tx.wallet_id, v_tx.user_id, v_amount, v_status;
END;
$$;
