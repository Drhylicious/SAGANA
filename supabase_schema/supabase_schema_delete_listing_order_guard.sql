-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_delete_listing_order_guard.sql
-- Run after supabase_schema_delete_listing.sql
--
-- Buyer module review, finding 1.1 (Confirmed bug — resolved per approved
-- Option A: block deletion if any orders reference the listing).
--
-- delete_listing() previously only checked status = 'withdrawn' before
-- deleting the marketplace_listings row. orders.listing_id references
-- marketplace_listings(id) ON DELETE CASCADE — so a withdrawn listing that
-- still had order history (e.g. one cancelled order, which is a normal,
-- legitimate state — an admin can cancel an order and a farmer can then
-- withdraw the listing) was silently deletable, permanently destroying the
-- buyer's order row along with it.
--
-- This version adds a second guard: if ANY orders row references this
-- listing, regardless of status (pending/approved/completed/cancelled),
-- deletion is blocked with a specific, actionable error message. This does
-- not change the existing 'withdrawn' status guard — both checks now apply.
--
-- No schema change. orders.listing_id keeps its existing
-- ON DELETE CASCADE — it is now simply never reached for a listing that
-- has any order history, because the RPC refuses to run the DELETE.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.delete_listing(p_listing_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing    RECORD;
  v_order_count INTEGER;
BEGIN
  SELECT * INTO v_listing FROM marketplace_listings
    WHERE id = p_listing_id AND farmer_id = auth.uid() FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_listing.status != 'withdrawn' THEN
    RAISE EXCEPTION 'This listing must be withdrawn before it can be deleted (status: %)', v_listing.status;
  END IF;

  SELECT COUNT(*) INTO v_order_count
    FROM orders WHERE listing_id = p_listing_id;

  IF v_order_count > 0 THEN
    RAISE EXCEPTION 'This listing has % order(s) on record and cannot be deleted. Order history is preserved for buyers even after a listing is withdrawn.', v_order_count;
  END IF;

  DELETE FROM marketplace_listings WHERE id = p_listing_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_listing(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
