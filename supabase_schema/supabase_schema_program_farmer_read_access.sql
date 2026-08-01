-- ============================================================
-- SAGANA — Farmer read access for My Programs
-- A farmer must be able to see a program's name/details even
-- after it's completed (not just while active), and must be able
-- to read the specific inventory item they were given.
--
-- DROP POLICY IF EXISTS first: CREATE POLICY has no IF NOT EXISTS
-- form, so without this a re-run of this file would fail with
-- "policy already exists" — same lesson learned from the
-- approve_crop_request overload issue earlier.
-- ============================================================

DROP POLICY IF EXISTS "cooperative_programs: farmer reads own enrolled"
  ON public.cooperative_programs;

CREATE POLICY "cooperative_programs: farmer reads own enrolled"
  ON public.cooperative_programs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.program_members pm
      WHERE pm.program_id = cooperative_programs.id AND pm.farmer_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "cooperative_inventory: farmer reads items from own enrollments"
  ON public.cooperative_inventory;

CREATE POLICY "cooperative_inventory: farmer reads items from own enrollments"
  ON public.cooperative_inventory FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.program_members pm
      WHERE pm.inventory_item_id = cooperative_inventory.id AND pm.farmer_id = auth.uid()
    )
  );

NOTIFY pgrst, 'reload schema';
