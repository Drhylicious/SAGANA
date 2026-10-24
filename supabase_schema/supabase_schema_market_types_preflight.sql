-- ============================================================
-- SAGANA — Market Types vs Selling Channels: PRE-FLIGHT (READ-ONLY)
--
-- Nothing here changes data. Run each numbered query on its own and send the
-- results back. Sections:
--   A. Why a Buyer can still see Cooperative Market listings
--   B. Everything that currently stores 'da_amad_market'
--   C. Live structure (constraints, generated columns, functions) that the
--      restructuring would touch
-- ============================================================

-- ─── A. BUYER LEAK DIAGNOSIS ─────────────────────────────────────────────

-- A1. The rule by account (buyer must be false; admin/officer/active farmer true).
SELECT ur.role, ur.status, ui.username,
       public.can_access_cooperative_market(ur.user_id) AS can_access_cooperative
FROM public.user_roles ur
JOIN public.user_information ui ON ui.user_id = ur.user_id
ORDER BY ur.role, ur.status, ui.username;

-- A2. Which Buyers have ordered a Cooperative Market listing? The restrictive
--     policy deliberately lets a buyer read a listing they already ordered
--     (so order history can show the crop name and photo). That clause is NOT
--     limited to order screens, so it also makes the listing appear in Browse.
--     If your test buyer appears here for Palay and Peanut, that is the cause.
SELECT ml.id AS listing_id, ml.crop_name, ml.crop_type, ml.status,
       ui.username AS buyer_username, count(*) AS orders
FROM public.marketplace_listings ml
JOIN public.orders o            ON o.listing_id = ml.id
JOIN public.user_roles ur       ON ur.user_id = o.buyer_id AND ur.role = 'buyer'
JOIN public.user_information ui ON ui.user_id = o.buyer_id
WHERE ml.crop_type = 'sp3_cooperative'
GROUP BY 1, 2, 3, 4, 5
ORDER BY 2, 5;

-- A3. The policy is installed and RESTRICTIVE (expect 1 row).
SELECT policyname, permissive, cmd, qual
FROM pg_policies
WHERE tablename = 'marketplace_listings'
  AND policyname = 'marketplace_listings: cooperative market hidden from buyers';

-- ─── B. WHERE 'da_amad_market' IS STORED TODAY ───────────────────────────

-- B1. Row counts per table.
SELECT 'crop_master' AS tbl, count(*) AS rows FROM public.crop_master WHERE crop_type = 'da_amad_market'
UNION ALL SELECT 'crop_requests',              count(*) FROM public.crop_requests              WHERE crop_type = 'da_amad_market'
UNION ALL SELECT 'inventory_batches',          count(*) FROM public.inventory_batches          WHERE crop_type = 'da_amad_market'
UNION ALL SELECT 'marketplace_listings',       count(*) FROM public.marketplace_listings       WHERE crop_type = 'da_amad_market'
UNION ALL SELECT 'cooperative_purchase_offers',count(*) FROM public.cooperative_purchase_offers WHERE crop_type = 'da_amad_market'
UNION ALL SELECT 'informal_sales',             count(*) FROM public.informal_sales             WHERE crop_type = 'da_amad_market'
UNION ALL SELECT 'price_records (price_type)', count(*) FROM public.price_records              WHERE price_type = 'da_amad_market';

-- B2. Which crops carry it.
SELECT id, crop_name, crop_type, is_active, is_cooperative_eligible
FROM public.crop_master WHERE crop_type = 'da_amad_market';

-- B3. DA-AMAD price records (these are the only rows whose "market type" is a
--     PRICE category rather than a crop's classification).
SELECT crop_name, price, unit, recorded_at, source
FROM public.price_records WHERE price_type = 'da_amad_market'
ORDER BY recorded_at DESC;

-- B4. Ginger on a channel it must not use (expect ZERO rows from each).
SELECT 'marketplace_listings' AS channel, ml.id, ml.status
FROM public.marketplace_listings ml
JOIN public.inventory_batches ib ON ib.id = ml.inventory_batch_id
WHERE ib.crop_type = 'da_amad_market'
UNION ALL
SELECT 'cooperative_purchase_offers', co.id, co.status
FROM public.cooperative_purchase_offers co
JOIN public.inventory_batches ib ON ib.id = co.inventory_batch_id
WHERE ib.crop_type = 'da_amad_market'
UNION ALL
SELECT 'informal_sales', isl.id, NULL
FROM public.informal_sales isl
JOIN public.inventory_batches ib ON ib.id = isl.inventory_batch_id
WHERE ib.crop_type = 'da_amad_market';

-- B5. The DA-AMAD channel itself: enrollments and Market Linking submissions.
SELECT 'da_amad_enrollments' AS what, status, count(*) FROM public.da_amad_enrollments GROUP BY status
UNION ALL
SELECT 'market_linking_programs', status, count(*) FROM public.market_linking_programs GROUP BY status
ORDER BY 1, 2;

-- B6. Market Linking submissions whose batch is NOT a DA-AMAD crop (expect ZERO;
--     submit_ginger_for_sale() does not check the batch's crop).
SELECT mlp.id, mlp.crop_name, mlp.status, ib.batch_number, ib.crop_type
FROM public.market_linking_programs mlp
JOIN public.inventory_batches ib ON ib.id = mlp.inventory_batch_id
WHERE ib.crop_type IS DISTINCT FROM 'da_amad_market';

-- B7. Ginger harvest and stock currently on hand (must survive the restructuring).
SELECT ib.status, count(*) AS batches, round(sum(ib.available_kg)::numeric, 2) AS available_kg
FROM public.inventory_batches ib
WHERE ib.crop_type = 'da_amad_market'
GROUP BY ib.status ORDER BY ib.status;

-- ─── C. LIVE STRUCTURE ───────────────────────────────────────────────────

-- C1. Every CHECK constraint that lists market-type values (names are needed to replace them).
SELECT conrelid::regclass AS tbl, conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE contype = 'c' AND pg_get_constraintdef(oid) ILIKE '%da_amad_market%'
ORDER BY 1, 2;

-- C2. Generated columns (is_cooperative_eligible is one).
SELECT table_name, column_name, generation_expression
FROM information_schema.columns
WHERE table_schema = 'public' AND generation_expression IS NOT NULL
ORDER BY 1, 2;

-- C3. Live bodies of every function that mentions Ginger or da_amad. These are
--     the functions the restructuring would edit; I need the live text, not the
--     repository copies. (Output is long: export as CSV.)
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND (p.prosrc ILIKE '%ginger%' OR p.prosrc ILIKE '%da_amad%' OR p.prosrc ILIKE '%crop_type%')
ORDER BY p.proname;

-- C4. Policies and views that mention these values.
SELECT 'policy' AS kind, tablename AS name, policyname AS detail, qual AS definition
FROM pg_policies
WHERE schemaname = 'public' AND (qual ILIKE '%da_amad%' OR qual ILIKE '%crop_type%' OR with_check ILIKE '%crop_type%')
UNION ALL
SELECT 'view', viewname, NULL, definition
FROM pg_views
WHERE schemaname = 'public' AND (definition ILIKE '%da_amad%' OR definition ILIKE '%crop_type%');

-- C5. Server-side self-purchase guard still present in the live place_order?
--     (expect true)
SELECT p.oid::regprocedure AS signature,
       p.prosrc ILIKE '%own listing%' AS blocks_own_listing
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'place_order';
