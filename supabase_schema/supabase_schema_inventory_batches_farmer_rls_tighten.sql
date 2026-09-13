-- Warning 4.1 (M-8): the farmer RLS policy on inventory_batches was FOR ALL
-- (SELECT/INSERT/UPDATE/DELETE), letting a farmer's client issue a raw
-- write directly against their own batch row and bypass every
-- reservation-aware RPC (update_batch_available_quantity,
-- delete_inventory_batch, and the shared _apply_batch_reservation /
-- _release_batch_reservation helpers every disposal path depends on).
-- No current code path does this — InventoryRepository's only mutating
-- calls are update_batch_available_quantity and delete_inventory_batch,
-- both RPCs — so this closes the gap at the database level too, matching
-- the precedent already set for marketplace_listings
-- (supabase_schema_marketplace_listings_farmer_rls_tighten.sql) and
-- orders (supabase_schema_orders_farmer_update_removal.sql).
--
-- Narrowed to SELECT only: confirmed no repository ever does a raw
-- .insert() into this table either — creation happens via harvest entry
-- RPCs, which bypass RLS regardless of what this policy grants.

DROP POLICY IF EXISTS "inventory_batches: farmer manages own" ON public.inventory_batches;

CREATE POLICY "inventory_batches: farmer reads own"
  ON public.inventory_batches FOR SELECT
  USING (auth.uid() = farmer_id);