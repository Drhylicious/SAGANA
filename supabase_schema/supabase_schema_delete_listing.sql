-- ============================================================
-- SAGANA — Safe Listing Deletion
-- deleteListing() was a plain client-side DELETE with no status
-- guard and no reservation release. A changes_required listing
-- still holds a live batch reservation (by design — see
-- requestChanges()'s own comment) — deleting it directly left
-- that reservation permanently locked with no listing left to
-- withdraw. Only a 'withdrawn' listing (reservation already
-- released by withdraw_listing) is safe to delete.
-- ============================================================

CREATE OR REPLACE FUNCTION public.delete_listing(p_listing_id UUID)
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

  IF v_listing.status != 'withdrawn' THEN
    RAISE EXCEPTION 'This listing must be withdrawn before it can be deleted (status: %)', v_listing.status;
  END IF;

  DELETE FROM marketplace_listings WHERE id = p_listing_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_listing(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
