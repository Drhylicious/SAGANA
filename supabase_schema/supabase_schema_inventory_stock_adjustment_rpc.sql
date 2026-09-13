-- ============================================================
-- SAGANA — Atomic inventory stock adjustment
-- AdminInventoryScreen's adjustStock() previously did a plain
-- client-side read-then-write (SELECT quantity_on_hand, compute
-- in Dart, then UPDATE) with no row lock — a lost-update race if
-- two writes to the same cooperative_inventory row happen close
-- together (two admins restocking, or a manual adjustment landing
-- alongside a loan/program distribution's automatic deduction).
-- This replaces it with a single atomic RPC using FOR UPDATE,
-- matching the pattern already used by issue_loan() and
-- distribute_program_benefit(). Business behavior is otherwise
-- unchanged: quantity still floors at zero rather than rejecting
-- (this is a manual correction flow, not a stock-reservation flow,
-- so preserving floor-at-zero rather than switching to reject-on-
-- insufficient-stock is intentional, not an oversight).
-- ============================================================

CREATE OR REPLACE FUNCTION adjust_inventory_stock(
  p_inventory_id UUID,
  p_quantity NUMERIC, -- positive = restock, negative = deduct
  p_transaction_type TEXT,
  p_notes TEXT DEFAULT NULL,
  p_recorded_by UUID DEFAULT NULL
)
RETURNS NUMERIC -- new quantity_on_hand, for the caller's own display use
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current NUMERIC;
  v_new NUMERIC;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can adjust cooperative inventory stock';
  END IF;

  SELECT quantity_on_hand INTO v_current
    FROM cooperative_inventory
    WHERE id = p_inventory_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory item % no longer exists', p_inventory_id;
  END IF;

  v_new := GREATEST(v_current + p_quantity, 0);

  UPDATE cooperative_inventory
  SET quantity_on_hand = v_new,
      last_restocked_at = CASE WHEN p_quantity > 0 THEN NOW() ELSE last_restocked_at END
  WHERE id = p_inventory_id;

  INSERT INTO inventory_transactions (
    inventory_id, transaction_type, quantity, notes, recorded_by
  ) VALUES (
    p_inventory_id, p_transaction_type, p_quantity, p_notes, p_recorded_by
  );

  RETURN v_new;
END;
$$;

GRANT EXECUTE ON FUNCTION adjust_inventory_stock TO authenticated;

NOTIFY pgrst, 'reload schema';
