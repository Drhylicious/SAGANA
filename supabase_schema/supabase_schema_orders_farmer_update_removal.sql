-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_orders_farmer_update_removal.sql
-- Run after supabase_schema_fixes.sql
--
-- Buyer module review, finding 2.8 (confirmed architectural/security risk).
--
-- "Farmers update order status" granted farmers unrestricted column-level
-- UPDATE on their own orders rows (status, quantity_kg, price_per_kg,
-- total_price), with no WITH CHECK restricting which columns or which
-- status transitions were valid — bypassing every safeguard built into
-- cancel_order()/complete_order() (admin-only check, stock reconciliation,
-- buyer notification).
--
-- Confirmed before removal, not assumed:
--   - No FarmerOrderRepository exists, and no Farmer screen references
--     `orders` (checked against the full Farmer screen list).
--   - admin_order_repository.dart confirms every real status transition
--     (approve/cancel/complete) is performed by Admin, never by a farmer.
--   - "Farmers see own orders" (SELECT) already covers the only legitimate
--     farmer need — visibility into orders against their own listings.
--   - information.md confirms the real cooperative workflow: SP3 admin
--     manages all commercial transactions; farmers harvest and deliver,
--     they do not manage order status themselves.
--
-- This removes ONLY the UPDATE policy. The SELECT policy
-- ("Farmers see own orders") is untouched — farmers keep full read
-- visibility into their own orders, exactly as before.
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Farmers update order status" ON public.orders;

NOTIFY pgrst, 'reload schema';