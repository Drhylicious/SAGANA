-- ============================================================
-- SAGANA — Allow 'rejected' and 'sold' on marketplace_listings.status
-- reject_listing and complete_order (see
-- supabase_schema_marketplace_order_reservation_fix.sql) have always
-- set these two values, but the original CHECK constraint from
-- supabase_schema_marketplace.sql never included them — every
-- rejection failed outright, and completing the order that exhausts
-- a listing's stock rolled back the whole transaction.
-- ============================================================

ALTER TABLE public.marketplace_listings
  DROP CONSTRAINT IF EXISTS marketplace_listings_status_check;

ALTER TABLE public.marketplace_listings
  ADD CONSTRAINT marketplace_listings_status_check
  CHECK (status IN ('pending_review', 'approved', 'changes_required', 'withdrawn', 'rejected', 'sold'));

NOTIFY pgrst, 'reload schema';
