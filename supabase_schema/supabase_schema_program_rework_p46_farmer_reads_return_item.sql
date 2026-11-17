-- ============================================================
-- SAGANA — p46: a Farmer can read the RETURN item of their own enrollments (so the card names it)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run any time. No data is changed or deleted.
--
-- Problem: the Farmer's My Programs card names what they return from the return item saved on their enrollment
-- (Peanut Seeds -> Peanut). The existing read rule on cooperative_inventory only covers the item GIVEN
-- (pm.inventory_item_id), so the return item came back empty for a Farmer and the card fell back to the item given
-- ("10 kg Peanut Seeds"). Staff read all inventory, so they already saw "Peanut".
--
-- Fix: the same rule, plus the return item of the Farmer's own enrollments (pm.return_item_id). Nothing else about
-- who can read inventory changes. The Farmer sees the same fields of that item they already see for the given item.
-- ============================================================

BEGIN;

DROP POLICY IF EXISTS "cooperative_inventory: farmer reads items from own enrollments"
  ON public.cooperative_inventory;

CREATE POLICY "cooperative_inventory: farmer reads items from own enrollments"
  ON public.cooperative_inventory FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.program_members pm
      WHERE pm.farmer_id = auth.uid()
        AND (pm.inventory_item_id = cooperative_inventory.id
             OR pm.return_item_id = cooperative_inventory.id)
    )
  );

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECK (the rule now mentions return_item_id; expect 1 row):
--   SELECT policyname FROM pg_policies
--    WHERE tablename = 'cooperative_inventory'
--      AND policyname = 'cooperative_inventory: farmer reads items from own enrollments'
--      AND qual ILIKE '%return_item_id%';
