-- READ ONLY. Investigates the 25 kg "reserved" on the batch behind offer
-- 22cba6b1-b7ea-4c3d-9a11-7c36f94e0e29 (offered 60 kg, accepted 35 kg).
-- No updates, no RPC calls. Returns ONE result set.
--
-- What the code says: inventory_batches.reserved_kg is derived by trigger as
--   quantity_kg - available_kg - sold_kg - adjusted_kg   (floored at 0).
-- Result when run (2026-10-29): the 25 kg is held by an approved Marketplace
-- listing whose orders total 25 kg (10 + 5 pending, 10 approved), so it is a
-- genuine reservation, not an orphan. If you run this on another batch, read the
-- 'marketplace_listing', 'order' and 'cooperative_offer' rows: a reservation with
-- no active holder among them would be orphaned.
WITH target AS (
  SELECT '22cba6b1-b7ea-4c3d-9a11-7c36f94e0e29'::uuid AS offer_id
), b AS (
  SELECT ib.* FROM public.inventory_batches ib
  JOIN public.cooperative_purchase_offers o ON o.inventory_batch_id = ib.id
  JOIN target t ON t.offer_id = o.id
)
-- 1. The batch arithmetic.
SELECT 'batch' AS holder, to_jsonb(b) AS detail,
  jsonb_build_object(
    'quantity', b.quantity_kg, 'available', b.available_kg, 'sold', b.sold_kg,
    'adjusted', b.adjusted_kg, 'reserved_stored', b.reserved_kg,
    'reserved_by_formula', GREATEST(round(b.quantity_kg - b.available_kg - b.sold_kg - b.adjusted_kg, 2), 0)
  ) AS note
FROM b
UNION ALL
-- 2. Every possible holder of a reservation on that batch.
SELECT 'marketplace_listing', to_jsonb(l), NULL FROM public.marketplace_listings l JOIN b ON l.inventory_batch_id = b.id
UNION ALL
SELECT 'order', to_jsonb(o), NULL FROM public.orders o
  JOIN public.marketplace_listings l ON l.id = o.listing_id JOIN b ON l.inventory_batch_id = b.id
UNION ALL
SELECT 'cooperative_offer', to_jsonb(c),
  jsonb_build_object('offered', c.offered_quantity_kg, 'confirmed', c.confirmed_quantity_kg,
    'unconfirmed_remainder', c.offered_quantity_kg - COALESCE(c.confirmed_quantity_kg, 0))
FROM public.cooperative_purchase_offers c JOIN b ON c.inventory_batch_id = b.id
UNION ALL
SELECT 'market_linking_program', to_jsonb(m), NULL FROM public.market_linking_programs m JOIN b ON m.inventory_batch_id = b.id
UNION ALL
SELECT 'market_linking_sale', to_jsonb(s), NULL FROM public.market_linking_sales s JOIN b ON s.inventory_batch_id = b.id
UNION ALL
SELECT 'informal_sale', to_jsonb(i), NULL FROM public.informal_sales i JOIN b ON i.inventory_batch_id = b.id
UNION ALL
-- 3. Which reconcile_batch_sold() is live? It must count cooperative offers with
-- status 'completed'. A definition that counts only 'confirmed' (the older
-- supabase_schema_market_linking_partial_sales.sql version) would understate Sold
-- for every completed offer, so check it here as well.
SELECT 'reconcile_batch_sold_definition',
  jsonb_build_object('counts_completed_offers', pg_get_functiondef(p.oid) ~ 'c\.status = ''completed''',
                     'counts_confirmed_offers', pg_get_functiondef(p.oid) ~ 'c\.status = ''confirmed'''),
  NULL
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'reconcile_batch_sold';
