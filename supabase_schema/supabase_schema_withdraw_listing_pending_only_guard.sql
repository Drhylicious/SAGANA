-- ============================================================
-- SAGANA — Withdraw Listing: Pending-Review-Only Guard
--
-- withdraw_listing() previously allowed withdrawal from 'pending_review'
-- OR 'approved' (plus the retired 'changes_required', already inert
-- since that status can no longer occur — see
-- supabase_schema_remove_changes_required.sql). Per explicit product
-- direction: once a listing is approved and live on the Marketplace,
-- buyers may already be viewing it, have it in their cart, or have a
-- pending order against it — allowing the farmer to pull it out from
-- under an in-progress purchase risks exactly the kind of inconsistency
-- this codebase's reservation model was built to prevent everywhere
-- else. A live listing's only farmer-initiated ways out are now: let it
-- sell, or contact the cooperative — there's no self-service withdrawal
-- once buyers can see it.
--
-- Matches the same guard-tightening pattern already applied elsewhere in
-- this module (supabase_schema_cancel_order_pending_only_guard.sql,
-- supabase_schema_reject_listing_guard.sql): defense in depth — the
-- client-side "Withdraw Listing" button is being removed from the Live
-- state in the same pass, but the RPC guard is the authoritative one,
-- unbypassable regardless of what calls this function directly.
--
-- Every other line preserved exactly from the current canonical version
-- (supabase_schema_marketplace_order_reservation_fix.sql) — only the
-- status guard changes.
-- ============================================================

CREATE OR REPLACE FUNCTION withdraw_listing(p_listing_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing RECORD;
BEGIN
  SELECT * INTO v_listing FROM marketplace_listings
    WHERE id = p_listing_id AND farmer_id = auth.uid() FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_listing.status != 'pending_review' THEN
    RAISE EXCEPTION 'This listing cannot be withdrawn (status: %)', v_listing.status;
  END IF;

  IF v_listing.inventory_batch_id IS NOT NULL AND v_listing.remaining_kg > 0 THEN
    PERFORM _release_batch_reservation(v_listing.inventory_batch_id, v_listing.remaining_kg);
  END IF;

  UPDATE marketplace_listings SET status = 'withdrawn', remaining_kg = 0 WHERE id = p_listing_id;
END;
$$;

GRANT EXECUTE ON FUNCTION withdraw_listing TO authenticated;

NOTIFY pgrst, 'reload schema';
