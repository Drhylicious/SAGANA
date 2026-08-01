-- ============================================================
-- SAGANA — Loan Items ↔ Cooperative Inventory backfill
-- Completes the manual checkpoint from
-- supabase_schema_loan_inventory_link.sql. cooperative_inventory
-- is currently empty, so this creates one matching row per
-- unlinked loan_items_master row, then links them.
-- ============================================================

DO $$
DECLARE
  v_inv_id UUID;
  v_item RECORD;
BEGIN
  FOR v_item IN
    SELECT id, item_name, category, unit
    FROM public.loan_items_master
    WHERE inventory_item_id IS NULL
  LOOP
    INSERT INTO public.cooperative_inventory (item_name, category, unit, quantity_on_hand)
    VALUES (v_item.item_name, v_item.category, v_item.unit, 0)
    RETURNING id INTO v_inv_id;

    UPDATE public.loan_items_master
    SET inventory_item_id = v_inv_id
    WHERE id = v_item.id;
  END LOOP;
END;
$$;