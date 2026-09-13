-- ============================================================
-- SAGANA — Authorization fix for distribute_program_benefit()
-- distribute_program_benefit() is SECURITY DEFINER and granted
-- to authenticated, but — unlike its sibling confirm_program_return()
-- in the same feature — it never checked that the caller is an
-- admin. Any authenticated account (Farmer, Buyer, or Staff) could
-- call it directly and deduct cooperative_inventory stock against
-- any program_members row, bypassing that table's RLS entirely via
-- the SECURITY DEFINER path. This adds the same admin_profiles
-- check confirm_program_return() already uses.
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
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can distribute a program benefit';
  END IF;

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

NOTIFY pgrst, 'reload schema';
