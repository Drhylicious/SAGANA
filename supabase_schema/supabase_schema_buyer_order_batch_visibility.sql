-- ============================================================
-- SAGANA — Buyers can't see batch/harvest info behind their OWN orders
--
-- Root cause of the "Category: Grain" section looking isolated/empty on
-- the Buyer Order Detail screen (Batch Reference and Freshness never
-- show, only Category): two RLS gaps found while investigating, both
-- confirmed by reading supabase_schema_harvest.sql directly.
--
-- 1) harvest_records has NO buyer-read policy at all (only "farmer
--    manages own" and "admin reads all") — a buyer can never read
--    harvest_date for ANY listing/order, permanently, not just
--    sometimes. This is why Freshness never appears for buyers anywhere
--    it's attempted (Order Detail here, and the "Harvested X days ago"
--    pill on Listing Details, which silently never renders for the same
--    reason).
--
-- 2) inventory_batches' buyer policy is
--      USING (status = 'available' AND auth.role() = 'authenticated')
--    — a buyer can browse a batch while it's available, but loses read
--    access the moment its status changes (reserved/low_stock/sold_out)
--    as stock gets consumed by ANY buyer's order, including their own.
--    A buyer revisiting their own past order later can lose visibility
--    into Batch Reference entirely, even though the order itself is
--    still very much theirs.
--
-- Fix: add policies scoped to "a batch/harvest tied to an order this
-- buyer actually placed" — narrow (not blanket batch/harvest visibility),
-- additive (RLS policies for the same command OR together, so the
-- existing "browse available stock" policy is untouched), and permanent
-- regardless of the batch's current status.
-- ============================================================

CREATE POLICY "inventory_batches: buyers read own order batches"
  ON public.inventory_batches FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.marketplace_listings ml
      JOIN public.orders o ON o.listing_id = ml.id
      WHERE ml.inventory_batch_id = inventory_batches.id
        AND o.buyer_id = auth.uid()
    )
  );

CREATE POLICY "harvest_records: buyers read own order harvests"
  ON public.harvest_records FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.inventory_batches ib
      JOIN public.marketplace_listings ml ON ml.inventory_batch_id = ib.id
      JOIN public.orders o ON o.listing_id = ml.id
      WHERE ib.harvest_record_id = harvest_records.id
        AND o.buyer_id = auth.uid()
    )
  );

NOTIFY pgrst, 'reload schema';
