-- ============================================================
-- SAGANA — Marketplace Overview KPIs: what each card SHOULD show (read-only)
--
-- Run this in the Supabase SQL editor and compare each value with the matching
-- card on Manager/Officer -> Marketplace. It changes nothing.
--
--   All Listings      every marketplace listing that is not withdrawn
--                     (= the "All" chip of All Listings)
--   Pending Approval  listings waiting for review (status pending_review)
--   Buyers            every Buyer account (= "All" in Buyer Management)
--   Orders            every order, whatever its status
--   Market Linking    every Market Linking request (= the "All" chip of the
--                     Market Linking screen)
--   Coop Offers       offers waiting for the COOPERATIVE to answer: open offers
--                     whose last proposal came from the Farmer
--   alerts            Farmers with an open Market Linking request, and
--                     cancellation requests waiting for a review
--
-- The SQL editor sees every row. If the app shows a different number, the signed
-- in account is not allowed to read some rows (a row level security question),
-- or the screen has not refreshed yet.
-- ============================================================

SELECT 'All Listings' AS kpi, count(*) AS value
  FROM public.marketplace_listings WHERE status <> 'withdrawn'
UNION ALL
SELECT 'Pending Approval', count(*)
  FROM public.marketplace_listings WHERE status = 'pending_review'
UNION ALL
SELECT 'Buyers', count(*)
  FROM public.user_roles WHERE role = 'buyer'
UNION ALL
SELECT 'Orders', count(*)
  FROM public.orders
UNION ALL
SELECT 'Market Linking', count(*)
  FROM public.market_linking_programs WHERE status <> 'requested'
UNION ALL
SELECT 'Coop Offers', count(*)
  FROM public.cooperative_purchase_offers
 WHERE status = 'pending' AND last_proposed_by = 'farmer'
UNION ALL
SELECT '(alert) Farmers with an open Market Linking request', count(DISTINCT farmer_id)
  FROM public.market_linking_programs WHERE status IN ('submitted', 'buyer_found');

-- Needs supabase_schema_market_linking_buyer_cancellation.sql (adds the column):
-- SELECT '(alert) Cancellation requests waiting' AS kpi, count(*) AS value
--   FROM public.market_linking_programs
--  WHERE status IN ('submitted', 'buyer_found') AND cancellation_status = 'requested';

-- Breakdown behind the Orders and Listings cards, if you want to see the parts:
-- SELECT status, count(*) FROM public.orders GROUP BY status ORDER BY 1;
-- SELECT status, count(*) FROM public.marketplace_listings GROUP BY status ORDER BY 1;
