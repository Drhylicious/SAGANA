-- ============================================================
-- SAGANA — Withdraw Listing Inventory Release
-- Same gap as reject_listing: withdrawing never released the
-- batch reservation. Also adds a status guard — a listing that's
-- already sold, rejected, or withdrawn shouldn't be withdrawable.
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
  IF v_listing.status NOT IN ('pending_review', 'changes_required', 'approved') THEN
    RAISE EXCEPTION 'This listing cannot be withdrawn (status: %)', v_listing.status;
  END IF;

  IF v_listing.inventory_batch_id IS NOT NULL THEN
    PERFORM _release_batch_reservation(v_listing.inventory_batch_id, v_listing.volume_kg);
  END IF;

  UPDATE marketplace_listings SET status = 'withdrawn' WHERE id = p_listing_id;
END;
$$;

GRANT EXECUTE ON FUNCTION withdraw_listing TO authenticated;

NOTIFY pgrst, 'reload schema';