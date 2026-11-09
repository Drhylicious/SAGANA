-- ============================================================
-- SAGANA — Marketplace product card: "N buyers" per listing
--
-- FOR YOUR REVIEW — NOT APPLIED. Run it once in the Supabase SQL editor.
-- One transaction, safe to re-run. Run the CHECKS at the bottom first if you
-- want to see the current state.
--
-- WHY
--   The Marketplace product card (Buyer Browse and the Farmer's Marketplace
--   pane) now shows how many different buyers have bought a listing, beside its
--   price, exactly like the Product Sales card. Only the view below had the
--   quantity sold; nothing had a buyer count.
--
-- WHAT IS COUNTED  (same rule as "sold" on the same card)
--   Only COMPLETED orders (the consumer confirmed receipt). Pending, approved
--   and cancelled orders are not sales.
--     buyers = number of DIFFERENT people with a completed order on the listing.
--   A Farmer who bought as a consumer counts as a buyer too (orders.buyer_id
--   holds whoever placed the order).
--   It is a COUNT only. Who bought, and what anyone paid, is never exposed.
--
-- WHAT IT CHANGES
--   1. View marketplace_listing_units_sold   adds the column `buyers`
--      (appended after sold_kg; existing columns, order and GRANTs unchanged).
--   2. Function public_marketplace_listings  (Guest mode) adds `buyers` to each
--      returned listing. It is patched IN PLACE from the live definition (the
--      one object `'sold_kg', COALESCE(s.sold_kg, 0)` gets a `'buyers'` sibling),
--      so nothing else in the function, including anything changed since
--      supabase_schema_guest_public_access.sql, is overwritten. If that text is
--      not found the script stops and changes nothing.
--
-- NOT CHANGED: tables, RLS policies, place_order(), stock rules, any other view
-- or function. The app keeps working before this script is run (the buyer count
-- simply reads 0), and after it.
-- ============================================================

BEGIN;

-- ─── 1. Buyer count on the per-listing sales view ───────────────────────────
CREATE OR REPLACE VIEW public.marketplace_listing_units_sold AS
SELECT
  listing_id,
  SUM(quantity_kg)          AS sold_kg,
  COUNT(DISTINCT buyer_id)  AS buyers
FROM public.orders
WHERE status = 'completed'
GROUP BY listing_id;

GRANT SELECT ON public.marketplace_listing_units_sold TO authenticated;

-- ─── 2. Guest listings function: add `buyers` to the returned JSON ──────────
DO $patch$
DECLARE
  v_def     text;
  v_patched text;
BEGIN
  SELECT pg_get_functiondef(p.oid)
    INTO v_def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'public_marketplace_listings';

  IF v_def IS NULL THEN
    RAISE EXCEPTION 'public_marketplace_listings() does not exist. Run supabase_schema_guest_public_access.sql first.';
  END IF;

  IF v_def ~ '''buyers''\s*,' THEN
    RAISE NOTICE 'public_marketplace_listings() already returns buyers; left unchanged.';
    RETURN;
  END IF;

  v_patched := regexp_replace(
    v_def,
    '(''sold_kg''\s*,\s*COALESCE\(s\.sold_kg,\s*0\))',
    '\1,' || E'\n' || '        ''buyers'', COALESCE(s.buyers, 0)'
  );

  IF v_patched = v_def THEN
    RAISE EXCEPTION 'Could not find the sold_kg line in public_marketplace_listings(); nothing was changed. Send me the live definition (query C3 below).';
  END IF;

  EXECUTE v_patched;
END
$patch$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECKS (read-only; run after the script)
-- ============================================================
-- C1  The view has the new column, and only the columns you expect:
--     SELECT column_name FROM information_schema.columns
--      WHERE table_schema = 'public' AND table_name = 'marketplace_listing_units_sold'
--      ORDER BY ordinal_position;               -- listing_id, sold_kg, buyers
--
-- C2  Buyers agree with the completed orders (every row must be TRUE):
--     SELECT v.listing_id,
--            v.buyers,
--            v.buyers = (SELECT count(DISTINCT o.buyer_id) FROM public.orders o
--                         WHERE o.listing_id = v.listing_id AND o.status = 'completed') AS ok
--       FROM public.marketplace_listing_units_sold v;
--
-- C3  The guest function now returns it (and still has everything else):
--     SELECT pg_get_functiondef('public.public_marketplace_listings(integer,integer,uuid)'::regprocedure);
--     -- look for:  'sold_kg', COALESCE(s.sold_kg, 0),  'buyers', COALESCE(s.buyers, 0)
--
-- C4  Guest call returns a buyers value on each listing:
--     SELECT l->>'crop_name' AS crop, l->>'sold_kg' AS sold_kg, l->>'buyers' AS buyers
--       FROM jsonb_array_elements(public.public_marketplace_listings(10, 0, NULL)) AS l;
--
-- C5  (Before or after) place_order() still blocks a Farmer buying their own listing:
--     SELECT pg_get_functiondef(p.oid) ILIKE '%own listing%' AS blocks_own_listing
--       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--      WHERE n.nspname = 'public' AND p.proname = 'place_order';        -- true
--
-- C6  Units are on listings and orders' listings (nothing to run for the card;
--     this just shows the units in use):
--     SELECT unit, count(*) FROM public.marketplace_listings GROUP BY unit ORDER BY 2 DESC;
