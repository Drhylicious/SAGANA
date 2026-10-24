-- ============================================================
-- SAGANA — Public Market / Cooperative Market visibility: PRE-FLIGHT
-- READ-ONLY. Run each query by itself and send back the results. Nothing here
-- changes data. The answers decide the exact backend rule that gets written.
-- ============================================================

-- A. Live read/write policies on the two tables the rule touches.
SELECT tablename, policyname, permissive, cmd, roles::text, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename IN ('marketplace_listings', 'orders')
ORDER BY tablename, cmd, policyname;

-- B. Which place_order version(s) are live (expect ONE row with the 10
--    fulfillment/delivery parameters; two rows means the 2-argument overload
--    from phase3/phase7 is still present).
SELECT oid::regprocedure AS signature
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname = 'place_order';

-- C. Today's listings by market type and status. This is what buyers can see
--    right now: every 'approved' row, whatever its crop_type.
SELECT coalesce(crop_type, '(null)') AS crop_type, status, count(*) AS listings
FROM public.marketplace_listings
GROUP BY 1, 2
ORDER BY 1, 2;

-- D. Listings / batches whose stored market type no longer matches the crop's
--    CURRENT market type in Crop Management (expect zero rows; any row means a
--    crop was re-classified after its harvest or listing was created).
SELECT ml.id AS listing_id, ml.status, ml.crop_name,
       ml.crop_type AS listing_type, cm.crop_type AS crop_master_type
FROM public.marketplace_listings ml
JOIN public.inventory_batches ib ON ib.id = ml.inventory_batch_id
JOIN public.farmer_crops fc ON fc.id = ib.crop_id
JOIN public.crop_master cm ON cm.id = fc.crop_master_id
WHERE ml.crop_type IS DISTINCT FROM cm.crop_type;

SELECT ib.id AS batch_id, ib.batch_number, ib.crop_type AS batch_type,
       cm.crop_name, cm.crop_type AS crop_master_type
FROM public.inventory_batches ib
JOIN public.farmer_crops fc ON fc.id = ib.crop_id
JOIN public.crop_master cm ON cm.id = fc.crop_master_id
WHERE ib.crop_type IS DISTINCT FROM cm.crop_type;

-- E. Rows with no market type at all (cannot be classified; the rule would
--    treat them as Public).
SELECT 'marketplace_listings' AS tbl, count(*) FROM public.marketplace_listings WHERE crop_type IS NULL
UNION ALL
SELECT 'inventory_batches', count(*) FROM public.inventory_batches WHERE crop_type IS NULL
UNION ALL
SELECT 'crop_master', count(*) FROM public.crop_master WHERE crop_type IS NULL;

-- F. Buyer orders that sit on Cooperative Market listings (these buyers keep
--    seeing their own order history; only new browsing/ordering is closed).
SELECT o.status, count(*) AS orders, count(DISTINCT o.buyer_id) AS buyers
FROM public.orders o
JOIN public.marketplace_listings ml ON ml.id = o.listing_id
JOIN public.user_roles ur ON ur.user_id = o.buyer_id
WHERE ml.crop_type = 'sp3_cooperative' AND ur.role = 'buyer'
GROUP BY o.status;

-- G. Crop Master as the Manager has classified it.
SELECT crop_name, crop_type, is_active FROM public.crop_master ORDER BY crop_type, crop_name;

