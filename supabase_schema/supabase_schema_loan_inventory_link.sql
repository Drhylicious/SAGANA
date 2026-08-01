-- ============================================================
-- SAGANA — Cooperative Inventory as Loan Catalog Source of Truth
-- ============================================================

-- Step 1: add link + loan-specific eligibility flag.
ALTER TABLE public.loan_items_master
  ADD COLUMN IF NOT EXISTS inventory_item_id UUID REFERENCES public.cooperative_inventory(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS is_loan_eligible BOOLEAN NOT NULL DEFAULT TRUE;

-- Step 2: MANUAL CHECKPOINT — do this by hand before Step 3.
-- For each of the 12 existing loan_items_master rows, link it to a
-- matching cooperative_inventory row (create the inventory row first if
-- none exists yet). Do NOT run Step 3 until every row has
-- inventory_item_id populated, or existing loan issuance will break.

-- Step 3 — run manually once Step 2 is confirmed done:
-- ALTER TABLE public.loan_items_master
--   ALTER COLUMN inventory_item_id SET NOT NULL,
--   DROP COLUMN IF EXISTS item_name,
--   DROP COLUMN IF EXISTS category,
--   DROP COLUMN IF EXISTS unit;

-- Atomic stock decrement for loan issuance — prevents a race condition if
-- two admins issue loans against the same item concurrently.
CREATE OR REPLACE FUNCTION decrement_inventory_stock(p_inventory_id UUID, p_quantity NUMERIC)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE cooperative_inventory
  SET quantity_on_hand = GREATEST(quantity_on_hand - p_quantity, 0)
  WHERE id = p_inventory_id;
END;
$$;

GRANT EXECUTE ON FUNCTION decrement_inventory_stock TO authenticated;

-- No new table needed for stock movement tracking — inventory_transactions
-- .transaction_type already includes 'loan_issued' from the original
-- cooperative_inventory schema; it was just never used until now.