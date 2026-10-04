-- Buyer Browse-tab rework — Phase 1 (additive only, no existing table/RPC/policy touched)
--
-- Buyer Browse tab needs a per-listing "units sold" figure (cumulative
-- completed kg). No existing column fits: marketplace_listings.remaining_kg
-- is decremented at *placement* time (reflects pending+approved+completed
-- minus cancelled, not strictly completed sales), and inventory_batches.sold_kg
-- is a batch-wide counter incremented by every disposal channel (cooperative
-- offer, market linking, marketplace), not scoped to one listing.
--
-- orders has row-level RLS restricting SELECT to auth.uid() = buyer_id /
-- farmer_id (or admin), so a client-side SUM(quantity_kg) WHERE listing_id=X
-- would silently return only the current user's own orders. This view follows
-- this codebase's existing precedent for a public read-aggregate that must
-- bypass per-row RLS: a plain VIEW granted to `authenticated`, same shape as
-- top_harvested_crops (supabase_schema_analytics_views_crop_id.sql).

CREATE OR REPLACE VIEW public.marketplace_listing_units_sold AS
SELECT
  listing_id,
  SUM(quantity_kg) AS sold_kg
FROM public.orders
WHERE status = 'completed'
GROUP BY listing_id;

GRANT SELECT ON public.marketplace_listing_units_sold TO authenticated;

NOTIFY pgrst, 'reload schema';
