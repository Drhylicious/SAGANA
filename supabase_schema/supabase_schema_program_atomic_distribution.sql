-- ============================================================
-- SAGANA — Atomic Program Benefit Distribution
-- Replaces ProgramRepository.distributeBenefit()'s three
-- sequential, non-transactional client calls (inventory_
-- transactions insert, decrement_inventory_stock RPC,
-- program_members update) with one atomic RPC. Same reasoning
-- as issue_loan(): a connectivity drop mid-operation must not
-- leave cooperative_inventory out of sync with what
-- program_members claims was distributed. Also closes the
-- silent-floor-at-zero gap — this now rejects and errors on
-- insufficient stock, consistent with issue_loan()'s behavior,
-- rather than silently distributing less than recorded.
-- ============================================================

CREATE OR REPLACE FUNCTION distribute_program_benefit(
  p_program_member_id UUID,
  p_inventory_item_id UUID,
  p_quantity NUMERIC,
  p_recorded_by UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_available NUMERIC;
  v_item_name TEXT;
BEGIN
  SELECT quantity_on_hand, item_name INTO v_available, v_item_name
    FROM cooperative_inventory
    WHERE id = p_inventory_item_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory item % no longer exists', p_inventory_item_id;
  END IF;

  IF v_available < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock for %: % on hand, % requested',
      v_item_name, v_available, p_quantity;
  END IF;

  UPDATE cooperative_inventory
  SET quantity_on_hand = quantity_on_hand - p_quantity
  WHERE id = p_inventory_item_id;

  INSERT INTO inventory_transactions (
    inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by
  ) VALUES (
    p_inventory_item_id, 'program_distribution', -p_quantity, p_program_member_id, 'program', p_recorded_by
  );

  UPDATE program_members
  SET inventory_item_id = p_inventory_item_id,
      quantity_given = p_quantity,
      distributed_at = NOW()
  WHERE id = p_program_member_id;
END;
$$;

GRANT EXECUTE ON FUNCTION distribute_program_benefit TO authenticated;
