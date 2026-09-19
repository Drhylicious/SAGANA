-- ============================================================
-- SAGANA — Cooperative Product Sales Program: farmer inventory read fix
-- (Phase D bug — reported: farmer-side product catalog/purchase sheet
-- shows blank item name, blank unit, and "0 in stock" for a real,
-- in-stock product)
--
-- Root cause (confirmed against the live database, not assumed):
-- cooperative_inventory already had a farmer SELECT policy —
-- "cooperative_inventory: farmer reads items from own enrollments" —
-- but it only covers program_members.inventory_item_id, which is the
-- DISTRIBUTION workflow's linkage (what item a farmer was physically
-- given). It predates this feature and has no knowledge of
-- program_products, the SALES workflow's linkage. So a farmer's client
-- (subject to RLS, unlike the admin-side screens and unlike the
-- SECURITY DEFINER purchase RPCs, which bypass RLS entirely) got zero
-- rows back from the embedded cooperative_inventory(...) join in
-- FarmerProgramRepository.fetchAvailableProducts — PostgREST silently
-- returns the nested object as null when RLS blocks it, rather than
-- erroring, which is why item_name/unit/quantity_on_hand all rendered
-- as blank/zero instead of throwing anything visible.
--
-- This is why the purchase RPCs themselves were never actually broken —
-- request_program_purchase()/confirm_program_purchase() are SECURITY
-- DEFINER and read cooperative_inventory with the function owner's
-- privileges, not the caller's. Only the farmer-facing display query was
-- affected.
--
-- Fix: an additional, narrowly-scoped SELECT policy — a farmer may read
-- an inventory item if it's a currently-available product in a
-- program they have an ACTIVE enrollment in. Exactly mirrors
-- program_products' own RLS condition (supabase_schema_program_product
-- _sales.sql), just applied one join further out. Does not touch or
-- replace the existing distribution-workflow policy.
-- ============================================================

CREATE POLICY "cooperative_inventory: enrolled farmers read sales program items"
  ON public.cooperative_inventory FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.program_products pp
      JOIN public.program_members pm ON pm.program_id = pp.program_id
      WHERE pp.inventory_item_id = cooperative_inventory.id
        AND pp.is_available = TRUE
        AND pm.farmer_id = auth.uid()
        AND pm.status = 'active'
    )
  );

NOTIFY pgrst, 'reload schema';
