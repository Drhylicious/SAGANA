-- ============================================================
-- SAGANA — Marketplace buyer names for Farmer Transaction History
-- (Farmer-Harvest Tab revision round — Transaction History feedback fix)
--
-- Farmer Transaction History's Marketplace channel tried to resolve a
-- buyer's name via a direct SELECT against user_information, scoped to
-- the farmer's session. That silently returns zero rows: user_information
-- only grants SELECT to the row's own owner, an admin, or staff (see
-- supabase_schema_auth.sql and supabase_schema_staff_dashboard_read_
-- access.sql) — there's no policy letting a farmer read a buyer's row,
-- so RLS filters it out with no error, and "Sold To" never appeared.
--
-- Widening user_information's own RLS policy would fix the immediate
-- symptom but over-grants: RLS is row-level, not column-level, so any
-- policy letting a farmer read a buyer's row at all would also expose
-- that buyer's phone_number and profile_photo_url, not just full_name —
-- fields nothing in this app currently shows a farmer. A SECURITY
-- DEFINER RPC scoped to exactly (order_id, buyer_name) for the calling
-- farmer's own completed orders keeps that data closed, same reasoning
-- already applied elsewhere in this schema for admin-action-notifies-
-- farmer cases.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION get_my_marketplace_buyer_names()
RETURNS TABLE(order_id UUID, buyer_name TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT o.id, ui.full_name
  FROM orders o
  JOIN user_information ui ON ui.user_id = o.buyer_id
  WHERE o.farmer_id = auth.uid()
    AND o.status = 'completed';
$$;

GRANT EXECUTE ON FUNCTION get_my_marketplace_buyer_names() TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- Run as an actual farmer session (not admin) with at least one
-- completed Marketplace order:
--   SELECT * FROM get_my_marketplace_buyer_names();
--   -- expect one row per completed order, with a non-null buyer_name
--
-- Cross-check against the same data an admin session already sees:
--   SELECT o.id, ui.full_name
--   FROM orders o JOIN user_information ui ON ui.user_id = o.buyer_id
--   WHERE o.farmer_id = '<that farmer's user id>' AND o.status = 'completed';
--   -- results should match exactly
