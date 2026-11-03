-- READ ONLY. Run AFTER supabase_schema_guest_public_access.sql.
-- Proves what the signed-out (anon) role can and cannot read.
-- Each block is independent; run them one at a time in the SQL editor.
-- Blocks that SET ROLE end with RESET ROLE.

-- A. Functions exist and anon can execute them (expect 5 rows, anon_can_execute = true)
SELECT p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authed_can_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname LIKE 'public\_%' ESCAPE '\'
ORDER BY p.proname;

-- B. anon has NO direct table access to private data (expect every row = false)
SELECT t AS table_name, has_table_privilege('anon', 'public.' || t, 'SELECT') AS anon_can_select
FROM unnest(ARRAY[
  'marketplace_listings','inventory_batches','harvest_records','orders',
  'farmer_profiles','buyer_profiles','admin_profiles','user_roles',
  'price_records','crop_master','market_types','notifications','loans'
]) AS t
WHERE to_regclass('public.' || t) IS NOT NULL;

-- C. As anon: private tables must be unreadable (expect "permission denied" or 0 rows)
--    Run each line separately; an error here is the GOOD outcome.
-- SET LOCAL ROLE anon; SELECT count(*) FROM public.farmer_profiles;
-- SET LOCAL ROLE anon; SELECT count(*) FROM public.orders;
-- SET LOCAL ROLE anon; SELECT count(*) FROM public.user_roles;

-- D. As anon: the public functions return only Buyer-visible market data
BEGIN;
SET LOCAL ROLE anon;
SELECT jsonb_array_length(public.public_marketplace_listings(5, 0)) AS listings_returned;
SELECT DISTINCT e->>'market_type' AS market_type
FROM jsonb_array_elements(public.public_marketplace_listings(200, 0)) e;   -- expect only Buyer-visible codes
SELECT DISTINCT e->>'price_type' AS price_type
FROM jsonb_array_elements(public.public_latest_prices()) e;                -- expect only Buyer-visible codes
SELECT (public.public_marketplace_listings(1, 0)->0) ? 'farmer_id' AS leaks_farmer_id;  -- expect false
RESET ROLE;
ROLLBACK;

-- E. Cross-check: the public count equals what the base tables say (expect equal)
SELECT
  (SELECT count(*) FROM public.marketplace_listings ml
     WHERE ml.status = 'approved'
       AND (ml.crop_type IS NULL OR EXISTS (SELECT 1 FROM public.market_types mt
            WHERE mt.code = ml.crop_type AND mt.buyer_visible)))               AS expected_public,
  (SELECT count(*) FROM jsonb_array_elements(public.public_marketplace_listings(200, 0))) AS returned_by_function;
